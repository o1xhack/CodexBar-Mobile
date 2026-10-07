import Foundation
import Testing
@testable import CodexBarCore

struct CodexExecutableResolverTests {
    @Test
    func `explicit RPC executable survives rejected implicit discovery`() {
        let reject: @Sendable ([String: String]) -> String? = { _ in nil }
        BinaryLocator.$codexBinaryResolverOverrideForTesting.withValue(reject) {
            let environment = ["PATH": "/usr/bin:/bin", "SHELL": "/bin/sh"]
            let resolution = defaultCodexExecutableResolver(environment, "/usr/bin/true")
            #expect(resolution?.executable == "/usr/bin/true")
            #expect(defaultCodexExecutableResolver(environment, "codex") == nil)
        }
    }

    @Test
    func `rejected discovery stops RPC before process launch`() async {
        let fetcher = UsageFetcher(
            environment: ["PATH": "/synthetic/bin"],
            initializeTimeoutSeconds: 1,
            requestTimeoutSeconds: 1,
            codexExecutableResolver: { environment, _ in
                resolveCodexExecutableForRPC(
                    environment: environment,
                    executable: "codex",
                    captureLoginPATH: { ["/synthetic/login/bin"] },
                    locateBinary: { environment, loginPATH in
                        #expect(environment["PATH"] == "/synthetic/bin")
                        #expect(loginPATH == ["/synthetic/login/bin"])
                        return nil
                    })
            })
        do {
            _ = try await fetcher.loadLatestCLIAccountSnapshot()
            Issue.record("Rejected discovery must fail before RPC launch")
        } catch CodexStatusProbeError.codexNotInstalled {
            // The RPC initializer rejects nil before configuring or launching the process.
        } catch {
            Issue.record("Unexpected RPC error: \(error)")
        }
    }

    @Test
    func `explicit native override skips login path capture`() {
        let resolved = resolveCodexExecutableForRPC(
            environment: ["CODEX_CLI_PATH": "/usr/bin/true"],
            executable: "codex",
            captureLoginPATH: {
                Issue.record("Native override should not capture a login-shell PATH")
                return nil
            })

        #expect(resolved?.executable == "/usr/bin/true")
        #expect(resolved?.loginPATH == nil)
    }

    @Test
    func `explicit script override captures login path for env based launchers`() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-script-override-\(UUID().uuidString)")
        try Data("#!/usr/bin/env node\n".utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let loginPATH = ["/custom/node/bin", "/usr/bin"]
        var captureCount = 0
        let resolved = resolveCodexExecutableForRPC(
            environment: ["CODEX_CLI_PATH": scriptURL.path],
            executable: "codex",
            captureLoginPATH: {
                captureCount += 1
                return loginPATH
            })

        #expect(resolved?.executable == scriptURL.path)
        #expect(resolved?.loginPATH == loginPATH)
        #expect(captureCount == 1)
    }
}
