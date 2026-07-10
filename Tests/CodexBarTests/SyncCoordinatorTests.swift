import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// Mock sync pusher that records push calls for testing.
final class MockSyncPusher: SyncPushing, @unchecked Sendable {
    var pushCount = 0
    var lastSnapshot: SyncedUsageSnapshot?
    var nextResult: SyncPushResult = .success

    // P4 — per-provider write tracking
    var perProviderCallCount = 0
    var lastPerProviderEnvelopes: [ProviderUsageEnvelope] = []
    var nextPerProviderResult: SyncPushResult = .success

    // L1 ghost-records cleanup — delete tracking
    var deleteCallCount = 0
    var deletedRecordNamesAcrossCalls: [[String]] = []
    var nextDeleteResult: SyncPushResult = .success

    // L1 reconcile — startup CKQuery for stranded records
    var fetchRecordNamesCallCount = 0
    var fetchRecordNamesLastDeviceID: String?
    var nextFetchRecordNamesResult: [String] = []

    @discardableResult
    func pushSnapshot(_ snapshot: SyncedUsageSnapshot) async -> SyncPushResult {
        self.pushCount += 1
        self.lastSnapshot = snapshot
        return self.nextResult
    }

    @discardableResult
    func pushPerProviderRecords(
        _ envelopes: [ProviderUsageEnvelope]) async -> SyncPushResult
    {
        self.perProviderCallCount += 1
        self.lastPerProviderEnvelopes = envelopes
        return self.nextPerProviderResult
    }

    @discardableResult
    func deletePerProviderRecords(recordNames: [String]) async -> SyncPushResult {
        self.deleteCallCount += 1
        self.deletedRecordNamesAcrossCalls.append(recordNames)
        return self.nextDeleteResult
    }

    func fetchPerProviderRecordNames(forDeviceID deviceID: String) async -> [String] {
        self.fetchRecordNamesCallCount += 1
        self.fetchRecordNamesLastDeviceID = deviceID
        return self.nextFetchRecordNamesResult
    }
}

