import CodexBarSync
import Foundation
import Testing

@testable import CodexBarMobile

/// Pins the subtitle selection rule for multi-account provider cards
/// introduced in iOS 1.3.0 (72).
///
/// Before T5, `ProviderUsageView`'s header always showed `accountEmail`
/// when non-nil (good) and was silent when nil — so two Codex cards that
/// both lacked email rendered indistinguishably. Worse, the `ContentView`
/// ForEach used `\.providerID` as SwiftUI identity, which collapsed
/// multiple-card entries down to one view instance in the list regardless
/// of what the data layer emitted.
///
/// These tests lock in:
///   - Single card (ordinal=nil) with email → subtitle is the email
///   - Single card (ordinal=nil) without email → subtitle is nil (clean layout)
///   - Multi-card (ordinal set) with email → email wins
///   - Multi-card (ordinal set) without email → "providerName N" ordinal fallback
///   - `cardIdentityKey` matches `CloudSyncReader.mergeSnapshots`'s bucket
@Suite("Provider card subtitle selection (T5)")
struct ProviderUsageViewSubtitleTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixtures

    private func makeSnapshot(
        providerID: String = "codex",
        providerName: String = "Codex",
        accountEmail: String?,
        accountOrganization: String? = nil
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: providerID,
            providerName: providerName,
            primary: nil,
            secondary: nil,
            accountEmail: accountEmail,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: self.baseDate,
            accountOrganization: accountOrganization)
    }

    // MARK: - cardIdentityKey

    @Test("cardIdentityKey includes accountEmail when present")
    func cardIdentityKeyWithEmail() {
        let snap = self.makeSnapshot(accountEmail: "alice@example.com")
        #expect(snap.cardIdentityKey == "codex|alice@example.com")
    }

    @Test("cardIdentityKey collapses nil accountEmail to empty tail (matches mergeSnapshots bucket)")
    func cardIdentityKeyWithoutEmail() {
        let snap = self.makeSnapshot(accountEmail: nil)
        #expect(snap.cardIdentityKey == "codex|")
    }

    @Test("Two distinct accounts → distinct cardIdentityKeys (so ForEach doesn't collapse)")
    func cardIdentityKeyDistinctForTwoAccounts() {
        let alice = self.makeSnapshot(accountEmail: "alice@example.com")
        let bob = self.makeSnapshot(accountEmail: "bob@example.com")
        #expect(alice.cardIdentityKey != bob.cardIdentityKey)
    }

    // MARK: - Subtitle selection

    @Test("Single-card + email → subtitle is the email")
    func singleCardWithEmail() {
        let view = ProviderUsageView(
            provider: self.makeSnapshot(accountEmail: "alice@example.com"),
            duplicateOrdinal: nil)
        #expect(view.subtitleLine() == "alice@example.com")
    }

    @Test("Single-card + nil email → subtitle is nil (clean layout)")
    func singleCardWithoutEmail() {
        let view = ProviderUsageView(
            provider: self.makeSnapshot(accountEmail: nil),
            duplicateOrdinal: nil)
        #expect(view.subtitleLine() == nil)
    }

    @Test("Single-card + workspace → workspace is the subtitle")
    func singleCardWithWorkspace() {
        let view = ProviderUsageView(
            provider: self.makeSnapshot(
                providerID: "notion",
                providerName: "Notion AI",
                accountEmail: nil,
                accountOrganization: "Design Workspace"),
            duplicateOrdinal: nil)
        #expect(view.subtitleLine() == "Design Workspace")
    }

    @Test("Email wins over workspace")
    func emailWinsOverWorkspace() {
        let view = ProviderUsageView(
            provider: self.makeSnapshot(
                accountEmail: "alice@example.com",
                accountOrganization: "Design Workspace"),
            duplicateOrdinal: nil)
        #expect(view.subtitleLine() == "alice@example.com")
    }

    @Test("Multi-card + email → email still wins (never show bare ordinal when email is attributable)")
    func multiCardWithEmail() {
        let view = ProviderUsageView(
            provider: self.makeSnapshot(accountEmail: "alice@example.com"),
            duplicateOrdinal: 1)
        #expect(view.subtitleLine() == "alice@example.com")
    }

    @Test("Multi-card + nil email → ordinal fallback (localized template)")
    func multiCardWithoutEmailFallsToOrdinal() {
        let view = ProviderUsageView(
            provider: self.makeSnapshot(accountEmail: nil),
            duplicateOrdinal: 2)
        let result = view.subtitleLine()
        // Template is `%@ %lld`-shaped in source locale; must contain the
        // provider name and the ordinal digits somewhere. Asserting on
        // substring rather than exact match keeps the test tolerant of
        // locale-specific reorderings (e.g. zh-Hans appends ` 号账户`).
        #expect(result != nil)
        #expect(result?.contains("Codex") == true)
        #expect(result?.contains("2") == true)
    }

    @Test("Multi-card + empty string email treated as nil")
    func multiCardWithEmptyEmailFallsToOrdinal() {
        // Defense against the bucket-merge fallback where `accountEmail: ""`
        // would otherwise render as a blank row. The subtitle helper
        // explicitly checks `!email.isEmpty`.
        let view = ProviderUsageView(
            provider: self.makeSnapshot(accountEmail: ""),
            duplicateOrdinal: 3)
        #expect(view.subtitleLine() != nil)
        #expect(view.subtitleLine()?.isEmpty == false)
    }
}
