import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// Round 2 / P2 of research doc 024. Exercises the writer half of the Cost
/// Window Ledger:
///
/// - **T2**: `upsertDayPoint` dedupes by composite key
///   `(deviceID, providerID, dayKey)` — same key written twice yields one row.
/// - **T3**: Dedup rule = newer `lastUpdated` wins; older or equal is skipped
///   (we already have at-least-as-fresh data for that day).
/// - Gate test: `CostLedgerService.isEnabled(userDefaults:)` reads the flag
///   correctly. The flag's wiring into `SwiftDataBridge.upsertProvider` is
///   covered by inspection — pollution of the shared `UserDefaults.standard`
///   in an integration test is deferred to P4 (where the UI exists to flip
///   the flag end-to-end).
/// - `upsertFromSnapshot` wrapper:iterates `daily[]` and writes one row per day.
@Suite("CWL Writer — upsert dedupe + lastUpdated dedup rule (T2 + T3)")
@MainActor
struct CWLWriterTests {
    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexBarTests-CWLWriter-\(UUID().uuidString)",
                isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Store.sqlite")
    }

    // MARK: - T2

    @Test("T2: same (deviceID, providerID, dayKey) written twice → 1 row")
    func testCompositeKeyDedupe() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 1.0, totalTokens: 100, isEstimated: false,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)

        // Second write with a strictly newer lastUpdated and different costs.
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 2.5, totalTokens: 250, isEstimated: true,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t.addingTimeInterval(60), in: context)

        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1, "Same composite key must dedupe to one row")
        let row = try #require(rows.first)
        #expect(row.compositeKey == "dev-A|codex|_|2026-05-28")
        #expect(row.costUSD == 2.5)
        #expect(row.totalTokens == 250)
        #expect(row.isEstimated == true)
        #expect(row.lastUpdated == t.addingTimeInterval(60))
    }

    @Test("T2: different (providerID, dayKey) under same device → separate rows")
    func testDistinctKeysAreSeparateRows() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 1.0, totalTokens: 100, isEstimated: false,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "claude", dayKey: "2026-05-28",
            costUSD: 1.0, totalTokens: 100, isEstimated: false,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-27",
            costUSD: 1.0, totalTokens: 100, isEstimated: false,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-B", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 1.0, totalTokens: 100, isEstimated: false,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 4, "4 distinct composite keys must yield 4 rows")
    }

    @Test("T2 (multi-account): two accounts, same providerID + dayKey → separate rows (no collide)")
    func testMultiAccountDoesNotCollide() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        // Two Codex accounts, same device, same day — must NOT collide.
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", accountEmail: "alice@codex.test",
            dayKey: "2026-05-28", costUSD: 1.0, totalTokens: 100, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [], lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", accountEmail: "bob@codex.test",
            dayKey: "2026-05-28", costUSD: 2.0, totalTokens: 200, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [], lastUpdated: t, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 2, "Two accounts of the same provider must stay distinct")
        let byEmail = Dictionary(grouping: rows, by: { $0.accountEmail ?? "_" })
        #expect(byEmail["alice@codex.test"]?.first?.costUSD == 1.0)
        #expect(byEmail["bob@codex.test"]?.first?.costUSD == 2.0)
    }

    // MARK: - T3

    @Test("T3: incoming with strictly newer lastUpdated → overwrites")
    func testNewerWins() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 1.0, totalTokens: 100, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 9.9, totalTokens: 9999, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t.addingTimeInterval(3600), in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.costUSD == 9.9, "Newer write must overwrite older")
        #expect(row.totalTokens == 9999)
        #expect(row.lastUpdated == t.addingTimeInterval(3600))
    }

    @Test("T3: incoming with older lastUpdated → skipped (existing kept)")
    func testOlderSkipped() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 5.0, totalTokens: 500, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 0.1, totalTokens: 10, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t.addingTimeInterval(-3600), in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.costUSD == 5.0, "Older write must be rejected")
        #expect(row.lastUpdated == t, "Existing lastUpdated must be preserved")
    }

    @Test("T3: incoming with equal lastUpdated → skipped (existing kept, no churn)")
    func testEqualLastUpdatedSkipped() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 5.0, totalTokens: 500, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try CostLedgerService.upsertDayPoint(
            deviceID: "dev-A", providerID: "codex", dayKey: "2026-05-28",
            costUSD: 7.7, totalTokens: 777, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [],
            lastUpdated: t, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.costUSD == 5.0, "Equal lastUpdated must skip (redundant write)")
    }

    // MARK: - Gate (`isEnabled`)

    @Test("Gate: isEnabled defaults to product default when flag is absent")
    func testGateUsesProductDefaultWhenAbsent() throws {
        let suite = "CWLTestSuite-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(CostLedgerService.isEnabled(userDefaults: defaults) == MobileSettingsDefaults.cwlEnabled)
    }

    @Test("Gate: isEnabled returns true when flag set")
    func testGateRespectsFlag() throws {
        let suite = "CWLTestSuite-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: MobileSettingsKeys.cwlEnabled)
        #expect(CostLedgerService.isEnabled(userDefaults: defaults) == true)

        defaults.set(false, forKey: MobileSettingsKeys.cwlEnabled)
        #expect(CostLedgerService.isEnabled(userDefaults: defaults) == false)
    }

    // MARK: - `upsertFromSnapshot` wrapper

    @Test("upsertFromSnapshot: iterates daily[] and writes one row per day")
    func testUpsertFromSnapshotIterates() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: t,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: 6.0,
                last30DaysTokens: 600,
                daily: [
                    SyncDailyPoint(
                        dayKey: "2026-05-26", costUSD: 1.0, totalTokens: 100,
                        modelBreakdowns: [], serviceBreakdowns: [], isEstimated: false),
                    SyncDailyPoint(
                        dayKey: "2026-05-27", costUSD: 2.0, totalTokens: 200,
                        modelBreakdowns: [], serviceBreakdowns: [], isEstimated: false),
                    SyncDailyPoint(
                        dayKey: "2026-05-28", costUSD: 3.0, totalTokens: 300,
                        modelBreakdowns: [], serviceBreakdowns: [], isEstimated: false),
                ],
                isEstimated: false))

        try CostLedgerService.upsertFromSnapshot(
            snapshot, deviceID: "dev-A", in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 3)
        let byDay = Dictionary(grouping: rows, by: \.dayKey)
        #expect(byDay["2026-05-26"]?.first?.costUSD == 1.0)
        #expect(byDay["2026-05-27"]?.first?.costUSD == 2.0)
        #expect(byDay["2026-05-28"]?.first?.costUSD == 3.0)
        // All days inherit the parent provider's lastUpdated.
        for row in rows {
            #expect(row.lastUpdated == t)
        }
    }

    @Test("upsertFromSnapshot: clear tombstone skips old snapshots and allows newer sync")
    func testUpsertFromSnapshotHonorsClearTombstone() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let suite = "CodexBarTests-CWLWriter-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let oldUpdate = Date(timeIntervalSince1970: 1_700_000_000)
        let clearedAt = oldUpdate.addingTimeInterval(60)
        let newerUpdate = clearedAt.addingTimeInterval(60)
        defaults.set(
            clearedAt.timeIntervalSince1970,
            forKey: MobileSettingsKeys.cwlBlobSeedClearedAt)

        func snapshot(lastUpdated: Date, cost: Double) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: nil,
                loginMethod: nil,
                statusMessage: nil,
                isError: false,
                lastUpdated: lastUpdated,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil,
                    sessionTokens: nil,
                    last30DaysCostUSD: cost,
                    last30DaysTokens: 100,
                    daily: [
                        SyncDailyPoint(
                            dayKey: "2026-05-28",
                            costUSD: cost,
                            totalTokens: 100,
                            modelBreakdowns: [],
                            serviceBreakdowns: [],
                            isEstimated: false),
                    ],
                    isEstimated: false))
        }

        try CostLedgerService.upsertFromSnapshot(
            snapshot(lastUpdated: oldUpdate, cost: 5.0),
            deviceID: "dev-A",
            in: context,
            userDefaults: defaults)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).isEmpty)

        try CostLedgerService.upsertFromSnapshot(
            snapshot(lastUpdated: newerUpdate, cost: 6.0),
            deviceID: "dev-A",
            in: context,
            userDefaults: defaults)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1)
        #expect(rows.first?.costUSD == 6.0)
        #expect(rows.first?.lastUpdated == newerUpdate)
    }

    @Test("upsertFromSnapshot: nil costSummary → no rows written")
    func testNoSummaryNoRows() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let snapshot = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil, secondary: nil,
            accountEmail: nil, loginMethod: nil, statusMessage: nil,
            isError: false,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            costSummary: nil)

        try CostLedgerService.upsertFromSnapshot(
            snapshot, deviceID: "dev-A", in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.isEmpty)
    }
}
