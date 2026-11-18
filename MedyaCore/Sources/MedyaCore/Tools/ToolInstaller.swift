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

    func currentVersion(_ k: ToolKind) -> String? {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: currentLink(k).path) else { return nil }
        return URL(fileURLWithPath: dest).lastPathComponent
    }

    /// Yeni sürüm kurulduysa `true`, zaten güncelse `false`.
    /// `beforeSwitch`: etkinleştirmeden hemen önce beklenecek şey (devam eden indirme varsa bekler).
    func install(_ kind: ToolKind, spec: ReleaseSpec, progress: @escaping @Sendable (Double) -> Void,
                 beforeSwitch: @Sendable () async -> Void) async throws -> Bool {
        if currentVersion(kind) == spec.version { return false }
        let fm = FileManager.default
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

        let content: URL
        if case .tarGzPython = spec.artifacts[0].unpack { content = out.appendingPathComponent("python", isDirectory: true) } else { content = out }
        try fm.createDirectory(at: kindDir(kind), withIntermediateDirectories: true)
        let versionDir = kindDir(kind).appendingPathComponent(spec.version, isDirectory: true)
        try? fm.removeItem(at: versionDir)
        try fm.moveItem(at: content, to: versionDir)

        do {
            for rel in kind.executables {
                let exe = versionDir.appendingPathComponent(rel)
                guard fm.fileExists(atPath: exe.path) else { throw ToolError.healthCheckFailed(rel) }
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
                await prepare(exe)
            }
            for rel in kind.executables where !(await healthy(versionDir.appendingPathComponent(rel), kind.healthArguments)) {
                throw ToolError.healthCheckFailed(rel)
            }
        } catch {
            try? fm.removeItem(at: versionDir)
            throw error
        }

        await beforeSwitch()
        let previous = currentVersion(kind)
        try switchCurrent(kind, to: spec.version)
        prune(kind, keep: [spec.version] + (previous.map { [$0] } ?? []))
        return true
    }

    /// Karantina işaretini kaldırır (yoksa sessiz geçer) ve geçici (ad-hoc) imzalar.
    func prepare(_ exe: URL) async {
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
