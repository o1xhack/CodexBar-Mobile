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

        // Include the November DST rollback even when this test runs in another season.
        let now = Date(timeIntervalSince1970: 1_794_002_400)
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

    @Test
    func `UTC cost days remain distinct across the November daylight saving rollback`() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let now = Date(timeIntervalSince1970: 1_793_620_800) // 2026-11-02T12:00:00Z
        let days = ["2026-10-31", "2026-11-01", "2026-11-02"]
        for day in days {
            context.insert(DailyCostPoint(
                deviceID: "calendar-mac",
                providerID: "calendar-fixture",
                accountEmail: nil,
                dayKey: day,
                costUSD: 1,
                totalTokens: 100,
                lastUpdated: now))
        }
        try context.save()
        let provider = ProviderUsageSnapshot(
            providerID: "calendar-fixture",
            providerName: "Calendar fixture",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: .init(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                daily: [],
                bucketTimeZoneIdentifier: "UTC"))
        let result = try CostLedgerService.aggregate(
            windowDays: 3,
            in: context,
            asOf: now,
            sourceSnapshots: [.init(
                providers: [provider],
                syncTimestamp: now,
                deviceName: "Calendar Mac",
                deviceID: "calendar-mac")],
            readerTimeZone: .gmt)
        #expect(result.dailyPoints.map(\.dayKey).sorted() == days)
        #expect(result.totalCostUSD == 3)
        #expect(result.totalTokens == 300)
    }

    @Test
    func `Background history refresh at scale leaves the main actor responsive`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = ModelContainerFactory.makeContainer(at: directory.appendingPathComponent("Store.sqlite"))
        let context = ModelContext(container)
        let now = Date()
        let providers = (0..<40).map { index in
            ProviderUsageSnapshot(
                providerID: "p\(index)", providerName: "Provider \(index)",
                primary: nil, secondary: nil, accountEmail: nil, loginMethod: nil,
                statusMessage: nil, isError: false, lastUpdated: now)
        }
        let snapshot = SyncedUsageSnapshot(
            providers: providers, syncTimestamp: now, deviceName: "Scale Mac", deviceID: "scale-mac")
        try SwiftDataBridge.upsert(deviceSnapshots: [snapshot], into: context)
        for provider in providers {
            for day in 0..<365 {
                context.insert(DailyCostPoint(
                    deviceID: "scale-mac", providerID: provider.providerID, accountEmail: nil,
                    dayKey: SyncCostSummary.iso8601DayKey(for: now.addingTimeInterval(-Double(day) * 86400)),
                    costUSD: 1, totalTokens: 100, lastUpdated: now))
            }
        }
        try context.save()
        let worker = CostHistoryWorker(container: container)
        let start = Date()
        let heartbeat = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(1))
            return Date()
        }
        let insights = try await worker.load(.init(
            snapshot: snapshot, sourceSnapshots: [snapshot], activeDeviceIDs: ["scale-mac"],
            windowDays: 365, useLedger: true, isDemoMode: false, clearTombstone: nil))
        let finished = Date()
        let heartbeatAt = try await heartbeat.value
        #expect(insights?.total30DayCost == 14600)
        #expect(heartbeatAt < finished, "Main actor must service input before the full history refresh completes")
        print(
            "CWL background refresh: \(finished.timeIntervalSince(start))s; main actor heartbeat: \(heartbeatAt.timeIntervalSince(start))s")
    }
}
