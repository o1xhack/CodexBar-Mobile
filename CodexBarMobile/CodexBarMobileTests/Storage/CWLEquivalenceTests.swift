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
/// UTC reader clock for UTC day keys, including when UTC is ahead of the
/// machine local date. Explicit cross-timezone cases below keep their own clocks.
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
        lastUpdated: Date,
        reportingPeriod: String? = nil) -> ProviderUsageSnapshot
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
                last30DaysCostUSD: nil, // force blob to reduce from daily[]
                last30DaysTokens: nil,
                daily: daily,
                isEstimated: false,
                reportingPeriod: reportingPeriod))
    }

    @Test
    func `Ledger insights numerically match blob insights for the same data`() throws {
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
        let aggregation = try CostLedgerService.aggregate(
                windowDays: 365, in: context, readerTimeZone: TimeZone(secondsFromGMT: 0)!)
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

    @Test
    func `Equivalence holds for multi-device local-cost provider totals, daily, model, and service mix`() throws {
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
            priorityCost: Double? = nil) -> ProviderUsageSnapshot
        {
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
                try CostLedgerService.upsertFromSnapshot(
                    provider,
                    deviceID: #require(snapshot.deviceID),
                    in: context)
            }
        }
        try context.save()

        let aggregation = try CostLedgerService.aggregate(
            windowDays: 365,
            in: context,
            activeDeviceIDs: ["dev-A", "dev-B"],
            readerTimeZone: TimeZone(secondsFromGMT: 0)!)
        let ledger = CostDashboardInsights.fromLedger(
            aggregation: aggregation, snapshot: mergedSnapshot)

        #expect(abs(blob.total30DayCost - 10.0) < Self.tolerance)
        #expect(abs(blob.total30DayCost - ledger.total30DayCost) < Self.tolerance)
        #expect(blob.total30DayTokens == ledger.total30DayTokens)
        #expect(blob.dailyPoints.map(\.costUSD) == ledger.dailyPoints.map(\.costUSD))

        let ledgerProvider = try #require(ledger.providerRows.first)
        #expect(abs(ledgerProvider.thirtyDayCost - 10.0) < Self.tolerance)
        #expect(ledgerProvider.thirtyDayTokens == 1000)
        #expect(ledgerProvider.dailyPoints.first?.costUSD == 10.0)

        let ledgerModels = Dictionary(
            uniqueKeysWithValues: ledger.modelRows.map { ($0.label, $0.amountUSD) })
        let ledgerServices = Dictionary(
            uniqueKeysWithValues: ledger.serviceRows.map { ($0.label, $0.amountUSD) })
        #expect(abs((ledgerModels["gpt-5"] ?? 0) - 10.0) < Self.tolerance)
        #expect(abs((ledgerServices["Codex Run"] ?? 0) - 8.0) < Self.tolerance)
        #expect(abs((ledgerServices["Codex Cloud"] ?? 0) - 2.0) < Self.tolerance)
    }

    @Test
    func `CWL ON: Overview window follows the selected window, not max provider historyDays`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let codex = self.provider(
            id: "codex", name: "Codex", modelLabel: "gpt-5",
            dailyCosts: [(0, 1.0, 100), (1, 2.0, 200)],
            lastUpdated: now,
            reportingPeriod: "all")
        let snapshot = SyncedUsageSnapshot(
            providers: [codex], syncTimestamp: now,
            deviceName: "Test Mac", deviceID: "test-device")
        try CostLedgerService.upsertFromSnapshot(codex, deviceID: "test-device", in: context)
        try context.save()

        // Each selected CWL window must drive the Overview "N Days" headline.
        for window in [7, 30, 90, 365] {
            let agg = try CostLedgerService.aggregate(
                windowDays: window, in: context, readerTimeZone: TimeZone(secondsFromGMT: 0)!)
            let insights = CostDashboardInsights.fromLedger(aggregation: agg, snapshot: snapshot)
            #expect(insights.cwlWindowDays == window)
            #expect(insights.historyDays == window, "CWL window \(window) must drive the headline")
            #expect(insights.historyDisplayTitle == SyncCostSummary.localizedRollingPeriodTitle(window))
        }

        // Blob path carries no override → headline falls back to provider historyDays.
        #expect(CostDashboardInsights(snapshot: snapshot).cwlWindowDays == nil)
    }

    @Test
    func `blob Overview follows a shared reporting period and suppresses mixed totals`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func provider(
            id: String,
            period: String,
            days: Int,
            historyWindowIsComparable: Bool? = nil) -> ProviderUsageSnapshot
        {
            ProviderUsageSnapshot(
                providerID: id,
                providerName: id,
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
                    last30DaysCostUSD: 12,
                    last30DaysTokens: 120,
                    daily: [],
                    historyDays: days,
                    reportingPeriod: period,
                    historyWindowIsComparable: historyWindowIsComparable))
        }
        func insights(_ providers: [ProviderUsageSnapshot]) -> CostDashboardInsights {
            CostDashboardInsights(snapshot: SyncedUsageSnapshot(
                providers: providers,
                syncTimestamp: now,
                deviceName: "Test Mac"))
        }

        let allTime = insights([
            provider(id: "codex", period: "all", days: 120),
            provider(id: "claude", period: "all", days: 365),
        ])
        #expect(allTime.hasComparableHistoryTotals)
        #expect(allTime.historyDisplayTitle == String(localized: "All"))
        #expect(allTime.total30DayCostIsKnown)

        let mixed = insights([
            provider(id: "codex", period: "rolling:30", days: 30),
            provider(id: "claude", period: "month-to-date", days: 30),
        ])
        #expect(!mixed.hasComparableHistoryTotals)
        #expect(mixed.historyDisplayTitle == String(localized: "Mixed cost windows"))
        #expect(!mixed.total30DayCostIsKnown)
        #expect(mixed.total30DayTokens == 0)
        #expect(mixed.spendProviderRows.isEmpty)

        let mixedMacs = insights([
            provider(id: "codex", period: "all", days: 365, historyWindowIsComparable: false),
        ])
        #expect(!mixedMacs.hasComparableHistoryTotals)
        #expect(!mixedMacs.total30DayCostIsKnown)
    }

    @Test
    func `blob MTD totals require matching producer month boundaries`() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func provider(id: String, day: String?, zone: String?) -> ProviderUsageSnapshot {
            ProviderUsageSnapshot(
                providerID: id, providerName: id, primary: nil, secondary: nil,
                accountEmail: nil, loginMethod: nil, statusMessage: nil, isError: false,
                lastUpdated: now,
                costSummary: SyncCostSummary(
                    sessionCostUSD: nil, sessionTokens: nil, last30DaysCostUSD: 12,
                    last30DaysTokens: 120, daily: [], reportingPeriod: "month-to-date",
                    sourceDayKey: day, bucketTimeZoneIdentifier: zone))
        }
        func insights(dayA: String?, zoneA: String?, dayB: String?, zoneB: String?) -> CostDashboardInsights {
            CostDashboardInsights(snapshot: SyncedUsageSnapshot(
                providers: [
                    provider(id: "openai", day: dayA, zone: zoneA),
                    provider(id: "claude", day: dayB, zone: zoneB),
                ], syncTimestamp: now, deviceName: "Synthetic Mac"), now: now)
        }
        let sameMonth = insights(dayA: "2026-10-01", zoneA: "UTC", dayB: "2026-10-02", zoneB: "GMT")
        #expect(sameMonth.hasComparableHistoryTotals)
        #expect(sameMonth.total30DayCostIsKnown)
        for mixed in [
            insights(dayA: "2026-10-01", zoneA: "UTC", dayB: "2026-09-30", zoneB: "America/Los_Angeles"),
            insights(dayA: "2026-10-01", zoneA: "UTC", dayB: "2026-10-01", zoneB: "America/Los_Angeles"),
            insights(dayA: "2026-10-01", zoneA: "UTC", dayB: "2026-09-30", zoneB: "UTC"),
            insights(dayA: "2026-10-01", zoneA: "UTC", dayB: nil, zoneB: nil),
            insights(dayA: "2026-10-01", zoneA: "UTC", dayB: "2026-10-01", zoneB: "invalid-zone"),
            insights(dayA: "2026-10-01", zoneA: "UTC", dayB: "2026-02-30", zoneB: "UTC"),
        ] {
            #expect(!mixed.hasComparableHistoryTotals)
            #expect(!mixed.total30DayCostIsKnown)
            #expect(mixed.total30DayTokens == 0)
            #expect(mixed.spendProviderRows.isEmpty)
            #expect(mixed.historyDisplayTitle == String(localized: "Mixed cost windows"))
        }
    }

    @Test
    func `CWL summary totals require the selected reporting period`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let point = SyncDailyPoint(
            dayKey: "2023-11-14",
            costUSD: 7,
            totalTokens: 70,
            costIsKnown: true)
        let rollup = CostLedgerProviderRollup(
            providerID: "codex",
            accountEmail: nil,
            totalCostUSD: 7,
            totalTokens: 70,
            dailyPoints: [point],
            modelBreakdowns: [],
            serviceBreakdowns: [])

        func provider(
            reportingPeriod: String?,
            historyDays: Int?) -> ProviderUsageSnapshot
        {
            ProviderUsageSnapshot(
                providerID: "codex",
                providerName: "Codex",
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
                    last30DaysCostUSD: 12,
                    last30DaysTokens: 120,
                    daily: [],
                    historyDays: historyDays,
                    reportingPeriod: reportingPeriod))
        }

        let monthToDate = CostDashboardInsights.ledgerDisplayTotals(
            rollup: rollup,
            provider: provider(reportingPeriod: "month-to-date", historyDays: 28),
            windowDays: 30)
        #expect(monthToDate.costUSD == 7)
        #expect(monthToDate.tokens == 70)
        #expect(!monthToDate.costIsKnown)

        let matchingRolling = CostDashboardInsights.ledgerDisplayTotals(
            rollup: rollup,
            provider: provider(reportingPeriod: "rolling:30", historyDays: 30),
            windowDays: 30)
        #expect(matchingRolling.costUSD == 12)
        #expect(matchingRolling.tokens == 120)
        #expect(matchingRolling.costIsKnown)

        let legacyThirtyDay = CostDashboardInsights.ledgerDisplayTotals(
            rollup: rollup,
            provider: provider(reportingPeriod: nil, historyDays: 30),
            windowDays: 30)
        #expect(legacyThirtyDay.costUSD == 12)
        #expect(legacyThirtyDay.tokens == 120)
    }

    @Test
    func `completed wider history treats omitted active-day rows as zero in a shorter window`() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-29T12:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let activeDays = [0, 3].map { offset -> SyncDailyPoint in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            return SyncDailyPoint(
                dayKey: formatter.string(from: date),
                costUSD: offset == 0 ? 2 : 5,
                totalTokens: offset == 0 ? 20 : 50,
                costIsKnown: true)
        }
        let summary = SyncCostSummary(
            sessionCostUSD: 2,
            sessionTokens: 20,
            last30DaysCostUSD: 40,
            last30DaysTokens: 400,
            daily: activeDays,
            historyDays: 30,
            reportingPeriod: "rolling:30",
            sourceUpdatedAt: now,
            sourceDayKey: formatter.string(from: today),
            sessionDayKey: formatter.string(from: today),
            bucketTimeZoneIdentifier: "UTC",
            sessionCostIsKnown: true,
            historyCoverageIsEstablished: true,
            historyWindowIsComparable: true,
            reportingPeriodSummary: SyncCostPeriodSummary(
                costUSD: 40,
                tokens: 400,
                daily: activeDays,
                historyDays: 30,
                historyCoverageIsEstablished: true,
                historyWindowIsComparable: true))
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: "dev@example.com",
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: summary)
        let rollup = try CostLedgerProviderRollup(
            providerID: "codex",
            accountEmail: "dev@example.com",
            totalCostUSD: 7,
            totalTokens: 70,
            dailyPoints: activeDays,
            modelBreakdowns: [],
            serviceBreakdowns: [])

        let totals = CostDashboardInsights.ledgerDisplayTotals(
            rollup: rollup,
            provider: provider,
            windowDays: 7,
            now: now,
            calendar: calendar)

        #expect(totals.costUSD == 7)
        #expect(totals.tokens == 70)
        #expect(totals.costIsKnown)
    }

    @Test
    func `CWL month-to-date daily fallback stays incomplete for a thirty-day window`() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-28T12:00:00Z"))
        let timeZone = try #require(TimeZone(identifier: "UTC"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let daily = (0..<28).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            return SyncDailyPoint(
                dayKey: formatter.string(from: date),
                costUSD: 1,
                totalTokens: 10,
                costIsKnown: true)
        }
        let provider = ProviderUsageSnapshot(
            providerID: "mistral",
            providerName: "Mistral",
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
                last30DaysCostUSD: 28,
                last30DaysTokens: 280,
                daily: daily,
                historyDays: 28,
                reportingPeriod: "month-to-date",
                sourceUpdatedAt: now,
                sourceDayKey: formatter.string(from: today),
                bucketTimeZoneIdentifier: timeZone.identifier,
                historyCoverageIsEstablished: true))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "mistral-month-to-date")
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
            snapshot: snapshot,
            now: now,
            calendar: calendar)
        let row = try #require(insights.providerRows.first)
        #expect(row.thirtyDayCost == 28)
        #expect(!row.thirtyDayCostIsKnown)
        #expect(!insights.total30DayCostIsKnown)
        #expect(insights.hasIncompleteCostData)
    }

    @Test
    func `CWL ledger does not reuse an incomparable synced window total`() throws {
        let url = self.makeTempStoreURL()
        defer { ModelContainerFactory.deleteStoreFiles(at: url) }
        let context = ModelContext(ModelContainerFactory.makeContainer(at: url))
        let now = Date()
        let provider = ProviderUsageSnapshot(
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
                sessionCostUSD: nil,
                sessionTokens: nil,
                last30DaysCostUSD: 37,
                last30DaysTokens: 3_700,
                daily: [SyncDailyPoint(
                    dayKey: self.dayKey(daysAgo: 0),
                    costUSD: 5,
                    totalTokens: 500,
                    costIsKnown: true)],
                historyDays: 30,
                reportingPeriod: "all",
                historyWindowIsComparable: false))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mixed-window Macs",
            deviceID: "mixed-window")
        try CostLedgerService.upsertFromSnapshot(provider, deviceID: "mixed-window", in: context)
        try context.save()

        let aggregation = try CostLedgerService.aggregate(
            windowDays: 30,
            in: context,
            readerTimeZone: TimeZone(secondsFromGMT: 0)!)
        let insights = CostDashboardInsights.fromLedger(
            aggregation: aggregation,
            snapshot: snapshot,
            now: now,
            calendar: Calendar(identifier: .gregorian))

        #expect(insights.total30DayCost == 5)
        #expect(insights.providerRows.first?.thirtyDayCost == 5)
    }

    @Test
    func `CWL provider totals do not reuse a shorter summary for longer windows`() throws {
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
                sessionTokens: 1490,
                last30DaysCostUSD: 2638.98,
                last30DaysTokens: 2_638_980,
                daily: [
                    SyncDailyPoint(
                        dayKey: self.dayKey(daysAgo: 2),
                        costUSD: 42.34,
                        totalTokens: 42340),
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
                last30DaysTokens: 12340,
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

        let aggregation = try CostLedgerService.aggregate(
                windowDays: 90, in: context, readerTimeZone: TimeZone(secondsFromGMT: 0)!)
        let insights = CostDashboardInsights.fromLedger(aggregation: aggregation, snapshot: snapshot)
        let row = try #require(insights.providerRows.first { $0.provider.providerID == "claude" })
        let summaryOnlyRow = try #require(insights.providerRows.first { $0.provider.providerID == "openai" })

        #expect(abs(row.thirtyDayCost - 42.34) < Self.tolerance)
        #expect(row.thirtyDayTokens == 42340)
        #expect(abs(row.todayCost - 1.49) < Self.tolerance)
        #expect(summaryOnlyRow.thirtyDayCost == 0)
        #expect(summaryOnlyRow.thirtyDayTokens == 0)
        #expect(!summaryOnlyRow.thirtyDayCostIsKnown)
        #expect(abs(insights.total30DayCost - 42.34) < Self.tolerance)
    }

    @Test
    func `CWL shorter windows do not inflate from a longer snapshot summary`() throws {
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
                last30DaysTokens: 10000,
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

        let aggregation = try CostLedgerService.aggregate(
                windowDays: 7, in: context, readerTimeZone: TimeZone(secondsFromGMT: 0)!)
        let insights = CostDashboardInsights.fromLedger(aggregation: aggregation, snapshot: snapshot)
        let row = try #require(insights.providerRows.first)

        #expect(abs(row.thirtyDayCost - 7) < Self.tolerance)
        #expect(row.thirtyDayTokens == 700)
    }

    @Test
    func `CWL token-only today stays unavailable instead of falling back to session cost`() throws {
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

    @Test
    func `CWL reader-relative rollup day is not remapped through the producer twice`() throws {
        let previousDefault = NSTimeZone.default
        NSTimeZone.default = try #require(TimeZone(identifier: "America/Los_Angeles"))
        defer { NSTimeZone.default = previousDefault }

        let now = try #require(ISO8601DateFormatter().date(from: "2026-05-29T00:30:00Z"))
        let point = SyncDailyPoint(
            dayKey: "2026-05-28",
            costUSD: 7,
            totalTokens: 700,
            costIsKnown: true)
        let rollup = CostLedgerProviderRollup(
            providerID: "codex",
            accountEmail: nil,
            totalCostUSD: 7,
            totalTokens: 700,
            dailyPoints: [point],
            modelBreakdowns: [],
            serviceBreakdowns: [])
        let aggregation = CostLedgerAggregation(
            windowDays: 7,
            totalCostUSD: 7,
            totalTokens: 700,
            activeDayCount: 1,
            providerRollups: ["codex": rollup],
            dailyPoints: [point],
            modelMix: [],
            serviceMix: [])
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 7,
                sessionTokens: 700,
                last30DaysCostUSD: 7,
                last30DaysTokens: 700,
                daily: [SyncDailyPoint(
                    dayKey: "2026-05-29",
                    costUSD: 7,
                    totalTokens: 700,
                    costIsKnown: true)],
                sourceDayKey: "2026-05-29",
                sessionDayKey: "2026-05-29",
                bucketTimeZoneIdentifier: "UTC",
                sessionCostIsKnown: true,
                historyCoverageIsEstablished: true))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac",
            deviceID: "dev-A")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))

        let insights = CostDashboardInsights.fromLedger(
            aggregation: aggregation,
            snapshot: snapshot,
            now: now,
            calendar: calendar)

        #expect(insights.dailyPoints.map(\.dayKey) == ["2026-05-28"])
        #expect(insights.providerRows.first?.dailyPoints.map(\.dayKey) == ["2026-05-28"])
        #expect(insights.providerRows.first?.todayCost == 7)
        #expect(insights.providerRows.first?.dailyPointsUseReaderCalendar == true)
    }

    @Test
    func `CWL applies live source freshness to a stored Today row`() throws {
        let now = Date()
        let staleSource = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let todayKey = SyncCostSummary.iso8601DayKey(for: now)
        let point = SyncDailyPoint(
            dayKey: todayKey,
            costUSD: 5,
            totalTokens: 500,
            costIsKnown: true)
        let rollup = CostLedgerProviderRollup(
            providerID: "codex",
            accountEmail: nil,
            totalCostUSD: 5,
            totalTokens: 500,
            dailyPoints: [point],
            modelBreakdowns: [],
            serviceBreakdowns: [])
        let aggregation = CostLedgerAggregation(
            windowDays: 30,
            totalCostUSD: 5,
            totalTokens: 500,
            activeDayCount: 1,
            providerRollups: ["codex": rollup],
            dailyPoints: [point],
            modelMix: [],
            serviceMix: [])
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 5,
                sessionTokens: 500,
                last30DaysCostUSD: 5,
                last30DaysTokens: 500,
                daily: [point],
                sourceUpdatedAt: staleSource,
                sourceDayKey: SyncCostSummary.iso8601DayKey(for: staleSource),
                sessionDayKey: SyncCostSummary.iso8601DayKey(for: staleSource),
                sessionCostIsKnown: true,
                historyCoverageIsEstablished: true))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac")

        let insights = CostDashboardInsights.fromLedger(
            aggregation: aggregation,
            snapshot: snapshot)

        let row = try #require(insights.providerRows.first)
        #expect(row.todayCost == 0)
        #expect(!row.todayCostIsKnown)
        #expect(!insights.totalTodayCostIsKnown)
        #expect(insights.hasIncompleteCostData)
    }

    @Test
    func `CWL explicit Today unavailability wins over a known live summary`() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-05-29T00:30:00Z"))
        var readerCalendar = Calendar(identifier: .gregorian)
        readerCalendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let readerTodayKey = "2026-05-28"
        let producerTodayKey = "2026-05-29"
        let unavailablePoint = SyncDailyPoint(
            dayKey: readerTodayKey,
            costUSD: 5,
            totalTokens: 500,
            costIsKnown: false)
        let rollup = CostLedgerProviderRollup(
            providerID: "codex",
            accountEmail: nil,
            totalCostUSD: 5,
            totalTokens: 500,
            dailyPoints: [unavailablePoint],
            modelBreakdowns: [],
            serviceBreakdowns: [])
        let aggregation = CostLedgerAggregation(
            windowDays: 30,
            totalCostUSD: 5,
            totalTokens: 500,
            activeDayCount: 1,
            providerRollups: ["codex": rollup],
            dailyPoints: [unavailablePoint],
            modelMix: [],
            serviceMix: [])
        let liveKnownPoint = SyncDailyPoint(
            dayKey: producerTodayKey,
            costUSD: 5,
            totalTokens: 500,
            costIsKnown: true)
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 5,
                sessionTokens: 500,
                last30DaysCostUSD: 5,
                last30DaysTokens: 500,
                daily: [liveKnownPoint],
                sourceUpdatedAt: now,
                sourceDayKey: producerTodayKey,
                sessionDayKey: producerTodayKey,
                bucketTimeZoneIdentifier: "UTC",
                sessionCostIsKnown: true,
                historyCoverageIsEstablished: true))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac")

        let insights = CostDashboardInsights.fromLedger(
            aggregation: aggregation,
            snapshot: snapshot,
            now: now,
            calendar: readerCalendar)

        let row = try #require(insights.providerRows.first)
        #expect(row.todayCost == 0)
        #expect(!row.todayCostIsKnown)
        #expect(!insights.totalTodayCostIsKnown)
        #expect(insights.hasIncompleteCostData)
    }

    @Test
    func `CWL reader keys stay Gregorian under a non-Gregorian system calendar`() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-05-29T00:30:00Z"))
        var readerCalendar = Calendar(identifier: .buddhist)
        readerCalendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let ledgerPoint = SyncDailyPoint(
            dayKey: "2026-05-28",
            costUSD: 9,
            totalTokens: 900,
            costIsKnown: true)
        let rollup = CostLedgerProviderRollup(
            providerID: "codex",
            accountEmail: nil,
            totalCostUSD: 9,
            totalTokens: 900,
            dailyPoints: [ledgerPoint],
            modelBreakdowns: [],
            serviceBreakdowns: [])
        let aggregation = CostLedgerAggregation(
            windowDays: 7,
            totalCostUSD: 9,
            totalTokens: 900,
            activeDayCount: 1,
            providerRollups: ["codex": rollup],
            dailyPoints: [ledgerPoint],
            modelMix: [],
            serviceMix: [])
        let provider = ProviderUsageSnapshot(
            providerID: "codex",
            providerName: "Codex",
            primary: nil,
            secondary: nil,
            accountEmail: nil,
            loginMethod: nil,
            statusMessage: nil,
            isError: false,
            lastUpdated: now,
            costSummary: SyncCostSummary(
                sessionCostUSD: 7,
                sessionTokens: 700,
                last30DaysCostUSD: 7,
                last30DaysTokens: 700,
                daily: [SyncDailyPoint(
                    dayKey: "2026-05-29",
                    costUSD: 7,
                    totalTokens: 700,
                    costIsKnown: true)],
                sourceUpdatedAt: now,
                sourceDayKey: "2026-05-29",
                sessionDayKey: "2026-05-29",
                bucketTimeZoneIdentifier: "UTC",
                sessionCostIsKnown: true,
                historyCoverageIsEstablished: true))
        let snapshot = SyncedUsageSnapshot(
            providers: [provider],
            syncTimestamp: now,
            deviceName: "Mac")

        let insights = CostDashboardInsights.fromLedger(
            aggregation: aggregation,
            snapshot: snapshot,
            now: now,
            calendar: readerCalendar)
        let row = try #require(insights.providerRows.first)

        #expect(row.todayCost == 9)
        #expect(row.todayCostIsKnown)
        #expect(insights.totalTodayCostIsKnown)
        #expect(insights.dailyPoints.map(\.dayKey) == ["2026-05-28"])
    }

    @Test
    func `CWL keeps coverage-only providers visible for the incomplete warning`() {
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

    @Test
    func `CWL keeps authoritative zero summaries visible and known`() {
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

    @Test
    func `Equivalence holds with multi-account providers (two Codex accounts)`() throws {
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
        let aggregation = try CostLedgerService.aggregate(
                windowDays: 365, in: context, readerTimeZone: TimeZone(secondsFromGMT: 0)!)
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
