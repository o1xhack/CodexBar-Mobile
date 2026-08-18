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
    func `v052 provider semantics reuse the existing Mobile envelope`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-v052-provider-semantics")
        settings.iCloudSyncEnabled = true
        for provider in [UsageProvider.claude, .cursor, .opencodego, .grok] {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(ProviderDefaults.metadata[provider]),
                enabled: true)
        }
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        let window = RateWindow(
            usedPercent: 25,
            windowMinutes: 7 * 24 * 60,
            resetsAt: pinned.addingTimeInterval(86400),
            resetDescription: nil)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: window,
                secondary: window,
                tertiary: window,
                extraRateWindows: [
                    NamedRateWindow(id: "model:opus", title: "Opus only", window: window),
                ],
                updatedAt: pinned,
                identity: ProviderIdentitySnapshot(
                    providerID: .cursor,
                    accountEmail: "cursor@example.test",
                    accountOrganization: nil,
                    loginMethod: "Cursor Pro")),
            provider: .cursor)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: window,
                secondary: window,
                extraRateWindows: [
                    NamedRateWindow(id: "model:sonnet", title: "Sonnet only", window: window),
                ],
                updatedAt: pinned),
            provider: .claude)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: window,
                secondary: window,
                tertiary: window,
                updatedAt: pinned,
                dataConfidence: .estimated),
            provider: .opencodego)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: window,
                secondary: window,
                updatedAt: pinned,
                identity: ProviderIdentitySnapshot(
                    providerID: .grok,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: "SuperGrok Heavy")),
            provider: .grok)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let providers = try #require(mock.lastSnapshot?.providers)
        let cursor = try #require(providers.first { $0.providerID == "cursor" })
        #expect(cursor.allRateWindows.map(\.label) == ["Total", "Cursor", "Third Party", "Opus only"])
        #expect(cursor.allRateWindows.map(\.id) == ["primary", "secondary", "tertiary", "model:opus"])
        #expect(cursor.loginMethod == "Cursor Pro")

        let claude = try #require(providers.first { $0.providerID == "claude" })
        #expect(claude.allRateWindows.last?.id == "model:sonnet")
        #expect(claude.allRateWindows.last?.label == "Sonnet only")

        let openCodeGo = try #require(providers.first { $0.providerID == "opencodego" })
        #expect(openCodeGo.usageDataConfidence == "estimated")
        #expect(openCodeGo.allRateWindows.map(\.label) == ["5-hour", "Weekly", "Monthly"])

        let grok = try #require(providers.first { $0.providerID == "grok" })
        #expect(grok.loginMethod == "SuperGrok Heavy")
        #expect(grok.allRateWindows.map(\.label) == ["Weekly", "On-demand"])
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
