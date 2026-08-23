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
        azure: AzureOpenAIUsageSnapshot? = nil,
        alibaba: AlibabaTokenPlanUsageSnapshot? = nil,
        providerCost: ProviderCostSnapshot? = nil,
        costUsage: CostUsageTokenSnapshot? = nil,
        identity: ProviderIdentitySnapshot? = nil,
        dataConfidence: UsageDataConfidence = .unknown,
        updatedAt: Date = Self.now) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: providerCost,
            costUsage: costUsage,
            azureOpenAIUsage: azure,
            alibabaTokenPlanUsage: alibaba,
            mistralUsage: mistral,
            updatedAt: updatedAt,
            identity: identity,
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
    func `Fireworks zero-limit cost maps to spend instead of quota`() throws {
        let cost = ProviderCostSnapshot(
            used: 27.40,
            limit: 0,
            currencyCode: "USD",
            period: "Last 30 days",
            updatedAt: Self.now)
        let mapped = try #require(SyncCoordinator.mapProviderAmount(
            provider: .fireworks,
            snapshot: self.snapshot(providerCost: cost, dataConfidence: .exact),
            providerCost: cost))

        #expect(mapped.kind == "spend")
        #expect(mapped.amount == 27.40)
        #expect(mapped.period == "Last 30 days")
        #expect(!mapped.isEstimated)
    }

    @Test
    func `custom plugin cost bridge preserves limit spend and balance semantics`() throws {
        let instanceID = try #require(ProviderInstanceID(rawValue: "acme-meter"))
        let limited = SyncCoordinator.mapPluginProviderUsageSnapshot(
            instanceID: instanceID,
            snapshot: self.snapshot(providerCost: ProviderCostSnapshot(
                used: 30,
                limit: 100,
                currencyCode: "USD",
                period: "Monthly",
                updatedAt: Self.now)),
            error: nil,
            deviceID: "MAC-A")
        #expect(limited.budget?.usedAmount == 30)
        #expect(limited.budget?.limitAmount == 100)
        #expect(limited.providerAmount == nil)

        let spend = SyncCoordinator.mapPluginProviderUsageSnapshot(
            instanceID: instanceID,
            snapshot: self.snapshot(
                providerCost: ProviderCostSnapshot(
                    used: 12.25,
                    limit: 0,
                    currencyCode: "EUR",
                    period: "Last 7 days",
                    updatedAt: Self.now),
                dataConfidence: .estimated),
            error: nil,
            deviceID: "MAC-A")
        #expect(spend.budget == nil)
        #expect(spend.providerAmount?.kind == "spend")
        #expect(spend.providerAmount?.amount == 12.25)
        #expect(spend.providerAmount?.isEstimated == true)

        let balance = SyncCoordinator.mapPluginProviderUsageSnapshot(
            instanceID: instanceID,
            snapshot: self.snapshot(providerCost: ProviderCostSnapshot(
                used: 10,
                limit: 50,
                currencyCode: "GBP",
                period: "Monthly",
                balance: 40,
                updatedAt: Self.now)),
            error: nil,
            deviceID: "MAC-A")
        #expect(balance.budget?.limitAmount == 50)
        #expect(balance.providerAmount?.kind == "balance")
        #expect(balance.providerAmount?.amount == 40)
    }

    @Test
    func `custom plugin cost-only snapshot remains visible to iOS with UTC day metadata`() throws {
        let instanceID = try #require(ProviderInstanceID(rawValue: "acme-meter"))
        let costUpdatedAt = try #require(ISO8601DateFormatter().date(from: "2026-08-22T12:00:00Z"))
        let costUsage = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 300,
            last30DaysCostUSD: 4.25,
            last30DaysRequests: 3,
            historyDays: 7,
            historyCoverageIsEstablished: true,
            meteredCostUSD: 3.0,
            costProvenance: .mixed,
            daily: [CostUsageDailyReport.Entry(
                date: "2026-08-22",
                inputTokens: 200,
                outputTokens: 100,
                totalTokens: 300,
                requestCount: 3,
                costUSD: 4.25,
                modelsUsed: ["acme-pro"],
                modelBreakdowns: [CostUsageDailyReport.ModelBreakdown(
                    modelName: "acme-pro",
                    costUSD: 4.25,
                    totalTokens: 300,
                    requestCount: 3,
                    isEstimated: true)],
                estimatedRequestCount: 1)],
            bucketTimeZoneIdentifier: "UTC",
            windowEndDayKey: "2026-08-18",
            updatedAt: costUpdatedAt)

        let mapped = SyncCoordinator.mapPluginProviderUsageSnapshot(
            instanceID: instanceID,
            snapshot: self.snapshot(costUsage: costUsage),
            error: nil,
            deviceID: "MAC-A")
        let summary = try #require(mapped.costSummary)
        #expect(mapped.hasUsableSignal)
        #expect(summary.last30DaysCostUSD == 4.25)
        #expect(summary.last30DaysTokens == 300)
        #expect(summary.daily.first?.dayKey == "2026-08-22")
        #expect(summary.daily.first?.isEstimated == true)
        #expect(summary.costProvenance == .mixed)
        #expect(summary.coverage?.estimated == 1)
        #expect(summary.sourceUpdatedAt == costUpdatedAt)
        #expect(summary.sourceDayKey == "2026-08-18")
        #expect(summary.bucketTimeZoneIdentifier == "GMT")
    }

    @Test
    func `custom plugin account ID wins over email and merges only matching accounts`() throws {
        let instanceID = try #require(ProviderInstanceID(rawValue: "acme-meter"))
        func mapped(accountID: String, email: String, deviceID: String) -> ProviderUsageSnapshot {
            let identity = ProviderIdentitySnapshot(
                providerID: instanceID,
                accountEmail: email,
                accountOrganization: nil,
                loginMethod: "API key",
                accountID: accountID)
            return SyncCoordinator.mapPluginProviderUsageSnapshot(
                instanceID: instanceID,
                snapshot: self.snapshot(identity: identity),
                error: nil,
                deviceID: deviceID)
        }

        let first = mapped(accountID: "Account A", email: "shared@example.com", deviceID: "MAC-A")
        let same = mapped(accountID: " account a ", email: "renamed@example.com", deviceID: "MAC-B")
        let different = mapped(accountID: "Account B", email: "shared@example.com", deviceID: "MAC-B")

        #expect(first.accountIdentities?.first == "acme-meter:account:account%20a")
        #expect(first.accountIdentities?.first == same.accountIdentities?.first)
        #expect(first.accountIdentities?.first != different.accountIdentities?.first)
        #expect(first.accountIdentities?.contains("acme-meter:email:shared@example.com") == false)
        #expect(first.accountRecordKey != same.accountRecordKey)
    }

    @Test
    func `custom plugin falls back from real email to device without treating labels as email`() throws {
        let instanceID = try #require(ProviderInstanceID(rawValue: "acme-meter"))
        func mapped(identity: ProviderIdentitySnapshot?, deviceID: String) -> ProviderUsageSnapshot {
            SyncCoordinator.mapPluginProviderUsageSnapshot(
                instanceID: instanceID,
                snapshot: self.snapshot(identity: identity),
                error: nil,
                deviceID: deviceID)
        }

        let emailIdentity = ProviderIdentitySnapshot(
            providerID: instanceID,
            accountEmail: " SAME@Example.com ",
            accountOrganization: nil,
            loginMethod: nil)
        let emailA = mapped(identity: emailIdentity, deviceID: "MAC-A")
        let emailB = mapped(identity: emailIdentity, deviceID: "MAC-B")
        #expect(emailA.accountIdentities?.first == "acme-meter:email:same@example.com")
        #expect(emailA.accountIdentities?.first == emailB.accountIdentities?.first)

        let accountlessA = mapped(identity: nil, deviceID: "MAC-A")
        let accountlessB = mapped(identity: nil, deviceID: "MAC-B")
        #expect(accountlessA.accountIdentities == ["acme-meter:record:device-mac-a"])
        #expect(accountlessB.accountIdentities == ["acme-meter:record:device-mac-b"])

        let fallbackLabel = ProviderIdentitySnapshot(
            providerID: instanceID,
            accountEmail: "Production workspace",
            accountOrganization: nil,
            loginMethod: "Token",
            accountEmailIsFallbackLabel: true)
        let fallback = mapped(identity: fallbackLabel, deviceID: "MAC-A")
        #expect(fallback.accountEmail == "Production workspace")
        #expect(fallback.accountIdentities == ["acme-meter:record:device-mac-a"])
        #expect(fallback.accountIdentities?.contains(where: { $0.contains(":email:") }) == false)
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
            providerID: UsageProvider.claude.instanceID,
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
            providerID: UsageProvider.cursor.instanceID,
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
                    day: "2023-11-13", cost: 1.5, inputTokens: 400, cachedTokens: 100, outputTokens: 200,
                    models: [
                        .init(name: "mistral-large", cost: 1.0, inputTokens: 300, cachedTokens: 50, outputTokens: 150),
                        .init(name: "free-model", cost: 0, inputTokens: 100, cachedTokens: 50, outputTokens: 50),
                    ]),
                MistralDailyUsageBucket(
                    day: "2023-11-14", cost: 2.7, inputTokens: 600, cachedTokens: 100, outputTokens: 300,
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
        #expect(summary.sessionCostUSD == nil)
        #expect(summary.sessionTokens == nil)
        #expect(summary.daily.count == 2)

        let day25 = try #require(summary.daily.first { $0.dayKey == "2023-11-13" })
        #expect(day25.costUSD == 1.5)
        #expect(day25.totalTokens == 700) // 400 + 100 + 200
        #expect(day25.costIsKnown == true)
        #expect(summary.costProvenance == .vendorMetered)
        #expect(summary.historyCoverageIsEstablished == true)
        // free-model (cost 0) is filtered out; only the paid model survives.
        #expect(day25.modelBreakdowns.count == 1)
        #expect(day25.modelBreakdowns.first?.label == "mistral-large")
        #expect(day25.modelBreakdowns.first?.costUSD == 1.0)
    }

    @Test
    func `mapMistralCostSummary: source freshness uses the provider fetch instant`() throws {
        let fetchedAt = try #require(ISO8601DateFormatter().date(from: "2026-07-16T00:30:00Z"))
        let summary = try #require(SyncCoordinator.mapMistralCostSummary(
            provider: .mistral,
            snapshot: self.snapshot(mistral: self.mistralFixture(), updatedAt: fetchedAt)))

        #expect(summary.sourceUpdatedAt == fetchedAt)
        #expect(summary.sourceUpdatedAt != self.mistralFixture().updatedAt)
        #expect(summary.sourceDayKey == "2026-07-16")
        #expect(summary.bucketTimeZoneIdentifier == "UTC")
    }

    @Test
    func `mapMistralCostSummary: sparse history does not publish an old bucket as Today`() throws {
        let sparse = MistralUsageSnapshot(
            totalCost: 1.5, currency: "USD", currencySymbol: "$",
            totalInputTokens: 400, totalOutputTokens: 200, totalCachedTokens: 100,
            modelCount: 1,
            daily: [MistralDailyUsageBucket(
                day: "2023-11-13", cost: 1.5,
                inputTokens: 400, cachedTokens: 100, outputTokens: 200,
                models: [.init(
                    name: "mistral-large", cost: 1.5,
                    inputTokens: 400, cachedTokens: 100, outputTokens: 200)])],
            startDate: nil, endDate: nil, updatedAt: Self.now)

        let summary = try #require(SyncCoordinator.mapMistralCostSummary(
            provider: .mistral,
            snapshot: self.snapshot(mistral: sparse)))

        #expect(summary.sessionCostUSD == nil)
        #expect(summary.sessionTokens == nil)
        #expect(summary.last30DaysCostUSD == 1.5)
        #expect(summary.last30DaysTokens == 700)
    }

    @Test
    func `mapMistralCostSummary: preserves an authoritative zero-cost day`() throws {
        let zero = MistralUsageSnapshot(
            totalCost: 0, currency: "USD", currencySymbol: "$",
            totalInputTokens: 10, totalOutputTokens: 5, totalCachedTokens: 0,
            modelCount: 1,
            daily: [MistralDailyUsageBucket(
                day: "2023-11-14", cost: 0,
                inputTokens: 10, cachedTokens: 0, outputTokens: 5,
                models: [.init(
                    name: "free-model", cost: 0,
                    inputTokens: 10, cachedTokens: 0, outputTokens: 5)])],
            startDate: nil, endDate: nil, updatedAt: Self.now)
        let summary = try #require(SyncCoordinator.mapMistralCostSummary(
            provider: .mistral,
            snapshot: self.snapshot(mistral: zero)))

        #expect(summary.daily.first?.costUSD == 0)
        #expect(summary.daily.first?.costIsKnown == true)
        #expect(summary.last30DaysCostUSD == 0)
        #expect(summary.costProvenance == .vendorMetered)
    }

    @Test
    func `mapMistralCostSummary: invalid raw totals remain unavailable`() throws {
        let invalid = MistralUsageSnapshot(
            totalCost: 5.0, currency: "USD", currencySymbol: "$",
            totalInputTokens: 1000, totalOutputTokens: 500, totalCachedTokens: 200,
            modelCount: 2,
            daily: self.mistralFixture().daily,
            startDate: nil, endDate: nil, updatedAt: Self.now)

        let summary = try #require(SyncCoordinator.mapMistralCostSummary(
            provider: .mistral,
            snapshot: self.snapshot(mistral: invalid)))

        #expect(summary.last30DaysCostUSD == nil)
        #expect(summary.last30DaysTokens == 1700)
        #expect(summary.daily.allSatisfy { $0.costUSD == 0 && $0.costIsKnown == false })
        #expect(summary.daily.flatMap(\.modelBreakdowns).isEmpty)
        #expect(summary.costProvenance == .unknown)
        #expect(summary.coverage?.unpriced == 2)
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
