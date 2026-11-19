import Testing
import Foundation
@testable import MedyaCore

@Suite struct DownloadHistoryTests {
    func record(_ n: Int) -> DownloadRecord {
        DownloadRecord(title: "Video \(n)", detail: "1080p", link: "https://youtu.be/\(n)", site: .youtube,
                       format: .video(maxHeight: 1080), subtitles: n % 2 == 0, files: ["/tmp/\(n).mp4"])
    }

    @Test func newestFirstAndCappedAtTwenty() {
        var list: [DownloadRecord] = []
        for n in 1...25 { list = DownloadHistory.adding(record(n), to: list) }
        #expect(list.count == 20)
        #expect(list.first?.title == "Video 25")
        #expect(list.last?.title == "Video 6")
    }

    @Test func downloadingTheSameThingAgainKeepsOneRow() {
        var list = DownloadHistory.adding(record(1), to: [])
        list = DownloadHistory.adding(record(2), to: list)
        list = DownloadHistory.adding(record(1), to: list)
        #expect(list.map(\.title) == ["Video 1", "Video 2"])
        var mp3 = record(1)
        mp3.format = .audio(kbps: 192)
        #expect(DownloadHistory.adding(mp3, to: list).count == 3)
    }

    @Test func roundTripsAllFormats() {
        let list = [record(1),
                    DownloadRecord(title: "Ses", detail: "MP3", link: "x", site: .other, format: .audio(kbps: 192), subtitles: false, files: []),
                    DownloadRecord(title: "Foto", detail: "Orijinal", link: "y", site: .instagram, format: .images, subtitles: false, files: ["/a.jpg", "/b.jpg"]),
                    DownloadRecord(title: "En iyi", detail: "", link: "z", site: .youtube, format: .video(maxHeight: nil), subtitles: true, files: [])]
        #expect(DownloadHistory.decode(DownloadHistory.encode(list)) == list)
    }

    @Test func garbageDecodesToEmpty() {
        #expect(DownloadHistory.decode(Data("bozuk".utf8)).isEmpty)
        #expect(DownloadHistory.decode(nil).isEmpty)
    }
}
