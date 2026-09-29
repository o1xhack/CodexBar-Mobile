import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Tests for iOS 1.6.0 / Mac 0.25.2 quota warning wire sync.
/// See Research/020-multi-account-comprehensive.md §R7.4.
@Suite("SyncQuotaWarningConfig + ProviderUsageSnapshot plumbing")
struct SyncQuotaWarningConfigTests {
    // MARK: - SyncQuotaWarningConfig basics

    @Test("macDefaults matches Mac's documented [50, 20] threshold")
    func macDefaultsConstant() {
        #expect(SyncQuotaWarningConfig.macDefaults == [50, 20])
    }

    @Test("resolvedSessionThresholds returns Mac defaults when nil")
    func resolvedSessionFallback() {
        let config = SyncQuotaWarningConfig()
        #expect(config.resolvedSessionThresholds() == [50, 20])
    }

    @Test("resolvedWeeklyThresholds returns Mac defaults when nil")
    func resolvedWeeklyFallback() {
        let config = SyncQuotaWarningConfig()
        #expect(config.resolvedWeeklyThresholds() == [50, 20])
    }

    @Test("resolvedSessionThresholds returns the override when set")
    func resolvedSessionOverride() {
        let config = SyncQuotaWarningConfig(sessionThresholds: [80, 30, 10])
        // Sorted descending defensively.
        #expect(config.resolvedSessionThresholds() == [80, 30, 10])
    }

    @Test("empty array is treated as missing → defaults")
    func resolvedEmptyArrayFallback() {
        let config = SyncQuotaWarningConfig(sessionThresholds: [], weeklyThresholds: [])
        #expect(config.resolvedSessionThresholds() == [50, 20])
        #expect(config.resolvedWeeklyThresholds() == [50, 20])
    }

    @Test("Out-of-range thresholds are clamped to [0, 99]")
    func clampsOutOfRange() {
        let config = SyncQuotaWarningConfig(sessionThresholds: [150, -5, 50])
        // 150 → 99, -5 → 0, 50 → 50 — then deduped + sorted desc.
        let result = config.resolvedSessionThresholds()
        #expect(result.contains(99))
        #expect(result.contains(50))
        #expect(result.contains(0))
        // Sorted descending.
        #expect(result == result.sorted(by: >))
    }

    @Test("Duplicate thresholds collapse")
    func dedupes() {
        let config = SyncQuotaWarningConfig(sessionThresholds: [50, 50, 50, 20, 20])
        #expect(config.resolvedSessionThresholds().count == 2)
    }

    @Test("Enabled flags default to true when missing")
    func enabledDefaultsTrue() {
        let config = SyncQuotaWarningConfig()
        #expect(config.resolvedSessionEnabled() == true)
        #expect(config.resolvedWeeklyEnabled() == true)
    }

    @Test("Enabled flag honors explicit false")
    func enabledExplicitFalse() {
        let config = SyncQuotaWarningConfig(
            sessionEnabled: false,
            weeklyEnabled: false)
        #expect(config.resolvedSessionEnabled() == false)
        #expect(config.resolvedWeeklyEnabled() == false)
    }

    // MARK: - Codable round-trip

    @Test("Codable round-trip preserves all four fields")
    func codableRoundTrip() throws {
        let original = SyncQuotaWarningConfig(
            sessionThresholds: [80, 50, 20],
            sessionEnabled: true,
            weeklyThresholds: [70, 30],
            weeklyEnabled: false)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SyncQuotaWarningConfig.self, from: data)

