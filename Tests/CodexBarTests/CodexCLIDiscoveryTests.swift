import Foundation
import Testing
@testable import CodexBarCore

struct CodexCLIDiscoveryTests {
    #if os(macOS)
    @Test(arguments: ["pty", "status"])
    func `supplied environment rejection cannot fall back to the process environment`(entrypoint: String) async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let package = root.appendingPathComponent("node_modules/@openai/codex")
        let wrapper = package.appendingPathComponent("bin/codex.js")
        let payload = package.appendingPathComponent("vendor/aarch64-apple-darwin/bin/codex")
        for directory in [wrapper.deletingLastPathComponent(), payload.deletingLastPathComponent()] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? fm.removeItem(at: root) }
        let marker = root.appendingPathComponent("launched")
        let script = """
        #!/bin/sh
        # path.join(vendorRoot, targetTriple, "bin")
        /usr/bin/touch "$CODEXBAR_TEST_LAUNCH_MARKER"
        printf 'Credits: 1\\n'
        """
        try Data(script.utf8).write(to: wrapper)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        try FakeExecutable.install("exit 0", at: payload)
        try FakeExecutable.install(
            #"printf '%s' '{"architecture":"arm64","packageRoot":null}'"#,
            at: root.appendingPathComponent("node"))
        let environment = [
            "PATH": root.path,
            "HOME": root.path,
            "TMPDIR": root.path,
            "NODE_OPTIONS": "--require=/fixture/forbidden-preload.cjs",
            "CODEXBAR_TEST_LAUNCH_MARKER": marker.path,
        ]
        let resolver: @Sendable ([String: String]) -> String? = { supplied in
            var isolated = supplied
            isolated["PATH"] = root.path
            return CodexLaunchPreflight.isLaunchCandidateAllowed(path: wrapper.path, environment: isolated)
                ? wrapper.path : nil
        }
        #expect(resolver([:]) == wrapper.path)
        #expect(resolver(environment) == nil)
        await BinaryLocator.$codexBinaryResolverOverrideForTesting.withValue(resolver) {
            do {
                if entrypoint == "pty" {
                    _ = try TTYCommandRunner().run(
                        binary: "codex",
                        send: "",
                        options: .init(timeout: 5, baseEnvironment: environment, initialDelay: 0))
                } else {
                    _ = try await CodexStatusProbe(timeout: 5, environment: environment).fetch()
                }
                Issue.record("Rejected discovery must stop before launch")
            } catch TTYCommandRunner.Error.binaryNotFound where entrypoint == "pty" {
                // The rejected locator result is terminal.
            } catch CodexStatusProbeError.codexNotInstalled where entrypoint == "status" {
                // The rejected locator result is terminal.
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
            #expect(!fm.fileExists(atPath: marker.path))
        }
    }

    @Test(arguments: ["relative", "mixed-relative", "leading-empty", "trailing-empty", "preload", "absolute"])
    func `Node discovery only runs an absolute interpreter without preload options`(configuration: String) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let relative = String(
            repeating: "../",
            count: URL(fileURLWithPath: fm.currentDirectoryPath)
                .pathComponents.count - 1) + root.path.dropFirst()
        let trusted = root.appendingPathComponent("trusted")
        try fm.createDirectory(at: trusted, withIntermediateDirectories: true)
        let node = trusted.appendingPathComponent("node")
        let marker = root.appendingPathComponent("executed")
        let plantedMarker = root.appendingPathComponent("planted")
        try FakeExecutable.install(
            "/usr/bin/touch \"$CODEXBAR_PLANTED_NODE_MARKER\"", at: root.appendingPathComponent("node"))
        let script = """
        #!/bin/sh
        /usr/bin/touch "$CODEXBAR_NODE_TEST_MARKER"
        printf '%s' '{"architecture":"arm64","packageRoot":null}'
        """
        try Data(script.utf8).write(to: node)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let path = switch configuration {
        case "relative": relative
        case "mixed-relative": "\(relative):\(trusted.path)"
        case "leading-empty": ":\(trusted.path)"
        case "trailing-empty": "\(trusted.path):"
        default: trusted.path
        }
        let environment = [
            "PATH": path,
            "CODEXBAR_NODE_TEST_MARKER": marker.path,
            "CODEXBAR_PLANTED_NODE_MARKER": plantedMarker.path,
            "NODE_OPTIONS": configuration == "preload" ? "--require=/fixture/preload.cjs" : "",
        ]
        let result = CodexLaunchPreflight.nodePackageResolution(
            wrapper: "/fixture/node_modules/@openai/codex/bin/codex.js",
            environment: environment,
            fileManager: fm)
        let shouldExecute = configuration != "relative" && configuration != "preload"
        #expect((result != nil) == shouldExecute)
        let executed = fm.fileExists(atPath: marker.path)
        #expect(executed == shouldExecute)
        #expect(!fm.fileExists(atPath: plantedMarker.path))
    }

    @Test(arguments: ["/Applications", "/Users/test/Applications"])
    func `resolves current ChatGPT launcher with bundle validation`(applications: String) {
        let bundle = "\(applications)/ChatGPT.app"
        let launcher = "\(bundle)/Contents/Resources/codex-cli/bin/codex"
        let fm = MockFileManager(executables: [launcher])
        var assessed: [String] = []
        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": "/missing/bin"],
            loginPATH: nil,
            commandV: { _, _, _, _ in nil },
            aliasResolver: { _, _, _, _, _ in nil },
            launchCandidateFilter: { path, fileManager in
                CodexLaunchPreflight.isLaunchCandidateAllowed(
                    path: path,
                    fileManager: fileManager,
                    hasExtendedAttribute: { _, _ in false },
                    spctlAssessment: { path in
                        assessed.append(path)
                        return .init(output: "accepted", exitStatus: 0)
                    },
                    appSignatureIsTrusted: { $0 == bundle },
                    isMachOExecutable: { _ in false })
            },
            fileManager: fm,
            home: "/Users/test")
        #expect(resolved == launcher)
        #expect(assessed == [bundle])
    }

    @Test(arguments: ["untrusted", "rejected", "unavailable"])
    func `current ChatGPT launcher still fails closed on untrusted bundle`(failure: String) {
        let launcher = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: launcher,
            fileManager: MockFileManager(executables: [launcher]),
            hasExtendedAttribute: { _, _ in false },
            spctlAssessment: { _ in
                failure == "unavailable" ? nil : .init(
                    output: failure == "rejected" ? "rejected" : "accepted",
                    exitStatus: failure == "rejected" ? 1 : 0)
            },
            appSignatureIsTrusted: { _ in failure != "untrusted" },
            isMachOExecutable: { _ in false })
        #expect(!allowed)
    }

    @Test(arguments: [false, true])
    func `npm payload availability preserves PATH precedence or falls through to ChatGPT`(payloadPresent: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let wrapper = root.appendingPathComponent("node_modules/@openai/codex/bin/codex.js")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: wrapper.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try Data().write(to: wrapper)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("codex"), withDestinationURL: wrapper)
        defer { try? FileManager.default.removeItem(at: root) }
        let launcher = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        let native = root.appendingPathComponent(
            "node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex").path
        let shim = bin.appendingPathComponent("codex").path
        var executables: Set<String> = [shim, launcher]
        if payloadPresent { executables.insert(native) }
        let fm = MockFileManager(executables: executables)
        let resolved = BinaryLocator.resolveCodexBinary(
            env: ["PATH": bin.path],
            loginPATH: nil,
            commandV: { _, _, _, _ in nil },
            aliasResolver: { _, _, _, _, _ in nil },
            launchCandidateFilter: { path, fileManager in
                CodexLaunchPreflight.isLaunchCandidateAllowed(
                    path: path,
                    fileManager: fileManager,
                    hasExtendedAttribute: { _, _ in false },
                    spctlAssessment: { _ in .init(output: "accepted", exitStatus: 0) },
                    appSignatureIsTrusted: { _ in true },
                    isMachOExecutable: { _ in false },
                    npmExecutableResolver: { _, _ in payloadPresent ? native : nil })
            },
            fileManager: fm,
            home: root.path)
        #expect(resolved == (payloadPresent ? shim : launcher))
    }

    @Test(arguments: ["nested", "hoisted", "legacy", "missing"], ["bin", "codex"])
    func `npm native payload availability controls wrapper eligibility`(layout: String, directory: String) {
        for (package, triple) in [
            ("codex-darwin-arm64", "aarch64-apple-darwin"),
            ("codex-darwin-x64", "x86_64-apple-darwin"),
        ] {
            let root = "/fixture/node_modules/@openai/codex"
            let wrapper = "\(root)/bin/codex.js"
            let payloadRoot = switch layout {
            case "nested": "\(root)/node_modules/@openai/\(package)"
            case "hoisted": "/fixture/node_modules/@openai/\(package)"
            default: root
            }
            let native = "\(payloadRoot)/vendor/\(triple)/\(directory)/codex"
            let source = switch directory {
            case "bin": "path.join(vendorRoot, targetTriple, \"bin\")"
            default: "path.join(archRoot, \"codex\")"
            }
            let fm = MockFileManager(
                executables: layout == "missing" ? [wrapper] : [wrapper, native],
                contents: [wrapper: Data(source.utf8)])
            var assessed: [String] = []
            let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
                path: wrapper,
                fileManager: fm,
                hasExtendedAttribute: { _, _ in false },
                spctlAssessment: { path in
                    assessed.append(path)
                    return .init(output: "accepted", exitStatus: 0)
                },
                appSignatureIsTrusted: { _ in false },
                isMachOExecutable: { $0 == native && layout != "missing" },
                npmExecutableResolver: { path, manager in
                    CodexLaunchPreflight.npmNativeExecutable(for: path, fileManager: manager) { _ in
                        .init(
                            architecture: package.hasSuffix("arm64") ? "arm64" : "x64",
                            packageRoot: layout == "legacy" ? nil : payloadRoot)
                    }
                })
            #expect(allowed == (layout != "missing"))
            #expect(assessed == (layout == "missing" ? [] : [native]))
        }
    }

    @Test(arguments: ["arm64", "x64"], ["allowed", "missing", "rejected"])
    func `mixed payloads assess only the executable selected by Node`(architecture: String, outcome: String) {
        let wrapper = "/fixture/node_modules/@openai/codex/bin/codex.js"
        let packageRoot = "/fixture/node_modules/@openai/codex-darwin-\(architecture)"
        let triple = architecture == "arm64" ? "aarch64-apple-darwin" : "x86_64-apple-darwin"
        let selected = "\(packageRoot)/vendor/\(triple)/bin/codex"
        let stale = "\(packageRoot)/vendor/\(triple)/codex/codex"
        let otherArchitecture = architecture == "arm64" ? "x64" : "arm64"
        let otherTriple = architecture == "arm64" ? "x86_64-apple-darwin" : "aarch64-apple-darwin"
        let other = "/fixture/node_modules/@openai/codex-darwin-\(otherArchitecture)/vendor/\(otherTriple)/bin/codex"
        var executables: Set<String> = [wrapper, stale, other]
        if outcome == "missing" { executables.remove(selected) } else { executables.insert(selected) }
        let fm = MockFileManager(
            executables: executables,
            contents: [wrapper: Data("path.join(vendorRoot, targetTriple, \"bin\")".utf8)])
        var assessed: [String] = []
        let allowed = CodexLaunchPreflight.isLaunchCandidateAllowed(
            path: wrapper,
            fileManager: fm,
            hasExtendedAttribute: { _, _ in false },
            spctlAssessment: { path in
                assessed.append(path)
                return .init(
                    output: outcome == "rejected" ? "rejected" : "accepted",
                    exitStatus: outcome == "rejected" ? 1 : 0)
            },
            appSignatureIsTrusted: { _ in false },
            isMachOExecutable: { executables.contains($0) && $0 != wrapper },
            npmExecutableResolver: { path, manager in
                CodexLaunchPreflight.npmNativeExecutable(for: path, fileManager: manager) { _ in
                    .init(architecture: architecture, packageRoot: packageRoot)
                }
            })
        #expect(allowed == (outcome == "allowed"))
        #expect(assessed == (outcome == "missing" ? [] : [selected]))
    }

    @Test(arguments: ["legacy", "current", "both", "non-executable-current", "missing"])
    func `transitional npm launcher selects the first existing payload`(layout: String) {
        let root = "/fixture/node_modules/@openai/codex"
        let wrapper = "\(root)/bin/codex.js"
        let current = "\(root)/vendor/aarch64-apple-darwin/bin/codex"
        let legacy = "\(root)/vendor/aarch64-apple-darwin/codex/codex"
        // Selection excerpt from openai/codex rust-v0.136.0, codex-cli/bin/codex.js.
        let source = #"""
        const packageBinaryPath = (vendorRoot) =>
          path.join(vendorRoot, targetTriple, "bin", codexBinaryName);
        const legacyBinaryPath = (vendorRoot) =>
          path.join(vendorRoot, targetTriple, "codex", codexBinaryName);
        function resolveNativePackage(vendorRoot) {
          const packageRoot = path.join(vendorRoot, targetTriple);
          const binaryPath = packageBinaryPath(vendorRoot);
          if (existsSync(binaryPath)) {
            return { binaryPath, pathDir: path.join(packageRoot, "codex-path") };
          }
          const legacyPath = legacyBinaryPath(vendorRoot);
          if (existsSync(legacyPath)) {
            return { binaryPath: legacyPath, pathDir: path.join(packageRoot, "path") };
          }
          return null;
        }
        """#
        let executables: Set<String> = switch layout {
        case "legacy", "non-executable-current": [legacy]
        case "current": [current]
        case "both": [current, legacy]
        default: []
        }
        let fm = MockFileManager(
            executables: executables,
            contents: [wrapper: Data(source.utf8)],
            existingFiles: layout == "non-executable-current" ? [current] : [])
        let resolved = CodexLaunchPreflight.npmNativeExecutable(for: wrapper, fileManager: fm) { _ in
            .init(architecture: "arm64", packageRoot: nil)
        }
        let expected: String? = switch layout {
        case "legacy": legacy
        case "current", "both": current
        default: nil
        }
        #expect(resolved == expected)
    }

    #endif
}

private final class MockFileManager: FileManager {
    private let executables: Set<String>
    private let fileContents: [String: Data]
    private let existingFiles: Set<String>

    init(executables: Set<String>, contents: [String: Data] = [:], existingFiles: Set<String> = []) {
        self.executables = executables
        self.fileContents = contents
        self.existingFiles = executables.union(existingFiles)
    }

    override func contents(atPath path: String) -> Data? {
        self.fileContents[path]
    }

    override func isExecutableFile(atPath path: String) -> Bool {
        self.executables.contains(path)
    }

    override func fileExists(atPath path: String) -> Bool {
        self.existingFiles.contains(path)
    }
}
