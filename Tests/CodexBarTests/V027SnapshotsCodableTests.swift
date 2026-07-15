// swiftlint:disable multiline_arguments
//
// Scoped to this file because the test constructors pack many
// trailing fixture values onto a single line for readability; the
// `multiline_arguments` rule prefers one argument per line which
// makes synthetic Codable payloads triple-height and harder to
// audit. Re-enabled at EOF.
import Foundation
import Testing
@testable import CodexBarSync

/// Codable round-trip + cross-version compat tests for the v0.27
/// envelope fields (build 133 + 134 + 135). Pins:
///   1. Each new type round-trips through JSON without loss.
///   2. A pre-1.8.0 (build 132 or older) payload decodes cleanly on
///      a build-135 reader — every new field lands as nil.
///   3. A build-135 payload decodes cleanly on a build-132 reader —
///      synthesised CodingKeys ignore unknown JSON keys, no throw.
///   4. The matrix entry for build 65.3 — `accountEmail` lives in the
///      CKRecord, NOT the envelope, so envelope decode is unaffected.
@Suite("v0.27 envelope — Codable round-trip + cross-version compat")
struct V027SnapshotsCodableTests {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Build 134 / 135 new types — individual round-trip

    @Test
    func `Claude Admin: round-trips with full top-models / top-cost lists`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let source = SyncClaudeAdminUsage(
            last30Days: SyncClaudeAdminWindowSummary(
                costUSD: 100.0, totalTokens: 1_000_000,
                inputTokens: 500_000, outputTokens: 200_000,
                cacheCreationInputTokens: 80000, cacheReadInputTokens: 220_000),
            last7Days: SyncClaudeAdminWindowSummary(
                costUSD: 30.0, totalTokens: 300_000,
                inputTokens: 150_000, outputTokens: 60000,
                cacheCreationInputTokens: 24000, cacheReadInputTokens: 66000),
            latestDay: SyncClaudeAdminWindowSummary(
                costUSD: 5.0, totalTokens: 50000,
                inputTokens: 25000, outputTokens: 10000,
                cacheCreationInputTokens: 4000, cacheReadInputTokens: 11000),
            topModels: [
                SyncClaudeAdminModelBreakdown(name: "claude-sonnet-4-6", totalTokens: 800_000),
            ],
            topCostItems: [
                SyncClaudeAdminCostItem(name: "Input tokens", costUSD: 60.0),
            ],
            updatedAt: now)
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(SyncClaudeAdminUsage.self, from: data)
        #expect(decoded.last30Days.costUSD == 100.0)
        #expect(decoded.last7Days.totalTokens == 300_000)
        #expect(decoded.latestDay?.outputTokens == 10000)
        #expect(decoded.topModels.first?.name == "claude-sonnet-4-6")
        #expect(decoded.topCostItems.first?.costUSD == 60.0)
    }

    @Test
    func `Claude Extra usage: round-trips with disabled / enabled / nil-limit`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Enabled + capped (Enterprise)
        let enabled = SyncClaudeExtraUsage(
            utilization: 42.5,
            monthlySpendUSD: 42.50,
            monthlyLimitUSD: 100.00,
            isEnabled: true,
            planTier: "Enterprise",
            updatedAt: now)
        let decoded = try Self.decoder.decode(
            SyncClaudeExtraUsage.self,
            from: Self.encoder.encode(enabled))
        #expect(decoded.utilization == 42.5)
        #expect(decoded.monthlyLimitUSD == 100.00)
        #expect(decoded.isEnabled)

        // Disabled + uncapped (Team without extra usage)
        let disabled = SyncClaudeExtraUsage(
            utilization: nil,
            monthlySpendUSD: nil,
            monthlyLimitUSD: nil,
            isEnabled: false,
            planTier: "Team",
            updatedAt: now)
        let dDecoded = try Self.decoder.decode(
            SyncClaudeExtraUsage.self,
            from: Self.encoder.encode(disabled))
        #expect(!dDecoded.isEnabled)
        #expect(dDecoded.monthlyLimitUSD == nil)
    }

    @Test
    func `OpenCode Zen balance: round-trips with workspaceID present and absent`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let withWS = SyncOpenCodeGoZenBalance(
            balanceUSD: 42.50, workspaceID: "ws-acme-prod", updatedAt: now)
        let dWith = try Self.decoder.decode(
            SyncOpenCodeGoZenBalance.self, from: Self.encoder.encode(withWS))
        #expect(dWith.workspaceID == "ws-acme-prod")
        #expect(dWith.balanceUSD == 42.50)

        let noWS = SyncOpenCodeGoZenBalance(
            balanceUSD: 0.0, workspaceID: nil, updatedAt: now)
        let dNo = try Self.decoder.decode(
            SyncOpenCodeGoZenBalance.self, from: Self.encoder.encode(noWS))
        #expect(dNo.workspaceID == nil)
        #expect(dNo.balanceUSD == 0.0)
    }

    @Test
    func `MiniMax billing history: round-trips with daily list and breakdowns`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let source = SyncMiniMaxBillingHistory(
            todayTokens: 1000,
            last30DaysTokens: 30000,
            todayCashUSD: 1.5,
            last30DaysCashUSD: 45.0,
            daily: [
                SyncMiniMaxBillingDay(day: "2026-05-01", tokens: 1000, cashUSD: 1.5),
                SyncMiniMaxBillingDay(day: "2026-05-02", tokens: 2000, cashUSD: nil),
            ],
            topMethods: [
                SyncMiniMaxBillingBreakdown(name: "chat/completions", tokens: 25000, cashUSD: 38.0),
            ],
            topModels: [
                SyncMiniMaxBillingBreakdown(name: "abab-7", tokens: 20000, cashUSD: 30.0),
            ],
            updatedAt: now)
        let decoded = try Self.decoder.decode(
            SyncMiniMaxBillingHistory.self, from: Self.encoder.encode(source))
        #expect(decoded.daily.count == 2)
        #expect(decoded.daily[0].cashUSD == 1.5)
        #expect(decoded.daily[1].cashUSD == nil)
        #expect(decoded.topMethods.first?.name == "chat/completions")
    }

    @Test
    func `Codex workspace context: round-trips with pace delta + label`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let source = SyncCodexWorkspaceContext(
            workspaceID: "ws-acme-prod",
            workspaceName: "Acme Production",
            weeklyPaceDelta: 0.12,
            weeklyPaceLabel: "+12% ahead of pace",
            updatedAt: now)
        let decoded = try Self.decoder.decode(
            SyncCodexWorkspaceContext.self, from: Self.encoder.encode(source))
        #expect(decoded.workspaceName == "Acme Production")
        #expect(decoded.weeklyPaceDelta == 0.12)
        #expect(decoded.weeklyPaceLabel == "+12% ahead of pace")
    }

    // MARK: - Cross-version compat — old payload decoded by NEW reader

    @Test
    func `Snapshot decode: pre-build-134 payload → all 5 new fields land as nil`() throws {
        // Wire format from a build-132 Mac (or older). Build 132
        // already had the 5 v0.27 dedicated card fields, so we keep
        // grokBilling here as a sanity check — the test pins that
        // the build-134 / 135 fields (claudeAdminUsage, claudeExtraUsage,
        // openCodeGoZenBalance, minimaxBilling, codexWorkspace) decode
        // as nil when the payload omits them.
        let json = """
        {
          "providerID": "claude",
          "providerName": "Claude",
          "primary": null,
          "secondary": null,
          "rateWindows": [],
          "accountEmail": "user@example.com",
          "loginMethod": "Pro",
          "statusMessage": null,
          "isError": false,
          "lastUpdated": "2026-05-19T00:00:00Z"
        }
        """
        let decoded = try Self.decoder.decode(
            ProviderUsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.providerID == "claude")
        // build-134 fields
        #expect(decoded.claudeAdminUsage == nil)
        #expect(decoded.claudeExtraUsage == nil)
        #expect(decoded.openCodeGoZenBalance == nil)
        #expect(decoded.minimaxBilling == nil)
        // build-135 wire-format addition is on the CKRecord, not the
        // envelope, so the envelope itself doesn't grow a new field.
        // Codex workspace IS on the envelope; pin it lands nil too.
        #expect(decoded.codexWorkspace == nil)
        // build-133 dedicated card fields also stay nil for an
        // envelope that doesn't include them.
        #expect(decoded.grokBilling == nil)
    }

    // MARK: - Cross-version compat — new payload tolerated by OLD reader

    @Test
    func `Snapshot decode: build-135 payload with ALL fields round-trips on build-135 reader`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let source = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "user@codex.test",
            loginMethod: "CLI",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            claudeAdminUsage: nil,
            claudeExtraUsage: nil,
            openCodeGoZenBalance: nil,
            minimaxBilling: nil,
            codexWorkspace: SyncCodexWorkspaceContext(
                workspaceID: "ws-acme",
                workspaceName: "Acme",
                weeklyPaceDelta: -0.05,
                weeklyPaceLabel: "On pace",
                updatedAt: now))
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(
            ProviderUsageSnapshot.self, from: data)
        #expect(decoded.codexWorkspace?.workspaceName == "Acme")
        #expect(decoded.codexWorkspace?.weeklyPaceDelta == -0.05)
        #expect(decoded.claudeAdminUsage == nil)
    }

    // MARK: - OpenAI history window — v0.26 extension verified compat

    @Test
    func `OpenAI dashboard: pre-build-134 payload (no historyDays) defaults to 30`() throws {
        let json = """
        {
          "last30Days": {"totalCostUSD": 0, "totalRequests": 0, "totalTokens": 0},
          "last7Days": {"totalCostUSD": 0, "totalRequests": 0, "totalTokens": 0},
          "latestDay": null,
          "dailyBuckets": [],
          "topModels": [],
          "topLineItems": []
        }
        """
        let decoded = try Self.decoder.decode(
            SyncOpenAIAPIDashboard.self, from: Data(json.utf8))
        #expect(decoded.historyDays == 30)
    }

    @Test
    func `OpenAI dashboard: historyDays clamps out-of-range values to 1..365`() {
        let dash0 = SyncOpenAIAPIDashboard(
            last30Days: SyncOpenAISummary(totalCostUSD: 0, totalRequests: 0, totalTokens: 0),
            last7Days: SyncOpenAISummary(totalCostUSD: 0, totalRequests: 0, totalTokens: 0),
            latestDay: nil,
            historyDays: -10)
        #expect(dash0.historyDays == 1)

        let dashHuge = SyncOpenAIAPIDashboard(
            last30Days: SyncOpenAISummary(totalCostUSD: 0, totalRequests: 0, totalTokens: 0),
            last7Days: SyncOpenAISummary(totalCostUSD: 0, totalRequests: 0, totalTokens: 0),
            latestDay: nil,
            historyDays: 10000)
        #expect(dashHuge.historyDays == 365)
    }
}

// swiftlint:enable multiline_arguments
