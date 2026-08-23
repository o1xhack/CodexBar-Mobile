import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// T17 (research doc 024 Round 8 / P7) — aggregate over a full ledger
/// (365 days × 40 providers ≈ 14.6k rows) must (a) produce correct totals at
/// scale and (b) finish well within a generous CI ceiling. The precise device
/// target (≤ 50 ms p95) is verified manually on a real device (M-perf) — a
/// tight wall-clock assertion would flake on shared CI timing, so here we use
/// a loose 2 s ceiling that still catches an O(n²) regression.
@Suite("CWL Performance — aggregate at scale (T17)")
@MainActor
struct CWLPerformanceTests {
    private func makeContext() -> (URL, ModelContext) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexBarTests-CWLPerf-\(UUID().uuidString)",
                isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Store.sqlite")
        return (url, ModelContext(ModelContainerFactory.makeContainer(at: url)))
    }

    @Test
    func `T17: aggregate(365) over 365 days × 40 providers — correct + under 2s`() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let now = Date()
        let providerCount = 40
        let dayCount = 365

        // Insert directly (bypass upsert's per-row dedup fetch) for fast setup.
        for p in 0..<providerCount {
            for d in 0..<dayCount {
                let date = now.addingTimeInterval(-TimeInterval(d * 86400))
                let dayKey = CostLedgerService.utcDayKeyFormatter.string(from: date)
                context.insert(DailyCostPoint(
                    deviceID: "dev-A",
                    providerID: "p\(p)",
                    accountEmail: nil,
                    dayKey: dayKey,
                    costUSD: 1.0,
                    totalTokens: 100,
                    lastUpdated: now))
            }
        }
        try context.save()

        // Exercise the production producer-calendar path as well as the row
        // merge. The lookup must stay O(rows), not allocate a DateFormatter
        // or scan every provider for each of the ~14.6k points.
        let sourceProviders = (0..<providerCount).map { index in
            ProviderUsageSnapshot(
                providerID: "p\(index)",
                providerName: "Provider \(index)",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: now,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil,
                    sessionTokens: nil,
                    last30DaysCostUSD: nil,
                    last30DaysTokens: nil,
                    daily: [],
                    bucketTimeZoneIdentifier: "UTC"))
        }
        let sourceSnapshot = SyncedUsageSnapshot(
            providers: sourceProviders,
            syncTimestamp: now,
            deviceName: "Mac A",
            deviceID: "dev-A")

        let start = Date()
        let agg = try CostLedgerService.aggregate(
            windowDays: 365,
            in: context,
            asOf: now,
            sourceSnapshots: [sourceSnapshot],
            readerTimeZone: TimeZone(identifier: "UTC") ?? .gmt)
        let elapsed = Date().timeIntervalSince(start)

        // Correctness at scale.
        #expect(agg.providerRollups.count == providerCount)
        #expect(agg.dailyPoints.count == dayCount)
        #expect(abs(agg.totalCostUSD - Double(providerCount * dayCount)) < 0.01)
        #expect(agg.totalTokens == providerCount * dayCount * 100)

        // Generous CI ceiling (device target ≤ 50ms is M-perf manual).
        #expect(elapsed < 2.0, "aggregate(365) at scale took \(elapsed)s")
    }
}
