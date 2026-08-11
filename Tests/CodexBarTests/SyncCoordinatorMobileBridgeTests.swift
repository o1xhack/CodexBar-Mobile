import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
@Suite(.serialized)
struct SyncCoordinatorMobileBridgeTests {
    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }

    @Test
    func `Fireworks cost-only snapshot survives ghost filtering as spend without quota`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-fireworks-cost-only")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .fireworks,
            metadata: #require(ProviderDefaults.metadata[.fireworks]),
            enabled: true)
        settings.fireworksAPIToken = "test-api-key"
        settings.fireworksAccountSlug = "test-account"
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        store._setSnapshotForTesting(
            FireworksUsageSummary(
                last30DaysSpend: 27.40,
                currencyCode: "USD",
                updatedAt: pinned)
                .toUsageSnapshot(),
            provider: .fireworks)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let legacy = try #require(mock.lastSnapshot?.providers.first { $0.providerID == "fireworks" })
        #expect(legacy.primary == nil)
        #expect(legacy.rateWindows.isEmpty)
        #expect(legacy.budget == nil)
        #expect(legacy.providerAmount?.kind == "spend")
        #expect(legacy.providerAmount?.amount == 27.40)
        let perProvider = try #require(mock.lastPerProviderEnvelopes
            .first { $0.provider.providerID == "fireworks" })
        #expect(perProvider.provider.providerAmount == legacy.providerAmount)
        #expect(perProvider.provider.hasUsableSignal)
    }

    @Test
    func `IBM Bob missing budget maps to an unknown Mobile primary window`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-ibmbob-unknown-budget")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .ibmbob,
            metadata: #require(ProviderDefaults.metadata[.ibmbob]),
            enabled: true)
        settings.addTokenAccount(provider: .ibmbob, label: "Fixture", token: "fixture-key")
        let store = self.makeUsageStore(settings: settings)
        let snapshot = IBMBobUsageSnapshot(
            teams: [.init(
                instanceName: "Personal",
                teamName: "Solo",
                planName: nil,
                usedBobcoins: 12.5,
                limitBobcoins: nil,
                resetsAt: nil)],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        store._setSnapshotForTesting(snapshot.toUsageSnapshot(), provider: .ibmbob)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers.first { $0.providerID == "ibmbob" })
        let primary = try #require(provider.primary)
        #expect(provider.rateWindows.count == 1)
        #expect(primary == provider.rateWindows.first)
        #expect(primary.label == "Monthly")
        #expect(primary.usedPercent == 0)
        #expect(!primary.usageKnown)
    }
}
