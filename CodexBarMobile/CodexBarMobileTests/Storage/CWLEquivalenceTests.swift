import CodexBarSync
import Foundation
import SwiftData
import Testing
@testable import CodexBarMobile

/// T7 (research doc 024 Round 5 / P4a) — the CWL ledger path and the existing
/// blob path must produce numerically equivalent `CostDashboardInsights` for
/// the same input. Builds a snapshot, runs the blob `init(snapshot:)`, then
/// feeds the same data through the writer → `aggregate` → `fromLedger` and
/// compares totals / per-provider cost / daily series / model+service mix.
///
/// The fixture pins `last30DaysCostUSD = nil` so the blob path also reduces
/// from `daily[]` (matching how the ledger sums daily rows), and uses a
/// 365-day aggregate window so every fixture day is in range regardless of
/// timezone edges.
@Suite("CWL Equivalence — ledger path == blob path (T7)")
@MainActor
struct CWLEquivalenceTests {
    private static let tolerance = 0.001

    private func makeTempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CodexBarTests-CWLEquiv-\(UUID().uuidString)",
                isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Store.sqlite")
    }

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Recent dayKey, `daysAgo` before now (UTC). Within any reasonable window.
    private func dayKey(daysAgo: Int) -> String {
        let d = Date().addingTimeInterval(-TimeInterval(daysAgo * 86400))
        return Self.utcFormatter.string(from: d)
    }

    private func provider(
        id: String,
        name: String,
        modelLabel: String,
        dailyCosts: [(daysAgo: Int, cost: Double, tokens: Int)],
        lastUpdated: Date) -> ProviderUsageSnapshot
    {
        let daily = dailyCosts.map { entry in
            SyncDailyPoint(
                dayKey: self.dayKey(daysAgo: entry.daysAgo),
                costUSD: entry.cost,
                totalTokens: entry.tokens,
                modelBreakdowns: [SyncCostBreakdown(label: modelLabel, costUSD: entry.cost)],
                serviceBreakdowns: [],
                isEstimated: false)
        }
        return ProviderUsageSnapshot(
            providerID: id,
            providerName: name,
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: "Pro",
            statusMessage: nil,
            isError: false,
            lastUpdated: lastUpdated,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: nil,   // force blob to reduce from daily[]
                last30DaysTokens: nil,
                daily: daily,
                isEstimated: false))
    }

    @Test("Ledger insights numerically match blob insights for the same data")
    func testEquivalence() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let codex = self.provider(
            id: "codex", name: "Codex", modelLabel: "gpt-5",
            dailyCosts: [(0, 1.0, 100), (1, 2.0, 200), (2, 3.0, 300)],
            lastUpdated: now)
        let claude = self.provider(
            id: "claude", name: "Claude", modelLabel: "claude-opus-4-7",
            dailyCosts: [(0, 0.5, 50), (1, 1.5, 150)],
            lastUpdated: now)
        let snapshot = SyncedUsageSnapshot(
            providers: [codex, claude],
            syncTimestamp: now,
            deviceName: "Test Mac",
            deviceID: "test-device")

        // Blob path.
        let blob = CostDashboardInsights(snapshot: snapshot)

        // Ledger path: write → aggregate → fromLedger.
        for provider in snapshot.providers {
            try CostLedgerService.upsertFromSnapshot(
                provider, deviceID: "test-device", in: context)
        }
        try context.save()
        let aggregation = try CostLedgerService.aggregate(windowDays: 365, in: context)
        let ledger = CostDashboardInsights.fromLedger(
            aggregation: aggregation, snapshot: snapshot)

        // --- Totals ---
        #expect(abs(blob.total30DayCost - ledger.total30DayCost) < Self.tolerance)
        #expect(blob.total30DayTokens == ledger.total30DayTokens)
        #expect(blob.activeDayCount == ledger.activeDayCount)

        // --- Provider rows (per provider thirtyDayCost / tokens) ---
        #expect(blob.providerRows.count == ledger.providerRows.count)
        let blobByProvider = Dictionary(
            grouping: blob.providerRows, by: { $0.provider.providerID })
        let ledgerByProvider = Dictionary(
            grouping: ledger.providerRows, by: { $0.provider.providerID })
        for (id, blobRows) in blobByProvider {
            let blobCost = blobRows.reduce(0) { $0 + $1.thirtyDayCost }
            let ledgerCost = (ledgerByProvider[id] ?? []).reduce(0) { $0 + $1.thirtyDayCost }
            #expect(abs(blobCost - ledgerCost) < Self.tolerance, "provider \(id) cost mismatch")
        }

        // --- Daily series (dayKey → costUSD) ---
        let blobDaily = Dictionary(
            uniqueKeysWithValues: blob.dailyPoints.map { ($0.dayKey, $0.costUSD) })
        let ledgerDaily = Dictionary(
            uniqueKeysWithValues: ledger.dailyPoints.map { ($0.dayKey, $0.costUSD) })
        #expect(blobDaily.keys.sorted() == ledgerDaily.keys.sorted())
        for (day, cost) in blobDaily {
            #expect(abs(cost - (ledgerDaily[day] ?? -1)) < Self.tolerance, "day \(day) cost mismatch")
        }

        // --- Model mix (label → amount) ---
        let blobModels = Dictionary(
            uniqueKeysWithValues: blob.modelRows.map { ($0.label, $0.amountUSD) })
        let ledgerModels = Dictionary(
            uniqueKeysWithValues: ledger.modelRows.map { ($0.label, $0.amountUSD) })
        #expect(blobModels.keys.sorted() == ledgerModels.keys.sorted())
        for (label, amount) in blobModels {
            #expect(abs(amount - (ledgerModels[label] ?? -1)) < Self.tolerance, "model \(label) mismatch")
        }
    }

    @Test("Equivalence holds for multi-device local-cost provider totals, daily, model, and service mix")
    func testEquivalenceMultiDeviceLocalCostSums() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let dayKey = self.dayKey(daysAgo: 0)

        func codexProvider(
            cost: Double,
            tokens: Int,
            updated: Date,
            standardCost: Double? = nil,
            priorityCost: Double? = nil
        ) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil,
                secondary: nil,
                accountEmail: "dev@example.com",
                loginMethod: "Pro",
                statusMessage: nil,
                isError: false,
                lastUpdated: updated,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil,
                    sessionTokens: nil,
                    last30DaysCostUSD: nil,
                    last30DaysTokens: nil,
                    daily: [
                        SyncDailyPoint(
                            dayKey: dayKey,
                            costUSD: cost,
                            totalTokens: tokens,
                            modelBreakdowns: [
                                SyncCostBreakdown(
                                    label: "gpt-5",
                                    costUSD: cost,
                                    standardCostUSD: standardCost,
                                    priorityCostUSD: priorityCost),
                            ],
                            serviceBreakdowns: [
                                SyncCostBreakdown(label: "Codex Run", costUSD: cost * 0.8),
                                SyncCostBreakdown(label: "Codex Cloud", costUSD: cost * 0.2),
                            ],
                            isEstimated: false),
                    ],
                    isEstimated: false,
                    historyDays: 30))
        }

        let macA = SyncedUsageSnapshot(
            providers: [
                codexProvider(
                    cost: 1.0,
                    tokens: 100,
                    updated: now.addingTimeInterval(-600),
                    standardCost: 1.0),
            ],
            syncTimestamp: now.addingTimeInterval(-500),
            deviceName: "MacBook Pro",
            deviceID: "dev-A")
        let macB = SyncedUsageSnapshot(
            providers: [
                codexProvider(
                    cost: 9.0,
                    tokens: 900,
                    updated: now.addingTimeInterval(-60),
                    priorityCost: 9.0),
            ],
            syncTimestamp: now.addingTimeInterval(-50),
            deviceName: "Mac Studio",
            deviceID: "dev-B")
        let mergedSnapshot = try #require(CloudSyncReader.mergeSnapshots([macA, macB]))

        let blob = CostDashboardInsights(snapshot: mergedSnapshot)
        for snapshot in [macA, macB] {
            for provider in snapshot.providers {
                try CostLedgerService.upsertFromSnapshot(provider, deviceID: snapshot.deviceID!, in: context)
            }
        }
        try context.save()

        let aggregation = try CostLedgerService.aggregate(
            windowDays: 365,
            in: context,
            activeDeviceIDs: ["dev-A", "dev-B"])
        let ledger = CostDashboardInsights.fromLedger(
            aggregation: aggregation, snapshot: mergedSnapshot)

        #expect(abs(blob.total30DayCost - 10.0) < Self.tolerance)
        #expect(abs(blob.total30DayCost - ledger.total30DayCost) < Self.tolerance)
        #expect(blob.total30DayTokens == ledger.total30DayTokens)
        #expect(blob.dailyPoints.map(\.costUSD) == ledger.dailyPoints.map(\.costUSD))

        let ledgerProvider = try #require(ledger.providerRows.first)
        #expect(abs(ledgerProvider.thirtyDayCost - 10.0) < Self.tolerance)
        #expect(ledgerProvider.thirtyDayTokens == 1_000)
        #expect(ledgerProvider.dailyPoints.first?.costUSD == 10.0)

        let ledgerModels = Dictionary(
            uniqueKeysWithValues: ledger.modelRows.map { ($0.label, $0.amountUSD) })
        let ledgerServices = Dictionary(
            uniqueKeysWithValues: ledger.serviceRows.map { ($0.label, $0.amountUSD) })
        #expect(abs((ledgerModels["gpt-5"] ?? 0) - 10.0) < Self.tolerance)
        #expect(abs((ledgerServices["Codex Run"] ?? 0) - 8.0) < Self.tolerance)
        #expect(abs((ledgerServices["Codex Cloud"] ?? 0) - 2.0) < Self.tolerance)
    }

    @Test("CWL ON: Overview window follows the selected window, not max provider historyDays")
    func testLedgerHistoryDaysFollowsSelectedWindow() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let codex = self.provider(
            id: "codex", name: "Codex", modelLabel: "gpt-5",
            dailyCosts: [(0, 1.0, 100), (1, 2.0, 200)],
            lastUpdated: now)
        let snapshot = SyncedUsageSnapshot(
            providers: [codex], syncTimestamp: now,
            deviceName: "Test Mac", deviceID: "test-device")
        try CostLedgerService.upsertFromSnapshot(codex, deviceID: "test-device", in: context)
        try context.save()

        // Each selected CWL window must drive the Overview "N Days" headline.
        for window in [7, 30, 90, 365] {
            let agg = try CostLedgerService.aggregate(windowDays: window, in: context)
            let insights = CostDashboardInsights.fromLedger(aggregation: agg, snapshot: snapshot)
            #expect(insights.cwlWindowDays == window)
            #expect(insights.historyDays == window, "CWL window \(window) must drive the headline")
        }

        // Blob path carries no override → headline falls back to provider historyDays.
        #expect(CostDashboardInsights(snapshot: snapshot).cwlWindowDays == nil)
    }

    @Test("CWL provider totals use snapshot summary as a floor for longer windows")
    func testLedgerProviderTotalsUseSnapshotSummaryFloor() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))

        let now = Date()
        let claude = ProviderUsageSnapshot(
            providerID: "claude",
            providerName: "Claude",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 1.49,
                sessionTokens: 1_490,
                last30DaysCostUSD: 2_638.98,
                last30DaysTokens: 2_638_980,
                daily: [
                    SyncDailyPoint(
                        dayKey: self.dayKey(daysAgo: 2),
                        costUSD: 42.34,
                        totalTokens: 42_340),
                ],
                historyDays: 30))
        let openai = ProviderUsageSnapshot(
            providerID: "openai",
            providerName: "OpenAI",
            primary: nil,
            secondary: nil,
            accountEmail: "admin@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: 12.34,
                last30DaysTokens: 12_340,
                daily: [],
                historyDays: 30))
        let snapshot = SyncedUsageSnapshot(
            providers: [claude, openai],
            syncTimestamp: now,
            deviceName: "Test Mac",
            deviceID: "test-device")

        try CostLedgerService.upsertFromSnapshot(claude, deviceID: "test-device", in: context)
        try CostLedgerService.upsertFromSnapshot(openai, deviceID: "test-device", in: context)
        try context.save()

        let aggregation = try CostLedgerService.aggregate(windowDays: 90, in: context)
        let insights = CostDashboardInsights.fromLedger(aggregation: aggregation, snapshot: snapshot)
        let row = try #require(insights.providerRows.first { $0.provider.providerID == "claude" })
        let summaryOnlyRow = try #require(insights.providerRows.first { $0.provider.providerID == "openai" })

        #expect(abs(row.thirtyDayCost - 2_638.98) < Self.tolerance)
        #expect(row.thirtyDayTokens == 2_638_980)
        #expect(abs(row.todayCost - 1.49) < Self.tolerance)
        #expect(abs(summaryOnlyRow.thirtyDayCost - 12.34) < Self.tolerance)
        #expect(summaryOnlyRow.thirtyDayTokens == 12_340)
        #expect(abs(insights.total30DayCost - 2_651.32) < Self.tolerance)
    }

    @Test("CWL shorter windows do not inflate from a longer snapshot summary")
    func testLedgerShorterWindowDoesNotUseLongerSnapshotSummary() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))

        let now = Date()
        let codex = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "user@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: 100,
                last30DaysTokens: 10_000,
                daily: [
                    SyncDailyPoint(
                        dayKey: self.dayKey(daysAgo: 0),
                        costUSD: 7,
                        totalTokens: 700),
                ],
                historyDays: 30))
        let snapshot = SyncedUsageSnapshot(
            providers: [codex],
            syncTimestamp: now,
            deviceName: "Test Mac",
            deviceID: "test-device")

        try CostLedgerService.upsertFromSnapshot(codex, deviceID: "test-device", in: context)
        try context.save()

        let aggregation = try CostLedgerService.aggregate(windowDays: 7, in: context)
        let insights = CostDashboardInsights.fromLedger(aggregation: aggregation, snapshot: snapshot)
        let row = try #require(insights.providerRows.first)

        #expect(abs(row.thirtyDayCost - 7) < Self.tolerance)
        #expect(row.thirtyDayTokens == 700)
    }

    @Test("CWL token-only today stays unavailable instead of falling back to session cost")
    func testLedgerTokenOnlyTodayStaysUnavailable() throws {
        let todayKey = SyncCostSummary.iso8601DayKey(for: Date())
        let point = SyncDailyPoint(
            dayKey: todayKey,
            costUSD: 0,
            totalTokens: 900,
            costIsKnown: false)
        let rollup = CostLedgerProviderRollup(
            providerID: "grok",
            accountEmail: nil,
            totalCostUSD: 0,
            totalTokens: 900,
            dailyPoints: [point],
            modelBreakdowns: [],
            serviceBreakdowns: [])
        let aggregation = CostLedgerAggregation(
            windowDays: 30,
            totalCostUSD: 0,
            totalTokens: 900,
            activeDayCount: 0,
            providerRollups: ["grok": rollup],
            dailyPoints: [point],
            modelMix: [],
            serviceMix: [])
        let provider = ProviderUsageSnapshot(
            providerID: "grok",
            providerName: "Grok",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: 12,
                sessionTokens: 900,
                last30DaysCostUSD: nil,
                last30DaysTokens: 900,
                daily: []))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: Date(),
            deviceName: "Mac")

        let insights = CostDashboardInsights.fromLedger(
            aggregation: aggregation,
            snapshot: snapshot)
        let row = try #require(insights.providerRows.first)

        #expect(row.todayCost == 0)
        #expect(!row.todayCostIsKnown)
        #expect(insights.hasIncompleteCostData)
    }

    @Test("CWL keeps coverage-only providers visible for the incomplete warning")
    func testLedgerKeepsCoverageOnlyProvider() throws {
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: nil,
                last30DaysTokens: nil,
                daily: [],
                coverage: SyncCostCoverage(priced: 0, unpriced: 0, unmetered: 1, estimated: 0),
                historyCoverageIsEstablished: false))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: Date(),
            deviceName: "Mac")
        let aggregation = CostLedgerAggregation(
            windowDays: 30,
            totalCostUSD: 0,
            totalTokens: 0,
            activeDayCount: 0,
            providerRollups: [:],
            dailyPoints: [],
            modelMix: [],
            serviceMix: [])

        let insights = CostDashboardInsights.fromLedger(
            aggregation: aggregation,
            snapshot: snapshot)

        #expect(insights.providerRows.count == 1)
        #expect(insights.hasDisplayData)
        #expect(insights.hasIncompleteCostData)
        #expect(!insights.total30DayCostIsKnown)
    }

    @Test("CWL keeps authoritative zero summaries visible and known")
    func testLedgerKeepsAuthoritativeZeroSummary() throws {
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: Date(),
            costSummary: SyncCostSummary(
                sessionCostUSD: 0,
                sessionTokens: 0,
                last30DaysCostUSD: 0,
                last30DaysTokens: 0,
                daily: [],
                historyDays: 30,
                historyCoverageIsEstablished: true))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: Date(),
            deviceName: "Mac")
        let aggregation = CostLedgerAggregation(
            windowDays: 30,
            totalCostUSD: 0,
            totalTokens: 0,
            activeDayCount: 0,
            providerRollups: [:],
            dailyPoints: [],
            modelMix: [],
            serviceMix: [])

        let insights = CostDashboardInsights.fromLedger(
            aggregation: aggregation,
            snapshot: snapshot)

        #expect(insights.providerRows.count == 1)
        #expect(insights.total30DayCost == 0)
        #expect(insights.totalTodayCost == 0)
        #expect(insights.total30DayCostIsKnown)
        #expect(insights.totalTodayCostIsKnown)
        #expect(!insights.hasIncompleteCostData)
    }

    @Test("Equivalence holds with multi-account providers (two Codex accounts)")
    func testEquivalenceMultiAccount() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let container = ModelContainerFactory.makeContainer(at: url)
        let context = ModelContext(container)

        let now = Date(timeIntervalSince1970: 1_700_000_000)

        func codexAccount(_ email: String, cost: Double) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
                primary: nil, secondary: nil,
                accountEmail: email,
                loginMethod: "Pro", statusMessage: nil, isError: false,
                lastUpdated: now,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil, sessionTokens: nil,
                    last30DaysCostUSD: nil, last30DaysTokens: nil,
                    daily: [SyncDailyPoint(
                        dayKey: self.dayKey(daysAgo: 0),
                        costUSD: cost, totalTokens: Int(cost * 100),
                        modelBreakdowns: [], serviceBreakdowns: [], isEstimated: false)],
                    isEstimated: false))
        }

        let snapshot = SyncedUsageSnapshot(
            providers: [
                codexAccount("alice@codex.test", cost: 1.0),
                codexAccount("bob@codex.test", cost: 2.0),
            ],
            syncTimestamp: now,
            deviceName: "Test Mac",
            deviceID: "test-device")

        let blob = CostDashboardInsights(snapshot: snapshot)
        for provider in snapshot.providers {
            try CostLedgerService.upsertFromSnapshot(
                provider, deviceID: "test-device", in: context)
        }
        try context.save()
        let aggregation = try CostLedgerService.aggregate(windowDays: 365, in: context)
        let ledger = CostDashboardInsights.fromLedger(
            aggregation: aggregation, snapshot: snapshot)

        // Both paths keep the two accounts as separate rows (the whole point
        // of the Round 4 account-aware key).
        #expect(blob.providerRows.count == 2)
        #expect(ledger.providerRows.count == 2)
        #expect(abs(blob.total30DayCost - ledger.total30DayCost) < Self.tolerance)
        #expect(abs(ledger.total30DayCost - 3.0) < Self.tolerance)
    }
}
