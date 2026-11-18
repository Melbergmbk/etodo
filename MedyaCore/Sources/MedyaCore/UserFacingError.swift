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
    case cancelled
    case noPreviousVersion
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
            "Safari'deki girişini kullanabilmek için \(AppIdentity.displayName) uygulamasına bir kez Tam Disk Erişimi vermen gerekiyor."
        case .browserCookiesUnavailable(let b):
            "Bu bağlantı için \(b.locative)ki girişin gerekiyor, ama macOS buna izin vermedi. \(AppIdentity.displayName) uygulamasına bir kez Tam Disk Erişimi vermen yeterli."
        case .unsupportedLink:
            "Bu bağlantı desteklenmiyor. Videonun ya da gönderinin doğrudan linkini yapıştırmayı dene."
        case .cancelled:
            "İndirme iptal edildi."
        case .noPreviousVersion:
            "Bu aracın saklanmış önceki sürümü yok. Önceki sürüm, araç ilk kez güncellendiğinde saklanır."
        case .unknown:
            "Beklenmeyen bir sorun oluştu. \"Ayrıntıları göster\" ile hata metnini kopyalayıp iletebilirsin."
        }
    }

    /// Kullanıcının Tam Disk Erişimi vermesiyle çözülen hatalar ("Ayarları Aç" düğmesi için).
    public var needsFullDiskAccess: Bool {
        switch self {
        case .safariNeedsFullDiskAccess, .browserCookiesUnavailable: true
        default: false
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
        if text.range(of: #"(could not|unable to) find .* cookies database"#, options: .regularExpression) != nil {
            return .browserCookiesUnavailable(browser)
        }
        if has("unable to download") && has("errno 8", "nodename nor servname", "errno 51", "network is unreachable", "errno 65", "no route to host", "timed out") { return .noInternet }
        if has("unsupported url") { return .unsupportedLink }
        if has("instagram") && has("login required", "rate-limit reached", "requested content is not available", "redirect to login page") {
            return .instagramLoginRequired(browser)
        }
        if has("http error 403", "sign in to confirm", "nsig extraction failed") { return .needsToolUpdate }
        if has("private video", "http error 404", "video unavailable") { return .privateOrDeleted }
        return .unknown(details: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public extension Browser {
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
