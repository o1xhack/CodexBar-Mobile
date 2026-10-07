import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
struct CodexLaunchPreflightDescriptorRaceTests {
    @TaskLocal private static var deliveryReadMayPause = false

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var total: Int {
            self.lock.withLock { self.count }
        }

        @discardableResult
        func increment() -> Int {
            self.lock.withLock {
                self.count += 1
                return self.count
            }
        }
    }

    @Test(arguments: ["replacement", "metadata", "app-alias"], [false, true])
    func `delivery rechecks the pathname after reading an opened signature`(mutation: String, shared: Bool) throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let allowed = root.appendingPathComponent("allowed")
        let blocked = root.appendingPathComponent("blocked")
        let alias = root.appendingPathComponent("candidate")
        let app = root.appendingPathComponent("Payload.app")
        let bundled = app.appendingPathComponent("allowed")
        try Data("allowed".utf8).write(to: allowed)
        try Data("blocked".utf8).write(to: blocked)
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: allowed.path)
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        try manager.linkItem(at: allowed, to: bundled)
        try manager.createSymbolicLink(at: alias, withDestinationURL: allowed)
        let armed = LockIsolated(false)
        let opened = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let leaderStarted = DispatchSemaphore(value: 0)
        let joined = DispatchSemaphore(value: 0)
        let releaseLeader = DispatchSemaphore(value: 0)
        let calls = Counter()
        let result = LockIsolated<CodexLaunchPreflight.GatekeeperAssessment?>(nil)
        let memo = CodexLaunchPreflight.AssessmentMemo(
            hostAllowsMemoization: true,
            onJoin: { armed.setValue(true); joined.signal() },
            onCacheHit: { armed.setValue(true) },
            readSignature: { file in
                #expect(fcntl(file.fileDescriptor, F_GETFD) & FD_CLOEXEC != 0)
                if Self.deliveryReadMayPause, armed.value {
                    armed.setValue(false)
                    opened.signal()
                    guard resume.wait(timeout: .now() + 10) == .success else {
                        Issue.record("The opened signature read was not released")
                        return nil
                    }
                }
                return (try? file.readToEnd()).map { .init(digest: $0) }
            })
        let lookup: @Sendable () -> CodexLaunchPreflight.GatekeeperAssessment? = {
            memo.assessment(path: alias.path, isDefinitive: { _ in true }, assess: { path in
                let attempt = calls.increment()
                let content = try? String(contentsOfFile: path, encoding: .utf8)
                let permissions = try? FileManager.default
                    .attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
                let inApp = URL(fileURLWithPath: path).resolvingSymlinksInPath().path.contains("/Payload.app/")
                let allowed = content == "allowed" && permissions?.intValue == 0o644 && !inApp
                if shared, attempt == 1 {
                    leaderStarted.signal()
                    guard releaseLeader.wait(timeout: .now() + 10) == .success else {
                        Issue.record("The in-flight leader was not released")
                        return nil
                    }
                }
                return .init(output: "\(path): \(allowed ? "accepted" : "rejected")", exitStatus: allowed ? 0 : 1)
            })
        }
        let group = DispatchGroup()
        defer {
            releaseLeader.signal()
            resume.signal()
            group.wait()
        }
        if shared {
            group.enter()
            DispatchQueue.global().async {
                _ = lookup()
                group.leave()
            }
            try #require(leaderStarted.wait(timeout: .now() + 10) == .success)
        } else {
            #expect(lookup()?.exitStatus == 0)
        }
        group.enter()
        DispatchQueue.global().async {
            Self.$deliveryReadMayPause.withValue(true) { result.setValue(lookup()) }
            group.leave()
        }
        if shared {
            try #require(joined.wait(timeout: .now() + 10) == .success)
            releaseLeader.signal()
        }
        try #require(opened.wait(timeout: .now() + 10) == .success)
        if mutation == "metadata" {
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: allowed.path)
        } else {
            try manager.removeItem(at: alias)
            try manager.createSymbolicLink(
                at: alias, withDestinationURL: mutation == "app-alias" ? bundled : blocked)
        }
        resume.signal()
        group.wait()
        #expect(result.value?.exitStatus == 1)
        #expect(result.value?.output == "\(alias.path): rejected")
        if shared {
            #expect((2...3).contains(calls.total))
        } else {
            #expect(calls.total == 2)
        }
        print("descriptor race: mutation=\(mutation) shared=\(shared) " +
            "assessments=\(calls.total) status=\(result.value?.exitStatus ?? -1)")
    }

    @Test
    func `a descriptor changed while binding cannot evict a valid cached verdict`() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let target = root.appendingPathComponent("target")
        try Data("target".utf8).write(to: target)
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        let opened = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let armed = LockIsolated(false)
        let targetCalls = Counter()
        let oldestCalls = Counter()
        let memo = CodexLaunchPreflight.AssessmentMemo(hostAllowsMemoization: true, readSignature: { file in
            if armed.value {
                armed.setValue(false)
                opened.signal()
                guard resume.wait(timeout: .now() + 10) == .success else {
                    Issue.record("The binding signature read was not released")
                    return nil
                }
            }
            return (try? file.readToEnd()).map { .init(digest: $0) }
        })
        let assess: @Sendable (String) -> CodexLaunchPreflight.GatekeeperAssessment? = { path in
            let content = try? String(contentsOfFile: path, encoding: .utf8)
            if content == "target", targetCalls.increment() == 1 { armed.setValue(true) }
            if content == "kept-0" { oldestCalls.increment() }
            return .init(output: "\(path): accepted", exitStatus: 0)
        }
        for index in 0..<CodexLaunchPreflight.AssessmentMemo.capacity {
            let path = root.appendingPathComponent("kept-\(index)")
            try Data("kept-\(index)".utf8).write(to: path)
            _ = memo.assessment(path: path.path, now: TimeInterval(index), isDefinitive: { _ in true }, assess: assess)
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            _ = memo.assessment(path: target.path, now: 20, isDefinitive: { _ in true }, assess: assess)
            group.leave()
        }
        defer {
            resume.signal()
            group.wait()
        }
        try #require(opened.wait(timeout: .now() + 10) == .success)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        resume.signal()
        group.wait()
        _ = memo.assessment(
            path: root.appendingPathComponent("kept-0").path,
            now: 21,
            isDefinitive: { _ in true },
            assess: assess)
        #expect(targetCalls.total == 2)
        #expect(oldestCalls.total == 1)
        print("descriptor binding: freshAssessments=\(targetCalls.total) oldestAssessments=\(oldestCalls.total)")
    }
}
#endif
