import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct CostUsageScannerClaudeSwapTests {
    @Test
    func `two swap homes contribute once across copied and shared history`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 9, day: 20)
        let sessions = env.root.appendingPathComponent(".claude-swap-backup/sessions", isDirectory: true)
        let first = sessions.appendingPathComponent("1-first/projects", isDirectory: true)
        let second = sessions.appendingPathComponent("2-second/projects", isDirectory: true)
        let shared = sessions.appendingPathComponent("3-shared/projects", isDirectory: true)
        let rows = [
            Self.row(env: env, day: day, id: "first", input: 100),
            Self.row(env: env, day: day, id: "second", input: 200),
        ]
        try Self.write(env.jsonl([rows[0]]), root: first)
        try Self.write(env.jsonl(rows), root: second)
        try FileManager.default.createDirectory(
            at: shared.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: shared, withDestinationURL: first)
        let missing = sessions.appendingPathComponent("4-missing/projects", isDirectory: true)
        try FileManager.default.createDirectory(
            at: missing.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: missing,
            withDestinationURL: env.root.appendingPathComponent("gone"))
        try Self.write(
            env.jsonl([Self.row(env: env, day: day, id: "decoy", input: 999)]),
            root: sessions.appendingPathComponent("unrelated/projects", isDirectory: true))

        let roots = CostUsageScanner.defaultClaudeProjectsRoots(
            options: .init(), environment: [:], homeDirectory: env.root)
        #expect(roots.contains(first.standardizedFileURL))
        #expect(roots.contains(second.standardizedFileURL))
        #expect(roots.filter { $0.resolvingSymlinksInPath() == first.resolvingSymlinksInPath() }.count == 1)
        let options = CostUsageScanner.Options(claudeProjectsRoots: roots, cacheRoot: env.cacheRoot)
        for now in [day, day.addingTimeInterval(120)] {
            let report = CostUsageScanner.loadDailyReport(
                provider: .claude, since: day, until: day, now: now, options: options)
            #expect(report.summary?.totalTokens == 320)
            #expect(try abs(#require(report.summary?.totalCostUSD) - 0.0012) < 0.000000001)
        }
        #expect(SettingsStore.hasAnyTokenCostUsageSources(env: [:], homeDirectory: env.root))
    }

    @Test
    func `literal configured home remains included beside discovered swap homes`() throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let configured = env.root.appendingPathComponent("custom, home/projects", isDirectory: true)
        let swap = env.root.appendingPathComponent(".claude-swap-backup/sessions/2-second/projects", isDirectory: true)
        try Self.write("", root: swap)
        let roots = CostUsageScanner.defaultClaudeProjectsRoots(
            options: .init(),
            environment: ["CLAUDE_CONFIG_DIR": configured.deletingLastPathComponent().path],
            homeDirectory: env.root)
        #expect(roots == [configured.standardizedFileURL, swap.standardizedFileURL])
        #expect(CostUsageScanner.defaultClaudeProjectsRoots(
            options: .init(claudeProjectsRoots: [configured]), environment: [:], homeDirectory: env.root) ==
            [configured])
    }

    private static func row(env: CostUsageTestEnvironment, day: Date, id: String, input: Int) -> [String: Any] {
        [
            "type": "assistant",
            "timestamp": env.isoString(for: day),
            "requestId": "request-\(id)",
            "message": [
                "id": id,
                "model": "claude-sonnet-4-5-20250929",
                "usage": ["input_tokens": input, "output_tokens": 10],
            ],
        ]
    }

    private static func write(_ contents: String, root: URL) throws {
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try contents.write(to: project.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)
    }
}
