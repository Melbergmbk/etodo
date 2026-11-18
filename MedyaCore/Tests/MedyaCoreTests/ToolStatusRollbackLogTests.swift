import Testing
import Foundation
import CryptoKit
@testable import MedyaCore

@Suite struct ToolStatusRollbackLogTests {
    static let api = "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"

    func tempRoot() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("mi-srl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    func sha(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    func publish(_ f: FakeFetcher, _ version: String) {
        let bin = Data("binary-\(version)".utf8)
        f.set(Self.api, """
        {"tag_name":"\(version)","assets":[
         {"name":"yt-dlp_macos","browser_download_url":"https://dl.test/\(version)/yt-dlp_macos"},
         {"name":"SHA2-256SUMS","browser_download_url":"https://dl.test/\(version)/SHA2-256SUMS"}]}
        """)
        f.set("https://dl.test/\(version)/yt-dlp_macos", bin)
        f.set("https://dl.test/\(version)/SHA2-256SUMS", "\(sha(bin))  yt-dlp_macos\n")
    }

    func runner() -> FakeRunner {
        FakeRunner([.init(matches: { u, a in u.lastPathComponent == "yt-dlp" && a == ["--version"] },
                          result: ProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""))])
    }

    func manager(_ root: URL, _ f: FakeFetcher) -> ToolManager {
        ToolManager(root: root, fetcher: f, runner: runner(), arch: "arm64")
    }

    func current(_ root: URL) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: root.appendingPathComponent("tools/ytdlp/current").path)
    }

    // MARK: ToolStatus.source / verified

    @Test func statusReportsSourceAndVerified() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        publish(f, "v1")
        let m = manager(root, f)
        _ = await m.updateAll()
        let all = await m.status()
        let yt = try #require(all.first { $0.kind == .ytdlp })
        #expect(yt.verified)
        #expect(yt.source == "github.com/yt-dlp")
        let deno = try #require(all.first { $0.kind == .deno })
        #expect(!deno.verified)
        #expect(deno.source == "github.com/denoland")
        #expect(all.first { $0.kind == .ffmpeg }?.source == "ffmpeg.martin-riedl.de")
        #expect(all.first { $0.kind == .python }?.source == "github.com/astral-sh")
        #expect(all.first { $0.kind == .galleryDL }?.source == "PyPI (pip)")
    }

    @Test func installWithoutVerificationRecordIsNotVerified() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let dir = root.appendingPathComponent("tools/ytdlp/old")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exe = dir.appendingPathComponent("yt-dlp")
        try Data("x".utf8).write(to: exe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("tools/ytdlp/current").path, withDestinationPath: "old")
        let st = await manager(root, f).status().first { $0.kind == .ytdlp }
        #expect(st?.isReady == true)
        #expect(st?.verified == false)
    }

    // MARK: Geri dönme

    @Test func rollbackReturnsToPreviousVersion() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let m = manager(root, f)
        publish(f, "v1"); _ = await m.updateAll()
        publish(f, "v2"); _ = await m.updateAll()
        #expect(current(root) == "v2")
        try await m.rollback(.ytdlp)
        #expect(current(root) == "v1")
        let st = await m.status().first { $0.kind == .ytdlp }
        #expect(st?.installedVersion == "v1")
        #expect(st?.verified == true)
        // Yeni sürüm de saklanır: tekrar ileri dönülebilir.
        try await m.rollback(.ytdlp)
        #expect(current(root) == "v2")
    }

    @Test func rollbackWithoutPreviousVersionFails() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let m = manager(root, f)
        publish(f, "v1"); _ = await m.updateAll()
        do {
            try await m.rollback(.ytdlp)
            Issue.record("hata bekleniyordu")
        } catch {
            #expect(error == .noPreviousVersion)
            #expect(!error.message.isEmpty)
        }
        #expect(current(root) == "v1")
    }

    @Test func rollbackWaitsForActiveDownload() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let m = manager(root, f)
        publish(f, "v1"); _ = await m.updateAll()
        publish(f, "v2"); _ = await m.updateAll()
        await m.beginDownload()
        let task = Task { try await m.rollback(.ytdlp) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(current(root) == "v2")
        await m.endDownload()
        try await task.value
        #expect(current(root) == "v1")
    }

    // MARK: İşlem kaydı

    @Test func logKeepsEntriesAndPersists() async throws {
        let root = try tempRoot()
        let file = root.appendingPathComponent("activity.json")
        let log = ActivityLog(file: file)
        await log.append("bir")
        await log.append("iki")
        #expect(await log.entries().map(\.message) == ["bir", "iki"])
        let reopened = ActivityLog(file: file)
        #expect(await reopened.entries().map(\.message) == ["bir", "iki"])
    }

    @Test func logKeepsOnlyLast50() async throws {
        let root = try tempRoot()
        let log = ActivityLog(file: root.appendingPathComponent("activity.json"))
        for i in 1...60 { await log.append("kayıt \(i)") }
        let entries = await log.entries()
        #expect(entries.count == 50)
        #expect(entries.first?.message == "kayıt 11")
        #expect(entries.last?.message == "kayıt 60")
    }

    @Test func corruptLogFileStartsEmpty() async throws {
        let root = try tempRoot()
        let file = root.appendingPathComponent("activity.json")
        try Data("bozuk".utf8).write(to: file)
        let log = ActivityLog(file: file)
        #expect(await log.entries().isEmpty)
        await log.append("yeni")
        #expect(await log.entries().map(\.message) == ["yeni"])
    }

    @Test func managerLogsInstallUpdateAndRollback() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let m = manager(root, f)
        publish(f, "v1"); _ = await m.updateAll()
        publish(f, "v2"); _ = await m.updateAll()
        try await m.rollback(.ytdlp)
        let messages = await m.log.entries().map(\.message)
        #expect(messages.contains("yt-dlp v1 kuruldu (doğrulandı)"))
        #expect(messages.contains("yt-dlp v1 → v2 (doğrulandı, eski sürüm saklandı)"))
        #expect(messages.contains("yt-dlp önceki sürüme döndü: v2 → v1"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("activity.json").path))
    }

    @Test func managerLogsUpToDateCheck() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let m = manager(root, f)
        publish(f, "v1"); _ = await m.updateAll()
        _ = await m.updateAll()
        let last = await m.log.entries().last?.message
        #expect(last?.hasPrefix("Güncelleme kontrolü") == true)
    }

    // MARK: Son kontrol zamanı

    @Test func lastCheckRecordedOnlyWhenOnline() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        f.failure = URLError(.notConnectedToInternet)
        let m = manager(root, f)
        _ = await m.updateAll()
        #expect(await m.lastCheck() == nil)
        f.failure = nil
        publish(f, "v1")
        _ = await m.updateAll()
        let last = try #require(await m.lastCheck())
        #expect(abs(last.timeIntervalSinceNow) < 60)
        // Kalıcı
        #expect(await manager(root, f).lastCheck() != nil)
    }

    // MARK: gallery-dl geri dönme (pip ile önceki sürüm)

    /// pip'le kurulan sürümü hatırlayıp `gallery_dl --version`'da onu söyler; `latest` PyPI'daki en yeni sürüm.
    final class PipRunner: ProcessRunning, @unchecked Sendable {
        private let lock = NSLock()
        private var version: String
        private var _latest = "2.0.0"
        private var _offline = false
        init(_ v: String) { version = v }
        var latest: String { get { lock.withLock { _latest } } set { lock.withLock { _latest = newValue } } }
        var offline: Bool { get { lock.withLock { _offline } } set { lock.withLock { _offline = newValue } } }
        func run(_ executable: URL, _ arguments: [String], environment: [String: String],
                 onLine: @escaping @Sendable (String) -> Void) async throws -> ProcessResult {
            lock.withLock {
                if arguments.contains("pip") {
                    if _offline {
                        return ProcessResult(exitCode: 1, stdout: "", stderr: """
                        WARNING: Retrying (Retry(total=4, connect=None, read=None, redirect=None, status=None)) after connection broken by 'NewConnectionError('<pip._vendor.urllib3.connection.HTTPSConnection object>: Failed to establish a new connection: [Errno 8] nodename nor servname provided, or not known')': /simple/gallery-dl/
                        ERROR: Could not find a version that satisfies the requirement gallery-dl==1.0.0 (from versions: none)
                        """)
                    }
                    if let spec = arguments.first(where: { $0.hasPrefix("gallery-dl==") }) {
                        version = String(spec.dropFirst("gallery-dl==".count))
                    } else if arguments.contains("--upgrade") {
                        let excluded = arguments.first(where: { $0.hasPrefix("gallery-dl!=") }).map { String($0.dropFirst("gallery-dl!=".count)) }
                        if excluded != _latest { version = _latest }
                    }
                    return ProcessResult(exitCode: 0, stdout: "", stderr: "")
                }
                return ProcessResult(exitCode: 0, stdout: arguments.contains("gallery_dl") ? "\(version)\n" : "", stderr: "")
            }
        }
    }

    func fakePython(_ root: URL, _ v: String) throws {
        let bin = root.appendingPathComponent("tools/python/\(v)/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let py = bin.appendingPathComponent("python3")
        try Data("x".utf8).write(to: py)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: py.path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("tools/python/current").path, withDestinationPath: v)
    }

    @Test func galleryDLRollbackReinstallsPreviousVersion() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try fakePython(root, "3.12.1")
        let m = ToolManager(root: root, fetcher: f, runner: PipRunner("1.0.0"), arch: "arm64")
        _ = await m.updateAll()
        var g = await m.status().first { $0.kind == .galleryDL }
        #expect(g?.installedVersion == "2.0.0")
        #expect(g?.verified == true)
        try await m.rollback(.galleryDL)
        g = await m.status().first { $0.kind == .galleryDL }
        #expect(g?.installedVersion == "1.0.0")
        #expect(g?.isReady == true)
        #expect(await m.log.entries().map(\.message).contains("gallery-dl önceki sürüme döndü: 2.0.0 → 1.0.0"))
    }

    @Test func galleryDLRollbackWithoutPreviousFails() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try fakePython(root, "3.12.1")
        let m = ToolManager(root: root, fetcher: f, runner: PipRunner("2.0.0"), arch: "arm64")
        _ = await m.updateAll()
        do { try await m.rollback(.galleryDL); Issue.record("hata bekleniyordu") }
        catch { #expect(error == .noPreviousVersion) }
    }

    // MARK: Geri dönme kalıcılığı (atlanan sürüm)

    @Test func rollbackIsNotUndoneByNextUpdate() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let m = manager(root, f)
        publish(f, "v1"); _ = await m.updateAll()
        publish(f, "v2"); _ = await m.updateAll()
        try await m.rollback(.ytdlp)
        #expect(!(await m.updateAll().contains(.ytdlp)))
        #expect(current(root) == "v1")
        // Uygulama yeniden açıldı
        let again = manager(root, f)
        #expect(!(await again.updateAll().contains(.ytdlp)))
        #expect(current(root) == "v1")
    }

    @Test func newerVersionAfterRollbackIsInstalled() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let m = manager(root, f)
        publish(f, "v1"); _ = await m.updateAll()
        publish(f, "v2"); _ = await m.updateAll()
        try await m.rollback(.ytdlp)
        publish(f, "v3")
        #expect(await m.updateAll().contains(.ytdlp))
        #expect(current(root) == "v3")
        // Atlama kaldırıldı: v2 yeniden yayımlanırsa (ör. geri çekilen sürüm) kurulabilir.
        publish(f, "v2")
        #expect(await m.updateAll().contains(.ytdlp))
        #expect(current(root) == "v2")
    }

    @Test func galleryDLRollbackIsNotUndoneByNextUpdate() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try fakePython(root, "3.12.1")
        let r = PipRunner("1.0.0")
        let m = ToolManager(root: root, fetcher: f, runner: r, arch: "arm64")
        _ = await m.updateAll()
        try await m.rollback(.galleryDL)
        #expect(!(await m.updateAll().contains(.galleryDL)))
        #expect(await m.status().first { $0.kind == .galleryDL }?.installedVersion == "1.0.0")
        r.latest = "3.0.0"
        #expect(await m.updateAll().contains(.galleryDL))
        #expect(await m.status().first { $0.kind == .galleryDL }?.installedVersion == "3.0.0")
    }

    @Test func galleryDLRollbackOfflineIsNoInternet() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try fakePython(root, "3.12.1")
        let r = PipRunner("1.0.0")
        let m = ToolManager(root: root, fetcher: f, runner: r, arch: "arm64")
        _ = await m.updateAll()
        r.offline = true
        do { try await m.rollback(.galleryDL); Issue.record("hata bekleniyordu") }
        catch { #expect(error == .noInternet) }
        #expect(await m.status().first { $0.kind == .galleryDL }?.installedVersion == "2.0.0")
    }

    @Test func pipNetworkErrorsAreRecognized() {
        #expect(ToolManager.pipLooksOffline("ERROR: ... Failed to establish a new connection: [Errno 8] nodename nor servname provided"))
        #expect(ToolManager.pipLooksOffline("Temporary failure in name resolution"))
        #expect(ToolManager.pipLooksOffline("ReadTimeoutError: HTTPSConnectionPool(host='pypi.org', port=443): Read timed out."))
        #expect(!ToolManager.pipLooksOffline("ERROR: No matching distribution found for gallery-dl==9.9.9"))
    }

    // MARK: hasPrevious

    @Test func statusReportsWhetherPreviousVersionIsKept() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        let m = manager(root, f)
        publish(f, "v1"); _ = await m.updateAll()
        #expect(await m.status().first { $0.kind == .ytdlp }?.hasPrevious == false)
        publish(f, "v2"); _ = await m.updateAll()
        #expect(await m.status().first { $0.kind == .ytdlp }?.hasPrevious == true)
    }

    @Test func galleryDLHasPreviousAfterUpgrade() async throws {
        let root = try tempRoot(), f = FakeFetcher()
        try fakePython(root, "3.12.1")
        let m = ToolManager(root: root, fetcher: f, runner: PipRunner("2.0.0"), arch: "arm64")
        _ = await m.updateAll()
        #expect(await m.status().first { $0.kind == .galleryDL }?.hasPrevious == false)
        let m2 = ToolManager(root: root, fetcher: f, runner: PipRunner("1.0.0"), arch: "arm64")
        _ = await m2.updateAll()
        #expect(await m2.status().first { $0.kind == .galleryDL }?.hasPrevious == true)
    }

    // MARK: Kontrol özeti yalnız değişiklik ya da hata olunca

    @Test func quietCheckWritesNoLogLine() {
        #expect(ToolManager.checkSummary(updated: [], failed: [], offline: false) == nil)
        #expect(ToolManager.checkSummary(updated: [.ytdlp], failed: [], offline: false) == "Güncelleme kontrolü — 1 araç güncellendi")
        #expect(ToolManager.checkSummary(updated: [], failed: [.deno], offline: false) == "Güncelleme kontrolü — deno güncellenemedi, eski sürüm kullanılıyor")
        #expect(ToolManager.checkSummary(updated: [], failed: [.deno], offline: true) == "Güncelleme kontrolü yapılamadı (internet yok)")
    }
}
