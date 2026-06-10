import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MiniMaxMenuCardTokenPlanTests {
    @Test
    func `minimax token plan model shows weekly quota and points balance`() throws {
        let now = Date()
        let renewsAt = Date(timeIntervalSince1970: 1_810_569_600)
        let minimax = MiniMaxUsageSnapshot(
            planName: "Token Plan · TokenPlanPlus-年度会员",
            availablePrompts: nil,
            currentPrompts: nil,
            remainingPrompts: nil,
            windowMinutes: nil,
            usedPercent: nil,
            resetsAt: nil,
            updatedAt: now,
            services: [
                MiniMaxServiceUsage(
                    serviceType: "text-generation",
                    windowType: "5 hours",
                    timeRange: "10:00-15:00(UTC+8)",
                    usage: 4,
                    limit: 100,
                    percent: 4,
                    resetsAt: now.addingTimeInterval(4 * 3600),
                    resetDescription: "Resets in 4 hours"),
                MiniMaxServiceUsage(
                    serviceType: "text-generation",
                    windowType: "Weekly",
                    timeRange: "06/01 00:00 - 06/08 00:00(UTC+8)",
                    usage: 1,
                    limit: 100,
                    percent: 1,
                    resetsAt: now.addingTimeInterval(6 * 24 * 3600),
                    resetDescription: "Resets in 6 days"),
            ],
            pointsBalance: 14000,
            subscriptionRenewsAt: renewsAt)
        let snapshot = minimax.toUsageSnapshot()
        let metadata = try #require(ProviderDefaults.metadata[.minimax])

        let model = UsageMenuCardView.Model.make(.init(
            provider: .minimax,
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
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.planText == "Plus")
        #expect(model.metrics[0].title == "Text Generation · 5h")
        #expect(model.metrics[1].title == "Text Generation · Weekly")
        #expect(model.metrics[0].detailLeftText == "Usage: 4 / 100")
        #expect(model.metrics[1].detailLeftText == "Usage: 1 / 100")
        #expect(model.metrics[0].detailRightText == nil)
        #expect(model.metrics[1].detailRightText == nil)
        #expect(model.metrics[0].detailText == nil)
        #expect(model.metrics[1].detailText == nil)
        #expect(model.metrics[0].cardStyle == false)
        #expect(model.metrics[1].cardStyle == false)
        #expect(model.providerCost?.title == "Credits")
        #expect(model.providerCost?.spendLine == "Balance: 14000")
        #expect(model.usageNotes == ["Renews: \(Self.formattedRenewalDate(renewsAt))"])
    }

    private static func formattedRenewalDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter.string(from: date)
    }
}
