import Foundation
import Testing
@testable import CodexBarCore

struct OneConsoleTokenPlanSnapshotTests {
    @Test(arguments: ["lite", "standard", "pro", "max", "custom"])
    func `personal parsers share tier quotas without sharing provider identity`(plan: String) throws {
        let usage = Data(#"{"per5HourPercentage":0.25,"per1WeekPercentage":0.5,"per5HourResetTime":1700003600000}"#
            .utf8)
        let subscription = Data("{\"specCode\":\"  \(plan.uppercased())  \"}".utf8)
        let quota = Data("{\"\(plan)\":{\"five_hour\":100,\"weekly\":200}}".utf8)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let alibaba = try AlibabaTokenPlanPersonalUsageParser.parse(
            from: usage, subscriptionData: subscription, quotaConfigData: quota, now: now)
        let qwen = try QwenCloudUsageParser.parse(
            from: usage, subscriptionData: subscription, quotaConfigData: quota, now: now)
        let expectedPlan = plan == "custom" ? plan : plan.capitalized
        let snapshots: [any OneConsoleTokenPlanSnapshot] = [alibaba, qwen]
        for snapshot in snapshots {
            #expect(snapshot.planName == expectedPlan)
            #expect(snapshot.usedQuota == nil)
            #expect(snapshot.totalQuota == nil)
            #expect(snapshot.remainingQuota == nil)
            #expect(snapshot.fiveHourUsedPercent == 25)
            #expect(snapshot.fiveHourTotalQuota == 100)
            #expect(snapshot.fiveHourResetsAt == Date(timeIntervalSince1970: 1_700_003_600))
            #expect(snapshot.weeklyUsedPercent == 50)
            #expect(snapshot.weeklyTotalQuota == 200)
            #expect(snapshot.updatedAt == now)
        }
        #expect(alibaba.toUsageSnapshot().identity?.providerID == .alibabatokenplan)
        #expect(qwen.toUsageSnapshot().identity?.providerID == .qwencloud)
    }

    @Test(arguments: [nil, Data("not json".utf8), Data(#"{"specCode":123}"#.utf8)])
    func `missing or malformed tiers preserve provider defaults`(subscription: Data?) throws {
        let usage = Data(#"{"per1WeekPercentage":0}"#.utf8)
        let alibaba = try AlibabaTokenPlanPersonalUsageParser.parse(
            from: usage, subscriptionData: subscription, quotaConfigData: nil, now: Date())
        let qwen = try QwenCloudUsageParser.parse(
            from: usage, subscriptionData: subscription, quotaConfigData: nil, now: Date())
        #expect(alibaba.planName == "Personal")
        #expect(qwen.planName == nil)
        #expect(alibaba.fiveHourUsedPercent == nil)
        #expect(qwen.fiveHourUsedPercent == nil)
        #expect(alibaba.weeklyUsedPercent == 0)
        #expect(qwen.weeklyUsedPercent == 0)
    }

    @Test
    func `subscription aliases and camel case quotas retain precedence`() throws {
        let snapshot = try QwenCloudUsageParser.parse(
            from: Data(#"{"per5HourPercentage":2,"per1WeekPercentage":-1}"#.utf8),
            subscriptionData: Data(#"{"specCode":" ","spec_code":"pro","planName":"max"}"#.utf8),
            quotaConfigData: Data(#"{"pro":{"fiveHour":80,"weekly":160},"max":{"fiveHour":800}}"#.utf8),
            now: Date())
        #expect(snapshot.planName == "Pro")
        #expect(snapshot.fiveHourUsedPercent == 100)
        #expect(snapshot.weeklyUsedPercent == 0)
        #expect(snapshot.fiveHourTotalQuota == 80)
        #expect(snapshot.weeklyTotalQuota == 160)
    }
}
