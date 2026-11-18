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

    @Test func invalidJSONThrows() {
        #expect(throws: (any Error).self) { try MediaInfo.parse(Data("not json".utf8)) }
    }
}
