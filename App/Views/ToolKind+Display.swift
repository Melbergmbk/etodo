import MedyaCore

extension ToolKind {
    /// Ayarlar ve kurulum ekranındaki sıra (taslaktaki gibi).
    static let displayOrder: [ToolKind] = [.ytdlp, .galleryDL, .python, .ffmpeg, .deno]

    var title: String { self == .ffmpeg ? "ffmpeg / ffprobe" : displayName }

    var purpose: String {
        switch self {
        case .ytdlp: "video ve ses indirici"
        case .galleryDL: "Instagram fotoğraf/galeri"
        case .python: "yt-dlp ve gallery-dl'in çalışma ortamı"
        case .ffmpeg: "görüntü + ses birleştirme"
        case .deno: "YouTube doğrulama testleri"
        }
    }

    /// Klasör adı olarak saklanan sürümü okunur hâle getirir ("3.12.7+20241002" → "3.12.7", "1730_7.1" → "7.1").
    func readableVersion(_ raw: String) -> String {
        switch self {
        case .python: String(raw.prefix { $0 != "+" })
        case .ffmpeg: raw.split(separator: "_").last.map(String.init) ?? raw
        case .deno: raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        default: raw
        }
    }
}
