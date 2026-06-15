// swiftlint:disable multiline_arguments
import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// MR2-MR5: extensibility, SyncCoordinator integration, mock+real
/// coexistence, and edge cases for `MockProviderInjector`.
///
/// MR1 (basic unit tests) lives in `MockProviderInjectorTests.swift`.
/// This file adds depth: 5+ rounds of testing with different conditions
/// to ensure the mock injection system is robust against real-world use.
///
/// **Mock detection convention** (Mac 0.23.5+ mix design): mocks use a
/// mix of real provider IDs (`codex`, `claude`, `perplexity`) and
/// synthetic IDs (`_mock_*`). The universal "is this a mock account?"
/// signal is the `*-mock@*.test` email TLD — the synthetic providerID
/// prefix only matches the 2 fallback mocks.
///
/// See `Research/020-multi-account-comprehensive.md` (mock section).
@MainActor
@Suite(.serialized)
struct MockProviderInjectorIntegrationTests {
    private func resetActivationState() {
        UserDefaults.standard.removeObject(
            forKey: MockProviderInjector.userDefaultsKey)
    }

    private func enableMock() {
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
    }

    private func disableMock() {
        UserDefaults.standard.set(
            false, forKey: MockProviderInjector.userDefaultsKey)
    }

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

    /// Helper: detect "is this an injected mock?" via the universal
    /// account-email TLD signal that works regardless of whether the
    /// mock borrowed a real providerID or used a synthetic `_mock_*`
    /// providerID.
    private func isMockSnapshot(_ snap: ProviderUsageSnapshot) -> Bool {
        (snap.accountEmail ?? "").hasSuffix(MockProviderInjector.mockEmailTLD)
    }

    /// Helper: detect "is this a mock recordName?" via the `-mock@`
    /// substring in the composite recordName, which is the universal
    /// marker (the email portion of the composite always contains
    /// `-mock@`, regardless of which providerID the mock used).
    private func isMockRecordName(_ name: String) -> Bool {
        name.contains("-mock@")
    }

    // MARK: - MR2 Extensibility / determinism

    @Test("MR2.1: enabled count is exactly 61 (51 IDs, 6 rich + 53 simple + 2 fallback entries)")
    func enabledCountIsStable() {
        self.enableMock()
        defer { self.resetActivationState() }
        // iOS 1.5.0: 32 mocks (29 IDs). iOS 1.6.0 catch-up: +11 simple
        // mocks for v0.24+v0.25 providers. iOS 1.7.0 catch-up: +2 for
        // v0.26 (moonshot/bedrock). Phase G: +7 multi-account
        // second-tab mocks for openai/deepseek/antigravity/manus/
        // copilot/venice/stepfun. iOS 1.8.0: +5 v0.27.0 simple mocks.
        // iOS 1.9.0: +3 v0.28+v0.29 simple mocks (azureopenai,
        // alibabatokenplan, t3chat) → 60. iOS 1.12.0 adds Devin → 61.
        #expect(MockProviderInjector.allMocks().count == 61)
    }

