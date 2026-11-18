import Testing
import Foundation
@testable import MedyaCore

/// Gerçek ağ gerekir: `MEDYA_LIVE=1 swift test --filter ToolManagerLiveTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MEDYA_LIVE"] == "1")) struct ToolManagerLiveTests {
    @Test func installsAllToolsAndPrintsVersions() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mi-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let runner = SystemProcessRunner()
        let m = ToolManager(root: root, fetcher: URLSessionFetcher(), runner: runner, arch: ToolManager.currentArch())
        print("LIVE kök: \(root.path) mimari: \(ToolManager.currentArch())")
        try await m.installMissing { kind, p in if p == 1 { print("LIVE kuruldu: \(kind.rawValue)") } }

        let p = await m.paths
        let checks: [(String, URL, [String])] = [
            ("yt-dlp", p.ytdlp, ["--version"]),
            ("gallery-dl", p.galleryDL, ["--version"]),
            ("ffmpeg", p.ffmpegDir.appendingPathComponent("ffmpeg"), ["-version"]),
            ("ffprobe", p.ffmpegDir.appendingPathComponent("ffprobe"), ["-version"]),
            ("deno", p.deno, ["--version"]),
            ("python", root.appendingPathComponent("tools/python/current/bin/python3"), ["--version"]),
        ]
        for (name, exe, args) in checks {
            let r = try await runner.run(exe, args, environment: [:], onLine: { _ in })
            print("LIVE \(name): \(r.stdout.split(separator: "\n").first ?? "")")
            #expect(r.exitCode == 0)
        }
        for s in await m.status() { print("LIVE durum \(s.kind.rawValue) \(s.installedVersion ?? "-") hazır=\(s.isReady)") }
        #expect(await m.status().allSatisfy(\.isReady))
        #expect(await m.updateAll().isEmpty)
        try? FileManager.default.removeItem(at: root)
    }
}
