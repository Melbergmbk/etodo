import Testing
import Foundation
@testable import MedyaCore

@Suite struct CommandBuilderTests {
    let tools = ToolPaths(
        ytdlp: URL(fileURLWithPath: "/t/yt-dlp"),
        galleryDL: URL(fileURLWithPath: "/t/gallery-dl"),
        ffmpegDir: URL(fileURLWithPath: "/t/bin"),
        deno: URL(fileURLWithPath: "/t/deno"))

    func request(_ site: Site, _ format: MediaFormat, browser: Browser = .chrome) -> DownloadRequest {
        let link = site == .instagram ? "https://www.instagram.com/reel/XYZ/" : "https://youtu.be/abc"
        return DownloadRequest(url: URL(string: link)!, site: site, format: format,
                               destination: URL(fileURLWithPath: "/Users/x/Downloads"),
                               browser: browser, useCookies: true)
    }

    @Test func noCookiesUnlessRequested() {
        var r = request(.youtube, .video(maxHeight: nil))
        r.useCookies = false
        #expect(!CommandBuilder.ytdlpArguments(r, tools: tools).contains("--cookies-from-browser"))
        #expect(!CommandBuilder.infoArguments(r, tools: tools).contains("--cookies-from-browser"))
        r.format = .images
        #expect(!CommandBuilder.galleryDLArguments(r).contains("--cookies-from-browser"))
    }

    func contains(_ args: [String], _ sub: [String]) -> Bool {
        guard !sub.isEmpty, args.count >= sub.count else { return false }
        return (0...(args.count - sub.count)).contains { Array(args[$0..<($0 + sub.count)]) == sub }
    }

    @Test func commonFlags() {
        let a = CommandBuilder.ytdlpArguments(request(.youtube, .video(maxHeight: nil), browser: .safari), tools: tools)
        #expect(contains(a, ["--cookies-from-browser", "safari"]))
        #expect(a.contains("--no-playlist"))
        #expect(contains(a, ["--ffmpeg-location", "/t/bin"]))
        #expect(a.contains("--newline"))
        #expect(contains(a, ["--progress-template",
            "download:MI|%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s"]))
        #expect(contains(a, ["-P", "/Users/x/Downloads/Etodo"]))
        #expect(contains(a, ["-o", "YouTube/%(channel,uploader|Bilinmeyen)s/Videolar/%(title).150B [%(id)s].%(ext)s"]))
        #expect(a.contains("--windows-filenames"))
    }

    @Test func printsFinalPathAndKeepsProgress() {
        let a = CommandBuilder.ytdlpArguments(request(.youtube, .audio(kbps: 128)), tools: tools)
        #expect(contains(a, ["--print", "after_move:filepath"]))
        #expect(a.contains("--progress"))
    }

    @Test func youtubeAudio() {
        let a = CommandBuilder.ytdlpArguments(request(.youtube, .audio(kbps: 192)), tools: tools)
        #expect(contains(a, ["-x", "--audio-format", "mp3", "--audio-quality", "192K"]))
        #expect(a.contains("--remote-components"))
        #expect(a.contains("ejs:github"))
        #expect(contains(a, ["--js-runtimes", "deno:/t/deno"]))
        #expect(a.last == "https://youtu.be/abc")
    }

    @Test func instagramHasNoYouTubeOnlyFlags() {
        let a = CommandBuilder.ytdlpArguments(request(.instagram, .video(maxHeight: nil)), tools: tools)
        #expect(!a.contains("--remote-components"))
        #expect(!a.contains("--js-runtimes"))
        #expect(a.last == "https://www.instagram.com/reel/XYZ/")
    }

    @Test func videoWithHeight() {
        let a = CommandBuilder.ytdlpArguments(request(.youtube, .video(maxHeight: 720)), tools: tools)
        #expect(contains(a, ["-f", "bv*[height<=720]+ba/b[height<=720]"]))
        #expect(contains(a, ["--merge-output-format", "mp4"]))
        #expect(contains(a, ["-S", "res,vcodec:h264,acodec:m4a"]))
    }

    @Test func videoBest() {
        let a = CommandBuilder.ytdlpArguments(request(.youtube, .video(maxHeight: nil)), tools: tools)
        #expect(contains(a, ["-f", "bv*+ba/b"]))
        #expect(a.contains("--ignore-config"))
    }

    @Test func subtitlesOnlyForYouTubeVideoWhenAsked() {
        var r = request(.youtube, .video(maxHeight: 1080))
        #expect(!CommandBuilder.ytdlpArguments(r, tools: tools).contains("--embed-subs"))
        r.subtitles = true
        let a = CommandBuilder.ytdlpArguments(r, tools: tools)
        #expect(contains(a, ["--write-auto-subs", "--sub-langs", "tr,en", "--embed-subs"]))
        #expect(!a.contains("--write-subs"))
        var audio = request(.youtube, .audio(kbps: 192))
        audio.subtitles = true
        #expect(!CommandBuilder.ytdlpArguments(audio, tools: tools).contains("--embed-subs"))
        var insta = request(.instagram, .video(maxHeight: nil))
        insta.subtitles = true
        #expect(!CommandBuilder.ytdlpArguments(insta, tools: tools).contains("--embed-subs"))
    }

    @Test func infoArguments() {
        let a = CommandBuilder.infoArguments(request(.youtube, .video(maxHeight: nil), browser: .firefox), tools: tools)
        #expect(a.contains("-J"))
        #expect(contains(a, ["--remote-components", "ejs:github"]))
        #expect(contains(a, ["--js-runtimes", "deno:/t/deno"]))
        #expect(a.contains("--no-playlist"))
        #expect(a.contains("--ignore-config"))
        #expect(contains(a, ["--cookies-from-browser", "firefox"]))
        #expect(a.last == "https://youtu.be/abc")
    }

    @Test func infoArgumentsInstagramHasNoYoutubeFlags() {
        let a = CommandBuilder.infoArguments(request(.instagram, .video(maxHeight: nil)), tools: tools)
        #expect(!a.contains("--js-runtimes"))
        #expect(!a.contains("--remote-components"))
    }

    @Test func galleryDL() {
        let r = request(.instagram, .images, browser: .brave)
        let a = CommandBuilder.galleryDLArguments(r)
        #expect(a == ["--cookies-from-browser", "brave", "--config-ignore", "-d", "/Users/x/Downloads/Etodo",
                      "-o", "directory=" + FolderLayout.galleryDLDirectory(r),
                      "https://www.instagram.com/reel/XYZ/"])
        #expect(!a.contains("-D"))
    }

    @Test func instagramReelOutputTemplate() {
        let a = CommandBuilder.ytdlpArguments(request(.instagram, .video(maxHeight: nil)), tools: tools)
        #expect(contains(a, ["-o", "Instagram/%(channel&@{}|Bilinmeyen)s/Reels/%(title).150B [%(id)s].%(ext)s"]))
    }

    @Test func browserDisplayNames() {
        #expect(Browser.chrome.displayName == "Chrome")
        #expect(Browser.safari.displayName == "Safari")
        #expect(Browser.edge.displayName == "Edge")
        #expect(Browser.allCases.count == 5)
    }
}
