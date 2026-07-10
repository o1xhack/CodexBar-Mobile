// swiftlint:disable multiline_arguments
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore
@testable import CodexBarSync

/// End-to-end regression tests that exercise the full
/// `upstream provider → UsageSnapshot → mapper → SyncBedrockCost/etc →
/// JSON encode → JSON decode → iOS-side reader` pipeline. These are the
/// tests that would have caught the C1/C2 CRITICAL bugs the
/// independent CR agent found.
///
/// The earlier unit tests used hand-built `ProviderCostSnapshot` /
/// `ProviderIdentitySnapshot` fixtures that didn't match what upstream
/// fetchers actually emit. That's how:
///   - C1 (Bedrock region rendered the composite cost string) and
///   - C2 (Moonshot balance always 0)
/// slipped past the unit tests. This file uses the real
/// `BedrockUsageSnapshot.toUsageSnapshot()` and
/// `MoonshotUsageSummary.toUsageSnapshot()` outputs as inputs so any
/// future upstream change in the format flips a test, not a user's
/// production card.
@MainActor
@Suite("v0.26 envelope — end-to-end pipeline from upstream fetcher to iOS reader")
struct V026EndToEndPipelineTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Bedrock

    @Test
    func `Bedrock end-to-end: upstream → mapper → encode → decode → region preserved (C1 regression)`() throws {
        // Step 1 — real upstream fetcher output. This is the exact
        // shape `BedrockUsageSnapshot.toUsageSnapshot()` produces in
        // production today: providerCost is populated; loginMethod is
        // the COMPOSITE display string "Spend: $X - Budget: $Y -
        // Tokens: $Z" — NOT the AWS region.
        let bedrock = BedrockUsageSnapshot(
            monthlySpend: 19.10,
            monthlyBudget: 50.0,
            inputTokens: 4_200_000,
            outputTokens: 1_100_000,
            region: "us-east-1",
            updatedAt: Self.now)
        let upstreamSnapshot = bedrock.toUsageSnapshot()

        // Pre-condition pin: upstream really IS packing the composite
        // string into loginMethod (so if upstream changes this format,
        // the assert flips and we know to revisit C1).
        #expect(upstreamSnapshot.identity?.loginMethod?.contains("Spend:") == true)
        #expect(upstreamSnapshot.identity?.loginMethod?.contains("us-east-1") == false)
        // And providerCost carries the spend / budget correctly.
        #expect(upstreamSnapshot.providerCost?.used == 19.10)
        #expect(upstreamSnapshot.providerCost?.limit == 50.0)

        // Step 2 — mapper. Region is passed in explicitly (the way
        // `SyncCoordinator.buildProviderUsageSnapshot` plumbs
        // `self.settings.bedrockRegion` through).
        let mapped = SyncCoordinator.mapBedrockCost(
            provider: .bedrock,
            snapshot: upstreamSnapshot,
            providerCost: upstreamSnapshot.providerCost,
            region: "us-east-1")
        let typed = try #require(mapped)

        // Step 3 — wire encode/decode round-trip.
        let envelope = ProviderUsageSnapshot(
            providerID: "bedrock", providerName: "AWS Bedrock",
            primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false,
            lastUpdated: Self.now,
            bedrockCost: typed)
        let data = try Self.encoder.encode(envelope)
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: data)

        // Step 4 — iOS-side reader sees the right region, not the
        // composite display string.
        let received = try #require(decoded.bedrockCost)
        #expect(received.region == "us-east-1")
        #expect(received.region?.contains("Spend:") == false)
        #expect(received.monthlySpendUSD == 19.10)
        #expect(received.monthlyBudgetUSD == 50.0)
        #expect(received.budgetUsedPercent != nil)
        #expect((received.budgetUsedPercent ?? 0) > 38.0)
        #expect((received.budgetUsedPercent ?? 0) < 39.0)
    }

    @Test
    func `Bedrock end-to-end: region nil propagates as nil (graceful fallback when SettingsStore is empty)`() throws {
        let bedrock = BedrockUsageSnapshot(
            monthlySpend: 3.50, monthlyBudget: nil,
            inputTokens: nil, outputTokens: nil,
            region: "ap-northeast-1",
            updatedAt: Self.now)
        let upstreamSnapshot = bedrock.toUsageSnapshot()
        let mapped = SyncCoordinator.mapBedrockCost(
            provider: .bedrock,
            snapshot: upstreamSnapshot,
            providerCost: upstreamSnapshot.providerCost,
            region: nil)
        let envelope = ProviderUsageSnapshot(
            providerID: "bedrock", providerName: "AWS Bedrock",
            primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false,
            lastUpdated: Self.now,
            bedrockCost: mapped)
        let decoded = try Self.decoder.decode(
            ProviderUsageSnapshot.self,
            from: Self.encoder.encode(envelope))
        // Region nil → iOS view skips the "Region: ..." line, doesn't
        // render the composite string. Spend still shows.
        #expect(decoded.bedrockCost?.region == nil)
        #expect(decoded.bedrockCost?.monthlySpendUSD == 3.50)
    }

    // MARK: - Moonshot

    @Test
    func `Moonshot end-to-end: upstream → mapper → encode → decode → balance non-zero (C2 regression)`() throws {
        // Step 1 — real upstream fetcher output. Production format:
        // providerCost = nil, primary = nil, loginMethod = "Balance: $X".
        // Anything that reads providerCost.used or primaryWindow's
        // usedPercent silently lands on 0.
        let moonshot = MoonshotUsageSummary(
            availableBalance: 58.40,
            voucherBalance: 50.0,
            cashBalance: 8.40,
            updatedAt: Self.now)
        let upstreamSnapshot = moonshot.toUsageSnapshot()

        // Pre-condition pin: upstream really IS using the loginMethod
        // composite string, and providerCost is unpopulated. If
        // upstream switches to providerCost-based publishing in a
        // future merge, this assert flips and the mapper's fallback
        // (which reads providerCost.used) automatically takes over.
        #expect(upstreamSnapshot.providerCost == nil)
        #expect(upstreamSnapshot.primary == nil)
        #expect(upstreamSnapshot.identity?.loginMethod?.contains("Balance:") == true)
        #expect(upstreamSnapshot.identity?.loginMethod?.contains("58.40") == true)

        // Step 2 — mapper. Parses balance out of loginMethod.
        let mapped = SyncCoordinator.mapMoonshotBalance(
            provider: .moonshot,
            snapshot: upstreamSnapshot,
            primaryWindow: nil)
        let typed = try #require(mapped)

        // Step 3 — wire encode/decode.
        let envelope = ProviderUsageSnapshot(
            providerID: "moonshot", providerName: "Moonshot / Kimi API",
            primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false,
            lastUpdated: Self.now,
            moonshotBalance: typed)
        let data = try Self.encoder.encode(envelope)
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: data)

        // Step 4 — iOS reader sees the real dollar amount.
        let received = try #require(decoded.moonshotBalance)
        #expect(received.balanceAmount == 58.40)
        #expect(received.balanceAmount > 0)
        #expect(received.balanceCurrency == "USD")
    }

    @Test
    func `Moonshot end-to-end: deficit path also parses balance correctly`() throws {
        // Triggers the deficit branch in
        // MoonshotUsageSummary.toUsageSnapshot(): cashBalance < 0.
        // loginMethod becomes "Balance: $58.40 · $5.00 in deficit".
        let moonshot = MoonshotUsageSummary(
            availableBalance: 58.40,
            voucherBalance: 63.40,
            cashBalance: -5.00,
            updatedAt: Self.now)
        let upstreamSnapshot = moonshot.toUsageSnapshot()
        #expect(upstreamSnapshot.identity?.loginMethod?.contains("in deficit") == true)

        let mapped = SyncCoordinator.mapMoonshotBalance(
            provider: .moonshot,
            snapshot: upstreamSnapshot,
            primaryWindow: nil)
        let typed = try #require(mapped)
        #expect(typed.balanceAmount == 58.40, "Must parse `Balance: $58.40` even when the deficit suffix is appended.")
    }

    @Test
    func `Moonshot end-to-end: zero balance → mapper returns nil → iOS hides card (not '0.00')`() {
        // A real Moonshot user can hit zero balance temporarily. The
        // mapper should return nil so iOS hides the card rather than
        // displaying "0.00" — which is what the C2 bug ACTUALLY did
        // for every user, regardless of their real balance.
        let moonshot = MoonshotUsageSummary(
            availableBalance: 0,
            voucherBalance: 0,
            cashBalance: 0,
            updatedAt: Self.now)
        let upstreamSnapshot = moonshot.toUsageSnapshot()
        let mapped = SyncCoordinator.mapMoonshotBalance(
            provider: .moonshot,
            snapshot: upstreamSnapshot,
            primaryWindow: nil)
        #expect(mapped == nil)
    }

    // MARK: - Kiro

    @Test
    func `Kiro end-to-end: upstream → mapper → encode → decode → credits + bonus preserved`() throws {
        // Build a KiroUsageSnapshot the way the upstream fetcher
        // would after a successful credentials probe, then convert
        // via the same `toUsageDetails()` extension that lives on
        // upstream. KiroUsageDetails is the type that lands in
        // `UsageSnapshot.kiroUsage`.
        let kiroDetails = KiroUsageDetails(
            planName: "pro",
            displayPlanName: "Pro",
            creditsUsed: 320,
            creditsTotal: 1000,
            creditsRemaining: 680,
            bonusCreditsUsed: 45,
            bonusCreditsTotal: 200,
            bonusCreditsRemaining: 155,
            bonusExpiryDays: 19,
            overagesStatus: nil,
            overageCreditsUsed: nil,
            estimatedOverageCostUSD: nil,
            manageURL: nil,
            contextUsage: nil)
        let upstreamSnapshot = UsageSnapshot(
            primary: nil, secondary: nil,
            kiroUsage: kiroDetails,
            updatedAt: Self.now)

        let mapped = SyncCoordinator.mapKiroCredits(
            provider: .kiro, snapshot: upstreamSnapshot)
        let typed = try #require(mapped)

        let envelope = ProviderUsageSnapshot(
            providerID: "kiro", providerName: "Kiro",
            primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false,
            lastUpdated: Self.now,
            kiroCredits: typed)
        let decoded = try Self.decoder.decode(
            ProviderUsageSnapshot.self,
            from: Self.encoder.encode(envelope))

        let received = try #require(decoded.kiroCredits)
        #expect(received.planName == "Pro")
        #expect(received.creditsUsed == 320)
        #expect(received.creditsTotal == 1000)
        #expect(received.creditsPercent == 32)
        #expect(received.bonusUsed == 45)
        #expect(received.bonusTotal == 200)
        #expect(received.bonusExpiryDays == 19)
    }

    // MARK: - Wire-contract pin

    @Test
    func `All six v0.26 typed fields survive a full Codable round-trip on ProviderUsageSnapshot`() throws {
        let envelope = ProviderUsageSnapshot(
            providerID: "openai", providerName: "OpenAI",
            primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false,
            lastUpdated: Self.now,
            openAIAPIDashboard: SyncOpenAIAPIDashboard(
                last30Days: SyncOpenAISummary(totalCostUSD: 100, totalRequests: 1000, totalTokens: 500_000),
                last7Days: SyncOpenAISummary(totalCostUSD: 30, totalRequests: 250, totalTokens: 110_000),
                latestDay: SyncOpenAISummary(totalCostUSD: 4, totalRequests: 40, totalTokens: 15000)),
            zaiHourlyUsage: SyncZaiHourlyUsage(
                xTime: [Self.now],
                modelSeries: [SyncZaiModelSeries(modelName: "glm", tokens: [42])]),
            kiroCredits: SyncKiroCredits(
                planName: "Pro", creditsUsed: 1, creditsTotal: 2, creditsPercent: 50,
                bonusUsed: nil, bonusTotal: nil, bonusExpiryDays: nil, resetsAt: nil),
            bedrockCost: SyncBedrockCost(
                monthlySpendUSD: 1, monthlyBudgetUSD: 2,
                inputTokens: nil, outputTokens: nil,
                region: "us-west-2", budgetUsedPercent: 50, updatedAt: Self.now),
            moonshotBalance: SyncMoonshotBalance(
                balanceAmount: 42, balanceCurrency: "USD", region: nil, updatedAt: Self.now),
            antigravityAccounts: SyncMultiAccountList(
                accounts: [SyncMultiAccountEntry(email: "a@b.test", isActive: true, expiresAt: nil)],
                activeIndex: 0))
        let data = try Self.encoder.encode(envelope)
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: data)
        // Every field round-trips losslessly.
        #expect(decoded.openAIAPIDashboard?.last30Days.totalCostUSD == 100)
        #expect(decoded.zaiHourlyUsage?.modelSeries.first?.modelName == "glm")
        #expect(decoded.kiroCredits?.planName == "Pro")
        #expect(decoded.bedrockCost?.region == "us-west-2")
        #expect(decoded.moonshotBalance?.balanceAmount == 42)
        #expect(decoded.antigravityAccounts?.accounts.first?.email == "a@b.test")
    }
}

// swiftlint:enable multiline_arguments
