import Foundation
import CryptoKit

/// Bir aracın tek sürümünü indirir, doğrular, açar, imzalar, sağlık kontrolünden geçirir ve etkinleştirir.
struct ToolInstaller: Sendable {
    let root: URL
    let fetcher: HTTPFetching
    let runner: ProcessRunning

    var toolsDir: URL { root.appendingPathComponent("tools", isDirectory: true) }
    func kindDir(_ k: ToolKind) -> URL { toolsDir.appendingPathComponent(k.rawValue, isDirectory: true) }
    func currentLink(_ k: ToolKind) -> URL { kindDir(k).appendingPathComponent("current") }

    /// SHA-256 doğrulamasından geçen sürüm klasörüne bırakılan işaret.
    static let verifiedMarker = ".sha256-verified"

    func isVerified(_ k: ToolKind, version: String) -> Bool {
        FileManager.default.fileExists(atPath: kindDir(k).appendingPathComponent(version).appendingPathComponent(Self.verifiedMarker).path)
    }

    /// `current` dışında saklanan sürüm (en fazla bir tane kalır).
    func keptVersion(_ k: ToolKind) -> String? {
        let current = currentVersion(k)
        let items = (try? FileManager.default.contentsOfDirectory(atPath: kindDir(k).path)) ?? []
        return items.filter { $0 != "current" && !$0.hasPrefix(".") && $0 != current }.sorted().last
    }

