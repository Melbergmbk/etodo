import Foundation

public actor ToolManager {
    private let root: URL
    private let installer: ToolInstaller
    private let arch: String
    private var downloads = 0
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    /// `arch`: `arm64` veya `x86_64`
    public init(root: URL, fetcher: HTTPFetching, runner: ProcessRunning, arch: String) {
        self.root = root
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
    private var galleryVersionFile: URL { tools.appendingPathComponent("galleryDL/version") }

    public var paths: ToolPaths {
        ToolPaths(ytdlp: tools.appendingPathComponent("ytdlp/current/yt-dlp"),
                  galleryDL: wrapper,
                  ffmpegDir: tools.appendingPathComponent("ffmpeg/current"),
                  deno: tools.appendingPathComponent("deno/current/deno"))
    }

    // MARK: Durum

    public func status() -> [ToolStatus] {
        let fm = FileManager.default
        return ToolKind.allCases.map { kind in
            switch kind {
            case .galleryDL:
                let v = (try? String(contentsOf: galleryVersionFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                let ready = fm.isExecutableFile(atPath: wrapper.path) && fm.isExecutableFile(atPath: pythonExe.path)
                return ToolStatus(kind: kind, installedVersion: v, isReady: ready)
            default:
                let v = installer.currentVersion(kind)
                let ready = kind.executables.allSatisfy { fm.isExecutableFile(atPath: installer.currentLink(kind).appendingPathComponent($0).path) }
                return ToolStatus(kind: kind, installedVersion: v, isReady: v != nil && ready)
            }
        }
    }

    // MARK: İndirme sayacı

    /// İndirme sürerken araç takası (güncelleme) bekletilir.
    public func beginDownload() { downloads += 1 }

    public func endDownload() {
        downloads = max(0, downloads - 1)
        if downloads == 0 {
            let waiters = idleWaiters
            idleWaiters = []
            waiters.forEach { $0.resume() }
        }
    }

    private func waitUntilIdle() async {
        guard downloads > 0 else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    // MARK: Kurulum ve güncelleme

    public func installMissing(progress: @escaping @Sendable (ToolKind, Double) -> Void) async throws(UserFacingError) {
        let missing = Set(status().filter { !$0.isReady }.map(\.kind))
        for kind in ToolKind.allCases where missing.contains(kind) {
            do { _ = try await update(kind) { progress(kind, $0) } } catch { throw Self.userError(error) }
            progress(kind, 1)
        }
    }

    /// Güncellenen araçların listesi; tek tek hata veren araç atlanır (eski sürüm çalışmaya devam eder).
    public func updateAll() async -> [ToolKind] {
        var updated: [ToolKind] = []
        for kind in ToolKind.allCases {
            if let changed = try? await update(kind, progress: { _ in }), changed { updated.append(kind) }
        }
        return updated
    }

    private func update(_ kind: ToolKind, progress: @escaping @Sendable (Double) -> Void) async throws -> Bool {
        if kind == .galleryDL { return try await updateGalleryDL() }
        let spec = try await kind.resolve(arch: arch, fetcher: installer.fetcher)
        let changed = try await installer.install(kind, spec: spec, progress: progress, beforeSwitch: { await self.waitUntilIdle() })
        return changed
    }

    // MARK: gallery-dl (taşınabilir Python'un site-packages'ine pip ile)

    private func galleryVersion() async -> String? {
        guard let r = try? await installer.runner.run(pythonExe, ["-m", "gallery_dl", "--version"], environment: [:], onLine: { _ in }),
              r.exitCode == 0 else { return nil }
        let v = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private func pip(_ args: [String]) async throws -> Bool {
        let r = try await installer.runner.run(pythonExe, ["-m", "pip"] + args, environment: ["PIP_DISABLE_PIP_VERSION_CHECK": "1"], onLine: { _ in })
        return r.exitCode == 0
    }

    private func updateGalleryDL() async throws -> Bool {
        guard FileManager.default.isExecutableFile(atPath: pythonExe.path) else { throw ToolError.healthCheckFailed("python") }
        let previous = await galleryVersion()
        await waitUntilIdle()
        let installed = try await pip(["install", "--upgrade", "gallery-dl"])
        let now = installed ? await galleryVersion() : nil
        guard let now else {
            if let previous { _ = try? await pip(["install", "gallery-dl==\(previous)"]) }
            throw ToolError.healthCheckFailed("gallery-dl")
        }
        try writeWrapper()
        try FileManager.default.createDirectory(at: galleryVersionFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try now.write(to: galleryVersionFile, atomically: true, encoding: .utf8)
        return now != previous
    }

    /// pip'in ürettiği betiklerin shebang'i mutlak yola bağlıdır; sürüm klasörü değişince bozulmaması için sabit bir sarmalayıcı kullanılır.
    private func writeWrapper() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: wrapper.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = "#!/bin/sh\nexec \"\(pythonExe.path)\" -m gallery_dl \"$@\"\n"
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
        return .unknown(details: String(describing: error))
    }
}
