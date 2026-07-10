// swiftlint:disable multiline_arguments
import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// End-to-end integration tests for Codex multi-account sync (R5 / R1).
///
/// These tests exercise the full Mac-side pipeline:
/// `settings.codexAccountReconciliationSnapshot` (driven by a real
/// `FileManagedCodexAccountStore` JSON file via the `_test_*` overrides) →
/// `SyncCoordinator.captureAndExpandMultiAccountSnapshots` → multi-account
/// emission → `MockSyncPusher` capture for assertion.
///
/// Each test simulates a sequence of "user uses account A, then switches to
/// B, then C" by mutating `codexActiveSource` and `_setSnapshotForTesting`
/// between pushes — the cache should naturally fill up over the session, and
/// every cycle's push should emit one CKRecord per known account (live +
/// cached). This is the closest we can get to user acceptance testing
/// without three real Codex accounts on a real Mac.
///
/// See `Research/020-multi-account-comprehensive.md` R5 §A.
@MainActor
@Suite(.serialized)
struct SyncCodexMultiAccountIntegrationTests {
    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        // Reset mock-provider state — see same comment in
        // SyncMultiAccountEdgeCasesTests.makeSettingsStore.
        UserDefaults.standard.removeObject(
            forKey: MockProviderInjector.userDefaultsKey)
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

    private func makeManagedAccount(
        email: String,
        homeSuffix: String) -> ManagedCodexAccount
    {
        ManagedCodexAccount(
            id: UUID(),
            email: email,
            managedHomePath: "/tmp/codex-test-home/\(homeSuffix)",
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_000,
            lastAuthenticatedAt: 1_700_000_000)
    }

