import Foundation

public enum Browser: String, CaseIterable, Sendable {
    case chrome, safari, brave, firefox, edge

    public var displayName: String {
        switch self {
        case .chrome: "Chrome"
        case .safari: "Safari"
        case .brave: "Brave"
        case .firefox: "Firefox"
        case .edge: "Edge"
        }
    }
}

public enum MediaFormat: Hashable, Sendable {
    case video(maxHeight: Int?)
    case audio(kbps: Int)
    case images
}

public struct DownloadRequest: Sendable {
    public var url: URL
    public var site: Site
    public var format: MediaFormat
    public var destination: URL
    public var browser: Browser

    public init(url: URL, site: Site, format: MediaFormat, destination: URL, browser: Browser) {
        self.url = url
        self.site = site
        self.format = format
        self.destination = destination
        self.browser = browser
    }
}

public struct ToolPaths: Sendable {
    public var ytdlp: URL
    public var galleryDL: URL
    public var ffmpegDir: URL
    public var deno: URL

    public init(ytdlp: URL, galleryDL: URL, ffmpegDir: URL, deno: URL) {
        self.ytdlp = ytdlp
        self.galleryDL = galleryDL
        self.ffmpegDir = ffmpegDir
        self.deno = deno
    }
}
