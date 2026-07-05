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
        crossModel: CrossModelUsageSnapshot? = nil) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: nil,
            secondary: nil,
            openRouterUsage: openRouter,
            crossModelUsage: crossModel,
            mistralUsage: mistral,
            azureOpenAIUsage: azure,
            alibabaTokenPlanUsage: alibaba,
            updatedAt: Self.now)
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

    @Test("mapMistralCostSummary: nil for a non-mistral provider")
    func mistralWrongProvider() {
        #expect(SyncCoordinator.mapMistralCostSummary(
            provider: .codex, snapshot: self.snapshot(mistral: self.mistralFixture())) == nil)
    }

    @Test("mapMistralCostSummary: nil when mistral usage is absent")
    func mistralNoUsage() {
        #expect(SyncCoordinator.mapMistralCostSummary(
            provider: .mistral, snapshot: self.snapshot()) == nil)
    }

    @Test("mapMistralCostSummary: nil when daily history is empty")
    func mistralEmptyDaily() {
        let empty = MistralUsageSnapshot(
            totalCost: 0, currency: "USD", currencySymbol: "$",
            totalInputTokens: 0, totalOutputTokens: 0, totalCachedTokens: 0,
            modelCount: 0, daily: [], startDate: nil, endDate: nil, updatedAt: Self.now)
        #expect(SyncCoordinator.mapMistralCostSummary(
            provider: .mistral, snapshot: self.snapshot(mistral: empty)) == nil)
    }

    @Test("mapMistralCostSummary: maps totals, daily points, and filters/sorts model breakdowns")
    func mistralMapsFields() throws {
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

    // MARK: - v0.39: CrossModel wallet + cost bridge

    private func crossModelFixture() -> CrossModelUsageSnapshot {
        CrossModelUsageSnapshot(
            currency: "USD",
            balance: 8.06,
            uncollected: 0.42,
            daily: CrossModelUsageWindow(
                cost: 0.27,
                promptTokens: 5200,
                completionTokens: 7267,
                totalTokens: 12467,
                requestCount: 84,
                successCount: 83),
            weekly: CrossModelUsageWindow(
                cost: 1.92,
                promptTokens: 41000,
                completionTokens: 52000,
                totalTokens: 93000,
                requestCount: 526,
                successCount: 520),
            monthly: CrossModelUsageWindow(
                cost: 5.37,
                promptTokens: 110_000,
                completionTokens: 150_000,
                totalTokens: 260_000,
                requestCount: 3166,
                successCount: 3140),
            updatedAt: Self.now)
    }

    @Test("mapCrossModelUsage: nil for a non-crossmodel provider")
    func crossModelWrongProvider() {
        #expect(SyncCoordinator.mapCrossModelUsage(
            provider: .codex, snapshot: self.snapshot(crossModel: self.crossModelFixture())) == nil)
    }

    @Test("mapCrossModelUsage: maps wallet and usage windows")
    func crossModelMapsTypedPayload() throws {
        let usage = try #require(SyncCoordinator.mapCrossModelUsage(
            provider: .crossmodel, snapshot: self.snapshot(crossModel: self.crossModelFixture())))
        #expect(usage.balance == 8.06)
        #expect(usage.uncollected == 0.42)
        #expect(usage.monthly?.cost == 5.37)
        #expect(usage.monthly?.requestCount == 3166)
    }

    @Test("mapCrossModelCostSummary: maps daily and monthly spend into the cost dashboard shape")
    func crossModelMapsCostSummary() throws {
        let summary = try #require(SyncCoordinator.mapCrossModelCostSummary(
            provider: .crossmodel, snapshot: self.snapshot(crossModel: self.crossModelFixture())))
        #expect(summary.sessionCostUSD == 0.27)
        #expect(summary.sessionTokens == 12467)
        #expect(summary.sessionRequests == 84)
        #expect(summary.last30DaysCostUSD == 5.37)
        #expect(summary.last30DaysTokens == 260_000)
        #expect(summary.last30DaysRequests == 3166)
        #expect(summary.currencyCode == "USD")
        #expect(summary.daily.count == 1)
        #expect(summary.daily.first?.costUSD == 0.27)
        #expect(summary.daily.first?.totalTokens == 12467)
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

    @Test("mapOpenRouter: nil for a non-openrouter provider")
    func openRouterWrongProvider() {
        #expect(SyncCoordinator.mapOpenRouter(
            provider: .codex, snapshot: self.snapshot(openRouter: self.openRouterFixture())) == nil)
    }

    @Test("mapOpenRouter: nil when openrouter usage is absent")
    func openRouterNoUsage() {
        #expect(SyncCoordinator.mapOpenRouter(
            provider: .openrouter, snapshot: self.snapshot()) == nil)
    }

    @Test("mapOpenRouter: maps balance, credits, key windows, and rate limit")
    func openRouterMapsFields() throws {
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

    @Test("mapAzureOpenAIInfo: nil for a non-azure provider")
    func azureWrongProvider() {
        #expect(SyncCoordinator.mapAzureOpenAIInfo(
            provider: .codex, snapshot: self.snapshot(azure: self.azureFixture())) == nil)
    }

    @Test("mapAzureOpenAIInfo: nil when azure usage is absent")
    func azureNoUsage() {
        #expect(SyncCoordinator.mapAzureOpenAIInfo(
            provider: .azureopenai, snapshot: self.snapshot()) == nil)
    }

    @Test("mapAzureOpenAIInfo: maps endpoint, deployment, model, api version")
    func azureMapsFields() throws {
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

    @Test("mapAlibabaTokenPlan: nil for a non-alibaba provider")
    func alibabaWrongProvider() {
        #expect(SyncCoordinator.mapAlibabaTokenPlan(
            provider: .codex, snapshot: self.snapshot(alibaba: self.alibabaFixture())) == nil)
    }

    @Test("mapAlibabaTokenPlan: nil when alibaba usage is absent")
    func alibabaNoUsage() {
        #expect(SyncCoordinator.mapAlibabaTokenPlan(
            provider: .alibabatokenplan, snapshot: self.snapshot()) == nil)
    }

    @Test("mapAlibabaTokenPlan: maps plan name and quota → credits")
    func alibabaMapsFields() throws {
        let plan = try #require(SyncCoordinator.mapAlibabaTokenPlan(
            provider: .alibabatokenplan, snapshot: self.snapshot(alibaba: self.alibabaFixture())))
        #expect(plan.planName == "Bailian Pro")
        #expect(plan.usedCredits == 300)
        #expect(plan.totalCredits == 1000)
        #expect(plan.remainingCredits == 700)
    }
}

// swiftlint:enable multiline_arguments
