import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// Pin the Phase G hotfix that decouples `shouldFetchAllTokenAccounts`
/// from `multiAccountMenuLayout` when iCloud sync is enabled.
///
/// Pre-hotfix bug: a user with 2 OpenAI admin keys + segmented Mac
/// menu layout (the default) had Mac fetch only the active admin
/// account → SyncCoordinator pushed 1 record → iPhone showed 1
/// OpenAI card, no tab switcher. The Phase G iOS UI was correct but
/// never received the second snapshot. The Mac menu's segmented vs.
/// stacked toggle is local Mac UI ergonomics — it should NOT
/// determine what reaches iPhone via CloudKit.
///
/// These tests pin the new behavior:
///   - iCloud sync ON  → always fan-out when accounts > 1
///   - iCloud sync OFF → preserve upstream gating on stacked layout
/// And the count > 1 guard remains in both branches (no point
/// fanning out a single-account provider).
@MainActor
@Suite("UsageStore.shouldFetchAllTokenAccounts — Phase G iCloud-sync hotfix")
struct ShouldFetchAllTokenAccountsTests {
    private static func makeStore(
        suite: String,
        iCloudSyncEnabled: Bool,
        layout: MultiAccountMenuLayout) -> UsageStore
    {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.iCloudSyncEnabled = iCloudSyncEnabled
        settings.multiAccountMenuLayout = layout
        return UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }

    private static func accounts(_ count: Int, provider _: UsageProvider = .openai) -> [ProviderTokenAccount] {
        (0..<count).map { i in
            ProviderTokenAccount(
                id: UUID(),
                label: "Account \(i + 1)",
                token: "sk-...\(i)",
                addedAt: Date().timeIntervalSince1970,
                lastUsed: nil)
        }
    }

    // MARK: - count guard (both branches respect it)

    @Test
    func `Single-account provider always returns false (no point fanning out 1)`() {
        let store = Self.makeStore(suite: "FetchAll-Single", iCloudSyncEnabled: true, layout: .stacked)
        let result = store.shouldFetchAllTokenAccounts(
            provider: .openai, accounts: Self.accounts(1))
        #expect(result == false)
    }

    @Test
    func `Zero accounts returns false`() {
        let store = Self.makeStore(suite: "FetchAll-Zero", iCloudSyncEnabled: true, layout: .stacked)
        let result = store.shouldFetchAllTokenAccounts(
            provider: .openai, accounts: [])
        #expect(result == false)
    }

    @Test
    func `Non-token-account provider returns false even with multi accounts`() {
        // `.codex` is in catalog only via managed-accounts path, not
        // token-account catalog — verify the guard at top of fn fires.
        let store = Self.makeStore(suite: "FetchAll-NonToken", iCloudSyncEnabled: true, layout: .stacked)
        let result = store.shouldFetchAllTokenAccounts(
            provider: .codex, accounts: Self.accounts(3, provider: .codex))
        #expect(
            result == false,
            "codex has no TokenAccountSupportCatalog entry; managed-accounts path handles it")
    }

    // MARK: - iCloud sync ON branch (Phase G hotfix)

    @Test
    func `iCloud sync ON + segmented + 2 accounts → true (the user-reported bug fixed)`() {
        // This is the EXACT scenario the user hit:
        // - OpenAI admin keys: 2
        // - Mac menu layout: segmented (default)
        // - iCloud sync: enabled (= user has the iPhone app)
        // Pre-fix: false → only active synced → iPhone shows 1 card.
        // Post-fix: true → both synced → iPhone shows 2 tabs.
        let store = Self.makeStore(suite: "FetchAll-ICloudSeg", iCloudSyncEnabled: true, layout: .segmented)
        let result = store.shouldFetchAllTokenAccounts(
            provider: .openai, accounts: Self.accounts(2))
        #expect(result == true)
    }

    @Test
    func `iCloud sync ON + stacked + 2 accounts → true (already true pre-fix)`() {
        let store = Self.makeStore(suite: "FetchAll-ICloudStack", iCloudSyncEnabled: true, layout: .stacked)
        let result = store.shouldFetchAllTokenAccounts(
            provider: .openai, accounts: Self.accounts(2))
        #expect(result == true)
    }

    @Test
    func `iCloud sync ON + 3 accounts → true (any count > 1)`() {
        let store = Self.makeStore(suite: "FetchAll-ICloudThree", iCloudSyncEnabled: true, layout: .segmented)
        let result = store.shouldFetchAllTokenAccounts(
            provider: .deepseek, accounts: Self.accounts(3, provider: .deepseek))
        #expect(result == true)
    }

    // MARK: - iCloud sync OFF branch (preserve upstream segmented = single-fetch behavior)

    @Test
    func `iCloud sync OFF + segmented + 2 accounts → false (upstream API-frugality preserved)`() {
        // Mac-only user (no iPhone). Honor upstream's intent: segmented
        // layout displays one card with top-tab switcher; only active
        // account needs fetching. Saves N-1 API calls per refresh.
        let store = Self.makeStore(suite: "FetchAll-NoSyncSeg", iCloudSyncEnabled: false, layout: .segmented)
        let result = store.shouldFetchAllTokenAccounts(
            provider: .openai, accounts: Self.accounts(2))
        #expect(result == false)
    }

    @Test
    func `iCloud sync OFF + stacked + 2 accounts → true (stacked layout shows all)`() {
        let store = Self.makeStore(suite: "FetchAll-NoSyncStack", iCloudSyncEnabled: false, layout: .stacked)
        let result = store.shouldFetchAllTokenAccounts(
            provider: .openai, accounts: Self.accounts(2))
        #expect(result == true)
    }

    @Test
    func `iCloud sync OFF + segmented + 1 account → false (count guard)`() {
        let store = Self.makeStore(suite: "FetchAll-NoSyncSegSingle", iCloudSyncEnabled: false, layout: .segmented)
        let result = store.shouldFetchAllTokenAccounts(
            provider: .openai, accounts: Self.accounts(1))
        #expect(result == false)
    }
}