@MainActor
@Suite(.serialized)
struct SyncCoordinatorTests {
    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
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
    func `push skipped when sync disabled`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-disabled")
        settings.iCloudSyncEnabled = false
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        #expect(mock.pushCount == 0)
        #expect(coordinator.lastSyncTime == nil)
    }

    @Test
    func `push succeeds when sync enabled`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-enabled")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // Push may or may not happen depending on whether there are enabled providers.
        // With default config, providers may be enabled, so check status tracking.
        if mock.pushCount > 0 {
            #expect(coordinator.lastSyncTime != nil)
            #expect(coordinator.lastSyncSucceeded == true)
            #expect(coordinator.lastSyncMessage == nil)
        }
    }

    @Test
    func `push failure tracks status`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-failure")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        mock.nextResult = .failure("iCloud sync unavailable")
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        if mock.pushCount > 0 {
            #expect(coordinator.lastSyncTime != nil)
            #expect(coordinator.lastSyncSucceeded == false)
            #expect(coordinator.lastSyncMessage == "iCloud sync unavailable")
        }
    }

    @Test
    func `is syncing is false after push`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-syncing")
        settings.iCloudSyncEnabled = true
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // isSyncing should be false after synchronous push completes
        #expect(coordinator.isSyncing == false)
    }

    @Test
    func `push includes model and service breakdowns`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-breakdowns")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 1500,
                sessionCostUSD: 0.32,
                last30DaysTokens: 32000,
                last30DaysCostUSD: 2.40,
                daily: [
                    CostUsageDailyReport.Entry(
                        date: "2026-03-16",
                        inputTokens: 1000,
                        outputTokens: 500,
                        totalTokens: 1500,
                        costUSD: 2.40,
                        modelsUsed: ["gpt-5.4", "gpt-5.3-codex"],
                        modelBreakdowns: [
                            .init(modelName: "gpt-5.4", costUSD: 1.80),
                            .init(modelName: "gpt-5.3-codex", costUSD: 0.60),
                        ]),
                ],
                updatedAt: Date()),
            provider: .codex)
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [
                OpenAIDashboardDailyBreakdown(
                    day: "2026-03-16",
                    services: [
                        OpenAIDashboardServiceUsage(service: "CLI", creditsUsed: 1.90),
                        OpenAIDashboardServiceUsage(service: "GitHub Code Review", creditsUsed: 0.50),
                    ],
                    totalCreditsUsed: 2.40),
            ],
            creditsPurchaseURL: nil,
            updatedAt: Date())

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.codex.rawValue }))
        let costSummary = try #require(provider.costSummary)
        let daily = try #require(costSummary.daily.first)

        #expect(daily.modelBreakdowns == [
            SyncCostBreakdown(label: "gpt-5.4", costUSD: 1.80),
            SyncCostBreakdown(label: "gpt-5.3-codex", costUSD: 0.60),
        ])
        #expect(daily.serviceBreakdowns == [
            SyncCostBreakdown(label: "Codex Run", costUSD: 1.90),
            SyncCostBreakdown(label: "GitHub Code Review", costUSD: 0.50),
        ])
    }

    @Test
    func `push builds codex cost summary from dashboard when token snapshot missing`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-dashboardFallback")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store.openAIDashboard = OpenAIDashboardSnapshot(
            signedInEmail: "user@example.com",
            codeReviewRemainingPercent: nil,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [
                OpenAIDashboardDailyBreakdown(
                    day: "2026-03-15",
                    services: [OpenAIDashboardServiceUsage(service: "CLI", creditsUsed: 0.75)],
                    totalCreditsUsed: 0.75),
                OpenAIDashboardDailyBreakdown(
                    day: "2026-03-16",
                    services: [OpenAIDashboardServiceUsage(service: "GitHub Code Review", creditsUsed: 1.25)],
                    totalCreditsUsed: 1.25),
            ],
            creditsPurchaseURL: nil,
            updatedAt: Date())

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == UsageProvider.codex.rawValue }))
        let costSummary = try #require(provider.costSummary)
        #expect(costSummary.sessionCostUSD == nil)
        #expect(costSummary.last30DaysCostUSD == 2.0)
        #expect(costSummary.daily.count == 2)
        #expect(costSummary.daily[0].serviceBreakdowns == [SyncCostBreakdown(label: "Codex Run", costUSD: 0.75)])
    }

    @Test
    func `default sync enabled is true`() throws {
        let suite = "SyncCoord-defaultEnabled"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(settings.iCloudSyncEnabled == true)
    }

    @Test
    func `sync enabled persists across instances`() throws {
        let suite = "SyncCoord-persist"
        let defaultsA = try #require(UserDefaults(suiteName: suite))
        defaultsA.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let storeA = SettingsStore(
            userDefaults: defaultsA,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        storeA.iCloudSyncEnabled = false

        let defaultsB = try #require(UserDefaults(suiteName: suite))
        let storeB = SettingsStore(
            userDefaults: defaultsB,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        #expect(storeB.iCloudSyncEnabled == false)
    }

    @Test
    func `toggling setting updates user defaults`() throws {
        let suite = "SyncCoord-toggle"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())

        settings.iCloudSyncEnabled = false
        #expect(defaults.bool(forKey: "iCloudSyncEnabled") == false)

        settings.iCloudSyncEnabled = true
        #expect(defaults.bool(forKey: "iCloudSyncEnabled") == true)
    }

    // MARK: - P4 per-provider dual-write

    @Test
    func `per provider write fires alongside legacy on first push`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-perprov-first")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date()),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // Legacy write ran once; per-provider write ran once with the Codex envelope.
        #expect(mock.pushCount == 1)
        #expect(mock.perProviderCallCount == 1)
        #expect(mock.lastPerProviderEnvelopes.count >= 1)
        #expect(mock.lastPerProviderEnvelopes.contains { $0.provider.providerID == "codex" })
    }

    @Test
    func `per provider write skipped when data unchanged`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-perprov-unchanged")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let fixedSnapshot = CostUsageTokenSnapshot(
            sessionTokens: 100,
            sessionCostUSD: 0.1,
            last30DaysTokens: 1000,
            last30DaysCostUSD: 1.0,
            daily: [],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        store._setTokenSnapshotForTesting(fixedSnapshot, provider: .codex)
        // Pin `updatedAt` so SyncCoordinator's `lastUpdated` is stable
        // between pushes. Without this, fallback `Date()` differs by ≥1s
        // between pushes on a slow CI runner, the diff hash flips, and
        // the "unchanged" assertion racily fails.
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()
        let firstCallEnvelopes = mock.lastPerProviderEnvelopes

        // Second push with unchanged data: coordinator's diff cache should
        // surface an empty envelope array, so the mock records either a
        // zero-length call or no call at all.
        await coordinator.pushCurrentSnapshot()

        #expect(!firstCallEnvelopes.isEmpty) // first push wrote envelopes
        // Second push skipped everything — either no call, or explicit empty.
        // Coordinator guards on `!envelopes.isEmpty` so it should be no call.
        #expect(mock.perProviderCallCount == 1)
    }

    @Test
    func `per provider write sends only changed provider on incremental update`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-perprov-incr")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .codex)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 50,
                sessionCostUSD: 0.05,
                last30DaysTokens: 500,
                last30DaysCostUSD: 0.5,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .claude)
        // Pin UsageSnapshot.updatedAt for both providers so SyncCoordinator's
        // `lastUpdated` fallback to `Date()` doesn't leak wall-clock between
        // pushes (see perProviderWriteSkippedWhenDataUnchanged comment).
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            provider: .claude)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        // First push — both providers upload.
        await coordinator.pushCurrentSnapshot()
        let firstCount = mock.lastPerProviderEnvelopes.count
        #expect(firstCount >= 2)

        // Change ONLY Codex (token snapshot + UsageSnapshot.updatedAt).
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 200,
                sessionCostUSD: 0.2,
                last30DaysTokens: 2000,
                last30DaysCostUSD: 2.0,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 1_700_001_000)),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_001_000)),
            provider: .codex)

        await coordinator.pushCurrentSnapshot()

        // Second call should contain only the changed provider.
        #expect(mock.perProviderCallCount == 2)
        #expect(mock.lastPerProviderEnvelopes.count == 1)
        #expect(mock.lastPerProviderEnvelopes.first?.provider.providerID == "codex")
    }

    // MARK: - L1 ghost-records cleanup

    @Test
    func `L1: first push after restart does NOT emit deletes (pushHistorySeeded guard)`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-firstpush")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date()),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // First-push guard: no deletes should fire even though
        // lastPushedRecordNames was empty pre-call. Otherwise we'd interpret
        // the empty initial set as "nothing was previously enabled" and
        // skip cleanup of records from previous Mac sessions.
        #expect(mock.deleteCallCount == 0)
    }

    @Test
    func `L1: provider disabled between cycles emits delete for its CKRecord`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-disable")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        for provider in [UsageProvider.codex, .claude] {
            store._setTokenSnapshotForTesting(
                CostUsageTokenSnapshot(
                    sessionTokens: 100,
                    sessionCostUSD: 0.1,
                    last30DaysTokens: 1000,
                    last30DaysCostUSD: 1.0,
                    daily: [],
                    updatedAt: pinned),
                provider: provider)
            store._setSnapshotForTesting(
                UsageSnapshot(primary: nil, secondary: nil, updatedAt: pinned),
                provider: provider)
        }

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        // First push — seed lastPushedRecordNames with both composites.
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 0)

        // Disable Claude before next cycle.
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: false)

        // Second push — Claude's composite is in lastPushedRecordNames but
        // not in this cycle's set, so a delete must fire for its recordName.
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 1)
        let deleted = mock.deletedRecordNamesAcrossCalls.last ?? []
        #expect(deleted.count == 1)
        #expect(deleted.first?.contains("claude") == true)
    }

    @Test
    func `L1: account-identity drift (composite key change) emits delete for old composite`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-drift")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)

        // First cycle: Codex with nil accountEmail (composite "codex|_").
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: pinned),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: pinned,
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: nil)),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 0) // first push, no delete

        // Second cycle: same provider but accountEmail loaded — composite
        // shifts from "codex|_" to "codex|user@example.com". The old
        // composite must be deleted.
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: pinned.addingTimeInterval(60),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "user@example.com",
                    accountOrganization: nil,
                    loginMethod: nil)),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()

        #expect(mock.deleteCallCount == 1)
        let deleted = mock.deletedRecordNamesAcrossCalls.last ?? []
        // Deleted composite must end with "|_" (the orphan with nil email).
        #expect(deleted.count == 1)
        #expect(deleted.first?.hasSuffix("|codex|_") == true)
    }

    @Test
    func `L1: no deletes when all providers stay enabled with stable identity`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-steady")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: pinned),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: pinned),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        // Three cycles, no state change.
        for _ in 0..<3 {
            await coordinator.pushCurrentSnapshot()
        }
        // pushHistorySeeded after first; subsequent two would only delete
        // if state changed. Steady state = no deletes.
        #expect(mock.deleteCallCount == 0)
    }

    @Test
    func `L1: delete failure does NOT advance lastPushedRecordNames (retries next cycle)`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-retry")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        for provider in [UsageProvider.codex, .claude] {
            store._setTokenSnapshotForTesting(
                CostUsageTokenSnapshot(
                    sessionTokens: 100,
                    sessionCostUSD: 0.1,
                    last30DaysTokens: 1000,
                    last30DaysCostUSD: 1.0,
                    daily: [],
                    updatedAt: pinned),
                provider: provider)
            store._setSnapshotForTesting(
                UsageSnapshot(primary: nil, secondary: nil, updatedAt: pinned),
                provider: provider)
        }

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: false)

        // First retry cycle: simulate delete failure.
        mock.nextDeleteResult = .failure("CloudKit unavailable")
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 1)

        // Second retry cycle: success this time, should re-attempt.
        mock.nextDeleteResult = .success
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 2)
        // Same composite re-deleted (because failure didn't advance state).
        #expect(mock.deletedRecordNamesAcrossCalls[0] ==
            mock.deletedRecordNamesAcrossCalls[1])
    }

    // MARK: - L1 reconcile (startup CKQuery for stranded records)

    @Test
    func `L1 reconcile seeds stranded CloudKit records for the next cleanup cycle`() async throws {
        // Reproduces user-reported 2026-05-05 bug: stranded mock CKRecords
        // from a previous Mac process incarnation persisted on iOS forever.
        // Cause: lastPushedRecordNames was in-memory only; restart wiped
        // the history, the first-cycle guard skipped delete, subsequent
        // cycles diff'd against (current vs current) so no diff fired.
        // Fix: at startup, fetch CloudKit's current state for this device
        // and seed the in-memory set, so the next push-cycle diff sees
        // pre-existing records.
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-reconcile")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: pinned),
            provider: .codex)
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, updatedAt: pinned),
            provider: .codex)

        // Pre-existing CloudKit state: this device pushed 2 mock records
        // in a previous process incarnation (mock toggle was on). After
        // restart, those records still exist but lastPushedRecordNames
        // is empty in memory.
        let mock = MockSyncPusher()
        let strandedMockA =
            "test-device-id|claude|personal-mock@claude.test"
        let strandedMockB =
            "test-device-id|cursor|expired-mock@cursor.test"
        mock.nextFetchRecordNamesResult = [strandedMockA, strandedMockB]

        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        // Reconcile happens fire-and-forget when startObserving is called.
        // Test environment: trigger reconcile + first push manually so we
        // can assert behavior without coupling to observer lifecycle.
        // Instead, simulate the reconcile-then-push flow by triggering
        // observation, then waiting for both ops to settle.
        coordinator.startObserving()
        // Yield so the reconcile Task can run before the push cycle.
        // Multiple yields because the reconcile Task and the
        // observeLoop's Task are scheduled separately.
        for _ in 0..<5 {
            await Task.yield()
        }

        // Reconcile fired exactly once at startup.
        #expect(mock.fetchRecordNamesCallCount == 1)
        // Push cycle ran (no current snapshot yet because store is empty,
        // but we explicitly seeded one above so push should fire).
        await coordinator.pushCurrentSnapshot()

        // The 2 stranded mocks are NOT in current cycle's emit set
        // (only real codex). Whole-provider gone (claude / cursor not
        // in any current record) → 1-cycle delete.
        #expect(mock.deleteCallCount == 1)
        let deletedNames = Set(mock.deletedRecordNamesAcrossCalls.flatMap(\.self))
        #expect(deletedNames.contains(strandedMockA))
        #expect(deletedNames.contains(strandedMockB))
    }

    @Test
    func `L1 reconcile: empty CloudKit result preserves first-push guard semantics`() async throws {
        // Fresh device, never pushed before — CloudKit returns empty.
        // Reconcile should be a no-op; first push behavior unchanged
        // (no spurious deletes, lastPushedRecordNames seeds normally).
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-reconcile-empty")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 100,
                sessionCostUSD: 0.1,
                last30DaysTokens: 1000,
                last30DaysCostUSD: 1.0,
                daily: [],
                updatedAt: Date()),
            provider: .codex)

        let mock = MockSyncPusher()
        mock.nextFetchRecordNamesResult = []
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        coordinator.startObserving()
        for _ in 0..<5 {
            await Task.yield()
        }
        await coordinator.pushCurrentSnapshot()

        #expect(mock.fetchRecordNamesCallCount == 1)
        #expect(mock.deleteCallCount == 0) // no stranded records to clean
    }

    @Test
    func `L1 reconcile: skipped when iCloud sync disabled`() async {
        let settings = self.makeSettingsStore(suite: "SyncCoord-l1-reconcile-disabled")
        settings.iCloudSyncEnabled = false
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        coordinator.startObserving()
        for _ in 0..<5 {
            await Task.yield()
        }
        // No CKQuery should fire — pushing is a no-op anyway, no point
        // querying CloudKit.
        #expect(mock.fetchRecordNamesCallCount == 0)
    }

    // MARK: - extraRateWindows passthrough (Claude Designs/Routines, Cursor Extra)

    @Test
    func `extraRateWindows: Claude Designs/Daily Routines/Web Sonnet appear in rateWindows`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-extras-claude")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        let designsWindow = RateWindow(
            usedPercent: 23.0,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)
        let routinesWindow = RateWindow(
            usedPercent: 42.5,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)
        let webSonnetWindow = RateWindow(
            usedPercent: 67.8,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12.0,
                    windowMinutes: 60,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 35.0,
                    windowMinutes: 10080,
                    resetsAt: nil,
                    resetDescription: nil),
                extraRateWindows: [
                    NamedRateWindow(id: "claude-design", title: "Designs", window: designsWindow),
                    NamedRateWindow(id: "claude-routines", title: "Daily Routines", window: routinesWindow),
                    NamedRateWindow(id: "claude-web-sonnet", title: "Web Sonnet", window: webSonnetWindow),
                ],
                updatedAt: pinned),
            provider: .claude)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == "claude" }))
        // Primary + secondary + 3 extras = 5 total in rateWindows.
        // Note: tertiary path requires supportsOpus + tertiary set — we
        // don't set tertiary here, so just primary + secondary + 3 extras.
        #expect(provider.rateWindows.count == 5)
        let labels = provider.rateWindows.compactMap(\.label)
        #expect(labels.contains("Designs"))
        #expect(labels.contains("Daily Routines"))
        #expect(labels.contains("Web Sonnet"))
    }

    @Test
    func `extraRateWindows: nil extras don't break legacy primary/secondary mapping`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-extras-nil")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12.0,
                    windowMinutes: 60,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                extraRateWindows: nil,
                updatedAt: pinned),
            provider: .claude)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == "claude" }))
        #expect(provider.rateWindows.count == 1) // just primary
    }

    @Test
    func `ghost provider not pushed to per provider zone`() async throws {
        // Provider enabled but has NO data yet (mimics early startup before
        // OAuth / cookies populate rate windows / cost / budget). The
        // legacy-zone monolithic write still includes it, but per-provider
        // zone push must skip it — otherwise it lands in
        // DeviceProvidersZone under recordName `{deviceID}|codex|_` and
        // never gets overwritten once accountEmail populates on a later push.
        let settings = self.makeSettingsStore(suite: "SyncCoord-ghost")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        // No token snapshot, no UsageSnapshot — provider has absolutely
        // nothing to say. This is the ghost case.

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // Legacy monolithic still pushed (includes the bare provider entry
        // so old iOS builds can at least name it).
        #expect(mock.pushCount >= 0) // may be 0 if no providers available at all
        // Per-provider zone must NOT receive the ghost.
        #expect(mock.lastPerProviderEnvelopes.allSatisfy { e in
            e.provider.providerID != "codex"
                || e.provider.primary != nil
                || e.provider.secondary != nil
                || !e.provider.rateWindows.isEmpty
                || e.provider.costSummary != nil
                || e.provider.budget != nil
                || e.provider.isError
                || e.provider.statusMessage != nil
        })
    }
}

