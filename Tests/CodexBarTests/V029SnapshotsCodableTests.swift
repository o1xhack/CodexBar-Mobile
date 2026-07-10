// swiftlint:disable multiline_arguments
//
// Scoped to this file: synthetic Codable fixtures pack several trailing
// values per line so the JSON shape stays auditable at a glance. Re-enabled
// at EOF.
import Foundation
import Testing
@testable import CodexBarSync

/// Codable round-trip + cross-version compat for the iOS 1.9.0 / Mac 0.29.0
/// parity-gap envelope blocks (`SyncOpenRouterStats` / `SyncAzureOpenAIInfo` /
/// `SyncAlibabaTokenPlan`, gaps D/E/G) and the `SyncCostSummary.historyDays`
/// addition (gap F). Mirrors `V027SnapshotsCodableTests`. Pins:
///   1. Each new block round-trips through JSON without loss.
///   2. A pre-1.9.0 payload (no new keys) decodes on a 1.9.0 reader — every
///      new field lands as nil. (Old Mac → new iOS, no blank-out.)
///   3. A 1.9.0 payload with all three blocks set round-trips, proving the
///      `ProviderUsageSnapshot` custom `init(from:)` decodes all three — the
///      direct guard against a missed wiring site (silent data loss).
@Suite("v0.29 envelope — Codable round-trip + cross-version compat")
struct V029SnapshotsCodableTests {
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

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Individual block round-trip

    @Test
    func `OpenRouter stats: round-trips with full key-usage windows + rate limit`() throws {
        let source = SyncOpenRouterStats(
            balanceUSD: 7.5, totalCreditsUSD: 50.0, totalUsageUSD: 42.5, usedPercent: 85.0,
            keyUsageDailyUSD: 1.25, keyUsageWeeklyUSD: 8.0, keyUsageMonthlyUSD: 30.0,
            keyLimitUSD: 100.0, rateLimitRequests: 20, rateLimitInterval: "10s",
            updatedAt: Self.now)
        let decoded = try Self.decoder.decode(
            SyncOpenRouterStats.self, from: Self.encoder.encode(source))
        #expect(decoded == source)
        #expect(decoded.balanceUSD == 7.5)
        #expect(decoded.rateLimitRequests == 20)
        #expect(decoded.rateLimitInterval == "10s")
    }

    @Test
    func `OpenRouter stats: round-trips with nil key windows + nil rate limit`() throws {
        let source = SyncOpenRouterStats(
            balanceUSD: 0, totalCreditsUSD: 0, totalUsageUSD: 0, usedPercent: 0,
            keyUsageDailyUSD: nil, keyUsageWeeklyUSD: nil, keyUsageMonthlyUSD: nil,
            keyLimitUSD: nil, rateLimitRequests: nil, rateLimitInterval: nil,
            updatedAt: Self.now)
        let decoded = try Self.decoder.decode(
            SyncOpenRouterStats.self, from: Self.encoder.encode(source))
        #expect(decoded == source)
        #expect(decoded.keyUsageDailyUSD == nil)
        #expect(decoded.rateLimitRequests == nil)
    }

    @Test
    func `Azure OpenAI info: round-trips with model present and absent`() throws {
        let withModel = SyncAzureOpenAIInfo(
            endpointHost: "my-res.openai.azure.com", deploymentName: "gpt-4o-prod",
            model: "gpt-4o", apiVersion: "2024-10-21", updatedAt: Self.now)
        let dWith = try Self.decoder.decode(
            SyncAzureOpenAIInfo.self, from: Self.encoder.encode(withModel))
        #expect(dWith == withModel)
        #expect(dWith.model == "gpt-4o")

        let noModel = SyncAzureOpenAIInfo(
            endpointHost: "r.openai.azure.com", deploymentName: "d", model: nil,
            apiVersion: "2024-10-21", updatedAt: Self.now)
        let dNo = try Self.decoder.decode(
            SyncAzureOpenAIInfo.self, from: Self.encoder.encode(noModel))
        #expect(dNo.model == nil)
    }

