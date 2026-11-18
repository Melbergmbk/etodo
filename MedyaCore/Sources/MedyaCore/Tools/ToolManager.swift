import Foundation

public actor ToolManager {
    private let installer: ToolInstaller
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

    /// gallery-dl durumu: kurulduğu Python sürümü + gallery-dl sürümü.
    private func galleryState() -> (python: String, gallery: String)? {
        guard let text = try? String(contentsOf: galleryStateFile, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        return lines.count >= 2 ? (lines[0], lines[1]) : nil
    }

    private func writeGalleryState(python: String, gallery: String) throws {
        try FileManager.default.createDirectory(at: galleryStateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "\(python)\n\(gallery)\n".write(to: galleryStateFile, atomically: true, encoding: .utf8)
    }

    public func status() -> [ToolStatus] {
        let fm = FileManager.default
        return ToolKind.allCases.map { kind in
            switch kind {
            case .galleryDL:
                let state = galleryState()
                let ready = fm.isExecutableFile(atPath: wrapper.path) && fm.isExecutableFile(atPath: pythonExe.path)
                    && state != nil && state?.python == installer.currentVersion(.python)
                return ToolStatus(kind: kind, installedVersion: state?.gallery, isReady: ready)
            default:
                let v = installer.currentVersion(kind)
                let ready = kind.executables.allSatisfy { fm.isExecutableFile(atPath: installer.currentLink(kind).appendingPathComponent($0).path) }
                return ToolStatus(kind: kind, installedVersion: v, isReady: v != nil && ready)
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
        var updated: [ToolKind] = []
        for kind in ToolKind.allCases {
            if let changed = try? await update(kind, progress: { _ in }), changed { updated.append(kind) }
        }
        return updated
    }

    private func update(_ kind: ToolKind, progress: @escaping @Sendable (Double) -> Void) async throws -> Bool {
        if kind == .galleryDL { return try await updateGalleryDL() }
        let spec = try await kind.resolve(arch: arch, fetcher: installer.fetcher)
        let carried = Carried()
        var extra: (@Sendable (URL) async throws -> Void)?
        if kind == .python {
            extra = { @Sendable dir in carried.value = try await self.installGalleryDL(into: dir) }
        }
        guard try await installer.prepare(kind, spec: spec, progress: progress, extraCheck: extra) else { return false }

        await acquireSwap()
        defer { releaseSwap() }
        try installer.commit(kind, version: spec.version)
        if kind == .python, let g = carried.value {
            try writeWrapper()
            try writeGalleryState(python: spec.version, gallery: g)
        }
        return true
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

    private func pip(_ args: [String], python: URL? = nil) async throws -> Bool {
        let r = try await installer.runner.run(python ?? pythonExe, ["-I", "-m", "pip", "install", "--no-user"] + args,
                                               environment: Self.pythonEnv, onLine: { _ in })
        return r.exitCode == 0
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
        let installed = try await pip(["--upgrade", "gallery-dl"])
        let now = installed ? await galleryVersion() : nil
        guard let now else {
            if let previous { _ = try? await pip(["gallery-dl==\(previous)"]) }
            throw ToolError.healthCheckFailed("gallery-dl")
        }
        try writeWrapper()
        try writeGalleryState(python: installer.currentVersion(.python) ?? "", gallery: now)
        return now != previous || galleryState()?.python != installer.currentVersion(.python)
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
