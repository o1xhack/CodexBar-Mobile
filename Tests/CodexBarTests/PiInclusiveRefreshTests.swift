import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI
@testable import CodexBarCore

struct PiInclusiveRefreshTests {
    @Test(arguments: [UsageProvider.codex, .claude, .pi])
    func `forced refresh reparses Pi history with unchanged file metadata`(provider: UsageProvider) async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 9)
        var nativeOptions = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: [env.claudeProjectsRoot],
            cacheRoot: env.cacheRoot)
        nativeOptions.refreshMinIntervalSeconds = 0
        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            cacheRoot: env.cacheRoot,
            refreshMinIntervalSeconds: 0,
            environment: ["HOME": env.root.path])
        func contents(input: Int) throws -> String {
            try env.jsonl([["type": "message", "id": "turn", "timestamp": env.isoString(for: day), "message": [
                "role": "assistant",
                "provider": provider == .claude ? "anthropic" : "openai-codex",
                "model": provider == .claude ? "claude-sonnet-4-6" : "openai/gpt-5.4",
                "usage": ["input": input, "output": 5, "totalTokens": input + 5],
            ]]])
        }
        func refresh(force: Bool) async throws -> CostUsageTokenSnapshot {
            try await CostUsageFetcher.loadTokenSnapshot(
                provider: provider,
                environment: ["HOME": env.root.path],
                now: day,
                forceRefresh: force,
                historyDays: 1,
                allowPricingRefresh: false,
                includePiSessions: true,
                scannerOptions: nativeOptions,
                piScannerOptions: piOptions)
        }
        let original = try contents(input: 10)
        let replacement = try contents(input: 20)
        #expect(original.utf8.count == replacement.utf8.count)
        let file = try env.writePiSessionFile(relativePath: "same-metadata.jsonl", contents: original)
        try FileManager.default.setAttributes([.modificationDate: day], ofItemAtPath: file.path)
        let initial = try await refresh(force: false)
        #expect(initial.last30DaysTokens == 15)
        #expect(initial.historyCoverageIsEstablished)

        // Overwrite the same inode; an ordinary metadata check cannot detect this edit.
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data(replacement.utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: day], ofItemAtPath: file.path)
        #expect(try await refresh(force: false).last30DaysTokens == 15)

        let forced = try await refresh(force: true)
        #expect(forced.last30DaysTokens == 25)
        #expect(forced.historyCoverageIsEstablished)
    }

    @Test(arguments: [false, true])
    func `an incomplete Pi mirror keeps the priced Claude total as a lower bound`(useOMP: Bool) async throws {
        let env = try CostUsageTestEnvironment()
        defer { env.cleanup() }
        let day = try env.makeLocalNoon(year: 2026, month: 4, day: 9)
        var nativeOptions = CostUsageScanner.Options(
            codexSessionsRoot: env.codexSessionsRoot,
            claudeProjectsRoots: [env.claudeProjectsRoot],
            cacheRoot: env.cacheRoot)
        nativeOptions.refreshMinIntervalSeconds = 0
        let ompSessionsRoot = env.root.appendingPathComponent("empty-omp", isDirectory: true)
        try FileManager.default.createDirectory(at: ompSessionsRoot, withIntermediateDirectories: true)
        let piOptions = PiSessionCostScanner.Options(
            piSessionsRoot: env.piSessionsRoot,
            ompSessionsRoot: ompSessionsRoot,
            cacheRoot: env.cacheRoot,
            calendar: .current,
            refreshMinIntervalSeconds: 0,
            environment: ["HOME": env.root.path])
        let claudeRow: [String: Any] = [
            "type": "assistant",
            "timestamp": env.isoString(for: day),
            "sessionId": "native-claude",
            "message": [
                "id": "native-claude-row",
                "model": "claude-sonnet-4-6",
                "usage": [
                    "input_tokens": 100_000,
                    "output_tokens": 1000,
                ],
            ],
        ]
        _ = try env.writeClaudeProjectFile(
            relativePath: "project-a/native-claude.jsonl",
            contents: env.jsonl([claudeRow]))
        let piRow: [String: Any] = [
            "type": "message",
            "id": "pi-claude",
            "timestamp": env.isoString(for: day),
            "message": [
                "role": "assistant",
                "provider": "anthropic",
                "model": "claude-sonnet-4-6",
                "usage": ["input": 20, "output": 5, "totalTokens": 25],
            ],
        ]
        let piFile = useOMP
            ? ompSessionsRoot.appendingPathComponent("truncated.jsonl")
            : env.piSessionsRoot.appendingPathComponent("truncated.jsonl")
        try env.jsonl([piRow]).write(to: piFile, atomically: true, encoding: .utf8)
        let truncated = try String(contentsOf: piFile, encoding: .utf8) + "{\"type\":\"message\""
        try truncated.write(to: piFile, atomically: true, encoding: .utf8)

        func load(includePiSessions: Bool, forceRefresh: Bool = false) async throws -> CostUsageTokenSnapshot {
            try await CostUsageFetcher.loadTokenSnapshot(
                provider: .claude,
                environment: ["HOME": env.root.path],
                now: day,
                forceRefresh: forceRefresh,
                historyDays: 1,
                allowPricingRefresh: false,
                refreshPricingInBackground: false,
                includePiSessions: includePiSessions,
                scannerOptions: nativeOptions,
                piScannerOptions: piOptions)
        }

        let native = try await load(includePiSessions: false)
        #expect(native.historyCoverageIsEstablished)
        #expect(!native.historyScanIsPartial)
        let nativeCost = try #require(native.last30DaysCostUSD)
        #expect(nativeCost > 0)

        let merged = try await load(includePiSessions: true)
        #expect(!merged.historyCoverageIsEstablished)
        #expect(merged.historyScanIsPartial)
        #expect(merged.last30DaysCostUSD == nativeCost)

        let model = SpendDashboardModel.build(
            inputs: [.init(provider: .claude, displayName: "Claude", snapshot: merged)],
            requestedDays: 1,
            now: day)
        let group = try #require(model.groups.first)
        let provider = try #require(group.providers.first)
        #expect(provider.totalCost == nativeCost)
        #expect(provider.costIsLowerBound)
        let payload = try #require(ShareStatsBuilder.make(model: model))
        let text = ShareStatsFormatting.text(payload)
        #expect(text.contains("(partial)"))
        #expect(!text.contains("Spend unavailable"))
        let overview = OverviewSpendSummary(model: model, providerCount: 1)
        #expect(overview.primarySpendText == "~" + UsageFormatter.currencyString(nativeCost, currencyCode: "USD"))
        let cli = CodexBarCLI.makeCostPayload(provider: .claude, snapshot: merged, error: nil)
        #expect(cli.historyCoverageIsEstablished == false)
        #expect(cli.totals?.totalCostUSD == nativeCost)
        let cliText = CodexBarCLI.renderCostText(provider: .claude, snapshot: merged, useColor: false)
        #expect(cliText.contains("Partial local history"))
        #expect(cliText.contains(UsageFormatter.currencyString(nativeCost, currencyCode: "USD")))

        // Repairing the mirror must restore complete coverage and include its priced usage.
        try env.jsonl([piRow]).write(to: piFile, atomically: true, encoding: .utf8)
        let complete = try await load(includePiSessions: true, forceRefresh: true)
        #expect(complete.historyCoverageIsEstablished)
        #expect(!complete.historyScanIsPartial)
        #expect(try #require(complete.last30DaysCostUSD) > nativeCost)
    }
}
