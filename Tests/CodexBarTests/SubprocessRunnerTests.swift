import Foundation
import Testing
@testable import CodexBarCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct SubprocessRunnerTests {
    @Test(arguments: [Double(Int.max) / 1_000_000_000, Double.greatestFiniteMagnitude])
    func `large finite subprocess timeouts retain successful output`(timeout: Double) async throws {
        let result = try await SubprocessRunner.run(
            binary: "/bin/echo",
            arguments: ["finished"],
            environment: [:],
            timeout: timeout,
            label: "large timeout fixture")
        #expect(result.stdout == "finished\n")
    }

    @Test
    func `reads large stdout without deadlock`() async throws {
        let result = try await SubprocessRunner.run(
            binary: "/usr/bin/python3",
            arguments: ["-c", "print('x' * 1_000_000)"],
            environment: ProcessInfo.processInfo.environment,
            timeout: 15,
            label: "python large stdout")

        #expect(result.stdout.count >= 1_000_000)
        #expect(result.stderr.isEmpty)
    }

    @Test
    func `bounds oversized stdout while continuing to drain`() async throws {
        let result = try await SubprocessRunner.run(
            binary: "/usr/bin/python3",
            arguments: ["-c", "print('x' * 2_000_000)"],
            environment: ProcessInfo.processInfo.environment,
            timeout: 5,
            label: "python oversized stdout")

        #expect(result.stdout.utf8.count == ProcessPipeCapture.defaultMaxBytes)
        #expect(result.stderr.isEmpty)
    }

    @Test
    func `rejects oversized output when strict limit is configured`() async throws {
        do {
            _ = try await SubprocessRunner.run(
                binary: "/usr/bin/python3",
                arguments: ["-c", "print('x' * 10_000)"],
                environment: ProcessInfo.processInfo.environment,
                timeout: 5,
                maxOutputBytes: 1024,
                label: "python strict output limit")
            Issue.record("Expected strict output limit failure")
        } catch let error as SubprocessRunnerError {
            guard case let .outputTooLarge(label) = error else {
                Issue.record("Expected outputTooLarge, got \(error)")
                return
            }
            #expect(label == "python strict output limit")
        } catch {
            Issue.record("Expected SubprocessRunnerError, got \(error)")
        }
    }

    @Test
    func `preserves captured prefix when limit splits three byte scalar`() async throws {
        let asciiCount = ProcessPipeCapture.defaultMaxBytes - 1
        let script = "import sys; sys.stdout.buffer.write(b'x' * \(asciiCount) + bytes([0xe2, 0x82, 0xac]) + b'tail')"
        let result = try await SubprocessRunner.run(
            binary: "/usr/bin/python3",
            arguments: ["-c", script],
            environment: ProcessInfo.processInfo.environment,
            timeout: 5,
            label: "python split utf8 stdout")

        #expect(result.stdout.count == ProcessPipeCapture.defaultMaxBytes)
        #expect(result.stdout.first == "x")
        #expect(result.stdout.last == "\u{FFFD}")
        #expect(result.stdout.utf8.count == ProcessPipeCapture.defaultMaxBytes + 2)
    }

    @Test
    func `bounds simultaneous oversized stdout and stderr while draining`() async throws {
        let script = """
        import sys
        chunk = 2048
        for _ in range(2000):
            sys.stdout.write('o' * chunk)
            sys.stdout.flush()
            sys.stderr.write('e' * chunk)
            sys.stderr.flush()
        """
        let result = try await SubprocessRunner.run(
            binary: "/usr/bin/python3",
            arguments: ["-c", script],
            environment: ProcessInfo.processInfo.environment,
            timeout: 10,
            label: "python simultaneous oversized output")

        #expect(result.stdout.utf8.count == ProcessPipeCapture.defaultMaxBytes)
        #expect(result.stderr.utf8.count == ProcessPipeCapture.defaultMaxBytes)
    }

    @Test
    func `bounds oversized stderr on failure`() async throws {
        do {
            _ = try await SubprocessRunner.run(
                binary: "/usr/bin/python3",
                arguments: ["-c", "import sys; sys.stderr.write('e' * 2_000_000); sys.exit(7)"],
                environment: ProcessInfo.processInfo.environment,
                timeout: 5,
                label: "python oversized stderr")
            Issue.record("Expected non-zero exit")
        } catch let error as SubprocessRunnerError {
            guard case let .nonZeroExit(code, stderr) = error else {
                Issue.record("Expected non-zero exit, got \(error)")
                return
            }
            #expect(code == 7)
            #expect(stderr.utf8.count == ProcessPipeCapture.defaultMaxBytes)
        } catch {
            Issue.record("Expected SubprocessRunnerError, got \(error)")
        }
    }

    @Test
    func `returns partial output when detached child keeps pipes open`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-subprocess-drain-\(UUID().uuidString)", isDirectory: true)
        let childPIDFile = root.appendingPathComponent("child.pid")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        defer {
            if let text = try? String(contentsOf: childPIDFile, encoding: .utf8),
               let childPID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                _ = kill(childPID, SIGKILL)
            }
        }

        var environment = ProcessInfo.processInfo.environment
        environment["CODEXBAR_TEST_CHILD_PID_FILE"] = childPIDFile.path
        let script = """
        import os
        import subprocess
        import sys

        ready_read, ready_write = os.pipe()
        child = subprocess.Popen(
            [sys.executable, "-c", "import os,signal,sys; os.write(int(sys.argv[1]), b'R'); signal.pause()",
             str(ready_write)],
            start_new_session=True,
            pass_fds=(ready_write,),
        )
        with open(os.environ["CODEXBAR_TEST_CHILD_PID_FILE"], "w") as handle:
            handle.write(str(child.pid))
        os.read(ready_read, 1)
        print("parent-output", flush=True)
        """

        let result = try await SubprocessRunner.run(
            binary: "/usr/bin/python3",
            arguments: ["-c", script],
            environment: environment,
            timeout: 5,
            label: "detached-output-holder")

        #expect(result.stdout.contains("parent-output"))
        let childPID = try #require(KiroProcessTestSupport.readPID(from: childPIDFile))
        #expect(kill(childPID, 0) == 0)
    }

    /// Regression test for #474: a hung subprocess must be killed and throw `.timedOut`
    /// instead of blocking indefinitely.
    ///
    /// This test was previously deleted (commit 3961770) because `waitUntilExit()` blocked
    /// the cooperative thread pool, starving the timeout task. The fix moves blocking calls
    /// to `DispatchQueue.global()`, making this test reliable.
    @Test(.timeLimit(.minutes(1)))
    func `throws timed out when process hangs`() async throws {
        let stdin = Pipe()
        defer {
            try? stdin.fileHandleForWriting.close()
            try? stdin.fileHandleForReading.close()
        }
        // Hold stdin open so only termination, not natural completion, can release the child.
        do {
            _ = try await SubprocessRunner.run(
                binary: "/bin/cat",
                arguments: [],
                environment: [:],
                timeout: 1,
                standardInput: stdin,
                label: "hung-process-test")
            Issue.record("Expected SubprocessRunnerError.timedOut but no error was thrown")
        } catch let error as SubprocessRunnerError {
            guard case let .timedOut(label) = error else {
                Issue.record("Expected .timedOut, got \(error)")
                return
            }
            #expect(label == "hung-process-test")
        } catch {
            Issue.record("Expected SubprocessRunnerError.timedOut, got unexpected error: \(error)")
        }
    }

    @Test
    func `timeout kills descendants that escape the process group`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-subprocess-tree-\(UUID().uuidString)", isDirectory: true)
        let childPIDFile = root.appendingPathComponent("child.pid")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var environment = ProcessInfo.processInfo.environment
        environment["CODEXBAR_TEST_CHILD_PID_FILE"] = childPIDFile.path
        let script = """
        import os
        import subprocess
        import sys
        import time

        child = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(30)"],
            start_new_session=True,
        )
        with open(os.environ["CODEXBAR_TEST_CHILD_PID_FILE"], "w") as handle:
            handle.write(str(child.pid))
        time.sleep(30)
        """

        do {
            _ = try await SubprocessRunner.run(
                binary: "/usr/bin/python3",
                arguments: ["-c", script],
                environment: environment,
                // Python must start and fork before the timeout can exercise descendant cleanup.
                // Even the loaded-runner budget stays well below the fixture's 30-second lifetime.
                timeout: 3 * TestTimingBudget.slowdownFactor,
                label: "escaped-descendant")
            Issue.record("Expected the escaped-descendant timeout")
        } catch let error as SubprocessRunnerError {
            guard case let .timedOut(label) = error else { throw error }
            #expect(label == "escaped-descendant")
        }

        let text = try String(contentsOf: childPIDFile, encoding: .utf8)
        let childPID = try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        defer { _ = kill(childPID, SIGKILL) }

        let deadline = Date().addingTimeInterval(1)
        while kill(childPID, 0) == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(childPID, 0) == -1)
    }

    /// Multiple concurrent hung subprocesses must all time out independently, proving that
    /// one blocked subprocess does not starve the timeout mechanism of others.
    /// This is the core scenario that caused the original permanent-refresh-stall bug.
    @Test(.timeLimit(.minutes(1)))
    func `concurrent hung processes all time out`() async {
        let count = 8
        let fired = AsyncStream.makeStream(of: Void.self)
        let release = DispatchSemaphore(value: 0)
        let holdTimeout: @Sendable () -> Void = {
            fired.continuation.yield(())
            #expect(release.wait(timeout: .now() + 30) == .success)
        }
        let outcomes = Task {
            defer { fired.continuation.finish() }
            return await SubprocessRunner.$timeoutWillFire.withValue(holdTimeout) {
                await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
                    for index in 0..<count {
                        group.addTask {
                            let stdin = Pipe()
                            defer {
                                try? stdin.fileHandleForWriting.close()
                                try? stdin.fileHandleForReading.close()
                            }
                            do {
                                _ = try await SubprocessRunner.run(
                                    binary: "/bin/cat",
                                    arguments: [],
                                    environment: [:],
                                    timeout: 0.1,
                                    standardInput: stdin,
                                    label: "concurrent-hung-\(index)")
                                return false
                            } catch SubprocessRunnerError.timedOut {
                                return true
                            } catch {
                                Issue.record("Unexpected error: \(error)")
                                return false
                            }
                        }
                    }
                    return await group.reduce(into: []) { $0.append($1) }
                }
            }
        }
        var reached = 0
        for await _ in fired.stream {
            reached += 1
            if reached == count { break }
        }
        #expect(reached == count)
        // All timeout handlers must be in flight together, before any is allowed to kill its child.
        for _ in 0..<count {
            release.signal()
        }
        #expect(await outcomes.value == Array(repeating: true, count: count))
    }

    /// Stress-test the timeout race guard: with very short timeouts, the exit-code task
    /// and the timeout task race tightly, exercising the TimeoutState synchronization path.
    @Test
    func `timeout race stress`() async {
        for i in 0..<20 {
            do {
                _ = try await SubprocessRunner.run(
                    binary: "/bin/sleep",
                    arguments: ["1"],
                    environment: ProcessInfo.processInfo.environment,
                    timeout: 0.1,
                    label: "race-stress-\(i)")
                Issue.record("Expected .timedOut for iteration \(i)")
            } catch let error as SubprocessRunnerError {
                guard case .timedOut = error else {
                    Issue.record("Expected .timedOut, got \(error) at iteration \(i)")
                    continue
                }
            } catch {
                Issue.record("Unexpected error at iteration \(i): \(error)")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `cancellation terminates hung process promptly`() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-cancelled-process-\(UUID().uuidString).pid")
        defer {
            if let pid = KiroProcessTestSupport.readPID(from: pidFile) { _ = kill(pid, SIGKILL) }
            try? FileManager.default.removeItem(at: pidFile)
        }
        let task = Task {
            try await SubprocessRunner.run(
                binary: "/usr/bin/python3",
                arguments: [
                    "-c",
                    "import os,signal,sys; " +
                        "open(sys.argv[1], 'w').write(str(os.getpid())); signal.pause()",
                    pidFile.path,
                ],
                environment: [:],
                timeout: .infinity,
                label: "cancelled-hung-process")
        }
        defer { task.cancel() }
        let pid = try await KiroProcessTestSupport.waitForPID(in: pidFile)
        #expect(kill(pid, 0) == 0)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError but subprocess completed")
        } catch is CancellationError {
            // There is no timeout or natural exit path to mask missing cancellation teardown.
        }
        #expect(kill(pid, 0) == -1)
    }

    /// Verify that many concurrent SubprocessRunner calls complete without starving each other.
    @Test
    func `concurrent calls do not starve`() async throws {
        try await withThrowingTaskGroup(of: SubprocessResult.self) { group in
            for i in 0..<20 {
                group.addTask {
                    try await SubprocessRunner.run(
                        binary: "/bin/sleep",
                        arguments: ["0.2"],
                        environment: ProcessInfo.processInfo.environment,
                        timeout: 10,
                        label: "concurrent-\(i)")
                }
            }

            var count = 0
            for try await _ in group {
                count += 1
            }
            #expect(count == 20, "All 20 concurrent calls should complete")
        }
    }

    @Test
    func `reapDescendants kills a session-escaped child after the parent exits`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-reap-\(UUID().uuidString)", isDirectory: true)
        let childPIDFile = root.appendingPathComponent("child.pid")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            if let text = try? String(contentsOf: childPIDFile, encoding: .utf8),
               let childPID = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
            {
                _ = kill(childPID, SIGKILL)
            }
            try? FileManager.default.removeItem(at: root)
        }

        let environment = ["CODEXBAR_TEST_CHILD_PID_FILE": childPIDFile.path]
        let script = """
        import os
        import subprocess
        import sys
        import time

        child = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(30)"],
            start_new_session=True,
        )
        with open(os.environ["CODEXBAR_TEST_CHILD_PID_FILE"], "w") as handle:
            handle.write(str(child.pid))
        time.sleep(0.4)
        """

        _ = try await SubprocessRunner.run(
            binary: "/usr/bin/python3",
            arguments: ["-c", script],
            environment: environment,
            timeout: 10,
            currentDirectoryURL: root,
            reapDescendants: true,
            label: "reap-escaped-child")

        let text = try String(contentsOf: childPIDFile, encoding: .utf8)
        let childPID = try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        let deadline = Date().addingTimeInterval(1.5)
        while kill(childPID, 0) == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(childPID, 0) == -1)
    }
}
