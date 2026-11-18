import Foundation

public enum Site: String, CaseIterable, Sendable {
    case youtube, instagram, other

    public static func detect(_ raw: String) -> Site? {
        guard let url = normalizedURL(raw), let host = url.host?.lowercased() else { return nil }
        if matches(host, "youtube.com") || host == "youtu.be" { return .youtube }
        if matches(host, "instagram.com") { return .instagram }
        return .other
    }

    public static func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = URLComponents(string: trimmed)
            ?? trimmed.addingPercentEncoding(withAllowedCharacters: encodingAllowed).flatMap(URLComponents.init(string:))
        guard var components = parsed,
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        if let items = components.percentEncodedQueryItems {
            let kept = items.filter { !isTracking($0.name.removingPercentEncoding ?? $0.name) }
            if kept.count != items.count {
                components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
            }
        }
        return components.url
    }

    public static func isInstagramPost(_ url: URL) -> Bool {
        guard let first = url.pathComponents.dropFirst().first?.lowercased() else { return false }
        return ["p", "reel", "reels", "tv"].contains(first)
    }

    private static let encodingAllowed: CharacterSet = {
        var set = CharacterSet.urlFragmentAllowed
        set.formUnion(.urlQueryAllowed)
        set.insert("%")
        return set
    }()

    private static func matches(_ host: String, _ domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func isTracking(_ name: String) -> Bool {
        let n = name.lowercased()
        return n == "igsh" || n == "si" || n.hasPrefix("utm_")
    }
}