    /// Phase G multi-account additions REUSE existing providerIDs
    /// (second tabs for openai/deepseek/... that already had a first
    /// entry), so unique providerID count only changes when a new real
    /// provider is appended.
    @Test("MR2.2: 51 distinct providerIDs match the published allowlists (49 real + 2 synthetic)")
    func providerIDsHaveSensibleDistribution() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let providerIDs = snapshots.map(\.providerID)
        let uniqueIDs = Set(providerIDs)
        // iOS 1.5.0: 29 (27 real + 2 synthetic). iOS 1.6.0: +11 real
        // providers (matches QuotaProviderList 27 → 38). iOS 1.7.0: +2
        // (moonshot, bedrock) → 40 real + 2 synthetic = 42 unique IDs.
        // Phase G additions REUSE existing providerIDs (second tabs
        // for openai/deepseek/... that already had a first entry), so
        // unique ID count stayed at 50 until iOS 1.12.0 appended Devin.
        #expect(
            uniqueIDs.count == 51,
            "should be 51 distinct mock provider IDs (49 real + 2 synthetic; v0.34 added devin)")
        let expected: Set<String> = MockProviderInjector.realProviderIDsBorrowedByMocks
            .union(MockProviderInjector.syntheticProviderIDs)
        #expect(uniqueIDs == expected)
        #expect(uniqueIDs == MockProviderInjector.allMockProviderIDs)
    }

    @Test("MR2.3: allMocks() is deterministic across calls (same providerID set)")
    func reToggleIsDeterministic() {
        // allMocks() is shape-only, doesn't depend on activation
        // state. Call twice and verify the providerID set is stable
        // (mocks are defined statically, so this is a regression
        // test against accidental state-coupled mutation).
        let firstIDs = Set(
            MockProviderInjector.allMocks().map(\.providerID))
        let secondIDs = Set(
            MockProviderInjector.allMocks().map(\.providerID))
        #expect(firstIDs == secondIDs)
    }

    @Test("MR2.4: same call produces consistent providerName/email per ID")
    func sameCallStableNameEmail() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots1 = MockProviderInjector.allMocks()
        let snapshots2 = MockProviderInjector.allMocks()
        // Compare provider name + email pairs (not whole snapshot — timestamps differ)
        let pairs1 = Set(
            snapshots1.map { "\($0.providerName)|\($0.accountEmail ?? "")" })
        let pairs2 = Set(
            snapshots2.map { "\($0.providerName)|\($0.accountEmail ?? "")" })
        #expect(pairs1 == pairs2)
    }

    @Test("MR2.5: every mock account email uses `.test` TLD (universal mock signal)")
    func allMockEmailsUseTestTLD() {
        self.enableMock()
        defer { self.resetActivationState() }
        for snap in MockProviderInjector.allMocks() {
            let email = snap.accountEmail ?? ""
            #expect(
                email.hasSuffix(".test"),
                "every mock email must use `.test` TLD; got: \(email) (providerID: \(snap.providerID))")
        }
    }

    // MARK: - MR3 SyncCoordinator integration

    @Test("MR3.1: enabled mock causes 52 mock providers in lastSnapshot")
    func enabledMockEmitsViaSyncCoordinator() async throws {
        self.enableMock()
        defer { self.resetActivationState() }
        let settings = self.makeSettingsStore(suite: "MR3-1-Enable")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock,
            mockInjector: { MockProviderInjector.allMocks() })
        await coordinator.pushCurrentSnapshot()

        let mockProviders = mock.lastSnapshot?.providers
            .filter { self.isMockSnapshot($0) } ?? []
        // iOS 1.7.0: 43 → 45 (moonshot + bedrock).
        // Phase G: 45 → 52 (+7 multi-account second tabs).
        // iOS 1.8.0: +5 v0.27.0 → 57. iOS 1.9.0: +3 v0.28+v0.29 → 60.
        // iOS 1.12.0: +1 v0.34.0 → 61.
        #expect(mockProviders.count == 61)
    }

    @Test("MR3.2: empty mock injector closure causes 0 mock providers in lastSnapshot")
    func disabledMockEmitsNothing() async throws {
        let settings = self.makeSettingsStore(suite: "MR3-2-Disable")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        // Pass empty closure — simulates production "mock disabled" state.
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock,
            mockInjector: { [] })
        await coordinator.pushCurrentSnapshot()

        let mockProviders = mock.lastSnapshot?.providers
            .filter { self.isMockSnapshot($0) } ?? []
        #expect(mockProviders.isEmpty)
    }

    @Test("MR3.3: mock providers also flow through per-provider write path")
    func mockProvidersFlowToPerProviderZone() async throws {
        self.enableMock()
        defer { self.resetActivationState() }
        let settings = self.makeSettingsStore(suite: "MR3-3-PerProvider")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock,
            mockInjector: { MockProviderInjector.allMocks() })
        await coordinator.pushCurrentSnapshot()

        let mockEnvelopes = mock.lastPerProviderEnvelopes
            .filter { self.isMockSnapshot($0.provider) }
        // All 61 mocks must reach the per-provider write path. Ollama
        // gets a synthetic 0% "Local inference" rate window (despite
        // having no real quota in production) specifically to avoid
        // ghost-filter drop. Per Codex MCP review feedback (R2 audit):
        // advertising full-provider coverage requires that every mock
        // actually reaches iOS through both write paths.
        // iOS 1.7.0: 43 → 45 (moonshot + bedrock).
        // iOS 1.8/1.9/1.12: 45 → 57 → 60 → 61.
        #expect(
            mockEnvelopes.count == 61,
            "Phase G + iOS 1.8/1.9/1.12: 45→52→57→60→61 (+7 multi-account, +5 v0.27, +3 v0.28/v0.29, +devin).")
    }

    /// Reference wrapper so tests can flip the mock activation state
    /// while reusing the same `SyncCoordinator` instance across cycles.
    private final class MockSwitch {
        var enabled: Bool
        init(enabled: Bool) {
            self.enabled = enabled
        }
    }

    @Test("MR3.4: enable → disable → next push has no mock + delete fires for mock recordNames")
    func enableDisableTriggersGhostCleanup() async throws {
        // Each mock account is identified by `*-mock@*.test` email
        // suffix, regardless of whether the providerID is real-borrowed
        // or synthetic. When mock is disabled, every mock account
        // becomes either "whole-provider gone" (synthetic IDs) or
        // "account-identity drift" (real-borrowed IDs where the only
        // emitted account is the mock one). Per R3 P1.1 / P1.2 logic,
        // both fire immediate 1-cycle delete.
        let settings = self.makeSettingsStore(suite: "MR3-4-Cleanup")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)
        let mock = MockSyncPusher()
        // Use class wrapper so closure can read mid-test toggle without
        // depending on process-global UserDefaults (which doesn't
        // isolate across parallel suites).
        let mockSwitch = MockSwitch(enabled: true)
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock,
            mockInjector: {
                mockSwitch.enabled ? MockProviderInjector.allMocks() : []
            })

        // Cycle 1: mock enabled → emit all current mocks. No deletes (first push).
        await coordinator.pushCurrentSnapshot()
        #expect(mock.lastSnapshot?.providers.contains { self.isMockSnapshot($0) } == true)
        #expect(mock.deleteCallCount == 0)

        // Flip the in-memory switch.
        mockSwitch.enabled = false

        // Cycle 2: no mocks emitted. Mock recordNames must be
        // delete-targeted via either whole-provider-gone (synthetic IDs
        // disappear entirely) or account-identity drift (real-borrowed
        // IDs where the only emitted account was a mock).
        await coordinator.pushCurrentSnapshot()
        let cycle2Mocks = mock.lastSnapshot?.providers
            .filter { self.isMockSnapshot($0) } ?? []
        #expect(cycle2Mocks.isEmpty)
        #expect(mock.deleteCallCount >= 1, "delete fires in cycle 2")
        let lastDeletes = mock.deletedRecordNamesAcrossCalls.last ?? []
        let mockDeletes = lastDeletes.filter { self.isMockRecordName($0) }
        // Note: codex (3 mock accounts) is the only enabled real provider
        // that wasn't disabled, so its 3 mock recordNames stay tracked
        // as drift candidates. The 29 others get delete-targeted in this
        // cycle. The remaining 3 are caught in subsequent cycles via
        // 2-cycle confirmation.
        #expect(
            mockDeletes.count >= 29,
            "≥29 mock per-account recordNames should be delete-targeted; got \(mockDeletes.count)")
    }

    @Test("MR3.5: mock providers don't disturb real provider sync (real codex coexists with mock codex)")
    func mockDoesNotDisturbRealProvider() async throws {
        self.enableMock()
        defer { self.resetActivationState() }
        let settings = self.makeSettingsStore(suite: "MR3-5-Coexist")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = self.makeUsageStore(settings: settings)

        // Real Codex active snapshot. Email uses `.example.com` (not
        // `.test`) so it's distinguishable from the 3 mock codex
        // accounts that share the same providerID.
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 30, windowMinutes: 300,
                    resetsAt: Date(), resetDescription: "test"),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "real@example.com",
                    accountOrganization: nil,
                    loginMethod: "oauth")),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(
            store: store, settings: settings, syncManager: mock,
            mockInjector: { MockProviderInjector.allMocks() })
        await coordinator.pushCurrentSnapshot()

        let allProviders = mock.lastSnapshot?.providers ?? []
        // Real codex: providerID == "codex" AND email NOT in `.test` TLD.
        let realCodex = allProviders.filter {
            $0.providerID == "codex" && !self.isMockSnapshot($0)
        }
        // Mock providers: any with `*-mock@*.test` email.
        let mockProviders = allProviders.filter { self.isMockSnapshot($0) }
        #expect(realCodex.count == 1, "real Codex still emits its 1 record")
        #expect(realCodex.first?.accountEmail == "real@example.com")
        // iOS 1.7.0: 43 → 45 (moonshot + bedrock).
        // Phase G: 45 → 52 (+7 second-tab mocks).
        #expect(mockProviders.count == 61, "61 mock providers also emit")
        // Real and mock CAN share providerID under mix design, but
        // they must NEVER share accountEmail.
        let realEmails = Set(realCodex.compactMap(\.accountEmail))
        let mockEmails = Set(mockProviders.compactMap(\.accountEmail))
        #expect(realEmails.isDisjoint(with: mockEmails))
    }

    // MARK: - MR4 Mock + real coexistence

    @Test("MR4.1: every mock providerID is in either real-borrowed or synthetic allowlist")
    func mockProviderIDsInAllowlist() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let realBorrowed = MockProviderInjector.realProviderIDsBorrowedByMocks
        let synthetic = MockProviderInjector.syntheticProviderIDs
        let allowed = realBorrowed.union(synthetic)
        let mockIDs = Set(snapshots.map(\.providerID))
        let unexpected = mockIDs.subtracting(allowed)
        #expect(
            mockIDs.isSubset(of: allowed),
            "mock providerIDs must be within real-borrowed ∪ synthetic; unexpected: \(unexpected)")
        // Real-borrowed IDs MUST also be valid UsageProvider entries —
        // otherwise we'd "borrow" a real ID that doesn't exist in the
        // provider catalog and iOS would still fall back to unknown
        // rendering (defeating the first-class rendering goal).
        let allRealIDs = Set(UsageProvider.allCases.map(\.rawValue))
        let missing = realBorrowed.subtracting(allRealIDs)
        #expect(
            realBorrowed.isSubset(of: allRealIDs),
            "real-borrowed mock IDs must exist in UsageProvider.allCases; missing: \(missing)")
    }

    @Test("MR4.2: mock per-account records have distinct CK record names")
    func mockMultiAccountRecordNamesDistinct() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        // Build composite record names like CloudSyncManager would.
        let deviceID = "test-device"
        let recordNames = snapshots.map { snap in
            CloudSyncManager.perProviderRecordName(
                deviceID: deviceID,
                providerID: snap.providerID,
                accountEmail: snap.accountEmail)
        }
        #expect(Set(recordNames).count == recordNames.count, "all 43 mock record names must be distinct")
    }

    @Test("MR4.3: mock multi-account uses accountIdentities with `{providerID}:{scheme}:{value}` schema")
    func mockMultiAccountIdentitiesAlignWithRealSchema() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        // Codex multi-account uses real `codex` providerID under mix
        // design, so the schema prefix is `codex:` not `_mock_codex_*:`.
        let codexMulti = snapshots.filter { $0.providerID == "codex" }
        for snap in codexMulti {
            let ids = snap.accountIdentities ?? []
            #expect(ids.count >= 1)
            #expect(
                ids.contains { $0.hasPrefix("codex:email:") },
                "schema must follow `{providerID}:{scheme}:{value}` with real `codex` prefix")
        }
    }

    // MARK: - MR5 Edge cases / robustness

    /// Helper: build a transient UserDefaults so we can test isEnabled
    /// with controlled state (avoids polluting the shared standard
    /// defaults across test cases).
    private func transientDefaults(setEnabled: Bool?) -> UserDefaults {
        let suiteName = "MR5-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        if let value = setEnabled {
            defaults.set(value, forKey: MockProviderInjector.userDefaultsKey)
        }
        return defaults
    }

    @Test("MR5.1: env var `1` activates (parser-level)")
    func envVarValueOneActivates() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "1"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2: env var `true` (lowercase) activates")
    func envVarValueTrueActivates() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "true"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2b: env var `TRUE` (uppercase) activates")
    func envVarValueTrueUppercaseActivates() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "TRUE"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2c: env var `yes` activates")
    func envVarValueYesActivates() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "yes"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2d: env var `0` does NOT activate")
    func envVarValueZeroDoesNotActivate() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "0"]
        #expect(!MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2e: env var arbitrary value (`maybe`) does NOT activate")
    func envVarValueArbitraryDoesNotActivate() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "maybe"]
        #expect(!MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2f: env var truthy overrides UserDefaults disabled")
    func envVarTruthyOverridesUserDefaultsDisabled() {
        let defaults = self.transientDefaults(setEnabled: false)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "1"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2g: UserDefaults true alone does NOT activate without env var (env var is hard gate)")
    func userDefaultsAloneDoesNotActivateWithoutEnvVar() {
        // Hardened in 0.23.5: env var is a hard gate. Without
        // CODEXBAR_MOCK_PROVIDERS set on launch, the entire mock
        // tooling is invisible — UserDefaults state alone cannot
        // activate mock injection. This keeps the Settings UI clean
        // for normal users while preserving the toggle for debug-mode
        // launches.
        let defaults = self.transientDefaults(setEnabled: true)
        let env: [String: String] = [:]
        #expect(!MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2h: env var present + falsy + UserDefaults true → activates (debug mode, UI toggle drives)")
    func envVarFalsyDoesNotOverrideUserDefaultsTrue() {
        // Design choice: env var presence opens debug mode. Within
        // debug mode, env var truthy short-circuits to ON; otherwise
        // UI toggle (UserDefaults) drives the runtime state. So
        // env var "0" + defaults true → debug mode + UI says on → on.
        let defaults = self.transientDefaults(setEnabled: true)
        let env = ["CODEXBAR_MOCK_PROVIDERS": "0"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("MR5.2i: env var name constant is exactly `CODEXBAR_MOCK_PROVIDERS`")
    func envVarNameIsConstant() {
        #expect(MockProviderInjector.environmentVariableName == "CODEXBAR_MOCK_PROVIDERS")
    }

    @Test("MR5.3: disabled gate always returns empty (env var absent)")
    func disabledReturnsCompletelyEmpty() {
        // Verifies the gate via the testable variant — without env
        // var, the injector reports disabled regardless of defaults
        // state. (The shape-only `allMocks()` always returns the full
        // mock set; that's tested separately.)
        let defaults = self.transientDefaults(setEnabled: true)
        let env: [String: String] = [:]
        for _ in 1...5 {
            #expect(!MockProviderInjector.isEnabled(
                environment: env, userDefaults: defaults))
        }
    }

    @Test("MR5.4: every mock snapshot has lastUpdated within reasonable window")
    func mockTimestampsAreReasonable() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let now = Date()
        for snap in snapshots {
            let delta = abs(snap.lastUpdated.timeIntervalSince(now))
            #expect(delta < 60, "lastUpdated should be within 60 seconds of now (got \(delta)s)")
        }
    }

    @Test("MR5.5: synthetic 3-lane utilization history all entries within 30 days")
    func syntheticHistoryWithin30Days() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let synth = snapshots.first { $0.providerID == "_mock_synthetic_unknown" }
        let now = Date()
        let thirtyOneDaysAgo = now.addingTimeInterval(-31 * 86400)
        for series in synth?.utilizationHistory ?? [] {
            for entry in series.entries {
                #expect(entry.capturedAt > thirtyOneDaysAgo)
                #expect(entry.capturedAt <= now.addingTimeInterval(60))
            }
        }
    }

    @Test("MR5.6: cursor fallback mock has no rate windows or cost (gracefully degraded)")
    func errorMockHasNoRateWindows() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let errMock = snapshots.first { $0.providerID == "_mock_cursor_unknown" }
        #expect(errMock?.primary == nil)
        #expect(errMock?.secondary == nil)
        #expect(errMock?.rateWindows.isEmpty == true)
        #expect(errMock?.costSummary == nil)
        #expect(errMock?.budget == nil)
    }

    @Test("MR5.7: Perplexity mock credit values are non-negative")
    func perplexityMockCreditsNonNegative() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let perp = snapshots.first { $0.providerID == "perplexity" }
        let credits = perp?.perplexityCredits
        #expect((credits?.recurringTotalCents ?? -1) >= 0)
        #expect((credits?.recurringUsedCents ?? -1) >= 0)
        #expect((credits?.promoTotalCents ?? -1) >= 0)
        #expect((credits?.promoUsedCents ?? -1) >= 0)
        #expect((credits?.purchasedTotalCents ?? -1) >= 0)
        #expect((credits?.purchasedUsedCents ?? -1) >= 0)
    }

    @Test("MR5.8: usedPercent values stay in [0, 100] range across all mocks")
    func usedPercentInRange() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        for snap in snapshots {
            for window in snap.rateWindows {
                #expect(window.usedPercent >= 0)
                #expect(window.usedPercent <= 100)
            }
            if let primary = snap.primary {
                #expect(primary.usedPercent >= 0)
                #expect(primary.usedPercent <= 100)
            }
            if let secondary = snap.secondary {
                #expect(secondary.usedPercent >= 0)
                #expect(secondary.usedPercent <= 100)
            }
        }
    }

    @Test("MR5.9: mock snapshots are valid Codable (no encoding errors)")
    func mockSnapshotsAreValidCodable() throws {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for snap in snapshots {
            let data = try encoder.encode(snap)
            #expect(!data.isEmpty)
        }
    }

    @Test("MR5.9b: at least one mock has usedPercent at 0 boundary")
    func boundaryZeroPercentExists() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let zeroBoundary = snapshots.contains { snap in
            snap.rateWindows.contains { $0.usedPercent == 0 }
                || snap.primary?.usedPercent == 0
        }
        #expect(zeroBoundary, "at least one mock should exercise the 0% boundary (per-Codex-MCP-review P2)")
    }

    @Test("MR5.9c: at least one mock has usedPercent at 100 boundary")
    func boundaryHundredPercentExists() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let hundredBoundary = snapshots.contains { snap in
            snap.rateWindows.contains { $0.usedPercent == 100 }
                || snap.primary?.usedPercent == 100
                || snap.secondary?.usedPercent == 100
        }
        #expect(hundredBoundary, "at least one mock should exercise the 100% boundary (per-Codex-MCP-review P2)")
    }

    @Test("MR5.9d: at least one mock has non-ASCII accountEmail")
    func nonASCIIEmailExists() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let nonASCII = snapshots.contains { snap in
            guard let email = snap.accountEmail else { return false }
            return !email.allSatisfy(\.isASCII)
        }
        #expect(
            nonASCII,
            "at least one mock should have a non-ASCII email to exercise UTF-8 path (per-Codex-MCP-review P2)")
    }

    @Test("MR5.9e: non-ASCII email's accountIdentities is percent-encoded NFC form")
    func nonASCIIEmailIdentityEncoded() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let cafeMock = snapshots.first { snap in
            (snap.accountEmail ?? "").contains("café")
        }
        #expect(cafeMock != nil, "café mock should exist")
        let identities = cafeMock?.accountIdentities ?? []
        let cafeIdentity = identities.first { $0.contains("caf%C3%A9") }
        #expect(
            cafeIdentity != nil,
            "non-ASCII email's accountIdentities entry must contain percent-encoded NFC bytes `caf%C3%A9`")
    }

    @Test("MR5.10: Codable round-trip preserves all critical multi-account fields")
    func codableRoundTripPreservesIdentities() throws {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for snap in snapshots {
            let data = try encoder.encode(snap)
            let decoded = try decoder.decode(
                ProviderUsageSnapshot.self, from: data)
            #expect(decoded.providerID == snap.providerID)
            #expect(decoded.accountEmail == snap.accountEmail)
            #expect(decoded.accountIdentities == snap.accountIdentities)
            #expect(decoded.isError == snap.isError)
            #expect(decoded.providerName == snap.providerName)
        }
    }

    // MARK: - MR6 Cost dashboard end-to-end (NEW for mix design)

    @Test("MR6.1: most mocks carry cost data so iPhone Cost dashboard is exercisable")
    func mostMocksCarryCostData() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let withCost = snapshots.filter { $0.costSummary != nil }
        // 61 mocks total; 9 intentionally have nil costSummary:
        // _mock_cursor_unknown (error), _mock_synthetic_unknown (budget-
        // only), antigravity-balance (preview), antigravity-team (Phase G,
        // also preview/no-billing → thirtyDayCostUSD: 0 deliberately;
        // makeSimpleProviderMock skips cost when 0/0), ollama (local),
        // elevenlabs (v0.27.0, character-credit subscription with
        // $0/$0 cost — usage is character count, not USD spend), and the
        // 3 v0.28+v0.29 providers azureopenai / alibabatokenplan / t3chat
        // (quota/subscription based, no USD spend).
        // Remaining 52 carry cost data.
        #expect(withCost.count == 52, "expected 52 mocks with cost data; got \(withCost.count)")
    }

    @Test("MR6.2: aggregate 30-day mock cost is realistic-heavy but bounded (no skew explosion)")
    func aggregate30DayCostIsBounded() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let total = snapshots
            .compactMap(\.costSummary)
            .compactMap(\.last30DaysCostUSD)
            .reduce(0, +)
        // iOS 1.9.0: a few headline providers (cursor / gemini / factory) +
        // Codex Alice now carry realistic heavy spend so the CWL ledger + Cost
        // dashboard are testable at scale; the old <$180 invariant is lifted.
        #expect(total > 1000, "aggregate must be visible enough to test the dashboard at scale")
        #expect(total < 15000, "aggregate must stay bounded (no runaway skew)")
    }

    @Test("MR6.3: mocks carry a multi-week daily breakdown for chart + CWL testing")
    func atLeastOneMockHasDailyBreakdown() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let withDaily = snapshots
            .compactMap(\.costSummary)
            .filter { $0.daily.count >= 30 }
        // iOS 1.9.0: every cost-bearing mock now synthesizes ~55 days of daily
        // data (not just Codex Alice), so the CWL ledger is populated broadly.
        #expect(withDaily.count >= 10, "many mocks must carry a daily breakdown for chart + CWL")
    }

    @Test("MR6.4: every daily point in the 30-day breakdown has model breakdowns (for pie chart)")
    func dailyBreakdownHasModelLabels() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let dailyCosts = snapshots
            .compactMap(\.costSummary)
            .flatMap(\.daily)
        for point in dailyCosts {
            #expect(!point.modelBreakdowns.isEmpty, "daily \(point.dayKey) must have model breakdowns")
            // Ensure breakdowns sum approximately to the day's total
            // (within rounding tolerance — small floating-point drift OK).
            let breakdownSum = point.modelBreakdowns.reduce(0.0) { $0 + $1.costUSD }
            let drift = abs(breakdownSum - point.costUSD)
            #expect(
                drift < 0.01,
                "model breakdowns sum (\(breakdownSum)) must match dayTotal (\(point.costUSD)) within $0.01")
        }
    }

    @Test("MR6.5: cost data sums match top-level last30DaysCostUSD (for any mock that has both)")
    func costSumMatchesAggregate() {
        self.enableMock()
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        for snap in snapshots {
            guard let cost = snap.costSummary,
                  let total = cost.last30DaysCostUSD,
                  cost.daily.count >= 30 else { continue }
            // last30DaysCostUSD is anchored to the trailing 30 days of the
            // (now ~55-day) synthetic history, so compare against that slice.
            let dailySum = cost.daily.suffix(30).reduce(0.0) { $0 + $1.costUSD }
            let drift = abs(dailySum - total)
            #expect(drift < 0.01, "trailing-30 daily sum (\(dailySum)) must match last30DaysCostUSD (\(total))")
        }
    }
}

// swiftlint:enable multiline_arguments
