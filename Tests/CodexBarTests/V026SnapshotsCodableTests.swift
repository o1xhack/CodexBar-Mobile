// swiftlint:disable multiline_arguments
import Foundation
import Testing
@testable import CodexBarSync

/// Codable round-trip + backward-compatibility tests for the six v0.26
/// envelope fields added to `ProviderUsageSnapshot`.
///
/// Why these matter: the wire format is the only contract between Mac
/// and iOS. Schema bugs land silently — the JSON decodes "fine" with
/// a missing field, the iOS card just stays blank, and the user can't
/// tell from logs why their Bedrock budget never showed. These tests
/// pin:
///   1. Each new type round-trips through JSON without loss.
///   2. ProviderUsageSnapshot decodes a NEW payload (with the v0.26
///      keys) on a pre-1.7 client → unknown keys are ignored.
///   3. ProviderUsageSnapshot decodes an OLD payload (without the
///      v0.26 keys) on a 1.7 client → new fields land as nil, no
///      throw, no fallback misfire.
///   4. The `providerPayloadVersion` SHALL NOT be bumped for this
///      release — additive optional fields, no forced rewrite.
@Suite("v0.26 envelope — Codable round-trip + backward compat")
struct V026SnapshotsCodableTests {
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

    // MARK: - SyncOpenAIAPIDashboard

    @Test
    func `OpenAI dashboard: round-trips through JSON without loss`() throws {
        let source = SyncOpenAIAPIDashboard(
            last30Days: SyncOpenAISummary(totalCostUSD: 100.5, totalRequests: 1200, totalTokens: 500_000),
            last7Days: SyncOpenAISummary(totalCostUSD: 30.5, totalRequests: 250, totalTokens: 110_000),
            latestDay: SyncOpenAISummary(totalCostUSD: 4.2, totalRequests: 41, totalTokens: 15000),
            dailyBuckets: [
                SyncOpenAIDailyBucket(
                    dayKey: "2026-05-15",
                    costUSD: 4.2,
                    requests: 41,
                    inputTokens: 12000,
                    cachedInputTokens: 1500,
                    outputTokens: 1500,
                    totalTokens: 15000),
            ],
            topModels: [
                SyncOpenAIModelBreakdown(modelName: "gpt-5", requests: 800, totalTokens: 320_000, costUSD: 60.4),
            ],
            topLineItems: [
                SyncOpenAILineItem(name: "Completions", costUSD: 92.3),
            ])
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(SyncOpenAIAPIDashboard.self, from: data)
        #expect(decoded == source)
    }

    @Test
    func `OpenAI dashboard: latestDay optional decodes to nil when missing`() throws {
        let json = """
        {
          "last30Days": {"totalCostUSD": 10, "totalRequests": 100, "totalTokens": 5000},
          "last7Days":  {"totalCostUSD": 3,  "totalRequests": 30,  "totalTokens": 1500}
        }
        """
        let decoded = try Self.decoder.decode(SyncOpenAIAPIDashboard.self, from: Data(json.utf8))
        #expect(decoded.latestDay == nil)
        #expect(decoded.dailyBuckets.isEmpty)
        #expect(decoded.topModels.isEmpty)
        #expect(decoded.topLineItems.isEmpty)
    }

    @Test
    func `OpenAI dashboard: daily bucket token fields default to 0 when omitted`() throws {
        let json = """
        {"dayKey":"2026-05-15","costUSD":4.2,"requests":41}
        """
        let bucket = try Self.decoder.decode(SyncOpenAIDailyBucket.self, from: Data(json.utf8))
        #expect(bucket.inputTokens == 0)
        #expect(bucket.cachedInputTokens == 0)
        #expect(bucket.outputTokens == 0)
        #expect(bucket.totalTokens == 0)
    }

    // MARK: - SyncZaiHourlyUsage

    @Test
    func `z.ai hourly usage: round-trips with sparse (nil) token slots`() throws {
        // Anchor on an integer timestamp so the ISO8601 encoder
        // (second-precision) round-trips losslessly.
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        let xTime = (0..<24).map { anchor.addingTimeInterval(TimeInterval(3600 * $0)) }
        let source = SyncZaiHourlyUsage(
            xTime: xTime,
            modelSeries: [
                SyncZaiModelSeries(
                    modelName: "glm-4.6",
                    tokens: [1000, nil, 2500, nil] + Array(repeating: nil, count: 20)),
                SyncZaiModelSeries(modelName: "glm-4.6-plus", tokens: Array(repeating: nil, count: 24)),
            ])
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(SyncZaiHourlyUsage.self, from: data)
        #expect(decoded == source)
    }

