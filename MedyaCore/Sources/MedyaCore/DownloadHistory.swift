import Foundation

/// Biten bir indirme. Yalnız bu Mac'te saklanır; "Tekrar indir" için link de tutulur.
public struct DownloadRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    /// "1080p", "MP3 · 192 kbps", "Orijinal kalite" gibi kısa açıklama.
    public var detail: String
    public var link: String
    public var site: Site
    public var format: MediaFormat
    public var subtitles: Bool
    public var files: [String]
    public var finishedAt: Date

    public init(id: UUID = UUID(), title: String, detail: String, link: String, site: Site, format: MediaFormat,
                subtitles: Bool, files: [String], finishedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.detail = detail
        self.link = link
        self.site = site
        self.format = format
        self.subtitles = subtitles
        self.files = files
        self.finishedAt = finishedAt
    }
}

public enum DownloadHistory {
    public static let limit = 20

    /// Yenisi başa eklenir; aynı link aynı biçimle yeniden indirildiyse eski satır kalkar. En fazla `limit` kayıt kalır.
    public static func adding(_ record: DownloadRecord, to list: [DownloadRecord]) -> [DownloadRecord] {
        let rest = list.filter { $0.id != record.id && !($0.link == record.link && $0.format == record.format) }
        return Array(([record] + rest).prefix(limit))
    }

    /// Bozuk ya da eski biçimli kayıt geçmişi sessizce boş sayılır.
    public static func decode(_ data: Data?) -> [DownloadRecord] {
        guard let data, let list = try? JSONDecoder().decode([DownloadRecord].self, from: data) else { return [] }
        return Array(list.prefix(limit))
    }

    public static func encode(_ list: [DownloadRecord]) -> Data {
        (try? JSONEncoder().encode(list)) ?? Data()
    }
}
