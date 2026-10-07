import Foundation
import Testing
@testable import CodexBar

struct CodexLoginRunnerTests {
    @Test(.timeLimit(.minutes(1)))
    func `login runner returns timeout before hung codex exits`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexbar-login-runner-\(UUID().uuidString)", isDirectory: true)
        let binDir = root.appendingPathComponent("bin", isDirectory: true)
        let homeDir = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let codex = binDir.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        printf 'login-started\\n'
        while :; do /bin/sleep 1; done
        """
        try script.write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)

        let result = await CodexLoginRunner.run(
            homePath: homeDir.path,
            timeout: 30,
            environment: ["PATH": binDir.path],
            loginPATH: nil)

        #expect(result.outcome == .timedOut)
        #expect(result.output.contains("login-started"))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `login runner bounds output drain while an owned holder keeps stdout open`(
        blockAfterAcknowledgment: Bool) async throws
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let holder = try GeminiStdoutHolderFixture(root: root)
        defer { #expect(holder.cleanup().succeeded) }
        try holder.installProducer(
            at: root.appendingPathComponent("codex"),
            blockAfterAcknowledgment: blockAfterAcknowledgment)

        let result = await CodexLoginRunner.run(
            homePath: root.path,
            timeout: blockAfterAcknowledgment ? 30 : 120,
            outputDrainTimeout: 0.5,
            environment: ["PATH": root.path],
            loginPATH: nil)

        #expect(result.outcome == (blockAfterAcknowledgment ? .timedOut : .success))
        #expect(result.output.contains("/tmp/gemini-package") == !blockAfterAcknowledgment)
        #expect(try String(contentsOf: holder.pidFile, encoding: .utf8) == String(holder.process.processIdentifier))
        #expect(holder.process.isRunning)
    }
}
