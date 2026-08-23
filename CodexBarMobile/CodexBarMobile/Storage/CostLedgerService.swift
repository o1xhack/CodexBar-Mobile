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

    var hasDisplayData: Bool {
        !self.providerRollups.isEmpty ||
            !self.dailyPoints.isEmpty ||
            !self.modelMix.isEmpty ||
            !self.serviceMix.isEmpty
    }
}

struct CostLedgerProviderRollup: Equatable {
    let providerID: String
    /// Account email (nil for single-account). Together with `providerID`
    /// forms the `cardIdentityKey` the Cost dashboard renders rows by.
    let accountEmail: String?
    /// Opaque/stable identity used to match this rollup to a live card.
    /// Falls back to account email for rows written before iOS 1.19.
    let accountIdentityKey: String?
    /// Full effective identity component, preserving merger overlap semantics
    /// for mixed writers that expose org+email, email-only or org-only sets.
    let accountIdentityKeys: [String]
    let totalCostUSD: Double
    let totalTokens: Int
    /// Daily points just for this provider, sorted oldest → newest.
    let dailyPoints: [SyncDailyPoint]
    /// Model mix just for this provider. Sorted by `costUSD` descending.
    let modelBreakdowns: [SyncCostBreakdown]
    /// Service mix just for this provider. Sorted by `costUSD` descending.
    let serviceBreakdowns: [SyncCostBreakdown]

    init(
        providerID: String,
        accountEmail: String?,
        accountIdentityKey: String? = nil,
        accountIdentityKeys: [String] = [],
        totalCostUSD: Double,
        totalTokens: Int,
        dailyPoints: [SyncDailyPoint],
        modelBreakdowns: [SyncCostBreakdown],
        serviceBreakdowns: [SyncCostBreakdown])
    {
        self.providerID = providerID
        self.accountEmail = accountEmail
        self.accountIdentityKey = accountIdentityKey
        self.accountIdentityKeys = accountIdentityKeys
        self.totalCostUSD = totalCostUSD
        self.totalTokens = totalTokens
        self.dailyPoints = dailyPoints
        self.modelBreakdowns = modelBreakdowns
        self.serviceBreakdowns = serviceBreakdowns
    }
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
    static func accountIdentityKey(for provider: ProviderUsageSnapshot) -> String {
        ProviderSnapshotMerger.effectiveIdentifiers(for: provider).first
            ?? "\(provider.providerID):legacy-no-identity"
    }

    static func accountIdentityKeys(for provider: ProviderUsageSnapshot) -> [String] {
        ProviderSnapshotMerger.effectiveIdentifiers(for: provider)
    }

    static func rollupKey(
        providerID: String,
        accountIdentityKey: String?,
        accountEmail: String?) -> String
    {
        "\(providerID)|\(accountIdentityKey ?? accountEmail ?? "_")"
    }

