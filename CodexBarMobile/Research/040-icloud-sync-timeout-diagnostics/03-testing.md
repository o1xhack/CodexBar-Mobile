# iCloud Sync Timeout and Diagnostics Testing

Status: `in-progress`
Date: 2026-07-10
Updated: 2026-07-15

## Gate Ledger

| Gate | Result | Evidence |
|---|---|---|
| Root-cause audit | pass | Mac CloudKit writes are unbounded; UI only reports returned failures; KVS is blocked behind legacy CloudKit await |
| Safety design review | pass | three independent reviews require cancellable CKOperation deadlines, exactly-once completion, single-flight/coalescing, and no state advancement after uncertain writes |
| Focused timeout/cancellation tests | pass | `swift test --filter CloudOperationDeadlineTests`: 6/6; covers synchronous success, underlying error, hard timeout/cancel, task cancellation, ignored late callback, and completion-gate release |
| SyncCoordinator regression | pass | post-review `swift test --filter SyncCoordinatorTests`: 29 tests in 2 suites passed; adds failure + queued-request termination and request-during-catch-up coverage while preserving successful coalescing |
| Mac full build/lint/tests | in progress | the signed candidate baseline passed `swift build`, lint, and all 52 isolated groups; the final bounded-flight and release-guard changes pass focused tests and require the refreshed PR CI/full gate before a new artifact is built |
| iOS build/tests/localization | pass | clean signed simulator run: 549 tests in 40 suites passed, including KVS/CloudKit error fallbacks and Widget snapshot parity; source/catalog audit clean; `1.18.0 (187)` |
| CloudKit Production schema audit | pass — no deploy | diff from prior draft tag adds no record type, field, zone, subscription, index, payload key, or encoding version; all Mac/iOS entitlements remain Production |
| Compatibility matrix impact | substituted | behavior changes the Mac write transport only; wire payload/schema/readers remain unchanged; 16 cases listed below |
| Signed/notarized Mac draft replacement | stale — rebuild required | notarization `fbe990bd-88a1-4589-9a5e-4a13e399a04a` and the 47,517,361-byte ZIP / 36,747,485-byte dSYM remain historical valid artifacts, but they predate the final bounded-flight fix and cannot be published; phase 1 must move the tag and replace both assets after PR approval |
| Sparkle candidate appcast | pass as historical evidence; removed from PR | `100.1.1.18.0`, prior archive length and EdDSA verification passed; PR #49 restores `appcast.xml` to the `mobile-dev` baseline, and finalize must regenerate/push the entry only after the replacement release is live |
| TestFlight 1.18.0 (187) | pass — VALID | archive/export/upload succeeded; App Store Connect build `c4922050-46d5-4ef7-8368-99a9a7302b2a`, uploaded 2026-07-10 18:34 PDT, `processingState=VALID`, `expired=false` |
| Final review blockers | in progress | PR review found and fixed an unbounded failure retry, premature draft appcast, shallow-checkout lint gate, and unsafe finalize checkout/artifact reuse; refreshed CI and final re-review are still required |

## PR-First Rollback and Review Evidence (2026-07-15)

- PR #49: `https://github.com/o1xhack/CodexBar-Mobile/pull/49`, base
  `mobile-dev`, head `upstream-sync/v0.41.0-mobile.1.18.0`; no merge performed.
- The GitHub Release was briefly changed from draft to live, then immediately
  restored to `draft=true` when the user required PR review first. Release CLI
  run `29449826232` was cancelled; its partial CLI assets are non-authoritative.
- The temporary appcast-only commit `efc86247` was reverted on `mobile-dev` by
  `a2fd82f1`. A cache-busted public feed read again reports `0.39.0.1` /
  `97.1.1.17.0` as the top item.
- First PR CI exposed missing checkout history in the parser-version audit even
  though SwiftLint reported zero violations. Commit `a8b8117f` restored
  `fetch-depth: 0`; the next lint job passed.
- Independent review then found that a failed 45-second CloudKit operation
  could consume an unlimited stream of pending refreshes and keep one flight
  alive forever. The final implementation limits a flight to the initial write
  plus one catch-up, ends immediately on failure, and schedules changes arriving
  during catch-up as a separate bounded flight.
- `Scripts/release.sh` now refuses finalize outside a clean checkout exactly
  matching `origin/mobile-dev`, requires the tag to be contained in that branch,
  and rejects/rebuilds artifacts when Mac build inputs changed after the ZIP's
  embedded `CodexGitCommit`.

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
