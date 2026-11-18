import Testing
@testable import MedyaCore

@Suite struct UserFacingErrorTests {
    func classify(_ s: String, _ b: Browser = .chrome) -> UserFacingError {
        UserFacingError.classify(stderr: s, browser: b)
    }

    @Test func instagramLogin() {
        let s = "ERROR: [Instagram] C7x: Requested content is not available, rate-limit reached or login required. Use --cookies-from-browser or --cookies for the authentication."
        #expect(classify(s, .chrome) == .instagramLoginRequired(.chrome))
        #expect(classify("ERROR: [instagram] C7x: Instagram API is not granting access: login required", .safari)
                == .instagramLoginRequired(.safari))
    }

    @Test func instagramMessageNamesBrowserWithSuffix() {
        #expect(UserFacingError.instagramLoginRequired(.chrome).message.contains("Chrome'da"))
        #expect(UserFacingError.instagramLoginRequired(.safari).message.contains("Safari'de"))
        #expect(UserFacingError.instagramLoginRequired(.firefox).message.contains("Firefox'ta"))
        #expect(UserFacingError.instagramLoginRequired(.brave).message.contains("Brave'de"))
        #expect(UserFacingError.instagramLoginRequired(.edge).message.contains("Edge'de"))
    }

    @Test func privateOrDeleted() {
        #expect(classify("ERROR: [youtube] abc: Private video. Sign in if you've been granted access to this video") == .privateOrDeleted)
        #expect(classify("ERROR: Unable to download JSON metadata: HTTP Error 404: Not Found") == .privateOrDeleted)
    }

    @Test func needsToolUpdate() {
        #expect(classify("ERROR: unable to download video data: HTTP Error 403: Forbidden") == .needsToolUpdate)
        #expect(classify("ERROR: [youtube] abc: Sign in to confirm you're not a bot") == .needsToolUpdate)
        #expect(classify("WARNING: [youtube] nsig extraction failed: Some formats may be missing") == .needsToolUpdate)
    }

    @Test func noInternet() {
        let s = "ERROR: [youtube] abc: Unable to download webpage: <urlopen error [Errno 8] nodename nor servname provided, or not known>"
        #expect(classify(s) == .noInternet)
    }

    @Test func safariFullDiskAccess() {
        let s = "PermissionError: [Errno 1] Operation not permitted: '/Users/x/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'"
        #expect(classify(s, .safari) == .safariNeedsFullDiskAccess)
    }

    @Test func browserCookies() {
        #expect(classify("ERROR: could not find brave cookies database in \"/Users/x/Library/Application Support/BraveSoftware\"", .brave)
                == .browserCookiesUnavailable(.brave))
    }

    @Test func unsupportedLink() {
        #expect(classify("ERROR: Unsupported URL: https://example.com/foo") == .unsupportedLink)
    }

    @Test func unknownKeepsDetails() {
        let e = classify("  something odd happened \n")
        #expect(e == .unknown(details: "something odd happened"))
        #expect(e.details == "something odd happened")
        #expect(UserFacingError.noInternet.details == nil)
    }

    @Test func privatePathsAnd404SubstringsAreNotPrivateErrors() {
        #expect(classify("ERROR: something broke in /private/var/folders/x/T/tmp") == .unknown(details: "ERROR: something broke in /private/var/folders/x/T/tmp"))
        #expect(classify("ERROR: bad item 14040 of list") == .unknown(details: "ERROR: bad item 14040 of list"))
        #expect(classify("ERROR: [youtube] abc: Video unavailable") == .privateOrDeleted)
    }

    @Test func loginRequiredOnlyForInstagram() {
        #expect(classify("ERROR: [twitter] 123: login required") != .instagramLoginRequired(.chrome))
        #expect(classify("ERROR: [twitter] 123: rate-limit reached") != .instagramLoginRequired(.chrome))
    }

    @Test(arguments: [
        "Unable to download JSON metadata: [Errno 51] Network is unreachable",
        "Unable to download video data: <urlopen error [Errno 65] No route to host>",
        "ERROR: Unable to download webpage: The read operation timed out",
        "ERROR: unable to download video data: <urlopen error [Errno 8] nodename nor servname provided>",
    ])
    func noInternetVariants(_ s: String) {
        #expect(classify(s) == .noInternet)
    }

    @Test func caseInsensitive() {
        #expect(classify("UNSUPPORTED url: x") == .unsupportedLink)
    }

    @Test func messagesAreTurkishAndNonEmpty() {
        let all: [UserFacingError] = [
            .instagramLoginRequired(.chrome), .privateOrDeleted, .needsToolUpdate, .noInternet,
            .destinationNotWritable, .safariNeedsFullDiskAccess, .browserCookiesUnavailable(.edge),
            .unsupportedLink, .unknown(details: "x"),
        ]
        for e in all { #expect(!e.message.isEmpty) }
        #expect(UserFacingError.privateOrDeleted.message == "Bu gönderi görünmüyor; özel hesap ya da silinmiş olabilir.")
        #expect(UserFacingError.safariNeedsFullDiskAccess.message.contains("Tam Disk Erişimi"))
    }
}
