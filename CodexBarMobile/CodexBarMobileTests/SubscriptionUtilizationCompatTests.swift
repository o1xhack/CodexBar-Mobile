import CodexBarSync
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import CodexBarMobile

/// Guards `UtilizationAggregateView` (the Cost-tab 30-day subscription
/// utilization chart) against iOS 1.3.0's new upstream providers that
/// don't emit utilization history.
///
/// Perplexity and OpenCode Go have no `utilizationHistory` on Mac today —
/// Perplexity publishes three credit pools instead (handled by T3's
/// PerplexityCreditsCard), OpenCode Go's web usage is reported as flat
/// rate windows. If the aggregate view crashes or produces malformed
/// state on providers with no history, the user opens the Cost tab
/// once with Perplexity enabled and gets a blank screen or a fall-off.
///
/// `UtilizationAggregateView.buildModel(from:windowSize:)` is already
/// `compactMap`-gated on `utilizationHistory` being non-nil and its
/// `session` series having entries — so the no-history case should be a
/// silent skip. These tests pin that behavior (so a future refactor
/// can't reintroduce a force-unwrap) and cover the identity-key stability
/// that the cache invalidation depends on.
@Suite("Subscription Utilization compatibility with new providers (T6)")
struct SubscriptionUtilizationCompatTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeProvider(
        id: String,
        name: String,
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
            lastUpdated: self.baseDate,
            utilizationHistory: utilization)
    }

    private func sessionSeries(_ percent: Double) -> [SyncUtilizationSeries] {
        [SyncUtilizationSeries(
            name: "session",
            windowMinutes: 300,
            entries: [SyncUtilizationEntry(
                capturedAt: self.baseDate,
                usedPercent: percent,
                resetsAt: nil)])]
    }

    @Test("Identity key is stable when Perplexity provider has no utilization history")
    func identityKeyStableWithPerplexityNoHistory() {
        // Typical real-world mix: Claude + Codex with session data, plus
        // Perplexity sitting in the list with nothing to aggregate. The
        // identity key derivation must skip the no-history provider's
        // entry count (`totalEntries += 0`) and still produce a stable,
        // deterministic key across repeated calls.
        let providers = [
            self.makeProvider(id: "claude", name: "Claude", utilization: self.sessionSeries(42)),
            self.makeProvider(id: "codex", name: "Codex", utilization: self.sessionSeries(18)),
            self.makeProvider(id: "perplexity", name: "Perplexity", utilization: nil),
        ]
        let k1 = UtilizationAggregateView.identityKey(for: providers, windowSize: 30)
        let k2 = UtilizationAggregateView.identityKey(for: providers, windowSize: 30)
        #expect(k1 == k2)
        #expect(k1.contains("perplexity"))
    }

    @Test("Identity key distinct when Perplexity is replaced by OpenCode Go")
    func identityKeyDistinctAcrossNewProviders() {
        let withPerplexity = [
            self.makeProvider(id: "claude", name: "Claude", utilization: self.sessionSeries(42)),
            self.makeProvider(id: "perplexity", name: "Perplexity", utilization: nil),
        ]
        let withOpenCodeGo = [
            self.makeProvider(id: "claude", name: "Claude", utilization: self.sessionSeries(42)),
            self.makeProvider(id: "opencodego", name: "OpenCode Go", utilization: nil),
        ]
        let k1 = UtilizationAggregateView.identityKey(for: withPerplexity, windowSize: 30)
        let k2 = UtilizationAggregateView.identityKey(for: withOpenCodeGo, windowSize: 30)
        #expect(k1 != k2)
    }

    @Test("Mixed providers (some with history, some without) produce a stable key that reflects ONLY history-bearing entries")
    func identityKeyEntryCountIgnoresNoHistoryProviders() {
        // OpenCode Go and Perplexity contribute 0 entries. Only Claude's
        // single entry counts. The `n=1` suffix proves the guard actually
        // excludes them.
        let providers = [
            self.makeProvider(id: "claude", name: "Claude", utilization: self.sessionSeries(42)),
            self.makeProvider(id: "perplexity", name: "Perplexity", utilization: nil),
            self.makeProvider(id: "opencodego", name: "OpenCode Go", utilization: nil),
        ]
        let key = UtilizationAggregateView.identityKey(for: providers, windowSize: 30)
        #expect(key.contains("n=1"))
    }

    @Test("All-no-history provider list produces a well-formed key (no crash)")
    func identityKeyAllNoHistoryProviders() {
        // Hypothetical worst case: user has only providers that don't
        // emit utilization history (e.g., a Perplexity-only account).
        // identityKey must still return a string, not crash, and must
        // not surface NaN / nil anywhere.
        let providers = [
            self.makeProvider(id: "perplexity", name: "Perplexity", utilization: nil),
            self.makeProvider(id: "opencodego", name: "OpenCode Go", utilization: nil),
        ]
        let key = UtilizationAggregateView.identityKey(for: providers, windowSize: 30)
        #expect(!key.isEmpty)
        #expect(key.contains("n=0"))
    }

    @Test("Provider tint color resolves to the palette entry (Perplexity teal, OpenCode Go mint)")
    func aggregateColorsDelegateToPalette() {
        // UtilizationAggregateView.providerColor(for:) now delegates to
        // ProviderColorPalette (consolidated in T2 / Build 70). This pins
        // that the aggregate view uses the SAME colors as the provider
        // cards — before consolidation it silently rendered unknown
        // providers as .gray.
        let perplexityColor = ProviderColorPalette.color(for: "perplexity")
        let goColor = ProviderColorPalette.color(for: "opencodego")
        // These both used to be .gray in UtilizationAggregateView and
        // .blue everywhere else. Post-T2/T6 they're unique.
        #expect(UIColor(perplexityColor) != UIColor(.gray))
        #expect(UIColor(goColor) != UIColor(.gray))
        #expect(UIColor(perplexityColor) != UIColor(goColor))
    }

    // MARK: - Daily-peak semantics (Build 77)
    //
    // Reported bug: iPhone Cost tab showed Codex at 0% in Subscription
    // Utilization while the Codex detail page rendered clear session bars
    // and "16% used". The aggregate view used to average RAW entries; for a
    // bursty session provider (most hourly samples at 0% between activity),
    // the raw average rounds to 0 even when the user is clearly using it.
    //
    // Fix: collapse entries to daily peaks (max per calendar day) before
    // aggregating — matches the detail view's "best per period" semantics.

    private func bursty30DayProvider(
        id: String = "codex",
        name: String = "Codex",
        peakPercentPerDay: Double,
        samplesPerDay: Int = 24
    ) -> ProviderUsageSnapshot {
        // Simulates a provider sampled hourly for 30 days, with `peakPercentPerDay`
        // hit for exactly ONE sample per day and 0% for the rest — matches a
        // user doing short bursts of activity inside a session quota that
        // otherwise idles at 0%.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var entries: [SyncUtilizationEntry] = []
        for dayOffset in 0 ..< 30 {
            let day = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            for hour in 0 ..< samplesPerDay {
                let captured = calendar.date(byAdding: .hour, value: hour, to: day)!
                let percent = (hour == 12) ? peakPercentPerDay : 0.0
                entries.append(SyncUtilizationEntry(
                    capturedAt: captured, usedPercent: percent, resetsAt: nil))
            }
        }
        return ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil, secondary: nil,
            accountEmail: nil,
            loginMethod: nil, statusMessage: nil,
            isError: false, lastUpdated: Date(),
            utilizationHistory: [SyncUtilizationSeries(
                name: "session", windowMinutes: 300, entries: entries)])
    }

    @Test("Bursty provider (1 peak/day, 23 zeros) produces non-zero aggregate via daily-peak semantics")
    func aggregateBurstyProviderShowsPeakNotZero() throws {
        // Pre-fix: this would have shown ~0.67% (16 / 24) rounding to 0% per
        // period card. Post-fix: shows 16% — same number the user sees on
        // the detail page's bar chart.
        let provider = self.bursty30DayProvider(peakPercentPerDay: 16)
        let model = try #require(UtilizationAggregateView.buildModel(from: [provider], windowSize: 30))

        // 30-day average of daily peaks should be ~16%, NOT ~0.67% (raw avg).
        let last30 = try #require(model.last30Avg)
        #expect(last30 > 15 && last30 < 17)

        // Daily bars should all show the peak value as segment height.
        let realBars = model.dayBars.filter { !$0.isPadding }
        #expect(!realBars.isEmpty)
        for bar in realBars {
            // Each day has exactly one provider segment with the peak value.
            #expect(bar.segments.count == 1)
            #expect(bar.segments.first?.avgPercent == 16)
        }
    }

    @Test("Two providers with different burst patterns reflect relative usage (not both 0%)")
    func aggregateTwoBurstyProvidersShowCorrectShare() throws {
        // The user's reported scenario: Claude "12% avg use, 100% share" and
        // Codex "0% avg use, 0% share". Post-fix, both should show their
        // actual peak averages and share proportionally.
        let claude = self.bursty30DayProvider(id: "claude", name: "Claude", peakPercentPerDay: 24)
        let codex = self.bursty30DayProvider(id: "codex", name: "Codex", peakPercentPerDay: 16)

        let model = try #require(UtilizationAggregateView.buildModel(from: [claude, codex], windowSize: 30))
        #expect(model.providerShares.count == 2)

        // 1.5.3 fix: ProviderShare.id now carries the multi-account-aware
        // composite key `providerID|accountEmail`. The bursty test fixture
        // has `accountEmail = nil`, so the IDs come out as `"claude|"` and
        // `"codex|"`. Lookups by name are stable across the id-format change.
        let claudeShare = try #require(model.providerShares.first { $0.name == "Claude" })
        let codexShare = try #require(model.providerShares.first { $0.name == "Codex" })

        // Raw average of daily peaks
        #expect(claudeShare.rawAvgPercent > 23 && claudeShare.rawAvgPercent < 25)
        #expect(codexShare.rawAvgPercent > 15 && codexShare.rawAvgPercent < 17)

        // Proportional share: Claude 24 / (24 + 16) = 60%, Codex 40%
        #expect(claudeShare.sharePercent > 59 && claudeShare.sharePercent < 61)
        #expect(codexShare.sharePercent > 39 && codexShare.sharePercent < 41)
    }

    @Test("Duplicate session series (cross-version Mac merge leakage) do not hide real data")
    func aggregateUnionsMultipleSessionSeries() throws {
        // Simulates the state after a pre-Build-77 `mergeUtilizationHistories`
        // that left two "session" series behind because two Macs disagreed on
        // windowMinutes. Pre-fix the aggregate picked `first(where: name ==
        // "session")` and used whichever series landed first — empty/stale
        // or real, non-deterministically.
        // Post-fix, aggregate unions entries across ALL series named "session".
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let realEntries = (0 ..< 5).map { dayOffset -> SyncUtilizationEntry in
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            return SyncUtilizationEntry(capturedAt: date, usedPercent: 42, resetsAt: nil)
        }
        // First series (empty) sits in front — pre-fix, aggregate would pick
        // this one and conclude "no data".
        let emptyFirst = SyncUtilizationSeries(name: "session", windowMinutes: 300, entries: [])
        let realSecond = SyncUtilizationSeries(name: "session", windowMinutes: 180, entries: realEntries)
        let provider = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex",
            primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil,
            statusMessage: nil, isError: false,
            lastUpdated: Date(),
            utilizationHistory: [emptyFirst, realSecond])

        let model = try #require(UtilizationAggregateView.buildModel(from: [provider], windowSize: 30))
        #expect(model.providerShares.count == 1)
        // Average of daily peaks (each day = 42%) should be 42, not 0.
        #expect(model.providerShares.first?.rawAvgPercent == 42)
    }

    @Test("Stale session history falls back to the freshest quota series")
    func aggregateFallsBackWhenSessionStopsUpdating() throws {
        // Production incident (2026-07-26): Codex session history stopped on
        // July 12 while weekly history continued through July 26. The aggregate
        // saw that an old session series existed and ignored every fresh weekly
        // sample, producing 0% for Today / This Week / 14 Days while Raw Sync
        // Data still showed current quota data.
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let staleSession = SyncUtilizationSeries(
            name: "session",
            windowMinutes: 300,
            entries: [
                SyncUtilizationEntry(
                    capturedAt: now.addingTimeInterval(-3 * 86_400),
                    usedPercent: 90,
                    resetsAt: nil),
            ])
        let freshWeekly = SyncUtilizationSeries(
            name: "weekly",
            windowMinutes: 10_080,
            entries: [
                SyncUtilizationEntry(
                    capturedAt: now,
                    usedPercent: 42,
                    resetsAt: nil),
            ])
        let provider = self.makeProvider(
            id: "codex",
            name: "Codex",
            utilization: [staleSession, freshWeekly])

        let model = try #require(
            UtilizationAggregateView.buildModel(from: [provider], windowSize: 30))
        #expect(model.todayAvg == 42)
        #expect(model.last14Avg == 42)
        #expect(model.providerShares.first?.rawAvgPercent == 42)
        #expect(model.dayBars.last?.segments.first?.avgPercent == 42)
    }

    @Test("Fresh zero-percent session remains preferred over a non-zero weekly quota")
    func aggregateDoesNotTreatCurrentZeroSessionAsMissing() throws {
        // A genuine 0% session is valid data. Selection is based on timestamp
        // freshness, never on the value, so weekly fallback cannot turn an idle
        // session into apparent activity.
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        let freshSession = SyncUtilizationSeries(
            name: "session",
            windowMinutes: 300,
            entries: [
                SyncUtilizationEntry(
                    capturedAt: now,
                    usedPercent: 0,
                    resetsAt: nil),
            ])
        let freshWeekly = SyncUtilizationSeries(
            name: "weekly",
            windowMinutes: 10_080,
            entries: [
                SyncUtilizationEntry(
                    capturedAt: now,
                    usedPercent: 75,
                    resetsAt: nil),
            ])
        let provider = self.makeProvider(
            id: "claude",
            name: "Claude",
            utilization: [freshSession, freshWeekly])

        let model = try #require(
            UtilizationAggregateView.buildModel(from: [provider], windowSize: 30))
        #expect(model.todayAvg == 0)
        #expect(model.providerShares.first?.rawAvgPercent == 0)
        #expect(model.dayBars.last?.segments.first?.avgPercent == 0)
    }

    // MARK: - Build 81 · thread safety (Codex-caught P0)

    @Test("iso8601DayKey is safe to call from many concurrent tasks (DateFormatter thread safety)")
    func dayKeyConcurrentCallsSafe() async {
        // Pre-Build-81 used a shared `static let DateFormatter` whose
        // `string(from:)` is documented unsafe under concurrent access on
        // iOS — could crash. Build 81 replaced with a per-call formatter.
        // Stress this by calling from many concurrent tasks and asserting
        // all results match the single-threaded reference.
        let dates = (0 ..< 30).map { Date(timeIntervalSince1970: TimeInterval(1_745_500_000 + $0 * 86400)) }
        let expected = dates.map { SyncCostSummary.iso8601DayKey(for: $0) }

        await withTaskGroup(of: [String].self) { group in
            for _ in 0 ..< 64 {
                group.addTask {
                    dates.map { SyncCostSummary.iso8601DayKey(for: $0) }
                }
            }
            for await result in group {
                #expect(result == expected)
            }
        }
    }
}
