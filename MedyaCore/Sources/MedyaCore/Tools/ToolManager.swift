import Foundation

public actor ToolManager {
    private let installer: ToolInstaller
    /// Kurulum, güncelleme ve geri dönme kaydı; uygulama indirme bitişlerini de buraya yazar.
    public nonisolated let log: ActivityLog
    private let lastCheckFile: URL
    private let arch: String
    private var downloads = 0
    private var swapping = false
    private var working = false
    private var updateTask: Task<[ToolKind], Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// `arch`: `arm64` veya `x86_64`
    public init(root: URL, fetcher: HTTPFetching, runner: ProcessRunning, arch: String) {
        self.arch = arch
        self.installer = ToolInstaller(root: root, fetcher: fetcher, runner: runner)
        self.log = ActivityLog(file: root.appendingPathComponent("activity.json"))
        self.lastCheckFile = root.appendingPathComponent("last-check")
    }

    public static func currentArch() -> String {
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    private var tools: URL { installer.toolsDir }
    private var pythonExe: URL { tools.appendingPathComponent("python/current/bin/python3") }
    private var wrapper: URL { tools.appendingPathComponent("bin/gallery-dl") }
    private var galleryStateFile: URL { tools.appendingPathComponent("galleryDL/state") }

    public var paths: ToolPaths {
        ToolPaths(ytdlp: tools.appendingPathComponent("ytdlp/current/yt-dlp"),
                  galleryDL: wrapper,
                  ffmpegDir: tools.appendingPathComponent("ffmpeg/current"),
                  deno: tools.appendingPathComponent("deno/current/deno"))
    }

    // MARK: Durum

    /// gallery-dl durumu: kurulduğu Python sürümü + gallery-dl sürümü (+ geri dönülebilecek önceki gallery-dl sürümü).
    private func galleryState() -> (python: String, gallery: String, previous: String?)? {
        guard let text = try? String(contentsOf: galleryStateFile, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        return lines.count >= 2 ? (lines[0], lines[1], lines.count >= 3 ? lines[2] : nil) : nil
    }

    /// Önceki sürüm verilmezse: gallery-dl sürümü değiştiyse eskisi, değişmediyse kayıtlı önceki saklanır.
    private func writeGalleryState(python: String, gallery: String, previous: String? = nil) throws {
        let old = galleryState()
        let keep = previous ?? (old.map { $0.gallery != gallery ? $0.gallery : $0.previous } ?? nil)
        try FileManager.default.createDirectory(at: galleryStateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = "\(python)\n\(gallery)\n" + (keep.map { "\($0)\n" } ?? "")
        try text.write(to: galleryStateFile, atomically: true, encoding: .utf8)
    }

    /// Son başarılı (internete ulaşılan) güncelleme kontrolü.
    public func lastCheck() -> Date? {
        guard let text = try? String(contentsOf: lastCheckFile, encoding: .utf8) else { return nil }
        return try? Date(text.trimmingCharacters(in: .whitespacesAndNewlines), strategy: .iso8601)
    }

    public func status() -> [ToolStatus] {
        let fm = FileManager.default
        return ToolKind.allCases.map { kind in
            switch kind {
            case .galleryDL:
                let state = galleryState()
                let ready = fm.isExecutableFile(atPath: wrapper.path) && fm.isExecutableFile(atPath: pythonExe.path)
                    && state != nil && state?.python == installer.currentVersion(.python)
                // Durum dosyası yalnız sağlık kontrolü geçince yazılır.
                return ToolStatus(kind: kind, installedVersion: state?.gallery, isReady: ready, verified: ready,
                                  hasPrevious: ready && state?.previous != nil)
            default:
                let v = installer.currentVersion(kind)
                let ready = kind.executables.allSatisfy { fm.isExecutableFile(atPath: installer.currentLink(kind).appendingPathComponent($0).path) }
                let verified = v.map { installer.isVerified(kind, version: $0) } ?? false
                return ToolStatus(kind: kind, installedVersion: v, isReady: v != nil && ready, verified: v != nil && ready && verified,
                                  hasPrevious: v != nil && installer.keptVersion(kind) != nil)
            }
        }
    }

    // MARK: Eşzamanlılık: indirme sayacı, takas bayrağı, tek iş

    private func waitForChange() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    private func notifyChange() {
        let w = waiters
        waiters = []
        w.forEach { $0.resume() }
    }

    /// İndirme sürerken araç takası (güncelleme) bekletilir; takas sürerken yeni indirme başlamaz.
    public func beginDownload() async {
        while swapping { await waitForChange() }
        downloads += 1
    }

    public func endDownload() {
        downloads = max(0, downloads - 1)
        notifyChange()
    }

    /// Yalnızca testler için: sayaç 0'a inip hemen yeniden artar (bekleyenler uyandıktan sonra).
    func endDownloadThenBeginForTest() {
        endDownload()
        downloads += 1
    }

    /// Kontrol ve bayrak atamasının arasında `await` yoktur.
    private func acquireSwap() async {
        while downloads > 0 || swapping { await waitForChange() }
        swapping = true
    }

    private func releaseSwap() {
        swapping = false
        notifyChange()
    }

    private func acquireWork() async {
        while working { await waitForChange() }
        working = true
    }

    private func releaseWork() {
        working = false
        notifyChange()
    }

    // MARK: Kurulum ve güncelleme

    /// Yarıda kalmış kurulumların geçici klasörleri (~90 MB olabilir). Yalnız açılışta, başka iş yokken çağrılır.
    public func removeLeftovers() {
        let fm = FileManager.default
        let dirs = [tools] + ToolKind.allCases.map { tools.appendingPathComponent($0.rawValue) }
        for dir in dirs {
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            where name.hasPrefix(".staging-") || name.hasPrefix(".current-") {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    public func installMissing(progress: @escaping @Sendable (ToolKind, Double) -> Void) async throws(UserFacingError) {
        await acquireWork()
        defer { releaseWork() }
        let missing = Set(status().filter { !$0.isReady }.map(\.kind))
        for kind in ToolKind.allCases where missing.contains(kind) {
            do { _ = try await update(kind) { progress(kind, $0) } } catch { throw Self.userError(error) }
            progress(kind, 1)
        }
    }

    /// Güncellenen araçların listesi; aynı anda gelen çağrılar tek işi paylaşır.
    /// Tek tek hata veren araç atlanır (eski sürüm çalışmaya devam eder).
    public func updateAll() async -> [ToolKind] {
        if let t = updateTask { return await t.value }
        let t = Task { await self.runUpdateAll() }
        updateTask = t
        return await t.value
    }

    private func runUpdateAll() async -> [ToolKind] {
        await acquireWork()
        defer { releaseWork(); updateTask = nil }
        var updated: [ToolKind] = [], failed: [ToolKind] = []
        var offline = false
        for kind in ToolKind.allCases {
            do {
                if try await update(kind, progress: { _ in }) { updated.append(kind) }
            } catch {
                failed.append(kind)
                if Self.userError(error) == .noInternet { offline = true }
            }
        }
        if !offline {
            try? Date().formatted(.iso8601).write(to: lastCheckFile, atomically: true, encoding: .utf8)
        }
        if let summary = Self.checkSummary(updated: updated, failed: failed, offline: offline) {
            await log.append(summary)
        }
        return updated
    }

    private func update(_ kind: ToolKind, progress: @escaping @Sendable (Double) -> Void) async throws -> Bool {
        if kind == .galleryDL { return try await updateGalleryDL() }
        let spec = try await kind.resolve(arch: arch, fetcher: installer.fetcher)
        if spec.version == skippedVersion(kind), installer.currentVersion(kind) != nil { return false }
        let carried = Carried()
        var extra: (@Sendable (URL) async throws -> Void)?
        if kind == .python {
            extra = { @Sendable dir in carried.value = try await self.installGalleryDL(into: dir) }
        }
        guard try await installer.prepare(kind, spec: spec, progress: progress, extraCheck: extra) else { return false }

        await acquireSwap()
        defer { releaseSwap() }
        let previous = installer.currentVersion(kind)
        try installer.commit(kind, version: spec.version)
        try? setSkipped(kind, nil)
        if kind == .python, let g = carried.value {
            try writeWrapper()
            try writeGalleryState(python: spec.version, gallery: g)
        }
        let verified = installer.isVerified(kind, version: spec.version) ? "doğrulandı" : "doğrulama kaydı yok"
        if let previous {
            await log.append("\(kind.displayName) \(previous) → \(spec.version) (\(verified), eski sürüm saklandı)")
        } else {
            await log.append("\(kind.displayName) \(spec.version) kuruldu (\(verified))")
        }
        return true
    }

    /// Güncelleme kontrolünün kayda geçecek özeti; sessiz (değişiklik ve hata yok) kontrolde `nil`.
    static func checkSummary(updated: [ToolKind], failed: [ToolKind], offline: Bool) -> String? {
        if offline { return "Güncelleme kontrolü yapılamadı (internet yok)" }
        if !failed.isEmpty {
            return "Güncelleme kontrolü — \(failed.map(\.displayName).joined(separator: ", ")) güncellenemedi, eski sürüm kullanılıyor"
        }
        return updated.isEmpty ? nil : "Güncelleme kontrolü — \(updated.count) araç güncellendi"
    }

    // MARK: Atlanan sürüm (geri dönülen sürüm, daha yenisi çıkana kadar yeniden kurulmaz)

    /// Sürüm klasörlerinin budanmasından etkilenmesin diye araç klasörlerinin dışında tutulur.
    private func skipFile(_ kind: ToolKind) -> URL { tools.appendingPathComponent("skipped/\(kind.rawValue)") }

    private func skippedVersion(_ kind: ToolKind) -> String? {
        (try? String(contentsOf: skipFile(kind), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setSkipped(_ kind: ToolKind, _ version: String?) throws {
        let file = skipFile(kind)
        guard let version else { try? FileManager.default.removeItem(at: file); return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try version.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: Geri dönme

    /// Saklanan önceki sürüme döner (indirme sürüyorsa bitmesini bekler). Önceki sürüm yoksa `.noPreviousVersion`.
    public func rollback(_ kind: ToolKind) async throws(UserFacingError) {
        await acquireWork()
        defer { releaseWork() }
        do {
            if kind == .galleryDL { try await rollbackGalleryDL() } else { try await rollbackTool(kind) }
        } catch {
            throw Self.userError(error)
        }
    }

    private func rollbackTool(_ kind: ToolKind) async throws {
        guard let from = installer.currentVersion(kind), let to = installer.keptVersion(kind) else {
            throw UserFacingError.noPreviousVersion
        }
        let carried = Carried()
        var extra: (@Sendable (URL) async throws -> Void)?
        if kind == .python {
            // Eski Python klasöründe o zamanki gallery-dl kurulu durur; çalıştığını doğrula.
            extra = { @Sendable dir in
                guard let v = await self.galleryVersion(python: dir.appendingPathComponent("bin/python3")) else {
                    throw ToolError.healthCheckFailed("gallery-dl")
                }
                carried.value = v
            }
        }
        try await installer.check(kind, installer.kindDir(kind).appendingPathComponent(to), extra)

        await acquireSwap()
        defer { releaseSwap() }
        try installer.commit(kind, version: to)
        try setSkipped(kind, from)
        if kind == .python, let g = carried.value {
            try writeWrapper()
            try writeGalleryState(python: to, gallery: g)
        }
        await log.append("\(kind.displayName) önceki sürüme döndü: \(from) → \(to)")
    }

    private func rollbackGalleryDL() async throws {
        guard let state = galleryState(), let target = state.previous, state.python == installer.currentVersion(.python) else {
            throw UserFacingError.noPreviousVersion
        }
        await acquireSwap()
        defer { releaseSwap() }
        guard try await pip(["gallery-dl==\(target)"]), await galleryVersion() == target else {
            _ = try? await pip(["gallery-dl==\(state.gallery)"])
            throw ToolError.healthCheckFailed("gallery-dl")
        }
        try writeGalleryState(python: state.python, gallery: target, previous: state.gallery)
        try setSkipped(.galleryDL, state.gallery)
        await log.append("gallery-dl önceki sürüme döndü: \(state.gallery) → \(target)")
    }

    // MARK: gallery-dl (taşınabilir Python'un site-packages'ine pip ile; her çağrı yalıtılmış)

    private static let pythonEnv = ["PYTHONPATH": "", "PYTHONHOME": "", "PIP_DISABLE_PIP_VERSION_CHECK": "1"]

    private func galleryVersion(python: URL? = nil) async -> String? {
        guard let r = try? await installer.runner.run(python ?? pythonExe, ["-I", "-m", "gallery_dl", "--version"],
                                                      environment: Self.pythonEnv, onLine: { _ in }),
              r.exitCode == 0 else { return nil }
        let v = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// Başarısızlık ağdan kaynaklanıyorsa `.noInternet` fırlatır.
    /// Zaman sınırı: kötü bağlantıda pip'in varsayılanı (15 sn × 6 deneme) yeni indirmeleri bekletiyordu.
    private func pip(_ args: [String], python: URL? = nil) async throws -> Bool {
        let r = try await installer.runner.run(python ?? pythonExe, ["-I", "-m", "pip", "install", "--no-user", "--timeout", "10", "--retries", "1"] + args,
                                               environment: Self.pythonEnv, onLine: { _ in })
        if r.exitCode != 0, Self.pipLooksOffline(r.stderr) { throw UserFacingError.noInternet }
        return r.exitCode == 0
    }

    static func pipLooksOffline(_ stderr: String) -> Bool {
        let text = stderr.lowercased()
        return ["failed to establish a new connection", "newconnectionerror", "temporary failure in name resolution",
                "nodename nor servname", "network is unreachable", "no route to host", "connection refused",
                "readtimeouterror", "connecttimeouterror", "read timed out", "max retries exceeded"]
            .contains { text.contains($0) }
    }

    /// Yeni Python klasörüne, şu an kullanılan gallery-dl sürümünü (yoksa en yenisini) kurar ve çalıştığını doğrular.
    private func installGalleryDL(into dir: URL) async throws -> String {
        let py = dir.appendingPathComponent("bin/python3")
        let spec = await galleryVersion().map { "gallery-dl==\($0)" } ?? "gallery-dl"
        guard try await pip([spec], python: py), let v = await galleryVersion(python: py) else {
            throw ToolError.healthCheckFailed("gallery-dl")
        }
        return v
    }

    private func updateGalleryDL() async throws -> Bool {
        guard FileManager.default.isExecutableFile(atPath: pythonExe.path) else { throw ToolError.healthCheckFailed("python") }
        await acquireSwap()
        defer { releaseSwap() }
        let previous = await galleryVersion()
        // Geri dönülen sürüm, daha yenisi çıkana kadar yeniden kurulmaz.
        let installed = try await pip(["--upgrade", skippedVersion(.galleryDL).map { "gallery-dl!=\($0)" } ?? "gallery-dl"])
        let now = installed ? await galleryVersion() : nil
        guard let now else {
            if let previous { _ = try? await pip(["gallery-dl==\(previous)"]) }
            throw ToolError.healthCheckFailed("gallery-dl")
        }
        let changed = now != previous
        try writeWrapper()
        try writeGalleryState(python: installer.currentVersion(.python) ?? "", gallery: now, previous: changed ? previous : nil)
        if changed {
            try? setSkipped(.galleryDL, nil)
            await log.append(previous.map { "gallery-dl \($0) → \(now) (sağlık kontrolü geçti)" } ?? "gallery-dl \(now) kuruldu (sağlık kontrolü geçti)")
        }
        return changed
    }

    /// pip'in ürettiği betiklerin shebang'i mutlak yola bağlıdır; sürüm klasörü değişince bozulmaması için sabit bir sarmalayıcı kullanılır.
    private func writeWrapper() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: wrapper.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = "#!/bin/sh\nexec \"\(pythonExe.path)\" -I -m gallery_dl \"$@\"\n"
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
    ]

    private static func userError(_ error: Error) -> UserFacingError {
        if let e = error as? UserFacingError { return e }
        if error is CancellationError { return .cancelled }
        if let e = error as? URLError, offlineCodes.contains(e.code) { return .noInternet }
        if case .unsafeRelease = error as? ToolError { return .needsToolUpdate }
        return .unknown(details: String(describing: error))
    }
}

private final class Carried: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    var value: String? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
