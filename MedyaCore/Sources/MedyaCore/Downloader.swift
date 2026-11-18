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

    public init(runner: ProcessRunning, tools: ToolPaths) {
        self.runner = runner
        self.tools = tools
    }

    public func fetchInfo(_ r: DownloadRequest) async throws(UserFacingError) -> FetchResult {
        lastErrorOutput = ""
        let result = try await execute(tools.ytdlp, CommandBuilder.infoArguments(r, tools: tools), onLine: { _ in })
        if result.exitCode != 0 {
            if Self.hasNoVideo(result.stderr) { return .images }
            throw fail(result.stderr, r)
        }
        do {
            return .media(try MediaInfo.parse(Data(result.stdout.utf8)))
        } catch {
            throw fail(result.stderr.isEmpty ? "Bilgi çözümlenemedi: \(error)" : result.stderr, r)
        }
    }

    public func download(_ r: DownloadRequest,
                         progress: @escaping @Sendable (DownloadProgress) -> Void) async throws(UserFacingError) -> [URL] {
        lastErrorOutput = ""
        try ensureDestination(r.destination)

        if r.format == .images { return try await runGalleryDL(r) }

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
        if r.site == .instagram, Self.hasNoVideo(result.stderr) { return try await runGalleryDL(r) }
        throw fail(result.stderr, r)
    }

    private func runGalleryDL(_ r: DownloadRequest) async throws(UserFacingError) -> [URL] {
        let paths = LockedList()
        let result = try await execute(tools.galleryDL, CommandBuilder.galleryDLArguments(r)) { line in
            let path = line.hasPrefix("# ") ? String(line.dropFirst(2)) : line
            if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) { paths.add(path) }
        }
        guard result.exitCode == 0 else { throw fail(result.stderr, r) }
        let files = paths.all.map { URL(fileURLWithPath: $0) }
        if files.isEmpty { throw fail(result.stderr.isEmpty ? "gallery-dl dosya üretmedi" : result.stderr, r) }
        return files
    }

    private func execute(_ exe: URL, _ args: [String],
                         onLine: @escaping @Sendable (String) -> Void) async throws(UserFacingError) -> ProcessResult {
        do {
            return try await runner.run(exe, args, environment: [:], onLine: onLine)
        } catch is CancellationError {
            throw .unknown(details: "İptal edildi")
        } catch {
            lastErrorOutput = "\(error)"
            throw .unknown(details: "\(error)")
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

    private static func hasNoVideo(_ stderr: String) -> Bool {
        let t = stderr.lowercased()
        return t.contains("there is no video in this post") || t.contains("no video formats found")
    }
}

private final class LockedList: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
