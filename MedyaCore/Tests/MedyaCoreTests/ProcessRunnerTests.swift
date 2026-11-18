import Testing
import Foundation
@testable import MedyaCore

final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct ProcessRunnerTests {
    let sh = URL(fileURLWithPath: "/bin/sh")

    @Test func collectsLinesAndStderr() async throws {
        let box = LineBox()
        let r = try await SystemProcessRunner().run(sh, ["-c", "echo a; echo b; echo err >&2; exit 3"], environment: [:]) { box.add($0) }
        #expect(r.exitCode == 3)
        #expect(box.all == ["a", "b"])
        #expect(r.stdout == "a\nb\n")
        #expect(r.stderr.contains("err"))
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let r = try await SystemProcessRunner().run(sh, ["-c", "yes x | head -c 3000000; yes y | head -c 3000000 >&2"], environment: [:]) { _ in }
        #expect(r.exitCode == 0)
        #expect(r.stderr.count >= 3_000_000)
    }

    @Test func environmentIsPassed() async throws {
        let box = LineBox()
        _ = try await SystemProcessRunner().run(sh, ["-c", "echo $MI_TEST"], environment: ["MI_TEST": "merhaba"]) { box.add($0) }
        #expect(box.all == ["merhaba"])
    }

    @Test func cancelKillsProcess() async throws {
        let box = LineBox()
        let task = Task {
            try await SystemProcessRunner().run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo $$; exec /bin/sleep 30"], environment: [:]) { box.add($0) }
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        let start = Date()
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(Date().timeIntervalSince(start) < 3)
        let pid = try #require(Int32(box.all.first ?? ""))
        #expect(kill(pid, 0) != 0)
    }

    @Test func cancelKillsChildProcesses() async throws {
        let box = LineBox()
        let task = Task {
            try await SystemProcessRunner().run(URL(fileURLWithPath: "/bin/sh"), ["-c", "/bin/sleep 30 & echo $!; wait"], environment: [:]) { box.add($0) }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        _ = try? await task.value
        let child = try #require(Int32(box.all.first ?? ""))
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(kill(child, 0) != 0)
    }

    @Test func cancelKillsGrandchildThatIgnoresTerm() async throws {
        let box = LineBox()
        let inner = "trap '' TERM; /bin/sleep 30 & echo $!; wait"
        let task = Task {
            try await SystemProcessRunner().run(URL(fileURLWithPath: "/bin/sh"), ["-c", "/bin/sh -c \"$INNER\" & wait"],
                                                environment: ["INNER": inner]) { box.add($0) }
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        let start = Date()
        task.cancel()
        _ = try? await task.value
        #expect(Date().timeIntervalSince(start) < 4)
        let grandchild = try #require(Int32(box.all.first ?? ""))
        #expect(kill(grandchild, 0) != 0)
    }

    @Test func missingExecutableThrows() async {
        await #expect(throws: (any Error).self) {
            try await SystemProcessRunner().run(URL(fileURLWithPath: "/nonexistent/tool"), [], environment: [:]) { _ in }
        }
    }
}