    // MARK: - SyncKiroCredits

    @Test
    func `Kiro credits: round-trips with both bonus pool present and absent`() throws {
        let withBonus = SyncKiroCredits(
            planName: "Pro",
            creditsUsed: 320,
            creditsTotal: 1000,
            creditsPercent: 32,
            bonusUsed: 45,
            bonusTotal: 200,
            bonusExpiryDays: 19,
            resetsAt: Date(timeIntervalSince1970: 1_700_000_000))
        let withoutBonus = SyncKiroCredits(
            planName: nil,
            creditsUsed: 0,
            creditsTotal: nil,
            creditsPercent: nil,
            bonusUsed: nil,
            bonusTotal: nil,
            bonusExpiryDays: nil,
            resetsAt: nil)
        for source in [withBonus, withoutBonus] {
            let data = try Self.encoder.encode(source)
            let decoded = try Self.decoder.decode(SyncKiroCredits.self, from: data)
            #expect(decoded == source)
        }
    }

    // MARK: - SyncBedrockCost

    @Test
    func `Bedrock cost: round-trips with budget present and absent`() throws {
        let withBudget = SyncBedrockCost(
            monthlySpendUSD: 19.10,
            monthlyBudgetUSD: 50.0,
            inputTokens: 4_200_000,
            outputTokens: 1_100_000,
            region: "us-east-1",
            budgetUsedPercent: 38.2,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let withoutBudget = SyncBedrockCost(
            monthlySpendUSD: 3.50,
            monthlyBudgetUSD: nil,
            inputTokens: nil,
            outputTokens: nil,
            region: nil,
            budgetUsedPercent: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        for source in [withBudget, withoutBudget] {
            let data = try Self.encoder.encode(source)
            let decoded = try Self.decoder.decode(SyncBedrockCost.self, from: data)
            #expect(decoded == source)
        }
    }

    // MARK: - SyncMoonshotBalance

    @Test
    func `Moonshot balance: round-trips through JSON`() throws {
        let source = SyncMoonshotBalance(
            balanceAmount: 58.40,
            balanceCurrency: "CNY",
            region: "cn-default",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(SyncMoonshotBalance.self, from: data)
        #expect(decoded == source)
    }

    @Test
    func `Moonshot balance: nil currency + region decode cleanly`() throws {
        let json = """
        {"balanceAmount": 12.5, "updatedAt": "2026-05-17T00:00:00Z"}
        """
        let decoded = try Self.decoder.decode(SyncMoonshotBalance.self, from: Data(json.utf8))
        #expect(decoded.balanceAmount == 12.5)
        #expect(decoded.balanceCurrency == nil)
        #expect(decoded.region == nil)
    }

    // MARK: - SyncMultiAccountList

    @Test
    func `Multi-account list: round-trips with active index pointing into accounts`() throws {
        let source = SyncMultiAccountList(
            accounts: [
                SyncMultiAccountEntry(
                    email: "primary@example.com",
                    isActive: true,
                    expiresAt: Date(timeIntervalSince1970: 1_700_000_000)),
                SyncMultiAccountEntry(email: "alt@example.com", isActive: false, expiresAt: nil),
            ],
            activeIndex: 0)
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(SyncMultiAccountList.self, from: data)
        #expect(decoded == source)
        #expect(decoded.accounts[decoded.activeIndex ?? 0].isActive)
    }

    // MARK: - ProviderUsageSnapshot — full envelope backward/forward compat

    @Test
    func `Snapshot decode: old payload (without v0.26 keys) → new fields land as nil`() throws {
        // Wire format from a Mac 0.25.x client — no v0.26 keys. The
        // 1.7.0 iOS decoder must NOT throw; all six new optional
        // fields land as nil; the rest of the snapshot is preserved.
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
          "lastUpdated": "2026-05-15T00:00:00Z"
        }
        """
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.providerID == "claude")
        #expect(decoded.openAIAPIDashboard == nil)
        #expect(decoded.zaiHourlyUsage == nil)
        #expect(decoded.kiroCredits == nil)
        #expect(decoded.bedrockCost == nil)
        #expect(decoded.moonshotBalance == nil)
        #expect(decoded.antigravityAccounts == nil)
    }

    @Test
    func `Snapshot decode: payload WITH all v0.26 keys round-trips cleanly on 1.7 reader`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let source = ProviderUsageSnapshot(
            providerID: "kiro",
            providerName: "Kiro",
            primary: nil,
            secondary: nil,
            accountEmail: "user@kiro.test",
            loginMethod: "CLI",
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            openAIAPIDashboard: SyncOpenAIAPIDashboard(
                last30Days: SyncOpenAISummary(totalCostUSD: 1, totalRequests: 1, totalTokens: 1),
                last7Days: SyncOpenAISummary(totalCostUSD: 1, totalRequests: 1, totalTokens: 1),
                latestDay: nil,
                dailyBuckets: [],
                topModels: [],
                topLineItems: []),
            zaiHourlyUsage: SyncZaiHourlyUsage(xTime: [now], modelSeries: [
                SyncZaiModelSeries(modelName: "m", tokens: [10]),
            ]),
            kiroCredits: SyncKiroCredits(
                planName: "Pro", creditsUsed: 1, creditsTotal: 2, creditsPercent: 50,
                bonusUsed: nil, bonusTotal: nil, bonusExpiryDays: nil, resetsAt: nil),
            bedrockCost: SyncBedrockCost(
                monthlySpendUSD: 1, monthlyBudgetUSD: 2, inputTokens: nil, outputTokens: nil,
                region: "us-east-1", budgetUsedPercent: 50, updatedAt: now),
            moonshotBalance: SyncMoonshotBalance(
                balanceAmount: 1, balanceCurrency: "USD", region: nil, updatedAt: now),
            antigravityAccounts: SyncMultiAccountList(
                accounts: [SyncMultiAccountEntry(email: "a@b.test", isActive: true, expiresAt: nil)],
                activeIndex: 0))
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: data)
        #expect(decoded.openAIAPIDashboard != nil)
        #expect(decoded.zaiHourlyUsage != nil)
        #expect(decoded.kiroCredits?.planName == "Pro")
        #expect(decoded.bedrockCost?.region == "us-east-1")
        #expect(decoded.moonshotBalance?.balanceCurrency == "USD")
        #expect(decoded.antigravityAccounts?.accounts.first?.email == "a@b.test")
    }

    @Test
    func `Snapshot decode: payload with PARTIAL v0.26 keys (only kiroCredits) decodes the others as nil`() throws {
        let json = """
        {
          "providerID": "kiro",
          "providerName": "Kiro",
          "primary": null,
          "secondary": null,
          "rateWindows": [],
          "accountEmail": null,
          "loginMethod": null,
          "statusMessage": null,
          "isError": false,
          "lastUpdated": "2026-05-17T00:00:00Z",
          "kiroCredits": {
            "planName": "Free",
            "creditsUsed": 5.0,
            "creditsTotal": 100.0,
            "creditsPercent": 5.0
          }
        }
        """
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.kiroCredits?.planName == "Free")
        #expect(decoded.openAIAPIDashboard == nil)
        #expect(decoded.zaiHourlyUsage == nil)
        #expect(decoded.bedrockCost == nil)
        #expect(decoded.moonshotBalance == nil)
        #expect(decoded.antigravityAccounts == nil)
    }

    // MARK: - providerPayloadVersion contract pin

    @Test
    func `Wire contract: providerPayloadVersion has NOT been bumped for v0.26 fields`() {
        // Pin the contract: adding optional `decodeIfPresent` fields
        // does NOT require a version bump. Bumping would force a full
        // rewrite cycle on every Mac and is reserved for incompatible
        // schema changes. See `Shared/iCloud/CloudConstants.swift` and
        // the Phase B section of plan
        // `/Users/yuxiao/.claude/plans/imperative-floating-stream.md`.
        #expect(CloudSyncConstants.providerPayloadVersion == 1)
    }
}

// swiftlint:enable multiline_arguments
