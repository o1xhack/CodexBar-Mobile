import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct OllamaSyncCoordinatorDurabilityTests {
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
    func `Ollama API fallback ghost does not delete the last good per-provider record`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-ollama-api-fallback")
        settings.iCloudSyncEnabled = true
        settings.ollamaAPIToken = "test-ollama-api-key"
        try settings.setProviderEnabled(
            provider: .ollama,
            metadata: #require(ProviderDefaults.metadata[.ollama]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        let goodSnapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: 60,
                resetsAt: pinned.addingTimeInterval(3600),
                resetDescription: "in 1 hour"),
            secondary: RateWindow(
                usedPercent: 10,
                windowMinutes: 10080,
                resetsAt: pinned.addingTimeInterval(86400),
                resetDescription: "tomorrow"),
            updatedAt: pinned,
            identity: ProviderIdentitySnapshot(
                providerID: .ollama,
                accountEmail: "user@example.com",
                accountOrganization: nil,
                loginMethod: "web"))
        store._setSnapshotForTesting(goodSnapshot, provider: .ollama)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()
        #expect(mock.lastPerProviderEnvelopes.contains { $0.provider.providerID == "ollama" })

        // The browser session flakes, so the API fallback returns an
        // intentional empty-quota snapshot. It must not delete the last good
        // CloudKit quota record.
        let apiFallbackSnapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            updatedAt: pinned.addingTimeInterval(60),
            identity: ProviderIdentitySnapshot(
                providerID: .ollama,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: "API key"))
        store._setSnapshotForTesting(apiFallbackSnapshot, provider: .ollama)

        await coordinator.pushCurrentSnapshot()

        #expect(mock.deleteCallCount == 0)
    }
}
