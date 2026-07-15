# iCloud Sync Timeout and Diagnostics

Status: `in-progress`
Date: 2026-07-10
Updated: 2026-07-15
Branch: `upstream-sync/v0.41.0-mobile.1.18.0`
Release: Mac `0.41.0.1`; iOS `1.18.0 (187)`

## Incident

A Mac on the published `0.39.0.1` release repeatedly shows `Syncing…` after
quit/relaunch while iOS reports that Mac's newest data is two days old. The
affected Mac has no user-visible phase, timeout, or actionable error.

Code audit confirms that `isSyncing` is cleared only when the complete async
pipeline returns. Mac CloudKit zone fetch/create, legacy record fetch/save,
per-provider batch save, and stale-record delete have no wall-clock deadline.
If CloudKit never calls completion, the UI remains busy forever and the KVS
fallback is never written because it currently runs after the first CloudKit
await. The `0.41.0.1` draft inherited the same path unchanged, so this is a
release blocker before live publication.

## Required Outcome

- Every Mac write-side CloudKit operation has a bounded wall-clock deadline,
  actively cancels its underlying `CKOperation`, and ignores late callbacks.
- Mac sync is single-flight. Additional triggers coalesce into one newest-state
  retry rather than overlapping writes or silently dropping changes.
- KVS compatibility data is written before the CloudKit wait, while CloudKit
  timeout still reports the overall attempt as failed.
- A failed/uncertain per-provider write does not update hashes, run stale
  deletion, or advance cleanup state.
- Mac Mobile UI shows phase, elapsed time, timeout/partial failure, and Retry.
- Advanced → Show Debug Settings exposes iCloud diagnostics and the existing
  file log contains sanitized sync attempt events.
- iOS Developer Tools gains a separate read-only iCloud Sync diagnostic beside
  Push Setup. It does not create, modify, or delete Production data.
- No payload, record type, record field, zone name, record ID, subscription,
  index, entitlement, or CloudKit schema change.

## Release Handling

Mac stays `0.41.0.1 / 100.1.1.18.0` because the existing GitHub release is
again a draft after the user restored the PR-first gate on 2026-07-15. The
existing tag, ZIP, and dSYM predate the final bounded-flight review fix and are
stale; they must be replaced by a newly signed/notarized candidate only after
PR #49 has no blocking review or CI findings.
iOS remains marketing version `1.18.0`, but build advances from 186 to 187
because build 186 is already uploaded to App Store Connect.

`mobile-dev` again serves the published `0.39.0.1` appcast. PR #49 intentionally
contains no `0.41.0.1` appcast entry so merge cannot advertise a draft URL.
Live Mac publication, merge, App Store submission, and CloudKit deploy remain
out of scope until the PR-first review gate is explicitly cleared.