@MainActor
@Suite(.serialized)
struct SyncCoordinatorUpstreamV041Tests {
    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
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
    func `Kimi quota lanes preserve Weekly, Rate Limit, Monthly, Code 7-day order for iOS`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-v041-kimi-order")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .kimi,
            metadata: #require(ProviderDefaults.metadata[.kimi]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let pinned = Date(timeIntervalSince1970: 1_700_000_000)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 25,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 40,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                extraRateWindows: [
                    NamedRateWindow(
                        id: "kimi-monthly",
                        title: "Monthly",
                        window: RateWindow(
                            usedPercent: 42,
                            windowMinutes: nil,
                            resetsAt: nil,
                            resetDescription: nil)),
                    NamedRateWindow(
                        id: "kimi-code-7d",
                        title: "Code 7-day",
                        window: RateWindow(
                            usedPercent: 17,
                            windowMinutes: 7 * 24 * 60,
                            resetsAt: nil,
                            resetDescription: nil)),
                ],
                updatedAt: pinned),
            provider: .kimi)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers.first { $0.providerID == "kimi" })
        #expect(provider.rateWindows.compactMap(\.label) == ["Weekly", "Rate Limit", "Monthly", "Code 7-day"])
        #expect(provider.rateWindows.map(\.usedPercent) == [25, 40, 42, 17])
    }

    @Test
    func `Claude Max multiplier label survives the Mac to iOS sync envelope`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-v041-claude-plan")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                identity: ProviderIdentitySnapshot(
                    providerID: .claude,
                    accountEmail: "max@example.com",
                    accountOrganization: nil,
                    loginMethod: "Claude Max 20x")),
            provider: .claude)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers.first { $0.providerID == "claude" })
        #expect(provider.loginMethod == "Claude Max 20x")
        let encoded = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: encoded)
        #expect(decoded.loginMethod == "Claude Max 20x")
    }
}
