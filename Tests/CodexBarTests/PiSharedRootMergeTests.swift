import Foundation
import Testing
@testable import CodexBarCore

struct PiSharedRootMergeTests {
    @Test
    func `live omp profiles suppress unrelated ambient discovery`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        func profileRoot(_ name: String) -> URL {
            env.root
                .appendingPathComponent(".omp", isDirectory: true)
                .appendingPathComponent("profiles", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("agent", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }

        let selectedRoots = [profileRoot("work"), profileRoot("personal")]
        let unrelatedRoot = profileRoot("unrelated")
        try (selectedRoots + [unrelatedRoot]).forEach {
            try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
        }

        let roots = PiFamilySessionScanner.costSessionRoots(
            environment: ["HOME": env.root.path],
            baseDirectories: [env.root],
            processContexts: selectedRoots.map { root in
                let profile = root
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .lastPathComponent
                return PiSessionProcessContext(
                    command: "/usr/local/bin/omp --profile \(profile)",
                    workingDirectory: env.root,
                    selectorEnvironment: ["HOME": env.root.path])
            })

        #expect(selectedRoots.allSatisfy { selected in
            roots.contains { $0.url == selected.standardizedFileURL && $0.preserveAfterProcessExit }
        })
        #expect(!roots.contains { $0.url == unrelatedRoot.standardizedFileURL })
    }

    @Test
    func `same pi dialect root keeps required process provenance`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let sharedRoot = env.root
            .appendingPathComponent(".pi", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        let roots = PiFamilySessionScanner.costSessionRoots(
            environment: ["HOME": env.root.path],
            baseDirectories: [env.root],
            processContexts: [
                PiSessionProcessContext(
                    command: "pi",
                    workingDirectory: env.root,
                    selectorEnvironment: ["HOME": env.root.path]),
                PiSessionProcessContext(
                    command: "pi --session-dir \(sharedRoot.path)",
                    workingDirectory: env.root),
            ])

        let root = try #require(roots.first { $0.url == sharedRoot.standardizedFileURL })
        #expect(!root.missingIsKnownEmpty)
        #expect(root.preserveAfterProcessExit)
        #expect(root.retentionKeys == ["process:pi:session-dir:\(sharedRoot.standardizedFileURL.path)"])
    }

    @Test
    func `custom agent dir root identity does not depend on directory existence`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let agentDir = env.root.appendingPathComponent("custom-pi-agent", isDirectory: true)
        let sessionsRoot = agentDir.appendingPathComponent("sessions", isDirectory: true)
        let environment = [
            "HOME": env.root.path,
            "PI_CODING_AGENT_DIR": agentDir.path,
        ]

        // The directory is absent on disk: canonicalization must keep the
        // directory marker so the resolved root stays identical once it appears.
        let missing = OMPSessionRootResolver.sessionRoots(
            environment: environment,
            baseDirectory: env.root)
        let missingRoot = try #require(missing.first { $0.path.hasSuffix("custom-pi-agent/sessions") })
        #expect(missingRoot.hasDirectoryPath)

        let missingCostRoot = try #require(PiFamilySessionScanner.costSessionRoots(
            environment: environment,
            baseDirectories: [env.root]).first { $0.url.path == missingRoot.path })
        #expect(missingCostRoot.url.hasDirectoryPath)

        try FileManager.default.createDirectory(
            at: sessionsRoot,
            withIntermediateDirectories: true)
        #expect(OMPSessionRootResolver.sessionRoots(
            environment: environment,
            baseDirectory: env.root) == missing)
        #expect(PiFamilySessionScanner.costSessionRoots(
            environment: environment,
            baseDirectories: [env.root]).first { $0.url.path == missingRoot.path }?.url == missingCostRoot.url)
    }

    @Test
    func `shared pi and omp root keeps required process provenance`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }

        let sharedRoot = env.root
            .appendingPathComponent(".pi", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        let roots = PiFamilySessionScanner.costSessionRoots(
            environment: ["HOME": env.root.path],
            baseDirectories: [env.root],
            processContexts: [
                PiSessionProcessContext(
                    command: "omp --session-dir \(sharedRoot.path)",
                    workingDirectory: env.root),
            ])

        let root = try #require(roots.first { $0.url == sharedRoot.standardizedFileURL })
        #expect(!root.missingIsKnownEmpty)
        #expect(root.preserveAfterProcessExit)
        #expect(root.retentionKeys == ["process:omp:session-dir:\(sharedRoot.standardizedFileURL.path)"])
    }
}
