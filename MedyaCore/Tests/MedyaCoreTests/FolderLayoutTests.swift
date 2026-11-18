import Testing
import Foundation
@testable import MedyaCore

@Suite struct FolderLayoutTests {
    func platform(_ link: String) -> Platform {
        let url = URL(string: link)!
        return Platform(url: url, site: Site.detect(link)!)
    }

    func request(_ link: String, _ format: MediaFormat) -> DownloadRequest {
        DownloadRequest(url: URL(string: link)!, site: Site.detect(link)!, format: format,
                        destination: URL(fileURLWithPath: "/Users/x/Downloads"), browser: .chrome)
    }

    @Test(arguments: [
        ("https://www.youtube.com/watch?v=abc", "YouTube"),
        ("https://youtu.be/abc", "YouTube"),
        ("https://www.instagram.com/reel/XYZ/", "Instagram"),
        ("https://x.com/nasa/status/1", "X (Twitter)"),
        ("https://twitter.com/nasa/status/1", "X (Twitter)"),
        ("https://mobile.twitter.com/nasa/status/1", "X (Twitter)"),
        ("https://www.tiktok.com/@a/video/1", "TikTok"),
        ("https://vm.tiktok.com/ZM123/", "TikTok"),
        ("https://www.vimeo.com/123", "Diğer/vimeo.com"),
        ("https://m.facebook.com/watch?v=1", "Diğer/m.facebook.com"),
    ])
    func platformFolder(link: String, folder: String) {
        #expect(platform(link).folder == folder)
    }

    @Test(arguments: [
        ("https://www.youtube.com/watch?v=abc", MediaFormat.video(maxHeight: nil), "Videolar"),
        ("https://www.youtube.com/shorts/abc", .video(maxHeight: 720), "Shorts"),
        ("https://www.youtube.com/shorts/abc", .audio(kbps: 128), "Sesler"),
        ("https://www.youtube.com/watch?v=abc", .audio(kbps: 320), "Sesler"),
        ("https://www.instagram.com/reel/XYZ/", .video(maxHeight: nil), "Reels"),
        ("https://www.instagram.com/reels/XYZ/", .video(maxHeight: nil), "Reels"),
        ("https://www.instagram.com/stories/ali/123/", .video(maxHeight: nil), "Hikâyeler"),
        ("https://www.instagram.com/p/XYZ/", .images, "Gönderiler"),
        ("https://www.instagram.com/tv/XYZ/", .video(maxHeight: nil), "Gönderiler"),
        ("https://www.instagram.com/reel/XYZ/", .audio(kbps: 128), "Sesler"),
        ("https://x.com/nasa/status/1", .video(maxHeight: nil), "Gönderiler"),
        ("https://x.com/nasa/status/1", .images, "Gönderiler"),
        ("https://www.tiktok.com/@a/video/1", .video(maxHeight: nil), "Videolar"),
        ("https://vimeo.com/123", .video(maxHeight: nil), "Videolar"),
        ("https://vimeo.com/123", .audio(kbps: 128), "Sesler"),
    ])
    func kindFolder(link: String, format: MediaFormat, folder: String) {
        #expect(FolderLayout.kindFolder(url: URL(string: link)!, platform: platform(link), format: format) == folder)
    }

    @Test func rootIsAppFolderInsideParent() {
        #expect(FolderLayout.root(in: URL(fileURLWithPath: "/Users/x/Downloads")).path == "/Users/x/Downloads/Etodo")
    }

