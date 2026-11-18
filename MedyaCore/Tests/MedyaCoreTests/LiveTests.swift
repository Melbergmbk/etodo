import Testing
import Foundation
@testable import MedyaCore

private final class TickCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

/// Gerçek ağ ve gerçek araçlar gerekir: `MEDYA_LIVE=1 swift test --filter LiveTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEDYA_LIVE"] == "1")) struct LiveTests {
    @Test func youtubeVideoAndAudioEndToEnd() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mi-e2e-\(UUID().uuidString)")
        let out = root.appendingPathComponent("indirilenler")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let runner = SystemProcessRunner()
        let manager = ToolManager(root: root.appendingPathComponent("araclar"), fetcher: URLSessionFetcher(),
                                  runner: runner, arch: ToolManager.currentArch())
        try await manager.installMissing { _, _ in }
        let downloader = Downloader(runner: runner, tools: await manager.paths)

        let url = URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!
        func request(_ f: MediaFormat) -> DownloadRequest {
            DownloadRequest(url: url, site: .youtube, format: f, destination: out, browser: .chrome)
        }

        let info: FetchResult
        do {
            info = try await downloader.fetchInfo(request(.video(maxHeight: 360)))
        } catch {
            print("LIVE hata: \(error)\nLIVE stderr: \(await downloader.lastErrorOutput)")
            throw error
        }
        guard case .media(let media) = info else { Issue.record("media bekleniyordu"); return }
        print("LIVE başlık: \(media.title) yükseklikler: \(media.availableHeights)")
        #expect(!media.title.isEmpty)
        #expect(media.availableHeights.contains { $0 <= 360 })

        let ticks = TickCounter()
        let videos = try await downloader.download(request(.video(maxHeight: 360))) { _ in ticks.bump() }
        let video = try #require(videos.first)
        let vsize = (try fm.attributesOfItem(atPath: video.path)[.size] as? Int) ?? 0
        print("LIVE video: \(video.lastPathComponent) \(vsize) bayt, ilerleme çağrısı: \(ticks.value)")
        #expect(video.pathExtension == "mp4")
        #expect(vsize > 0)
        #expect(ticks.value >= 1)

        let audios = try await downloader.download(request(.audio(kbps: 128))) { _ in }
        let audio = try #require(audios.first)
        let asize = (try fm.attributesOfItem(atPath: audio.path)[.size] as? Int) ?? 0
        print("LIVE ses: \(audio.lastPathComponent) \(asize) bayt")
        #expect(audio.pathExtension == "mp3")
        #expect(asize > 0)

        let base = out.appendingPathComponent("Etodo/YouTube/jawed").path
        #expect(video.deletingLastPathComponent().path == base + "/Videolar")
        #expect(audio.deletingLastPathComponent().path == base + "/Sesler")
        let tree = fm.enumerator(atPath: out.path)?.compactMap { $0 as? String }.sorted() ?? []
        print("LIVE ağaç:\n" + tree.map { "  " + $0 }.joined(separator: "\n"))
    }
}
