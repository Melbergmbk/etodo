import Foundation
import CryptoKit
@testable import MedyaCore

/// GitHub'dan zip olarak inen bir aracın (deno) sahte yayını; kurulum mekanizması testleri için.
enum DenoRelease {
    static let api = "https://api.github.com/repos/denoland/deno/releases/latest"
    static func url(_ version: String) -> String { "https://dl.test/deno/\(version)/deno.zip" }

    static func publish(_ f: FakeFetcher, version: String, sumOverride: String? = nil) {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("mi-deno-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try! Data("binary-\(version)".utf8).write(to: work.appendingPathComponent("deno"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); p.arguments = ["-q", "d.zip", "deno"]; p.currentDirectoryURL = work
        try! p.run(); p.waitUntilExit()
        let data = try! Data(contentsOf: work.appendingPathComponent("d.zip"))
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        f.set(api, """
        {"tag_name":"\(version)","assets":[
         {"name":"deno-aarch64-apple-darwin.zip","browser_download_url":"\(url(version))"},
         {"name":"deno-aarch64-apple-darwin.zip.sha256sum","browser_download_url":"\(url(version)).sha256sum"}]}
        """)
        f.set(url(version), data)
        f.set(url(version) + ".sha256sum", "\(sumOverride ?? sha)  deno-aarch64-apple-darwin.zip\n")
    }

    /// unzip gerçekten çalışır; `deno --version` başarılı (verilen sürüm klasöründe başarısız).
    static func runner(failingVersion: String? = nil) -> HybridRunner {
        HybridRunner { u, a in
            let fails = failingVersion.map { u.path.contains("/\($0)/") } ?? false
            if u.lastPathComponent == "deno", a == ["--version"], !fails { return ProcessResult(exitCode: 0, stdout: "ok\n", stderr: "") }
            return ProcessResult(exitCode: 1, stdout: "", stderr: "no script")
        }
    }
}
