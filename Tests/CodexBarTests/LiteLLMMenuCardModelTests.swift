import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct LiteLLMMenuCardModelTests {
    @Test
    func `litellm spend without budget remains visible`() throws {
        let now = Date()
        let metadata = try #require(ProviderDefaults.metadata[.litellm])
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 12.5,
                limit: 0,
                currencyCode: "USD",
                period: "Personal spend",
                updatedAt: now),
            updatedAt: now)

        let model = UsageMenuCardView.Model.make(.init(
            provider: .litellm,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.providerCost?.title == "API spend")
        #expect(model.providerCost?.spendLine == "Personal spend: $12.50")
        #expect(model.providerCost?.percentUsed == nil)
    }
}
