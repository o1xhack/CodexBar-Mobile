import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MuseMenuCardModelTests {
    @Test(arguments: [
        (UsageDataConfidence.estimated, [L("Quota from the selected dev.meta.ai browser team")]),
        (.exact, []),
    ])
    func `browser team quotas are disclosed under the usage bars`(
        confidence: UsageDataConfidence,
        expectedNotes: [String]) throws
    {
        let now = Date(timeIntervalSince1970: 1_790_341_873)
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 15, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            updatedAt: now,
            identity: nil,
            dataConfidence: confidence)
        let metadata = try #require(ProviderDefaults.metadata[.muse])

        let model = UsageMenuCardView.Model.make(.init(
            provider: .muse,
            metadata: metadata,
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
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.usageNotes == expectedNotes)
    }
}
