# Alibaba Token Plan Rate Windows — Sync Compatibility Testing

Status: `substituted`
Date: 2026-07-24
Canonical gate: [`docs/ios-sync-compatibility-testing.md`](../../../docs/ios-sync-compatibility-testing.md)

## Verdict

The 16-case compatibility gate is recorded and has no simulated failure. Real
hardware coverage is **not complete**: this workspace has one Mac and one iOS
Simulator, not two independent Macs and two physical iPhones with old/new
signed builds. The PR may complete code review, but release QA must treat the
remaining silent-push, independent-cache, and real CloudKit convergence risk as
unverified until the physical matrix is run.

Versions represented by the substituted checks:

- old Mac: `0.45.2.1`; new Mac: `0.45.2.2`
- old iOS: `1.19.0 (188)`; new iOS: `1.19.0 (189)`

No live Alibaba account, browser cookies, Keychain item, Production CloudKit
record, or signed old build was used. This preserves the task's authorization
boundary and avoids prompting for credentials.

## Substituted Evidence

| ID | Validation | Result |
|---|---|---|
| S1 | `swift test --filter AlibabaTokenPlan` passed 62 tests in 11 suites. Coverage includes monthly-only, 5-hour + weekly, weekly-only, and weekly + monthly partial responses. Semantic slots stay `primary = 5-hour`, `secondary = Weekly`, `tertiary = Credits`. | pass |
| S2 | `DashboardSnapshotBuilderTests` (11), `CLIGuardDecisionTests` (14), and the Alibaba menu/Widget/sync checks cover CLI guard inputs, menu/card labels, Widget rows, Dashboard JSON kinds, and sync projection. Weekly-only never becomes a session window. | pass |
| S3 | `CloudKitMergeTests` runs two distinct Mac device IDs in both old/new freshness orders and two opposite reader input orders. Alibaba lanes converge in canonical order `5-hour`, `Weekly`, `Credits`; all 54 merge tests pass. | pass |
| S4 | All 15 `SyncWireFormatRoundTripTests` pass, including current-reader decode of payloads without `rateWindows`; the branch adds no Shared field, CloudKit record type, index, entitlement, or schema change. Old clients retain the existing `primary` / `secondary` wire fields. | pass |
| S5 | `V045ProviderPresentationTests` verifies the new iOS reader's semantic localization keys. On iPhone 17 / iOS 26.4 Simulator, 604 non-UI tests pass; the serialized UI target passes 3 tests with 4 SpringBoard-only cases skipped by their environment guard. | pass |
| S6 | Source audit confirms both iPhone paths consume `ProviderUsageSnapshot.allRateWindows`; mixed-device merge is deterministic and independent of snapshot input order. Ghost filtering and account/device identity code are unchanged. | pass |

## 2 Mac × 2 iPhone Matrix

Every row is marked `substituted` because independent physical-device caches,
silent pushes, and Production CloudKit delivery cannot be reproduced in this
single-Mac simulator environment.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | S3, S4, S6 | R1: real silent-push and independent-cache convergence unverified. |
| 2 | old | old | old | new | substituted | S3–S6 | R1: real silent-push and independent-cache convergence unverified. |
| 3 | old | old | new | old | substituted | S3–S6 | R1: real silent-push and independent-cache convergence unverified. |
| 4 | old | old | new | new | substituted | S3–S6 | R1: real silent-push and independent-cache convergence unverified. |
| 5 | old | new | old | old | substituted | S1–S4, S6 | R1: real silent-push and independent-cache convergence unverified. |
| 6 | old | new | old | new | substituted | S1–S6 | R1: real silent-push and independent-cache convergence unverified. |
| 7 | old | new | new | old | substituted | S1–S6 | R1: real silent-push and independent-cache convergence unverified. |
| 8 | old | new | new | new | substituted | S1–S3, S5, S6 | R1: real silent-push and independent-cache convergence unverified. |
| 9 | new | old | old | old | substituted | S1–S4, S6 | R1: real silent-push and independent-cache convergence unverified. |
| 10 | new | old | old | new | substituted | S1–S6 | R1: real silent-push and independent-cache convergence unverified. |
| 11 | new | old | new | old | substituted | S1–S6 | R1: real silent-push and independent-cache convergence unverified. |
| 12 | new | old | new | new | substituted | S1–S3, S5, S6 | R1: real silent-push and independent-cache convergence unverified. |
| 13 | new | new | old | old | substituted | S1–S4, S6 | R1: real silent-push and independent-cache convergence unverified. |
| 14 | new | new | old | new | substituted | S1–S6 | R1: real silent-push and independent-cache convergence unverified. |
| 15 | new | new | new | old | substituted | S1–S6 | R1: real silent-push and independent-cache convergence unverified. |
| 16 | new | new | new | new | substituted | S1–S3, S5, S6 | R1: real silent-push and independent-cache convergence unverified. |

## Risk Found and Fixed During Matrix Review

The first mixed-writer simulation exposed a real compatibility defect outside
the original review comment: if an old Mac wrote the freshest monthly-only
snapshot, its `Credits` lane replaced the new Mac's rolling windows.
`ProviderSnapshotMerger` now unions Alibaba's named lanes across active writers
and restores canonical order. The test runs both freshness orders and opposite
reader input orders, preventing one iPhone's fetch order from changing the
visible result.

## Remaining Release QA

Before a live release, run the same 16 rows on two Macs and two physical
iPhones. For each row, record screenshots or logs showing:

1. both Macs retain distinct device records;
2. both iPhones converge to identical `5-hour`, `Weekly`, and `Credits` rows;
3. foreground fetch and silent push both refresh without duplicated or ghost
   cards;
4. upgrading either device preserves its cache and account identity.

Until that evidence exists, this document's final release-gate result remains
`substituted`, not a physical-device `pass`.
