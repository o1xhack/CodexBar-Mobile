import CodexBarSync
import Foundation
import Testing
@testable import CodexBarMobile

/// Tests for identity-key correctness across the five hotspot views refactored in P1.
/// Cache invalidation relies on stable identity keys — same inputs must hash identically,
/// changed inputs must produce different keys, and unrelated state changes must not
/// affect the key.
@Suite("View Cache Identity Keys")
struct ViewCacheIdentityTests {
    // MARK: - Fixtures

    private static func makeProvider(
        id: String = "claude",
        name: String = "Claude",
        lastUpdated: Date = Date(timeIntervalSince1970: 1_700_000_000),
        utilization: [SyncUtilizationSeries]? = nil
    ) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            costSummary: nil,
            budget: nil,
            rateWindows: [],
            utilizationHistory: utilization)
    }

    private static func makeSeries(
        name: String = "session",
        windowMinutes: Int = 300,
        entries: [SyncUtilizationEntry] = [
            SyncUtilizationEntry(
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                usedPercent: 42,
                resetsAt: nil),
        ]
    ) -> SyncUtilizationSeries {
        SyncUtilizationSeries(name: name, windowMinutes: windowMinutes, entries: entries)
    }

    private static func makeSnapshot(
        providers: [ProviderUsageSnapshot] = [makeProvider()],
        syncTimestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        deviceID: String? = "mac-1"
    ) -> SyncedUsageSnapshot {
        SyncedUsageSnapshot(
            providers: providers,
            syncTimestamp: syncTimestamp,
            deviceName: "Test Mac",
            deviceID: deviceID,
            appVersion: "0.20.0",
            mobileVersion: "1.3.0",
            notificationPushEnabled: true)
    }

    // MARK: - Hotspot 1: UtilizationAggregateView

    @Test("UtilizationAggregateView: same input → same key")
    func aggregate_sameInput_sameKey() {
        let providers = [Self.makeProvider(id: "a"), Self.makeProvider(id: "b")]
        let k1 = UtilizationAggregateView.identityKey(for: providers, windowSize: 30)
        let k2 = UtilizationAggregateView.identityKey(for: providers, windowSize: 30)
        #expect(k1 == k2)
    }

    @Test("UtilizationAggregateView: changed providerID → different key")
    func aggregate_changedProviderID_differentKey() {
        let k1 = UtilizationAggregateView.identityKey(
            for: [Self.makeProvider(id: "a")], windowSize: 30)
        let k2 = UtilizationAggregateView.identityKey(
            for: [Self.makeProvider(id: "b")], windowSize: 30)
        #expect(k1 != k2)
    }

    @Test("UtilizationAggregateView: changed lastUpdated → different key")
    func aggregate_changedLastUpdated_differentKey() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let k1 = UtilizationAggregateView.identityKey(
            for: [Self.makeProvider(lastUpdated: base)], windowSize: 30)
        let k2 = UtilizationAggregateView.identityKey(
            for: [Self.makeProvider(lastUpdated: base.addingTimeInterval(60))], windowSize: 30)
        #expect(k1 != k2)
    }

    @Test("UtilizationAggregateView: provider order does not affect key")
    func aggregate_orderIrrelevant() {
        let a = Self.makeProvider(id: "a")
        let b = Self.makeProvider(id: "b")
        let k1 = UtilizationAggregateView.identityKey(for: [a, b], windowSize: 30)
        let k2 = UtilizationAggregateView.identityKey(for: [b, a], windowSize: 30)
        #expect(k1 == k2)
    }

    @Test("UtilizationAggregateView: different windowSize → different key")
    func aggregate_windowSize_affectsKey() {
        let p = [Self.makeProvider()]
        #expect(UtilizationAggregateView.identityKey(for: p, windowSize: 30)
            != UtilizationAggregateView.identityKey(for: p, windowSize: 7))
    }

    // MARK: - Hotspot 2: UtilizationHistoryView

    @Test("UtilizationHistoryView: same series & index → same key")
    func history_sameInput_sameKey() {
        let s = [Self.makeSeries()]
        let k1 = UtilizationHistoryView.identityKey(series: s, selectedSeriesIndex: 0)
        let k2 = UtilizationHistoryView.identityKey(series: s, selectedSeriesIndex: 0)
        #expect(k1 == k2)
    }

    @Test("UtilizationHistoryView: changed selectedSeriesIndex → different key")
    func history_changedIndex_differentKey() {
        let s = [
            Self.makeSeries(name: "session"),
            Self.makeSeries(name: "weekly", windowMinutes: 10080),
        ]
        let k1 = UtilizationHistoryView.identityKey(series: s, selectedSeriesIndex: 0)
        let k2 = UtilizationHistoryView.identityKey(series: s, selectedSeriesIndex: 1)
        #expect(k1 != k2)
    }

    @Test("UtilizationHistoryView: new entry appended → different key")
    func history_newEntry_differentKey() {
        let base = [
            SyncUtilizationEntry(
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                usedPercent: 10,
                resetsAt: nil),
        ]
        let extended = base + [
            SyncUtilizationEntry(
                capturedAt: Date(timeIntervalSince1970: 1_700_000_060),
                usedPercent: 20,
                resetsAt: nil),
        ]
        let k1 = UtilizationHistoryView.identityKey(
            series: [Self.makeSeries(entries: base)], selectedSeriesIndex: 0)
        let k2 = UtilizationHistoryView.identityKey(
            series: [Self.makeSeries(entries: extended)], selectedSeriesIndex: 0)
        #expect(k1 != k2)
    }

    // MARK: - Hotspot 3: CostShareCardView / ShareCardData.displayProviders

    @Test("ShareCardData.displayProviders is deterministic for the same provider list")
    func displayProviders_deterministic() {
        let providers: [ShareCardData.ProviderRow] = [
            ShareCardData.ProviderRow(name: "A", cost: 10, share: 0.5, color: .red),
            ShareCardData.ProviderRow(name: "B", cost: 6, share: 0.3, color: .blue),
            ShareCardData.ProviderRow(name: "C", cost: 3, share: 0.15, color: .green),
            ShareCardData.ProviderRow(name: "D", cost: 1, share: 0.05, color: .orange),
        ]
        let data = ShareCardData(
            totalCost: 20, todayCost: 5, totalTokens: 1_000, activeDays: 7, avgDailyCost: 3,
            providers: providers, topModels: [], dailyBars: [])
        let first = data.displayProviders
        let second = data.displayProviders
        #expect(first.count == second.count)
        #expect(first.map(\.name) == second.map(\.name))
        #expect(first.map(\.cost) == second.map(\.cost))
    }

    @Test("ShareCardData.displayProviders collapses tail to 'Others' when 6 or more providers")
    func displayProviders_collapsesTail() {
        // iOS 1.9.0 cap: top 5 + an aggregated "Others" row, only when count >= 6.
        let rows: [ShareCardData.ProviderRow] = (0 ..< 6).map {
            ShareCardData.ProviderRow(name: "P\($0)", cost: Double(6 - $0), share: 0.1, color: .gray)
        }
        let data = ShareCardData(
            totalCost: 21, todayCost: 0, totalTokens: 0, activeDays: 0, avgDailyCost: 0,
            providers: rows, topModels: [], dailyBars: [])
        let display = data.displayProviders
        #expect(display.count == 6)
        #expect(display.prefix(5).map(\.name) == ["P0", "P1", "P2", "P3", "P4"])
        #expect(display.last?.name == OthersRowPreview.title(names: ["P5"]))
        // The Others bucket aggregates only the tail beyond the top 5 (P5, cost 1).
        #expect(display.last?.cost == 1)
    }

    @Test("Others preview names only the first two distinct hidden items")
    func othersPreview_capsNames() {
        let title = OthersRowPreview.title(names: ["Codex", "Claude Code", "Codex", "Cursor"])
        #expect(title.contains("Codex"))
        #expect(title.contains("Claude Code"))
        #expect(!title.contains("Cursor"))
        #expect(title.contains("…"))
    }

    @Test("ShareCardData.displayProviders shows all when 5 or fewer providers (no 'Others')")
    func displayProviders_noCollapseAtFive() {
        let rows: [ShareCardData.ProviderRow] = (0 ..< 5).map {
            ShareCardData.ProviderRow(name: "P\($0)", cost: Double(5 - $0), share: 0.2, color: .gray)
        }
        let data = ShareCardData(
            totalCost: 15, todayCost: 0, totalTokens: 0, activeDays: 0, avgDailyCost: 0,
            providers: rows, topModels: [], dailyBars: [])
        let display = data.displayProviders
        #expect(display.count == 5)
        #expect(display.last?.name == "P4")
    }

    // Note: Hotspot 5 (CostTab) reverted to synchronous compute — no cache identity needed.
    // See ContentView.swift CostTab.currentInsights; Cost tab has no hover interaction so
    // per-render recompute cost is acceptable. Async cache caused UI test failures because
    // first render had cachedInsights=nil and rendered nothing until .task(id:) fired.
}
