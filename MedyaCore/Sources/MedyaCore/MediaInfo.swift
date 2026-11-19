import Foundation

public struct MediaInfo: Sendable, Equatable {
    public var title: String
    public var uploader: String?
    public var duration: TimeInterval?
    public var thumbnailURL: URL?
    public var availableHeights: [Int]
    var streams: [Stream]

    struct Stream: Sendable, Equatable {
        var height: Int?
        var width: Int? = nil
        var vcodec: String?
        var acodec: String?
        var bytes: Int64?
        var isHLS = false
    }

    public init(title: String, uploader: String?, duration: TimeInterval?, thumbnailURL: URL?, availableHeights: [Int]) {
        self.init(title: title, uploader: uploader, duration: duration, thumbnailURL: thumbnailURL,
                  availableHeights: availableHeights, streams: [])
    }

    init(title: String, uploader: String?, duration: TimeInterval?, thumbnailURL: URL?, availableHeights: [Int], streams: [Stream]) {
        self.title = title
        self.uploader = uploader
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.availableHeights = availableHeights
        self.streams = streams
    }

    /// İndirilecek dosyanın yaklaşık boyutu. CommandBuilder'daki seçimi taklit eder:
    /// sınırın altındaki en yüksek çözünürlük, mümkünse H.264 görüntü + M4A ses.
    public func estimatedVideoBytes(maxHeight: Int?) -> Int64? {
        let videos = streams.filter { ($0.height ?? 0) > 0 && $0.vcodec != "none" && $0.height! <= (maxHeight ?? .max) }
        guard let top = videos.map({ $0.height! }).max() else { return nil }
        guard let video = Self.pick(videos.filter { $0.height == top }, preferring: { $0.vcodec?.hasPrefix("avc1") == true }),
              let videoBytes = video.bytes else { return nil }
        if let a = video.acodec, a != "none" { return videoBytes }
        let audios = streams.filter { $0.vcodec == "none" && $0.acodec != nil && $0.acodec != "none" }
        let audio = Self.pick(audios, preferring: { $0.acodec?.hasPrefix("mp4a") == true })
        return videoBytes + (audio?.bytes ?? 0)
    }

    /// Seçilecek görüntü akışı QuickTime'ın açabildiği H.264/HEVC mi? 1440p ve 4K YouTube genelde VP9/AV1'dir.
    /// Codec bilinmiyorsa (akış bilgisi yok) uyarı gösterilmesin diye true döner.
    public func opensInQuickTime(maxHeight: Int?) -> Bool {
        let videos = streams.filter { ($0.height ?? 0) > 0 && $0.vcodec != "none" && $0.height! <= (maxHeight ?? .max) }
        guard let top = videos.map({ $0.height! }).max(),
              let video = Self.pick(videos.filter { $0.height == top }, preferring: { $0.vcodec?.hasPrefix("avc1") == true }),
              let codec = video.vcodec?.lowercased() else { return true }
        return ["avc", "h264", "hvc", "hev", "h265"].contains { codec.hasPrefix($0) }
    }

    /// Kalite adı kısa kenara göre: dikey 1080×1920 bir Short "1920p" değil "1080p" görünür.
    public func qualityName(forHeight h: Int) -> Int {
        let widths = streams.filter { $0.height == h }.compactMap(\.width)
        guard let w = widths.max(), w > 0 else { return h }
        return min(w, h)
    }

    /// MP3 sabit bit hızıyla kodlanır: kbit/sn × süre.
    public func estimatedAudioBytes(kbps: Int) -> Int64? {
        duration.map { Int64(Double(kbps) * 125 * $0) }
    }

    private static func pick(_ candidates: [Stream], preferring: (Stream) -> Bool) -> Stream? {
        // yt-dlp doğrudan indirmeyi (https) akış parçalarına (m3u8) tercih eder.
        let direct = candidates.filter { !$0.isHLS }
        let candidates = direct.isEmpty ? candidates : direct
        let preferred = candidates.filter(preferring)
        return (preferred.isEmpty ? candidates : preferred).max { ($0.bytes ?? 0) < ($1.bytes ?? 0) }
    }

    private struct Raw: Decodable {
        struct Format: Decodable {
            var height: Int?
            var width: Int?
            var vcodec: String?
            var acodec: String?
            var filesize: Double?
            var filesize_approx: Double?
            var tbr: Double?
            var `protocol`: String?
            var ext: String?
            var format_note: String?
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
            guard let h = f.height, h > 0, f.vcodec != "none" else { return nil }
            if f.ext == "mhtml" || f.format_note?.lowercased().contains("storyboard") == true { return nil }
            return h
        }
        let streams = (raw.formats ?? []).compactMap { f -> Stream? in
            if f.ext == "mhtml" || f.format_note?.lowercased().contains("storyboard") == true { return nil }
            // Boyut bilinmiyorsa ortalama bit hızı (kbit/sn) × süre
            let bytes = f.filesize ?? f.filesize_approx ?? zip(f.tbr, raw.duration).map { $0 * 125 * $1 }
            return Stream(height: f.height, width: f.width, vcodec: f.vcodec, acodec: f.acodec, bytes: bytes.map { Int64($0) },
                          isHLS: f.protocol?.contains("m3u8") == true)
        }
        return MediaInfo(
            title: raw.title ?? raw.id ?? "",
            uploader: raw.uploader,
            duration: raw.duration,
            thumbnailURL: raw.thumbnail.flatMap(URL.init(string:)),
            availableHeights: Array(Set(heights)).sorted(by: >),
            streams: streams)
    }
}

private func zip(_ a: Double?, _ b: Double?) -> (Double, Double)? {
    guard let a, let b else { return nil }
    return (a, b)
}

public extension MediaInfo {
    /// Kullanıcının son seçtiği kaliteye en yakın seçenek: onu aşmayan en yüksek, yoksa en düşük; tercih yoksa en iyisi.
    func height(closestTo preferred: Int?) -> Int? {
        guard let preferred else { return availableHeights.max() }
        return availableHeights.filter { $0 <= preferred }.max() ?? availableHeights.min()
    }
}
