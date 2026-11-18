import Testing
import Foundation
@testable import MedyaCore

final class FakeRunner: ProcessRunning, @unchecked Sendable {
    struct Script {
        var matches: @Sendable (URL, [String]) -> Bool
        var lines: [String] = []
        var result: ProcessResult
    }
    private let lock = NSLock()
    private var scripts: [Script]
    private var _calls: [(URL, [String])] = []
    var throwing: (any Error)?
    init(_ scripts: [Script], throwing: (any Error)? = nil) { self.scripts = scripts; self.throwing = throwing }
    var calls: [(URL, [String])] { lock.lock(); defer { lock.unlock() }; return _calls }

    func run(_ executable: URL, _ arguments: [String], environment: [String: String],
             onLine: @escaping @Sendable (String) -> Void) async throws -> ProcessResult {
        if let throwing { throw throwing }
        let s: Script? = lock.withLock { _calls.append((executable, arguments)); return scripts.first { $0.matches(executable, arguments) } }
        guard let s else { return ProcessResult(exitCode: 1, stdout: "", stderr: "no script") }
        s.lines.forEach(onLine)
        return s.result
    }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DownloadProgress] = []
    func add(_ p: DownloadProgress) { lock.lock(); items.append(p); lock.unlock() }
    var all: [DownloadProgress] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct DownloaderTests {
    let tools = ToolPaths(
        ytdlp: URL(fileURLWithPath: "/t/yt-dlp"), galleryDL: URL(fileURLWithPath: "/t/gallery-dl"),
        ffmpegDir: URL(fileURLWithPath: "/t/bin"), deno: URL(fileURLWithPath: "/t/deno"))

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("mi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    func touch(_ name: String, in dir: URL) throws -> URL {
        let u = dir.appendingPathComponent(name)
        try Data("x".utf8).write(to: u)
        return u
    }
    func request(_ site: Site, _ format: MediaFormat, dest: URL) -> DownloadRequest {
        let link = site == .instagram ? "https://www.instagram.com/p/XYZ/" : "https://youtu.be/abc"
        return DownloadRequest(url: URL(string: link)!, site: site, format: format, destination: dest, browser: .chrome)
    }
    let isYtdlp: @Sendable (URL, [String]) -> Bool = { u, _ in u.lastPathComponent == "yt-dlp" }
    let isGallery: @Sendable (URL, [String]) -> Bool = { u, _ in u.lastPathComponent == "gallery-dl" }

    @Test func ytdlpSuccessReportsProgressAndReturnsFile() async throws {
        let dir = try tempDir()
        let file = try touch("v.mp4", in: dir)
        let runner = FakeRunner([.init(matches: isYtdlp,
            lines: ["MI|50|100|NA|1000|5", "MI|100|100|NA|1000|0", file.path],
            result: ProcessResult(exitCode: 0, stdout: "", stderr: ""))])
        let box = ProgressBox()
        let files = try await Downloader(runner: runner, tools: tools)
            .download(request(.youtube, .video(maxHeight: nil), dest: dir)) { box.add($0) }
        #expect(files == [file])
        #expect(box.all.count >= 1)
        #expect(box.all.last?.fraction == 1)
    }

    @Test func instagramNoVideoFallsBackToGalleryDL() async throws {
        let dir = try tempDir()
        let a = try touch("1.jpg", in: dir), b = try touch("2.jpg", in: dir), c = try touch("3.jpg", in: dir)
        let runner = FakeRunner([
            .init(matches: isYtdlp, result: ProcessResult(exitCode: 1, stdout: "", stderr: "ERROR: [Instagram] XYZ: There is no video in this post")),
            .init(matches: isGallery, lines: [a.path, "# " + b.path, c.path],
                  result: ProcessResult(exitCode: 0, stdout: "", stderr: "")),
        ])
        let files = try await Downloader(runner: runner, tools: tools)
            .download(request(.instagram, .video(maxHeight: nil), dest: dir)) { _ in }
        #expect(files == [a, b, c])
        #expect(runner.calls.contains { $0.0.lastPathComponent == "gallery-dl" })
    }

    @Test func imagesFormatGoesStraightToGalleryDL() async throws {
        let dir = try tempDir()
        let a = try touch("1.jpg", in: dir)
        let runner = FakeRunner([.init(matches: isGallery, lines: [a.path], result: ProcessResult(exitCode: 0, stdout: "", stderr: ""))])
        let files = try await Downloader(runner: runner, tools: tools)
            .download(request(.instagram, .images, dest: dir)) { _ in }
        #expect(files == [a])
        #expect(!runner.calls.contains { $0.0.lastPathComponent == "yt-dlp" })
    }

    @Test func http403NeedsToolUpdateAndKeepsRawStderr() async throws {
        let dir = try tempDir()
        let runner = FakeRunner([.init(matches: isYtdlp, result: ProcessResult(exitCode: 1, stdout: "", stderr: "ERROR: HTTP Error 403: Forbidden"))])
        let d = Downloader(runner: runner, tools: tools)
        await #expect(throws: UserFacingError.needsToolUpdate) {
            try await d.download(request(.youtube, .video(maxHeight: nil), dest: dir)) { _ in }
        }
        #expect(await d.lastErrorOutput.contains("403"))
    }

    @Test func readOnlyDestinationFails() async throws {
        let dir = try tempDir()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let runner = FakeRunner([])
        await #expect(throws: UserFacingError.destinationNotWritable) {
            try await Downloader(runner: runner, tools: tools)
                .download(request(.youtube, .video(maxHeight: nil), dest: dir)) { _ in }
        }
        #expect(runner.calls.isEmpty)
    }

    @Test func createsMissingDestination() async throws {
        let dir = try tempDir().appendingPathComponent("a/b")
        let runner = FakeRunner([.init(matches: isYtdlp, result: ProcessResult(exitCode: 0, stdout: "", stderr: ""))])
        _ = try? await Downloader(runner: runner, tools: tools)
            .download(request(.youtube, .video(maxHeight: nil), dest: dir)) { _ in }
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func fetchInfoParsesMedia() async throws {
        let json = #"{"id":"abc","title":"Merhaba","formats":[{"height":720,"vcodec":"avc1","ext":"mp4"}]}"#
        let runner = FakeRunner([.init(matches: isYtdlp, result: ProcessResult(exitCode: 0, stdout: json, stderr: ""))])
        let r = try await Downloader(runner: runner, tools: tools).fetchInfo(request(.youtube, .video(maxHeight: nil), dest: try tempDir()))
        guard case .media(let info) = r else { Issue.record("media bekleniyordu"); return }
        #expect(info.title == "Merhaba")
        #expect(info.availableHeights == [720])
    }

    @Test(arguments: ["ERROR: There is no video in this post", "ERROR: No video formats found!"])
    func fetchInfoImages(stderr: String) async throws {
        let runner = FakeRunner([.init(matches: isYtdlp, result: ProcessResult(exitCode: 1, stdout: "", stderr: stderr))])
        let r = try await Downloader(runner: runner, tools: tools).fetchInfo(request(.instagram, .video(maxHeight: nil), dest: try tempDir()))
        #expect(r == .images)
    }

    @Test func cancellationMapsToCancelled() async throws {
        let dir = try tempDir()
        let d = Downloader(runner: FakeRunner([], throwing: CancellationError()), tools: tools)
        await #expect(throws: UserFacingError.cancelled) {
            try await d.download(request(.youtube, .video(maxHeight: nil), dest: dir)) { _ in }
        }
    }

    @Test func missingToolMapsToNeedsToolUpdate() async throws {
        let dir = try tempDir()
        let missing = ToolPaths(ytdlp: URL(fileURLWithPath: "/nonexistent/yt-dlp"), galleryDL: tools.galleryDL,
                                ffmpegDir: tools.ffmpegDir, deno: tools.deno)
        let d = Downloader(runner: SystemProcessRunner(), tools: missing)
        await #expect(throws: UserFacingError.needsToolUpdate) {
            try await d.download(request(.youtube, .video(maxHeight: nil), dest: dir)) { _ in }
        }
        #expect(!(await d.lastErrorOutput).isEmpty)
    }

    @Test func fetchInfoNoVideoOnYoutubeIsNotImages() async throws {
        let runner = FakeRunner([.init(matches: isYtdlp, result: ProcessResult(exitCode: 1, stdout: "", stderr: "ERROR: No video formats found!"))])
        let d = Downloader(runner: runner, tools: tools)
        let r = try? await d.fetchInfo(request(.youtube, .video(maxHeight: nil), dest: try tempDir()))
        #expect(r == nil)
    }

    @Test func mixedGalleryMergesYtdlpAndGalleryPaths() async throws {
        let dir = try tempDir()
        let v = try touch("v.mp4", in: dir), a = try touch("1.jpg", in: dir), b = try touch("2.jpg", in: dir)
        let runner = FakeRunner([
            .init(matches: isYtdlp, lines: [v.path],
                  result: ProcessResult(exitCode: 1, stdout: "", stderr: "ERROR: [Instagram] XYZ: There is no video in this post")),
            .init(matches: isGallery, lines: ["# " + v.path, a.path, b.path],
                  result: ProcessResult(exitCode: 0, stdout: "", stderr: "")),
        ])
        let files = try await Downloader(runner: runner, tools: tools)
            .download(request(.instagram, .video(maxHeight: nil), dest: dir)) { _ in }
        #expect(files == [v, a, b])
    }
}
