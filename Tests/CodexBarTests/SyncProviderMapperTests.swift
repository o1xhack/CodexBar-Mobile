// swiftlint:disable multiline_arguments
//
// Scoped to this file: the native-usage fixtures pack several trailing
// values per line so each model breakdown reads as one row. Re-enabled at EOF.
import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// Unit tests for the provider→envelope mappers added for the iOS 1.9.0 /
/// Mac 0.29.0 parity gap-fills (C / D / E / G). Each mapper is provider-gated
/// and reads a CodexBarCore-native usage struct off `UsageSnapshot`; these pin
/// both the gate (wrong provider OR nil native data → nil) and the field
/// mapping into the wire envelope. The CR for the A–G batch flagged that only
/// gap A had coordinator-level coverage; this closes C/D/E/G.
@MainActor
@Suite("Sync provider mappers — parity gap-fills (C/D/E/G)")
struct SyncProviderMapperTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Minimal `UsageSnapshot` carrying at most one provider-native block.
    private func snapshot(
        mistral: MistralUsageSnapshot? = nil,
        openRouter: OpenRouterUsageSnapshot? = nil,
        azure: AzureOpenAIUsageSnapshot? = nil,
        alibaba: AlibabaTokenPlanUsageSnapshot? = nil,
        sub2API: Sub2APIUsageDetails? = nil,
        wayfinder: WayfinderUsageSnapshot? = nil,
        providerCost: ProviderCostSnapshot? = nil,
        dataConfidence: UsageDataConfidence = .unknown) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: providerCost,
            openRouterUsage: openRouter,
            sub2APIUsage: sub2API,
            wayfinderUsage: wayfinder,
            mistralUsage: mistral,
            azureOpenAIUsage: azure,
            alibabaTokenPlanUsage: alibaba,
            updatedAt: Self.now,
            dataConfidence: dataConfidence)
    }

    // MARK: - v0.42-v0.45: new provider bridge

    @Test
    func `additional rate-window labels preserve new provider tertiary windows`() {
        #expect(SyncCoordinator.additionalWindowLabel(windowMinutes: 1440) == "Daily")
        #expect(SyncCoordinator.additionalWindowLabel(windowMinutes: 10080) == "Weekly")
        #expect(SyncCoordinator.additionalWindowLabel(windowMinutes: 43200) == "Monthly")
        #expect(SyncCoordinator.additionalWindowLabel(windowMinutes: nil) == "Additional")
    }

    @Test
    func `mapSub2APIUsage preserves wallet and request totals`() throws {
        let native = Sub2APIUsageDetails(
            kind: .subscription,
            balance: 61.6,
            unit: "USD",
            today: .init(requests: 84, totalTokens: 12467, actualCostUSD: 0.27),
            total: .init(requests: 3166, totalTokens: 260_000, actualCostUSD: 5.37))
        let mapped = try #require(SyncCoordinator.mapSub2APIUsage(
            provider: .sub2api,
            snapshot: self.snapshot(sub2API: native)))
        #expect(mapped.kind == "subscription")
        #expect(mapped.balance == 61.6)
        #expect(mapped.today?.requests == 84)
        #expect(mapped.total?.totalTokens == 260_000)
        #expect(SyncCoordinator.mapSub2APIUsage(
            provider: .codex,
            snapshot: self.snapshot(sub2API: native)) == nil)
    }

    @Test
    func `mapWayfinderUsage preserves routing and savings evidence`() throws {
        let native = WayfinderUsageSnapshot(
            gatewayStatus: "healthy",
            offline: false,
            dryRun: false,
            missingKeys: [],
            modelCount: 6,
            requests: 1420,
            tokens: 8_600_000,
            realized: 7.84,
            baseline: 12.68,
            saved: 4.84,
            savedPct: 38.2,
            priced: true,
            routes: [.init(name: "local", requests: 960, saved: 3.61, tokens: 5_900_000)],
            avgDecisionMs: 7.4,
            updatedAt: Self.now)
        let mapped = try #require(SyncCoordinator.mapWayfinderUsage(
            provider: .wayfinder,
            snapshot: self.snapshot(wayfinder: native)))
        #expect(mapped.modelCount == 6)
        #expect(mapped.savedPercent == 38.2)
        #expect(mapped.routes.first?.name == "local")
        #expect(mapped.averageDecisionMilliseconds == 7.4)
        #expect(SyncCoordinator.mapWayfinderUsage(
            provider: .codex,
            snapshot: self.snapshot(wayfinder: native)) == nil)
    }

    @Test(arguments: [UsageProvider.neuralwatt, .zenmux])
    func `zero-limit balances use amount lane`(_ provider: UsageProvider) throws {
        let cost = ProviderCostSnapshot(
            used: 32.67,
            limit: 0,
            currencyCode: "USD",
            period: "Prepaid balance",
            updatedAt: Self.now)
        let mapped = try #require(SyncCoordinator.mapProviderAmount(
            provider: provider,
            snapshot: self.snapshot(providerCost: cost, dataConfidence: .exact),
            providerCost: cost))
        #expect(mapped.kind == "balance")
        #expect(mapped.amount == 32.67)
        #expect(mapped.isEstimated == false)
    }

    @Test
    func `aiand partial spend remains uncapped and estimated`() throws {
        let cost = ProviderCostSnapshot(
            used: 840,
            limit: 0,
            currencyCode: "JPY",
            period: "Last 30 days (partial)",
            updatedAt: Self.now)
        let mapped = try #require(SyncCoordinator.mapProviderAmount(
            provider: .aiand,
            snapshot: self.snapshot(providerCost: cost, dataConfidence: .estimated),
            providerCost: cost))
        #expect(mapped.kind == "spend")
        #expect(mapped.currencyCode == "JPY")
        #expect(mapped.period == "Last 30 days (partial)")
        #expect(mapped.isEstimated)
        #expect(SyncCoordinator.mapProviderAmount(
            provider: .claude,
            snapshot: self.snapshot(providerCost: cost),
            providerCost: cost) == nil)
    }

    @Test
    func `token account record key is stable delimiter-safe and label independent`() throws {
        let id = try #require(UUID(uuidString: "C86A7C42-BF93-4B15-AC95-0B917DBDDA1D"))
        let first = ProviderTokenAccount(
            id: id, label: "Same | label", token: "secret-a",
            addedAt: 1, lastUsed: nil)
        let renamed = ProviderTokenAccount(
            id: id, label: "Renamed", token: "secret-b",
            addedAt: 1, lastUsed: nil)
        let firstKey = SyncCoordinator.tokenAccountRecordKey(first)
        #expect(firstKey == SyncCoordinator.tokenAccountRecordKey(renamed))
        #expect(!firstKey.contains("|"))
        #expect(!firstKey.contains("secret"))
    }

    @Test
    func `mapper uses opaque identity when account email is an editable label`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .claude,
            accountEmail: "Shared production",
            accountOrganization: nil,
            loginMethod: "Token",
            accountEmailIsFallbackLabel: true)
        #expect(SyncCoordinator.syncAccountIdentities(
            provider: .claude,
            identity: identity,
            accountRecordKey: "token-a") == ["claude:record:token-a"])
        #expect(SyncCoordinator.syncAccountIdentities(
            provider: .claude,
            identity: identity,
            accountRecordKey: "token-b") == ["claude:record:token-b"])
    }

    @Test
    func `mapper keeps real email identity ahead of per-Mac opaque key`() {
        let identity = ProviderIdentitySnapshot(
            providerID: .cursor,
            accountEmail: "same@example.com",
            accountOrganization: nil,
            loginMethod: "Token")
        let identities = SyncCoordinator.syncAccountIdentities(
            provider: .cursor,
            identity: identity,
            accountRecordKey: "token-a")
        #expect(identities == [
            "cursor:email:same@example.com",
            "cursor:record:token-a",
        ])
    }

    // MARK: - C: Mistral cost summary

    private func mistralFixture() -> MistralUsageSnapshot {
        MistralUsageSnapshot(
            totalCost: 4.2, currency: "USD", currencySymbol: "$",
            totalInputTokens: 1000, totalOutputTokens: 500, totalCachedTokens: 200,
            modelCount: 2,
            daily: [
                MistralDailyUsageBucket(
                    day: "2026-05-25", cost: 1.5, inputTokens: 400, cachedTokens: 100, outputTokens: 200,
                    models: [
                        .init(name: "mistral-large", cost: 1.0, inputTokens: 300, cachedTokens: 50, outputTokens: 150),
                        .init(name: "free-model", cost: 0, inputTokens: 100, cachedTokens: 50, outputTokens: 50),
                    ]),
                MistralDailyUsageBucket(
                    day: "2026-05-26", cost: 2.7, inputTokens: 600, cachedTokens: 100, outputTokens: 300,
                    models: [
                        .init(name: "mixtral", cost: 2.7, inputTokens: 600, cachedTokens: 100, outputTokens: 300),
                    ]),
            ],
            startDate: nil, endDate: nil, updatedAt: Self.now)
    }

    @Test
    func `mapMistralCostSummary: nil for a non-mistral provider`() {
        #expect(SyncCoordinator.mapMistralCostSummary(
            provider: .codex, snapshot: self.snapshot(mistral: self.mistralFixture())) == nil)
    }

    @Test
    func `mapMistralCostSummary: nil when mistral usage is absent`() {
        #expect(SyncCoordinator.mapMistralCostSummary(
            provider: .mistral, snapshot: self.snapshot()) == nil)
    }

    @Test
    func `mapMistralCostSummary: nil when daily history is empty`() {
        let empty = MistralUsageSnapshot(
            totalCost: 0, currency: "USD", currencySymbol: "$",
            totalInputTokens: 0, totalOutputTokens: 0, totalCachedTokens: 0,
            modelCount: 0, daily: [], startDate: nil, endDate: nil, updatedAt: Self.now)
        #expect(SyncCoordinator.mapMistralCostSummary(
            provider: .mistral, snapshot: self.snapshot(mistral: empty)) == nil)
    }

    @Test
    func `mapMistralCostSummary: maps totals, daily points, and filters/sorts model breakdowns`() throws {
        let summary = try #require(SyncCoordinator.mapMistralCostSummary(
            provider: .mistral, snapshot: self.snapshot(mistral: self.mistralFixture())))
        #expect(summary.last30DaysCostUSD == 4.2)
        #expect(summary.last30DaysTokens == 1700) // 1000 + 500 + 200
        #expect(summary.daily.count == 2)

        let day25 = try #require(summary.daily.first { $0.dayKey == "2026-05-25" })
        #expect(day25.costUSD == 1.5)
        #expect(day25.totalTokens == 700) // 400 + 100 + 200
        // free-model (cost 0) is filtered out; only the paid model survives.
        #expect(day25.modelBreakdowns.count == 1)
        #expect(day25.modelBreakdowns.first?.label == "mistral-large")
        #expect(day25.modelBreakdowns.first?.costUSD == 1.0)
    }

    // MARK: - D: OpenRouter stats

    private func openRouterFixture() -> OpenRouterUsageSnapshot {
        OpenRouterUsageSnapshot(
            totalCredits: 50, totalUsage: 42.5, balance: 7.5, usedPercent: 85,
            keyLimit: 100, keyUsage: 42.5,
            keyUsageDaily: 1.25, keyUsageWeekly: 8, keyUsageMonthly: 30,
            rateLimit: OpenRouterRateLimit(requests: 20, interval: "10s"),
            updatedAt: Self.now)
    }

    @Test
    func `mapOpenRouter: nil for a non-openrouter provider`() {
        #expect(SyncCoordinator.mapOpenRouter(
            provider: .codex, snapshot: self.snapshot(openRouter: self.openRouterFixture())) == nil)
    }

    @Test
    func `mapOpenRouter: nil when openrouter usage is absent`() {
        #expect(SyncCoordinator.mapOpenRouter(
            provider: .openrouter, snapshot: self.snapshot()) == nil)
    }

    @Test
    func `mapOpenRouter: maps balance, credits, key windows, and rate limit`() throws {
        let stats = try #require(SyncCoordinator.mapOpenRouter(
            provider: .openrouter, snapshot: self.snapshot(openRouter: self.openRouterFixture())))
        #expect(stats.balanceUSD == 7.5)
        #expect(stats.totalCreditsUSD == 50)
        #expect(stats.totalUsageUSD == 42.5)
        #expect(stats.usedPercent == 85)
        #expect(stats.keyUsageDailyUSD == 1.25)
        #expect(stats.keyUsageWeeklyUSD == 8)
        #expect(stats.keyUsageMonthlyUSD == 30)
        #expect(stats.keyLimitUSD == 100)
        #expect(stats.rateLimitRequests == 20)
        #expect(stats.rateLimitInterval == "10s")
    }

    // MARK: - E: Azure OpenAI info

    private func azureFixture() -> AzureOpenAIUsageSnapshot {
        AzureOpenAIUsageSnapshot(
            endpointHost: "r.openai.azure.com", deploymentName: "gpt-4o-prod",
            model: "gpt-4o", apiVersion: "2024-10-21", updatedAt: Self.now)
    }

    @Test
    func `mapAzureOpenAIInfo: nil for a non-azure provider`() {
        #expect(SyncCoordinator.mapAzureOpenAIInfo(
            provider: .codex, snapshot: self.snapshot(azure: self.azureFixture())) == nil)
    }

    @Test
    func `mapAzureOpenAIInfo: nil when azure usage is absent`() {
        #expect(SyncCoordinator.mapAzureOpenAIInfo(
            provider: .azureopenai, snapshot: self.snapshot()) == nil)
    }

    @Test
    func `mapAzureOpenAIInfo: maps endpoint, deployment, model, api version`() throws {
        let info = try #require(SyncCoordinator.mapAzureOpenAIInfo(
            provider: .azureopenai, snapshot: self.snapshot(azure: self.azureFixture())))
        #expect(info.endpointHost == "r.openai.azure.com")
        #expect(info.deploymentName == "gpt-4o-prod")
        #expect(info.model == "gpt-4o")
        #expect(info.apiVersion == "2024-10-21")
    }

    // MARK: - G: Alibaba Token Plan

    private func alibabaFixture() -> AlibabaTokenPlanUsageSnapshot {
        AlibabaTokenPlanUsageSnapshot(
            planName: "Bailian Pro", usedQuota: 300, totalQuota: 1000,
            remainingQuota: 700, resetsAt: Self.now, updatedAt: Self.now)
    }

    @Test
    func `mapAlibabaTokenPlan: nil for a non-alibaba provider`() {
        #expect(SyncCoordinator.mapAlibabaTokenPlan(
            provider: .codex, snapshot: self.snapshot(alibaba: self.alibabaFixture())) == nil)
    }

    @Test
    func `mapAlibabaTokenPlan: nil when alibaba usage is absent`() {
        #expect(SyncCoordinator.mapAlibabaTokenPlan(
            provider: .alibabatokenplan, snapshot: self.snapshot()) == nil)
    }

    @Test
    func `mapAlibabaTokenPlan: suppresses an empty rate-only credit card`() {
        let rateOnly = AlibabaTokenPlanUsageSnapshot(
            planName: "TOKEN PLAN",
            usedQuota: nil,
            totalQuota: nil,
            remainingQuota: nil,
            resetsAt: nil,
            fiveHourUsedPercent: 25,
            sevenDayUsedPercent: 50,
            updatedAt: Self.now)

        #expect(SyncCoordinator.mapAlibabaTokenPlan(
            provider: .alibabatokenplan,
            snapshot: self.snapshot(alibaba: rateOnly)) == nil)
        #expect(rateOnly.toUsageSnapshot().primary?.windowMinutes == 300)
        #expect(rateOnly.toUsageSnapshot().secondary?.windowMinutes == 10080)
    }

    @Test
    func `mapAlibabaTokenPlan: maps plan name and quota → credits`() throws {
        let plan = try #require(SyncCoordinator.mapAlibabaTokenPlan(
            provider: .alibabatokenplan, snapshot: self.snapshot(alibaba: self.alibabaFixture())))
        #expect(plan.planName == "Bailian Pro")
        #expect(plan.usedCredits == 300)
        #expect(plan.totalCredits == 1000)
        #expect(plan.remainingCredits == 700)
    }
}

// swiftlint:enable multiline_arguments
