import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// T10 + T11 (research doc 024 Round 7 / P6) — `seedFromExistingBlobs` imports
/// the existing blob-path data into the ledger on first CWL enable, so the
/// dashboard has history immediately. Corrupt / nil blobs are skipped without
/// crashing; the seed is idempotent.
@Suite("CWL Seed — import existing blobs into ledger (T10 + T11)")
@MainActor
struct CWLSeedTests {
    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexBarTests-CWLSeed-\(UUID().uuidString)",
                isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Store.sqlite")
    }

    private func makeContext() -> (URL, ModelContext) {
        let url = self.makeTempStoreURL()
        return (url, ModelContext(ModelContainerFactory.makeContainer(at: url)))
    }

    private func summaryBlob(daily: [SyncDailyPoint]) -> Data {
        let summary = SyncCostSummary(
            sessionCostUSD: nil, sessionTokens: nil,
            last30DaysCostUSD: nil, last30DaysTokens: nil,
            daily: daily, isEstimated: false)
        return (try? CloudSyncConstants.makeJSONEncoder().encode(summary)) ?? Data()
    }

    private func day(_ key: String, _ cost: Double, _ tokens: Int,
                     models: [SyncCostBreakdown] = []) -> SyncDailyPoint
    {
        SyncDailyPoint(
            dayKey: key, costUSD: cost, totalTokens: tokens,
            modelBreakdowns: models, serviceBreakdowns: [], isEstimated: false)
    }

    // MARK: - T10

    @Test("T10: seed imports daily points from ProviderSnapshotModel blobs, carrying account + device")
    func testSeedImports() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let blob = self.summaryBlob(daily: [
            self.day("2026-05-27", 1.0, 100, models: [SyncCostBreakdown(label: "gpt-5", costUSD: 1.0)]),
            self.day("2026-05-28", 2.0, 200),
        ])
        context.insert(ProviderSnapshotModel(
            deviceID: "dev-A",
            providerID: "codex",
            providerName: "Codex",
            accountEmail: "alice@codex.test",
            lastUpdated: now,
            costSummaryData: blob))
        try context.save()

        try CostLedgerService.seedFromExistingBlobs(in: context)

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 2)
        let byDay = Dictionary(grouping: rows, by: \.dayKey)
        #expect(byDay["2026-05-27"]?.first?.costUSD == 1.0)
        #expect(byDay["2026-05-28"]?.first?.costUSD == 2.0)
        #expect(rows.allSatisfy { $0.accountEmail == "alice@codex.test" })
        #expect(rows.allSatisfy { $0.deviceID == "dev-A" })
        // Model breakdown blob preserved on the day that had one.
        #expect(byDay["2026-05-27"]?.first?.modelBreakdownsData != nil)
    }

    @Test("T10: seed is idempotent — second run is a no-op")
    func testSeedIdempotent() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(ProviderSnapshotModel(
            deviceID: "dev-A", providerID: "codex", providerName: "Codex",
            accountEmail: nil, lastUpdated: now,
            costSummaryData: self.summaryBlob(daily: [self.day("2026-05-28", 5.0, 500)])))
        try context.save()

        try CostLedgerService.seedFromExistingBlobs(in: context)
        try CostLedgerService.seedFromExistingBlobs(in: context)

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1, "Re-seed must not duplicate rows")
        #expect(rows.first?.costUSD == 5.0)
    }

    @Test("T10: default-on aggregate seeds existing blobs before first ledger read")
    func testDefaultOnAggregateSeedsBeforeRead() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let asOf = try #require(CostLedgerService.utcDayKeyFormatter.date(from: "2026-05-28"))
        context.insert(ProviderSnapshotModel(
            deviceID: "dev-A",
            providerID: "codex",
            providerName: "Codex",
            accountEmail: nil,
            lastUpdated: asOf,
            costSummaryData: self.summaryBlob(daily: [self.day("2026-05-28", 5.0, 500)])))
        try context.save()

        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).isEmpty)

        let aggregation = try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: 90,
            in: context,
            asOf: asOf)

        #expect(aggregation.totalCostUSD == 5.0)
        #expect(aggregation.totalTokens == 500)
        #expect(aggregation.providerRollups["codex|_"]?.totalCostUSD == 5.0)
        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).count == 1)
    }

    @Test("T10: default-on aggregate does not reseed blobs older than explicit clear")
    func testDefaultOnAggregateHonorsClearTombstone() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let suiteName = "CodexBarTests-CWLSeed-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let asOf = try #require(CostLedgerService.utcDayKeyFormatter.date(from: "2026-05-28"))
        let clearedAt = asOf.addingTimeInterval(60)
        context.insert(ProviderSnapshotModel(
            deviceID: "dev-A",
            providerID: "codex",
            providerName: "Codex",
            accountEmail: nil,
            lastUpdated: asOf,
            costSummaryData: self.summaryBlob(daily: [self.day("2026-05-28", 5.0, 500)])))
        try context.save()

        try CostLedgerService.seedFromExistingBlobs(in: context)
        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).count == 1)

        try CostLedgerService.clearAll(in: context, clearedAt: clearedAt, userDefaults: defaults)

        let clearedAggregation = try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: 90,
            in: context,
            asOf: asOf,
            userDefaults: defaults)

        #expect(clearedAggregation.totalCostUSD == 0)
        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).isEmpty)

        context.insert(ProviderSnapshotModel(
            deviceID: "dev-A",
            providerID: "claude",
            providerName: "Claude",
            accountEmail: nil,
            lastUpdated: clearedAt.addingTimeInterval(60),
            costSummaryData: self.summaryBlob(daily: [self.day("2026-05-28", 6.0, 600)])))
        try context.save()

        let refreshedAggregation = try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: 90,
            in: context,
            asOf: asOf,
            userDefaults: defaults)

        #expect(refreshedAggregation.totalCostUSD == 6.0)
        #expect(refreshedAggregation.providerRollups["claude|_"]?.totalCostUSD == 6.0)
        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).count == 1)
    }

    // MARK: - T11

    @Test("T11: corrupt blob is skipped, valid rows still seed, no crash")
    func testSeedSkipsCorruptBlob() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Corrupt blob — not decodable as SyncCostSummary.
        context.insert(ProviderSnapshotModel(
            deviceID: "dev-A", providerID: "codex", providerName: "Codex",
            accountEmail: nil, lastUpdated: now,
            costSummaryData: Data("definitely not json".utf8)))
        // Valid blob.
        context.insert(ProviderSnapshotModel(
            deviceID: "dev-A", providerID: "claude", providerName: "Claude",
            accountEmail: nil, lastUpdated: now,
            costSummaryData: self.summaryBlob(daily: [self.day("2026-05-28", 3.0, 300)])))
        try context.save()

        // Must not throw / crash.
        try CostLedgerService.seedFromExistingBlobs(in: context)

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        #expect(rows.count == 1, "Only the valid provider's daily seeds")
        #expect(rows.first?.providerID == "claude")
        #expect(rows.first?.costUSD == 3.0)
    }

    @Test("T11: row with nil costSummaryData is skipped")
    func testSeedSkipsNilBlob() throws {
        let (url, context) = self.makeContext()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }

        context.insert(ProviderSnapshotModel(
            deviceID: "dev-A", providerID: "ollama", providerName: "Ollama",
            accountEmail: nil,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            costSummaryData: nil))
        try context.save()

        try CostLedgerService.seedFromExistingBlobs(in: context)

        #expect(try context.fetch(FetchDescriptor<DailyCostPoint>()).isEmpty)
    }
}
