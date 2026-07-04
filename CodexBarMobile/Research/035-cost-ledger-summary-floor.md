# 035 — Cost Ledger Summary Floor

Status: `done`
Date: 2026-06-29
Scope: CodexBar Mobile Cost dashboard aggregation and local-cost multi-device merge.

## Bug

User TestFlight QA found the Cost page undercounting spend relative to Raw Sync Data:

- Cost page showed roughly `$2,679.20` for the selected 90-day window.
- Raw Sync Data for a single synced Mac showed Claude `$2,638.98` plus Codex `$2,368.16`, already about `$5,007.14` before any other providers.
- Raw also showed Claude `$1.49 / today`, while the Cost page reported only Codex active today.

The Cost page therefore violated a basic data invariant: for an equal-or-longer selected window, the rendered provider total must not be lower than the synced provider summary from Raw Sync Data.

## Root Cause

With Cost Window Ledger enabled, `CostDashboardInsights.fromLedger(...)` used only `CostLedgerProviderRollup.totalCostUSD`, which is computed from persisted `daily[]` rows.

That is correct for trend charts and model/service breakdowns, but not as the sole source for provider totals:

- Mac can sync a complete summary total in `SyncCostSummary.last30DaysCostUSD`.
- The accompanying `daily[]` history can be partial or temporarily incomplete.
- In that case, CWL daily aggregation undercounts provider totals even though Raw Sync Data has the authoritative summary.

The multi-device local-cost merge had the same class of risk: `CloudSyncReader.mergeCostSummaries(...)` recomputed merged totals from `daily[]` instead of first summing each device's synced summary total.

## Fix

- `CostDashboardInsights.fromLedger(...)` now resolves provider display totals through `ledgerDisplayTotals(...)`.
- For a selected CWL window equal to the provider summary window, the provider summary is authoritative.
- For a selected CWL window longer than the provider summary window, the summary acts as a floor; the displayed total is at least the raw synced summary.
- For a selected CWL window shorter than the provider summary window, the ledger window remains authoritative so 7-day views are not inflated by 30-day summaries.
- CWL today cost now falls back to `costSummary.todayTotals()` when the ledger has no row for today.
- `CloudSyncReader.mergeCostSummaries(...)` now sums per-device summary totals for local-cost providers, falling back to daily totals only when a device has no summary field.
- Provider Share subtitle now says "selected cost window" for non-30-day CWL windows instead of hardcoding "30-day".

## Verification

Added regression coverage:

- `CWLEquivalenceTests.testLedgerProviderTotalsUseSnapshotSummaryFloor`
- `CWLEquivalenceTests.testLedgerShorterWindowDoesNotUseLongerSnapshotSummary`
- `CloudKitMergeTests.localCostSummaryTotalsPreservedWhenDailyIncomplete`
- Strengthened `CloudKitMergeTests.localCostStillSumsAfterRefactor` to assert summary totals are summed too.

Release target:

- Corrective iOS TestFlight build: `1.16.0 (168)`.
- Upload completed on 2026-06-29:
  - Archive: `/tmp/CodexBarMobile-20260629-211537.xcarchive`
  - App Store Connect build check: `1.16.0 (168)` uploaded at `2026-06-29T21:19:19-07:00`, build id `01a13bf5-8a83-4c0f-a3b7-6a2e996817ff`, `processingState=VALID`.
- Release-notes re-upload completed on 2026-06-29:
  - Archive: `/tmp/CodexBarMobile-20260629-221212.xcarchive`
  - App Store Connect build check: `1.16.0 (169)` uploaded at `2026-06-29T22:15:05-07:00`, build id `ba744863-1aa5-4f29-aa3d-844de0b430df`, `processingState=VALID`.

## iOS Sync Compatibility Gate

This change touches synced provider display data and merge logic, so
`docs/ios-sync-compatibility-testing.md` applies.

Real 2 Mac x 2 iPhone old/new hardware coverage was not available in this
agent run. The release uses substituted validation: focused unit tests for
single-device CWL rendering, summary-only providers, shorter CWL windows, and
multi-device local-cost merge; plus simulator test execution on the new iOS
build. Remaining risk is real-device CloudKit cache convergence and mixed
old/new silent-push timing, to be validated through TestFlight QA.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | Not changed by new iOS code path; existing clients unchanged | Baseline only |
| 2 | old | old | old | new | substituted | `CloudKitMergeTests` + `CWLEquivalenceTests` on new iOS | New iOS reads existing payload shape |
| 3 | old | old | new | old | substituted | Same as case 2 | Reader order should not matter |
| 4 | old | old | new | new | substituted | Focused simulator tests passed | Both new readers use same merge logic |
| 5 | old | new | old | old | substituted | Old iOS not modified; new Mac payload shape unchanged by this iOS fix | No schema change |
| 6 | old | new | old | new | substituted | Local-cost merge tests cover two writer summaries | Real push/cache timing not exercised |
| 7 | old | new | new | old | substituted | Same as case 6 | Reader order should not matter |
| 8 | old | new | new | new | substituted | Multi-device summary merge tests | Real-device convergence remains QA item |
| 9 | new | old | old | old | substituted | Symmetric with case 5 | No schema change |
| 10 | new | old | old | new | substituted | Symmetric with case 6 | Real push/cache timing not exercised |
| 11 | new | old | new | old | substituted | Symmetric with case 7 | Reader order should not matter |
| 12 | new | old | new | new | substituted | Symmetric with case 8 | Real-device convergence remains QA item |
| 13 | new | new | old | old | substituted | Old iOS not modified; Mac payload shape unchanged | No schema change |
| 14 | new | new | old | new | substituted | New iOS focused tests; old iOS unchanged | Mixed reader cache not exercised |
| 15 | new | new | new | old | substituted | Same as case 14 | Mixed reader cache not exercised |
| 16 | new | new | new | new | substituted | Focused simulator tests passed | Final validation via TestFlight |
