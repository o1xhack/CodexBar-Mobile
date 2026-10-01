import CodexBarSync
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct SyncV070PartialHistoryTests {
    @Test(arguments: [CostReportingPeriod.rolling(days: 30), .monthToDate, .allTime])
    func `partial scans remain lower bounds on old and new mobile wire surfaces`(
        period: CostReportingPeriod) async throws
    {
        let settings = testSettingsStore(
            suiteName: "SyncV070PartialHistoryTests",
            userDefaults: InMemoryUserDefaults(),
            keychainAccessPolicy: .init(setDisabled: { _ in }, isExplicitlyDisabled: { false }))
        settings.iCloudSyncEnabled = true
        settings.costUsageEnabled = true
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(
                homeDirectory: "/nonexistent", cacheTTL: 0, fileExists: { _ in false }, directoryContents: { _ in [] }),
            settings: settings, startupBehavior: .testing, environmentBase: [:])
        let updatedAt = Date(timeIntervalSince1970: 1_791_020_400)
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, updatedAt: updatedAt),
            provider: .codex)
        var tokens = CostUsageTokenSnapshot(
            sessionTokens: 12, sessionCostUSD: 1,
            last30DaysTokens: 12, last30DaysCostUSD: 1,
            historyCoverageIsEstablished: true, historyScanIsPartial: true,
            daily: [.init(
                date: "2026-10-02",
                inputTokens: 6,
                outputTokens: 6,
                totalTokens: 12,
                costUSD: 1,
                modelsUsed: nil,
                modelBreakdowns: nil)],
            bucketTimeZoneIdentifier: "UTC", updatedAt: updatedAt)
        tokens.reportingPeriod = period
        store._setTokenSnapshotForTesting(tokens, provider: .codex)
        let pusher = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: pusher)
        await coordinator.pushCurrentSnapshot()
        let summary = try #require(pusher.lastSnapshot?.providers.first?.costSummary)
        #expect(summary.historyCoverageIsEstablished == false)
        if period != .rolling(days: 30) {
            #expect(summary.reportingPeriodSummary?.historyCoverageIsEstablished == false)
        }
        let encoder = CloudSyncConstants.makeJSONEncoder()
        let decoder = CloudSyncConstants.makeJSONDecoder()
        let wire = try decoder.decode(SyncCostSummary.self, from: encoder.encode(summary))
        #expect(wire.reportingPeriodHistoryCoverageIsEstablished == false)
    }
}
