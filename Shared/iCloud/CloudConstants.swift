import Foundation

/// Constants for iCloud sync between Mac and iOS.
public enum CloudSyncConstants {
    // MARK: - CloudKit

    /// The CloudKit container identifier shared by Mac and iOS apps.
    ///
    /// **WIRE CONTRACT · IRREVERSIBLE.** This string is burned into every
    /// CloudKit record, subscription, and zone ever written by any client.
    /// Renaming it makes every existing user's synced data invisible (the
    /// records still exist under the old container, just nobody reads them)
    /// and forces re-pairing across Mac + iOS. Never change without a
    /// user-migration plan.
    public static let containerIdentifier = "iCloud.com.o1xhack.codexbar"

    /// The CloudKit record type for per-device usage snapshots.
    ///
    /// **WIRE CONTRACT.** Mac writes records of this type, iOS queries them.
    /// Renaming orphans every existing `DeviceSnapshot` in `customZoneName` —
    /// old records stay, new writes go elsewhere, iOS sees a "first-run"
    /// state for every user. The legacy zone is still used as a fallback for
    /// users on Mac builds prior to P4 per-provider zone migration.
    public static let recordType = "DeviceSnapshot"

    /// Custom record zone name for per-device usage snapshots.
    ///
    /// **WIRE CONTRACT.** `CKRecordZoneSubscription` on this zone name is how
    /// iOS gets silent pushes when Mac writes. If this string changes, all
    /// existing subscriptions on every iPhone become orphaned — push
    /// notifications silently stop until users manually re-trigger setup.
    public static let customZoneName = "DeviceSnapshotsZone"

    /// Record type for per-provider snapshot records (P4 — split from the
    /// monolithic `DeviceSnapshot` payload so each provider can be uploaded and
    /// downloaded incrementally, and so a single provider's state never has to
    /// share CloudKit's 1MB-per-record budget with everything else).
    ///
    /// **WIRE CONTRACT.** Record names follow the format
    /// `"{deviceID}|{providerID}|{accountEmail ?? "_"}"` (see
    /// `CloudSyncManager.perProviderRecordName` on Mac + iOS matching parser
    /// in `SnapshotCache.compositeKey`). Renaming this record type or the
    /// record-name format orphans every incremental-sync record and breaks
    /// delete cascades via `CKModifyRecordsOperation.recordIDsToDelete`.
    public static let providerRecordType = "DeviceProviderSnapshot"

    /// Dedicated zone for per-provider snapshot records. New zone (not reused
    /// from `customZoneName`) so a future server-side prune of legacy
    /// `DeviceSnapshot` records never disturbs provider-level data, and so
    /// per-provider `CKRecordZoneSubscription` subs can be set up independently.
    ///
    /// **WIRE CONTRACT.** Same concern as `customZoneName`: iOS subscriptions
    /// on this exact zone name are how per-provider incremental pushes reach
    /// the device. Renaming = silent loss of push delivery.
    public static let providerZoneName = "DeviceProvidersZone"

    /// Bumped when the on-wire payload format changes (compression algorithm,
    /// envelope shape, etc.). Stored in the `encodingVersion` CKRecord field so
    /// readers can reject records they don't understand instead of silently
    /// decoding garbage.
    public static let providerPayloadVersion = 1

    /// Record type for user-confirmed account linkages between provider
    /// snapshots whose union-find identifiers DON'T overlap on their own
    /// (e.g. one Mac is too old to emit `accountIdentities` and the other
    /// is current). See Research/019 §7. Records live in the same
    /// `DeviceProvidersZone` as the per-provider snapshots so the existing
    /// zone subscription delivers updates incrementally.
    ///
    /// **WIRE CONTRACT.** Record name format `"linkage-{recordUUID}"`. The
    /// `linkedIdentifiers: [String]` field carries the same `cardIdentityKey`
    /// composite key (`providerID|accountEmail`) iOS already uses for union-find
    /// — adding a virtual edge between any snapshots whose effective identifiers
    /// contain at least one of those listed. Renaming the record type or field
    /// names orphans every existing linkage on every iPhone — there is no
    /// migration path; treat it as permanent.
    public static let providerAccountLinkageRecordType = "ProviderAccountLinkage"

