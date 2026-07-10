// swiftlint:disable multiline_arguments
//
// Scoped to this file: synthetic Codable fixtures pack trailing values
// onto single lines for readability. Re-enabled at EOF.
import Foundation
import Testing
@testable import CodexBarSync

/// Codable round-trip + cross-version compat for the v0.30/v0.31 sync (025)
/// `SyncDeepSeekUsage` envelope. Pins the four device-mix scenarios from
/// Research/025 §03 at the wire level:
///   - S1 full round-trip without loss.
///   - S3 (old Mac → new iOS): a payload WITHOUT `deepSeekUsage` decodes →
///     the field lands as nil, generic fallback.
///   - S2 (new Mac → old iOS): a payload WITH `deepSeekUsage` + an unknown
///     future key decodes on a reader that ignores them — no throw.
///   - free-tier: missing optional balance/daily keys degrade silently.
@Suite("v0.30 DeepSeek envelope — Codable round-trip + cross-version compat")
struct V030SnapshotsCodableTests {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static func sampleUsage() -> SyncDeepSeekUsage {
        SyncDeepSeekUsage(
            todayTokens: 1_250_000, monthTokens: 28_400_000,
            todayCost: 0.42, monthCost: 9.85,
            todayRequests: 312, monthRequests: 7240,
            topModel: "deepseek-chat", currency: "USD",
            totalBalanceUSD: 12.5, grantedBalanceUSD: 5.0, toppedUpBalanceUSD: 7.5,
            daily: [
                SyncDeepSeekDaily(dayKey: "2025-11-01", totalTokens: 1_400_000, cost: 0.30, requestCount: 240),
                SyncDeepSeekDaily(dayKey: "2025-11-02", totalTokens: 1_490_000, cost: 0.33, requestCount: 252),
            ],
            updatedAt: self.now)
    }

    // MARK: - S1 — full round-trip

    @Test
    func `SyncDeepSeekUsage round-trips with all fields`() throws {
        let source = Self.sampleUsage()
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(SyncDeepSeekUsage.self, from: data)
        #expect(decoded == source)
        #expect(decoded.todayTokens == 1_250_000)
        #expect(decoded.monthCost == 9.85)
        #expect(decoded.todayRequests == 312)
        #expect(decoded.topModel == "deepseek-chat")
        #expect(decoded.daily.count == 2)
        #expect(decoded.daily.first?.dayKey == "2025-11-01")
    }

    // MARK: - free-tier — missing optional keys degrade silently

    @Test
    func `SyncDeepSeekUsage decodes with optional balance/daily/cost omitted`() throws {
        // Only the always-present counters + updatedAt; no costs, no balances,
        // no daily, no currency.
        let json = """
        {"todayTokens": 10, "monthTokens": 200, "todayRequests": 3,
         "monthRequests": 40, "updatedAt": "2023-11-14T22:13:20Z"}
        """
        let decoded = try Self.decoder.decode(SyncDeepSeekUsage.self, from: Data(json.utf8))
        #expect(decoded.todayTokens == 10)
        #expect(decoded.todayCost == nil)
        #expect(decoded.totalBalanceUSD == nil)
        #expect(decoded.daily.isEmpty)
        #expect(decoded.currency == "USD") // decoder default
    }

    // MARK: - S1 — envelope carries the field through ProviderUsageSnapshot

    @Test
    func `ProviderUsageSnapshot carries deepSeekUsage through round-trip`() throws {
        let snap = ProviderUsageSnapshot(
            providerID: "deepseek", providerName: "DeepSeek",
            primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil,
            isError: false, lastUpdated: Self.now,
            deepSeekUsage: Self.sampleUsage())
        let data = try Self.encoder.encode(snap)
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: data)
        #expect(decoded.deepSeekUsage?.monthRequests == 7240)
        #expect(decoded.deepSeekUsage?.daily.count == 2)
    }

    // MARK: - S3 — old Mac payload (no deepSeekUsage) → new reader = nil

    @Test
    func `Old payload without deepSeekUsage decodes to nil (backward compat)`() throws {
        let json = """
        {"providerID": "deepseek", "providerName": "DeepSeek",
         "isError": false, "lastUpdated": "2023-11-14T22:13:20Z"}
        """
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.deepSeekUsage == nil)
        #expect(decoded.providerID == "deepseek")
        #expect(decoded.rateWindows.isEmpty)
    }

    // MARK: - S2 dual — payload with an unknown future key does not throw

    @Test
    func `Payload with deepSeekUsage + unknown future key decodes (forward compat)`() throws {
        let json = """
        {"providerID": "deepseek", "providerName": "DeepSeek",
         "isError": false, "lastUpdated": "2023-11-14T22:13:20Z",
         "deepSeekUsage": {"todayTokens": 1, "monthTokens": 2, "todayRequests": 3,
           "monthRequests": 4, "currency": "USD", "updatedAt": "2023-11-14T22:13:20Z"},
         "someFutureField_v999": {"nested": [1, 2, 3]}}
        """
        let decoded = try Self.decoder.decode(ProviderUsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.deepSeekUsage?.todayTokens == 1)
    }

    // MARK: - #1163 request counts + currency on SyncCostSummary

    @Test
    func `SyncCostSummary round-trips with request counts + currency`() throws {
        let source = SyncCostSummary(
            sessionCostUSD: 1.0, sessionTokens: 1000,
            last30DaysCostUSD: 28.9, last30DaysTokens: 1_200_000,
            daily: [],
            sessionRequests: 42, last30DaysRequests: 7240, currencyCode: "EUR")
        let data = try Self.encoder.encode(source)
        let decoded = try Self.decoder.decode(SyncCostSummary.self, from: data)
        #expect(decoded.sessionRequests == 42)
        #expect(decoded.last30DaysRequests == 7240)
        #expect(decoded.currencyCode == "EUR")
    }

    @Test
    func `Old SyncCostSummary payload without request counts decodes to nil`() throws {
        let json = """
        {"sessionCostUSD": 1.0, "sessionTokens": 1000, "last30DaysCostUSD": 28.9,
         "last30DaysTokens": 1200000, "daily": []}
        """
        let decoded = try Self.decoder.decode(SyncCostSummary.self, from: Data(json.utf8))
        #expect(decoded.last30DaysRequests == nil)
        #expect(decoded.currencyCode == nil)
        #expect(decoded.last30DaysCostUSD == 28.9)
    }
}

// swiftlint:enable multiline_arguments