    @Test
    func `Alibaba Token Plan: round-trips with full credits and all-nil quota`() throws {
        let full = SyncAlibabaTokenPlan(
            planName: "Bailian Pro", usedCredits: 300, totalCredits: 1000,
            remainingCredits: 700, resetsAt: Self.now, updatedAt: Self.now)
        let dFull = try Self.decoder.decode(
            SyncAlibabaTokenPlan.self, from: Self.encoder.encode(full))
        #expect(dFull == full)
        #expect(dFull.usedCredits == 300)
        #expect(dFull.remainingCredits == 700)

        let empty = SyncAlibabaTokenPlan(
            planName: nil, usedCredits: nil, totalCredits: nil,
            remainingCredits: nil, resetsAt: nil, updatedAt: Self.now)
        let dEmpty = try Self.decoder.decode(
            SyncAlibabaTokenPlan.self, from: Self.encoder.encode(empty))
        #expect(dEmpty.planName == nil)
        #expect(dEmpty.totalCredits == nil)
    }

    // MARK: - Cross-version compat — old payload decoded by NEW reader

    @Test
    func `Snapshot decode: pre-1.9.0 payload → all three parity blocks land nil`() throws {
        // Wire format from a pre-1.9.0 Mac: none of the gap D/E/G keys present.
        let json = """
        {
          "providerID": "openrouter",
          "providerName": "OpenRouter",
          "primary": null,
          "secondary": null,
          "rateWindows": [],
          "accountEmail": "user@example.com",
          "loginMethod": "Balance: $7.50",
          "statusMessage": null,
          "isError": false,
          "lastUpdated": "2026-05-19T00:00:00Z"
        }
        """
        let decoded = try Self.decoder.decode(
            ProviderUsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.providerID == "openrouter")
        #expect(decoded.openRouterStats == nil)
        #expect(decoded.azureOpenAIInfo == nil)
        #expect(decoded.alibabaTokenPlan == nil)
        // costSummary absent → nil; its gap-F historyDays is therefore moot.
        #expect(decoded.costSummary == nil)
    }

    // MARK: - Cross-version compat — new payload round-trips on reader

    @Test
    func `Snapshot decode: 1.9.0 payload with all three parity blocks round-trips`() throws {
        let source = ProviderUsageSnapshot(
            providerID: "openrouter",
            providerName: "OpenRouter",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "Balance: $7.50",
            statusMessage: nil,
            isError: false,
            lastUpdated: Self.now,
            openRouterStats: SyncOpenRouterStats(
                balanceUSD: 7.5, totalCreditsUSD: 50, totalUsageUSD: 42.5, usedPercent: 85,
                keyUsageDailyUSD: 1.25, keyUsageWeeklyUSD: 8, keyUsageMonthlyUSD: 30,
                keyLimitUSD: 100, rateLimitRequests: 20, rateLimitInterval: "10s",
                updatedAt: Self.now),
            azureOpenAIInfo: SyncAzureOpenAIInfo(
                endpointHost: "r.openai.azure.com", deploymentName: "gpt-4o-prod",
                model: "gpt-4o", apiVersion: "2024-10-21", updatedAt: Self.now),
            alibabaTokenPlan: SyncAlibabaTokenPlan(
                planName: "Bailian Pro", usedCredits: 300, totalCredits: 1000,
                remainingCredits: 700, resetsAt: Self.now, updatedAt: Self.now))
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: data)
        #expect(decoded.openRouterStats?.balanceUSD == 7.5)
        #expect(decoded.openRouterStats?.rateLimitInterval == "10s")
        #expect(decoded.azureOpenAIInfo?.deploymentName == "gpt-4o-prod")
        #expect(decoded.azureOpenAIInfo?.endpointHost == "r.openai.azure.com")
        #expect(decoded.alibabaTokenPlan?.totalCredits == 1000)
        #expect(decoded.alibabaTokenPlan?.planName == "Bailian Pro")
    }

    // MARK: - gap F — SyncCostSummary.historyDays

    @Test
    func `Cost summary: pre-1.9.0 payload (no historyDays) decodes as nil`() throws {
        let json = """
        {
          "sessionCostUSD": null, "sessionTokens": null,
          "last30DaysCostUSD": 1.0, "last30DaysTokens": 100,
          "daily": []
        }
        """
        let decoded = try Self.decoder.decode(SyncCostSummary.self, from: Data(json.utf8))
        #expect(decoded.historyDays == nil)
        #expect(decoded.last30DaysCostUSD == 1.0)
    }

    @Test
    func `Cost summary: round-trips historyDays = 90`() throws {
        let source = SyncCostSummary(
            sessionCostUSD: nil, sessionTokens: nil,
            last30DaysCostUSD: 1.0, last30DaysTokens: 100,
            daily: [], isEstimated: nil, historyDays: 90)
        let decoded = try Self.decoder.decode(
            SyncCostSummary.self, from: Self.encoder.encode(source))
        #expect(decoded.historyDays == 90)
    }
}

// swiftlint:enable multiline_arguments
