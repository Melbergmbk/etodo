import Foundation

public enum Platform: Equatable, Sendable {
    case youtube, instagram, x, tiktok
    case other(host: String)

    public init(url: URL, site: Site) {
        let host = (url.host ?? "").lowercased()
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        switch site {
        case .youtube: self = .youtube
        case .instagram: self = .instagram
        case .other:
            if matches("x.com") || matches("twitter.com") { self = .x }
            else if matches("tiktok.com") { self = .tiktok }
            else { self = .other(host: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) }
        }
    }

    /// Etodo kökünün altındaki ilk klasör(ler); diğer sitelerde "Diğer/<site>".
    public var folder: String {
        switch self {
        case .youtube: "YouTube"
        case .instagram: "Instagram"
        case .x: "X (Twitter)"
        case .tiktok: "TikTok"
        case .other(let host): "Diğer/\(host)"
        }
    }
}

/// Spec §14: <kök>/Etodo/<Platform>/<kanal>/<tür>/dosya
public enum FolderLayout {
    public static let unknown = "Bilinmeyen"
    static let fileTemplate = "%(title).150B [%(id)s].%(ext)s"

    public static func root(in parent: URL) -> URL {
        parent.appendingPathComponent(AppIdentity.folderName, isDirectory: true)
    }

    public static func kindFolder(url: URL, platform: Platform, format: MediaFormat) -> String {
        if case .audio = format { return "Sesler" }
        let first = url.pathComponents.dropFirst().first?.lowercased() ?? ""
        switch platform {
        case .youtube: return first == "shorts" ? "Shorts" : "Videolar"
        case .instagram:
            switch first {
            case "reel", "reels": return "Reels"
            case "stories": return "Hikâyeler"
            default: return "Gönderiler"
            }
        case .x: return "Gönderiler"
        case .tiktok, .other: return "Videolar"
        }
    }

    /// yt-dlp alan adları extractor kaynağından doğrulandı (rapora bakın):
    /// Instagram `channel` = kullanıcı adı, X `uploader_id` = screen_name, TikTok `uploader` = unique_id.
    /// `&@{}` yalnız değer varsa "@" ekler; yoksa `|Bilinmeyen` düz kalır ("@Bilinmeyen" olmaz).
    static func channelTemplate(_ platform: Platform) -> String {
        switch platform {
        case .youtube: "%(channel,uploader|\(unknown))s"
        case .instagram: "%(channel&@{}|\(unknown))s"
        case .x: "%(uploader_id&@{}|\(unknown))s"
        case .tiktok: "%(uploader&@{}|\(unknown))s"
        case .other: "%(uploader,channel|\(unknown))s"
        }
    }

    public static func ytdlpOutputTemplate(_ r: DownloadRequest) -> String {
        let platform = Platform(url: r.url, site: r.site)
        let kind = kindFolder(url: r.url, platform: platform, format: r.format)
        return [platform.folder, channelTemplate(platform), kind, fileTemplate].joined(separator: "/")
    }

    /// Instagram gönderileri (/p/) karışık galeri olabileceği için doğrudan gallery-dl ile; MP3 isteği yt-dlp'de kalır.
    public static func usesGalleryDL(_ r: DownloadRequest) -> Bool {
        switch r.format {
        case .images: return true
        case .audio: return false
        case .video:
            let first = r.url.pathComponents.dropFirst().first?.lowercased()
            return r.site == .instagram && first == "p"
        }
    }

    /// gallery-dl `directory` seçeneği (koşullu biçim, JSON). Koşullar sırayla denenir; "" varsayılandır.
    public static func galleryDLDirectory(_ r: DownloadRequest) -> String {
        let platform = Platform(url: r.url, site: r.site)
        let base = platform.folder.split(separator: "/").map(String.init)
        let kind = kindFolder(url: r.url, platform: platform, format: r.format)
        let entries: [(String, [String])]
        switch platform {
        case .instagram:
            let dated = "{post_date:%Y-%m-%d} · {post_shortcode}"
            entries = [
                ("username and count > 1", base + ["@{username}", kind, dated]),
                ("username", base + ["@{username}", kind]),
                ("count > 1", base + [unknown, kind, dated]),
                ("", base + [unknown, kind]),
            ]
        case .x:
            entries = [
                ("author['name']", base + ["@{author[name]}", "Gönderiler"]),
                ("", base + [unknown, "Gönderiler"]),
            ]
        default:
            entries = [("", base + [unknown, "Gönderiler"])]
        }
        return "{" + entries.map { "\(jsonString($0.0)):[\($0.1.map(jsonString).joined(separator: ","))]" }
            .joined(separator: ",") + "}"
    }

    /// Eski sürüm kayıt yerini doğrudan dosyaların klasörü olarak saklıyordu (varsayılan ~/Downloads/MedyaIndirici);
    /// artık ayar Etodo klasörünün üst klasörüdür.
    public static func parentFolder(stored: String?, fallback: URL) -> URL {
        guard let stored, !stored.isEmpty else { return fallback }
        let url = URL(fileURLWithPath: stored, isDirectory: true)
        if ["MedyaIndirici", AppIdentity.folderName].contains(url.lastPathComponent) {
            return url.deletingLastPathComponent()
        }
        return url
    }

    private static func jsonString(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }
}
