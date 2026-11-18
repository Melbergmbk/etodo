import Foundation

public enum ToolKind: String, CaseIterable, Sendable {
    case ytdlp, python, galleryDL, ffmpeg, deno

    public var displayName: String {
        switch self {
        case .ytdlp: "yt-dlp"
        case .python: "Python"
        case .galleryDL: "gallery-dl"
        case .ffmpeg: "ffmpeg"
        case .deno: "deno"
        }
    }

    /// Aracın indirildiği yer (kısa, kullanıcıya gösterilir).
    public var source: String {
        switch self {
        case .ytdlp: "github.com/yt-dlp"
        case .python: "github.com/astral-sh"
        case .galleryDL: "PyPI (pip)"
        case .ffmpeg: "ffmpeg.martin-riedl.de"
        case .deno: "github.com/denoland"
        }
    }
}

public struct ToolStatus: Sendable, Equatable {
    public var kind: ToolKind
    public var installedVersion: String?
    public var isReady: Bool
    public var source: String
    /// Son kurulumda SHA-256 doğrulandı mı (gallery-dl için: sağlık kontrolü geçti mi).
    public var verified: Bool
    /// Geri dönülebilecek saklanmış önceki sürüm var mı.
    public var hasPrevious: Bool

    public init(kind: ToolKind, installedVersion: String?, isReady: Bool, verified: Bool, hasPrevious: Bool = false) {
        self.kind = kind
        self.installedVersion = installedVersion
        self.isReady = isReady
        self.source = kind.source
        self.verified = verified
        self.hasPrevious = hasPrevious
    }
}

/// Sağlama toplamının nereden okunacağı.
enum Checksum: Sendable {
    /// `<hash>  <dosya adı>` satırları olan toplu liste
    case sums(URL, entry: String)
    /// Tek dosyanın sağlama toplamı dosyası (`<hash>  <ad>`)
    case single(URL)
}

enum Unpack: Sendable {
    case copy(as: String)
    /// install_only arşivinin tek üst klasörü `python/`
    case tarGzPython
    case zip
}

struct Artifact: Sendable {
    var url: URL
    var checksum: Checksum
    var unpack: Unpack
}

struct ReleaseSpec: Sendable {
    var version: String
    var artifacts: [Artifact]
}

enum ToolError: Error, Equatable {
    case checksumMismatch(String)
    case checksumMissing(String)
    case assetNotFound(String)
    case healthCheckFailed(String)
    case unpackFailed(String)
    /// Uzaktan gelen sürüm adı ya da adres güvenli değil
    case unsafeRelease(String)
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable { var name: String; var browser_download_url: URL }
    var tag_name: String
    var assets: [Asset]
}

extension ToolKind {
    /// Kurulumdan sonra imzalanacak ve sağlık kontrolü yapılacak yürütülebilirler (sürüm klasörüne göre).
    var executables: [String] {
        switch self {
        case .ytdlp: ["yt-dlp"]
        case .python: ["bin/python3"]
        case .ffmpeg: ["ffmpeg", "ffprobe"]
        case .deno: ["deno"]
        case .galleryDL: []
        }
    }

    var healthArguments: [String] { self == .ffmpeg ? ["-version"] : ["--version"] }

    // ffmpeg kaynağı: ffmpeg.martin-riedl.de — arm64 + amd64 statik sürüm derlemesi, her dosya için .sha256, sabit "redirect/latest" adresi.
    static let ffmpegBase = URL(string: "https://ffmpeg.martin-riedl.de")!

    private static func github(_ repo: String, fetcher: HTTPFetching) async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        return try JSONDecoder().decode(GitHubRelease.self, from: try await fetcher.data(from: url))
    }

    private static func asset(_ r: GitHubRelease, _ name: String) throws -> GitHubRelease.Asset {
        guard let a = r.assets.first(where: { $0.name == name }) else { throw ToolError.assetNotFound(name) }
        return a
    }

    /// Sürüm adı klasör adı olarak kullanılır; yol kaçışına izin vermez.
    static func isSafeVersion(_ v: String) -> Bool {
        v.range(of: #"^[A-Za-z0-9][A-Za-z0-9._+-]*$"#, options: .regularExpression) != nil && v != "current"
    }

    /// `.galleryDL` için çağrılmaz (pip ile kurulur).
    func resolve(arch: String, fetcher: HTTPFetching) async throws -> ReleaseSpec {
        let spec = try await fetchSpec(arch: arch, fetcher: fetcher)
        guard Self.isSafeVersion(spec.version) else { throw ToolError.unsafeRelease(spec.version) }
        return spec
    }

    private func fetchSpec(arch: String, fetcher: HTTPFetching) async throws -> ReleaseSpec {
        let gh = arch == "arm64" ? "aarch64" : "x86_64"
        switch self {
        case .ytdlp:
            let r = try await Self.github("yt-dlp/yt-dlp", fetcher: fetcher)
            let bin = try Self.asset(r, "yt-dlp_macos"), sums = try Self.asset(r, "SHA2-256SUMS")
            return ReleaseSpec(version: r.tag_name, artifacts: [
                Artifact(url: bin.browser_download_url, checksum: .sums(sums.browser_download_url, entry: bin.name), unpack: .copy(as: "yt-dlp"))])
        case .python:
            let r = try await Self.github("astral-sh/python-build-standalone", fetcher: fetcher)
            let pattern = #"^cpython-(3\.12\.\d+\+\d+)-\#(gh)-apple-darwin-install_only\.tar\.gz$"#
            guard let a = r.assets.first(where: { $0.name.range(of: pattern, options: .regularExpression) != nil }) else {
                throw ToolError.assetNotFound("cpython-3.12.* \(gh)")
            }
            let sums = try Self.asset(r, "SHA256SUMS")
            let version = String(a.name.dropFirst("cpython-".count).prefix { $0 != "-" })
            return ReleaseSpec(version: version, artifacts: [
                Artifact(url: a.browser_download_url, checksum: .sums(sums.browser_download_url, entry: a.name), unpack: .tarGzPython)])
        case .deno:
            let r = try await Self.github("denoland/deno", fetcher: fetcher)
            let zip = try Self.asset(r, "deno-\(gh)-apple-darwin.zip")
            let sum = try Self.asset(r, "deno-\(gh)-apple-darwin.zip.sha256sum")
            return ReleaseSpec(version: r.tag_name, artifacts: [
                Artifact(url: zip.browser_download_url, checksum: .single(sum.browser_download_url), unpack: .zip)])
        case .ffmpeg:
            let a = arch == "arm64" ? "arm64" : "amd64"
            let latest = Self.ffmpegBase.appendingPathComponent("redirect/latest/macos/\(a)/release/ffmpeg.zip")
            let final = try await fetcher.finalURL(of: latest)
            guard final.scheme == "https", final.host == Self.ffmpegBase.host else { throw ToolError.unsafeRelease(final.absoluteString) }
            let dir = final.deletingLastPathComponent()
            let version = dir.lastPathComponent
            func artifact(_ name: String) -> Artifact {
                let u = dir.appendingPathComponent("\(name).zip")
                return Artifact(url: u, checksum: .single(u.appendingPathExtension("sha256")), unpack: .zip)
            }
            return ReleaseSpec(version: version, artifacts: [artifact("ffmpeg"), artifact("ffprobe")])
        case .galleryDL:
            throw ToolError.assetNotFound("galleryDL")
        }
    }
}
