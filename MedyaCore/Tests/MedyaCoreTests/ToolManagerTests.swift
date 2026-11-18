import Testing
import Foundation
import CryptoKit
@testable import MedyaCore

final class FakeFetcher: HTTPFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [URL: Data] = [:]
    private var finals: [URL: URL] = [:]
    private var _requested: [URL] = []
    var failure: (any Error)?

    func set(_ url: String, _ data: Data) { lock.withLock { files[URL(string: url)!] = data } }
    func set(_ url: String, _ text: String) { set(url, Data(text.utf8)) }
    func redirect(_ from: String, to: String) { lock.withLock { finals[URL(string: from)!] = URL(string: to)! } }
    var requested: [URL] { lock.withLock { _requested } }

    private func get(_ url: URL) throws -> Data {
        try lock.withLock {
            _requested.append(url)
            if let failure { throw failure }
            guard let d = files[url] else { throw FetchError.badStatus(404) }
            return d
        }
    }
    func data(from: URL) async throws -> Data { try get(from) }
    func download(from: URL, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try get(from).write(to: to)
        progress(1)
    }
    func finalURL(of: URL) async throws -> URL { lock.withLock { finals[of] ?? of } }
}

@Suite struct ToolManagerTests {
    static let api = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"

    func tempRoot() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("mi-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    /// yt-dlp sürümü yayımlar: ikili + SHA2-256SUMS
    func publishYtdlp(_ f: FakeFetcher, version: String, content: String? = nil, sumOverride: String? = nil) {
        let bin = Data((content ?? "binary-\(version)").utf8)
        f.set(Self.api, """
        {"tag_name":"\(version)","assets":[
         {"name":"yt-dlp_macos","browser_download_url":"https://dl.test/\(version)/yt-dlp_macos"},
         {"name":"SHA2-256SUMS","browser_download_url":"https://dl.test/\(version)/SHA2-256SUMS"}]}
        """)
        f.set("https://dl.test/\(version)/yt-dlp_macos", bin)
        f.set("https://dl.test/\(version)/SHA2-256SUMS", "\(sumOverride ?? sha(bin))  yt-dlp_macos\n0000  yt-dlp.exe\n")
    }

    func runner(failingVersion: String? = nil) -> FakeRunner {
        FakeRunner([.init(matches: { u, a in
            u.lastPathComponent == "yt-dlp" && a == ["--version"] && !(failingVersion.map { u.path.contains("/\($0)/") } ?? false)
        }, result: ProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""))])
    }

    func manager(_ root: URL, _ f: FakeFetcher, _ r: FakeRunner) -> ToolManager {
        ToolManager(root: root, fetcher: f, runner: r, arch: "arm64")
    }

    @Test func removeLeftoversDeletesOnlyInterruptedInstallFolders() async throws {
        let root = try tempRoot(), fm = FileManager.default
        let tools = root.appendingPathComponent("tools")
        let keep = tools.appendingPathComponent("ytdlp/2026.10.26")
        for dir in [tools.appendingPathComponent(".staging-abc/out"), tools.appendingPathComponent("ytdlp/.current-xyz"), keep] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        await manager(root, FakeFetcher(), FakeRunner([])).removeLeftovers()
        #expect(!fm.fileExists(atPath: tools.appendingPathComponent(".staging-abc").path))
        #expect(!fm.fileExists(atPath: tools.appendingPathComponent("ytdlp/.current-xyz").path))
        #expect(fm.fileExists(atPath: keep.path))
    }

    func versionDirs(_ root: URL) -> [String] {
        let dir = root.appendingPathComponent("tools/ytdlp")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0 != "current" }.sorted()
    }
    func current(_ root: URL) -> String? {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("tools/ytdlp/current").path))
    }

    @Test func checksumMismatchInstallsNothing() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        publishYtdlp(f, version: "v1", sumOverride: String(repeating: "a", count: 64))
        let m = manager(root, f, runner())
        let updated = await m.updateAll()
        #expect(!updated.contains(.ytdlp))
        #expect(versionDirs(root).isEmpty)
        #expect(current(root) == nil)
    }

    @Test func checksumMismatchSurfacesAsError() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        publishYtdlp(f, version: "v1", sumOverride: String(repeating: "a", count: 64))
        let m = manager(root, f, runner())
        await #expect(throws: UserFacingError.self) { try await m.installMissing { _, _ in } }
    }

    @Test func failedHealthCheckKeepsOldVersion() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        publishYtdlp(f, version: "v1")
        let m = manager(root, f, runner(failingVersion: "v2"))
        #expect(await m.updateAll().contains(.ytdlp))
        #expect(current(root) == "v1")
        publishYtdlp(f, version: "v2")
        #expect(!(await m.updateAll().contains(.ytdlp)))
        #expect(current(root) == "v1")
        #expect(versionDirs(root) == ["v1"])
    }

    @Test func swapWaitsForActiveDownload() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        publishYtdlp(f, version: "v1")
        let m = manager(root, f, runner())
        _ = await m.updateAll()
        publishYtdlp(f, version: "v2")
        await m.beginDownload()
        let task = Task { await m.updateAll() }
        for _ in 0..<100 where !f.requested.contains(URL(string: "https://dl.test/v2/yt-dlp_macos")!) {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(150))
        #expect(current(root) == "v1")
        await m.endDownload()
        #expect(await task.value.contains(.ytdlp))
        #expect(current(root) == "v2")
    }

    @Test func onlyTwoVersionFoldersRemain() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let m = manager(root, f, runner())
        for v in ["v1", "v2", "v3"] {
            publishYtdlp(f, version: v)
            #expect(await m.updateAll().contains(.ytdlp))
        }
        #expect(versionDirs(root) == ["v2", "v3"])
        #expect(current(root) == "v3")
    }

    @Test func sameVersionIsNotReinstalled() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        publishYtdlp(f, version: "v1")
        let m = manager(root, f, runner())
        _ = await m.updateAll()
        #expect(!(await m.updateAll().contains(.ytdlp)))
    }

    @Test func networkFailureIsNoInternet() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        f.failure = URLError(.notConnectedToInternet)
        let m = manager(root, f, runner())
        do {
            try await m.installMissing { _, _ in }
            Issue.record("hata bekleniyordu")
        } catch {
            #expect(error == .noInternet)
        }
    }

    @Test func statusAndPathsAfterInstall() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        publishYtdlp(f, version: "v1")
        let m = manager(root, f, runner())
        _ = await m.updateAll()
        let st = await m.status().first { $0.kind == .ytdlp }
        #expect(st?.installedVersion == "v1")
        #expect(st?.isReady == true)
        let paths = await m.paths
        #expect(FileManager.default.isExecutableFile(atPath: paths.ytdlp.path))
        #expect(paths.galleryDL.path.hasSuffix("tools/bin/gallery-dl"))
    }

    @Test func ffmpegResolvesVersionFromRedirect() async throws {
        let f = FakeFetcher()
        f.redirect("https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip",
                   to: "https://ffmpeg.martin-riedl.de/download/macos/arm64/123_9.0/ffmpeg.zip")
        let spec = try await ToolKind.ffmpeg.resolve(arch: "arm64", fetcher: f)
        #expect(spec.version == "123_9.0")
        #expect(spec.artifacts.map(\.url.lastPathComponent) == ["ffmpeg.zip", "ffprobe.zip"])
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func next() -> Int { lock.withLock { n += 1; return n } }
}
