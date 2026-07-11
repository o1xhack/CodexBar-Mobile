# iCloud Sync Timeout and Diagnostics Design

Status: `ready`
Date: 2026-07-10

## Safety Invariants

1. A timeout first wins an exactly-once completion gate, then cancels the
   underlying `CKOperation`; a late callback cannot resume a continuation or
   mutate coordinator state.
2. Only one sync attempt writes at a time. A trigger during an attempt sets one
   pending flag; after completion the coordinator rebuilds and pushes the
   newest state once.
3. Stable record IDs make retry idempotent. Timeout or partial failure never
   advances provider hashes, stale-record baselines, or missing counters.
4. Stale delete runs only after the per-provider delta is confirmed successful
   or there was no delta.
5. KVS remains compatibility-only. Writing it before CloudKit prevents a hang
   from blocking old readers but never converts a CloudKit timeout into success.
6. Diagnostic checks are read-only. They may inspect account status, existing
   zone availability, local synced snapshots, and KVS status; they may not save,
   modify, delete, reset, or create Production objects.

## Mac State Model

Phases: preparing snapshot, legacy CloudKit, provider CloudKit, stale cleanup,
and completed. Each attempt records its start time, elapsed time, phase
transitions, result, and sanitized message.

The normal Mobile pane stays concise. When debug settings are enabled it also
offers the read-only health report and file log entry point. The Debug pane
shows current/last attempt state, recent in-memory events, run-read-only-check,
copy-report, enable/open file log controls.

## iOS Diagnostic

Developer Tools adds `iCloud Sync Diagnostics` alongside `Push Setup`.
It displays account/container status, legacy/provider zone availability, KVS
availability, the current reader status/error, and per-device freshness. Its
actions are `Run Read-only Check`, normal `Refresh Synced Data`, and
`Copy Diagnostic Report`.

## Test Plan

- deadline gate: success, hard error, timeout cancellation, task cancellation,
  synchronous completion, and late callback exactly-once stress;
- coordinator: normal success/failure, provider partial failure, delete failure,
  single-flight/coalescing, retry state, and no cleanup advancement;
- existing ghost cleanup, multi-account, mapper, payload, and CloudKit tests;
- iOS diagnostic formatting and read-only result rendering;
- Mac/iOS build, full lint, four-language audit, full test suites;
- CloudKit Production schema audit and the existing 16-row compatibility
  evidence updated for this release.
