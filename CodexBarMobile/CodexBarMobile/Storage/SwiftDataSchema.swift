import Foundation
import SwiftData

// MARK: - SwiftData Schema (Contract C1 · research doc 009)
//
// P2a scope: introduce SwiftData as the iOS local persistent store.
// Views still read from the legacy `@Observable SyncedUsageData` path;
// P2b will migrate them to `@Query`.
//
// Schema overview:
//
//   DeviceRecord (1) ──< ProviderSnapshotModel (N) ──< UtilizationEntryModel (N)
//   SyncStateRecord (independent — one row per CloudKit zone)
//
// Uniqueness strategy:
// - `DeviceRecord.deviceID`               — @Attribute(.unique)
// - `ProviderSnapshotModel.compositeKey`  — @Attribute(.unique)
//   SwiftData does not support multi-attribute `.unique`, so we store a
//   stable composed string `{deviceID}|{providerID}|{accountEmail ?? ""}`
//   and enforce uniqueness on that. The three source fields are kept as
//   first-class properties so @Query can filter without parsing the key.
// - `SyncStateRecord.zoneName`            — @Attribute(.unique)
// - `UtilizationEntryModel` has no unique key. Dedup is enforced by the
//   upsert bridge on (provider, seriesName, capturedAt).

// MARK: - Device

@Model
final class DeviceRecord {
    /// Stable UUID coming from `SyncedUsageSnapshot.deviceID`. For legacy
    /// single-device snapshots without a deviceID, bridge layer substitutes
    /// a deterministic fallback (see `SwiftDataBridge.deviceIDFallback`).
    @Attribute(.unique) var deviceID: String
    var deviceName: String
    var appVersion: String?
    var lastSyncAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ProviderSnapshotModel.device)
    var providers: [ProviderSnapshotModel] = []

    init(
        deviceID: String,
        deviceName: String,
        appVersion: String? = nil,
        lastSyncAt: Date = .now
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.lastSyncAt = lastSyncAt
    }
}

// MARK: - Provider Snapshot

@Model
final class ProviderSnapshotModel {
    /// Unique key composed from `deviceID|providerID|accountEmail ?? ""`.
    /// SwiftData does not currently support composite `.unique`; using a
    /// computed-and-stored key keeps uniqueness enforceable at the store level.
    @Attribute(.unique) var compositeKey: String

    var deviceID: String
    var providerID: String
    var providerName: String
    var accountEmail: String?
    var loginMethod: String?
    var statusMessage: String?
    var isError: Bool
    var lastUpdated: Date
    var subscriptionExpiresAt: Date?
    var subscriptionRenewsAt: Date?

    /// JSON-encoded `ProviderUsageSnapshot` — canonical cold-start mirror.
    /// Older rows leave this nil and fall back to the decomposed columns below.
    var providerPayloadData: Data?

    /// JSON-encoded `[SyncRateWindow]` — opaque blob, decoded on read.
    var rateWindowsData: Data
    /// JSON-encoded `SyncCostSummary` — opaque blob, decoded on read.
    var costSummaryData: Data?
    /// JSON-encoded `SyncBudgetSnapshot` — opaque blob, decoded on read.
    var budgetData: Data?
    /// JSON-encoded `SyncPerplexityCreditSummary` — opaque blob, decoded on
    /// read. Only populated for `providerID == "perplexity"` when Mac is
    /// pushing structured credit data (Mac 0.20.3+); nil for every other
    /// provider and for legacy Mac payloads.
    var perplexityCreditsData: Data?

    @Relationship(deleteRule: .cascade, inverse: \UtilizationEntryModel.provider)
    var utilizationEntries: [UtilizationEntryModel] = []

    var device: DeviceRecord?

    init(
        deviceID: String,
        providerID: String,
        providerName: String,
        accountEmail: String? = nil,
        loginMethod: String? = nil,
        statusMessage: String? = nil,
        isError: Bool = false,
        lastUpdated: Date,
        subscriptionExpiresAt: Date? = nil,
        subscriptionRenewsAt: Date? = nil,
        providerPayloadData: Data? = nil,
        rateWindowsData: Data = Data("[]".utf8),
        costSummaryData: Data? = nil,
        budgetData: Data? = nil,
        perplexityCreditsData: Data? = nil,
        device: DeviceRecord? = nil
    ) {
        self.compositeKey = Self.makeCompositeKey(
            deviceID: deviceID,
            providerID: providerID,
            accountEmail: accountEmail)
        self.deviceID = deviceID
        self.providerID = providerID
        self.providerName = providerName
        self.accountEmail = accountEmail
        self.loginMethod = loginMethod
        self.statusMessage = statusMessage
        self.isError = isError
        self.lastUpdated = lastUpdated
        self.subscriptionExpiresAt = subscriptionExpiresAt
        self.subscriptionRenewsAt = subscriptionRenewsAt
        self.providerPayloadData = providerPayloadData
        self.rateWindowsData = rateWindowsData
        self.costSummaryData = costSummaryData
        self.budgetData = budgetData
        self.perplexityCreditsData = perplexityCreditsData
        self.device = device
    }

