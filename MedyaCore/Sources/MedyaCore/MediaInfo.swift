import Foundation

public struct MediaInfo: Sendable, Equatable {
    public var title: String
    public var uploader: String?
    public var duration: TimeInterval?
    public var thumbnailURL: URL?
    public var availableHeights: [Int]

    public init(title: String, uploader: String?, duration: TimeInterval?, thumbnailURL: URL?, availableHeights: [Int]) {
        self.title = title
        self.uploader = uploader
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.availableHeights = availableHeights
    }

    private struct Raw: Decodable {
        struct Format: Decodable {
            var height: Int?
            var vcodec: String?
        }
        var id: String?
        var title: String?
        var uploader: String?
        var duration: Double?
        var thumbnail: String?
        var formats: [Format]?
    }

    public static func parse(_ data: Data) throws -> MediaInfo {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        // vcodec "none" ses akışı ve storyboard (önizleme şeridi) kayıtlarını eler
        let heights = (raw.formats ?? []).compactMap { f -> Int? in
            guard let h = f.height, h > 0, let codec = f.vcodec, codec != "none" else { return nil }
            return h
        }
        return MediaInfo(
            title: raw.title ?? raw.id ?? "",
            uploader: raw.uploader,
            duration: raw.duration,
            thumbnailURL: raw.thumbnail.flatMap(URL.init(string:)),
            availableHeights: Array(Set(heights)).sorted(by: >))
    }
}
