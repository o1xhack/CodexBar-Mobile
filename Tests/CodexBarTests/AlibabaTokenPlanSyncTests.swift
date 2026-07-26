import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct AlibabaTokenPlanSyncTests {
    @Test
    func `sync preserves duration labels for iOS`() async throws {
        let suite = "AlibabaTokenPlanSyncTests-labels"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .alibabatokenplan,
            metadata: #require(ProviderDefaults.metadata[.alibabatokenplan]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(
            AlibabaTokenPlanUsageSnapshot(
                planName: "TOKEN PLAN",
                usedQuota: 300,
                totalQuota: 1000,
                remainingQuota: 700,
                resetsAt: nil,
                fiveHourUsedPercent: 10,
                fiveHourResetsAt: nil,
                sevenDayUsedPercent: 20,
                sevenDayResetsAt: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
                .toUsageSnapshot(),
            provider: .alibabatokenplan)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.alibabatokenplan.rawValue }))
        #expect(provider.rateWindows.map(\.label) == ["5-hour", "Weekly", "Credits"])
    }

    @Test
    func `sync preserves weekly semantic lane for partial responses`() async throws {
        let suite = "AlibabaTokenPlanSyncTests-weekly-lane"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .alibabatokenplan,
            metadata: #require(ProviderDefaults.metadata[.alibabatokenplan]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        store._setSnapshotForTesting(
            AlibabaTokenPlanUsageSnapshot(
                planName: "Bailian Pro",
                usedQuota: 300,
                totalQuota: 1000,
                remainingQuota: 700,
                resetsAt: nil,
                sevenDayUsedPercent: 20,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
                .toUsageSnapshot(),
            provider: .alibabatokenplan)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.alibabatokenplan.rawValue }))
        #expect(provider.primary == nil)
        #expect(provider.secondary?.label == "Weekly")
        #expect(provider.secondary?.windowMinutes == 7 * 24 * 60)
        #expect(provider.rateWindows.map(\.label) == ["Weekly", "Credits"])
    }
}
