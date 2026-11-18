import Foundation

public enum UserFacingError: Error, Equatable, Sendable {
    case instagramLoginRequired(Browser)
    case privateOrDeleted
    case needsToolUpdate
    case noInternet
    case destinationNotWritable
    case safariNeedsFullDiskAccess
    case browserCookiesUnavailable(Browser)
    case unsupportedLink
    case unknown(details: String)

    public var message: String {
        switch self {
        case .instagramLoginRequired(let b):
            "Instagram'dan indirmek için \(b.locative) Instagram hesabına giriş yapmış olmalısın."
        case .privateOrDeleted:
            "Bu gönderi görünmüyor; özel hesap ya da silinmiş olabilir."
        case .needsToolUpdate:
            "İndirme aracı bu siteyle uyumsuz kalmış görünüyor. Araçları güncelleyip tekrar dene."
        case .noInternet:
            "İnternet bağlantısı yok gibi görünüyor. Bağlantını kontrol edip tekrar dene."
        case .destinationNotWritable:
            "Seçtiğin klasöre kayıt yapılamıyor. Klasör silinmiş ya da yazma iznin yok; başka bir klasör seç."
        case .safariNeedsFullDiskAccess:
            "Safari'nin çerezlerini okuyabilmek için \(AppIdentity.displayName) uygulamasına Tam Disk Erişimi vermen gerekiyor. Sistem Ayarları > Gizlilik ve Güvenlik > Tam Disk Erişimi bölümünden uygulamayı aç, sonra uygulamayı kapatıp yeniden başlat."
        case .browserCookiesUnavailable(let b):
            "\(b.displayName) çerezleri okunamadı. \(b.displayName) kurulu olmalı ve en az bir kez açılmış olmalı; olmuyorsa Ayarlar'dan başka bir tarayıcı seç."
        case .unsupportedLink:
            "Bu bağlantı desteklenmiyor. Videonun ya da gönderinin doğrudan linkini yapıştırmayı dene."
        case .unknown:
            "Beklenmeyen bir sorun oluştu. \"Ayrıntıları göster\" ile hata metnini kopyalayıp iletebilirsin."
        }
    }

    public var details: String? {
        if case .unknown(let d) = self { return d }
        return nil
    }

    public static func classify(stderr: String, browser: Browser) -> UserFacingError {
        let text = stderr.lowercased()
        func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }

        if has("operation not permitted") && has("cookies.binarycookies") { return .safariNeedsFullDiskAccess }
        if text.range(of: #"could not find .* cookies database"#, options: .regularExpression) != nil {
            return .browserCookiesUnavailable(browser)
        }
        if has("unable to download webpage") && has("errno 8", "nodename nor servname") { return .noInternet }
        if has("unsupported url") { return .unsupportedLink }
        if has("login required", "rate-limit reached") || (has("requested content is not available") && has("instagram")) {
            return .instagramLoginRequired(browser)
        }
        if has("http error 403", "sign in to confirm", "nsig extraction failed") { return .needsToolUpdate }
        if has("private", "404") { return .privateOrDeleted }
        return .unknown(details: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension Browser {
    /// Türkçe bulunma eki ("Chrome'da"); ünlü uyumu tarayıcı adının okunuşuna göre elle verilir.
    var locative: String {
        switch self {
        case .chrome: "Chrome'da"
        case .safari: "Safari'de"
        case .brave: "Brave'de"
        case .firefox: "Firefox'ta"
        case .edge: "Edge'de"
        }
    }
}
