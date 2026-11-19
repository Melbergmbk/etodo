import Testing
import Foundation
import CryptoKit
@testable import MedyaCore

/// tar/unzip gerçekten çalışır; diğer her şey (sağlık, pip, xattr, codesign) betikli.
final class HybridRunner: ProcessRunning, @unchecked Sendable {
    private let real = SystemProcessRunner()
    private let lock = NSLock()
    private var _calls: [(URL, [String])] = []
    let handler: @Sendable (URL, [String]) -> ProcessResult
    init(_ handler: @escaping @Sendable (URL, [String]) -> ProcessResult) { self.handler = handler }
    var calls: [(URL, [String])] { lock.withLock { _calls } }

    func run(_ executable: URL, _ arguments: [String], environment: [String: String],
             onLine: @escaping @Sendable (String) -> Void) async throws -> ProcessResult {
        lock.withLock { _calls.append((executable, arguments)) }
        if ["tar", "unzip"].contains(executable.lastPathComponent) {
            return try await real.run(executable, arguments, environment: environment, onLine: onLine)
        }
        return handler(executable, arguments)
    }
}

/// pip yükseltmesi kapı açılana kadar bekler.
final class GateRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _started = false
    private var cont: CheckedContinuation<Void, Never>?
    private var opened = false
    var started: Bool { lock.withLock { _started } }

    func open() { lock.withLock { opened = true; let c = cont; cont = nil; return c }?.resume() }

    func run(_ executable: URL, _ arguments: [String], environment: [String: String],
             onLine: @escaping @Sendable (String) -> Void) async throws -> ProcessResult {
        if arguments.contains("--upgrade") {
            lock.withLock { _started = true }
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in if opened { return true }; cont = c; return false }
                if resumeNow { c.resume() }
            }
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        if arguments.contains("gallery_dl") { return ProcessResult(exitCode: 0, stdout: "1.0.0\n", stderr: "") }
        return ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock(); private var v = false
    func set() { lock.withLock { v = true } }
    var isSet: Bool { lock.withLock { v } }
}

@Suite struct ToolManagerHardeningTests {
    static let pyApi = "https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest"
    static let denoApi = "https://api.github.com/repos/denoland/deno/releases/latest"

