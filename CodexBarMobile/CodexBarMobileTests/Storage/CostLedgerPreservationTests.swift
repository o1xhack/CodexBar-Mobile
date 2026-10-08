import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// The ledger keeps 365 days that a Mac's own logs may no longer hold. A Mac that temporarily
/// loses an account or cannot price a day must not erase that history.
@Suite("Cost ledger preserves history")
struct CostLedgerPreservationTests {
    private let day = "2026-09-20"
    private let earlier = Date(timeIntervalSince1970: 1_791_000_000)
    private var later: Date { self.earlier.addingTimeInterval(3600) }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(CodexBarSwiftDataSchema.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: configuration))
    }

    private func claude(email: String?, cost: Double?, known: Bool = true, at date: Date) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude", primary: nil, secondary: nil,
            accountEmail: email, loginMethod: email == nil ? nil : "Max", statusMessage: nil, isError: false,
            lastUpdated: date,
            costSummary: cost.map { cost in
                SyncCostSummary(
                    sessionCostUSD: nil, sessionTokens: nil, last30DaysCostUSD: cost, last30DaysTokens: 100,
                    daily: [SyncDailyPoint(
                        dayKey: self.day, costUSD: known ? cost : 0, totalTokens: 100, costIsKnown: known)],
                    sourceUpdatedAt: date)
            })
    }

    private func device(_ providers: [ProviderUsageSnapshot], at date: Date) -> SyncedUsageSnapshot {
        SyncedUsageSnapshot(providers: providers, syncTimestamp: date, deviceName: "Mac Studio", deviceID: "studio")
    }

    private func rows(_ context: ModelContext) throws -> [DailyCostPoint] {
        try context.fetch(FetchDescriptor<DailyCostPoint>())
    }

    @Test func `a day the Mac cannot price keeps the amount the ledger already knows`() throws {
        let context = try self.makeContext()
        for (cost, known, date) in [(363.1, true, self.earlier), (0.0, false, self.later)] {
            try CostLedgerService.upsertDayPoint(
                deviceID: "studio", providerID: "codex", dayKey: self.day,
                costUSD: cost, totalTokens: 100, costIsKnown: known, isEstimated: nil,
                modelBreakdowns: [], serviceBreakdowns: [], lastUpdated: date, in: context)
        }
        let row = try #require(try self.rows(context).first)
        #expect(row.costUSD == 363.1)
        #expect(row.costIsKnown == true)

        // A later publication that knows the cost still corrects it.
        try CostLedgerService.upsertDayPoint(
            deviceID: "studio", providerID: "codex", dayKey: self.day,
            costUSD: 350, totalTokens: 90, costIsKnown: true, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [], lastUpdated: self.later.addingTimeInterval(60), in: context)
        #expect(try self.rows(context).first?.costUSD == 350)
    }

    @Test func `an account that becomes unknown on the same Mac keeps its history`() throws {
        let context = try self.makeContext()
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.claude(email: "fixture@example.invalid", cost: 40, at: self.earlier)],
                                          at: self.earlier)],
            into: context)
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.claude(email: nil, cost: nil, at: self.later)], at: self.later)],
            into: context)
        _ = try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: 365, in: context, asOf: self.later, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let rows = try self.rows(context)
        #expect(rows.count == 1)
        #expect(rows.first?.costUSD == 40)
        #expect(rows.first?.accountEmail == "fixture@example.invalid")
    }

    @Test func `kept history moves to the next owner instead of counting twice`() throws {
        let context = try self.makeContext()
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.claude(email: "old@example.invalid", cost: 40, at: self.earlier)],
                                          at: self.earlier)],
            into: context)
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.claude(email: nil, cost: nil, at: self.later)], at: self.later)],
            into: context)
        let newOwnerAt = self.later.addingTimeInterval(60)
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.claude(email: "new@example.invalid", cost: 45, at: newOwnerAt)],
                                          at: newOwnerAt)],
            into: context)
        let rows = try self.rows(context)
        #expect(rows.count == 1)
        #expect(rows.first?.accountEmail == "new@example.invalid")
        #expect(rows.first?.costUSD == 45)
    }

    @Test func `a provider the Mac stops publishing still loses its history`() throws {
        let context = try self.makeContext()
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.claude(email: "fixture@example.invalid", cost: 40, at: self.earlier)],
                                          at: self.earlier)],
            into: context)
        let codex = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex", primary: nil, secondary: nil, accountEmail: nil,
            loginMethod: nil, statusMessage: nil, isError: false, lastUpdated: self.later)
        try SwiftDataBridge.upsert(deviceSnapshots: [self.device([codex], at: self.later)], into: context)
        #expect(try self.rows(context).isEmpty)
    }

    @Test func `a renamed record keeps history and a removed provider drops it`() throws {
        let context = try self.makeContext()
        let old = self.claude(email: "fixture@example.invalid", cost: 40, at: self.earlier)
        try SwiftDataBridge.upsert(deviceSnapshots: [self.device([old], at: self.earlier)], into: context)

        // Same delta: the account-less record arrives, then the old record name is deleted.
        try SwiftDataBridge.upsertIncrementalCacheMirror(
            cacheDeviceSnapshots: [self.device([self.claude(email: nil, cost: nil, at: self.later)], at: self.later)],
            deletedRecordNames: ["studio|claude|fixture@example.invalid"],
            into: context)
        #expect(try self.rows(context).count == 1)

        try SwiftDataBridge.deleteProviderRecords(named: ["studio|claude|_"], from: context)
        _ = try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: 365, in: context, asOf: self.later, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(try self.rows(context).isEmpty)
    }
}
