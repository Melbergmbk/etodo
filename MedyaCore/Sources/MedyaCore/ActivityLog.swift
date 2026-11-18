import Foundation

public struct ActivityEntry: Codable, Sendable, Equatable {
    public var date: Date
    public var message: String
}

/// Kurulum, güncelleme, geri dönme ve indirme bitişlerinin kısa kaydı (son 50).
/// Kişisel veri yazılmaz: link yok, yalnız araç sürümleri ve dosya adları.
public actor ActivityLog {
    public static let limit = 50
    private let file: URL
    private var items: [ActivityEntry]

    public init(file: URL) {
        self.file = file
        let data = try? Data(contentsOf: file)
        items = data.flatMap { try? Self.decoder.decode([ActivityEntry].self, from: $0) } ?? []
    }

    public func append(_ message: String) {
        items.append(ActivityEntry(date: Date(), message: message))
        if items.count > Self.limit { items.removeFirst(items.count - Self.limit) }
        guard let data = try? Self.encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// Eskiden yeniye.
    public func entries() -> [ActivityEntry] { items }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
