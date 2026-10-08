import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

private actor ScriptedSyncPusher: SyncPushing {
    private var results: [SyncPushResult]
    private var calls = 0

    init(results: [SyncPushResult]) {
        self.results = results
    }

    func pushSnapshot(_ snapshot: SyncedUsageSnapshot) async -> SyncPushResult {
        self.calls += 1
        return self.results.isEmpty ? .success : self.results.removeFirst()
    }

    func callCount() -> Int {
        self.calls
    }
}

@MainActor
@Suite(.serialized)
struct SyncCoordinatorPushRetryTests {
    private func makeCoordinator(suite: String, pusher: any SyncPushing) -> SyncCoordinator {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = true
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        return SyncCoordinator(store: store, settings: settings, syncManager: pusher)
    }

    @Test
    func `failed pushes keep one pending retry with growing backoff and stopping clears it`() async {
        let pusher = ScriptedSyncPusher(results: [.failure("timed out"), .failure("timed out")])
        let coordinator = self.makeCoordinator(suite: "SyncCoord-push-retry-pending", pusher: pusher)
        #expect(coordinator.failedPushRetryDelays == [30, 60, 120, 300])

        await coordinator.pushCurrentSnapshot()
        #expect(coordinator.consecutivePushFailures == 1)
        #expect(coordinator.hasPendingPushRetry)

        await coordinator.pushCurrentSnapshot()
        #expect(coordinator.consecutivePushFailures == 2)
        #expect(coordinator.hasPendingPushRetry, "still exactly one pending retry")

        coordinator.stopObserving()
        #expect(!coordinator.hasPendingPushRetry)
        #expect(coordinator.consecutivePushFailures == 0)
    }

    @Test
    func `a scheduled retry pushes again and success clears the backoff`() async throws {
        let pusher = ScriptedSyncPusher(results: [.failure("timed out")])
        let coordinator = self.makeCoordinator(suite: "SyncCoord-push-retry-fires", pusher: pusher)
        coordinator.failedPushRetryDelays = [0.05]
        coordinator.startObserving()
        defer { coordinator.stopObserving() }

        await coordinator.pushCurrentSnapshot()
        let deadline = Date().addingTimeInterval(10)
        while coordinator.consecutivePushFailures != 0 || coordinator.hasPendingPushRetry {
            try #require(Date() < deadline, "retry did not succeed in time")
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(await pusher.callCount() >= 2)
        #expect(coordinator.lastSyncSucceeded)
    }

    @Test
    func `the limits note appears only for a refresh with neither data nor an error`() {
        let note = SyncCoordinator.limitsUnavailableNote(snapshot: nil, error: nil, availability: .unavailable)
        #expect(note == "Usage limits are not available for this account on this Mac.")
        #expect(SyncCoordinator.limitsUnavailableNote(snapshot: nil, error: "boom", availability: .unavailable) == nil)
        #expect(SyncCoordinator.limitsUnavailableNote(snapshot: nil, error: nil, availability: .available) == nil)
        #expect(SyncCoordinator.limitsUnavailableNote(snapshot: nil, error: nil, availability: nil) == nil)
        let snapshot = UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date())
        #expect(SyncCoordinator.limitsUnavailableNote(snapshot: snapshot, error: nil, availability: .unavailable) == nil)
    }
}
