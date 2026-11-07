# CloudKit save-result identity: independent static review

Verdict: no actionable defect found in the proposed production fix. This is a source review, not a build/test or rebuilt-artifact approval.

Base HEAD: `dfa3dc0b84c8ae07e3faaec8e9fe56f8b509d603`. Reviewed working tree has an uncommitted production change.
CloudSyncEngine.swift SHA256: `5e1fb737c85da2d6429b38363b835c746897063cf844c97f06de3c369f5edb5b`.
Reviewed production diff SHA256: `3c84819bdce13c9c5639de72e150a7195c8e07de729d9e05cc66e9007e3c9f3a`.

## Root cause

`UsageSnapshot.init(from:)` intentionally removes native Claude/Grok live reset-credit detail sections (`Sources/CodexBarCore/UsageFetcher.swift:462`). Consequently, decoding the saved encrypted usagePayload and re-encoding an AccountSnapshotSyncPayload can yield a different hash from the original publication. The old save-result predicate could reject a successful save and retain its in-flight marker indefinitely. The same predicate also filters failures, so retry/conflict handling was affected.

## Reviewed fix and invariants

- SaveContents at CloudSyncEngine.swift:221 captures schemaVersion, provider, deviceID, accountKey, fetchedAt, displayLabel, and raw encrypted usagePayload string. It does not decode UsageSnapshot. Complete CKRecord.ID indexes the desired record; the existing recordName indexes the pending marker.
- shouldApplySaveResult at line 284 requires both the marker and current desired record for account snapshots; missing/removed state rejects late results. Other record types retain existing behavior.
- Successful and failed result filters both use the new predicate (lines 1452 and 1476). Successful confirmation removes desired state and transfers the existing pending hash to lastSnapshotHashes synchronously before an actor suspension. Existing persisted hash format, deduplication, and migration logic are unchanged.
- pushPendingSnapshots defers newer publications when a marker exists (line 2492); it updates fleet/pending payloads without changing the desired record. Once confirmation clears the marker, the newer queued payload can be published normally.
- Conflict rebasing, server recreation, and late-result system-field refresh use copyUserFields (line 1825), preserving raw user fields while replacing CloudKit system metadata. Required comparison fields therefore remain stable through retries.
- Retryable failures retain the marker/desired record; existing terminal/future-schema/remote-wins paths release state as before. A deleted/cancelled desired record cannot be confirmed by a delayed callback.
- CanonicalSyncJSON keeps its existing ISO8601 date precision. This review does not propose a new date/hash contract or persistence migration.

## Recommended regression coverage

1. Native Claude and Grok identity plus live reset-credit sections: prove decoding changes the original payload hash, then verify the raw result is accepted and the original pending hash becomes the confirmed hash.
2. Existing delayed-old-result versus newer desired record scenario, including duplicate callbacks after marker removal.
3. Independently changed schema/provider/device/account/fetchedAt/label/raw usagePayload rejects the result.
4. Missing marker and missing desired record each reject matching content.
5. System-field rebasing via copyUserFields preserves confirmation; failure-filter matching reaches the existing retry/conflict path.
6. Non-account record behavior remains unchanged.

No source files were modified by the reviewer. Build/test adaptation was still in progress at review time. The prior Mac signed artifact does not contain this new fix and needs replacement/reverification; iOS shipping inputs are unaffected by this Mac-only file change.
