import Foundation
import Testing
@testable import CodexBarCore

struct AlibabaTokenPlanPersonalTests {
    @Test
    func `personal variants use dedicated rolling window gateways`() {
        #expect(AlibabaTokenPlanAPIRegion.international.usesPersonalTokenPlanAPI == false)
        #expect(AlibabaTokenPlanAPIRegion.chinaMainland.usesPersonalTokenPlanAPI == false)
        #expect(AlibabaTokenPlanAPIRegion.internationalPersonal.usesPersonalTokenPlanAPI)
        #expect(AlibabaTokenPlanAPIRegion.chinaMainlandPersonal.usesPersonalTokenPlanAPI)
        #expect(
            AlibabaTokenPlanUsageFetcher.defaultQuotaURL(region: .internationalPersonal).host
                == "bailian-singapore-cs.alibabacloud.com")
        #expect(
            AlibabaTokenPlanUsageFetcher.defaultQuotaURL(region: .chinaMainlandPersonal).host
                == "bailian-cs.console.aliyun.com")
    }

    @Test
    func `personal parser maps rolling windows and plan quotas`() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try AlibabaTokenPlanPersonalUsageParser.parse(
            from: self.fixture("personal_usage"),
            subscriptionData: self.fixture("personal_subscription"),
            quotaConfigData: self.fixture("personal_quota_config"),
            now: now)
        let usage = snapshot.toUsageSnapshot()

        #expect(snapshot.planName == "Pro")
        #expect(snapshot.fiveHourTotalQuota == 12000)
        #expect(snapshot.weeklyTotalQuota == 40000)
        #expect(abs((usage.primary?.usedPercent ?? -.infinity) - 0.09973083333333333) < 0.000_000_001)
        #expect(usage.primary?.windowMinutes == 5 * 60)
        #expect(abs((usage.secondary?.usedPercent ?? -.infinity) - 0.03014725) < 0.000_000_001)
        #expect(usage.secondary?.windowMinutes == 7 * 24 * 60)
        #expect(usage.secondary?.resetDescription == "12.06 / 40,000 credits used")
    }

    @Test
    func `legacy Team rolling windows retain monthly credits as tertiary`() {
        let snapshot = AlibabaTokenPlanUsageSnapshot(
            planName: "Bailian Pro",
            usedQuota: 250,
            totalQuota: 1000,
            remainingQuota: 750,
            resetsAt: nil,
            sevenDayUsedPercent: 12.5,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let usage = snapshot.toUsageSnapshot()

        #expect(usage.primary == nil)
        #expect(usage.secondary?.usedPercent == 12.5)
        #expect(usage.tertiary?.usedPercent == 25)
        #expect(usage.tertiary?.windowMinutes == 30 * 24 * 60)
    }

    @Test
    func `personal login error maps to login required`() {
        let json = """
        {
          "data": {
            "success": false,
            "errorCode": "BailianGateway.Login.NotLogined",
            "errorMsg": "BailianGateway.Login.NotLogined"
          },
          "httpStatusCode": "200"
        }
        """

        #expect(throws: AlibabaTokenPlanUsageError.loginRequired) {
            try AlibabaTokenPlanPersonalUsageParser.parse(
                from: Data(json.utf8),
                subscriptionData: nil,
                quotaConfigData: nil,
                now: Date(timeIntervalSince1970: 1_700_000_000))
        }
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures/AlibabaTokenPlan"))
        return try Data(contentsOf: url)
    }
}
