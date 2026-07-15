import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

private actor ReviewBlockingSyncPusher: SyncPushing {
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var calls = 0
    private let firstResult: SyncPushResult
    private let blockedCalls: Set<Int>

    init(
        firstResult: SyncPushResult = .success,
        blockedCalls: Set<Int> = [1])
    {
        self.firstResult = firstResult
        self.blockedCalls = blockedCalls
    }

    func pushSnapshot(_ snapshot: SyncedUsageSnapshot) async -> SyncPushResult {
        self.calls += 1
        let call = self.calls
        if self.blockedCalls.contains(call) {
            await withCheckedContinuation { continuation in
                self.continuations[call] = continuation
            }
        }
        return call == 1 ? self.firstResult : .success
    }

    func releasePush(_ call: Int) {
        self.continuations.removeValue(forKey: call)?.resume()
    }

    func callCount() -> Int {
        self.calls
    }
}

@MainActor
@Suite(.serialized)
struct SyncCoordinatorSingleFlightFailureTests {
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
    func `failed push ends flight without retrying a queued snapshot`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-single-flight-failure")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let pusher = ReviewBlockingSyncPusher(firstResult: .failure("CloudKit timed out"))
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: pusher)

        let first = Task { await coordinator.pushCurrentSnapshot() }
        while await pusher.callCount() == 0 {
            await Task.yield()
        }
        await coordinator.pushCurrentSnapshot()
        #expect(coordinator.isSyncing)
        await pusher.releasePush(1)
        await first.value

        #expect(await pusher.callCount() == 1)
        #expect(!coordinator.isSyncing)
        #expect(!coordinator.lastSyncSucceeded)
        #expect(coordinator.lastSyncMessage == "CloudKit timed out")
        #expect(coordinator.lastFailedPhase == .legacyUpload)
    }

    @Test
    func `request during catch up starts one new bounded flight`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-catch-up-follow-up")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let pusher = ReviewBlockingSyncPusher(blockedCalls: [1, 2])
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: pusher)

        let first = Task { await coordinator.pushCurrentSnapshot() }
        while await pusher.callCount() == 0 {
            await Task.yield()
        }
        await coordinator.pushCurrentSnapshot()
        await pusher.releasePush(1)

        while await pusher.callCount() < 2 {
            await Task.yield()
        }
        await coordinator.pushCurrentSnapshot()
        await pusher.releasePush(2)
        await first.value

        for _ in 0..<1000 {
            if await pusher.callCount() == 3, !coordinator.isSyncing { break }
            await Task.yield()
        }

        #expect(await pusher.callCount() == 3)
        #expect(!coordinator.isSyncing)
        #expect(coordinator.lastSyncSucceeded)
    }
}
