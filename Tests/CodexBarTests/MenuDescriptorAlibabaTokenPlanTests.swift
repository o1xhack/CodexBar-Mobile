import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MenuDescriptorAlibabaTokenPlanTests {
    @Test
    func `rate limits use five hour and weekly labels`() throws {
        let suite = "MenuDescriptorAlibabaTokenPlanTests-rate-limits"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        let snapshot = AlibabaTokenPlanUsageSnapshot(
            planName: "TOKEN PLAN",
            usedQuota: nil,
            totalQuota: nil,
            remainingQuota: nil,
            resetsAt: nil,
            fiveHourUsedPercent: 7.69,
            fiveHourResetsAt: nil,
            sevenDayUsedPercent: 2.61,
            sevenDayResetsAt: nil,
            updatedAt: Date(timeIntervalSince1970: 1))
            .toUsageSnapshot()
        store._setSnapshotForTesting(snapshot, provider: .alibabatokenplan)

        let descriptor = MenuDescriptor.build(
            provider: .alibabatokenplan,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false)
        let lines = descriptor.sections.flatMap(\.entries).compactMap { entry -> String? in
            guard case let .text(text, _) = entry else { return nil }
            return text
        }

        #expect(lines.contains(where: { $0.hasPrefix("5-hour:") }))
        #expect(lines.contains(where: { $0.hasPrefix("Weekly:") }))
        #expect(!lines.contains(where: { $0.hasPrefix("Credits:") || $0.hasPrefix("Usage:") }))
    }
}
