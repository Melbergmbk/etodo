import Foundation

public enum FetchResult: Sendable, Equatable {
    case media(MediaInfo)
    case images
}

public actor Downloader {
    private let runner: ProcessRunning
    private let tools: ToolPaths
    /// Son çalıştırmanın ham hata çıktısı ("Ayrıntıları göster" için).
    public private(set) var lastErrorOutput: String = ""

    /// Tarayıcı çerezlerine ilk kez dokunmadan önce kullanıcıya sorulur; false dönerse çerezsiz hata gösterilir.
    private let beforeCookies: (@Sendable (Browser) async -> Bool)?

    public init(runner: ProcessRunning, tools: ToolPaths, beforeCookies: (@Sendable (Browser) async -> Bool)? = nil) {
        self.runner = runner
        self.tools = tools
        self.beforeCookies = beforeCookies
    }

    public func fetchInfo(_ r: DownloadRequest) async throws(UserFacingError) -> FetchResult {
        lastErrorOutput = ""
        return try await withCookieFallback(r) { (r) async throws(UserFacingError) -> FetchResult in try await self.fetchInfoOnce(r) }
    }

    public func download(_ r: DownloadRequest,
                         progress: @escaping @Sendable (DownloadProgress) -> Void) async throws(UserFacingError) -> [URL] {
        lastErrorOutput = ""
        try ensureDestination(FolderLayout.root(in: r.destination))
        return try await withCookieFallback(r) { (r) async throws(UserFacingError) -> [URL] in try await self.downloadOnce(r, progress: progress) }
    }

    /// Önce çerezsiz dener; yalnız giriş gerektiren hatalarda bir kez de tarayıcı çerezleriyle dener.
    /// (Silinmiş video gibi girişin çözemeyeceği hatalarda gerçek hata gösterilir.)
    private func withCookieFallback<T>(_ r: DownloadRequest,
                                       _ op: (DownloadRequest) async throws(UserFacingError) -> T) async throws(UserFacingError) -> T {
        if r.useCookies { return try await op(r) }
        do {
            return try await op(r)
        } catch {
            guard error != .cancelled, Self.loginMightHelp(lastErrorOutput) else { throw error }
            if let ask = beforeCookies, await !ask(r.browser) { throw error }
            var withCookies = r
            withCookies.useCookies = true
            return try await op(withCookies)
        }
    }

    static func loginMightHelp(_ stderr: String) -> Bool {
        let t = stderr.lowercased()
        return ["login", "log in", "sign in", "authenticat", "cookies", "private", "rate-limit",
                "requested content is not available", "confirm your age", "age-restricted", "age restricted",
                "members-only", "members only"].contains { t.contains($0) }
    }

    private func fetchInfoOnce(_ r: DownloadRequest) async throws(UserFacingError) -> FetchResult {
        let result = try await execute(tools.ytdlp, CommandBuilder.infoArguments(r, tools: tools), onLine: { _ in })
        if result.exitCode != 0 {
            if Self.mayHaveImages(r), Self.hasNoVideo(result.stderr) { return .images }
            throw fail(result.stderr, r)
        }
        do {
            return .media(try MediaInfo.parse(Data(result.stdout.utf8)))
        } catch {
            throw fail(result.stderr.isEmpty ? "Bilgi çözümlenemedi: \(error)" : result.stderr, r)
        }
    }

    private func downloadOnce(_ r: DownloadRequest,
                              progress: @escaping @Sendable (DownloadProgress) -> Void) async throws(UserFacingError) -> [URL] {
        if FolderLayout.usesGalleryDL(r) { return try await runGalleryDL(r, prior: []) }

        let paths = LockedList()
        let result = try await execute(tools.ytdlp, CommandBuilder.ytdlpArguments(r, tools: tools)) { line in
            if let p = ProgressParser.parse(line: line) {
                progress(p)
            } else if line.hasPrefix("/"), FileManager.default.fileExists(atPath: line) {
                paths.add(line)
            }
        }
        if result.exitCode == 0 {
            let files = paths.all.map { URL(fileURLWithPath: $0) }
            if files.isEmpty { throw fail(result.stderr.isEmpty ? "Dosya yolu alınamadı" : result.stderr, r) }
            return files
        }
        if Self.mayHaveImages(r), Self.hasNoVideo(result.stderr) {
            var images = r
            images.format = .images
            return try await runGalleryDL(images, prior: paths.all)
        }
        throw fail(result.stderr, r)
    }

    private func runGalleryDL(_ r: DownloadRequest, prior: [String]) async throws(UserFacingError) -> [URL] {
        let paths = LockedList()
        let result = try await execute(tools.galleryDL, CommandBuilder.galleryDLArguments(r)) { line in
            let path = line.hasPrefix("# ") ? String(line.dropFirst(2)) : line
            if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) { paths.add(path) }
        }
        guard result.exitCode == 0 else { throw fail(result.stderr, r) }
        var seen = Set<String>()
        let files = (prior + paths.all).filter { seen.insert($0).inserted }.map { URL(fileURLWithPath: $0) }
        if files.isEmpty { throw fail(result.stderr.isEmpty ? "gallery-dl dosya üretmedi" : result.stderr, r) }
        return files
    }

    private func execute(_ exe: URL, _ args: [String],
                         onLine: @escaping @Sendable (String) -> Void) async throws(UserFacingError) -> ProcessResult {
        do {
            return try await runner.run(exe, args, environment: [:], onLine: onLine)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            // Araç dosyası yok ya da çalıştırılamıyor: kullanıcıya "araçları güncelle" yolu gösterilir
            lastErrorOutput = "\(error)"
            throw .needsToolUpdate
        }
    }

    private func ensureDestination(_ dir: URL) throws(UserFacingError) {
        let fm = FileManager.default
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { throw .destinationNotWritable }
        guard fm.isWritableFile(atPath: dir.path) else { throw .destinationNotWritable }
    }

    private func fail(_ stderr: String, _ r: DownloadRequest) -> UserFacingError {
        lastErrorOutput = stderr
        return .classify(stderr: stderr, browser: r.browser)
    }

    /// Görsel gönderisi olabilen siteler: Instagram ve X.
    private static func mayHaveImages(_ r: DownloadRequest) -> Bool {
        switch Platform(url: r.url, site: r.site) {
        case .instagram, .x: true
        default: false
        }
    }

    private static func hasNoVideo(_ stderr: String) -> Bool {
        let t = stderr.lowercased()
        return t.contains("there is no video in this post") || t.contains("no video formats found")
            || t.contains("no video could be found in this tweet")
    }
}

private final class LockedList: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
