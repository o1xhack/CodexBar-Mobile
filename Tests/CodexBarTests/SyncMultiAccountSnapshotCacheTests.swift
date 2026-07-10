// swiftlint:disable multiline_arguments
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// Unit tests for `SyncMultiAccountSnapshotCache` — the per-account snapshot
/// cache that lets SyncCoordinator emit one CKRecord per Codex account even
/// though Mac's `UsageStore.snapshots[.codex]` only ever holds the active
/// account at any moment. See `Research/020-multi-account-comprehensive.md`.
@MainActor
struct SyncMultiAccountSnapshotCacheTests {
    private func makeSnapshot(
        providerID: String = "codex",
        accountEmail: String?,
        lastUpdated: Date = .init(timeIntervalSince1970: 1_700_000_000))
        -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerID.capitalized,
            primary: nil,
            secondary: nil,
            accountEmail: accountEmail,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            costSummary: nil,
            budget: nil,
            rateWindows: [],
            utilizationHistory: nil,
            perplexityCredits: nil,
            accountIdentities: nil)
    }

    @Test
    func `record and retrieve single account`() {
        let cache = SyncMultiAccountSnapshotCache()
        let alice = self.makeSnapshot(accountEmail: "alice@example.com")
        cache.record(alice, providerID: "codex", accountID: "uuid-A")

        // Excluding A → empty (only entry was A).
        let cached = cache.cachedSnapshots(
            providerID: "codex", excludingAccountID: "uuid-A")
        #expect(cached.isEmpty)
        #expect(cache.count(forProvider: "codex") == 1)
    }

    @Test
    func `cached snapshots exclude active`() {
        let cache = SyncMultiAccountSnapshotCache()
        let alice = self.makeSnapshot(accountEmail: "alice@example.com")
        let bob = self.makeSnapshot(accountEmail: "bob@example.com")
        let carol = self.makeSnapshot(accountEmail: "carol@example.com")
        cache.record(alice, providerID: "codex", accountID: "uuid-A")
        cache.record(bob, providerID: "codex", accountID: "uuid-B")
        cache.record(carol, providerID: "codex", accountID: "uuid-C")

        // Active = B → return A and C
        let nonActive = cache.cachedSnapshots(
            providerID: "codex", excludingAccountID: "uuid-B")
        let emails = Set(nonActive.compactMap(\.accountEmail))
        #expect(emails == ["alice@example.com", "carol@example.com"])
        #expect(nonActive.count == 2)
    }

    @Test
    func `record replaces existing entry`() {
        let cache = SyncMultiAccountSnapshotCache()
        let aliceOld = self.makeSnapshot(
            accountEmail: "alice@example.com",
            lastUpdated: .init(timeIntervalSince1970: 1_700_000_000))
        let aliceNew = self.makeSnapshot(
            accountEmail: "alice@example.com",
            lastUpdated: .init(timeIntervalSince1970: 1_700_001_000))
        cache.record(aliceOld, providerID: "codex", accountID: "uuid-A")
        cache.record(aliceNew, providerID: "codex", accountID: "uuid-A")

        #expect(cache.count(forProvider: "codex") == 1)
        // Verify newer snapshot is what's cached: ask for non-A from a
        // different perspective (active="other" returns A) and inspect
        // lastUpdated.
        let cached = cache.cachedSnapshots(
            providerID: "codex", excludingAccountID: "uuid-other")
        #expect(cached.count == 1)
        #expect(cached.first?.lastUpdated == .init(timeIntervalSince1970: 1_700_001_000))
    }

    @Test
    func `purge stale accounts removes unreferenced`() {
        let cache = SyncMultiAccountSnapshotCache()
        let alice = self.makeSnapshot(accountEmail: "alice@example.com")
        let bob = self.makeSnapshot(accountEmail: "bob@example.com")
        let carol = self.makeSnapshot(accountEmail: "carol@example.com")
        cache.record(alice, providerID: "codex", accountID: "uuid-A")
        cache.record(bob, providerID: "codex", accountID: "uuid-B")
        cache.record(carol, providerID: "codex", accountID: "uuid-C")

        // Simulate user deleting account-B on Mac. Living set is {A, C}.
        cache.purgeStaleAccounts(
            providerID: "codex",
            livingAccountIDs: ["uuid-A", "uuid-C"])

        #expect(cache.count(forProvider: "codex") == 2)
        let cached = cache.cachedSnapshots(
            providerID: "codex", excludingAccountID: "uuid-other")
        let emails = Set(cached.compactMap(\.accountEmail))
        #expect(emails == ["alice@example.com", "carol@example.com"])
    }

    @Test
    func `purge stale accounts empty living wipes provider`() {
        let cache = SyncMultiAccountSnapshotCache()
        cache.record(
            self.makeSnapshot(accountEmail: "alice@example.com"),
            providerID: "codex", accountID: "uuid-A")
        cache.record(
            self.makeSnapshot(accountEmail: "bob@example.com"),
            providerID: "codex", accountID: "uuid-B")

        // Living set empty → all entries for codex go away.
        cache.purgeStaleAccounts(providerID: "codex", livingAccountIDs: [])

        #expect(cache.count(forProvider: "codex") == 0)
    }

    @Test
    func `cross provider isolation`() {
        // R2 readiness: cache must not leak between providers when token-based
        // providers are added in Round 2.
        let cache = SyncMultiAccountSnapshotCache()
        cache.record(
            self.makeSnapshot(providerID: "codex", accountEmail: "alice@x.com"),
            providerID: "codex", accountID: "uuid-A")
        cache.record(
            self.makeSnapshot(providerID: "claude", accountEmail: "alice@x.com"),
            providerID: "claude", accountID: "uuid-A")

        // Codex purge of "uuid-A" must not touch claude.
        cache.purgeStaleAccounts(providerID: "codex", livingAccountIDs: [])

        #expect(cache.count(forProvider: "codex") == 0)
        #expect(cache.count(forProvider: "claude") == 1)
    }

    @Test
    func `reset clears all providers`() {
        let cache = SyncMultiAccountSnapshotCache()
        cache.record(
            self.makeSnapshot(providerID: "codex", accountEmail: "alice@x.com"),
            providerID: "codex", accountID: "uuid-A")
        cache.record(
            self.makeSnapshot(providerID: "claude", accountEmail: "bob@x.com"),
            providerID: "claude", accountID: "uuid-B")

        cache.reset()

        #expect(cache.count(forProvider: "codex") == 0)
        #expect(cache.count(forProvider: "claude") == 0)
    }

    @Test
    func `different providers with same account ID do not collide`() {
        // Edge case: same UUID string used for both providers (shouldn't
        // happen in practice but cache must not key-collide).
        let cache = SyncMultiAccountSnapshotCache()
        let codexSnap = self.makeSnapshot(
            providerID: "codex", accountEmail: "shared@x.com")
        let claudeSnap = self.makeSnapshot(
            providerID: "claude", accountEmail: "shared@x.com")
        cache.record(codexSnap, providerID: "codex", accountID: "uuid-shared")
        cache.record(claudeSnap, providerID: "claude", accountID: "uuid-shared")

        let codexCached = cache.cachedSnapshots(
            providerID: "codex", excludingAccountID: "other")
        let claudeCached = cache.cachedSnapshots(
            providerID: "claude", excludingAccountID: "other")
        #expect(codexCached.count == 1)
        #expect(claudeCached.count == 1)
        #expect(codexCached.first?.providerID == "codex")
        #expect(claudeCached.first?.providerID == "claude")
    }

    @Test
    func `excluding account ID with no record returns all`() {
        // SyncCoordinator scenario: active account is fresh (just got recorded
        // earlier in same call) — excluding it from "before record" view
        // returns nothing. But excluding an account that was never cached
        // returns everything (= correct cold-start behavior).
        let cache = SyncMultiAccountSnapshotCache()
        let alice = self.makeSnapshot(accountEmail: "alice@example.com")
        let bob = self.makeSnapshot(accountEmail: "bob@example.com")
        cache.record(alice, providerID: "codex", accountID: "uuid-A")
        cache.record(bob, providerID: "codex", accountID: "uuid-B")

        // Excluding "uuid-never-seen" → returns both.
        let all = cache.cachedSnapshots(
            providerID: "codex", excludingAccountID: "uuid-never-seen")
        #expect(all.count == 2)
    }
}

// swiftlint:enable multiline_arguments
