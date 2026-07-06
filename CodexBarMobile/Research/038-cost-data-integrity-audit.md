# 038 — Cost Data Integrity Audit

Status: done  
Date: 2026-07-06  
Scope: iOS 1.17.0 Cost dashboard, Cost Window Ledger, Provider Share, share cards

## Finding

The Cost dashboard jump was not caused by a single rendering bug. The unstable
number came from two different cost reducers being allowed to disagree:

- `CloudSyncReader` / blob path used `ProviderSnapshotMerger`, where
  local-cost providers (`codex`, `claude`, `vertexai`) are summed across Macs.
- `CostLedgerService.aggregate` used one latest-wins rule for every provider.
  That is correct for account-level APIs, but wrong for local CLI history.
- Local cache hydration, full fetch, SwiftData persistence, and silent push can
  temporarily render either path, so the same screen can bounce between summed
  local data and latest-device local data before settling.

This affects more than the top Overview number. The same wrong reducer feeds:

- `total30DayCost`, `total30DayTokens`, `totalTodayCost`
- `activeDayCount`, `dailyPoints`
- provider rollups / Provider Share
- Model Mix and Codex Service Mix
- share-card provider contribution

## Correct Rules

Provider cost semantics must be provider-aware:

- Local-cost providers: sum active-device daily rows for the same
  `(providerID, accountEmail, dayKey)`.
- Account-level providers: keep the latest row for the same
  `(providerID, accountEmail, dayKey)`.
- Account identity is part of the key. Two accounts of the same provider stay
  distinct.
- Archived devices are excluded before local-cost summing.
- Model/service/category breakdowns must be merged from the same daily rows as
  totals; they must not be recomputed from a different path.
- Provider Share should include only positive spend rows. Zero-spend providers
  can still exist in raw data, but they are not spend contributors.
- Share cards must compute 7-day provider share from provider daily points,
  not by scaling 30-day provider totals.

## Fix Implemented

- `ProviderSnapshotMerger` now exposes the local-cost provider semantic and
  preserves service breakdowns, estimated flags, standard/priority cost/token
  split, request counts, and currency when merging local-cost summaries.
- `CostLedgerService.aggregate` now uses the same local-cost/account-level
  reducer as the blob path and accepts active device IDs so archived device
  rows are filtered before aggregation.
- `CostDashboardInsights.ProviderRow` now carries resolved today tokens and
  provider daily points.
- Provider Share uses `spendProviderRows` so `$0.00` rows do not appear as
  contribution cards.
- `ShareCardData` computes Today tokens from resolved daily totals and computes
  7-day provider contribution from exact provider daily points.
- iOS `MARKETING_VERSION` remains `1.17.0`; build is bumped to `182`.

## Test Coverage

New and updated tests cover:

- CWL local-cost same-day multi-device sum.
- CWL account-level same-day latest-wins.
- CWL active-device filtering.
- CWL model/service/split metadata preservation.
- Blob vs CWL equivalence for multi-device local-cost data.
- Shared CloudKit merge preservation of service breakdowns and split metadata.
- Provider Share zero-spend filtering.
- Share-card exact 7-day provider contribution.
- Share-card Today token resolution.

Validation on 2026-07-06:

- Focused affected suites: 66 passed, 0 failed.
- Full iOS suite on iPhone 17 simulator: 538 passed, 0 failed, 4 skipped.
- `bash Scripts/lint.sh lint`: passed.
- `git diff --check`: passed.
- TestFlight upload: `1.17.0 (182)` uploaded from
  `/tmp/CodexBarMobile-20260706-153422.xcarchive`; App Store Connect build id
  `225b252c-ec68-426c-99a6-298f39fd6290`, `processingState=VALID`, uploaded
  `2026-07-06T15:37:48-07:00`.

## Residual Risk

This fixes the iOS reducer and presentation mismatch. It cannot retroactively
delete stale ledger rows already written by old builds, so active-device
filtering is part of the fix. If future provider cost sources change from local
history to account-wide APIs, they must move out of the local-cost provider set
with tests for both blob and CWL paths.