    @Test func youtubeTemplateUsesChannelDisplayName() {
        #expect(FolderLayout.ytdlpOutputTemplate(request("https://www.youtube.com/watch?v=abc", .video(maxHeight: nil)))
                == "YouTube/%(channel,uploader|Bilinmeyen)s/Videolar/%(title).150B [%(id)s].%(ext)s")
        #expect(FolderLayout.ytdlpOutputTemplate(request("https://www.youtube.com/shorts/abc", .audio(kbps: 128)))
                == "YouTube/%(channel,uploader|Bilinmeyen)s/Sesler/%(title).150B [%(id)s].%(ext)s")
    }

    @Test func handleTemplatesPrefixAtOnlyWhenPresent() {
        #expect(FolderLayout.ytdlpOutputTemplate(request("https://www.instagram.com/reel/XYZ/", .video(maxHeight: nil)))
                == "Instagram/%(channel&@{}|Bilinmeyen)s/Reels/%(title).150B [%(id)s].%(ext)s")
        #expect(FolderLayout.ytdlpOutputTemplate(request("https://x.com/nasa/status/1", .video(maxHeight: nil)))
                == "X (Twitter)/%(uploader_id&@{}|Bilinmeyen)s/Gönderiler/%(title).150B [%(id)s].%(ext)s")
        #expect(FolderLayout.ytdlpOutputTemplate(request("https://www.tiktok.com/@a/video/1", .video(maxHeight: nil)))
                == "TikTok/%(uploader&@{}|Bilinmeyen)s/Videolar/%(title).150B [%(id)s].%(ext)s")
    }

    @Test func otherSiteTemplate() {
        #expect(FolderLayout.ytdlpOutputTemplate(request("https://www.vimeo.com/123", .video(maxHeight: nil)))
                == "Diğer/vimeo.com/%(uploader,channel|Bilinmeyen)s/Videolar/%(title).150B [%(id)s].%(ext)s")
    }

    @Test func instagramPostsGoStraightToGalleryDLExceptAudio() {
        #expect(FolderLayout.usesGalleryDL(request("https://www.instagram.com/p/XYZ/", .video(maxHeight: nil))))
        #expect(FolderLayout.usesGalleryDL(request("https://www.instagram.com/p/XYZ/", .images)))
        #expect(!FolderLayout.usesGalleryDL(request("https://www.instagram.com/p/XYZ/", .audio(kbps: 128))))
        #expect(!FolderLayout.usesGalleryDL(request("https://www.instagram.com/reel/XYZ/", .video(maxHeight: nil))))
        #expect(FolderLayout.usesGalleryDL(request("https://x.com/nasa/status/1", .images)))
        #expect(!FolderLayout.usesGalleryDL(request("https://x.com/nasa/status/1", .video(maxHeight: nil))))
    }

    func directory(_ link: String) throws -> [String: [String]] {
        let json = FolderLayout.galleryDLDirectory(request(link, .images))
        return try JSONDecoder().decode([String: [String]].self, from: Data(json.utf8))
    }

    @Test func instagramGalleryDirectoryIsConditional() throws {
        let d = try directory("https://www.instagram.com/p/XYZ/")
        #expect(d["username and count > 1"] == ["Instagram", "@{username}", "Gönderiler", "{post_date:%Y-%m-%d} · {post_shortcode}"])
        #expect(d["username"] == ["Instagram", "@{username}", "Gönderiler"])
        #expect(d["count > 1"] == ["Instagram", "Bilinmeyen", "Gönderiler", "{post_date:%Y-%m-%d} · {post_shortcode}"])
        #expect(d[""] == ["Instagram", "Bilinmeyen", "Gönderiler"])
    }

    @Test func instagramGalleryConditionsAreOrderedMostSpecificFirst() {
        let json = FolderLayout.galleryDLDirectory(request("https://www.instagram.com/p/XYZ/", .images))
        let keys = ["\"username and count > 1\"", "\"username\"", "\"count > 1\"", "\"\""]
        let positions = keys.map { json.range(of: $0)?.lowerBound }
        #expect(positions.allSatisfy { $0 != nil })
        #expect(positions.compactMap { $0 } == positions.compactMap { $0 }.sorted())
    }

    @Test func xGalleryDirectory() throws {
        let d = try directory("https://x.com/nasa/status/1")
        #expect(d["author['name']"] == ["X (Twitter)", "@{author[name]}", "Gönderiler"])
        #expect(d[""] == ["X (Twitter)", "Bilinmeyen", "Gönderiler"])
    }

    @Test func otherGalleryDirectory() throws {
        let d = try directory("https://www.flickr.com/photos/a/1")
        #expect(d[""] == ["Diğer", "flickr.com", "Bilinmeyen", "Gönderiler"])
    }

    @Test(arguments: [
        (nil as String?, "/Users/x/Downloads"),
        ("/Users/x/Downloads/MedyaIndirici", "/Users/x/Downloads"),
        ("/Volumes/Disk/MedyaIndirici", "/Volumes/Disk"),
        ("/Users/x/Movies", "/Users/x/Movies"),
        ("/Users/x/Downloads/Etodo", "/Users/x/Downloads"),
    ])
    func migratesStoredDestination(stored: String?, expected: String) {
        let fallback = URL(fileURLWithPath: "/Users/x/Downloads", isDirectory: true)
        #expect(FolderLayout.parentFolder(stored: stored, fallback: fallback).path == expected)
    }
}
