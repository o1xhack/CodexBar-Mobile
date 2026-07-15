import CodexBarCore
import CodexBarSync
import Foundation
import Testing
@testable import CodexBar

/// Wire-format and aggregation tests for the new `isEstimated: Bool?`
/// field on `SyncCostBreakdown` / `SyncDailyPoint` / `SyncCostSummary`.
///
/// **Why this matters in two directions:**
/// 1. Old Mac (≤ 0.20.x) → new iOS: payloads have no `isEstimated` key.
///    Decoder must accept and resolve to `nil`. Otherwise every old user
///    sees their `daily` history blank-out on first iOS upgrade.
/// 2. New Mac (≥ 0.23) → old iOS: payloads include `isEstimated`. Old
///    iOS's strict synthesized decoder ignores unknown keys (default
///    behavior). The Build 79 forward-compat invariant covers this for
///    sibling fields and we trust it here.
@MainActor
@Suite("SyncCost isEstimated wire format + aggregation")
struct SyncCostIsEstimatedTests {
    // MARK: - SyncCostBreakdown wire format

    @Test
    func `SyncCostBreakdown decodes old payload (no isEstimated key) as nil`() throws {
        let json = Data("""
        { "label": "claude-opus-4-7", "costUSD": 0.0075 }
        """.utf8)
        let decoded = try JSONDecoder().decode(SyncCostBreakdown.self, from: json)
        #expect(decoded.label == "claude-opus-4-7")
        #expect(decoded.costUSD == 0.0075)
        #expect(decoded.isEstimated == nil)
    }

    @Test
    func `SyncCostBreakdown decodes new payload with isEstimated=true`() throws {
        let json = Data("""
        { "label": "claude-opus-4-99", "costUSD": 0.0075, "isEstimated": true }
        """.utf8)
        let decoded = try JSONDecoder().decode(SyncCostBreakdown.self, from: json)
        #expect(decoded.isEstimated == true)
    }

    @Test
    func `SyncCostBreakdown roundtrips isEstimated=true through encoder`() throws {
        let original = SyncCostBreakdown(label: "x", costUSD: 1.0, isEstimated: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncCostBreakdown.self, from: data)
        #expect(decoded == original)
        #expect(decoded.isEstimated == true)
    }

    @Test
    func `SyncCostBreakdown roundtrips nil isEstimated as nil`() throws {
        let original = SyncCostBreakdown(label: "x", costUSD: 1.0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncCostBreakdown.self, from: data)
        #expect(decoded.isEstimated == nil)
    }

    // MARK: - SyncDailyPoint wire format

