import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// Unit tests for `MockProviderInjector` — the debug-only synthetic
/// provider data injector used for end-to-end iCloud sync testing
/// without real provider subscriptions.
///
/// See `Research/020-multi-account-comprehensive.md` (mock injection)
/// and `MockProviderInjector.swift` for activation details.
@MainActor
@Suite(.serialized)
struct MockProviderInjectorTests {
    /// Reset UserDefaults flag and env var before each test to avoid
    /// state leaking across cases.
    private func resetActivationState() {
        UserDefaults.standard.removeObject(
            forKey: MockProviderInjector.userDefaultsKey)
        // Env vars can't be unset from inside a process directly, but
        // since each test process inherits the launch env they should
        // not have CODEXBAR_MOCK_PROVIDERS set unless someone explicitly
        // exported it before running tests. We assume clean env.
    }

    @Test("Disabled by default — env var absent")
    func defaultIsDisabled() {
        // Test process inherits a clean env without
        // CODEXBAR_MOCK_PROVIDERS, so the real isEnabled gate fires
        // and reports false. (allMocks() is shape-only and always
        // returns the full set — that's covered by other tests.)
        self.resetActivationState()
        #expect(!MockProviderInjector.isEnabled)
    }

    @Test("Env var truthy + defaults true → activates")
    func envVarTruthyActivates() {
        // Hardened in 0.23.5: env var is the gate. Verify via the
        // testable variant since env vars cannot be mutated from
        // inside a running process.
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: MockProviderInjector.userDefaultsKey)
        defer {
            defaults.removeObject(forKey: MockProviderInjector.userDefaultsKey)
        }
        let env = ["CODEXBAR_MOCK_PROVIDERS": "1"]
        #expect(MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
        // Phase G adds 7 multi-account second-tab simple mocks
        // (openai/deepseek/antigravity/manus/copilot/venice/stepfun) so
        // iOS multi-account tab UI is exercised end-to-end. 45 → 52.
        // iOS 1.8.0 adds 5 v0.27.0 provider simple mocks
        // (grok/groq/elevenlabs/deepgram/llmproxy). 52 → 57.
        // iOS 1.9.0 adds 3 v0.28+v0.29 provider simple mocks
        // (azureopenai/alibabatokenplan/t3chat). 57 → 60.
        // iOS 1.12.0 adds Devin. 60 → 61.
        // iOS 1.13.0 adds LiteLLM, Poe, Chutes, and Zed. 61 → 65.
        #expect(
            MockProviderInjector.allMocks().count == 65,
            "iOS 1.13.0: 61 → 65 (+LiteLLM/Poe/Chutes/Zed simple mocks).")
    }

    @Test("UserDefaults true alone (no env var) → disabled")
    func userDefaultsAloneDisabled() {
        // Env var is required. UserDefaults state alone cannot
        // activate mock injection — keeps the Settings UI clean for
        // normal users.
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: MockProviderInjector.userDefaultsKey)
        defer {
            defaults.removeObject(forKey: MockProviderInjector.userDefaultsKey)
        }
        let env: [String: String] = [:]
        #expect(!MockProviderInjector.isEnabled(
            environment: env, userDefaults: defaults))
    }

    @Test("Mock providerIDs are split: real-borrowed (for first-class iOS UI) + `_mock_*` (for fallback test)")
    func mockProviderIDsSplitRealAndSynthetic() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        #expect(!snapshots.isEmpty)
        let realBorrowed = MockProviderInjector.realProviderIDsBorrowedByMocks
        let synthetic = MockProviderInjector.syntheticProviderIDs
        for snap in snapshots {
            let id = snap.providerID
            let isAllowed = realBorrowed.contains(id) || synthetic.contains(id)
            #expect(isAllowed, "mock providerID must be in real-borrowed or synthetic allowlist; got \(id)")
        }
    }

    @Test("Synthetic providerIDs are exactly `_mock_*` prefixed (mock-only namespace)")
    func syntheticIDsArePrefixed() {
        for id in MockProviderInjector.syntheticProviderIDs {
            #expect(id.hasPrefix("_mock_"), "synthetic mock providerID must use `_mock_` prefix; got \(id)")
            #expect(id != "_mock_", "synthetic providerID must have non-empty suffix")
        }
    }

    @Test("All mock account emails use `.test` TLD (RFC 6761 reserved)")
    func allMockEmailsAreReservedTLD() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let accountedEmails = snapshots.compactMap(\.accountEmail)
        #expect(!accountedEmails.isEmpty)
        for email in accountedEmails {
            #expect(
                email.hasSuffix(MockProviderInjector.mockEmailTLD),
                "mock email must use `.test` TLD (RFC 6761 reserved); got: \(email)")
        }
    }

    @Test("Codex (real ID) mock has 3 distinct accounts on `codex` providerID")
    func codexMockHas3DistinctAccounts() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let codexEntries = snapshots.filter { $0.providerID == "codex" }
        #expect(codexEntries.count == 3, "3 Codex mocks on real `codex` providerID")
        let emails = Set(codexEntries.compactMap(\.accountEmail))
        #expect(emails.count == 3, "all 3 Codex mocks must have distinct emails")
        for email in emails {
            #expect(email.hasSuffix(".test"), "all 3 Codex mock emails must use .test TLD; got \(email)")
        }
    }

    @Test("Claude (real ID) mock has 2 distinct accounts on `claude` providerID")
    func claudeMockHas2DistinctAccounts() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let claudeEntries = snapshots.filter { $0.providerID == "claude" }
        #expect(claudeEntries.count == 2)
        let emails = Set(claudeEntries.compactMap(\.accountEmail))
        #expect(emails.count == 2)
    }

    @Test("Perplexity (real ID) mock has structured credit breakdown on `perplexity` providerID")
    func perplexityMockHasCreditBreakdown() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let perplexity = snapshots.first { $0.providerID == "perplexity" }
        #expect(perplexity != nil)
        let credits = perplexity?.perplexityCredits
        #expect(credits != nil, "Perplexity mock must populate perplexityCredits")
        #expect(credits?.recurringTotalCents == 50000)
        #expect(credits?.promoTotalCents == 10000)
        #expect(credits?.purchasedTotalCents == 25000)
        #expect(credits?.planName == "Pro")
    }

    @Test("Cursor fallback mock has isError + statusMessage on `_mock_cursor_unknown` providerID")
    func cursorErrorMockHasErrorState() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let errorMock = snapshots.first { $0.providerID == "_mock_cursor_unknown" }
        #expect(errorMock != nil)
        #expect(errorMock?.isError == true)
        #expect(errorMock?.statusMessage != nil)
        #expect(errorMock?.statusMessage?.contains("Mock") == true)
    }

    @Test("Synthetic fallback mock has 3 rate windows + 30-day utilization history")
    func syntheticMockHas3LanesAndHistory() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let synthetic = snapshots.first { $0.providerID == "_mock_synthetic_unknown" }
        #expect(synthetic != nil)
        #expect(synthetic?.rateWindows.count == 3, "3 lanes: 5h, weekly, search")
        #expect(synthetic?.utilizationHistory?.count == 3, "3 utilization series")
        let history = synthetic?.utilizationHistory ?? []
        for series in history {
            #expect(series.entries.count == 30, "30 days of history entries")
        }
        #expect(synthetic?.budget != nil, "Synthetic mock has a budget snapshot")
    }

    @Test("Mock data round-trips through JSON encoding")
    func mockDataRoundTripsJSON() throws {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
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
            #expect(decoded.providerName == snap.providerName)
            #expect(decoded.accountEmail == snap.accountEmail)
        }
    }

    @Test("All mock snapshots have non-empty accountIdentities (except cursor fallback)")
    func mockSnapshotsHaveAccountIdentities() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        // All mocks except the cursor error mock (which intentionally
        // sets accountIdentities to nil — exercises the legacy
        // per-device bucket fallback). The cursor error mock still has
        // a non-nil accountEmail so iOS shows it via fallback rendering;
        // only the cross-Mac merge identifier is intentionally missing.
        let mocksWithIdentities = snapshots.filter {
            $0.providerID != "_mock_cursor_unknown"
        }
        for snap in mocksWithIdentities {
            #expect(
                (snap.accountIdentities?.count ?? 0) >= 1,
                "\(snap.providerID) should have ≥1 accountIdentities entry for cross-Mac merge")
        }
    }

    @Test("Most real-borrowed mocks include cost data so iPhone Cost dashboard is exercisable")
    func realBorrowedMocksHaveCostData() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let realBorrowed = MockProviderInjector.realProviderIDsBorrowedByMocks
        let realBorrowedSnapshots = snapshots.filter { realBorrowed.contains($0.providerID) }
        let withCost = realBorrowedSnapshots.filter { $0.costSummary != nil }
        // Real-borrowed mocks must mostly carry cost data; the
        // intentionally cost-less mocks are:
        //   - antigravity (preview / no-billing)
        //   - ollama (local inference, no cost)
        //   - elevenlabs (v0.27.0, character-credit subscription —
        //     usage is character allowance, not USD spend)
        //   - azureopenai (v0.28.0, deployment-status usage, no USD)
        //   - alibabatokenplan (v0.29.0, token-plan credit quota, no USD)
        //   - t3chat (v0.28.0, web-session subscription %, no USD)
        //   - poe (v0.36.1, points/subscription usage, no USD)
        let costLessIDs = realBorrowedSnapshots
            .filter { $0.costSummary == nil }
            .map(\.providerID)
        #expect(
            Set(costLessIDs).isSubset(of: [
                "antigravity", "ollama", "elevenlabs",
                "azureopenai", "alibabatokenplan", "t3chat",
                "poe",
            ]),
            "only the known credit/subscription mocks may be cost-less; got \(costLessIDs)")
        #expect(withCost.count >= 25, "≥25 real-borrowed mocks must carry cost data; got \(withCost.count)")
    }

    @Test("Codex Alice mock has 30-day daily breakdown so per-day chart is exercisable")
    func codexAliceHasDailyBreakdown() {
        self.resetActivationState()
        UserDefaults.standard.set(
            true, forKey: MockProviderInjector.userDefaultsKey)
        defer { self.resetActivationState() }
        let snapshots = MockProviderInjector.allMocks()
        let alice = snapshots.first { snap in
            snap.providerID == "codex"
                && (snap.accountEmail ?? "").contains("café")
        }
        #expect(alice != nil, "Alice mock should exist with non-ASCII café email")
        let daily = alice?.costSummary?.daily ?? []
        #expect(daily.count == 55, "Alice carries 55 days of daily cost points")
        let total = daily.reduce(0.0) { $0 + $1.costUSD }
        #expect(total > 0, "daily totals must sum to a positive value")
        for point in daily {
            #expect(!point.modelBreakdowns.isEmpty, "every daily point should have a model breakdown")
        }
    }
}
