import Testing
import Foundation
@testable import MedyaCore

@Suite struct SiteTests {
    @Test(arguments: [
        "https://youtu.be/abc",
        "https://www.youtube.com/shorts/abc",
        "https://music.youtube.com/watch?v=abc",
        "https://m.youtube.com/watch?v=abc&list=PL1&t=30",
    ])
    func detectsYouTube(_ link: String) {
        #expect(Site.detect(link) == .youtube)
    }

    @Test func detectsInstagramAndStripsTracking() throws {
        let link = "https://www.instagram.com/reel/XYZ/?igsh=123"
        #expect(Site.detect(link) == .instagram)
        let url = try #require(Site.normalizedURL(link))
        #expect(!url.absoluteString.contains("igsh"))
        #expect(url.absoluteString == "https://www.instagram.com/reel/XYZ/")
    }

    @Test func normalizedKeepsMeaningfulParameters() throws {
        let url = try #require(Site.normalizedURL("https://www.youtube.com/watch?v=abc&si=TRK&utm_source=x&t=30"))
        #expect(url.absoluteString == "https://www.youtube.com/watch?v=abc&t=30")
    }

    @Test(arguments: [
        "https://x.com/u/status/1",
        "https://twitter.com/u/status/1",
        "https://www.tiktok.com/@u/video/1",
    ])
    func otherSites(_ link: String) {
        #expect(Site.detect(link) == .other)
    }

    @Test(arguments: ["merhaba", "", "ftp://a"])
    func invalidLinks(_ link: String) {
        #expect(Site.detect(link) == nil)
    }

    @Test func trimsPastedWhitespace() {
        #expect(Site.detect("  https://youtu.be/abc  \n") == .youtube)
    }

    @Test func lookalikeHostsAreNotYouTube() {
        #expect(Site.detect("https://notyoutube.com/watch?v=1") == .other)
        #expect(Site.detect("https://youtube.com.evil.io/x") == .other)
    }

    @Test func instagramPostPaths() throws {
        for path in ["p", "reel", "reels", "tv"] {
            let url = try #require(URL(string: "https://www.instagram.com/\(path)/ABC/"))
            #expect(Site.isInstagramPost(url))
        }
        let profile = try #require(URL(string: "https://www.instagram.com/someone/"))
        #expect(!Site.isInstagramPost(profile))
    }
}
