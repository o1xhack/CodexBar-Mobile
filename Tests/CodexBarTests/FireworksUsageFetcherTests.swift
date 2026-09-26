import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@Suite(.serialized)
struct FireworksUsageFetcherTests {
    @Test
    func `presents an unbounded billing summary as API spend`() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 62.99,
                limit: 0,
                currencyCode: "USD",
                period: "Last 30 days",
                updatedAt: Date()),
            updatedAt: Date())

        let presentation = FireworksProviderDescriptor.descriptor.presentation.cost(snapshot: snapshot)

        #expect(presentation.menuCardStyle == .apiSpend)
        #expect(FireworksProviderDescriptor.descriptor.presentation.menuCard.providerCostIsRequiredUsage)
        #expect(!OpenAIAPIProviderDescriptor.descriptor.presentation.menuCard.providerCostIsRequiredUsage)
    }

    @Test
    func `presents a configured spend limit as a generic budget`() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 62.99,
                limit: 100,
                currencyCode: "USD",
                period: "Last 30 days",
                updatedAt: Date()),
            updatedAt: Date())

        let presentation = FireworksProviderDescriptor.descriptor.presentation.cost(snapshot: snapshot)

        #expect(presentation.menuCardStyle == .generic)
    }

    @Test @MainActor
    func `shows billing spend when cost summary is disabled`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 62.99,
                limit: 0,
                currencyCode: "USD",
                period: "Last 30 days",
                updatedAt: now),
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .fireworks,
            metadata: FireworksProviderDescriptor.descriptor.metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            costSummaryInlineEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.providerCost?.title == "API spend")
        #expect(model.providerCost?.spendLine == "Last 30 days: $62.99")
    }

    @Test @MainActor
    func `keeps billing spend visible when the provider changes its period label`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 62.99,
                limit: 0,
                currencyCode: "USD",
                period: "Trailing month",
                updatedAt: now),
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .fireworks,
            metadata: FireworksProviderDescriptor.descriptor.metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            costSummaryInlineEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.providerCost?.title == "API spend")
        #expect(model.providerCost?.spendLine == "Trailing month: $62.99")
    }
}