    /// `YYYY-MM-DD` UTC formatter retained for deterministic historical test
    /// fixtures. Production window cutoffs use `SyncCostSummary`'s local
    /// day-key formatter so CWL windows match Mac-synced cost day keys.
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
    /// All days in one call share the cost summary's source timestamp (falling
    /// back to `provider.lastUpdated` for legacy payloads) because the wire
    /// format has no per-day timestamp. If the user has explicitly cleared
    /// local cost history, cost data at or before that clear timestamp is
    /// skipped so unchanged CloudKit data cannot recreate deleted rows.
    static func upsertFromSnapshot(
        _ provider: ProviderUsageSnapshot,
        deviceID: String,
        in context: ModelContext,
        userDefaults: UserDefaults = .standard) throws
    {
        guard let summary = provider.costSummary else { return }
        guard !summary.daily.isEmpty else { return }
        let costUpdatedAt = summary.sourceUpdatedAt ?? provider.lastUpdated
        if let clearedAt = Self.blobSeedClearedAt(userDefaults: userDefaults),
           costUpdatedAt <= clearedAt
        {
            return
        }

        let encoder = CloudSyncConstants.makeJSONEncoder()
        let accountIdentityKeys = Self.accountIdentityKeys(for: provider)
        let accountIdentityKey = accountIdentityKeys.first
        for point in summary.daily {
            try Self.upsertDayPoint(
                deviceID: deviceID,
                providerID: provider.providerID,
                accountEmail: provider.accountEmail,
                accountRecordKey: provider.accountRecordKey,
                accountIdentityKey: accountIdentityKey,
                accountIdentityKeys: accountIdentityKeys,
                dayKey: point.dayKey,
                costUSD: point.costUSD,
                totalTokens: point.totalTokens,
                costIsKnown: point.costIsKnown,
                isEstimated: point.isEstimated,
                modelBreakdowns: point.modelBreakdowns,
                serviceBreakdowns: point.serviceBreakdowns,
                lastUpdated: costUpdatedAt,
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
        accountRecordKey: String? = nil,
        accountIdentityKey: String? = nil,
        accountIdentityKeys: [String]? = nil,
        dayKey: String,
        costUSD: Double,
        totalTokens: Int,
        costIsKnown: Bool? = nil,
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
            accountRecordKey: accountRecordKey,
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
        let identityData = accountIdentityKeys.flatMap { try? enc.encode($0) }

        if let existing = try context.fetch(descriptor).first {
            // Identity metadata may be newly available on an otherwise equal
            // payload. Backfill it before the freshness early-return so an
            // upgrade never strands a legacy email-key row.
            existing.accountEmail = accountEmail
            existing.accountRecordKey = accountRecordKey
            existing.accountIdentityKey = accountIdentityKey
            existing.accountIdentitiesData = identityData
            // Token-cost publications can change without advancing the
            // provider usage timestamp. Keep the ledger byte-for-byte aligned
            // with the current blob whenever an equal-time pricing/catch-up
            // refresh changes any cost payload field. This also makes a
            // rolling-upgrade nil-to-known availability backfill atomic with
            // its recomputed amount, token, and breakdown values.
            if existing.lastUpdated == lastUpdated,
               existing.costUSD != costUSD ||
               existing.totalTokens != totalTokens ||
               existing.costIsKnown != costIsKnown ||
               existing.isEstimated != isEstimated ||
               existing.modelBreakdownsData != modelData ||
               existing.serviceBreakdownsData != serviceData
            {
                existing.costUSD = costUSD
                existing.totalTokens = totalTokens
                existing.costIsKnown = costIsKnown
                existing.isEstimated = isEstimated
                existing.modelBreakdownsData = modelData
                existing.serviceBreakdownsData = serviceData
                return
            }
            // Dedup. Skip if we already have data at least as fresh for
            // this exact (deviceID, providerID, dayKey). An identical
            // same-time payload is redundant; an older payload is stale.
            if existing.lastUpdated >= lastUpdated {
                return
            }
            existing.costUSD = costUSD
            existing.totalTokens = totalTokens
            existing.costIsKnown = costIsKnown
            existing.isEstimated = isEstimated
            existing.modelBreakdownsData = modelData
            existing.serviceBreakdownsData = serviceData
            existing.lastUpdated = lastUpdated
        } else {
            let point = DailyCostPoint(
                deviceID: deviceID,
                providerID: providerID,
                accountEmail: accountEmail,
                accountRecordKey: accountRecordKey,
                accountIdentityKey: accountIdentityKey,
                accountIdentitiesData: identityData,
                dayKey: dayKey,
                costUSD: costUSD,
                totalTokens: totalTokens,
                costIsKnown: costIsKnown,
                isEstimated: isEstimated,
                modelBreakdownsData: modelData,
                serviceBreakdownsData: serviceData,
                lastUpdated: lastUpdated)
            context.insert(point)
        }
    }

    /// Rekey pre-1.19 email-key ledger rows before the matching provider row
    /// moves to an opaque CloudKit record key. This preserves days older than
    /// the current Mac blob window instead of letting stale-provider pruning
    /// discard them during the identity upgrade.
    static func migrateLegacyAccountKey(
        deviceID: String,
        providerID: String,
        accountEmail: String?,
        accountRecordKey: String,
        accountIdentityKeys: [String],
        in context: ModelContext) throws
    {
        let identityData = try? CloudSyncConstants.makeJSONEncoder().encode(accountIdentityKeys)
        let accountIdentityKey = accountIdentityKeys.first
        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate {
                $0.deviceID == deviceID && $0.providerID == providerID
            })
        let legacyRows = try context.fetch(descriptor).filter {
            $0.accountRecordKey == nil && $0.accountEmail == accountEmail
        }
        for legacy in legacyRows {
            let newKey = DailyCostPoint.makeCompositeKey(
                deviceID: deviceID,
                providerID: providerID,
                accountEmail: accountEmail,
                accountRecordKey: accountRecordKey,
                dayKey: legacy.dayKey)
            let existingDescriptor = FetchDescriptor<DailyCostPoint>(
                predicate: #Predicate { $0.compositeKey == newKey })
            if let existing = try context.fetch(existingDescriptor).first,
               existing !== legacy
            {
                if legacy.lastUpdated > existing.lastUpdated {
                    existing.costUSD = legacy.costUSD
                    existing.totalTokens = legacy.totalTokens
                    existing.costIsKnown = legacy.costIsKnown
                    existing.isEstimated = legacy.isEstimated
                    existing.modelBreakdownsData = legacy.modelBreakdownsData
                    existing.serviceBreakdownsData = legacy.serviceBreakdownsData
                    existing.lastUpdated = legacy.lastUpdated
                }
                existing.accountIdentityKey = accountIdentityKey
                existing.accountIdentitiesData = identityData
                context.delete(legacy)
            } else {
                legacy.compositeKey = newKey
                legacy.accountRecordKey = accountRecordKey
                legacy.accountIdentityKey = accountIdentityKey
                legacy.accountIdentitiesData = identityData
            }
        }
    }

    /// Moves every accumulated ledger day from a provider-level cost's old
    /// account owner to its new owner before the old envelope's tombstone is
    /// applied. The incoming Mac blob is bounded (normally 30 days), while CWL
    /// can retain 90–365 days; deleting the old owner would otherwise discard
    /// older ledger-only history permanently.
    static func migrateCostOwnership(
        deviceID: String,
        providerID: String,
        fromAccountEmail: String?,
        fromAccountRecordKey: String?,
        to provider: ProviderUsageSnapshot,
        in context: ModelContext) throws
    {
        let targetIdentityKeys = Self.accountIdentityKeys(for: provider)
        let targetIdentityKey = targetIdentityKeys.first
        let targetIdentityData = try? CloudSyncConstants.makeJSONEncoder().encode(targetIdentityKeys)
        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate {
                $0.deviceID == deviceID && $0.providerID == providerID
            })
        let sourceRows = try context.fetch(descriptor).filter {
            Self.rowMatchesAccount(
                $0,
                accountEmail: fromAccountEmail,
                accountRecordKey: fromAccountRecordKey)
        }

        for source in sourceRows {
            let targetKey = DailyCostPoint.makeCompositeKey(
                deviceID: deviceID,
                providerID: providerID,
                accountEmail: provider.accountEmail,
                accountRecordKey: provider.accountRecordKey,
                dayKey: source.dayKey)
            guard source.compositeKey != targetKey else { continue }
            let targetDescriptor = FetchDescriptor<DailyCostPoint>(
                predicate: #Predicate { $0.compositeKey == targetKey })
            if let target = try context.fetch(targetDescriptor).first,
               target !== source
            {
                if source.lastUpdated > target.lastUpdated {
                    target.costUSD = source.costUSD
                    target.totalTokens = source.totalTokens
                    target.costIsKnown = source.costIsKnown
                    target.isEstimated = source.isEstimated
                    target.modelBreakdownsData = source.modelBreakdownsData
                    target.serviceBreakdownsData = source.serviceBreakdownsData
                    target.lastUpdated = source.lastUpdated
                }
                target.accountEmail = provider.accountEmail
                target.accountRecordKey = provider.accountRecordKey
                target.accountIdentityKey = targetIdentityKey
                target.accountIdentitiesData = targetIdentityData
                context.delete(source)
            } else {
                source.compositeKey = targetKey
                source.accountEmail = provider.accountEmail
                source.accountRecordKey = provider.accountRecordKey
                source.accountIdentityKey = targetIdentityKey
                source.accountIdentitiesData = targetIdentityData
            }
        }
    }

    /// Whether this account still owns accumulated ledger history even when
    /// its latest bounded provider blob temporarily carries no cost summary.
    /// Ownership migration must consult both stores: the blob describes the
    /// current window, while CWL can retain older days independently.
    static func hasRows(
        deviceID: String,
        providerID: String,
        accountEmail: String?,
        accountRecordKey: String?,
        in context: ModelContext) throws -> Bool
    {
        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate {
                $0.deviceID == deviceID && $0.providerID == providerID
            })
        return try context.fetch(descriptor).contains {
            Self.rowMatchesAccount(
                $0,
                accountEmail: accountEmail,
                accountRecordKey: accountRecordKey)
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
    /// The "window" is `[asOf-(windowDays-1) … asOf]` in local dayKeys.
    ///
    /// O(n) over surviving rows after window filter. For Round 7 / P7
    /// performance work we may move this to a background actor; for now
    /// it runs on the caller's context (P4 calls from `@MainActor`).
    static func aggregate(
        windowDays: Int,
        in context: ModelContext,
        asOf: Date = Date(),
        activeDeviceIDs: Set<String>? = nil,
        sourceSnapshots: [SyncedUsageSnapshot] = [],
        readerTimeZone: TimeZone = .current) throws -> CostLedgerAggregation
    {
        let windowDays = max(1, min(windowDays, 365))
        let cutoffKey = Self.cutoffDayKey(
            windowDays: windowDays,
            asOf: asOf,
            timeZone: readerTimeZone)
        // Valid IANA zones span more than 24 hours, so a producer can be two
        // logical dates behind the reader (UTC-11 versus UTC+14). Fetch two
        // extra boundary days; the source-aware filter below still admits
        // exactly `windowDays` for each producer.
        let fetchCutoffKey = Self.cutoffDayKey(
            windowDays: windowDays + 2,
            asOf: asOf,
            timeZone: readerTimeZone)
        let readerTodayKey = Self.dayKey(for: asOf, timeZone: readerTimeZone)

        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate { $0.dayKey >= fetchCutoffKey })
        let fetchedRows = try context.fetch(descriptor)
        let rows: [DailyCostPoint] = if let activeDeviceIDs {
            fetchedRows.filter { activeDeviceIDs.contains($0.deviceID) }
        } else {
            fetchedRows
        }

        let decoder = CloudSyncConstants.makeJSONDecoder()
        let sourceDayWindows = Self.makeSourceDayWindows(
            snapshots: sourceSnapshots,
            windowDays: windowDays,
            asOf: asOf,
            readerTodayDayKey: readerTodayKey)
        let accountGrouping = Self.makeAccountGrouping(rows: rows, decoder: decoder)
        var groupedRows: [LedgerGroupKey: [DailyCostPoint]] = [:]
        for (index, row) in rows.enumerated() {
            guard let normalizedDayKey = Self.readerRelativeDayKey(
                row,
                readerCutoffKey: cutoffKey,
                readerTodayKey: readerTodayKey,
                sourceDayWindows: sourceDayWindows,
                decoder: decoder)
            else { continue }
            let root = accountGrouping.roots[index]
            groupedRows[LedgerGroupKey(
                providerID: row.providerID,
                accountGroup: root,
                dayKey: normalizedDayKey), default: []].append(row)
        }

        let mergedPoints: [AggregatedDailyCostPoint] = groupedRows.compactMap { key, group in
            guard let first = group.first else { return nil }
            let identityKeys = accountGrouping.identityKeysByRoot[key.accountGroup] ?? []
            let preferredIdentityKey = accountGrouping.preferredKeyByRoot[key.accountGroup]
            if ProviderSnapshotMerger.usesLocalCostMerge(providerID: first.providerID) {
                return AggregatedDailyCostPoint.mergingLocalCostRows(
                    group,
                    dayKey: key.dayKey,
                    accountIdentityKey: preferredIdentityKey,
                    accountIdentityKeys: identityKeys,
                    decoder: decoder)
            }
            guard let latest = group.max(by: { $0.lastUpdated < $1.lastUpdated }) else {
                return nil
            }
            return AggregatedDailyCostPoint(
                row: latest,
                dayKey: key.dayKey,
                accountIdentityKey: preferredIdentityKey,
                accountIdentityKeys: identityKeys,
                decoder: decoder)
        }

        // Per-account-provider accumulators, keyed by the stable wire identity
        // when present and legacy accountEmail otherwise.
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
            let rollupKey = Self.rollupKey(
                providerID: point.providerID,
                accountIdentityKey: point.accountIdentityKey,
                accountEmail: point.accountEmail)
            var acc = perProvider[rollupKey] ?? ProviderAccumulator(
                providerID: point.providerID,
                accountEmail: point.accountEmail,
                accountIdentityKey: point.accountIdentityKey,
                accountIdentityKeys: point.accountIdentityKeys)
            acc.ingest(point)
            perProvider[rollupKey] = acc

            perDay[point.dayKey, default: .init(dayKey: point.dayKey)].ingest(point)
            guard point.costIsKnown != false else { continue }
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

    /// Aggregate for default-on CWL readers. If existing synced blob snapshots
    /// contain rows not yet represented in the ledger, seed those missing rows
    /// first and re-run the aggregate so upgraded or partially seeded users do
    /// not lose Daily Spend / Model Mix / Service Mix history.
    static func aggregateSeedingFromExistingBlobsIfNeeded(
        windowDays: Int,
        in context: ModelContext,
        asOf: Date = Date(),
        activeDeviceIDs: Set<String>? = nil,
        sourceSnapshots: [SyncedUsageSnapshot] = [],
        readerTimeZone: TimeZone = .current,
        userDefaults: UserDefaults = .standard) throws -> CostLedgerAggregation
    {
        try self.pruneLedgerRowsMissingProviderSnapshots(in: context)

        let clearedAt = Self.blobSeedClearedAt(userDefaults: userDefaults)
        if try Self.hasMissingSeedableCostBlobRows(in: context, newerThan: clearedAt) {
            try Self.seedFromExistingBlobs(in: context, newerThan: clearedAt)
        }
        return try Self.aggregate(
            windowDays: windowDays,
            in: context,
            asOf: asOf,
            activeDeviceIDs: activeDeviceIDs,
            sourceSnapshots: sourceSnapshots,
            readerTimeZone: readerTimeZone)
    }

    /// Same as `aggregate(...)` but filtered to one provider. Used by
    /// `ProviderDetailView` (P4) — avoids materialising the cross-provider
    /// aggregate just to display a single provider's per-day cost section.
    static func aggregateProvider(
        providerID: String,
        accountEmail: String?,
        accountIdentityKey: String? = nil,
        windowDays: Int,
        in context: ModelContext,
        asOf: Date = Date(),
        activeDeviceIDs: Set<String>? = nil,
        sourceSnapshots: [SyncedUsageSnapshot] = [],
        readerTimeZone: TimeZone = .current) throws -> CostLedgerProviderRollup
    {
        let full = try Self.aggregate(
            windowDays: windowDays,
            in: context,
            asOf: asOf,
            activeDeviceIDs: activeDeviceIDs,
            sourceSnapshots: sourceSnapshots,
            readerTimeZone: readerTimeZone)
        let rollupKey = Self.rollupKey(
            providerID: providerID,
            accountIdentityKey: accountIdentityKey,
            accountEmail: accountEmail)
        return full.providerRollups[rollupKey] ?? CostLedgerProviderRollup(
            providerID: providerID,
            accountEmail: accountEmail,
            accountIdentityKey: accountIdentityKey,
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
    /// entities are untouched. A clear timestamp is written so the default-on
    /// migration path cannot immediately rebuild the ledger from older blobs.
    static func clearAll(
        in context: ModelContext,
        clearedAt: Date = Date(),
        userDefaults: UserDefaults = .standard) throws
    {
        try context.delete(model: DailyCostPoint.self)
        try context.save()
        userDefaults.set(
            clearedAt.timeIntervalSince1970,
            forKey: MobileSettingsKeys.cwlBlobSeedClearedAt)
    }

    static func hasBlobSeedClearTombstone(userDefaults: UserDefaults = .standard) -> Bool {
        self.blobSeedClearedAt(userDefaults: userDefaults) != nil
    }

    static func blobSeedClearTombstoneDate(userDefaults: UserDefaults = .standard) -> Date? {
        self.blobSeedClearedAt(userDefaults: userDefaults)
    }

    static func deleteRows(
        deviceID: String,
        providerID: String,
        accountEmail: String?,
        accountRecordKey: String? = nil,
        in context: ModelContext) throws
    {
        let descriptor = FetchDescriptor<DailyCostPoint>(
            predicate: #Predicate {
                $0.deviceID == deviceID && $0.providerID == providerID
            })
        let rows = try context.fetch(descriptor)
        var didDelete = false
        for row in rows where Self.rowMatchesAccount(
            row,
            accountEmail: accountEmail,
            accountRecordKey: accountRecordKey)
        {
            context.delete(row)
            didDelete = true
        }
        if didDelete {
            try context.save()
        }
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
    static func seedFromExistingBlobs(in context: ModelContext, newerThan: Date? = nil) throws {
        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        let decoder = CloudSyncConstants.makeJSONDecoder()
        let encoder = CloudSyncConstants.makeJSONEncoder()
        for row in providers {
            guard let blob = row.costSummaryData,
                  let summary = try? decoder.decode(SyncCostSummary.self, from: blob)
            else { continue }
            let costUpdatedAt = summary.sourceUpdatedAt ?? row.lastUpdated
            if let newerThan, costUpdatedAt <= newerThan { continue }
            let payload = row.providerPayloadData.flatMap {
                try? decoder.decode(ProviderUsageSnapshot.self, from: $0)
            }
            let accountRecordKey = row.accountRecordKey ?? payload?.accountRecordKey
            let accountIdentityKeys = payload.map(Self.accountIdentityKeys(for:))
            let accountIdentityKey = accountIdentityKeys?.first
            for point in summary.daily {
                try Self.upsertDayPoint(
                    deviceID: row.deviceID,
                    providerID: row.providerID,
                    accountEmail: row.accountEmail,
                    accountRecordKey: accountRecordKey,
                    accountIdentityKey: accountIdentityKey,
                    accountIdentityKeys: accountIdentityKeys,
                    dayKey: point.dayKey,
                    costUSD: point.costUSD,
                    totalTokens: point.totalTokens,
                    costIsKnown: point.costIsKnown,
                    isEstimated: point.isEstimated,
                    modelBreakdowns: point.modelBreakdowns,
                    serviceBreakdowns: point.serviceBreakdowns,
                    lastUpdated: costUpdatedAt,
                    encoder: encoder,
                    in: context)
            }
        }
        try context.save()
    }

    /// Seed existing blob-path history while preserving an explicit clear
    /// boundary. Used by the Settings off→on path so re-enabling Local Cost
    /// History does not restore blob data the user just cleared.
    static func seedFromExistingBlobsRespectingClearTombstone(
        in context: ModelContext,
        userDefaults: UserDefaults = .standard) throws
    {
        try self.seedFromExistingBlobs(
            in: context,
            newerThan: self.blobSeedClearedAt(userDefaults: userDefaults))
    }

    private static func hasMissingSeedableCostBlobRows(in context: ModelContext, newerThan: Date?) throws -> Bool {
        let providers = try context.fetch(FetchDescriptor<ProviderSnapshotModel>())
        let decoder = CloudSyncConstants.makeJSONDecoder()
        let encoder = CloudSyncConstants.makeJSONEncoder()
        for row in providers {
            guard let blob = row.costSummaryData,
                  let summary = try? decoder.decode(SyncCostSummary.self, from: blob)
            else { continue }
            let costUpdatedAt = summary.sourceUpdatedAt ?? row.lastUpdated
            if let newerThan, costUpdatedAt <= newerThan { continue }
            let payload = row.providerPayloadData.flatMap {
                try? decoder.decode(ProviderUsageSnapshot.self, from: $0)
            }
            let accountRecordKey = row.accountRecordKey ?? payload?.accountRecordKey
            let accountIdentityKeys = payload.map(Self.accountIdentityKeys(for:))
            let accountIdentityKey = accountIdentityKeys?.first
            let accountIdentitiesData = accountIdentityKeys.flatMap { try? encoder.encode($0) }
            for point in summary.daily {
                let key = DailyCostPoint.makeCompositeKey(
                    deviceID: row.deviceID,
                    providerID: row.providerID,
                    accountEmail: row.accountEmail,
                    accountRecordKey: accountRecordKey,
                    dayKey: point.dayKey)
                let descriptor = FetchDescriptor<DailyCostPoint>(
                    predicate: #Predicate { $0.compositeKey == key })
                guard let existing = try context.fetch(descriptor).first else {
                    return true
                }
                if existing.lastUpdated < costUpdatedAt {
                    return true
                }
                if existing.lastUpdated == costUpdatedAt {
                    let modelData = point.modelBreakdowns.isEmpty
                        ? nil
                        : try? encoder.encode(point.modelBreakdowns)
                    let serviceData = point.serviceBreakdowns.isEmpty
                        ? nil
                        : try? encoder.encode(point.serviceBreakdowns)
                    if existing.accountEmail != row.accountEmail
                        || existing.accountRecordKey != accountRecordKey
                        || existing.accountIdentityKey != accountIdentityKey
                        || existing.accountIdentitiesData != accountIdentitiesData
                        || existing.costUSD != point.costUSD
                        || existing.totalTokens != point.totalTokens
                        || existing.costIsKnown != point.costIsKnown
                        || existing.isEstimated != point.isEstimated
                        || existing.modelBreakdownsData != modelData
                        || existing.serviceBreakdownsData != serviceData
                    {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func pruneLedgerRowsMissingProviderSnapshots(in context: ModelContext) throws {
        let providerKeys = try Set(
            context.fetch(FetchDescriptor<ProviderSnapshotModel>())
                .map(\.compositeKey))

        let rows = try context.fetch(FetchDescriptor<DailyCostPoint>())
        var didDelete = false
        for row in rows {
            let providerKey = ProviderSnapshotModel.makeCompositeKey(
                deviceID: row.deviceID,
                providerID: row.providerID,
                accountEmail: row.accountEmail,
                accountRecordKey: row.accountRecordKey)
            if !providerKeys.contains(providerKey) {
                context.delete(row)
                didDelete = true
            }
        }
        if didDelete {
            try context.save()
        }
    }

    private static func blobSeedClearedAt(userDefaults: UserDefaults) -> Date? {
        guard let rawValue = userDefaults.object(forKey: MobileSettingsKeys.cwlBlobSeedClearedAt) as? Double,
              rawValue > 0
        else {
            return nil
        }
        return Date(timeIntervalSince1970: rawValue)
    }

    private static func rowMatchesAccount(
        _ row: DailyCostPoint,
        accountEmail: String?,
        accountRecordKey: String?) -> Bool
    {
        if let accountRecordKey {
            return row.accountRecordKey == accountRecordKey
        }
        return row.accountRecordKey == nil && row.accountEmail == accountEmail
    }

    // MARK: - Helpers

    /// `[asOf - (windowDays - 1) days, asOf]` lower bound as a `YYYY-MM-DD`
    /// local dayKey string. Comparison against `DailyCostPoint.dayKey` works
    /// lexicographically because the format is fixed-width.
    static func cutoffDayKey(
        windowDays: Int,
        asOf: Date,
        timeZone: TimeZone = .current) -> String
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let localDay = calendar.startOfDay(for: asOf)
        let cutoff = calendar.date(
            byAdding: .day,
            value: -(windowDays - 1),
            to: localDay) ?? localDay
        return Self.dayKey(for: cutoff, timeZone: timeZone)
    }

    /// A CWL row retains its producing device ID and producer-local day key.
    /// Keep the window indexed by both device and provider identity so two
    /// Macs with different pinned cost timezones are never filtered through a
    /// lossy, post-merge provider calendar.
    private struct SourceDayWindowKey: Hashable {
        let deviceID: String
        let providerID: String
        let accountIdentity: String
    }

    private struct SourceDayWindow {
        let oldestDayKey: String
        let todayDayKey: String
        let costUpdatedAt: Date
        /// Producer-local day key -> reader-relative day key. This preserves
        /// logical age while giving all producers one canonical rollup axis.
        let readerRelativeDayKeys: [String: String]
    }

    private static func makeSourceDayWindows(
        snapshots: [SyncedUsageSnapshot],
        windowDays: Int,
        asOf: Date,
        readerTodayDayKey: String) -> [SourceDayWindowKey: SourceDayWindow]
    {
        var result: [SourceDayWindowKey: SourceDayWindow] = [:]
        let formatter = Self.logicalDayKeyFormatter()
        guard let readerToday = formatter.date(from: readerTodayDayKey) else {
            return result
        }
        var relativeDayKeysByProducerToday: [String: [String: String]] = [:]

        for snapshot in snapshots {
            let deviceID = snapshot.deviceID ?? SwiftDataBridge.deviceIDFallback(for: snapshot)
            for provider in snapshot.providers {
                guard let summary = provider.costSummary,
                      !summary.hasInvalidBucketTimeZoneIdentifier
                else { continue }
                let todayDayKey = summary.costDayKey(for: asOf)
                guard let today = formatter.date(from: todayDayKey),
                      let oldest = formatter.calendar.date(
                          byAdding: .day,
                          value: -(windowDays - 1),
                          to: today)
                else { continue }
                let readerRelativeDayKeys: [String: String]
                if let cached = relativeDayKeysByProducerToday[todayDayKey] {
                    readerRelativeDayKeys = cached
                } else {
                    var keys: [String: String] = [:]
                    for age in 0..<windowDays {
                        guard let producerDay = formatter.calendar.date(
                            byAdding: .day, value: -age, to: today),
                            let readerDay = formatter.calendar.date(
                                byAdding: .day, value: -age, to: readerToday)
                        else { continue }
                        keys[formatter.string(from: producerDay)] = formatter.string(from: readerDay)
                    }
                    relativeDayKeysByProducerToday[todayDayKey] = keys
                    readerRelativeDayKeys = keys
                }
                let window = SourceDayWindow(
                    oldestDayKey: formatter.string(from: oldest),
                    todayDayKey: todayDayKey,
                    costUpdatedAt: summary.sourceUpdatedAt ?? provider.lastUpdated,
                    readerRelativeDayKeys: readerRelativeDayKeys)
                for identity in Self.accountIdentityKeys(for: provider) {
                    let key = SourceDayWindowKey(
                        deviceID: deviceID,
                        providerID: provider.providerID,
                        accountIdentity: identity)
                    if result[key].map({ $0.costUpdatedAt < window.costUpdatedAt }) ?? true {
                        result[key] = window
                    }
                }
            }
        }
        return result
    }

    private static func readerRelativeDayKey(
        _ row: DailyCostPoint,
        readerCutoffKey: String,
        readerTodayKey: String,
        sourceDayWindows: [SourceDayWindowKey: SourceDayWindow],
        decoder: JSONDecoder) -> String?
    {
        let candidates = Self.accountIdentityKeys(for: row, decoder: decoder).compactMap { identity in
            sourceDayWindows[SourceDayWindowKey(
                deviceID: row.deviceID,
                providerID: row.providerID,
                accountIdentity: identity)]
        }
        if let window = candidates.max(by: { $0.costUpdatedAt < $1.costUpdatedAt }) {
            guard row.dayKey >= window.oldestDayKey,
                  row.dayKey <= window.todayDayKey
            else { return nil }
            return window.readerRelativeDayKeys[row.dayKey]
        }

        // Legacy or unmatched rows keep reader-local semantics. The upper
        // bound prevents future-dated rows from entering a current window.
        guard row.dayKey >= readerCutoffKey, row.dayKey <= readerTodayKey else {
            return nil
        }
        return row.dayKey
    }

    private static func logicalDayKeyFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func dayKey(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Private accumulators

    private struct AccountGrouping {
        let roots: [Int]
        let identityKeysByRoot: [Int: [String]]
        let preferredKeyByRoot: [Int: String]
    }

    private static func makeAccountGrouping(
        rows: [DailyCostPoint],
        decoder: JSONDecoder) -> AccountGrouping
    {
        var unionFind = LedgerUnionFind(count: rows.count)
        var firstSeen: [String: Int] = [:]
        let identities = rows.map { Self.accountIdentityKeys(for: $0, decoder: decoder) }
        for (index, rowIdentities) in identities.enumerated() {
            for identity in rowIdentities {
                let scoped = "\(rows[index].providerID)|\(identity)"
                if let prior = firstSeen[scoped] {
                    unionFind.union(index, prior)
                } else {
                    firstSeen[scoped] = index
                }
            }
        }

        let roots = rows.indices.map { unionFind.find($0) }
        var identitySets: [Int: Set<String>] = [:]
        var preferredRows: [Int: DailyCostPoint] = [:]
        for index in rows.indices {
            let root = roots[index]
            identitySets[root, default: []].formUnion(identities[index])
            if rows[index].accountIdentityKey != nil,
               preferredRows[root].map({ $0.lastUpdated < rows[index].lastUpdated }) ?? true
            {
                preferredRows[root] = rows[index]
            }
        }
        return AccountGrouping(
            roots: roots,
            identityKeysByRoot: identitySets.mapValues { $0.sorted() },
            preferredKeyByRoot: preferredRows.compactMapValues(\.accountIdentityKey))
    }

    private static func accountIdentityKeys(
        for row: DailyCostPoint,
        decoder: JSONDecoder) -> [String]
    {
        if let data = row.accountIdentitiesData,
           let decoded = try? decoder.decode([String].self, from: data),
           !decoded.isEmpty
        {
            return decoded
        }
        if let key = row.accountIdentityKey, !key.isEmpty {
            return [key]
        }
        if let normalized = AccountIdentityNormalize.normalize(row.accountEmail) {
            return ["\(row.providerID):email:\(normalized)"]
        }
        if let recordKey = row.accountRecordKey, !recordKey.isEmpty {
            return ["\(row.providerID):record:\(recordKey)"]
        }
        return ["\(row.providerID):legacy-no-identity"]
    }

    private struct LedgerUnionFind {
        var parent: [Int]

        init(count: Int) {
            self.parent = Array(0..<count)
        }

        mutating func find(_ value: Int) -> Int {
            if self.parent[value] != value {
                self.parent[value] = self.find(self.parent[value])
            }
            return self.parent[value]
        }

        mutating func union(_ lhs: Int, _ rhs: Int) {
            let leftRoot = self.find(lhs)
            let rightRoot = self.find(rhs)
            if leftRoot != rightRoot {
                self.parent[rightRoot] = leftRoot
            }
        }
    }

    private struct LedgerGroupKey: Hashable {
        let providerID: String
        let accountGroup: Int
        let dayKey: String
    }

    private struct AggregatedDailyCostPoint {
        let providerID: String
        let accountEmail: String?
        let accountIdentityKey: String?
        let accountIdentityKeys: [String]
        let dayKey: String
        let costUSD: Double
        let totalTokens: Int
        let costIsKnown: Bool?
        let isEstimated: Bool?
        let modelBreakdowns: [SyncCostBreakdown]
        let serviceBreakdowns: [SyncCostBreakdown]

        init(
            row: DailyCostPoint,
            dayKey: String? = nil,
            accountIdentityKey: String?,
            accountIdentityKeys: [String],
            decoder: JSONDecoder)
        {
            self.providerID = row.providerID
            self.accountEmail = row.accountEmail
            self.accountIdentityKey = accountIdentityKey
            self.accountIdentityKeys = accountIdentityKeys
            self.dayKey = dayKey ?? row.dayKey
            self.costUSD = row.costUSD
            self.totalTokens = row.totalTokens
            self.costIsKnown = row.costIsKnown
            self.isEstimated = row.isEstimated
            self.modelBreakdowns = Self.decodeBreakdowns(row.modelBreakdownsData, decoder: decoder)
            self.serviceBreakdowns = Self.decodeBreakdowns(row.serviceBreakdownsData, decoder: decoder)
        }

        static func mergingLocalCostRows(
            _ rows: [DailyCostPoint],
            dayKey: String,
            accountIdentityKey: String?,
            accountIdentityKeys: [String],
            decoder: JSONDecoder) -> AggregatedDailyCostPoint?
        {
            guard let first = rows.first else { return nil }
            var dayAccumulator = DayAccumulator(dayKey: dayKey)
            for row in rows {
                dayAccumulator.ingest(AggregatedDailyCostPoint(
                    row: row,
                    dayKey: dayKey,
                    accountIdentityKey: accountIdentityKey,
                    accountIdentityKeys: accountIdentityKeys,
                    decoder: decoder))
            }
            return AggregatedDailyCostPoint(
                providerID: first.providerID,
                accountEmail: first.accountEmail,
                accountIdentityKey: accountIdentityKey,
                accountIdentityKeys: accountIdentityKeys,
                dayKey: dayKey,
                costUSD: dayAccumulator.costUSD,
                totalTokens: dayAccumulator.totalTokens,
                costIsKnown: dayAccumulator.mergedCostIsKnown,
                isEstimated: dayAccumulator.isEstimated ? true : nil,
                modelBreakdowns: dayAccumulator.modelBreakdownsArray,
                serviceBreakdowns: dayAccumulator.serviceBreakdownsArray)
        }

        private init(
            providerID: String,
            accountEmail: String?,
            accountIdentityKey: String?,
            accountIdentityKeys: [String],
            dayKey: String,
            costUSD: Double,
            totalTokens: Int,
            costIsKnown: Bool?,
            isEstimated: Bool?,
            modelBreakdowns: [SyncCostBreakdown],
            serviceBreakdowns: [SyncCostBreakdown])
        {
            self.providerID = providerID
            self.accountEmail = accountEmail
            self.accountIdentityKey = accountIdentityKey
            self.accountIdentityKeys = accountIdentityKeys
            self.dayKey = dayKey
            self.costUSD = costUSD
            self.totalTokens = totalTokens
            self.costIsKnown = costIsKnown
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
        var sawKnownCost = false
        var sawUnknownCost = false
        var sawUnavailableCost = false
        var modelBreakdowns: [String: CostBreakdownAccumulator] = [:]
        var serviceBreakdowns: [String: CostBreakdownAccumulator] = [:]

        mutating func ingest(_ point: AggregatedDailyCostPoint) {
            self.costUSD += point.costUSD
            self.totalTokens += point.totalTokens
            if point.isEstimated == true {
                self.isEstimated = true
            }
            switch point.costIsKnown {
            case true: self.sawKnownCost = true
            case false: self.sawUnavailableCost = true
            case nil: self.sawUnknownCost = true
            }
            guard point.costIsKnown != false else { return }
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
                isEstimated: self.isEstimated ? true : nil,
                costIsKnown: self.mergedCostIsKnown)
        }

        var mergedCostIsKnown: Bool? {
            if self.sawUnavailableCost { return false }
            if self.sawUnknownCost { return nil }
            return self.sawKnownCost ? true : nil
        }
    }

    private struct ProviderAccumulator {
        let providerID: String
        let accountEmail: String?
        let accountIdentityKey: String?
        let accountIdentityKeys: [String]
        var costUSD: Double = 0
        var totalTokens: Int = 0
        var perDay: [String: DayAccumulator] = [:]
        var perModel: [String: CostBreakdownAccumulator] = [:]
        var perService: [String: CostBreakdownAccumulator] = [:]

        init(
            providerID: String,
            accountEmail: String?,
            accountIdentityKey: String?,
            accountIdentityKeys: [String])
        {
            self.providerID = providerID
            self.accountEmail = accountEmail
            self.accountIdentityKey = accountIdentityKey
            self.accountIdentityKeys = accountIdentityKeys
        }

        mutating func ingest(_ point: AggregatedDailyCostPoint) {
            self.costUSD += point.costUSD
            self.totalTokens += point.totalTokens
            self.perDay[point.dayKey, default: .init(dayKey: point.dayKey)].ingest(point)
            guard point.costIsKnown != false else { return }
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
                accountIdentityKey: self.accountIdentityKey,
                accountIdentityKeys: self.accountIdentityKeys,
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

extension [SyncCostBreakdown] {
    fileprivate func sortedByCostThenName() -> [SyncCostBreakdown] {
        self.sorted { lhs, rhs in
            if lhs.costUSD == rhs.costUSD {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.costUSD > rhs.costUSD
        }
    }
}
