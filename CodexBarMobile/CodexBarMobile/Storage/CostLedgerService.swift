import CodexBarSync
import Foundation
import SwiftData

// MARK: - CostLedgerService (Cost Window Ledger · research doc 024)
//
// Round 2 / P2: writer half of the ledger. Reader (`aggregate(...)`),
// diagnostics, clear, seed-from-existing-blobs come in later rounds.
// Read `Research/024-cost-window-ledger/{DESIGN,ARCHITECTURE}.md` for the
// full picture; this file implements the per-day upsert + dedup contract
// they describe.
//
// Invariants:
//   1. Default ON as of iOS 1.17.x. `isEnabled` reads
//      `MobileSettingsKeys.cwlEnabled` from `UserDefaults.standard`, but
//      treats an absent key as the product default so new users build a
//      local ledger without visiting Settings first.
//   2. Per-day uniqueness by `(deviceID, providerID, dayKey)`. Enforced via
//      `DailyCostPoint.compositeKey` lookup before insert.
//   3. Dedup rule: `existing.lastUpdated >= incoming.lastUpdated` → skip.
//      Same-or-older incoming data is rejected. The wire format has no
//      per-day timestamp, so all days in a single Mac push share the
//      `ProviderUsageSnapshot.lastUpdated`. Same-Mac, same-cycle pushes
//      are therefore correctly skipped as redundant.
//   4. The writer never deletes ledger rows. Clearing is a separate
//      explicit action (P4 + P6).

// MARK: - Aggregate output types (Round 3 / P3)

/// Result of `CostLedgerService.aggregate(windowDays:in:asOf:)`. Mirrors
/// the shape `CostDashboardInsights` consumes today, so P4 can swap the
/// blob-derived insights for this without changing the dashboard renderer.
/// Cross-device merge is done in the aggregator with provider-aware semantics:
/// local-cost providers sum active-device rows; account-level providers keep
/// the latest row for the same `(providerID, accountEmail, dayKey)`.
struct CostLedgerAggregation: Equatable {
    /// Window the aggregator was asked to compute, in days.
    let windowDays: Int
    /// Sum of `costUSD` across every (providerID, dayKey) survivor.
    let totalCostUSD: Double
    /// Sum of `totalTokens` across every survivor.
    let totalTokens: Int
    /// Distinct dayKeys with `costUSD > 0` across all providers within the window.
    let activeDayCount: Int
    /// Per-providerID rollup. Keys are sorted lexicographically by `providerID`
    /// inside `sortedProviderRollups` for stable rendering.
    let providerRollups: [String: CostLedgerProviderRollup]
    /// Re-aggregated daily series (one entry per dayKey, summed across
    /// providers). Sorted oldest → newest.
    let dailyPoints: [SyncDailyPoint]
    /// Re-aggregated model mix across all providers and days. Sorted by
    /// `costUSD` descending.
    let modelMix: [SyncCostBreakdown]
    /// Re-aggregated service mix (e.g. Codex Cloud services) across all
    /// providers and days. Sorted by `costUSD` descending.
    let serviceMix: [SyncCostBreakdown]

    var sortedProviderRollups: [CostLedgerProviderRollup] {
        self.providerRollups.values.sorted { $0.providerID < $1.providerID }
    }
}

struct CostLedgerProviderRollup: Equatable {
    let providerID: String
    /// Account email (nil for single-account). Together with `providerID`
    /// forms the `cardIdentityKey` the Cost dashboard renders rows by.
    let accountEmail: String?
    let totalCostUSD: Double
    let totalTokens: Int
    /// Daily points just for this provider, sorted oldest → newest.
    let dailyPoints: [SyncDailyPoint]
    /// Model mix just for this provider. Sorted by `costUSD` descending.
    let modelBreakdowns: [SyncCostBreakdown]
    /// Service mix just for this provider. Sorted by `costUSD` descending.
    let serviceBreakdowns: [SyncCostBreakdown]
}

