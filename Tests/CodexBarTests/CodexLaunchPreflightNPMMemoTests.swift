import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
struct CodexLaunchPreflightNPMMemoTests {
    @Test(arguments: [true, false], ["standalone", "bundle", "bundle-alias"])
    func `production discovery memo follows Node selection without caching wrapper eligibility`(
        hardened: Bool,
        layout: String) throws
    {
        let fixture = try CodexLaunchPreflightSignatureTests.Fixture(hardened: hardened)
        defer { withExtendedLifetime(fixture) {} }
        let root = fixture.root.resolvingSymlinksInPath()
        let manager = FixtureFileManager(root: root.path)
        let package = root.appendingPathComponent("node_modules/@openai/codex")
        let wrapper = package.appendingPathComponent("bin/codex.js")
        let bin = root.appendingPathComponent("bin")
        let shim = bin.appendingPathComponent("codex")
        let nodeRuns = root.appendingPathComponent("node-runs")
        for directory in [wrapper.deletingLastPathComponent(), bin] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data("#!/usr/bin/env node\n// path.join(vendorRoot, targetTriple, \"bin\")\n".utf8).write(to: wrapper)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        try manager.createSymbolicLink(at: shim, withDestinationURL: wrapper)
        var payloads: [String: URL] = [:]
        var inodes: [String: UInt64] = [:]
        for architecture in ["arm64", "x64"] {
            let triple = architecture == "arm64" ? "aarch64-apple-darwin" : "x86_64-apple-darwin"
            let actualRoot = layout == "standalone" ? package :
                root.appendingPathComponent("Payload.app/Contents/Resources/\(architecture)")
            var payloadRoot = actualRoot
            if layout == "bundle-alias" {
                try manager.createDirectory(at: actualRoot, withIntermediateDirectories: true)
                payloadRoot = root.appendingPathComponent("payload-\(architecture)")
                try manager.createSymbolicLink(at: payloadRoot, withDestinationURL: actualRoot)
            }
            let payload = payloadRoot.appendingPathComponent("vendor/\(triple)/bin/codex")
            let nodeDirectory = root.appendingPathComponent("node-\(architecture)")
            for directory in [payload.deletingLastPathComponent(), nodeDirectory] {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try manager.copyItem(atPath: fixture.path, toPath: payload.path)
            let node = nodeDirectory.appendingPathComponent("node")
            try JSONSerialization.data(withJSONObject: [
                "architecture": architecture, "packageRoot": payloadRoot.path,
            ]).write(to: node.appendingPathExtension("json"))
            try FakeExecutable.install("""
            printf '%s\\n' '\(architecture)' >> "$CODEXBAR_NODE_TEST_MARKER"
            /bin/cat "${0%.sh}.json"
            """, at: node)
            payloads[architecture] = payload
            inodes[architecture] = try #require(Self.inode(payload.path))
        }
        let allowedInode = try #require(inodes["arm64"])
        let rejectedInode = try #require(inodes["x64"])
        let assessed = LockIsolated<[UInt64]>([])
        let hostAllowsMemoization = CodexLaunchPreflight.HostEnforcement.allowsMemoization
        let canMemoize = hardened && hostAllowsMemoization && layout == "standalone"
        let assess: @Sendable (String) -> CodexLaunchPreflight.GatekeeperAssessment? = { path in
            guard let inode = Self.inode(path) else {
                Issue.record("The assessor must receive a fixture payload")
                return nil
            }
            #expect(inode == allowedInode || inode == rejectedInode)
            assessed.setValue(assessed.value + [inode])
            let allowed = inode == allowedInode
            return .init(output: "\(path): \(allowed ? "accepted" : "rejected")", exitStatus: allowed ? 0 : 1)
        }
        try CodexLaunchPreflight.$spctlAssessmentOverrideForTesting.withValue(assess) {
            func resolve(_ architecture: String, extra: [String: String] = [:]) -> String? {
                var environment = [
                    "PATH": "\(bin.path):\(root.path)/node-\(architecture)",
                    "HOME": root.path,
                    "TMPDIR": root.path,
                    "CODEXBAR_NODE_TEST_MARKER": nodeRuns.path,
                ]
                environment.merge(extra) { _, value in value }
                // Exercise the production default filter, including its launch-environment construction.
                return BinaryLocator.resolveCodexBinary(
                    env: environment,
                    loginPATH: [],
                    commandV: { _, _, _, _ in nil },
                    aliasResolver: { _, _, _, _, _ in nil },
                    fileManager: manager,
                    home: root.path)
            }
            #expect(resolve("arm64") == shim.path)
            #expect(resolve("arm64", extra: ["CODEXBAR_TEST_VARIANT": "same-file"]) == shim.path)
            #expect(resolve("x64") == nil)
            #expect(resolve("x64") == nil)
            #expect(resolve("arm64") == shim.path)
            let expected = canMemoize ? [allowedInode, rejectedInode] :
                [allowedInode, allowedInode, rejectedInode, rejectedInode, allowedInode]
            #expect(assessed.value == expected)

            // A cached payload verdict must not skip current Node safety checks or payload availability.
            #expect(resolve("arm64", extra: ["NODE_OPTIONS": "--require=/fixture/blocked.cjs"]) == nil)
            try manager.removeItem(at: #require(payloads["arm64"]))
            #expect(resolve("arm64") == nil)
            #expect(assessed.value == expected)
        }
        let runs = try String(contentsOf: nodeRuns, encoding: .utf8).split(separator: "\n")
        #expect(runs == ["arm64", "arm64", "x64", "x64", "arm64", "arm64"])
        print("npm memo integration: layout=\(layout) hardened=\(hardened) hostGate=\(hostAllowsMemoization) " +
            "lookups=7 nodeRuns=\(runs.count) assessments=\(assessed.value.count)")
    }

    private static func inode(_ path: String) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? NSNumber)?.uint64Value
    }
}

private final class FixtureFileManager: FileManager {
    private let root: String

    init(root: String) { self.root = root + "/" }

    override func isExecutableFile(atPath path: String) -> Bool {
        path.hasPrefix(self.root) && super.isExecutableFile(atPath: path)
    }
}
#endif
