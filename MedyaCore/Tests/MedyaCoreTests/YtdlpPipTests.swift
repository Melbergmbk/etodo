import Testing
import Foundation
@testable import MedyaCore

/// pip'le kurulan paketlerin sürümünü hatırlar; `latest` PyPI'daki en yeni sürüm.
final class MultiPipRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var versions: [String: String] = [:]
    private var _latest: [String: String] = ["yt-dlp": "2026.11.01", "gallery-dl": "1.0.0"]
    private var _calls: [(URL, [String])] = []
    var calls: [(URL, [String])] { lock.withLock { _calls } }
    func setLatest(_ pkg: String, _ v: String) { lock.withLock { _latest[pkg] = v } }

    private static let modules = ["yt_dlp": "yt-dlp", "gallery_dl": "gallery-dl"]

    func run(_ executable: URL, _ arguments: [String], environment: [String: String],
             onLine: @escaping @Sendable (String) -> Void) async throws -> ProcessResult {
        lock.withLock {
            _calls.append((executable, arguments))
            if arguments.contains("pip"), let spec = arguments.last {
                let pkg = String(spec.prefix { $0 != "[" && $0 != "=" && $0 != "!" })
                if let r = spec.range(of: "==") {
                    versions[pkg] = String(spec[r.upperBound...])
                } else {
                    let excluded = spec.range(of: "!=").map { String(spec[$0.upperBound...]) }
                    if let latest = _latest[pkg], latest != excluded { versions[pkg] = latest }
                }
                return ProcessResult(exitCode: 0, stdout: "", stderr: "")
            }
            if let i = arguments.firstIndex(of: "-m"), i + 1 < arguments.count,
               let pkg = Self.modules[arguments[i + 1]], let v = versions[pkg] {
                return ProcessResult(exitCode: 0, stdout: "\(v)\n", stderr: "")
            }
            return ProcessResult(exitCode: 1, stdout: "", stderr: "yok")
        }
    }
}

@Suite struct YtdlpPipTests {
    func tempRoot() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("mi-yt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func fakePython(_ root: URL, _ v: String = "3.12.1") throws {
        let bin = root.appendingPathComponent("tools/python/\(v)/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let py = bin.appendingPathComponent("python3")
        try Data("x".utf8).write(to: py)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: py.path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("tools/python/current").path, withDestinationPath: v)
    }

    func yt(_ m: ToolManager) async -> ToolStatus? { await m.status().first { $0.kind == .ytdlp } }

    @Test func ytdlpIsInstalledThroughPipWithExtras() async throws {
        let root = try tempRoot(), r = MultiPipRunner()
        try fakePython(root)
        let m = ToolManager(root: root, fetcher: FakeFetcher(), runner: r, arch: "arm64")
        #expect(await m.updateAll().contains(.ytdlp))
        let st = await yt(m)
        #expect(st?.installedVersion == "2026.11.01")
        #expect(st?.isReady == true)
        #expect(st?.source == "PyPI (pip)")
        #expect(r.calls.contains { $0.1.contains("pip") && $0.1.contains("--upgrade") && $0.1.contains("yt-dlp[default,curl-cffi]") })
        let wrapper = await m.paths.ytdlp
        #expect(wrapper.path.hasSuffix("tools/bin/yt-dlp"))
        #expect(try String(contentsOf: wrapper, encoding: .utf8).contains("-I -m yt_dlp"))
        #expect(await m.log.entries().map(\.message).contains("yt-dlp 2026.11.01 kuruldu (sağlık kontrolü geçti)"))
    }

    @Test func oldSingleFileYtdlpIsRemovedAfterSwitch() async throws {
        let root = try tempRoot(), fm = FileManager.default
        try fakePython(root)
        let old = root.appendingPathComponent("tools/ytdlp/2026.10.26")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("bin".utf8).write(to: old.appendingPathComponent("yt-dlp"))
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("tools/ytdlp/current").path, withDestinationPath: "2026.10.26")
        let m = ToolManager(root: root, fetcher: FakeFetcher(), runner: MultiPipRunner(), arch: "arm64")
        // Eski kurulum, pip'e geçene kadar "hazır değil" sayılır (açılışta bir kez kurulur).
        #expect(await yt(m)?.isReady == false)
        #expect(await m.updateAll().contains(.ytdlp))
        #expect(try fm.contentsOfDirectory(atPath: root.appendingPathComponent("tools/ytdlp").path) == ["state"])
        #expect(await yt(m)?.isReady == true)
    }

    @Test func sameVersionIsNotReportedAsUpdate() async throws {
        let root = try tempRoot()
        try fakePython(root)
        let m = ToolManager(root: root, fetcher: FakeFetcher(), runner: MultiPipRunner(), arch: "arm64")
        _ = await m.updateAll()
        #expect(!(await m.updateAll().contains(.ytdlp)))
    }

    @Test func ytdlpRollbackAndSkip() async throws {
        let root = try tempRoot(), r = MultiPipRunner()
        try fakePython(root)
        let m = ToolManager(root: root, fetcher: FakeFetcher(), runner: r, arch: "arm64")
        _ = await m.updateAll()
        r.setLatest("yt-dlp", "2026.11.15")
        #expect(await m.updateAll().contains(.ytdlp))
        #expect(await yt(m)?.hasPrevious == true)
        try await m.rollback(.ytdlp)
        #expect(await yt(m)?.installedVersion == "2026.11.01")
        #expect(r.calls.contains { $0.1.contains("yt-dlp[default,curl-cffi]==2026.11.01") })
        // Geri dönülen sürüm yeniden kurulmaz; daha yenisi çıkınca kurulur.
        #expect(!(await m.updateAll().contains(.ytdlp)))
        r.setLatest("yt-dlp", "2026.12.01")
        #expect(await m.updateAll().contains(.ytdlp))
        #expect(await yt(m)?.installedVersion == "2026.12.01")
    }
}