    /// Build the composite unique key. Used by the upsert bridge to look up
    /// existing rows and by the initializer. **Format must stay byte-identical
    /// to `CloudSyncManager.perProviderRecordName` and
    /// `SnapshotCache.compositeKey` — `"_"` for nil `accountEmail`.** Letting
    /// these drift means a delete-by-recordName from CloudKit silently misses
    /// the matching SwiftData row, and any cross-layer key comparison breaks.
    /// (Codex hardening review on Build 67 surfaced the empty-string-vs-`"_"`
    /// drift here.)
    static func makeCompositeKey(
        deviceID: String,
        providerID: String,
        accountEmail: String?
    ) -> String {
        "\(deviceID)|\(providerID)|\(accountEmail ?? "_")"
    }
}

// MARK: - Utilization Entry

@Model
final class UtilizationEntryModel {
    /// e.g. "session" / "weekly" / "opus". Matches `SyncUtilizationSeries.name`.
    var seriesName: String
    var capturedAt: Date
    var usedPercent: Double
    var resetsAt: Date?
    /// Window length in minutes (from parent series). Stored redundantly so
    /// per-entry @Query filtering can group by window without a join.
    var windowMinutes: Int

    var provider: ProviderSnapshotModel?

    init(
        seriesName: String,
        capturedAt: Date,
        usedPercent: Double,
        resetsAt: Date? = nil,
        windowMinutes: Int = 0,
        provider: ProviderSnapshotModel? = nil
    ) {
        self.seriesName = seriesName
        self.capturedAt = capturedAt
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
        self.provider = provider
    }
}

// MARK: - Sync State (per CloudKit zone)

@Model
final class SyncStateRecord {
    /// CloudKit zone name (e.g. "DeviceSnapshotsZone", "DeviceProvidersZone").
    @Attribute(.unique) var zoneName: String
    /// Archived `CKServerChangeToken` blob. Nil on first sync.
    var changeTokenData: Data?
    var lastSyncAt: Date

    init(zoneName: String, changeTokenData: Data? = nil, lastSyncAt: Date = .distantPast) {
        self.zoneName = zoneName
        self.changeTokenData = changeTokenData
        self.lastSyncAt = lastSyncAt
    }
}

// MARK: - Schema registry

enum CodexBarSwiftDataSchema {
    /// Registered @Model types. Keep this array in sync with the declarations
    /// above. `ModelContainerFactory` feeds it to `ModelContainer(for:)`.
    ///
    /// `DailyCostPoint` (declared in `CostLedgerModels.swift`) is the Cost
    /// Window Ledger entity introduced in Round 1 / P1 of research doc 024.
    /// Added here so SwiftData lightweight-migrates existing stores to
    /// include the new table on first open.
    static let models: [any PersistentModel.Type] = [
        DeviceRecord.self,
        ProviderSnapshotModel.self,
        UtilizationEntryModel.self,
        SyncStateRecord.self,
        DailyCostPoint.self,
    ]
}

// MARK: - Contract C3 · SnapshotIdentityKey

/// Stable cache-invalidation key for view-level `@State` caches.
/// Used by P1 (`UtilizationAggregateView`, `CostShareCardView`, etc.) to detect
/// when underlying data changed without hashing the entire snapshot.
///
/// - `providerIDs`: sorted, comma-joined `providerID` list.
/// - `lastUpdated`: max `lastUpdated` across all visible providers.
///
/// Semantics: two keys are equal iff both the provider set AND the newest
/// `lastUpdated` are equal. Adding/removing a provider changes `providerIDs`;
/// refreshing any provider changes `lastUpdated`.
struct SnapshotIdentityKey: Hashable, Sendable {
    let providerIDs: String
    let lastUpdated: Date

    init(providerIDs: String, lastUpdated: Date) {
        self.providerIDs = providerIDs
        self.lastUpdated = lastUpdated
    }

    /// Build from an arbitrary collection of providers.
    static func make<S: Sequence>(
        providerIDs: S,
        lastUpdated: Date
    ) -> SnapshotIdentityKey where S.Element == String {
        SnapshotIdentityKey(
            providerIDs: providerIDs.sorted().joined(separator: ","),
            lastUpdated: lastUpdated)
    }
}
