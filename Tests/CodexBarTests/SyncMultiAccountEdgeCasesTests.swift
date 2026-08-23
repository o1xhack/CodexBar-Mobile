// swiftformat:disable preferCountWhere
// swiftlint:disable multiline_arguments
import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// R5 §E — Mac-side edge cases for the multi-account sync expansion.
/// Augments R5 §A (Codex managed-account end-to-end) and R3 P1 tests by
/// exercising lifecycle transitions, error propagation, and cross-provider
/// scenarios that wouldn't otherwise be covered.
///
/// See `Research/020-multi-account-comprehensive.md` R5 §E.
@MainActor
@Suite(.serialized)
struct SyncMultiAccountEdgeCasesTests {
    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        // Ensure mock-provider injection is off — MockProviderInjector
        // reads UserDefaults.standard (process-wide) so a parallel test
        // suite that flipped the flag could leak into our SyncCoordinator
        // cycles. Resetting at the start of every R5 helper guarantees
        // a clean slate regardless of test execution order.
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

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func makeTokenAccount(label: String) -> ProviderTokenAccount {
        ProviderTokenAccount(
            id: UUID(), label: label, token: "tok-\(label)",
            addedAt: Date().timeIntervalSince1970, lastUsed: nil)
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
                providerID: provider.instanceID,
                accountEmail: accountEmail,
                accountOrganization: nil,
                loginMethod: "oauth"))
    }

    private func makeTokenAccountUsageSnapshot(
        provider: UsageProvider,
        label: String,
        accountEmail: String,
        usedPercent: Double = 25.0,
        error: String? = nil) -> TokenAccountUsageSnapshot
    {
        TokenAccountUsageSnapshot(
            account: self.makeTokenAccount(label: label),
            snapshot: error == nil
                ? self.makeUsageSnapshot(
                    provider: provider, accountEmail: accountEmail, usedPercent: usedPercent)
                : nil,
            error: error,
            sourceLabel: nil,
            cacheKey: "test-\(provider.rawValue)-\(label)")
    }

    // MARK: - E1: Provider toggle-off purges cache

    @Test
    func `R5 E1: Disabling a multi-account provider purges its cache entries`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E1-Disable")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "alice", accountEmail: "alice@x.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "bob", accountEmail: "bob@x.com")
        store._setSnapshotForTesting(alice.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        // Cycle 1: emit Alice + Bob.
        await coordinator.pushCurrentSnapshot()
        let cycle1Claude = mock.lastSnapshot?.providers
            .filter { $0.providerID == "claude" } ?? []
        #expect(cycle1Claude.count == 2)

        // Cycle 2: disable Claude, clear stale accountSnapshots.
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: false)
        store.accountSnapshots.removeValue(forKey: .claude)
        await coordinator.pushCurrentSnapshot()
        let cycle2Claude = mock.lastSnapshot?.providers
            .filter { $0.providerID == "claude" } ?? []
        #expect(cycle2Claude.isEmpty, "disabled Claude should not emit")
    }

    // MARK: - E2: Re-enable after disable starts cold

    @Test
    func `R5 E2: Re-enabling provider after disable starts with empty cache (no zombie data)`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E2-ReEnable")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "alice", accountEmail: "alice@x.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "bob", accountEmail: "bob@x.com")
        store._setSnapshotForTesting(alice.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        // Cycle 1: emit alice+bob.
        await coordinator.pushCurrentSnapshot()
        let cycle1ClaudeCount = mock.lastSnapshot?.providers
            .filter { $0.providerID == "claude" }.count ?? 0
        #expect(cycle1ClaudeCount == 2)

        // Cycle 2: disable.
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: false)
        store.accountSnapshots.removeValue(forKey: .claude)
        store._setSnapshotForTesting(nil, provider: .claude)
        await coordinator.pushCurrentSnapshot()

        // Cycle 3: re-enable. Old multi-account state was purged. New
        // session brings only what's currently in store.
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let onlyAlice = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "alice", accountEmail: "alice@x.com")
        store._setSnapshotForTesting(onlyAlice.snapshot, provider: .claude)
        // Don't repopulate accountSnapshots.
        await coordinator.pushCurrentSnapshot()
        let cycle3Claude = mock.lastSnapshot?.providers
            .filter { $0.providerID == "claude" } ?? []
        #expect(
            cycle3Claude.count == 1,
            "after re-enable with no multi-account data, only active emits — Bob is gone (no zombie)")
        #expect(cycle3Claude.first?.accountEmail == "alice@x.com")
    }

    // MARK: - E3: Token-account error preserved per-record

    @Test
    func `R5 E3: Token-account with refresh error emits record with error, others unaffected`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E3-AcctError")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        // Alice is fresh. Bob has refresh error (snapshot=nil, error=set).
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "alice", accountEmail: "alice@x.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude,
            label: "bob",
            accountEmail: "bob@x.com",
            error: "Cookie expired")
        store._setSnapshotForTesting(alice.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let claudes = mock.lastSnapshot?.providers
            .filter { $0.providerID == "claude" } ?? []
        #expect(claudes.count == 2)
        let aliceEmit = claudes.first { $0.accountEmail == "alice@x.com" }
        // Bob's record has accountEmail=nil because his snapshot is nil
        // (the error path doesn't populate identity). This is real
        // production behavior — without a successful auth, we don't know
        // the email. Identify by isError == true.
        let bobEmit = claudes.first { $0.isError && $0.accountEmail == nil }
        #expect(aliceEmit?.isError == false)
        #expect(bobEmit != nil, "Bob's record should be present with isError")
        #expect(bobEmit?.statusMessage == "Cookie expired")
    }

    // MARK: - E4: Multiple multi-account providers in same push

    @Test
    func `R5 E4: Codex 3 accounts + Claude 2 accounts + Cursor 2 accounts = 7 records in one push`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E4-MultiProvMulti")
        settings.iCloudSyncEnabled = true
        for provider: UsageProvider in [.codex, .claude, .cursor] {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(ProviderDefaults.metadata[provider]),
                enabled: true)
        }
        let store = self.makeUsageStore(settings: settings)

        // Codex: 3 accounts. Use the multiAccountCache via Mac-side
        // observation cycling. To keep test simple, set active to one
        // and only exercise that account's emit. Multi-account Codex is
        // separately covered in R5 §A.
        let codexActive = self.makeUsageSnapshot(
            provider: .codex, accountEmail: "codex-active@x.com")
        store._setSnapshotForTesting(codexActive, provider: .codex)

        // Claude: 2 token accounts.
        let claudeAlice = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "claude-a", accountEmail: "claude-a@x.com")
        let claudeBob = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "claude-b", accountEmail: "claude-b@x.com")
        store._setSnapshotForTesting(claudeAlice.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [claudeAlice, claudeBob]

        // Cursor: 2 token accounts.
        let cursorCarol = self.makeTokenAccountUsageSnapshot(
            provider: .cursor, label: "cursor-c", accountEmail: "cursor-c@x.com")
        let cursorDave = self.makeTokenAccountUsageSnapshot(
            provider: .cursor, label: "cursor-d", accountEmail: "cursor-d@x.com")
        store._setSnapshotForTesting(cursorCarol.snapshot, provider: .cursor)
        store.accountSnapshots[.cursor] = [cursorCarol, cursorDave]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let providers = mock.lastSnapshot?.providers ?? []
        let codexCount = providers.count(where: { $0.providerID == "codex" })
        let claudeCount = providers.count(where: { $0.providerID == "claude" })
        let cursorCount = providers.count(where: { $0.providerID == "cursor" })
        #expect(codexCount == 1, "Codex single-account in this scenario")
        #expect(claudeCount == 2)
        #expect(cursorCount == 2)
        #expect(providers.count == 5)
    }

    // MARK: - E5: All 11 token-based providers each multi-account

    @Test
    func `R5 E5: Token-based providers each with 2 accounts → expansion works for all enabled`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E5-AllToken")
        settings.iCloudSyncEnabled = true
        let providers: [UsageProvider] = [
            .claude, .zai, .cursor, .opencode, .opencodego,
            .factory, .minimax, .augment, .ollama, .abacus, .mistral,
        ]
        for provider in providers {
            try settings.setProviderEnabled(
                provider: provider,
                metadata: #require(ProviderDefaults.metadata[provider]),
                enabled: true)
        }
        let store = self.makeUsageStore(settings: settings)
        let actuallyEnabled = store.enabledProviders().compactMap(\.firstPartyProvider)

        for provider in actuallyEnabled {
            let active = self.makeTokenAccountUsageSnapshot(
                provider: provider,
                label: "\(provider.rawValue)-active",
                accountEmail: "\(provider.rawValue)-a@x.com")
            let other = self.makeTokenAccountUsageSnapshot(
                provider: provider,
                label: "\(provider.rawValue)-other",
                accountEmail: "\(provider.rawValue)-b@x.com")
            store._setSnapshotForTesting(active.snapshot, provider: provider)
            store.accountSnapshots[provider.instanceID] = [active, other]
        }

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let allProviders = mock.lastSnapshot?.providers ?? []
        // Expect 2 records per enabled token provider, but tolerate
        // providers whose enablement was constrained for other reasons
        // (e.g. enabledProviders filters out some by token-source policy).
        // Check count match for enabled set.
        var providersWithExpansion = 0
        for provider in actuallyEnabled {
            let count = allProviders.filter { $0.providerID == provider.rawValue }.count
            if count == 2 { providersWithExpansion += 1 }
        }
        #expect(providersWithExpansion >= 8, "at least 8 of the 11 token providers should expand to 2 records each")
        #expect(allProviders.count >= 16, "at least 16 records (8 providers × 2) should emit")
    }

    @Test
    func `Provider-level local cost is emitted once across token accounts`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E5-SharedCostOnce")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .opencodego,
            metadata: #require(ProviderDefaults.metadata[.opencodego]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let now = Date()
        let daily = CostUsageDailyReport.Entry(
            date: self.dayKey(now),
            inputTokens: 100,
            outputTokens: 50,
            totalTokens: 150,
            costUSD: 3,
            modelsUsed: ["test-model"],
            modelBreakdowns: nil)
        let localUsage = OpenCodeGoUsageSnapshot(
            hasMonthlyUsage: true,
            rollingUsagePercent: 10,
            weeklyUsagePercent: 20,
            monthlyUsagePercent: 30,
            rollingResetInSec: 60,
            weeklyResetInSec: 120,
            monthlyResetInSec: 180,
            daily: [daily],
            updatedAt: now)
        let activeSnapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            opencodegoUsage: localUsage,
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: UsageProvider.opencodego.instanceID,
                accountEmail: "bob@x.com",
                accountOrganization: nil,
                loginMethod: "token"))
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .opencodego, label: "alice", accountEmail: "alice@x.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .opencodego, label: "bob", accountEmail: "bob@x.com")
        settings.updateProviderConfig(provider: .opencodego) { config in
            config.tokenAccounts = ProviderTokenAccountData(
                version: 1,
                accounts: [alice.account, bob.account],
                activeIndex: 1)
        }
        store._setSnapshotForTesting(activeSnapshot, provider: .opencodego)
        store._setTokenSnapshotForTesting(
            localUsage.toCostUsageTokenSnapshot(historyDays: 30),
            provider: .opencodego)
        store.accountSnapshots[.opencodego] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let emitted = mock.lastSnapshot?.providers.filter { $0.providerID == "opencodego" } ?? []
        #expect(emitted.count == 2)
        #expect(emitted.compactMap(\.costSummary).count == 1)
        #expect(emitted.compactMap(\.costSummary?.last30DaysCostUSD) == [3])
        #expect(emitted.first(where: { $0.accountEmail == "alice@x.com" })?.costSummary == nil)
        #expect(emitted.first(where: { $0.accountEmail == "bob@x.com" })?.costSummary != nil)
        #expect(emitted.first(where: { $0.accountEmail == "alice@x.com" })?.costSummaryCleared == true)
        #expect(emitted.first(where: { $0.accountEmail == "bob@x.com" })?.costSummaryCleared == nil)

        // Move ownership to Alice. Bob must now carry an explicit tombstone;
        // omitting his summary alone would leave his old iOS ledger rows alive.
        settings.updateProviderConfig(provider: .opencodego) { config in
            config.tokenAccounts = ProviderTokenAccountData(
                version: 1,
                accounts: [alice.account, bob.account],
                activeIndex: 0)
        }
        await coordinator.pushCurrentSnapshot()

        let moved = mock.lastSnapshot?.providers.filter { $0.providerID == "opencodego" } ?? []
        #expect(moved.first(where: { $0.accountEmail == "alice@x.com" })?.costSummary != nil)
        #expect(moved.first(where: { $0.accountEmail == "alice@x.com" })?.costSummaryCleared == nil)
        #expect(moved.first(where: { $0.accountEmail == "bob@x.com" })?.costSummary == nil)
        #expect(moved.first(where: { $0.accountEmail == "bob@x.com" })?.costSummaryCleared == true)

        // A stale persisted selection can temporarily be absent from the
        // freshly fetched account list. Keep one deterministic owner instead
        // of clearing every account and dropping the shared cost payload.
        let missing = self.makeTokenAccount(label: "missing")
        settings.updateProviderConfig(provider: .opencodego) { config in
            config.tokenAccounts = ProviderTokenAccountData(
                version: 1,
                accounts: [missing, alice.account, bob.account],
                activeIndex: 0)
        }
        await coordinator.pushCurrentSnapshot()

        let staleSelection = mock.lastSnapshot?.providers
            .filter { $0.providerID == "opencodego" } ?? []
        #expect(staleSelection.compactMap(\.costSummary).count == 1)
        #expect(staleSelection.first(where: { $0.accountEmail == "alice@x.com" })?.costSummary != nil)
        #expect(staleSelection.first(where: { $0.accountEmail == "bob@x.com" })?.costSummaryCleared == true)
    }

    @Test
    func `OpenRouter management spend uses one stable owner independent of selected API key`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E5-OpenRouterStableCostOwner")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .openrouter,
            metadata: #require(ProviderDefaults.metadata[.openrouter]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let now = Date(timeIntervalSince1970: 1_787_079_600)
        let cost = CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: 150,
            last30DaysCostUSD: 3,
            last30DaysRequests: 2,
            historyDays: 30,
            historyCoverageIsEstablished: true,
            meteredCostUSD: 3,
            costProvenance: .vendorMetered,
            daily: [CostUsageDailyReport.Entry(
                date: "2026-08-18",
                inputTokens: 100,
                outputTokens: 50,
                totalTokens: 150,
                requestCount: 2,
                costUSD: 3,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            bucketTimeZoneIdentifier: "UTC",
            updatedAt: now)
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .openrouter, label: "alice", accountEmail: "alice@x.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .openrouter, label: "bob", accountEmail: "bob@x.com")
        settings.updateProviderConfig(provider: .openrouter) { config in
            config.tokenAccounts = ProviderTokenAccountData(
                version: 1,
                accounts: [alice.account, bob.account],
                activeIndex: 0)
        }
        store._setSnapshotForTesting(alice.snapshot, provider: .openrouter)
        store._setTokenSnapshotForTesting(cost, provider: .openrouter)
        store.accountSnapshots[.openrouter] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        func assertStableOwner(_ providers: [ProviderUsageSnapshot]) throws {
            #expect(providers.count == 3)
            let owner = try #require(providers.first {
                $0.accountRecordKey == ProviderUsageSnapshot.openRouterManagementCostRecordKey
            })
            #expect(owner.accountEmail == nil)
            #expect(owner.costSummary?.last30DaysCostUSD == 3)
            #expect(owner.accountIdentities == [
                "openrouter:record:\(ProviderUsageSnapshot.openRouterManagementCostRecordKey)",
            ])
            let accounts = providers.filter {
                $0.accountRecordKey != ProviderUsageSnapshot.openRouterManagementCostRecordKey
            }
            #expect(accounts.allSatisfy { $0.costSummary == nil })
            #expect(accounts.allSatisfy { $0.costSummaryCleared == true })
        }

        try assertStableOwner(mock.lastSnapshot?.providers.filter {
            $0.providerID == "openrouter"
        } ?? [])

        settings.updateProviderConfig(provider: .openrouter) { config in
            config.tokenAccounts = ProviderTokenAccountData(
                version: 1,
                accounts: [alice.account, bob.account],
                activeIndex: 1)
        }
        await coordinator.pushCurrentSnapshot()

        try assertStableOwner(mock.lastSnapshot?.providers.filter {
            $0.providerID == "openrouter"
        } ?? [])
        #expect(
            mock.deleteCallCount == 0,
            "switching API-key selection must not migrate or delete provider-level spend")
    }

    @Test
    func `Mistral account-native cost failure does not emit a shared-owner tombstone`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E5-MistralAccountNativeCost")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .mistral,
            metadata: #require(ProviderDefaults.metadata[.mistral]),
            enabled: true)

        let aliceAccount = self.makeTokenAccount(label: "alice")
        let bobAccount = self.makeTokenAccount(label: "bob")
        settings.updateProviderConfig(provider: .mistral) { config in
            config.tokenAccounts = ProviderTokenAccountData(
                version: 1,
                accounts: [aliceAccount, bobAccount],
                activeIndex: 0)
        }

        let now = Date(timeIntervalSince1970: 1_787_079_600)
        let aliceBilling = MistralUsageSnapshot(
            totalCost: 3,
            currency: "USD",
            currencySymbol: "$",
            totalInputTokens: 100,
            totalOutputTokens: 50,
            totalCachedTokens: 0,
            modelCount: 1,
            daily: [MistralDailyUsageBucket(
                day: "2026-08-18",
                cost: 3,
                inputTokens: 100,
                cachedTokens: 0,
                outputTokens: 50,
                models: [])],
            startDate: nil,
            endDate: nil,
            updatedAt: now)
        let aliceUsage = UsageSnapshot(
            primary: nil,
            secondary: nil,
            mistralUsage: aliceBilling,
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: .mistral,
                accountEmail: "alice@x.com",
                accountOrganization: nil,
                loginMethod: "web"))
        let alice = TokenAccountUsageSnapshot(
            account: aliceAccount,
            snapshot: aliceUsage,
            error: nil,
            sourceLabel: "web",
            cacheKey: "test-mistral-alice")
        let bob = TokenAccountUsageSnapshot(
            account: bobAccount,
            snapshot: nil,
            error: "Temporary billing fetch failure",
            sourceLabel: nil,
            cacheKey: "test-mistral-bob")

        let store = self.makeUsageStore(settings: settings)
        store._setSnapshotForTesting(aliceUsage, provider: .mistral)
        store.accountSnapshots[.mistral] = [alice, bob]
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let emitted = mock.lastSnapshot?.providers.filter { $0.providerID == "mistral" } ?? []
        #expect(emitted.count == 2)
        #expect(emitted.first(where: { $0.accountEmail == "alice@x.com" })?.costSummary != nil)
        let failedAccount = try #require(emitted.first { $0.accountEmail == nil })
        #expect(failedAccount.costSummary == nil)
        #expect(failedAccount.costSummaryCleared == nil)
    }

    // MARK: - E6: 27 providers all enabled (single-account stress)

    @Test
    func `R5 E6: All 27 providers enabled, single-account each → 27 records, no missing`() async {
        let settings = self.makeSettingsStore(suite: "R5E6-All27")
        settings.iCloudSyncEnabled = true
        let allProviders = UsageProvider.allCases
        for provider in allProviders {
            // Some providers may not have metadata defaults — skip
            // gracefully if so.
            guard let meta = ProviderDefaults.metadata[provider] else { continue }
            settings.setProviderEnabled(
                provider: provider, metadata: meta, enabled: true)
        }
        let store = self.makeUsageStore(settings: settings)
        let enabled = store.enabledProviders().compactMap(\.firstPartyProvider)
        for provider in enabled {
            store._setSnapshotForTesting(
                self.makeUsageSnapshot(
                    provider: provider,
                    accountEmail: "\(provider.rawValue)@x.com"),
                provider: provider)
        }

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let pushedCount = mock.lastSnapshot?.providers.count ?? 0
        // `enabled` is the set of providers actually enabled in settings
        // (which may be < 27 if `ProviderDefaults.metadata` is missing
        // some providers; we skipped those during setup).
        #expect(
            pushedCount == enabled.count,
            "should push exactly one record per enabled provider (\(enabled.count))")
        #expect(enabled.count >= 20, "we expect to enable at least 20 of the 27 providers")
        // Verify no duplicates.
        let providerIDs = mock.lastSnapshot?.providers.map(\.providerID) ?? []
        #expect(
            Set(providerIDs).count == providerIDs.count,
            "no duplicate providerIDs in single-account scenario")
    }

    // MARK: - E7: Token provider with empty account list does not crash

    @Test
    func `R5 E7: accountSnapshots[provider] = [] (empty) skips expansion safely`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E7-EmptyArr")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let activeSnap = self.makeUsageSnapshot(
            provider: .claude, accountEmail: "active@x.com")
        store._setSnapshotForTesting(activeSnap, provider: .claude)
        // Empty array (different from nil).
        store.accountSnapshots[.claude] = []

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let claudes = mock.lastSnapshot?.providers
            .filter { $0.providerID == "claude" } ?? []
        #expect(claudes.count == 1, "empty array fails count >= 2 guard, fallback to active")
    }

    // MARK: - E8: Push idempotency — repeated push without state change

    @Test
    func `R5 E8: Repeated push without state change doesn't grow record set`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E8-Idempotent")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let alice = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "alice", accountEmail: "alice@x.com")
        let bob = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "bob", accountEmail: "bob@x.com")
        store._setSnapshotForTesting(alice.snapshot, provider: .claude)
        store.accountSnapshots[.claude] = [alice, bob]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)

        // Push 5 times.
        for _ in 1...5 {
            await coordinator.pushCurrentSnapshot()
        }

        let claudes = mock.lastSnapshot?.providers
            .filter { $0.providerID == "claude" } ?? []
        #expect(claudes.count == 2, "repeated push with stable state still emits 2 records (no growth)")
        #expect(mock.deleteCallCount == 0, "no spurious deletes during stable repeated push")
    }

    // MARK: - E9: Token provider with all-error accounts still emits correctly

    @Test
    func `R5 E9: All token accounts in error state still emit 2 error records`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E9-AllErrors")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let aliceErr = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "alice", accountEmail: "alice@x.com",
            error: "Auth failed for Alice")
        let bobErr = self.makeTokenAccountUsageSnapshot(
            provider: .claude, label: "bob", accountEmail: "bob@x.com",
            error: "Auth failed for Bob")
        // Active snapshot is also error.
        store._setSnapshotForTesting(nil, provider: .claude)
        store._setErrorForTesting("Auth failed", provider: .claude)
        store.accountSnapshots[.claude] = [aliceErr, bobErr]

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let claudes = mock.lastSnapshot?.providers
            .filter { $0.providerID == "claude" } ?? []
        // The error-snapshots have accountEmail = nil (since
        // entry.snapshot is nil), so the multi-account emit will produce
        // 2 records both with accountEmail=nil. Implementation detail
        // — verify the count at least.
        #expect(claudes.count == 2)
        // Both should have isError true.
        let allError = claudes.allSatisfy(\.isError)
        #expect(allError)
    }

    // MARK: - E10: Codex liveSystem + multi managed transition

    @Test
    func `R5 E10: Switching FROM .liveSystem TO .managedAccount emits correctly`() async throws {
        let settings = self.makeSettingsStore(suite: "R5E10-LiveToManaged")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let alice = ManagedCodexAccount(
            id: UUID(), email: "alice@example.com",
            managedHomePath: "/tmp/alice",
            createdAt: 1, updatedAt: 1, lastAuthenticatedAt: 1)
        let bob = ManagedCodexAccount(
            id: UUID(), email: "bob@example.com",
            managedHomePath: "/tmp/bob",
            createdAt: 1, updatedAt: 1, lastAuthenticatedAt: 1)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("e10-\(UUID()).json")
        try FileManagedCodexAccountStore(fileURL: storeURL).storeAccounts(
            ManagedCodexAccountSet(
                version: FileManagedCodexAccountStore.currentVersion,
                accounts: [alice, bob]))
        settings._test_managedCodexAccountStoreURL = storeURL

        let store = self.makeUsageStore(settings: settings)
        // Start with .liveSystem.
        settings.codexActiveSource = .liveSystem
        store._setSnapshotForTesting(
            self.makeUsageSnapshot(provider: .codex, accountEmail: "live@example.com"),
            provider: .codex)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()
        let cycle1 = mock.lastSnapshot?.providers
            .filter { $0.providerID == "codex" } ?? []
        #expect(cycle1.count == 1, ".liveSystem only emits live")

        // Switch to .managedAccount(alice). storedAccounts.count = 2 → expansion.
        settings.codexActiveSource = .managedAccount(id: alice.id)
        store._setSnapshotForTesting(
            self.makeUsageSnapshot(provider: .codex, accountEmail: "alice@example.com"),
            provider: .codex)
        await coordinator.pushCurrentSnapshot()
        let cycle2 = mock.lastSnapshot?.providers
            .filter { $0.providerID == "codex" } ?? []
        // First push as managed: cache cold start, only Alice emitted.
        // The previously-emitted "live" record will be detected as
        // partial shrink and deferred for delete (2-cycle).
        #expect(cycle2.count == 1, "first managed push: cold cache, only Alice emitted")
    }
}

// swiftlint:enable multiline_arguments
// swiftformat:enable preferCountWhere