    private func writeManagedAccounts(
        _ accounts: [ManagedCodexAccount]) throws -> URL
    {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-multi-\(UUID().uuidString).json")
        let store = FileManagedCodexAccountStore(fileURL: storeURL)
        try store.storeAccounts(ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: accounts))
        return storeURL
    }

    private func makeCodexUsageSnapshot(
        for account: ManagedCodexAccount,
        usedPercent: Double = 25.0) -> UsageSnapshot
    {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(3600),
                resetDescription: "in 1 hour"),
            secondary: nil,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: account.email,
                accountOrganization: account.providerAccountID,
                loginMethod: "managed-account"))
    }

    private func setupCoordinator(
        suite: String,
        managedAccounts: [ManagedCodexAccount]) throws
        -> (SettingsStore, UsageStore, MockSyncPusher, SyncCoordinator)
    {
        let settings = self.makeSettingsStore(suite: suite)
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let storeURL = try self.writeManagedAccounts(managedAccounts)
        settings._test_managedCodexAccountStoreURL = storeURL

        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        return (settings, store, mock, coordinator)
    }

    // MARK: - Core scenario: 3 accounts, sequential switch

    @Test
    func `R5 A1: switching between 3 Codex managed accounts fills cache and emits all 3`() async throws {
        let alice = self.makeManagedAccount(email: "alice@example.com", homeSuffix: "alice")
        let bob = self.makeManagedAccount(email: "bob@example.com", homeSuffix: "bob")
        let carol = self.makeManagedAccount(email: "carol@example.com", homeSuffix: "carol")
        let (settings, store, mock, coordinator) = try self.setupCoordinator(
            suite: "R5A1-Sequential",
            managedAccounts: [alice, bob, carol])

        // Cycle 1: active = Alice. Cache cold start — only Alice emitted.
        settings.codexActiveSource = .managedAccount(id: alice.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: alice, usedPercent: 10),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()
        let cycle1 = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(cycle1.count == 1, "cold start: only active account emitted")
        #expect(cycle1.first?.accountEmail == "alice@example.com")

        // Cycle 2: active = Bob. Cache now has Alice. Push emits Alice + Bob.
        settings.codexActiveSource = .managedAccount(id: bob.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: bob, usedPercent: 50),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()
        let cycle2 = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(cycle2.count == 2, "after switching to Bob, both Alice (cached) and Bob (active) emit")
        let cycle2Emails = Set(cycle2.compactMap(\.accountEmail))
        #expect(cycle2Emails == ["alice@example.com", "bob@example.com"])

        // Cycle 3: active = Carol. Cache has Alice + Bob. Push emits all 3.
        settings.codexActiveSource = .managedAccount(id: carol.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: carol, usedPercent: 80),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()
        let cycle3 = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(
            cycle3.count == 3,
            "after switching to Carol, all 3 Codex accounts (Alice cached, Bob cached, Carol active) emit")
        let cycle3Emails = Set(cycle3.compactMap(\.accountEmail))
        #expect(
            cycle3Emails == ["alice@example.com", "bob@example.com", "carol@example.com"],
            "every account's email preserved through cache")

        // Per-account distinct usedPercent preserved (proves cache stored
        // real per-account data, not duplicated active).
        let percents = Set(cycle3.compactMap(\.primary?.usedPercent))
        #expect(percents == [10, 50, 80])
    }

    // MARK: - Active source = .liveSystem

    @Test
    func `R5 A2: liveSystem active source does NOT trigger multi-account expansion`() async throws {
        let alice = self.makeManagedAccount(email: "alice@example.com", homeSuffix: "alice")
        let bob = self.makeManagedAccount(email: "bob@example.com", homeSuffix: "bob")
        let (settings, store, mock, coordinator) = try self.setupCoordinator(
            suite: "R5A2-LiveSystem",
            managedAccounts: [alice, bob])

        // .liveSystem means the running ~/.codex install — distinct concept
        // from the managed-account list. Even with 2 stored managed
        // accounts, expansion should not run when active source is
        // .liveSystem (no `activeStoredAccount` matches).
        settings.codexActiveSource = .liveSystem
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: alice, usedPercent: 25),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()
        let cycle1 = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(
            cycle1.count == 1,
            ".liveSystem active source means only the live snapshot emits, no expansion")
    }

    // MARK: - Account removal

    @Test
    func `R5 A3: removing managed account from store purges cache + immediate delete`() async throws {
        let alice = self.makeManagedAccount(email: "alice@example.com", homeSuffix: "alice")
        let bob = self.makeManagedAccount(email: "bob@example.com", homeSuffix: "bob")
        let (settings, store, mock, coordinator) = try self.setupCoordinator(
            suite: "R5A3-Removal",
            managedAccounts: [alice, bob])

        // Cycle 1: Alice active. Cache empty → 1 emit.
        settings.codexActiveSource = .managedAccount(id: alice.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: alice), provider: .codex)
        await coordinator.pushCurrentSnapshot()

        // Cycle 2: switch to Bob. Cache now has Alice → 2 emit.
        settings.codexActiveSource = .managedAccount(id: bob.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: bob), provider: .codex)
        await coordinator.pushCurrentSnapshot()
        #expect(mock.lastSnapshot?.providers.count(where: { $0.providerID == "codex" }) == 2)

        // Cycle 3: user removes Alice from settings. Replace store URL with
        // a new one that has only Bob.
        let newStoreURL = try self.writeManagedAccounts([bob])
        settings._test_managedCodexAccountStoreURL = newStoreURL
        // Bob still active — same snapshot.
        await coordinator.pushCurrentSnapshot()
        let cycle3 = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(cycle3.count == 1, "after removing Alice, only Bob remains")
        #expect(cycle3.first?.accountEmail == "bob@example.com")
        // Codex providerID is still in the emit set so this is a "real
        // shrink" → 2-cycle confirmation deferral. NO immediate delete.
        let initialDeletes = mock.deleteCallCount

        // Cycle 4: still only Bob. 2-cycle threshold → Alice's record
        // gets confirmed-deleted from CloudKit.
        await coordinator.pushCurrentSnapshot()
        #expect(
            mock.deleteCallCount > initialDeletes,
            "Alice's record should be deleted after 2 cycles missing")
        let lastDeletes = mock.deletedRecordNamesAcrossCalls.last ?? []
        #expect(lastDeletes.contains { $0.contains("alice@example.com") })
    }

    // MARK: - Non-ASCII email

    @Test
    func `R5 A4: managed account with non-ASCII email pushes correctly`() async throws {
        // Codex MCP review noted that accountIdentities normalization
        // (Research/019) mirrors iOS for non-ASCII emails. Here we
        // verify Mac-side push doesn't choke on it.
        let cafe = self.makeManagedAccount(
            email: "café@münich.example.com",
            homeSuffix: "cafe")
        let (settings, store, mock, coordinator) = try self.setupCoordinator(
            suite: "R5A4-NonASCII",
            managedAccounts: [cafe])

        settings.codexActiveSource = .managedAccount(id: cafe.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: cafe), provider: .codex)
        await coordinator.pushCurrentSnapshot()

        let cycle1 = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(cycle1.count == 1)
        #expect(cycle1.first?.accountEmail?.contains("café") == true)
        // accountIdentities should be populated for non-ASCII via NFC +
        // percent-encoding normalization.
        let identities = cycle1.first?.accountIdentities ?? []
        #expect(
            identities.contains(where: { $0.hasPrefix("codex:email:") }),
            "non-ASCII email should be normalized into codex:email:<encoded>")
    }

    // MARK: - Active-account switch race (P2.1 ghost guard)

    @Test
    func `R5 A5: active-account switch with ghost snapshot does NOT pollute cache`() async throws {
        // Reproduces the race window described in Research/020 H7:
        // user switches account A → B; `prepareCodexAccountScopedRefreshIfNeeded`
        // wipes snapshots[.codex]; observation triggers push BEFORE B's
        // refresh completes; main loop builds a ghost snapshot for the
        // codex provider. Without R3 P2.1 guard, the ghost would be
        // recorded into cache as B's data, polluting future emits.
        let alice = self.makeManagedAccount(email: "alice@example.com", homeSuffix: "alice")
        let bob = self.makeManagedAccount(email: "bob@example.com", homeSuffix: "bob")
        let (settings, store, mock, coordinator) = try self.setupCoordinator(
            suite: "R5A5-GhostRace",
            managedAccounts: [alice, bob])

        // Cycle 1: Alice active with real data.
        settings.codexActiveSource = .managedAccount(id: alice.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: alice, usedPercent: 35),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()

        // Cycle 2: simulate the race window — switch to Bob but
        // snapshots[.codex] hasn't been refilled yet (ghost state).
        settings.codexActiveSource = .managedAccount(id: bob.id)
        store._setSnapshotForTesting(nil, provider: .codex) // wipe = ghost
        await coordinator.pushCurrentSnapshot()

        // Cycle 3: refresh completes — Bob's real data lands.
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: bob, usedPercent: 70),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()
        let cycle3 = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(cycle3.count == 2, "both Alice (cached, real) and Bob (active, real) emit")
        // Verify cached Alice still has her ORIGINAL usedPercent (35),
        // NOT the ghost's nil/0 — proves cache stayed clean across the
        // race window.
        let aliceEmit = cycle3.first { $0.accountEmail == "alice@example.com" }
        #expect(
            aliceEmit?.primary?.usedPercent == 35,
            "Alice's cached snapshot should retain original (35) — not overwritten by ghost during Bob switch")
        let bobEmit = cycle3.first { $0.accountEmail == "bob@example.com" }
        #expect(bobEmit?.primary?.usedPercent == 70, "Bob's freshly-refreshed data emits")
    }

    // MARK: - 0 / 1 managed accounts edge cases

    @Test
    func `R5 A6: 0 stored accounts → no expansion, falls through to active path`() async throws {
        let (settings, store, mock, coordinator) = try self.setupCoordinator(
            suite: "R5A6-Empty",
            managedAccounts: [])

        settings.codexActiveSource = .liveSystem
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 50, windowMinutes: 300,
                    resetsAt: Date(), resetDescription: "now"),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "live@example.com",
                    accountOrganization: nil,
                    loginMethod: "live-system")),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()
        let cycle1 = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(cycle1.count == 1)
    }

    @Test
    func `R5 A7: 1 stored account = single-account behavior, no expansion`() async throws {
        let alice = self.makeManagedAccount(email: "alice@example.com", homeSuffix: "alice")
        let (settings, store, mock, coordinator) = try self.setupCoordinator(
            suite: "R5A7-Single",
            managedAccounts: [alice])

        settings.codexActiveSource = .managedAccount(id: alice.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: alice), provider: .codex)
        await coordinator.pushCurrentSnapshot()
        let cycle1 = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(cycle1.count == 1)
    }

    // MARK: - Cache size up to 5 accounts

    @Test
    func `R5 A8: 5 managed accounts all become visible after rotating through`() async throws {
        let accounts = (1...5).map { i in
            self.makeManagedAccount(
                email: "user\(i)@example.com", homeSuffix: "u\(i)")
        }
        let (settings, store, mock, coordinator) = try self.setupCoordinator(
            suite: "R5A8-Five",
            managedAccounts: accounts)

        // Rotate through all 5, simulating user clicking each one.
        for (index, account) in accounts.enumerated() {
            settings.codexActiveSource = .managedAccount(id: account.id)
            store._setSnapshotForTesting(
                self.makeCodexUsageSnapshot(
                    for: account,
                    usedPercent: Double(index + 1) * 10),
                provider: .codex)
            await coordinator.pushCurrentSnapshot()
        }

        // After rotating through all 5, the last push should emit all 5.
        let last = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(last.count == 5, "all 5 accounts visible after each was active once")
        let emails = Set(last.compactMap(\.accountEmail))
        #expect(
            emails == [
                "user1@example.com", "user2@example.com", "user3@example.com",
                "user4@example.com", "user5@example.com",
            ])
    }

    // MARK: - Active source switching back to previously-cached account

    @Test
    func `R5 A9: switching back to previously-active account refreshes cached entry`() async throws {
        let alice = self.makeManagedAccount(email: "alice@example.com", homeSuffix: "alice")
        let bob = self.makeManagedAccount(email: "bob@example.com", homeSuffix: "bob")
        let (settings, store, mock, coordinator) = try self.setupCoordinator(
            suite: "R5A9-SwitchBack",
            managedAccounts: [alice, bob])

        // Cycle 1: Alice active, usedPercent=10.
        settings.codexActiveSource = .managedAccount(id: alice.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: alice, usedPercent: 10),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()

        // Cycle 2: Bob active. Alice cached at usedPercent=10.
        settings.codexActiveSource = .managedAccount(id: bob.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: bob, usedPercent: 50),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()

        // Cycle 3: switch BACK to Alice with refreshed data (usedPercent=30).
        settings.codexActiveSource = .managedAccount(id: alice.id)
        store._setSnapshotForTesting(
            self.makeCodexUsageSnapshot(for: alice, usedPercent: 30),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()

        let cycle3 = mock.lastSnapshot?.providers.filter { $0.providerID == "codex" } ?? []
        #expect(cycle3.count == 2)
        let aliceEmit = cycle3.first { $0.accountEmail == "alice@example.com" }
        #expect(aliceEmit?.primary?.usedPercent == 30, "Alice's data refreshed when she became active again")
        let bobEmit = cycle3.first { $0.accountEmail == "bob@example.com" }
        #expect(bobEmit?.primary?.usedPercent == 50, "Bob's data preserved in cache from cycle 2")
    }
}

// swiftlint:enable multiline_arguments
