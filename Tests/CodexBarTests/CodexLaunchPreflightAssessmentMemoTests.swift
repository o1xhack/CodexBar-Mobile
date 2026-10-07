import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
struct CodexLaunchPreflightAssessmentMemoTests {
    private typealias Memo = CodexLaunchPreflight.AssessmentMemo
    private typealias Assessment = CodexLaunchPreflight.GatekeeperAssessment

    private static let notAnApp = "rejected (the code is valid but does not seem to be an app)\n" +
        "origin=Developer ID Application: Synthetic Fixture (FIXTURE01)"

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int {
            self.lock.withLock { self.value }
        }

        func increment() {
            self.lock.withLock { self.value += 1 }
        }
    }

    private struct Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        init() throws {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        }

        func executable(_ name: String, contents: String = "synthetic native codex") throws -> URL {
            let url = self.root.appendingPathComponent(name)
            try Data(contents.utf8).write(to: url)
            return url
        }

        func remove() { try? FileManager.default.removeItem(at: self.root) }
    }

    /// Keep the contributor's filesystem/race tests synthetic; real signature coverage is separate.
    private static func memo(
        onJoin: @escaping @Sendable () -> Void = {},
        onCacheHit: @escaping @Sendable () -> Void = {}) -> Memo
    {
        Memo(hostAllowsMemoization: true, onJoin: onJoin, onCacheHit: onCacheHit, readSignature: { _ in
            .init(digest: Data("synthetic signature".utf8))
        })
    }

    private static func assess(
        _ memo: Memo,
        _ path: String,
        now: TimeInterval = 0,
        calls: Counter,
        output: String? = Self.notAnApp) -> Assessment?
    {
        memo.assessment(
            path: path,
            now: now,
            isDefinitive: { CodexLaunchPreflight.isDefinitiveAssessment($0.output, path: path) },
            assess: { _ in
                calls.increment()
                return output.map { Assessment(output: "\(path): \($0)", exitStatus: 3) }
            })
    }

    @Test
    func `a cache hit rechecks app ancestry even when an alias keeps the same inode`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let native = try fixture.executable("standalone")
        let bundle = fixture.root.appendingPathComponent("Payload.app")
        let bundled = bundle.appendingPathComponent("codex")
        let alias = fixture.root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: native, to: bundled)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: native)
        let memo = Self.memo(onCacheHit: {
            do {
                try FileManager.default.removeItem(at: alias)
                try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: bundled)
            } catch {
                Issue.record(error)
            }
        })
        let calls = Counter()
        _ = Self.assess(memo, alias.path, calls: calls)
        _ = Self.assess(memo, alias.path, now: 1, calls: calls)
        #expect(alias.resolvingSymlinksInPath() == bundled.resolvingSymlinksInPath())
        #expect(calls.count == 2)
        _ = Self.assess(memo, alias.path, now: 2, calls: calls)
        #expect(calls.count == 3)
        print("app ancestry recheck: requests=3 assessments=\(calls.count)")
    }

    @Test
    func `an unchanged executable is assessed once`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let codex = try fixture.executable("codex")
        let memo = Self.memo()
        let calls = Counter()

        for _ in 0..<100 {
            #expect(Self.assess(memo, codex.path, calls: calls)?.exitStatus == 3)
        }

        #expect(calls.count == 1)
        print("assessment memo serial: requests=100 assessments=\(calls.count)")
    }

    @Test
    func `rewriting the executable forces a fresh assessment`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let codex = try fixture.executable("codex")
        let memo = Self.memo()
        let calls = Counter()
        _ = Self.assess(memo, codex.path, calls: calls)

        try Data("a codex update that is definitely not the old one".utf8).write(to: codex)
        _ = Self.assess(memo, codex.path, calls: calls)

        #expect(calls.count == 2)
    }

    @Test
    func `an extended attribute change alone forces a fresh assessment`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let codex = try fixture.executable("codex")
        let memo = Self.memo()
        let calls = Counter()
        let modifiedBefore = try FileManager.default.attributesOfItem(atPath: codex.path)[.modificationDate] as? Date
        _ = Self.assess(memo, codex.path, calls: calls)

        // Quarantine arrives as an xattr: size and mtime stay put, only ctime moves.
        let value = Array("0081;00000000;Synthetic;".utf8)
        let status = setxattr(codex.path, "com.apple.quarantine", value, value.count, 0, 0)
        #expect(status == 0)
        let modifiedAfter = try FileManager.default.attributesOfItem(atPath: codex.path)[.modificationDate] as? Date
        #expect(modifiedBefore == modifiedAfter)
        _ = Self.assess(memo, codex.path, calls: calls)

        #expect(calls.count == 2)
    }

    @Test
    func `a repointed symlink gets its own verdict`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let old = try fixture.executable("codex-0.1", contents: "old release")
        let new = try fixture.executable("codex-0.2", contents: "new release")
        let link = fixture.root.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: old)
        let memo = Self.memo()
        let calls = Counter()
        _ = Self.assess(memo, link.path, calls: calls)

        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: new)
        _ = Self.assess(memo, link.path, calls: calls)

        #expect(calls.count == 2)
    }

    @Test
    func `verdicts expire after the lifetime`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let codex = try fixture.executable("codex")
        let memo = Self.memo()
        let calls = Counter()

        _ = Self.assess(memo, codex.path, now: 0, calls: calls)
        _ = Self.assess(memo, codex.path, now: Memo.lifetime - 1, calls: calls)
        #expect(calls.count == 1)

        _ = Self.assess(memo, codex.path, now: Memo.lifetime, calls: calls)
        #expect(calls.count == 2)
    }

    @Test
    func `timeouts and spctl errors stay retryable`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let codex = try fixture.executable("codex")
        let memo = Self.memo()
        let timeouts = Counter()
        let errors = Counter()

        for _ in 0..<3 {
            #expect(Self.assess(memo, codex.path, calls: timeouts, output: nil) == nil)
            _ = Self.assess(memo, codex.path, calls: errors, output: "spctl: syspolicyd is unavailable")
        }

        #expect(timeouts.count == 3)
        #expect(errors.count == 3)
    }

    @Test
    func `app bundles are never memoized`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bundle = fixture.root.appendingPathComponent("Codex.app")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let memo = Self.memo()
        let calls = Counter()

        for _ in 0..<3 {
            _ = Self.assess(memo, bundle.path, calls: calls, output: "accepted\nsource=Notarized Developer ID")
        }

        #expect(calls.count == 3)
    }

    @Test
    func `concurrent callers share one assessment`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let codex = try fixture.executable("codex")
        let joins = Counter()
        let memo = Self.memo(onJoin: { joins.increment() })
        let calls = Counter()
        let path = codex.path

        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            _ = memo.assessment(
                path: path,
                isDefinitive: { _ in true },
                assess: { _ in
                    calls.increment()
                    Thread.sleep(forTimeInterval: 0.2)
                    return Assessment(output: Self.notAnApp, exitStatus: 3)
                })
        }

        #expect(calls.count == 1)
        #expect(joins.count <= 19)
        print("assessment memo concurrent: requests=20 assessments=\(calls.count) joined=\(joins.count)")
    }

    @Test
    func `capacity evicts the verdict closest to expiry`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let memo = Self.memo()
        let calls = Counter()
        let paths = try (0...Memo.capacity).map { try fixture.executable("codex-\($0)").path }

        for (offset, path) in paths.enumerated() {
            _ = Self.assess(memo, path, now: TimeInterval(offset), calls: calls)
        }
        _ = Self.assess(memo, paths[1], now: TimeInterval(paths.count), calls: calls)
        #expect(calls.count == paths.count)

        _ = Self.assess(memo, paths[0], now: TimeInterval(paths.count), calls: calls)
        #expect(calls.count == paths.count + 1)
    }

    /// A final launch decision through the production preflight, with Gatekeeper faked from file contents:
    /// "signed release" is a valid CLI (allowed), anything else has no usable signature (blocked).
    private static func decide(
        _ memo: Memo,
        _ path: String,
        now: TimeInterval = 0,
        calls: Counter,
        during: @escaping (Int) -> Void = { _ in }) -> Bool
    {
        CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: path,
            fileManager: .default,
            hasExtendedAttribute: { _, _ in false },
            spctlAssessment: { candidate in
                memo.assessment(
                    path: candidate,
                    now: now,
                    isDefinitive: { CodexLaunchPreflight.isDefinitiveAssessment($0.output, path: candidate) },
                    assess: { assessed in
                        calls.increment()
                        let contents = try? String(contentsOfFile: assessed, encoding: .utf8)
                        during(calls.count)
                        let verdict = contents == "signed release"
                            ? Self.notAnApp : "rejected\nsource=no usable signature"
                        return Assessment(output: "\(assessed): \(verdict)", exitStatus: 3)
                    })
            },
            appSignatureIsTrusted: { _ in false },
            isMachOExecutable: { _ in true })
    }

    @Test
    func `a link swapped during assessment cannot lend its target's verdict`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let unsigned = try fixture.executable("codex-unsigned", contents: "unsigned build")
        let signed = try fixture.executable("codex-signed", contents: "signed release")
        let link = fixture.root.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unsigned)
        let memo = Self.memo()
        let calls = Counter()
        let swap = { (destination: URL) in
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
        }

        // The link names the signed CLI while spctl runs and the unsigned one again when it returns.
        #expect(!Self.decide(memo, link.path, calls: calls, during: { call in
            if call == 1 {
                swap(signed)
                swap(unsigned)
            }
        }))
        // Gatekeeper assessed the unsigned file by inode, so the swap changed nothing and the verdict holds.
        #expect(calls.count == 1)
        #expect(!Self.decide(memo, link.path, calls: calls))
        #expect(calls.count == 1)
    }

    @Test
    func `an intermediate directory link swapped during assessment cannot lend its verdict`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = FileManager.default
        for (release, contents) in [("release-1", "unsigned build"), ("release-2", "signed release")] {
            let bin = fixture.root.appendingPathComponent("\(release)/bin")
            try manager.createDirectory(at: bin, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: bin.appendingPathComponent("codex"))
        }
        let current = fixture.root.appendingPathComponent("current")
        try manager.createSymbolicLink(atPath: current.path, withDestinationPath: "release-1")
        let codex = current.appendingPathComponent("bin/codex").path
        let memo = Self.memo()
        let calls = Counter()

        #expect(!Self.decide(memo, codex, calls: calls, during: { call in
            guard call == 1 else { return }
            try? manager.removeItem(at: current)
            try? manager.createSymbolicLink(atPath: current.path, withDestinationPath: "release-2")
            try? manager.removeItem(at: current)
            try? manager.createSymbolicLink(atPath: current.path, withDestinationPath: "release-1")
        }))
        #expect(!Self.decide(memo, codex, calls: calls))
        #expect(calls.count == 1)
    }

    @Test
    func `a parent directory swapped during assessment and restored cannot lend its verdict`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manager = FileManager.default
        for (name, contents) in [("tool", "unsigned build"), ("signed", "signed release")] {
            let bin = fixture.root.appendingPathComponent("\(name)/bin")
            try manager.createDirectory(at: bin, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: bin.appendingPathComponent("codex"))
        }
        let tool = fixture.root.appendingPathComponent("tool")
        let signed = fixture.root.appendingPathComponent("signed")
        let aside = fixture.root.appendingPathComponent("tool-aside")
        let codex = tool.appendingPathComponent("bin/codex").path
        let memo = Self.memo()
        let calls = Counter()

        // The unsigned tool is moved aside, the signed one takes its pathname while spctl runs, and the
        // original is restored before it returns.
        #expect(!Self.decide(memo, codex, calls: calls, during: { call in
            guard call == 1 else { return }
            try? manager.moveItem(at: tool, to: aside)
            try? manager.moveItem(at: signed, to: tool)
            try? manager.moveItem(at: tool, to: signed)
            try? manager.moveItem(at: aside, to: tool)
        }))
        #expect(!Self.decide(memo, codex, calls: calls))
        #expect(!Self.decide(memo, codex, calls: calls))
        #expect(calls.count == 1)
    }

    @Test
    func `a cache hit revalidates the caller's path before answering`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let signed = try fixture.executable("codex-signed", contents: "signed release")
        let unsigned = try fixture.executable("codex-unsigned", contents: "unsigned build")
        let link = fixture.root.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: signed)
        let armed = Counter()
        // Fires after the remembered entry is found and before it is returned: the narrowest cache-hit window.
        let memo = Self.memo(onCacheHit: {
            guard armed.count == 1 else { return }
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: unsigned)
        })
        let calls = Counter()

        #expect(Self.decide(memo, link.path, calls: calls))
        #expect(Self.decide(memo, link.path, calls: calls))
        #expect(calls.count == 1)

        armed.increment()
        // The signed CLI's remembered "allowed" must not reach the decision for the unsigned one.
        #expect(!Self.decide(memo, link.path, calls: calls))
        #expect(calls.count == 2)
    }

    @Test
    func `verdicts are reported for the caller's path, not the inode path assessed`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let codex = try fixture.executable("codex")
        let memo = Self.memo()
        var assessedPaths: [String] = []
        let first = memo.assessment(path: codex.path, isDefinitive: { _ in true }, assess: { assessed in
            assessedPaths.append(assessed)
            return Assessment(output: "\(assessed): \(Self.notAnApp)", exitStatus: 3)
        })
        let second = memo.assessment(path: codex.path, isDefinitive: { _ in true }, assess: { _ in nil })

        #expect(assessedPaths.count == 1)
        #expect(assessedPaths.first?.hasPrefix("/.vol/") == true)
        #expect(first?.output.hasPrefix("\(codex.path): rejected") == true)
        #expect(second?.output == first?.output)
    }

    @Test
    func `launch decisions follow the memoized verdict to the final effect`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let codex = try fixture.executable("codex", contents: "signed release")
        let memo = Self.memo()
        let calls = Counter()
        var revoked = false
        let decide = { (now: TimeInterval) -> Bool in
            CodexLaunchPreflight.isLaunchCandidateAllowed(
                path: codex.path,
                fileManager: .default,
                hasExtendedAttribute: { _, _ in false },
                spctlAssessment: { path in
                    memo.assessment(
                        path: path,
                        now: now,
                        isDefinitive: { CodexLaunchPreflight.isDefinitiveAssessment($0.output, path: path) },
                        assess: { path in
                            calls.increment()
                            let unsigned = (try? String(contentsOfFile: path, encoding: .utf8)) != "signed release"
                            let verdict = revoked
                                ? "rejected (CSSMERR_TP_CERT_REVOKED)"
                                : unsigned ? "rejected\nsource=no usable signature" : Self.notAnApp
                            return Assessment(output: "\(path): \(verdict)", exitStatus: 3)
                        })
                },
                appSignatureIsTrusted: { _ in false },
                isMachOExecutable: { _ in true })
        }

        #expect(decide(0))
        #expect(decide(1))
        #expect(calls.count == 1)

        // Replacing the executable is caught on the next lookup, not after the lifetime.
        try Data("unsigned replacement".utf8).write(to: codex)
        #expect(!decide(2))
        #expect(!decide(3))
        #expect(calls.count == 2)

        // A revocation that leaves the file untouched takes effect once the verdict expires.
        try Data("signed release".utf8).write(to: codex)
        #expect(decide(4))
        revoked = true
        #expect(decide(4 + Memo.lifetime - 1))
        #expect(!decide(4 + Memo.lifetime))
        #expect(calls.count == 4)
    }

    private final class Decisions: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Bool] = [:]
        subscript(name: String) -> Bool? {
            get { self.lock.withLock { self.values[name] } }
            set { self.lock.withLock { self.values[name] = newValue } }
        }
    }

    @Test
    func `no caller inherits a verdict for a target swapped during a shared assessment`() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let signed = try fixture.executable("codex-signed", contents: "signed release")
        let unsigned = try fixture.executable("codex-unsigned", contents: "unsigned replacement")
        let link = fixture.root.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: signed)
        let started = DispatchSemaphore(value: 0)
        let joined = DispatchSemaphore(value: 0)
        let memo = Self.memo(onJoin: { joined.signal() })
        let calls = Counter()
        let decisions = Decisions()
        let path = link.path

        let decide: @Sendable () -> Bool = {
            CodexLaunchPreflight.isLaunchCandidateAllowed(
                path: path,
                fileManager: .default,
                hasExtendedAttribute: { _, _ in false },
                spctlAssessment: { candidate in
                    memo.assessment(
                        path: candidate,
                        isDefinitive: { CodexLaunchPreflight.isDefinitiveAssessment($0.output, path: candidate) },
                        assess: { candidate in
                            calls.increment()
                            // Gatekeeper reads whatever the link names when the assessment starts.
                            let isSigned = (try? String(contentsOfFile: candidate, encoding: .utf8)) == "signed release"
                            if calls.count == 1 {
                                started.signal()
                                _ = joined.wait(timeout: .now() + 5)
                                // Retarget to the forbidden binary while the shared assessment is running.
                                try? FileManager.default.removeItem(at: link)
                                try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: unsigned)
                            }
                            let verdict = isSigned ? Self.notAnApp : "rejected\nsource=no usable signature"
                            return Assessment(output: "\(candidate): \(verdict)", exitStatus: 3)
                        })
                },
                appSignatureIsTrusted: { _ in false },
                isMachOExecutable: { _ in true })
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            decisions["leader"] = decide()
            group.leave()
        }
        _ = started.wait(timeout: .now() + 5)
        group.enter()
        DispatchQueue.global().async {
            decisions["waiter"] = decide()
            group.leave()
        }
        _ = group.wait(timeout: .now() + 10)

        // Both lookups now name the unsigned binary, so neither may be allowed on the signed one's verdict.
        #expect(decisions["leader"] == false)
        #expect(decisions["waiter"] == false)
        #expect(calls.count == 3)
    }

    @Test
    func `only accepted and rejected verdicts are definitive`() {
        let path = "/tools/bin/codex"
        #expect(CodexLaunchPreflight.isDefinitiveAssessment("\(path): \(Self.notAnApp)", path: path))
        #expect(CodexLaunchPreflight.isDefinitiveAssessment(
            "\(path): accepted\nsource=Notarized Developer ID",
            path: path))
        #expect(!CodexLaunchPreflight.isDefinitiveAssessment(
            "spctl: syspolicyd is unavailable",
            path: path))
        #expect(!CodexLaunchPreflight.isDefinitiveAssessment("", path: path))
    }
}
#endif
