import Foundation
import SwiftData

// MARK: - DailyCostPoint (Cost Window Ledger · research doc 024)

//
// Per-device, per-provider, per-day cost ledger entry. Together these rows
// form the iOS-side append + dedupe ledger that lets the Cost dashboard show
// longer windows than Mac's current `historyDays`. Round 1 / P1 introduces
// only the model + schema registration; writer (P2) / reader (P3) / UI (P4)
// come in later rounds. See `Research/024-cost-window-ledger/ARCHITECTURE.md`.
//
// Uniqueness: `compositeKey = "{deviceID}|{providerID}|{dayKey}"` — same
// `@Attribute(.unique)` pattern used by `ProviderSnapshotModel`. SwiftData
// has no native composite-unique; the three source fields stay first-class
// so `@Query` filters work without parsing.
//
// Lightweight migration: adding this entity to
// `CodexBarSwiftDataSchema.models` is handled by SwiftData automatically. Old
// stores without this table will be upgraded in place on first open (verified
// by `CWLMigrationTests` / T16). No `VersionedSchema` / `SchemaMigrationPlan`
// introduced this round — current `ModelContainerFactory` policy is
// "init-failure → delete + recreate" (it's a CloudKit cache, can be
// repopulated). Revisit once a real field-change migration is needed.

@Model
final class DailyCostPoint {
    /// Composite unique key `{deviceID}|{providerID}|{dayKey}`. The three
    /// source fields below are also stored directly for query-side filtering.
    /// **Format must stay byte-identical across writer / reader / tests** —
    /// drift here silently produces duplicate rows for the same logical day.
    @Attribute(.unique) var compositeKey: String

    var deviceID: String
    var providerID: String
    /// Account email (`nil` for single-account providers). Part of the
    /// composite key so multi-account providers (two Codex accounts on one
    /// Mac, etc.) keep separate per-day rows — matching the blob path's
    /// `ProviderSnapshotModel` per-(providerID, accountEmail) granularity.
    /// Without this, the two accounts collide on `(deviceID, providerID,
    /// dayKey)` and one silently overwrites the other.
    var accountEmail: String?
    /// Opaque record identity. It owns per-device row uniqueness when present,
    /// so editable account-label changes do not create a new history bucket.
    var accountRecordKey: String?
    /// Stable cross-Mac merge identity selected from the wire identity set.
    /// This differs from `accountRecordKey` when two Macs know the same real
    /// account by authenticated email/org but use different local token UUIDs.
    var accountIdentityKey: String?
    /// Encoded `[String]` identity set used for the same overlap/union
    /// semantics as `ProviderSnapshotMerger` across mixed Mac writers.
    var accountIdentitiesData: Data?
    /// `YYYY-MM-DD` UTC, matches `SyncDailyPoint.dayKey` on the wire.
    var dayKey: String

    var costUSD: Double
    var totalTokens: Int
    /// Mirrors `SyncCostBreakdown.isEstimated` rolled up to the day. Preserved
    /// so the iOS estimated-badge (P5) still works under CWL.
    var isEstimated: Bool?

    /// Encoded `[SyncCostBreakdown]` — preserves `isEstimated`,
    /// `standardCostUSD` / `priorityCostUSD` / `standardTokens` /
    /// `priorityTokens` (gap A Codex standard/fast split). Decoded on read.
    var modelBreakdownsData: Data?
    /// Encoded `[SyncCostBreakdown]` for service-level breakdowns. Decoded on read.
    var serviceBreakdownsData: Data?

    /// When this day's data was last refreshed by the Mac that pushed it.
    /// Used by the writer's dedup:
    /// `if existing.lastUpdated >= new.lastUpdated → skip` (we already have
    /// fresher data for this `(deviceID, providerID, dayKey)`). Also used by
    /// the reader's multi-device merge — same `(providerID, dayKey)` across
    /// devices, latest `lastUpdated` wins.
    var lastUpdated: Date

    init(
        deviceID: String,
        providerID: String,
        accountEmail: String?,
        accountRecordKey: String? = nil,
        accountIdentityKey: String? = nil,
        accountIdentitiesData: Data? = nil,
        dayKey: String,
        costUSD: Double,
        totalTokens: Int,
        isEstimated: Bool? = nil,
        modelBreakdownsData: Data? = nil,
        serviceBreakdownsData: Data? = nil,
        lastUpdated: Date)
    {
        self.compositeKey = Self.makeCompositeKey(
            deviceID: deviceID,
            providerID: providerID,
            accountEmail: accountEmail,
            accountRecordKey: accountRecordKey,
            dayKey: dayKey)
        self.deviceID = deviceID
        self.providerID = providerID
        self.accountEmail = accountEmail
        self.accountRecordKey = accountRecordKey
        self.accountIdentityKey = accountIdentityKey
        self.accountIdentitiesData = accountIdentitiesData
        self.dayKey = dayKey
        self.costUSD = costUSD
        self.totalTokens = totalTokens
        self.isEstimated = isEstimated
        self.modelBreakdownsData = modelBreakdownsData
        self.serviceBreakdownsData = serviceBreakdownsData
        self.lastUpdated = lastUpdated
    }

    /// Compose the composite unique key. Format pinned:
    /// `{deviceID}|{providerID}|{accountEmail ?? "_"}|{dayKey}`. The `"_"`
    /// for nil `accountEmail` matches `ProviderSnapshotModel.makeCompositeKey`
    /// byte-for-byte. Writer + reader + tests must all build it via this
    /// helper so any future format change propagates uniformly.
    static func makeCompositeKey(
        deviceID: String,
        providerID: String,
        accountEmail: String?,
        accountRecordKey: String? = nil,
        dayKey: String) -> String
    {
        "\(deviceID)|\(providerID)|\(accountRecordKey ?? accountEmail ?? "_")|\(dayKey)"
    }
}
