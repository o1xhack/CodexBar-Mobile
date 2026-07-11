# iCloud Sync Timeout and Diagnostics Testing

Status: `in-progress`
Date: 2026-07-10

## Gate Ledger

| Gate | Result | Evidence |
|---|---|---|
| Root-cause audit | pass | Mac CloudKit writes are unbounded; UI only reports returned failures; KVS is blocked behind legacy CloudKit await |
| Safety design review | pass | three independent reviews require cancellable CKOperation deadlines, exactly-once completion, single-flight/coalescing, and no state advancement after uncertain writes |
| Focused timeout/cancellation tests | pass | `swift test --filter CloudOperationDeadlineTests`: 6/6; covers synchronous success, underlying error, hard timeout/cancel, task cancellation, ignored late callback, and completion-gate release |
| SyncCoordinator regression | pass | `swift test --filter SyncCoordinatorTests`: 26/26; added single-flight/coalescing, failure-phase, and provider-failure retry assertions |
| Mac full build/lint/tests | pass | `swift build` pass; final `./Scripts/lint.sh` pass with 0 violations; all 52 isolated test groups passed. Group 27 initially caught missing catch-up-catalog keys, then passed after Galician/Indonesian/Italian/Polish/Turkish parity was completed |
| iOS build/tests/localization | pass | clean signed simulator run: 549 tests in 40 suites passed, including KVS/CloudKit error fallbacks and Widget snapshot parity; source/catalog audit clean; `1.18.0 (187)` |
| CloudKit Production schema audit | pass — no deploy | diff from prior draft tag adds no record type, field, zone, subscription, index, payload key, or encoding version; all Mac/iOS entitlements remain Production |
| Compatibility matrix impact | substituted | behavior changes the Mac write transport only; wire payload/schema/readers remain unchanged; 16 cases listed below |
| Signed/notarized Mac draft replacement | pending | |
| TestFlight 1.18.0 (187) | pending | |
| Final review blockers | pass — 0 | two final review loops verified cancellation closure release, observation rearm, phase ownership, localized/live status, correct failure phase, versioning and release consistency |

## Production Safety

The diagnostic path must remain read-only. No test record, test zone,
subscription, record type, field, query index, encoding version, or payload key
may be added. Existing push-test tools remain separate and are not invoked by
the new iCloud diagnostic.

## 2 Mac × 2 iPhone Compatibility Matrix

Old Mac = published `0.39.0.1`; new Mac = fixed `0.41.0.1` candidate. Old
iPhone = published/TestFlight `1.17.0`; new iPhone = `1.18.0 (187)` candidate.
The four physical-device placements cannot be automated from this development
Mac before the candidate is installed on the user's two Macs/two iPhones, so
all 16 rows use the same conservative substituted evidence:

- wire/schema diff is empty (`CloudConstants.swift`, `UsageSnapshot.swift`,
  payload version, record types/fields/zones/subscriptions unchanged);
- existing cross-version encode/decode, merge, ghost cleanup, per-provider,
  KVS fallback, and mapper tests remain in the full test suite;
- new transport tests prove exactly-once timeout completion, underlying
  operation cancellation, late-callback suppression, coalesced newest-state
  follow-up, and no provider hash advancement after failure;
- iOS reader code and cache/merge behavior are unchanged; the new diagnostic is
  read-only and the normal Refresh action calls the existing reader.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Remaining risk |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | unchanged released baseline | real CloudKit/account/network state |
| 2 | old | old | old | new | substituted | reader/wire audit + iOS build | real silent-push/cache timing |
| 3 | old | old | new | old | substituted | reader/wire audit + iOS build | real silent-push/cache timing |
| 4 | old | old | new | new | substituted | reader/wire audit + iOS build | two-iPhone convergence |
| 5 | old | new | old | old | substituted | optional wire compatibility + bounded writer tests | mixed-writer CloudKit timing |
| 6 | old | new | old | new | substituted | wire/merge tests + bounded writer tests | mixed-device convergence |
| 7 | old | new | new | old | substituted | wire/merge tests + bounded writer tests | mixed-device convergence |
| 8 | old | new | new | new | substituted | wire/merge tests + bounded writer tests | two-iPhone convergence |
| 9 | new | old | old | old | substituted | symmetric writer identity audit | mixed-writer CloudKit timing |
| 10 | new | old | old | new | substituted | wire/merge tests + bounded writer tests | mixed-device convergence |
| 11 | new | old | new | old | substituted | wire/merge tests + bounded writer tests | mixed-device convergence |
| 12 | new | old | new | new | substituted | wire/merge tests + bounded writer tests | two-iPhone convergence |
| 13 | new | new | old | old | substituted | old-reader optional-wire audit | two-Mac operation timing |
| 14 | new | new | old | new | substituted | single-flight + merge/ghost tests | mixed-iPhone cache timing |
| 15 | new | new | new | old | substituted | single-flight + merge/ghost tests | mixed-iPhone cache timing |
| 16 | new | new | new | new | substituted | full candidate build/test gates | physical four-device convergence |

## Manual Acceptance After Candidate Installation

1. On the previously stuck Mac, enable file logging in Advanced → Debug, press
   Sync Now, and verify it reaches success or a phase-specific timeout/failure;
   it must never remain indefinitely on “Syncing”.
2. Run the read-only diagnostic on that Mac and copy the report. Confirm account
   available, both zones available, and KVS payload decodable (a missing zone is
   valid only before the first successful write).
3. On iPhone build 187, open Settings → Developer Tools → iCloud Sync
   Diagnostics, run the read-only check, then Refresh Synced Data. Confirm both
   Macs and their latest timestamps converge on both iPhones.
4. Repeat the document's 16 placements while retaining screenshots/log reports.
