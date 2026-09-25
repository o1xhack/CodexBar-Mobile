import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct TokenPlanMonthlyWindowTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    private static let monthly = #"{"per1MonthPercentage":0.25,"per1MonthResetTime":1791043200000}"#

    @Test(arguments: [false, true])
    func `CLI accepts flat and embedded monthly usage`(embedded: Bool) throws {
        let payload = embedded ? #"{"data":{"DataV2":{"data":{"data":\#(Self.monthly)}}}}"# : Self.monthly
        let usage = try AlibabaTokenPlanCLIUsageParser.parse(Data(payload.utf8), now: Self.now).toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.primary?.windowMinutes == 43200)
        #expect(usage.primary?.resetsAt == Date(timeIntervalSince1970: 1_791_043_200))
        #expect(usage.primary?.resetDescription == nil)
        #expect(usage.secondary == nil)
        #expect(usage.tertiary == nil)
        #expect(usage.updatedAt == Self.now)
    }

    @Test
    func `monthly usage retains rolling windows`() throws {
        let usage = try AlibabaTokenPlanCLIUsageParser.parse(Data(#"""
        {"per5HourPercentage":0.1,"per1WeekPercentage":0.2,"per1MonthPercentage":0.3}
        """#.utf8), now: Self.now).toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 10)
        #expect(usage.primary?.windowMinutes == 300)
        #expect(usage.secondary?.usedPercent == 20)
        #expect(usage.secondary?.windowMinutes == 10080)
        #expect(usage.extraRateWindows?.first?.window.usedPercent == 30)
        #expect(usage.extraRateWindows?.first?.window.windowMinutes == 43200)
        #expect(usage.extraRateWindows?.first?.title == "Monthly")
        #expect(usage.tertiary == nil)
    }

    @Test(arguments: [false, true])
    func `web monthly quota preserves totals and provider identity`(qwen: Bool) throws {
        let subscription = Data(#"{"data":{"specCode":"standard"}}"#.utf8)
        let quota = Data(#"{"standard":{"monthly":45000}}"#.utf8)
        let usage = try qwen
            ? QwenCloudUsageParser.parse(
                from: Data(Self.monthly.utf8),
                subscriptionData: subscription,
                quotaConfigData: quota,
                now: Self.now).toUsageSnapshot()
            : AlibabaTokenPlanPersonalUsageParser.parse(
                from: Data(Self.monthly.utf8),
                subscriptionData: subscription,
                quotaConfigData: quota,
                now: Self.now).toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 25)
        #expect(usage.primary?.windowMinutes == 43200)
        #expect(usage.primary?.resetDescription == "11,250 / 45,000 credits used")
        #expect(usage.identity?.providerID == (qwen ? .qwencloud : .alibabatokenplan))
        #expect(usage.identity?.loginMethod == "Standard")
    }

    @Test(arguments: ["true", "-0.1", "1.5", #""0.25""#, "null"])
    func `CLI rejects invalid monthly ratios`(ratio: String) {
        #expect(throws: AlibabaTokenPlanCLIUsageError.invalidOutput) {
            try AlibabaTokenPlanCLIUsageParser.parse(Data("{\"per1MonthPercentage\":\(ratio)}".utf8))
        }
    }

    @Test
    func `invalid monthly ratio does not erase a valid weekly window`() throws {
        let usage = try AlibabaTokenPlanCLIUsageParser.parse(Data(#"""
        {"per1WeekPercentage":0.2,"per1MonthPercentage":true,"per1MonthResetTime":1791043200000}
        """#.utf8)).toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.secondary?.usedPercent == 20)
        #expect(usage.tertiary == nil)
    }

    @Test
    func `shared mapping preserves web coercion and CLI reset validation`() throws {
        let data = Data(#"""
        {"per5HourPercentage":"invalid","per5HourResetTime":1791043200000,"per1WeekPercentage":0.2}
        """#.utf8)
        let web = try AlibabaTokenPlanPersonalUsageParser.parse(
            from: data, subscriptionData: nil, quotaConfigData: nil, now: Self.now)
        let cli = try AlibabaTokenPlanCLIUsageParser.parse(data, now: Self.now)
        #expect(web.fiveHourUsedPercent == nil)
        #expect(web.fiveHourResetsAt == Date(timeIntervalSince1970: 1_791_043_200))
        #expect(cli.fiveHourResetsAt == nil)
        #expect(cli.weeklyUsedPercent == web.weeklyUsedPercent)
    }

    @Test(arguments: [false, true])
    @MainActor
    func `menu shows monthly labels and mixed windows`(mixed: Bool) throws {
        let payload = mixed
            ? #"{"per5HourPercentage":0.1,"per1WeekPercentage":0.2,"per1MonthPercentage":0.3}"#
            : Self.monthly
        let result = Result {
            try QwenCloudUsageParser.parseUsageSnapshot(from: Data(payload.utf8), now: Self.now).toUsageSnapshot()
        }
        let error: String? = if case let .failure(error) = result {
            error.localizedDescription
        } else { nil }
        let model = UsageMenuCardView.Model.make(.init(
            provider: .qwencloud,
            metadata: QwenCloudProviderDescriptor.descriptor.metadata,
            snapshot: try? result.get(),
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: error,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: true,
            now: Self.now))
        if let directory = ProcessInfo.processInfo.environment["CODEXBAR_TOKEN_PLAN_PROOF_DIR"] {
            let hosting = NSHostingView(rootView: UsageMenuCardView(model: model, width: 340)
                .padding(16)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light))
            hosting.appearance = NSAppearance(named: .aqua)
            let data = try #require(MenuLayoutScreenshotRenderTests.pngDataWithWindow(hosting: hosting))
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try data.write(to: output.appendingPathComponent(mixed ? "mixed.png" : "monthly.png"))
        }
        #expect(error == nil)
        #expect(model.metrics.map(\.title) == (mixed ? ["5-hour", "Weekly", "Monthly"] : ["Monthly"]))
    }
}
