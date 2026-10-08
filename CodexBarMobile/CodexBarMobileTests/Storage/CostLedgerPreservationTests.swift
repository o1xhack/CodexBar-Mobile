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

    @Test func `a provider the Mac stops publishing keeps its history but no longer shows it`() throws {
        let context = try self.makeContext()
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.claude(email: "fixture@example.invalid", cost: 40, at: self.earlier)],
                                          at: self.earlier)],
            into: context)
        let codex = ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex", primary: nil, secondary: nil, accountEmail: nil,
            loginMethod: nil, statusMessage: nil, isError: false, lastUpdated: self.later)
        let current = self.device([codex], at: self.later)
        try SwiftDataBridge.upsert(deviceSnapshots: [current], into: context)
        try SwiftDataBridge.deleteProviderRecords(named: ["studio|claude|fixture@example.invalid"], from: context)
        let aggregation = try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: 365, in: context, asOf: self.later, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(try self.rows(context).count == 1, "turning a provider off must not erase what it cost")
        let insights = CostDashboardInsights.fromLedger(aggregation: aggregation, snapshot: current, now: self.later)
        #expect(insights.providerRows.isEmpty, "history without a live card is kept but not shown")
    }

    @Test func `a renamed record keeps history`() throws {
        let context = try self.makeContext()
        let old = self.claude(email: "fixture@example.invalid", cost: 40, at: self.earlier)
        try SwiftDataBridge.upsert(deviceSnapshots: [self.device([old], at: self.earlier)], into: context)
        // Same delta: the account-less record arrives, then the old record name is deleted.
        try SwiftDataBridge.upsertIncrementalCacheMirror(
            cacheDeviceSnapshots: [self.device([self.claude(email: nil, cost: nil, at: self.later)], at: self.later)],
            deletedRecordNames: ["studio|claude|fixture@example.invalid"],
            into: context)
        #expect(try self.rows(context).first?.costUSD == 40)
    }

    @Test func `a clear tombstone without a new owner keeps the history`() throws {
        let context = try self.makeContext()
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.claude(email: "fixture@example.invalid", cost: 40, at: self.earlier)],
                                          at: self.earlier)],
            into: context)
        let tombstone = ProviderUsageSnapshot(
            providerID: "claude", providerName: "Claude", primary: nil, secondary: nil,
            accountEmail: "fixture@example.invalid", loginMethod: "Max", statusMessage: nil, isError: false,
            lastUpdated: self.later, costSummaryCleared: true)
        try SwiftDataBridge.upsert(deviceSnapshots: [self.device([tombstone], at: self.later)], into: context)
        #expect(try self.rows(context).first?.costUSD == 40)
    }

    private func codex(cost: Double, known: Bool, tokens: Int, at date: Date, day: String? = nil) -> ProviderUsageSnapshot {
        ProviderUsageSnapshot(
            providerID: "codex", providerName: "Codex", primary: nil, secondary: nil,
            accountEmail: "fixture@example.invalid", loginMethod: "Pro", statusMessage: nil, isError: false,
            lastUpdated: date,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil, sessionTokens: nil, last30DaysCostUSD: known ? cost : nil, last30DaysTokens: tokens,
                daily: [SyncDailyPoint(
                    dayKey: day ?? self.day, costUSD: known ? cost : 0, totalTokens: tokens, costIsKnown: known)],
                sourceUpdatedAt: date))
    }

    @Test func `a Mac publishing an unknown day keeps the known amount end to end and does not reseed`() throws {
        let context = try self.makeContext()
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.codex(cost: 363.1, known: true, tokens: 781, at: self.earlier)],
                                          at: self.earlier)],
            into: context)
        let regressed = self.device([self.codex(cost: 0, known: false, tokens: 1531, at: self.later)], at: self.later)
        try SwiftDataBridge.upsert(deviceSnapshots: [regressed], into: context)

        #expect(try CostLedgerService.hasMissingSeedableCostBlobRows(in: context, newerThan: nil) == false)
        let aggregation = try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: 365, in: context, asOf: self.later, userDefaults: defaults)
        let insights = CostDashboardInsights.fromLedger(aggregation: aggregation, snapshot: regressed, now: self.later)
        #expect(insights.providerRows.first?.thirtyDayCost == 363.1)
        let row = try #require(try self.rows(context).first)
        #expect(row.totalTokens == 781, "a kept day keeps its tokens with its amount")

        // The fixed Mac republishes the known amount (and corrected tokens) for that day.
        let fixedAt = self.later.addingTimeInterval(60)
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.codex(cost: 371.2, known: true, tokens: 793, at: fixedAt)], at: fixedAt)],
            into: context)
        #expect(try self.rows(context).first?.costUSD == 371.2)
    }

    @Test func `a known zero or a legacy amount follows the protection rules`() throws {
        let context = try self.makeContext()
        func upsert(_ cost: Double, known: Bool?, at date: Date, day: String) throws {
            try CostLedgerService.upsertDayPoint(
                deviceID: "studio", providerID: "codex", dayKey: day,
                costUSD: cost, totalTokens: 10, costIsKnown: known, isEstimated: nil,
                modelBreakdowns: [], serviceBreakdowns: [], lastUpdated: date, in: context)
        }
        try upsert(0, known: true, at: self.earlier, day: "2026-09-01")
        try upsert(0, known: false, at: self.later, day: "2026-09-01")
        try upsert(12, known: nil, at: self.earlier, day: "2026-09-02")
        try upsert(0, known: false, at: self.later, day: "2026-09-02")
        let rows = Dictionary(uniqueKeysWithValues: try self.rows(context).map { ($0.dayKey, $0) })
        #expect(rows["2026-09-01"]?.costIsKnown == false, "a known $0 has nothing to protect")
        #expect(rows["2026-09-02"]?.costUSD == 12, "a legacy positive amount is known")
    }

    @Test func `merging days prefers a known amount and otherwise the newer row`() throws {
        let context = try self.makeContext()
        func point(_ cost: Double, known: Bool?, at date: Date) -> DailyCostPoint {
            let row = DailyCostPoint(
                deviceID: "studio", providerID: "codex", accountEmail: nil, dayKey: self.day,
                costUSD: cost, totalTokens: 10, isEstimated: nil, modelBreakdownsData: nil,
                serviceBreakdownsData: nil, lastUpdated: date)
            row.costIsKnown = known
            context.insert(row)
            return row
        }
        let knownOld = point(50, known: true, at: self.earlier)
        let unknownNew = point(0, known: false, at: self.later)
        #expect(CostLedgerService.replacesDay(knownOld, with: unknownNew) == false)
        #expect(CostLedgerService.replacesDay(unknownNew, with: knownOld) == true)
        let knownNew = point(40, known: true, at: self.later)
        #expect(CostLedgerService.replacesDay(knownOld, with: knownNew) == true, "a known repricing still applies")
        let zeroOld = point(0, known: true, at: self.earlier)
        #expect(CostLedgerService.replacesDay(zeroOld, with: unknownNew) == true)
    }

    @Test func `the per-day pick across Macs is order independent and prefers the newest known amount`() throws {
        let context = try self.makeContext()
        func point(_ device: String, _ cost: Double, known: Bool, at date: Date) -> DailyCostPoint {
            let row = DailyCostPoint(
                deviceID: device, providerID: "openai", accountEmail: "a@example.invalid", dayKey: self.day,
                costUSD: cost, totalTokens: 1, costIsKnown: known, lastUpdated: date)
            context.insert(row)
            return row
        }
        let positive = point("mac-a", 20, known: true, at: self.earlier)
        let zero = point("mac-b", 0, known: true, at: self.later)
        let unknown = point("mac-c", 0, known: false, at: self.later.addingTimeInterval(60))
        // A newer known $0 is an authoritative correction; only unknown rows fall back.
        for order in [[positive, zero, unknown], [unknown, zero, positive], [zero, unknown, positive]] {
            #expect(CostLedgerService.preferredDay(in: order) === zero)
        }
        for order in [[positive, unknown], [unknown, positive]] {
            #expect(CostLedgerService.preferredDay(in: order) === positive)
        }
        let olderUnknown = point("mac-d", 0, known: false, at: self.earlier)
        #expect(CostLedgerService.preferredDay(in: [olderUnknown, unknown]) === unknown)
    }

    @Test func `every kept day moves to the next local owner and is counted once`() throws {
        let context = try self.makeContext()
        // The old owner has one day only the ledger still holds.
        try CostLedgerService.upsertDayPoint(
            deviceID: "studio", providerID: "claude", accountEmail: "old@example.invalid", dayKey: "2026-06-01",
            costUSD: 30, totalTokens: 10, costIsKnown: true, isEstimated: nil,
            modelBreakdowns: [], serviceBreakdowns: [], lastUpdated: self.earlier, in: context)
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.claude(email: "old@example.invalid", cost: 40, at: self.earlier)],
                                          at: self.earlier)],
            into: context)
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([self.claude(email: nil, cost: nil, at: self.later)], at: self.later)],
            into: context)
        let newOwnerAt = self.later.addingTimeInterval(60)
        let current = self.device([self.claude(email: "new@example.invalid", cost: 45, at: newOwnerAt)], at: newOwnerAt)
        try SwiftDataBridge.upsert(deviceSnapshots: [current], into: context)
        let rows = try self.rows(context)
        #expect(Set(rows.map(\.accountEmail)) == ["new@example.invalid"])
        #expect(rows.count == 2)
        let aggregation = try CostLedgerService.aggregateSeedingFromExistingBlobsIfNeeded(
            windowDays: 365, in: context, asOf: newOwnerAt, userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let insights = CostDashboardInsights.fromLedger(aggregation: aggregation, snapshot: current, now: newOwnerAt)
        #expect(insights.providerRows.count == 1)
        #expect(insights.providerRows.first?.thirtyDayCost == 75)
    }

    @Test func `account-level spend never moves to another account`() throws {
        let context = try self.makeContext()
        func openai(_ email: String, cost: Double?, at date: Date) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "openai", providerName: "OpenAI", primary: nil, secondary: nil,
                accountEmail: email, loginMethod: nil, statusMessage: nil, isError: false, lastUpdated: date,
                costSummary: cost.map {
                    SyncCostSummary(
                        sessionCostUSD: nil, sessionTokens: nil, last30DaysCostUSD: $0, last30DaysTokens: 1,
                        daily: [SyncDailyPoint(dayKey: self.day, costUSD: $0, totalTokens: 1, costIsKnown: true)],
                        sourceUpdatedAt: date)
                })
        }
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([openai("a@example.invalid", cost: 20, at: self.earlier)], at: self.earlier)],
            into: context)
        try SwiftDataBridge.upsert(
            deviceSnapshots: [self.device([openai("b@example.invalid", cost: 5, at: self.later)], at: self.later)],
            into: context)
        let byAccount = Dictionary(grouping: try self.rows(context), by: { $0.accountEmail ?? "" })
        #expect(byAccount["a@example.invalid"]?.first?.costUSD == 20)
        #expect(byAccount["b@example.invalid"]?.first?.costUSD == 5)
    }
}

