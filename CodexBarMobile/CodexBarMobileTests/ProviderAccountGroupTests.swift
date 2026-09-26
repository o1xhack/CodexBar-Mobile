import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Unit tests for the Phase G grouping primitive that collapses
/// post-merge `[ProviderUsageSnapshot]` into one `ProviderAccountGroup`
/// per providerID. The grouping is the join point between the iCloud
/// cross-Mac merge (`CloudSyncReader.mergeSnapshots`) and the iOS
/// Usage list (one row per group) + ProviderDetailView (segmented
/// account tabs).
///
/// Pre-Phase-G, the Usage list iterated raw post-merge snapshots and
/// rendered N cards per multi-account provider. User feedback was
/// "Mac shows one card with tabs, iOS shouldn't be different" — this
/// suite pins the grouping that fixes the divergence.
@Suite("ProviderAccountGroup grouping")
struct ProviderAccountGroupTests {
    private static func snapshot(
        providerID: String,
        providerName: String,
        accountEmail: String? = nil,
        loginMethod: String? = nil) -> ProviderUsageSnapshot
    {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerName,
            primary: nil,
            secondary: nil,
            accountEmail: accountEmail,
            loginMethod: loginMethod,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))
    }

    // MARK: - groupedByProvider

    @Test("Empty input → empty groups")
    func emptyInput() {
        let groups: [ProviderUsageSnapshot] = []
        #expect(groups.groupedByProvider().isEmpty)
    }

    @Test("Single snapshot → one group with one account, hasMultipleAccounts == false")
    func singleSnapshot() {
        let snap = Self.snapshot(providerID: "claude", providerName: "Claude", accountEmail: "user@example.com")
        let groups = [snap].groupedByProvider()
        #expect(groups.count == 1)
        #expect(groups.first?.providerID == "claude")
        #expect(groups.first?.accounts.count == 1)
        #expect(groups.first?.hasMultipleAccounts == false)
    }

    @Test("Two snapshots same providerID → one group with two accounts")
    func twoSnapshotsSameProvider() {
        let a = Self.snapshot(
            providerID: "openai", providerName: "OpenAI",
            accountEmail: "admin-msxiao113@openai.com")
        let b = Self.snapshot(
            providerID: "openai", providerName: "OpenAI",
            accountEmail: "admin-outlook@openai.com")
        let groups = [a, b].groupedByProvider()
        #expect(groups.count == 1)
        let group = try? #require(groups.first)
        #expect(group?.providerID == "openai")
        #expect(group?.accounts.count == 2)
        #expect(group?.hasMultipleAccounts == true)
        // Order preserved (first-appearance).
        #expect(group?.accounts[0].accountEmail == "admin-msxiao113@openai.com")
        #expect(group?.accounts[1].accountEmail == "admin-outlook@openai.com")
    }

    @Test("Different providerIDs → distinct groups in first-appearance order")
    func distinctProviderIDsPreserveOrder() {
        let snaps = [
            Self.snapshot(providerID: "codex", providerName: "Codex"),
            Self.snapshot(providerID: "claude", providerName: "Claude"),
            Self.snapshot(providerID: "openai", providerName: "OpenAI"),
        ]
        let groups = snaps.groupedByProvider()
        #expect(groups.map(\.providerID) == ["codex", "claude", "openai"])
    }

    @Test("Mixed multi-account + single-account, order preserved")
    func mixedMultiAndSingle() {
        let snaps = [
            Self.snapshot(providerID: "codex", providerName: "Codex (alice)", accountEmail: "alice@x.test"),
            Self.snapshot(providerID: "openai", providerName: "OpenAI"),
            Self.snapshot(providerID: "codex", providerName: "Codex (bob)", accountEmail: "bob@x.test"),
            Self.snapshot(providerID: "claude", providerName: "Claude"),
        ]
        let groups = snaps.groupedByProvider()
        #expect(groups.map(\.providerID) == ["codex", "openai", "claude"])
        #expect(groups[0].accounts.count == 2) // codex alice + bob
        #expect(groups[0].hasMultipleAccounts == true)
        #expect(groups[1].accounts.count == 1)
        #expect(groups[1].hasMultipleAccounts == false)
        #expect(groups[2].accounts.count == 1)
    }

    @Test("Representative is the first appearance (group-level cosmetics use it)")
    func representativeIsFirstAppearance() {
        let first = Self.snapshot(providerID: "claude", providerName: "Claude (Personal)")
        let second = Self.snapshot(providerID: "claude", providerName: "Claude (Work)")
        let groups = [first, second].groupedByProvider()
        #expect(groups.first?.representative.providerName == "Claude (Personal)")
    }

    // MARK: - tabLabel

    @Test("tabLabel prefers email local-part over login method")
    func tabLabelPrefersEmail() {
        let group = ProviderAccountGroup(
            providerID: "openai",
            providerName: "OpenAI",
            accounts: [
                Self.snapshot(
                    providerID: "openai", providerName: "OpenAI",
                    accountEmail: "admin-msxiao113@openai.com",
                    loginMethod: "Admin"),
            ])
        // Should be the part before "@", not "Admin".
        #expect(group.tabLabel(forIndex: 0) == "admin-msxiao113")
    }

    @Test("tabLabel falls back to loginMethod when email missing")
    func tabLabelFallsBackToLoginMethod() {
        let group = ProviderAccountGroup(
            providerID: "kiro",
            providerName: "Kiro",
            accounts: [
                Self.snapshot(
                    providerID: "kiro", providerName: "Kiro",
                    accountEmail: nil,
                    loginMethod: "Pro Plan"),
            ])
        #expect(group.tabLabel(forIndex: 0) == "Pro Plan")
    }

    @Test("tabLabel falls back to `Account N` when nothing else available")
    func tabLabelFallsBackToOrdinal() {
        let group = ProviderAccountGroup(
            providerID: "x",
            providerName: "X",
            accounts: [
                Self.snapshot(providerID: "x", providerName: "X"),
                Self.snapshot(providerID: "x", providerName: "X"),
            ])
        #expect(group.tabLabel(forIndex: 0) == String.localizedStringWithFormat(
            String(localized: "Account %lld"), 1))
        #expect(group.tabLabel(forIndex: 1) == String.localizedStringWithFormat(
            String(localized: "Account %lld"), 2))
    }

    @Test("tabLabel handles out-of-bounds gracefully")
    func tabLabelOutOfBounds() {
        let group = ProviderAccountGroup(
            providerID: "x",
            providerName: "X",
            accounts: [Self.snapshot(providerID: "x", providerName: "X")])
        #expect(group.tabLabel(forIndex: 5) == "")
    }

    @Test("tabAccessibilityIdentifier is providerID + index — stable across renders")
    func tabAccessibilityIDStable() {
        let group = ProviderAccountGroup(
            providerID: "openai",
            providerName: "OpenAI",
            accounts: [
                Self.snapshot(providerID: "openai", providerName: "OpenAI"),
                Self.snapshot(providerID: "openai", providerName: "OpenAI"),
            ])
        #expect(group.tabAccessibilityIdentifier(forIndex: 0) == "provider-account-tab-openai-0")
        #expect(group.tabAccessibilityIdentifier(forIndex: 1) == "provider-account-tab-openai-1")
    }
}