    @Test
    func `SyncDailyPoint decodes old payload (no isEstimated key) as nil`() throws {
        let json = Data("""
        {
            "dayKey": "2026-04-27", "costUSD": 1.5, "totalTokens": 1000
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(SyncDailyPoint.self, from: json)
        #expect(decoded.dayKey == "2026-04-27")
        #expect(decoded.isEstimated == nil)
        #expect(decoded.modelBreakdowns.isEmpty)
        #expect(decoded.serviceBreakdowns.isEmpty)
    }

    @Test
    func `SyncDailyPoint decodes new payload with isEstimated=true`() throws {
        let json = Data("""
        {
            "dayKey": "2026-04-27", "costUSD": 1.5, "totalTokens": 1000,
            "modelBreakdowns": [], "serviceBreakdowns": [],
            "isEstimated": true
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(SyncDailyPoint.self, from: json)
        #expect(decoded.isEstimated == true)
    }

    // MARK: - SyncCostSummary wire format

    @Test
    func `SyncCostSummary decodes old payload (no isEstimated key) as nil`() throws {
        let json = Data("""
        {
            "sessionCostUSD": null, "sessionTokens": null,
            "last30DaysCostUSD": 1.0, "last30DaysTokens": 100,
            "daily": []
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(SyncCostSummary.self, from: json)
        #expect(decoded.last30DaysCostUSD == 1.0)
        #expect(decoded.isEstimated == nil)
    }

    @Test
    func `SyncCostSummary roundtrips isEstimated=true`() throws {
        let original = SyncCostSummary(
            sessionCostUSD: nil,
            sessionTokens: nil,
            last30DaysCostUSD: 1.0,
            last30DaysTokens: 100,
            daily: [],
            isEstimated: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncCostSummary.self, from: data)
        #expect(decoded.isEstimated == true)
    }

    // MARK: - SyncCostBreakdown standard/fast split (#1070)

    @Test
    func `SyncCostBreakdown decodes old payload (no split keys) as nil split`() throws {
        let json = Data("""
        { "label": "gpt-5.5", "costUSD": 1.0 }
        """.utf8)
        let decoded = try JSONDecoder().decode(SyncCostBreakdown.self, from: json)
        #expect(decoded.standardCostUSD == nil)
        #expect(decoded.priorityCostUSD == nil)
        #expect(decoded.standardTokens == nil)
        #expect(decoded.priorityTokens == nil)
    }

    @Test
    func `SyncCostBreakdown roundtrips the Codex standard/fast split`() throws {
        let original = SyncCostBreakdown(
            label: "gpt-5.5",
            costUSD: 1.0,
            isEstimated: nil,
            standardCostUSD: 0.8,
            priorityCostUSD: 0.2,
            standardTokens: 800,
            priorityTokens: 200)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncCostBreakdown.self, from: data)
        #expect(decoded == original)
        #expect(decoded.standardCostUSD == 0.8)
        #expect(decoded.priorityCostUSD == 0.2)
        #expect(decoded.standardTokens == 800)
        #expect(decoded.priorityTokens == 200)
    }

    @Test
    func `SyncCoordinator carries the Codex standard/fast split into the envelope (#1070)`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-codex-split")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .codex,
            metadata: #require(ProviderDefaults.metadata[.codex]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 10, windowMinutes: 60, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .codex)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 1000,
                sessionCostUSD: 0.5,
                last30DaysTokens: 10000,
                last30DaysCostUSD: 5.0,
                daily: [
                    CostUsageDailyReport.Entry(
                        date: "2026-05-26",
                        inputTokens: 700,
                        outputTokens: 300,
                        cacheReadTokens: 0,
                        cacheCreationTokens: 0,
                        totalTokens: 1000,
                        costUSD: 5.0,
                        modelsUsed: ["gpt-5.5"],
                        modelBreakdowns: [
                            .init(
                                modelName: "gpt-5.5",
                                costUSD: 5.0,
                                standardCostUSD: 4.0,
                                priorityCostUSD: 1.0,
                                standardTokens: 800,
                                priorityTokens: 200),
                        ]),
                ],
                updatedAt: Date()),
            provider: .codex)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == "codex" }))
        let summary = try #require(provider.costSummary)
        let day = try #require(summary.daily.first(where: { $0.dayKey == "2026-05-26" }))
        let breakdown = try #require(day.modelBreakdowns.first(where: { $0.label == "gpt-5.5" }))
        #expect(breakdown.standardCostUSD == 4.0)
        #expect(breakdown.priorityCostUSD == 1.0)
        #expect(breakdown.standardTokens == 800)
        #expect(breakdown.priorityTokens == 200)
    }

    // MARK: - SyncCoordinator aggregation

    @Test
    func `SyncCoordinator: unknown Claude model bubbles isEstimated up to summary`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-isEst-claude")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 12.0,
                    windowMinutes: 60,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .claude)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 1500,
                sessionCostUSD: 0.32,
                last30DaysTokens: 32000,
                last30DaysCostUSD: 2.40,
                daily: [
                    CostUsageDailyReport.Entry(
                        date: "2026-04-27",
                        inputTokens: 1000,
                        outputTokens: 500,
                        cacheReadTokens: 0,
                        cacheCreationTokens: 0,
                        totalTokens: 1500,
                        costUSD: 2.40,
                        modelsUsed: ["claude-opus-4-7", "claude-opus-4-99"],
                        modelBreakdowns: [
                            // Known: should be isEstimated == nil/false
                            .init(modelName: "claude-opus-4-7", costUSD: 1.80),
                            // Unknown: walks to opus-4-7 via fallback,
                            // marked isEstimated == true.
                            .init(modelName: "claude-opus-4-99", costUSD: 0.60),
                        ]),
                ],
                updatedAt: Date()),
            provider: .claude)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == "claude" }))
        let summary = try #require(provider.costSummary)
        #expect(
            summary.isEstimated == true,
            "Summary with one unknown-model breakdown should be flagged estimated.")

        let day = try #require(summary.daily.first(where: { $0.dayKey == "2026-04-27" }))
        #expect(
            day.isEstimated == true,
            "Day with one unknown-model breakdown should be flagged estimated.")

        let knownBreakdown = day.modelBreakdowns.first { $0.label == "claude-opus-4-7" }
        let unknownBreakdown = day.modelBreakdowns.first { $0.label == "claude-opus-4-99" }
        #expect(
            knownBreakdown?.isEstimated == nil,
            "Known model breakdown should NOT be flagged estimated.")
        #expect(
            unknownBreakdown?.isEstimated == true,
            "Unknown model breakdown should BE flagged estimated.")
    }

    @Test
    func `SyncCoordinator: all-known Claude models keep isEstimated nil`() async throws {
        let settings = self.makeSettingsStore(suite: "SyncCoord-isEst-allknown")
        settings.iCloudSyncEnabled = true
        try settings.setProviderEnabled(
            provider: .claude,
            metadata: #require(ProviderDefaults.metadata[.claude]),
            enabled: true)

        let store = self.makeUsageStore(settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 5.0,
                    windowMinutes: 60,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .claude)
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 1000,
                sessionCostUSD: 0.10,
                last30DaysTokens: 10000,
                last30DaysCostUSD: 1.0,
                daily: [
                    CostUsageDailyReport.Entry(
                        date: "2026-04-27",
                        inputTokens: 500,
                        outputTokens: 500,
                        cacheReadTokens: 0,
                        cacheCreationTokens: 0,
                        totalTokens: 1000,
                        costUSD: 1.0,
                        modelsUsed: ["claude-opus-4-7"],
                        modelBreakdowns: [
                            .init(modelName: "claude-opus-4-7", costUSD: 1.0),
                        ]),
                ],
                updatedAt: Date()),
            provider: .claude)

        let mock = MockSyncPusher()
        let coordinator = SyncCoordinator(store: store, settings: settings, syncManager: mock)
        await coordinator.pushCurrentSnapshot()

        let provider = try #require(mock.lastSnapshot?.providers
            .first(where: { $0.providerID == "claude" }))
        let summary = try #require(provider.costSummary)
        #expect(
            summary.isEstimated == nil,
            "Summary with all-known models should keep isEstimated nil so old iOS treats as not estimated.")
        let day = try #require(summary.daily.first(where: { $0.dayKey == "2026-04-27" }))
        #expect(day.isEstimated == nil)
    }

    // MARK: - Helpers (mirrored from SyncCoordinatorTests setup pattern)

    private func makeSettingsStore(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(userDefaults: defaults)
    }

    private func makeUsageStore(settings: SettingsStore) -> UsageStore {
        UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
    }
}
