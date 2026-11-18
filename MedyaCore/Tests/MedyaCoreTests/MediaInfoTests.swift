import Testing
import Foundation
@testable import MedyaCore

@Suite struct MediaInfoTests {
    func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func parsesYouTube() throws {
        let info = try MediaInfo.parse(fixture("youtube-info"))
        #expect(info.title == "Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film")
        #expect(info.uploader == "Blender")
        #expect(info.duration == 635)
        #expect(info.thumbnailURL != nil)
        #expect(info.availableHeights == [2160, 1080, 720, 360])
    }

    @Test func parsesInstagramReel() throws {
        let info = try MediaInfo.parse(fixture("instagram-reel-info"))
        #expect(info.title == "Video by ornek_hesap")
        #expect(info.uploader == "Örnek Hesap")
        #expect(info.duration == 14.8)
        #expect(info.availableHeights == [1280, 960])
    }

    @Test func missingOptionalFields() throws {
        let data = Data(#"{"id":"abc","formats":[]}"#.utf8)
        let info = try MediaInfo.parse(data)
        #expect(info.title == "abc")
        #expect(info.uploader == nil)
        #expect(info.duration == nil)
        #expect(info.thumbnailURL == nil)
        #expect(info.availableHeights.isEmpty)
    }

    @Test func missingVcodecCountsAsVideoButStoryboardsDoNot() throws {
        let json = #"""
        {"id":"a","formats":[
          {"height":720},
          {"height":90,"ext":"mhtml","format_note":"storyboard"},
          {"height":45,"vcodec":"none"},
          {"height":480,"vcodec":"avc1"}]}
        """#
        let info = try MediaInfo.parse(Data(json.utf8))
        #expect(info.availableHeights == [720, 480])
    }

    @Test func invalidJSONThrows() {
        #expect(throws: (any Error).self) { try MediaInfo.parse(Data("not json".utf8)) }
    }

    @Test func estimatesVideoSizePreferringH264AndM4A() throws {
        let json = #"""
        {"id":"a","duration":100,"formats":[
          {"height":1080,"vcodec":"avc1.640028","acodec":"none","filesize":50000000},
          {"height":1080,"vcodec":"vp09.00.40.08","acodec":"none","filesize":40000000},
          {"height":720,"vcodec":"avc1.4d401f","acodec":"none","filesize_approx":20000000},
          {"height":2160,"vcodec":"vp09.00.51.08","acodec":"none","tbr":16000},
          {"vcodec":"none","acodec":"mp4a.40.2","filesize":3000000},
          {"vcodec":"none","acodec":"opus","filesize":2500000}
        ]}
        """#
        let info = try MediaInfo.parse(Data(json.utf8))
        #expect(info.estimatedVideoBytes(maxHeight: 1080) == 53_000_000)
        #expect(info.estimatedVideoBytes(maxHeight: 900) == 23_000_000)
        // boyut yoksa tbr (kbit/sn) × süre
        #expect(info.estimatedVideoBytes(maxHeight: 2160) == 203_000_000)
        #expect(info.estimatedVideoBytes(maxHeight: nil) == 203_000_000)
        #expect(info.estimatedVideoBytes(maxHeight: 360) == nil)
    }

    @Test func estimatesAudioSizeFromBitrateAndDuration() throws {
        let info = MediaInfo(title: "", uploader: nil, duration: 60, thumbnailURL: nil, availableHeights: [])
        #expect(info.estimatedAudioBytes(kbps: 192) == 1_440_000)
        let noDuration = MediaInfo(title: "", uploader: nil, duration: nil, thumbnailURL: nil, availableHeights: [])
        #expect(noDuration.estimatedAudioBytes(kbps: 192) == nil)
    }

    @Test func combinedFormatsCountOnce() throws {
        let json = #"""
        {"id":"a","duration":10,"formats":[{"height":640,"vcodec":"avc1","acodec":"mp4a","filesize":1000000}]}
        """#
        let info = try MediaInfo.parse(Data(json.utf8))
        #expect(info.estimatedVideoBytes(maxHeight: 640) == 1_000_000)
    }

    @Test func ignoresHLSCopiesWhenDirectDownloadExists() throws {
        let json = #"""
        {"id":"a","duration":100,"formats":[
          {"height":1080,"vcodec":"avc1.64002A","acodec":"none","protocol":"m3u8_native","tbr":7400},
          {"height":1080,"vcodec":"avc1.64002A","acodec":"none","protocol":"https","filesize":257000000},
          {"vcodec":"none","acodec":"mp4a.40.2","protocol":"https","filesize":30000000}
        ]}
        """#
        let info = try MediaInfo.parse(Data(json.utf8))
        #expect(info.estimatedVideoBytes(maxHeight: 1080) == 287_000_000)
    }

    @Test func verticalVideoIsNamedByShortSide() throws {
        let json = #"""
        {"id":"a","formats":[{"height":1920,"width":1080,"vcodec":"avc1"},{"height":1280,"width":720,"vcodec":"avc1"},{"height":1080,"width":1920,"vcodec":"avc1"}]}
        """#
        let info = try MediaInfo.parse(Data(json.utf8))
        #expect(info.qualityName(forHeight: 1920) == 1080)
        #expect(info.qualityName(forHeight: 1280) == 720)
        #expect(info.qualityName(forHeight: 1080) == 1080)
        #expect(info.qualityName(forHeight: 999) == 999)
    }

    @Test func remembersQualityClosestToLastChoice() {
        let info = MediaInfo(title: "t", uploader: nil, duration: nil, thumbnailURL: nil, availableHeights: [2160, 1080, 720, 480])
        #expect(info.height(closestTo: nil) == 2160)
        #expect(info.height(closestTo: 1080) == 1080)
        #expect(info.height(closestTo: 900) == 720)
        #expect(info.height(closestTo: 360) == 480)
    }
}
