// swiftlint:disable multiline_arguments
import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// Integration tests for SyncCoordinator's multi-account expansion (R2 in
/// `Research/020-multi-account-comprehensive.md`). Verifies that when a
/// token-based provider has 2+ token accounts active in
/// `UsageStore.accountSnapshots`, SyncCoordinator emits one ProviderUsageSnapshot
/// per account on push.
///
/// Codex multi-account uses a different mechanism (observation-cache) and
/// requires a full ManagedCodexAccount fixture to test end-to-end — that's
/// covered in R3 with virtual machine integration.
@MainActor
@Suite(.serialized)
struct SyncCoordinatorMultiAccountTests {
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

    private func makeTokenAccount(
        label: String,
        token: String) -> ProviderTokenAccount
    {
        ProviderTokenAccount(
            id: UUID(),
            label: label,
            token: token,
            addedAt: Date().timeIntervalSince1970,
            lastUsed: nil)
    }

    private func makeUsageSnapshot(
        provider: UsageProvider,
        accountEmail: String,
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
                providerID: provider,
                accountEmail: accountEmail,
                accountOrganization: nil,
                loginMethod: "oauth"))
    }

    private func makeTokenAccountUsageSnapshot(
        provider: UsageProvider,
        accountLabel: String,
        accountEmail: String,
        usedPercent: Double = 25.0) -> TokenAccountUsageSnapshot
    {
        TokenAccountUsageSnapshot(
            account: self.makeTokenAccount(
                label: accountLabel, token: "tok-\(accountLabel)"),
            snapshot: self.makeUsageSnapshot(
                provider: provider,
                accountEmail: accountEmail,
                usedPercent: usedPercent),
            error: nil,
            sourceLabel: nil)
    }

    @Test
    func `token provider multi account emits all accounts`() async throws {
        let settings = self.makeSettingsStore(
            suite: "TokenMulti-Claude-Emit")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "alice", accountEmail: "alice@example.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "bob", accountEmail: "bob@example.com")

        // Active account snapshot (main loop input)
        store._setSnapshotForTesting(alice.snapshot, provider: .claude)
        // Full per-account list (multi-account expansion input)
        store.accountSnapshots[.claude] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let claudeSnapshots =
            mock.lastSnapshot?.providers.filter { $0.providerID == "claude" } ?? []
        #expect(claudeSnapshots.count == 2)
        let emails = Set(claudeSnapshots.compactMap(\.accountEmail))
        #expect(emails == ["alice@example.com", "bob@example.com"])
    }

    @Test
    func `token provider empty account snapshots keeps active only`() async throws {
        // accountSnapshots[.claude] not set → expansion skips → main loop's
        // single (active) snapshot is the only Claude record emitted.
        let settings = self.makeSettingsStore(suite: "TokenMulti-Claude-Empty")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let activeSnap = self.makeUsageSnapshot(
            provider: .claude, accountEmail: "active@example.com")
        store._setSnapshotForTesting(activeSnap, provider: .claude)
        // Don't populate accountSnapshots[.claude]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let claudeSnapshots =
            mock.lastSnapshot?.providers.filter { $0.providerID == "claude" } ?? []
        #expect(claudeSnapshots.count == 1)
        #expect(claudeSnapshots.first?.accountEmail == "active@example.com")
    }

    @Test
    func `token provider single entry account snapshots keeps active only`() async throws {
        // accountSnapshots[.claude] has only 1 entry → expansion skips
        // (count < 2) → main loop's single snapshot remains.
        let settings = self.makeSettingsStore(
            suite: "TokenMulti-Claude-Single")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let solo = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "solo", accountEmail: "solo@example.com")
        store._setSnapshotForTesting(solo.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [solo]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let claudeSnapshots =
            mock.lastSnapshot?.providers.filter { $0.providerID == "claude" } ?? []
        #expect(claudeSnapshots.count == 1)
        #expect(claudeSnapshots.first?.accountEmail == "solo@example.com")
    }

    @Test
    func `token provider three accounts all emit distinct emails`() async throws {
        let settings = self.makeSettingsStore(suite: "TokenMulti-Claude-Three")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "alice", accountEmail: "alice@example.com",
            usedPercent: 10)
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "bob", accountEmail: "bob@example.com",
            usedPercent: 50)
        let carol = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "carol", accountEmail: "carol@example.com",
            usedPercent: 90)
        store._setSnapshotForTesting(bob.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [alice, bob, carol]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let claudeSnapshots =
            mock.lastSnapshot?.providers.filter { $0.providerID == "claude" } ?? []
        #expect(claudeSnapshots.count == 3)
        let emails = Set(claudeSnapshots.compactMap(\.accountEmail))
        #expect(emails == [
            "alice@example.com", "bob@example.com", "carol@example.com",
        ])
        // Each account preserves its own usedPercent (verified via primary
        // window — proves we're building per-account, not duplicating).
        let percents = Set(claudeSnapshots.compactMap(\.primary?.usedPercent))
        #expect(percents == [10, 50, 90])
    }

    @Test
    func `multiple token providers multi account expand independently`() async throws {
        // Both Claude and Cursor have 2 token accounts each → expansion
        // produces 2+2 = 4 records total (no cross-provider mixing).
        let settings = self.makeSettingsStore(
            suite: "TokenMulti-MultiProv")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        try settings.setProviderEnabled(
            provider: .cursor,
            metadata: #require(ProviderDefaults.metadata[.cursor]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let claudeAlice = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "claude-alice",
            accountEmail: "alice@anthropic.com")
        let claudeBob = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "claude-bob",
            accountEmail: "bob@anthropic.com")
        let cursorCarol = self.makeTokenAccountUsageSnapshot(
            provider: .cursor,
            accountLabel: "cursor-carol",
            accountEmail: "carol@cursor.sh")
        let cursorDave = self.makeTokenAccountUsageSnapshot(
            provider: .cursor,
            accountLabel: "cursor-dave",
            accountEmail: "dave@cursor.sh")
        store._setSnapshotForTesting(
            claudeAlice.snapshot, provider: .claude)
        store._setSnapshotForTesting(
            cursorCarol.snapshot, provider: .cursor)
        store.accountSnapshots[.claude] = [claudeAlice, claudeBob]
        store.accountSnapshots[.cursor] = [cursorCarol, cursorDave]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let claudes = mock.lastSnapshot?.providers
            .filter { $0.providerID == "claude" } ?? []
        let cursors = mock.lastSnapshot?.providers
            .filter { $0.providerID == "cursor" } ?? []
        #expect(claudes.count == 2)
        #expect(cursors.count == 2)
        let claudeEmails = Set(claudes.compactMap(\.accountEmail))
        let cursorEmails = Set(cursors.compactMap(\.accountEmail))
        #expect(claudeEmails == ["alice@anthropic.com", "bob@anthropic.com"])
        #expect(cursorEmails == ["carol@cursor.sh", "dave@cursor.sh"])
    }

    @Test
    func `token provider multi account preserves per account identity`() async throws {
        // Each emitted ProviderUsageSnapshot must carry the correct
        // accountIdentities for cross-Mac union-find merging on iOS.
        // Claude is a Tier-A provider, so accountIdentities should contain
        // `claude:email:<email>` for each account.
        let settings = self.makeSettingsStore(suite: "TokenMulti-Identity")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "alice", accountEmail: "alice@example.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "bob", accountEmail: "bob@example.com")
        store._setSnapshotForTesting(alice.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let claudeSnapshots =
            mock.lastSnapshot?.providers.filter { $0.providerID == "claude" } ?? []
        #expect(claudeSnapshots.count == 2)

        // Each snapshot's accountIdentities must contain its own email key —
        // not Alice's identifiers on Bob's snapshot or vice-versa.
        for snap in claudeSnapshots {
            let identities = snap.accountIdentities ?? []
            guard let email = snap.accountEmail else {
                Issue.record("snapshot has nil email")
                continue
            }
            let expectedEmailKey = "claude:email:\(email)"
            #expect(
                identities.contains(expectedEmailKey),
                "snapshot for \(email) missing self-key in accountIdentities")
        }
    }

    @Test
    func `non token provider unaffected by multi account changes`() async throws {
        // .gemini is not in `tokenBasedMultiAccountProviders` — even if some
        // bug populates accountSnapshots[.gemini], expansion must skip it.
        let settings = self.makeSettingsStore(suite: "TokenMulti-Gemini")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .gemini,
            metadata: #require(ProviderDefaults.metadata[.gemini]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let activeSnap = self.makeUsageSnapshot(
            provider: .gemini, accountEmail: "primary@google.com")
        store._setSnapshotForTesting(activeSnap, provider: .gemini)
        // Hypothetically populate accountSnapshots[.gemini] — should be
        // ignored because Gemini isn't in the multi-account allowlist.
        let phantom = self.makeTokenAccountUsageSnapshot(
            provider: .gemini,
            accountLabel: "phantom", accountEmail: "phantom@google.com")
        store.accountSnapshots[.gemini] = [
            phantom,
            self.makeTokenAccountUsageSnapshot(
                provider: .gemini,
                accountLabel: "phantom2",
                accountEmail: "phantom2@google.com"),
        ]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let geminis =
            mock.lastSnapshot?.providers.filter { $0.providerID == "gemini" } ?? []
        #expect(geminis.count == 1)
        #expect(geminis.first?.accountEmail == "primary@google.com")
    }

    @Test
    func `composite record names distinct across multi account`() async throws {
        // Per-provider zone CKRecords are keyed by
        // `{deviceID}|{providerID}|{accountEmail}`. With 2 emails, the 2
        // records must have distinct recordNames so CloudKit doesn't
        // overwrite one with the other.
        let settings = self.makeSettingsStore(suite: "TokenMulti-RecordNames")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "alice", accountEmail: "alice@example.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "bob", accountEmail: "bob@example.com")
        store._setSnapshotForTesting(alice.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        // Two per-provider envelopes pushed — both with distinct composite
        // record names (different accountEmail).
        let envelopes = mock.lastPerProviderEnvelopes
            .filter { $0.provider.providerID == "claude" }
        #expect(envelopes.count == 2)
        let recordNames = envelopes.map { envelope in
            CloudSyncManager.perProviderRecordName(
                deviceID: envelope.deviceID,
                providerID: envelope.provider.providerID,
                accountEmail: envelope.provider.accountEmail)
        }
        #expect(
            Set(recordNames).count == 2,
            "two per-account claude records must have distinct CK record names")
    }

    // MARK: - R3 P1+P2 edge case tests

    @Test
    func `R3 P1: disabled provider + populated accountSnapshots does NOT leak records`() async throws {
        // Reproduces Codex MCP review's P1: if a provider is DISABLED in
        // settings but `accountSnapshots[.claude]` still contains stale
        // entries (e.g., user just toggled it off but the dict hasn't been
        // cleared yet), expansion must skip the provider entirely. No
        // CKRecord may be emitted for a disabled provider.
        let settings = self.makeSettingsStore(suite: "R3P1-Disabled-Leak")
        settings.iCloudSyncEnabled = true
        // Codex enabled (so push has at least one provider, otherwise
        // pushCurrentSnapshot early-returns on empty enabledProviders).
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        // Claude DISABLED.
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: false)

        let store = self.makeUsageStore(settings: settings)
        // Populate stale token-account data for the DISABLED provider.
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "alice", accountEmail: "alice@anthropic.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "bob", accountEmail: "bob@anthropic.com")
        store.accountSnapshots[.claude] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        await coordinator.pushCurrentSnapshot()

        let claudes =
            mock.lastSnapshot?.providers.filter { $0.providerID == "claude" } ?? []
        #expect(
            claudes.isEmpty,
            "disabled provider must not emit ANY records, even with stale accountSnapshots data")
    }

    @Test
    func `R3 P1: partial shrink (cache temp empty) does NOT trigger spurious delete on cycle 2`() async throws {
        // Cycle 1: emits Alice + Bob via accountSnapshots. lastPushedRecordNames seeded.
        // Cycle 2: accountSnapshots cleared (transient). Only Alice (active)
        //   emitted. The delete cycle MUST NOT fire for Bob because the
        //   provider (claude) is still present — partial shrink, 2-cycle
        //   confirmation required.
        let settings = self.makeSettingsStore(suite: "R3P1-PartialShrink")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "alice", accountEmail: "alice@anthropic.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "bob", accountEmail: "bob@anthropic.com")
        store._setSnapshotForTesting(alice.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        // Cycle 1: pushes Alice + Bob.
        await coordinator.pushCurrentSnapshot()
        let cycle1Claudes =
            mock.lastSnapshot?.providers.filter { $0.providerID == "claude" } ?? []
        #expect(cycle1Claudes.count == 2, "cycle 1 should emit both Alice and Bob")
        #expect(mock.deleteCallCount == 0, "first push never emits deletes")

        // Cycle 2: simulate transient shrink — accountSnapshots cleared but
        // active snapshot still in place.
        store.accountSnapshots.removeValue(forKey: .claude)
        await coordinator.pushCurrentSnapshot()
        let cycle2Claudes =
            mock.lastSnapshot?.providers.filter { $0.providerID == "claude" } ?? []
        #expect(cycle2Claudes.count == 1, "cycle 2 emits only active (cache empty)")
        #expect(
            mock.deleteCallCount == 0,
            "partial shrink must NOT trigger delete on first missing cycle")
    }

    @Test
    func `R3 P1: partial shrink confirmed after 2 missing cycles emits delete`() async throws {
        // Cycle 1: emits Alice + Bob.
        // Cycle 2: shrunk to Alice only — counter[Bob]=1, no delete.
        // Cycle 3: still Alice only — counter[Bob]=2, delete fires.
        let settings = self.makeSettingsStore(suite: "R3P1-PartialShrinkConfirm")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "alice", accountEmail: "alice@anthropic.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            accountLabel: "bob", accountEmail: "bob@anthropic.com")
        store._setSnapshotForTesting(alice.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        // Cycle 1.
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 0)

        // Cycle 2 — shrink.
        store.accountSnapshots.removeValue(forKey: .claude)
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 0, "2nd cycle: still grace period")

        // Cycle 3 — still shrunk.
        await coordinator.pushCurrentSnapshot()
        #expect(mock.deleteCallCount == 1, "3rd cycle: 2-cycle threshold reached")
        let deleted = mock.deletedRecordNamesAcrossCalls.last ?? []
        #expect(deleted.count == 1)
        #expect(
            deleted.first?.contains("bob@anthropic.com") == true,
            "Bob's record should be the one deleted")
    }
}

// swiftlint:enable multiline_arguments