/// Lightweight ledger diagnostics for the Settings panel (P4). All fields
/// are O(rows) to compute; safe for an immediate call. `estimatedBytes` is a
/// coarse estimate (`row count × 200`), not a real on-disk measurement.
struct CostLedgerDiagnostics: Equatable {
    let deviceCount: Int
    let providerCount: Int
    let dayCount: Int
    let rowCount: Int
    let earliestDayKey: String?
    let latestWriteAt: Date?
    let estimatedBytes: Int
}

// MARK: - CostLedgerService

enum CostLedgerService {

    /// `YYYY-MM-DD` UTC formatter, matches the wire format's `SyncDailyPoint.dayKey`.
    /// Static so we don't reallocate per call; `DateFormatter` is reentrant-safe
    /// for read-only use after configuration.
    static let utcDayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Gate

    /// True iff the CWL feature flag is on. Reads `cwlEnabled` from the
    /// supplied `UserDefaults` (defaults to `.standard`). Test-friendly —
    /// pass a per-suite `UserDefaults(suiteName:)` to verify the flag
    /// logic without touching the shared store.
    static func isEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        guard userDefaults.object(forKey: MobileSettingsKeys.cwlEnabled) != nil else {
            return MobileSettingsDefaults.cwlEnabled
        }
        return userDefaults.bool(forKey: MobileSettingsKeys.cwlEnabled)
    }

    // MARK: - Upsert: snapshot → daily rows

    /// Iterate `provider.costSummary?.daily` and upsert each day as a
    /// `DailyCostPoint` row. Called from `SwiftDataBridge.upsertProvider`
    /// **after** the existing blob write, **only when** `isEnabled()` is
    /// true. The blob path always runs, so even with CWL on the ledger and
    /// the blob stay in sync (the blob acts as a fallback / authoritative
    /// snapshot for the current Mac window).
    ///
    /// All days in one call share `provider.lastUpdated` — the wire format
    /// has no per-day timestamp.
    static func upsertFromSnapshot(
        _ provider: ProviderUsageSnapshot,
        deviceID: String,
        in context: ModelContext) throws
    {
        guard let summary = provider.costSummary else { return }
        guard !summary.daily.isEmpty else { return }

        let encoder = CloudSyncConstants.makeJSONEncoder()
        for point in summary.daily {
            try Self.upsertDayPoint(
                deviceID: deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail,
                dayKey: point.dayKey,
                costUSD: point.costUSD,
                totalTokens: point.totalTokens,
                isEstimated: point.isEstimated,
                modelBreakdowns: point.modelBreakdowns,
                serviceBreakdowns: point.serviceBreakdowns,
                lastUpdated: provider.lastUpdated,
                encoder: encoder,
                in: context)
        }
    }

    /// Granular upsert for a single `(deviceID, providerID, dayKey)`.
    /// Exposed (internal) so tests can drive the dedup rule directly
    /// without constructing a full `ProviderUsageSnapshot`. Also reusable
    /// by future rounds (e.g. `seedFromExistingBlobs` in P6).
    static func upsertDayPoint(
        // `accountEmail` defaults to nil for the single-account convenience
        // case (tests, future single-account seed). The real production
        // entry `upsertFromSnapshot` always passes `provider.accountEmail`
        // explicitly — the multi-account-collision bug this key fix closes
        // lived there, not here.
        deviceID: String,
        providerID: String,
        accountEmail: String? = nil,
        dayKey: String,
        costUSD: Double,
        totalTokens: Int,
        isEstimated: Bool?,
        modelBreakdowns: [SyncCostBreakdown],
        serviceBreakdowns: [SyncCostBreakdown],
        lastUpdated: Date,
        encoder: JSONEncoder? = nil,
        in context: ModelContext) throws
    {
        let key = DailyCostPoint.makeCompositeKey(
            deviceID: deviceID,
            providerID: providerID,
            accountEmail: accountEmail,
            dayKey: dayKey)
        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate { $0.compositeKey == key })

        let enc = encoder ?? CloudSyncConstants.makeJSONEncoder()
        let modelData: Data? = modelBreakdowns.isEmpty
            ? nil
            : try? enc.encode(modelBreakdowns)
        let serviceData: Data? = serviceBreakdowns.isEmpty
            ? nil
            : try? enc.encode(serviceBreakdowns)

        if let existing = try context.fetch(descriptor).first {
            // Dedup. Skip if we already have data at least as fresh for
            // this exact (deviceID, providerID, dayKey). Same `lastUpdated`
            // = same Mac, same cycle = redundant write; older = stale.
            if existing.lastUpdated >= lastUpdated {
                return
            }
            existing.costUSD = costUSD
            existing.totalTokens = totalTokens
            existing.isEstimated = isEstimated
            existing.modelBreakdownsData = modelData
            existing.serviceBreakdownsData = serviceData
            existing.lastUpdated = lastUpdated
        } else {
            let point = DailyCostPoint(
                deviceID: deviceID,
                providerID: providerID,
                accountEmail: accountEmail,
                dayKey: dayKey,
                costUSD: costUSD,
                totalTokens: totalTokens,
                isEstimated: isEstimated,
                modelBreakdownsData: modelData,
                serviceBreakdownsData: serviceData,
                lastUpdated: lastUpdated)
            context.insert(point)
        }
    }

    // MARK: - Aggregate (reader · Round 3 / P3)

    /// Aggregate ledger rows for the trailing `windowDays`.
    ///
    /// Cross-device merge is provider-aware:
    /// - local-cost providers (`codex`, `claude`, `vertexai`) sum active-device
    ///   rows because their cost comes from per-machine local history.
    /// - account-level providers keep the latest row for the same provider /
    ///   account / day because those APIs already return account-wide totals.
    ///
    /// `asOf` exists for deterministic tests; production callers pass `Date()`.
    /// The "window" is `[asOf-(windowDays-1) … asOf]` in UTC dayKeys.
    ///
    /// O(n) over surviving rows after window filter. For Round 7 / P7
    /// performance work we may move this to a background actor; for now
    /// it runs on the caller's context (P4 calls from `@MainActor`).
    static func aggregate(
        windowDays: Int,
        in context: ModelContext,
        asOf: Date = Date(),
        activeDeviceIDs: Set<String>? = nil) throws -> CostLedgerAggregation
    {
        let windowDays = max(1, min(windowDays, 365))
        let cutoffKey = Self.cutoffDayKey(windowDays: windowDays, asOf: asOf)

        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate { $0.dayKey >= cutoffKey })
        let fetchedRows = try context.fetch(descriptor)
        let rows: [DailyCostPoint]
        if let activeDeviceIDs {
            rows = fetchedRows.filter { activeDeviceIDs.contains($0.deviceID) }
        } else {
            rows = fetchedRows
        }

        let decoder = CloudSyncConstants.makeJSONDecoder()
        var groupedRows: [LedgerGroupKey: [DailyCostPoint]] = [:]
        for row in rows {
            groupedRows[LedgerGroupKey(row: row), default: []].append(row)
        }

        let mergedPoints: [AggregatedDailyCostPoint] = groupedRows.values.compactMap { group in
            guard let first = group.first else { return nil }
            if ProviderSnapshotMerger.usesLocalCostMerge(providerID: first.providerID) {
                return AggregatedDailyCostPoint.mergingLocalCostRows(group, decoder: decoder)
            }
            guard let latest = group.max(by: { $0.lastUpdated < $1.lastUpdated }) else {
                return nil
            }
            return AggregatedDailyCostPoint(row: latest, decoder: decoder)
        }

        // Per-account-provider accumulators, keyed by cardIdentityKey
        // (providerID|accountEmail) so the dashboard can match rows per account.
        var perProvider: [String: ProviderAccumulator] = [:]
        // Per-day + per-model aggregate ACROSS all providers/accounts (these
        // intentionally collapse account distinction — they're cross-cutting).
        var perDay: [String: DayAccumulator] = [:]
        // Per-model cost + Codex standard/fast split (upstream #1070), summed
        // across the window so the rebuilt modelMix carries the split through
        // to the dashboard's Model Mix rows — at parity with the blob path.
        var perModel: [String: CostBreakdownAccumulator] = [:]
        var perService: [String: CostBreakdownAccumulator] = [:]

        for point in mergedPoints {
            let rollupKey = "\(point.providerID)|\(point.accountEmail ?? "_")"
            var acc = perProvider[rollupKey] ?? ProviderAccumulator(
                providerID: point.providerID,
                accountEmail: point.accountEmail)
            acc.ingest(point)
            perProvider[rollupKey] = acc

            perDay[point.dayKey, default: .init(dayKey: point.dayKey)].ingest(point)
            for breakdown in point.modelBreakdowns where breakdown.costUSD > 0 {
                perModel[breakdown.label, default: .init()].ingest(breakdown)
            }
            for breakdown in point.serviceBreakdowns where breakdown.costUSD > 0 {
                perService[breakdown.label, default: .init()].ingest(breakdown)
            }
        }

        let providerRollupsKeyed = Dictionary(
            uniqueKeysWithValues: perProvider.map { rollupKey, acc in
                (rollupKey, acc.toRollup())
            })

        let dailyPoints = perDay
            .sorted { $0.key < $1.key }
            .map { _, acc in acc.toDailyPoint() }

        let modelMix = perModel
            .map { label, entry in entry.toBreakdown(label: label) }
            .sortedByCostThenName()

        let serviceMix = perService
            .map { label, entry in entry.toBreakdown(label: label) }
            .sortedByCostThenName()

        let totalCostUSD = perDay.values.reduce(0) { $0 + $1.costUSD }
        let totalTokens = perDay.values.reduce(0) { $0 + $1.totalTokens }
        let activeDayCount = perDay.values.count(where: { $0.costUSD > 0 })

        return CostLedgerAggregation(
            windowDays: windowDays,
            totalCostUSD: totalCostUSD,
            totalTokens: totalTokens,
            activeDayCount: activeDayCount,
            providerRollups: providerRollupsKeyed,
            dailyPoints: dailyPoints,
            modelMix: modelMix,
            serviceMix: serviceMix)
    }

    /// Same as `aggregate(...)` but filtered to one provider. Used by
    /// `ProviderDetailView` (P4) — avoids materialising the cross-provider
    /// aggregate just to display a single provider's per-day cost section.
    static func aggregateProvider(
        providerID: String,
        accountEmail: String?,
        windowDays: Int,
        in context: ModelContext,
        asOf: Date = Date(),
        activeDeviceIDs: Set<String>? = nil) throws -> CostLedgerProviderRollup
    {
        let full = try Self.aggregate(
            windowDays: windowDays,
            in: context,
            asOf: asOf,
            activeDeviceIDs: activeDeviceIDs)
        let rollupKey = "\(providerID)|\(accountEmail ?? "_")"
        return full.providerRollups[rollupKey] ?? CostLedgerProviderRollup(
            providerID: providerID,
            accountEmail: accountEmail,
            totalCostUSD: 0,
            totalTokens: 0,
            dailyPoints: [],
            modelBreakdowns: [],
            serviceBreakdowns: [])
    }

    // MARK: - Diagnostics (Round 3 / P3)

    /// Coarse ledger health stats for the Settings diagnostics panel (P4).
    /// O(n) over ledger rows.
    static func diagnostics(in context: ModelContext) throws -> CostLedgerDiagnostics {
        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        let devices = Set(rows.map(\.deviceID))
        let providers = Set(rows.map(\.providerID))
        let days = Set(rows.map(\.dayKey))
        let earliestDayKey = days.min()
        let latestWriteAt = rows.map(\.lastUpdated).max()
        // Coarse estimate (200 bytes/row is a reasonable upper bound for
        // a DailyCostPoint with both encoded blobs). Real on-disk size
        // requires reading the SQLite file; deferred to P7.
        let estimatedBytes = rows.count * 200

        return CostLedgerDiagnostics(
            deviceCount: devices.count,
            providerCount: providers.count,
            dayCount: days.count,
            rowCount: rows.count,
            earliestDayKey: earliestDayKey,
            latestWriteAt: latestWriteAt,
            estimatedBytes: estimatedBytes)
    }

    // MARK: - Clear (explicit user action · Round 6 / P4b)

    /// Delete every `DailyCostPoint` row. Wired to the Settings "clear ledger"
    /// button (with a confirmation dialog). Touches ONLY the ledger — the blob
    /// path (`ProviderSnapshotModel.costSummaryData`) and all other SwiftData
    /// entities are untouched, so toggling CWL off + clearing leaves the
    /// build-140 dashboard fully intact.
    static func clearAll(in context: ModelContext) throws {
        try context.delete(model: DailyCostPoint.self)
        try context.save()
    }

    // MARK: - Seed from existing blobs (migration · Round 7 / P6)

    /// One-shot import of the existing blob-path data into the ledger. Run on
    /// the user's first CWL enable so the dashboard has history immediately
    /// (instead of waiting for the next Mac sync to rebuild it). Reads every
    /// `ProviderSnapshotModel` row, decodes its `costSummaryData`, and upserts
    /// each daily point keyed by the row's (deviceID, providerID, accountEmail).
    ///
    /// Idempotent: re-running seeds the same `(deviceID, providerID,
    /// accountEmail, dayKey)` keys with the same `lastUpdated`, so the dedup
    /// rule (`existing.lastUpdated >= incoming → skip`) makes a second run a
    /// no-op. A corrupt / undecodable blob is skipped (that provider just has
    /// no seeded history); other rows still seed. Throws only on the final
    /// `save()` — the caller (toggle-on) turns CWL back off on throw.
    static func seedFromExistingBlobs(in context: ModelContext) throws {
        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        let decoder = CloudSyncConstants.makeJSONDecoder()
        let encoder = CloudSyncConstants.makeJSONEncoder()
        for row in providers {
            guard let blob = row.costSummaryData,
                  let summary = try? decoder.decode(SyncCostSummary.self, from: blob)
            else { continue }
            for point in summary.daily {
                try Self.upsertDayPoint(
                    deviceID: row.deviceID,
                    providerID: row.providerID,
                    accountEmail: row.accountEmail,
                    dayKey: point.dayKey,
                    costUSD: point.costUSD,
                    totalTokens: point.totalTokens,
                    isEstimated: point.isEstimated,
                    modelBreakdowns: point.modelBreakdowns,
                    serviceBreakdowns: point.serviceBreakdowns,
                    lastUpdated: row.lastUpdated,
                    encoder: encoder,
                    in: context)
            }
        }
        try context.save()
    }

    // MARK: - Helpers

    /// `[asOf - (windowDays - 1) days, asOf]` lower bound as a `YYYY-MM-DD`
    /// UTC dayKey string. Comparison against `DailyCostPoint.dayKey` works
    /// lexicographically because the format is fixed-width.
    static func cutoffDayKey(windowDays: Int, asOf: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let cutoff = calendar.date(
            byAdding: .day,
            value: -(windowDays - 1),
            to: asOf) ?? asOf
        return Self.utcDayKeyFormatter.string(from: cutoff)
    }

    // MARK: - Private accumulators

    private struct LedgerGroupKey: Hashable {
        let providerID: String
        let accountEmail: String?
        let dayKey: String

        init(row: DailyCostPoint) {
            self.providerID = row.providerID
            self.accountEmail = row.accountEmail
            self.dayKey = row.dayKey
        }
    }

    private struct AggregatedDailyCostPoint {
        let providerID: String
        let accountEmail: String?
        let dayKey: String
        let costUSD: Double
        let totalTokens: Int
        let isEstimated: Bool?
        let modelBreakdowns: [SyncCostBreakdown]
        let serviceBreakdowns: [SyncCostBreakdown]

        init(row: DailyCostPoint, decoder: JSONDecoder) {
            self.providerID = row.providerID
            self.accountEmail = row.accountEmail
            self.dayKey = row.dayKey
            self.costUSD = row.costUSD
            self.totalTokens = row.totalTokens
            self.isEstimated = row.isEstimated
            self.modelBreakdowns = Self.decodeBreakdowns(row.modelBreakdownsData, decoder: decoder)
            self.serviceBreakdowns = Self.decodeBreakdowns(row.serviceBreakdownsData, decoder: decoder)
        }

        static func mergingLocalCostRows(
            _ rows: [DailyCostPoint],
            decoder: JSONDecoder
        ) -> AggregatedDailyCostPoint? {
            guard let first = rows.first else { return nil }
            var dayAccumulator = DayAccumulator(dayKey: first.dayKey)
            for row in rows {
                dayAccumulator.ingest(AggregatedDailyCostPoint(row: row, decoder: decoder))
            }
            return AggregatedDailyCostPoint(
                providerID: first.providerID,
                accountEmail: first.accountEmail,
                dayKey: first.dayKey,
                costUSD: dayAccumulator.costUSD,
                totalTokens: dayAccumulator.totalTokens,
                isEstimated: dayAccumulator.isEstimated ? true : nil,
                modelBreakdowns: dayAccumulator.modelBreakdownsArray,
                serviceBreakdowns: dayAccumulator.serviceBreakdownsArray)
        }

        private init(
            providerID: String,
            accountEmail: String?,
            dayKey: String,
            costUSD: Double,
            totalTokens: Int,
            isEstimated: Bool?,
            modelBreakdowns: [SyncCostBreakdown],
            serviceBreakdowns: [SyncCostBreakdown])
        {
            self.providerID = providerID
            self.accountEmail = accountEmail
            self.dayKey = dayKey
            self.costUSD = costUSD
            self.totalTokens = totalTokens
            self.isEstimated = isEstimated
            self.modelBreakdowns = modelBreakdowns
            self.serviceBreakdowns = serviceBreakdowns
        }

        private static func decodeBreakdowns(_ data: Data?, decoder: JSONDecoder) -> [SyncCostBreakdown] {
            guard let data,
                  let decoded = try? decoder.decode([SyncCostBreakdown].self, from: data)
            else { return [] }
            return decoded
        }
    }

    private struct DayAccumulator {
        let dayKey: String
        var costUSD: Double = 0
        var totalTokens: Int = 0
        var isEstimated = false
        var modelBreakdowns: [String: CostBreakdownAccumulator] = [:]
        var serviceBreakdowns: [String: CostBreakdownAccumulator] = [:]

        mutating func ingest(_ point: AggregatedDailyCostPoint) {
            self.costUSD += point.costUSD
            self.totalTokens += point.totalTokens
            if point.isEstimated == true {
                self.isEstimated = true
            }
            for breakdown in point.modelBreakdowns {
                self.modelBreakdowns[breakdown.label, default: .init()].ingest(breakdown)
            }
            for breakdown in point.serviceBreakdowns {
                self.serviceBreakdowns[breakdown.label, default: .init()].ingest(breakdown)
            }
        }

        var modelBreakdownsArray: [SyncCostBreakdown] {
            self.modelBreakdowns
                .map { label, entry in entry.toBreakdown(label: label) }
                .sortedByCostThenName()
        }

        var serviceBreakdownsArray: [SyncCostBreakdown] {
            self.serviceBreakdowns
                .map { label, entry in entry.toBreakdown(label: label) }
                .sortedByCostThenName()
        }

        func toDailyPoint() -> SyncDailyPoint {
            SyncDailyPoint(
                dayKey: self.dayKey,
                costUSD: self.costUSD,
                totalTokens: self.totalTokens,
                modelBreakdowns: self.modelBreakdownsArray,
                serviceBreakdowns: self.serviceBreakdownsArray,
                isEstimated: self.isEstimated ? true : nil)
        }
    }

    private struct ProviderAccumulator {
        let providerID: String
        let accountEmail: String?
        var costUSD: Double = 0
        var totalTokens: Int = 0
        var perDay: [String: DayAccumulator] = [:]
        var perModel: [String: CostBreakdownAccumulator] = [:]
        var perService: [String: CostBreakdownAccumulator] = [:]

        init(providerID: String, accountEmail: String?) {
            self.providerID = providerID
            self.accountEmail = accountEmail
        }

        mutating func ingest(_ point: AggregatedDailyCostPoint) {
            self.costUSD += point.costUSD
            self.totalTokens += point.totalTokens
            self.perDay[point.dayKey, default: .init(dayKey: point.dayKey)].ingest(point)
            for breakdown in point.modelBreakdowns where breakdown.costUSD > 0 {
                self.perModel[breakdown.label, default: .init()].ingest(breakdown)
            }
            for breakdown in point.serviceBreakdowns where breakdown.costUSD > 0 {
                self.perService[breakdown.label, default: .init()].ingest(breakdown)
            }
        }

        func toRollup() -> CostLedgerProviderRollup {
            CostLedgerProviderRollup(
                providerID: self.providerID,
                accountEmail: self.accountEmail,
                totalCostUSD: self.costUSD,
                totalTokens: self.totalTokens,
                dailyPoints: self.perDay
                    .sorted { $0.key < $1.key }
                    .map { _, acc in acc.toDailyPoint() },
                modelBreakdowns: self.perModel
                    .map { label, entry in entry.toBreakdown(label: label) }
                    .sortedByCostThenName(),
                serviceBreakdowns: self.perService
                    .map { label, entry in entry.toBreakdown(label: label) }
                    .sortedByCostThenName())
        }
    }

    private struct CostBreakdownAccumulator {
        var costUSD: Double = 0
        var isEstimated = false
        var standardCostUSD: Double = 0
        var priorityCostUSD: Double = 0
        var standardTokens: Int = 0
        var priorityTokens: Int = 0
        var hasStandardCost = false
        var hasPriorityCost = false
        var hasStandardTokens = false
        var hasPriorityTokens = false

        mutating func ingest(_ breakdown: SyncCostBreakdown) {
            self.costUSD += breakdown.costUSD
            if breakdown.isEstimated == true {
                self.isEstimated = true
            }
            if let value = breakdown.standardCostUSD {
                self.standardCostUSD += value
                self.hasStandardCost = true
            }
            if let value = breakdown.priorityCostUSD {
                self.priorityCostUSD += value
                self.hasPriorityCost = true
            }
            if let value = breakdown.standardTokens {
                self.standardTokens += value
                self.hasStandardTokens = true
            }
            if let value = breakdown.priorityTokens {
                self.priorityTokens += value
                self.hasPriorityTokens = true
            }
        }

        func toBreakdown(label: String) -> SyncCostBreakdown {
            SyncCostBreakdown(
                label: label,
                costUSD: self.costUSD,
                isEstimated: self.isEstimated ? true : nil,
                standardCostUSD: self.hasStandardCost ? self.standardCostUSD : nil,
                priorityCostUSD: self.hasPriorityCost ? self.priorityCostUSD : nil,
                standardTokens: self.hasStandardTokens ? self.standardTokens : nil,
                priorityTokens: self.hasPriorityTokens ? self.priorityTokens : nil)
        }
    }
}

private extension Array where Element == SyncCostBreakdown {
    func sortedByCostThenName() -> [SyncCostBreakdown] {
        self.sorted { lhs, rhs in
            if lhs.costUSD == rhs.costUSD {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.costUSD > rhs.costUSD
        }
    }
}