    /// Record type for user-confirmed lifecycle events for Mac sync devices.
    ///
    /// **WIRE CONTRACT.** Record name format `"device-lifecycle-{recordUUID}"`.
    /// Records live in `DeviceProvidersZone` so iOS can share the existing zone
    /// subscription and change-token surface. Renaming this record type or its
    /// field names orphans every merge/archive decision a user has made.
    public static let deviceLifecycleEventRecordType = "DeviceLifecycleEvent"

    // MARK: - JSON codec factories
    //
    // ALL CloudKit / SwiftData blob encode-decode in this codebase MUST go
    // through these factories. The Build 66 root cause was a `JSONEncoder()`
    // constructed with default `dateEncodingStrategy = .deferredToDate`
    // (encoded `Date` as `TimeInterval` Double) while the decoder used
    // `.iso8601` (expected ISO8601 string), so every payload that round-tripped
    // through the mismatched pair lost its `Date` fields. Centralising the
    // construction here prevents future drift.

    /// JSONEncoder configured for CodexBar wire formats. Uses ISO8601 dates so
    /// Mac↔iOS, CloudKit-payload↔SwiftData-blob, and SwiftData-blob↔SwiftData-blob
    /// round-trips all agree on `Date` representation.
    public static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// JSONDecoder configured for CodexBar wire formats. Pair with
    /// `makeJSONEncoder()` — never construct `JSONDecoder()` directly for
    /// CodexBar types.
    public static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Legacy zone used by Build 42–49. Kept only so we can delete the stale
    /// `quota-transition-zone-sub` on upgrade; no new records are written here.
    public static let quotaTransitionsZoneName = "QuotaTransitionsZone"

    /// Dedicated zone for "quota depleted" push events. Split by state (not predicate)
    /// because CKQuerySubscription does not persist on this container (A/B test
    /// confirmed, see `QuotaTransitionSubscriptions.swift`). Splitting by zone lets
    /// each CKRecordZoneSubscription carry its own static localization key.
    ///
    /// **WIRE CONTRACT.** Zone-name change silences every "quota depleted"
    /// push notification in production until users manually reinstall / reset
    /// CodexBar on Mac — there's no migration path for zone renames.
    public static let quotaDepletedZoneName = "QuotaDepletedZone"

    /// Dedicated zone for "quota restored" push events. See `quotaDepletedZoneName`.
    ///
    /// **WIRE CONTRACT.** Same concern; silences "quota restored" pushes on
    /// rename. Users miss recovery notifications.
    public static let quotaRestoredZoneName = "QuotaRestoredZone"

    /// CloudKit record type for visible quota change push events (alert push design).
    /// One record per (provider, hourBucket) within each state-specific zone — see
    /// `Research/004-alert-push-cloudkit.md`.
    public static let quotaTransitionRecordType = "QuotaTransition"

    /// Subscription ID used by Build 42–49 (single zone-level sub on
    /// `QuotaTransitionsZone`). Kept as a constant so the new setup code can
    /// delete it during upgrade.
    public static let quotaTransitionLegacySubscriptionID = "quota-transition-zone-sub"

    /// Subscription ID for the "depleted" CKRecordZoneSubscription on
    /// `QuotaDepletedZone`.
    public static let quotaTransitionDepletedSubscriptionID = "quota-transition-depleted"

    /// Subscription ID for the "restored" CKRecordZoneSubscription on
    /// `QuotaRestoredZone`.
    public static let quotaTransitionRestoredSubscriptionID = "quota-transition-restored"

    /// UserDefaults key for the stable device UUID (persisted on each Mac).
    public static let deviceIDKey = "com.codexbar.sync.deviceID"

    // MARK: - Legacy KVS (kept for backward compatibility during transition)

    /// The key used in NSUbiquitousKeyValueStore for the usage snapshot.
    public static let kvsSnapshotKey = "com.codexbar.usage.snapshot"

    /// Maximum allowed payload size for NSUbiquitousKeyValueStore (1 MB).
    public static let maxKVSPayloadBytes = 1_048_576

    /// Legacy alias — existing tests reference `maxPayloadBytes`.
    public static let maxPayloadBytes = maxKVSPayloadBytes
}
