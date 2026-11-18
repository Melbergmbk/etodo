import Foundation

public struct ProcessResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol ProcessRunning: Sendable {
    /// `onLine` stdout satırlarını geldikçe alır; stderr `ProcessResult.stderr` içinde toplanır.
    /// Görev iptal edilirse süreç ve alt süreçleri sonlandırılır ve `CancellationError` fırlatılır.
    func run(_ executable: URL, _ arguments: [String], environment: [String: String],
             onLine: @escaping @Sendable (String) -> Void) async throws -> ProcessResult
}

public final class SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: URL, _ arguments: [String], environment: [String: String],
                    onLine: @escaping @Sendable (String) -> Void) async throws -> ProcessResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let out = StreamCollector(onLine: onLine)
        let err = StreamCollector(onLine: nil)
        let group = DispatchGroup()
        let box = ProcessBox(process)

        process.terminationHandler = { _ in group.leave() }
        group.enter()
        do { try process.run() } catch {
            process.terminationHandler = nil
            group.leave()
            throw error
        }
        // yazma uçları ebeveynde kapanmazsa EOF hiç gelmez
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()
        for (pipe, collector) in [(outPipe, out), (errPipe, err)] {
            group.enter()
            DispatchQueue.global().async {
                let h = pipe.fileHandleForReading
                while true {
                    let data = h.availableData
                    if data.isEmpty { break }
                    collector.append(data)
                }
                collector.finish()
                group.leave()
            }
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                group.notify(queue: .global()) { cont.resume() }
            }
        } onCancel: {
            box.terminateTree()
        }

        if Task.isCancelled { throw CancellationError() }
        return ProcessResult(exitCode: process.terminationStatus, stdout: out.text, stderr: err.text)
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ p: Process) { process = p }

    /// Süreç ve tüm torunları: önce SIGTERM, 2 sn sonra hâlâ yaşayanlara SIGKILL.
    /// Çağıran iş parçacığını bloklamamak için arka kuyrukta çalışır.
    func terminateTree() {
        let root = process.processIdentifier
        guard process.isRunning, root > 0 else { return }
        DispatchQueue.global().async { [process] in
            let pids = [root] + Self.descendants(of: root)
            pids.forEach { kill($0, SIGTERM) }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                // üst süreç ölmüş olsa bile anlık görüntüdeki torunlar öldürülür
                for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            }
        }
    }

    private static func descendants(of pid: Int32) -> [Int32] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-P", String(pid)]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let children = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { Int32($0) }
        return children + children.flatMap { descendants(of: $0) }
    }
}

/// Boruyu parça parça okur; satırlara böler (sunucu tarafında tek yazan iş parçacığı vardır).
private final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var all = Data()
    private var pending = Data()
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: all, as: UTF8.self)
    }

    func append(_ data: Data) {
        lock.lock()
        all.append(data)
        var lines: [String] = []
        if onLine != nil {
            pending.append(data)
            while let nl = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                let line = pending[pending.startIndex..<nl]
                pending.removeSubrange(pending.startIndex...nl)
                if !line.isEmpty { lines.append(String(decoding: line, as: UTF8.self)) }
            }
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    func finish() {
        lock.lock()
        let rest = pending
        pending = Data()
        lock.unlock()
        if !rest.isEmpty { onLine?(String(decoding: rest, as: UTF8.self)) }
    }
}