    func currentVersion(_ k: ToolKind) -> String? {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: currentLink(k).path) else { return nil }
        return URL(fileURLWithPath: dest).lastPathComponent
    }

    /// Sürümü hazırlar (indir, doğrula, aç, imzala, sağlık kontrolü) ama etkinleştirmez.
    /// `true`: `commit` ile etkinleştirilmeli; `false`: zaten güncel.
    /// `extraCheck`: etkinleştirmeden önce sürüm klasörüne uygulanan ek hazırlık/sağlık adımı (hata fırlatırsa kurulum iptal olur).
    func prepare(_ kind: ToolKind, spec: ReleaseSpec, progress: @escaping @Sendable (Double) -> Void,
                 extraCheck: (@Sendable (URL) async throws -> Void)? = nil) async throws -> Bool {
        guard ToolKind.isSafeVersion(spec.version) else { throw ToolError.unsafeRelease(spec.version) }
        if currentVersion(kind) == spec.version { return false }
        let fm = FileManager.default
        let versionDir = kindDir(kind).appendingPathComponent(spec.version, isDirectory: true)

        // Saklanan önceki sürüme dönülüyorsa klasörü silmeden sağlığına bak.
        if fm.fileExists(atPath: versionDir.path) {
            if (try? await check(kind, versionDir, extraCheck)) != nil { return true }
            try? fm.removeItem(at: versionDir)
        }

        let staging = toolsDir.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let out = staging.appendingPathComponent("out", isDirectory: true)
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let count = Double(spec.artifacts.count)
        for (i, a) in spec.artifacts.enumerated() {
            let file = staging.appendingPathComponent("dl\(i)")
            let base = Double(i)
            try await fetcher.download(from: a.url, to: file) { progress((base + $0) / count) }
            try await verify(file, a)
            try await unpack(a.unpack, file: file, into: out)
        }
        try rejectEscapingSymlinks(in: out)

        let content: URL
        if case .tarGzPython = spec.artifacts[0].unpack { content = out.appendingPathComponent("python", isDirectory: true) } else { content = out }
        try Data().write(to: content.appendingPathComponent(Self.verifiedMarker))
        try fm.createDirectory(at: kindDir(kind), withIntermediateDirectories: true)
        try fm.moveItem(at: content, to: versionDir)

        do { try await check(kind, versionDir, extraCheck) } catch {
            try? fm.removeItem(at: versionDir)
            throw error
        }
        return true
    }

    func check(_ kind: ToolKind, _ versionDir: URL, _ extra: (@Sendable (URL) async throws -> Void)?) async throws {
        let fm = FileManager.default
        for rel in kind.executables {
            let exe = versionDir.appendingPathComponent(rel)
            guard fm.fileExists(atPath: exe.path) else { throw ToolError.healthCheckFailed(rel) }
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
            await prepareBinary(exe)
        }
        for rel in kind.executables where !(await healthy(versionDir.appendingPathComponent(rel), kind.healthArguments)) {
            throw ToolError.healthCheckFailed(rel)
        }
        try await extra?(versionDir)
    }

    /// Eşzamanlı (await yok): `current` bağlantısını çevirir, eskileri budar.
    func commit(_ kind: ToolKind, version: String) throws {
        let previous = currentVersion(kind)
        try switchCurrent(kind, to: version)
        prune(kind, keep: [version] + (previous.map { [$0] } ?? []))
    }

    /// Açılan arşivde, hedefi çıkış klasörü dışına taşan (ya da mutlak) sembolik bağlantı varsa reddeder.
    func rejectEscapingSymlinks(in out: URL) throws {
        let fm = FileManager.default
        let base = out.standardizedFileURL.path
        guard let walker = fm.enumerator(at: out, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return }
        for case let item as URL in walker {
            guard (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true,
                  let dest = try? fm.destinationOfSymbolicLink(atPath: item.path) else { continue }
            let resolved = dest.hasPrefix("/")
                ? URL(fileURLWithPath: dest).standardizedFileURL
                : item.deletingLastPathComponent().appendingPathComponent(dest).standardizedFileURL
            if dest.hasPrefix("/") || !(resolved.path == base || resolved.path.hasPrefix(base + "/")) {
                throw ToolError.unsafeRelease("symlink \(item.lastPathComponent) -> \(dest)")
            }
        }
    }

    /// Karantina işaretini kaldırır (yoksa sessiz geçer) ve geçici (ad-hoc) imzalar.
    func prepareBinary(_ exe: URL) async {
        _ = try? await runner.run(URL(fileURLWithPath: "/usr/bin/xattr"), ["-d", "com.apple.quarantine", exe.path], environment: [:], onLine: { _ in })
        _ = try? await runner.run(URL(fileURLWithPath: "/usr/bin/codesign"), ["--force", "-s", "-", exe.path], environment: [:], onLine: { _ in })
    }

    /// `<araç> --version` 10 sn içinde 0 ile çıkmalı.
    func healthy(_ exe: URL, _ args: [String]) async -> Bool {
        let runner = self.runner
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                (try? await runner.run(exe, args, environment: [:], onLine: { _ in }))?.exitCode == 0
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func verify(_ file: URL, _ a: Artifact) async throws {
        let name: String, listURL: URL
        switch a.checksum {
        case .sums(let u, let entry): listURL = u; name = entry
        case .single(let u): listURL = u; name = ""
        }
        let text = String(decoding: try await fetcher.data(from: listURL), as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.split(whereSeparator: \.isWhitespace) }
        let line = name.isEmpty
            ? lines.first(where: { !$0.isEmpty })
            : lines.first(where: { $0.count >= 2 && $0[1].trimmingCharacters(in: CharacterSet(charactersIn: "*")) == name })
        guard let expected = line?.first?.lowercased() else { throw ToolError.checksumMissing(name.isEmpty ? listURL.lastPathComponent : name) }
        let actual = try Self.sha256(of: file)
        guard actual == expected else { throw ToolError.checksumMismatch(file.lastPathComponent) }
    }

    static func sha256(of file: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: file)
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func unpack(_ kind: Unpack, file: URL, into out: URL) async throws {
        switch kind {
        case .copy(let name):
            try FileManager.default.copyItem(at: file, to: out.appendingPathComponent(name))
        case .tarGzPython:
            try await extract("/usr/bin/tar", ["-xzf", file.path, "-C", out.path])
        case .zip:
            try await extract("/usr/bin/unzip", ["-o", "-q", file.path, "-d", out.path])
        }
    }

    private func extract(_ tool: String, _ args: [String]) async throws {
        let r = try await runner.run(URL(fileURLWithPath: tool), args, environment: [:], onLine: { _ in })
        guard r.exitCode == 0 else { throw ToolError.unpackFailed(r.stderr) }
    }

    /// `current` bağlantısını atomik olarak değiştirir (göreli hedef: klasör taşınsa da bozulmaz).
    func switchCurrent(_ kind: ToolKind, to version: String) throws {
        let fm = FileManager.default
        let tmp = kindDir(kind).appendingPathComponent(".current-\(UUID().uuidString)")
        try fm.createSymbolicLink(atPath: tmp.path, withDestinationPath: version)
        if rename(tmp.path, currentLink(kind).path) != 0 {
            try? fm.removeItem(at: tmp)
            throw ToolError.unpackFailed("current bağlantısı güncellenemedi")
        }
    }

    func prune(_ kind: ToolKind, keep: [String]) {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(atPath: kindDir(kind).path)) ?? []
        for name in items where name != "current" && !keep.contains(name) {
            try? fm.removeItem(at: kindDir(kind).appendingPathComponent(name))
        }
    }
}