        #expect(decoded.sessionThresholds == [80, 50, 20])
        #expect(decoded.sessionEnabled == true)
        #expect(decoded.weeklyThresholds == [70, 30])
        #expect(decoded.weeklyEnabled == false)
    }

    @Test("Codable decodes missing fields as nil (backward compat)")
    func codableMissingFields() throws {
        // Empty JSON object — simulates an old Mac that wrote
        // a config with all-defaults.
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SyncQuotaWarningConfig.self, from: json)
        #expect(decoded.sessionThresholds == nil)
        #expect(decoded.weeklyThresholds == nil)
        #expect(decoded.sessionEnabled == nil)
        #expect(decoded.weeklyEnabled == nil)
        // Resolution still produces Mac defaults.
        #expect(decoded.resolvedSessionThresholds() == [50, 20])
        #expect(decoded.resolvedWeeklyThresholds() == [50, 20])
        #expect(decoded.resolvedSessionEnabled() == true)
    }

    // MARK: - ProviderUsageSnapshot wire compat

    @Test("Snapshot decodes pre-1.6.0 JSON (no quotaWarnings field)")
    func snapshotBackwardCompat() throws {
        // Simulate a JSON envelope from Mac pre-0.25.2 — the field
        // doesn't appear at all in the payload.
        let oldJSON = """
        {
            "providerID": "claude",
            "providerName": "Claude",
            "isError": false,
            "lastUpdated": 1700000000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(ProviderUsageSnapshot.self, from: oldJSON)
        #expect(snapshot.providerID == "claude")
        #expect(snapshot.quotaWarnings == nil)
    }

    @Test("Snapshot round-trip preserves quotaWarnings")
    func snapshotWithQuotaRoundTrip() throws {
        let warnings = SyncQuotaWarningConfig(
            sessionThresholds: [60, 25],
            sessionEnabled: true,
            weeklyThresholds: [70, 30],
            weeklyEnabled: true)
        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            quotaWarnings: warnings)

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderUsageSnapshot.self, from: data)

        #expect(decoded.quotaWarnings?.sessionThresholds == [60, 25])
        #expect(decoded.quotaWarnings?.weeklyEnabled == true)
    }

    @Test("`with(quotaWarnings:)` keeps all other fields intact")
    func withQuotaWarningsPreservesOtherFields() {
        let original = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: SyncRateWindow(usedPercent: 25, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: "ChatGPT",
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000))

        let enriched = original.with(
            quotaWarnings: SyncQuotaWarningConfig(sessionThresholds: [40]))

        #expect(enriched.providerID == original.providerID)
        #expect(enriched.providerName == original.providerName)
        #expect(enriched.primary?.usedPercent == 25)
        #expect(enriched.accountEmail == "user@example.com")
        #expect(enriched.loginMethod == "ChatGPT")
        #expect(enriched.quotaWarnings?.sessionThresholds == [40])
    }

    // MARK: - Per-window helper

    @Test("quotaWarning(forWindowIndex:) returns session config at index 0")
    func windowHelperSession() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: SyncQuotaWarningConfig(
                sessionThresholds: [70, 40],
                weeklyThresholds: [55, 15]))
        let result = snapshot.quotaWarning(forWindowIndex: 0)
        #expect(result.thresholds == [70, 40])
        #expect(result.enabled == true)
    }

    @Test("quotaWarning(forWindowIndex:) returns weekly config at index 1")
    func windowHelperWeekly() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: SyncQuotaWarningConfig(
                sessionThresholds: [70, 40],
                weeklyThresholds: [55, 15],
                weeklyEnabled: false))
        let result = snapshot.quotaWarning(forWindowIndex: 1)
        #expect(result.thresholds == [55, 15])
        #expect(result.enabled == false)
    }

    @Test("quotaWarning(forWindowIndex:) returns disabled for extra windows")
    func windowHelperExtraWindow() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "perplexity",
            providerName: "Perplexity",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: SyncQuotaWarningConfig(sessionThresholds: [50]))
        let result = snapshot.quotaWarning(forWindowIndex: 2)
        #expect(result.thresholds == nil)
        #expect(result.enabled == false)
    }

    @Test("period metadata routes xKiro daily windows to session controls")
    func dailyPeriodUsesSessionControls() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "xkiro",
            providerName: "xKiro",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: SyncQuotaWarningConfig(
                sessionThresholds: [75],
                sessionEnabled: false,
                weeklyThresholds: [35],
                weeklyEnabled: true))

        let result = snapshot.quotaWarning(forWindowIndex: 0, period: .daily)

        #expect(result.thresholds == [75])
        #expect(result.enabled == false)
    }

    @Test("Aixy budget periods route promoted and named windows to matching controls")
    func aixyPeriodsUseMatchingControls() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "aixy",
            providerName: "Aixy",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: SyncQuotaWarningConfig(
                sessionThresholds: [75],
                weeklyThresholds: [35]))

        let daily = snapshot.quotaWarning(forWindowIndex: 0, windowID: "aixy-daily", period: .daily)
        let monthly = snapshot.quotaWarning(forWindowIndex: 1, windowID: "aixy-monthly", period: .monthly)
        let lifetime = snapshot.quotaWarning(forWindowIndex: 2, windowID: "aixy-lifetime", period: .lifetime)

        #expect(daily.thresholds == [75])
        #expect(monthly.thresholds == [35])
        #expect(lifetime.thresholds == [35])
        #expect(daily.enabled && monthly.enabled && lifetime.enabled)
    }

    @Test("unsupported extra period keeps markers disabled")
    func unsupportedExtraPeriodRemainsDisabled() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "grok",
            providerName: "Grok",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: SyncQuotaWarningConfig(sessionThresholds: [50]))

        let result = snapshot.quotaWarning(forWindowIndex: 2, windowID: "extra", period: .daily)

        #expect(result.thresholds == nil)
        #expect(result.enabled == false)
    }

    @Test("nil quotaWarnings falls back to Mac defaults — never empty render")
    func windowHelperNilFallback() {
        let snapshot = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            quotaWarnings: nil)
        let session = snapshot.quotaWarning(forWindowIndex: 0)
        let weekly = snapshot.quotaWarning(forWindowIndex: 1)
        #expect(session.thresholds == [50, 20])
        #expect(weekly.thresholds == [50, 20])
        #expect(session.enabled == true)
        #expect(weekly.enabled == true)
    }
}