    func tempRoot() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("mi-h-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }
    @discardableResult func sh(_ exe: String, _ args: [String], cwd: URL) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args; p.currentDirectoryURL = cwd
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit(); return p.terminationStatus
    }
    func manager(_ root: URL, _ f: FakeFetcher, _ r: ProcessRunning) -> ToolManager {
        ToolManager(root: root, fetcher: f, runner: r, arch: "arm64")
    }
    func dirs(_ root: URL, _ kind: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("tools/\(kind)").path)) ?? [])
            .filter { $0 != "current" && !$0.hasPrefix(".") }.sorted()
    }
    func current(_ root: URL, _ kind: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("tools/\(kind)/current").path)
    }


    func publishPython(_ f: FakeFetcher, version: String) throws {
        let work = try tempRoot()
        try FileManager.default.createDirectory(at: work.appendingPathComponent("python/bin"), withIntermediateDirectories: true)
        try Data("py".utf8).write(to: work.appendingPathComponent("python/bin/python3"))
        try sh("/usr/bin/tar", ["-czf", "py.tar.gz", "python"], cwd: work)
        let data = try Data(contentsOf: work.appendingPathComponent("py.tar.gz"))
        let name = "cpython-\(version)-aarch64-apple-darwin-install_only.tar.gz"
        f.set(Self.pyApi, """
        {"tag_name":"t","assets":[
         {"name":"\(name)","browser_download_url":"https://dl.test/py/\(version)/\(name)"},
         {"name":"SHA256SUMS","browser_download_url":"https://dl.test/py/\(version)/SHA256SUMS"}]}
        """)
        f.set("https://dl.test/py/\(version)/\(name)", data)
        f.set("https://dl.test/py/\(version)/SHA256SUMS", "\(sha(data))  \(name)\n")
    }
    func pyRunner(failPipIn: String? = nil) -> HybridRunner {
        HybridRunner { u, a in
            if a.contains("pip"), let bad = failPipIn, u.path.contains(bad) { return ProcessResult(exitCode: 1, stdout: "", stderr: "pip fail") }
            if a.contains("gallery_dl") { return ProcessResult(exitCode: 0, stdout: "1.0.0\n", stderr: "") }
            return ProcessResult(exitCode: 0, stdout: "ok\n", stderr: "")
        }
    }
    let v1 = "3.12.1+20260101", v2 = "3.12.2+20260102"

    // C1
    @Test func pythonUpdateWithFailingPipKeepsOldPythonAndGalleryDL() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try publishPython(f, version: v1)
        let m = manager(root, f, pyRunner(failPipIn: "3.12.2"))
        #expect(await m.updateAll().contains(.python))
        try publishPython(f, version: v2)
        #expect(!(await m.updateAll().contains(.python)))
        #expect(current(root, "python") == v1)
        #expect(dirs(root, "python") == [v1])
        let g = await m.status().first { $0.kind == .galleryDL }
        #expect(g?.isReady == true)
    }

    @Test func pythonUpdateInstallsGalleryDLIntoNewPython() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try publishPython(f, version: v1)
        let r = pyRunner()
        let m = manager(root, f, r)
        _ = await m.updateAll()
        try publishPython(f, version: v2)
        #expect(await m.updateAll().contains(.python))
        #expect(current(root, "python") == v2)
        let pip = r.calls.last { $0.0.path.contains(v2) && $0.1.contains("pip") }
        #expect(pip?.1.contains("gallery-dl==1.0.0") == true)
        #expect(r.calls.contains { $0.0.path.contains(v2) && $0.1.contains("yt-dlp[default,curl-cffi]==ok") })
        #expect(await m.status().first { $0.kind == .ytdlp }?.isReady == true)
        #expect(pip?.1.contains("-I") == true)
        let g = await m.status().first { $0.kind == .galleryDL }
        #expect(g?.isReady == true)
        #expect(g?.installedVersion == "1.0.0")
    }

    @Test func galleryDLNotReadyWhenPythonChangedUnderneath() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try publishPython(f, version: v1)
        let m = manager(root, f, pyRunner())
        _ = await m.updateAll()
        let link = root.appendingPathComponent("tools/python/current")
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "other")
        let g = await m.status().first { $0.kind == .galleryDL }
        #expect(g?.isReady == false)
    }

    // I2
    @Test func beginDownloadWaitsWhileSwapInProgress() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let py = root.appendingPathComponent("tools/python/current/bin/python3")
        try FileManager.default.createDirectory(at: py.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: py)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: py.path)
        let gate = GateRunner()
        let m = manager(root, f, gate)
        let upd = Task { await m.updateAll() }
        for _ in 0..<200 where !gate.started { try await Task.sleep(for: .milliseconds(10)) }
        #expect(gate.started)
        let began = Flag()
        let b = Task { await m.beginDownload(); began.set() }
        try await Task.sleep(for: .milliseconds(150))
        #expect(!began.isSet)
        gate.open()
        _ = await upd.value
        await b.value
        #expect(began.isSet)
    }

    @Test func downloadStartingRightAfterEndPreventsSwap() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        DenoRelease.publish(f, version: "v1")
        let m = manager(root, f, DenoRelease.runner())
        _ = await m.updateAll()
        DenoRelease.publish(f, version: "v2")
        await m.beginDownload()
        let task = Task { await m.updateAll() }
        for _ in 0..<100 where !f.requested.contains(URL(string: DenoRelease.url("v2"))!) {
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(100))
        await m.endDownloadThenBeginForTest()
        try await Task.sleep(for: .milliseconds(150))
        #expect(current(root, "deno") == "v1")
        await m.endDownload()
        #expect(await task.value.contains(.deno))
        #expect(current(root, "deno") == "v2")
    }

    // I3
    @Test func concurrentUpdateAllRunsOnce() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        DenoRelease.publish(f, version: "v1")
        let m = manager(root, f, DenoRelease.runner())
        async let a = m.updateAll()
        async let b = m.updateAll()
        _ = await (a, b)
        #expect(f.requested.filter { $0.absoluteString == DenoRelease.api }.count == 1)
    }

    // I4
    @Test(arguments: ["..", "a/b", "current", ".", ".hidden"])
    func unsafeVersionIsRejected(_ tag: String) async throws {
        let f = FakeFetcher()
        f.set(DenoRelease.api, """
        {"tag_name":"\(tag)","assets":[
         {"name":"deno-aarch64-apple-darwin.zip","browser_download_url":"https://dl.test/x/deno.zip"},
         {"name":"deno-aarch64-apple-darwin.zip.sha256sum","browser_download_url":"https://dl.test/x/deno.zip.sha256sum"}]}
        """)
        await #expect(throws: ToolError.self) { _ = try await ToolKind.deno.resolve(arch: "arm64", fetcher: f) }
    }

    @Test func ffmpegForeignHostIsRejected() async throws {
        let f = FakeFetcher()
        f.redirect("https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip",
                   to: "https://evil.example.com/download/macos/arm64/123_9.0/ffmpeg.zip")
        await #expect(throws: ToolError.self) { _ = try await ToolKind.ffmpeg.resolve(arch: "arm64", fetcher: f) }
    }

    @Test func unsafeVersionMapsToNeedsToolUpdate() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        // Python ve pip araçları kurulur; sıradaki ffmpeg yabancı adrese yönlenir.
        try publishPython(f, version: v1)
        f.redirect("https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip",
                   to: "https://evil.example.com/download/macos/arm64/123_9.0/ffmpeg.zip")
        let m = manager(root, f, pyRunner())
        do { try await m.installMissing { _, _ in }; Issue.record("hata bekleniyordu") }
        catch { #expect(error == .needsToolUpdate) }
    }

    // I5
    func publishDeno(_ f: FakeFetcher, links: [(String, String)]) throws {
        let work = try tempRoot()
        try Data("deno".utf8).write(to: work.appendingPathComponent("deno"))
        for (name, target) in links { try FileManager.default.createSymbolicLink(atPath: work.appendingPathComponent(name).path, withDestinationPath: target) }
        try sh("/usr/bin/zip", ["-yqr", "d.zip", "."], cwd: work)
        let data = try Data(contentsOf: work.appendingPathComponent("d.zip"))
        f.set(Self.denoApi, """
        {"tag_name":"v9.9.9","assets":[
         {"name":"deno-aarch64-apple-darwin.zip","browser_download_url":"https://dl.test/deno.zip"},
         {"name":"deno-aarch64-apple-darwin.zip.sha256sum","browser_download_url":"https://dl.test/deno.zip.sha256sum"}]}
        """)
        f.set("https://dl.test/deno.zip", data)
        f.set("https://dl.test/deno.zip.sha256sum", "\(sha(data))  deno-aarch64-apple-darwin.zip\n")
    }

    @Test func escapingSymlinkInArchiveIsRejected() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try publishDeno(f, links: [("evil", "../../../../etc"), ("abs", "/etc")])
        let m = manager(root, f, pyRunner())
        #expect(!(await m.updateAll().contains(.deno)))
        #expect(dirs(root, "deno").isEmpty)
    }

    @Test func internalSymlinkInArchiveIsAccepted() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try publishDeno(f, links: [("alias", "deno")])
        let m = manager(root, f, pyRunner())
        #expect(await m.updateAll().contains(.deno))
        #expect(current(root, "deno") == "v9.9.9")
    }

    // I6
    @Test func rollingBackToKeptPreviousVersionSurvives() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let m = manager(root, f, DenoRelease.runner())
        DenoRelease.publish(f, version: "v1"); _ = await m.updateAll()
        DenoRelease.publish(f, version: "v2"); _ = await m.updateAll()
        let marker = root.appendingPathComponent("tools/deno/v1/marker")
        try Data("m".utf8).write(to: marker)
        DenoRelease.publish(f, version: "v1")
        #expect(await m.updateAll().contains(.deno))
        #expect(current(root, "deno") == "v1")
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(dirs(root, "deno") == ["v1", "v2"])
    }

    // gallery-dl geri alma: sarmalayıcı ve durum dosyası değişmez
    @Test func galleryDLRollbackLeavesWrapperAndStateUntouched() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let pyDir = root.appendingPathComponent("tools/python/\(v1)/bin")
        try FileManager.default.createDirectory(at: pyDir, withIntermediateDirectories: true)
        let py = pyDir.appendingPathComponent("python3")
        try Data("x".utf8).write(to: py)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: py.path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("tools/python/current").path, withDestinationPath: v1)
        let wrapper = root.appendingPathComponent("tools/bin/gallery-dl")
        try FileManager.default.createDirectory(at: wrapper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("SENTINEL".utf8).write(to: wrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let state = root.appendingPathComponent("tools/galleryDL/state")
        try FileManager.default.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("\(v1)\n1.0.0\n".utf8).write(to: state)
        let n = Counter()
        let r = HybridRunner { _, a in
            if a.contains("gallery_dl") { return n.next() == 1 ? ProcessResult(exitCode: 0, stdout: "1.0.0\n", stderr: "") : ProcessResult(exitCode: 1, stdout: "", stderr: "broken") }
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
        let m = manager(root, f, r)
        let updated = await m.updateAll()
        #expect(!updated.contains(.galleryDL))
        #expect(r.calls.contains { $0.1.contains("gallery-dl==1.0.0") })
        #expect(try String(contentsOf: wrapper, encoding: .utf8) == "SENTINEL")
        #expect(try String(contentsOf: state, encoding: .utf8) == "\(v1)\n1.0.0\n")
    }

    @Test func galleryDLWrapperIsIsolated() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try publishPython(f, version: v1)
        let m = manager(root, f, pyRunner())
        _ = await m.updateAll()
        let text = try String(contentsOf: await m.paths.galleryDL, encoding: .utf8)
        #expect(text.contains("-I -m gallery_dl"))
    }
}
