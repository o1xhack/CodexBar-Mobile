import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// Round 3 / P3 of research doc 024 — reader. Exercises the aggregate
/// primitive `CostLedgerService.aggregate(...)` plus `aggregateProvider`
/// and `diagnostics`:
///
/// - **T4**: single-device aggregation correctness — totals, activeDayCount,
///   per-provider rollups, daily series order.
/// - **T5**: cross-device merge — local-cost providers sum active-device
///   rows, while account-level providers keep the latest account/day row.
/// - **T6**: window filtering — 7d / 30d / 90d / 365d return exactly the
///   days inside the window; boundary day inclusive.
/// - Diagnostics smoke: counts, earliest dayKey, latestWriteAt.
///
/// T7 (equivalence against the blob-derived `CostDashboardInsights`) is
/// deliberately deferred to P4 — it needs the blob path and the ledger
/// path consumed via the same renderer.
@Suite("CWL Aggregate — single + cross-device merge + window filter (T4 + T5 + T6) + diagnostics")
@MainActor
struct CWLAggregateTests {
    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexBarTests-CWLAggregate-\(UUID().uuidString)",
                isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Store.sqlite")
    }

    private func makeContext() -> (URL, ModelContext) {
        let url = self.makeTempStoreURL()
        let container = ModelContainerFactory.makeContainer(at: url)
        return (url, ModelContext(container))
    }

    /// Fixed "today" so window math is deterministic regardless of when
    /// the test runs. Built from explicit components instead of a magic
    /// timestamp — easier to verify by eye.
    private static let asOf: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(
            from: DateComponents(year: 2026, month: 5, day: 28))!
    }()

    private func dayKey(daysAgo: Int) -> String {
        let d = Self.asOf.addingTimeInterval(-TimeInterval(daysAgo * 86400))
        return CostLedgerService.utcDayKeyFormatter.string(from: d)
    }

    private func insert(
        _ context: ModelContext,
        device: String,
        provider: String,
        account: String? = nil,
        daysAgo: Int,
        cost: Double,
        tokens: Int,
        modelBreakdowns: [SyncCostBreakdown] = [],
        serviceBreakdowns: [SyncCostBreakdown] = [],
        lastUpdated: Date) throws
    {
        try CostLedgerService.upsertDayPoint(
            deviceID: device,
            providerID: provider,
            accountEmail: account,
            dayKey: self.dayKey(daysAgo: daysAgo),
            costUSD: cost,
            totalTokens: tokens,
            isEstimated: nil,
            modelBreakdowns: modelBreakdowns,
            serviceBreakdowns: serviceBreakdowns,
            lastUpdated: lastUpdated,
            in: context)
    }

    // MARK: - T4

    @Test("T4: single-device aggregate — totals, activeDayCount, providerRollups")
    func testSingleDeviceAggregate() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        // 3 days × 2 providers, all from one device.
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try self.insert(context, device: "dev-A", provider: "codex",
            daysAgo: 0, cost: 1.0, tokens: 100, lastUpdated: t)
        try self.insert(context, device: "dev-A", provider: "codex",
            daysAgo: 1, cost: 2.0, tokens: 200, lastUpdated: t)
        try self.insert(context, device: "dev-A", provider: "codex",
            daysAgo: 2, cost: 3.0, tokens: 300, lastUpdated: t)
        try self.insert(context, device: "dev-A", provider: "claude",
            daysAgo: 0, cost: 0.5, tokens: 50, lastUpdated: t)
        try self.insert(context, device: "dev-A", provider: "claude",
            daysAgo: 1, cost: 0.0, tokens: 0, lastUpdated: t)
        try context.save()

        let agg = try CostLedgerService.aggregate(
            windowDays: 30, in: context, asOf: Self.asOf)

        // Totals across both providers, all 3 days.
        #expect(agg.totalCostUSD == 6.5)
        #expect(agg.totalTokens == 650)
        // Days with cost > 0: today, yesterday, day before. (claude day-1 = $0
        // contributes nothing on its own — but codex day-1 = $2 makes day-1 active.)
        #expect(agg.activeDayCount == 3)

        // Per-provider rollups.
        #expect(agg.providerRollups.count == 2)
        let codex = try #require(agg.providerRollups["codex|_"])
        #expect(codex.totalCostUSD == 6.0)
        #expect(codex.totalTokens == 600)
        #expect(codex.dailyPoints.count == 3)

        let claude = try #require(agg.providerRollups["claude|_"])
        #expect(claude.totalCostUSD == 0.5)
        #expect(claude.totalTokens == 50)
        #expect(claude.dailyPoints.count == 2)

        // Daily series re-aggregated across providers, sorted oldest → newest.
        #expect(agg.dailyPoints.count == 3)
        let sorted = agg.dailyPoints.map(\.dayKey)
        #expect(sorted == sorted.sorted())
    }

    // MARK: - T5

    @Test("T5: local-cost same provider/account/day across devices → active-device rows sum")
    func testCrossDeviceLocalCostSums() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(3600) // 1 hour later

        // Codex is a local-cost provider. Two active Macs report different
        // local CLI spend for the same day, so the correct answer is SUM.
        try self.insert(context, device: "dev-A", provider: "codex",
            daysAgo: 0, cost: 1.0, tokens: 100,
            modelBreakdowns: [
                SyncCostBreakdown(
                    label: "gpt-5", costUSD: 1.0,
                    standardCostUSD: 1.0, standardTokens: 100),
            ],
            serviceBreakdowns: [
                SyncCostBreakdown(label: "Codex Run", costUSD: 0.25),
            ],
            lastUpdated: t0)
        try self.insert(context, device: "dev-B", provider: "codex",
            daysAgo: 0, cost: 9.0, tokens: 900,
            modelBreakdowns: [
                SyncCostBreakdown(
                    label: "gpt-5", costUSD: 9.0,
                    priorityCostUSD: 9.0, priorityTokens: 900),
            ],
            serviceBreakdowns: [
                SyncCostBreakdown(label: "Codex Run", costUSD: 1.75),
            ],
            lastUpdated: t1)
        try context.save()

        let agg = try CostLedgerService.aggregate(
            windowDays: 7, in: context, asOf: Self.asOf)

        #expect(agg.totalCostUSD == 10.0)
        #expect(agg.totalTokens == 1_000)
        #expect(agg.activeDayCount == 1)
        let codex = try #require(agg.providerRollups["codex|_"])
        #expect(codex.totalCostUSD == 10.0)
        #expect(codex.totalTokens == 1_000)

        let model = try #require(agg.modelMix.first { $0.label == "gpt-5" })
        #expect(model.costUSD == 10.0)
        #expect(model.standardCostUSD == 1.0)
        #expect(model.priorityCostUSD == 9.0)
        #expect(model.standardTokens == 100)
        #expect(model.priorityTokens == 900)

        let service = try #require(agg.serviceMix.first { $0.label == "Codex Run" })
        #expect(service.costUSD == 2.0)
        #expect(codex.dailyPoints.first?.modelBreakdowns.first?.costUSD == 10.0)
        #expect(codex.serviceBreakdowns.first?.costUSD == 2.0)
    }

    @Test("T5: account-level same provider/account/day across devices → latest wins")
    func testCrossDeviceAccountLevelLatestWins() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(3600)

        try self.insert(context, device: "dev-A", provider: "openrouter",
            account: "api@example.com", daysAgo: 0, cost: 1.0, tokens: 100, lastUpdated: t0)
        try self.insert(context, device: "dev-B", provider: "openrouter",
            account: "api@example.com", daysAgo: 0, cost: 9.0, tokens: 900, lastUpdated: t1)
        try context.save()

        let agg = try CostLedgerService.aggregate(
            windowDays: 7, in: context, asOf: Self.asOf)

        #expect(agg.totalCostUSD == 9.0)
        #expect(agg.totalTokens == 900)
        let openrouter = try #require(agg.providerRollups["openrouter|api@example.com"])
        #expect(openrouter.totalCostUSD == 9.0)
    }

    @Test("T5: activeDeviceIDs filter excludes archived local-cost rows before summing")
    func testActiveDeviceFilterExcludesArchivedRows() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try self.insert(context, device: "dev-archived", provider: "codex",
            daysAgo: 0, cost: 100.0, tokens: 10_000, lastUpdated: t)
        try self.insert(context, device: "dev-active", provider: "codex",
            daysAgo: 0, cost: 2.0, tokens: 200, lastUpdated: t)
        try context.save()

        let agg = try CostLedgerService.aggregate(
            windowDays: 7,
            in: context,
            asOf: Self.asOf,
            activeDeviceIDs: ["dev-active"])

        #expect(agg.totalCostUSD == 2.0)
        #expect(agg.totalTokens == 200)
        let codex = try #require(agg.providerRollups["codex|_"])
        #expect(codex.totalCostUSD == 2.0)
    }

    @Test("T5: activeDeviceIDs filter includes legacy fallback device rows")
    func testActiveDeviceFilterIncludesLegacyFallbackRows() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let legacySnapshot = SyncedUsageSnapshot(
            providers: [],
            syncTimestamp: t,
            deviceName: "Old Mac",
            deviceID: nil)
        let modernSnapshot = SyncedUsageSnapshot(
            providers: [],
            syncTimestamp: t,
            deviceName: "New Mac",
            deviceID: "dev-new")
        let activeDeviceIDs = try #require(CostLedgerDeviceFilter.activeDeviceIDs(
            for: [legacySnapshot, modernSnapshot]))

        try self.insert(context, device: "legacy:Old Mac", provider: "codex",
            daysAgo: 0, cost: 3.0, tokens: 300, lastUpdated: t)
        try self.insert(context, device: "dev-new", provider: "codex",
            daysAgo: 0, cost: 2.0, tokens: 200, lastUpdated: t)
        try self.insert(context, device: "dev-archived", provider: "codex",
            daysAgo: 0, cost: 100.0, tokens: 10_000, lastUpdated: t)
        try context.save()

        #expect(activeDeviceIDs == ["legacy:Old Mac", "dev-new"])
        let agg = try CostLedgerService.aggregate(
            windowDays: 7,
            in: context,
            asOf: Self.asOf,
            activeDeviceIDs: activeDeviceIDs)

        #expect(agg.totalCostUSD == 5.0)
        #expect(agg.totalTokens == 500)
        let codex = try #require(agg.providerRollups["codex|_"])
        #expect(codex.totalCostUSD == 5.0)
    }

    @Test("T5: cross-device different (providerID, dayKey) → both kept (no merge)")
    func testCrossDeviceDistinctKeysCoexist() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let t = Date(timeIntervalSince1970: 1_700_000_000)

        // 2 devices, different providers + days — nothing to merge.
        try self.insert(context, device: "dev-A", provider: "codex",
            daysAgo: 0, cost: 1.0, tokens: 100, lastUpdated: t)
        try self.insert(context, device: "dev-B", provider: "claude",
            daysAgo: 1, cost: 2.0, tokens: 200, lastUpdated: t)
        try context.save()

        let agg = try CostLedgerService.aggregate(
            windowDays: 7, in: context, asOf: Self.asOf)
        #expect(agg.totalCostUSD == 3.0)
        #expect(agg.totalTokens == 300)
        #expect(agg.activeDayCount == 2)
        #expect(agg.providerRollups.count == 2)
    }

    // MARK: - T6

    @Test("T6: window filter — 7d returns only days within last 7, 30d within 30, 90d within 90")
    func testWindowFilter() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let t = Date(timeIntervalSince1970: 1_700_000_000)

        // Insert 100 days of data, $1 each.
        for daysAgo in 0..<100 {
            try self.insert(context, device: "dev-A", provider: "codex",
                daysAgo: daysAgo, cost: 1.0, tokens: 100, lastUpdated: t)
        }
        try context.save()

        let agg7 = try CostLedgerService.aggregate(
            windowDays: 7, in: context, asOf: Self.asOf)
        #expect(agg7.dailyPoints.count == 7)
        #expect(agg7.totalCostUSD == 7.0)
        #expect(agg7.windowDays == 7)

        let agg30 = try CostLedgerService.aggregate(
            windowDays: 30, in: context, asOf: Self.asOf)
        #expect(agg30.dailyPoints.count == 30)
        #expect(agg30.totalCostUSD == 30.0)

        let agg90 = try CostLedgerService.aggregate(
            windowDays: 90, in: context, asOf: Self.asOf)
        #expect(agg90.dailyPoints.count == 90)
        #expect(agg90.totalCostUSD == 90.0)

        let agg100 = try CostLedgerService.aggregate(
            windowDays: 100, in: context, asOf: Self.asOf)
        #expect(agg100.dailyPoints.count == 100)
        #expect(agg100.totalCostUSD == 100.0)
    }

    @Test("T6: window clamps to [1, 365] — too-small input clamped to 1, too-large to 365")
    func testWindowClamp() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try self.insert(context, device: "dev-A", provider: "codex",
            daysAgo: 0, cost: 1.0, tokens: 100, lastUpdated: t)
        try context.save()

        let aggZero = try CostLedgerService.aggregate(
            windowDays: 0, in: context, asOf: Self.asOf)
        #expect(aggZero.windowDays == 1)

        let aggHuge = try CostLedgerService.aggregate(
            windowDays: 10_000, in: context, asOf: Self.asOf)
        #expect(aggHuge.windowDays == 365)
    }

    @Test("T6: cutoffDayKey — windowDays=1 → today; windowDays=7 → today-6")
    func testCutoffDayKey() {
        // 2026-05-28 UTC
        let asOf = Self.asOf
        #expect(CostLedgerService.cutoffDayKey(windowDays: 1, asOf: asOf) == "2026-05-28")
        #expect(CostLedgerService.cutoffDayKey(windowDays: 7, asOf: asOf) == "2026-05-22")
        #expect(CostLedgerService.cutoffDayKey(windowDays: 30, asOf: asOf) == "2026-04-29")
    }

    // MARK: - aggregateProvider

    @Test("aggregateProvider: returns rollup for the requested provider only")
    func testAggregateProviderFilters() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try self.insert(context, device: "dev-A", provider: "codex",
            daysAgo: 0, cost: 1.0, tokens: 100, lastUpdated: t)
        try self.insert(context, device: "dev-A", provider: "claude",
            daysAgo: 0, cost: 2.0, tokens: 200, lastUpdated: t)
        try context.save()

        let codex = try CostLedgerService.aggregateProvider(
            providerID: "codex", accountEmail: nil, windowDays: 7,
            in: context, asOf: Self.asOf)
        #expect(codex.providerID == "codex")
        #expect(codex.totalCostUSD == 1.0)
    }

    @Test("aggregateProvider: missing provider returns empty rollup (not nil)")
    func testAggregateProviderMissing() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let rollup = try CostLedgerService.aggregateProvider(
            providerID: "nonexistent", accountEmail: nil, windowDays: 7,
            in: context, asOf: Self.asOf)
        #expect(rollup.providerID == "nonexistent")
        #expect(rollup.totalCostUSD == 0)
        #expect(rollup.dailyPoints.isEmpty)
    }

    // MARK: - Multi-account (Round 4 — account-aware key)

    @Test("Multi-account: two accounts of same provider → separate rollups, summed totals")
    func testMultiAccountSeparateRollups() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        // Two Codex accounts, same device + same day.
        try self.insert(context, device: "dev-A", provider: "codex",
            account: "alice@codex.test", daysAgo: 0, cost: 1.0, tokens: 100, lastUpdated: t)
        try self.insert(context, device: "dev-A", provider: "codex",
            account: "bob@codex.test", daysAgo: 0, cost: 2.0, tokens: 200, lastUpdated: t)
        try context.save()

        let agg = try CostLedgerService.aggregate(
            windowDays: 7, in: context, asOf: Self.asOf)

        // Two distinct per-account rollups (NOT merged into one codex rollup).
        #expect(agg.providerRollups.count == 2)
        let alice = try #require(agg.providerRollups["codex|alice@codex.test"])
        let bob = try #require(agg.providerRollups["codex|bob@codex.test"])
        #expect(alice.totalCostUSD == 1.0)
        #expect(alice.accountEmail == "alice@codex.test")
        #expect(bob.totalCostUSD == 2.0)
        #expect(bob.accountEmail == "bob@codex.test")

        // Cross-cutting totals still sum both accounts on the shared day.
        #expect(agg.totalCostUSD == 3.0)
        #expect(agg.activeDayCount == 1)

        // aggregateProvider can fetch a single account's rollup.
        let aliceOnly = try CostLedgerService.aggregateProvider(
            providerID: "codex", accountEmail: "alice@codex.test",
            windowDays: 7, in: context, asOf: Self.asOf)
        #expect(aliceOnly.totalCostUSD == 1.0)
    }

    // MARK: - Diagnostics

    @Test("diagnostics: counts + earliest day + latestWriteAt reflect inserted rows")
    func testDiagnostics() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        // Empty ledger.
        let empty = try CostLedgerService.diagnostics(in: context)
        #expect(empty.rowCount == 0)
        #expect(empty.deviceCount == 0)
        #expect(empty.providerCount == 0)
        #expect(empty.dayCount == 0)
        #expect(empty.earliestDayKey == nil)
        #expect(empty.latestWriteAt == nil)
        #expect(empty.estimatedBytes == 0)

        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = t0.addingTimeInterval(3600)
        try self.insert(context, device: "dev-A", provider: "codex",
            daysAgo: 5, cost: 1.0, tokens: 100, lastUpdated: t0)
        try self.insert(context, device: "dev-A", provider: "claude",
            daysAgo: 0, cost: 2.0, tokens: 200, lastUpdated: t1)
        try self.insert(context, device: "dev-B", provider: "codex",
            daysAgo: 2, cost: 3.0, tokens: 300, lastUpdated: t1)
        try context.save()

        let d = try CostLedgerService.diagnostics(in: context)
        #expect(d.rowCount == 3)
        #expect(d.deviceCount == 2)
        #expect(d.providerCount == 2)
        #expect(d.dayCount == 3)
        #expect(d.earliestDayKey == self.dayKey(daysAgo: 5))
        #expect(d.latestWriteAt == t1)
        #expect(d.estimatedBytes == 600)
    }

    // MARK: - clearAll (T12)

    @Test("T12: clearAll empties the ledger and leaves other entities untouched")
    func testClearAll() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try self.insert(context, device: "dev-A", provider: "codex",
            daysAgo: 0, cost: 1.0, tokens: 100, lastUpdated: t)
        try self.insert(context, device: "dev-A", provider: "claude",
            daysAgo: 1, cost: 2.0, tokens: 200, lastUpdated: t)
        // A different entity that clearAll must NOT touch.
        context.insert(DeviceRecord(
            deviceID: "dev-A", deviceName: "Test", lastSyncAt: t))
        try context.save()
        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).count == 2)

        try CostLedgerService.clearAll(in: context)

        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).isEmpty,
            "ledger must be empty after clearAll")
        #expect(try context.fetch(FetchDescriptor<DeviceRecord>()).count == 1,
            "clearAll must only delete DailyCostPoint, not other entities")
    }
}
