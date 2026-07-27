# Subscription Utilization Fresh-Series Fallback — Sync Compatibility Testing

Status: `substituted`
Date: 2026-07-26
Canonical gate: [`docs/ios-sync-compatibility-testing.md`](../../../docs/ios-sync-compatibility-testing.md)

## Verdict

All 16 old/new placements are recorded and have no simulated failure. The
physical gate is **not complete**: this workspace has one Mac and one iOS
Simulator, not two independent Macs and two physical iPhones with retained
old/new signed builds. PR review and merge may proceed, but iOS build 191 must
not be treated as physically release-ready until silent-push, independent-cache,
and real CloudKit convergence are exercised on the four-device matrix.

Versions represented by this hotfix matrix:

- old Mac: `0.45.2.1`; new Mac: `0.45.2.2`
- old iOS reader: `1.19.0 (188)`; new iOS reader: `1.19.1 (191)`
- uploaded build `1.19.0 (189)` contains the same Subscription Utilization
  selection fix as build 191, but predates the Alibaba iOS presentation changes

The Subscription Utilization fix changes only the new iOS reader's selection of
already-synced history. It adds no Mac writer change, Shared field, CloudKit
record type, schema field, zone, subscription, entitlement, or encoding version.

No live provider account, browser cookie, Keychain item, Production CloudKit
record, or physical-device push was used.

## Substituted Evidence

| ID | Validation | Result |
|---|---|---|
| S1 | XcodeBuildMCP ran `SubscriptionUtilizationCompatTests`, `CloudKitMergeTests`, `ViewCacheIdentityTests`, `DualZoneReaderTests`, `SnapshotCacheTests`, and `SyncModelTests` together on iPhone 17 Simulator: 159 passed, 0 failed. | pass |
| S2 | The two new regressions reproduce stale `session` plus current `weekly`, and fresh 0% `session` plus non-zero `weekly`. The new reader falls back only for stale data and never treats 0% as missing. Duplicate selected series are still unioned before aggregation. | pass |
| S3 | `CloudKitMergeTests` exercises two distinct Mac device identities, opposite freshness orders, utilization-series union, stale/idle histories, zero histories, and deterministic merge order. `DualZoneReaderTests` and `SnapshotCacheTests` cover old/new zone fallback, replay, ghost filtering, cache replacement, and multi-device retention. | pass |
| S4 | `SyncModelTests` covers old payload decoding, legacy version keys, JSON round trips, and unknown future fields. Source diff audit confirms this hotfix does not change `Shared/`, `CloudConstants`, entitlements, schema, writer code, or payload version. | pass |
| S5 | Final reviewed source passed the complete simulator suite with 610 tests, 0 failures, and 4 intentional SpringBoard skips; the focused multi-account suite passed 13/13. `xcodegen generate` synchronized all app, push-extension, widget, and sync-framework targets at build 191. Root lint, localization, and CI-policy gates passed. | pass |
| S6 | The Alibaba mixed-writer compatibility evidence remains recorded in [`043/03-testing.md`](../043-alibaba-token-plan-rate-windows/03-testing.md); the combined branch reran its merge and presentation regressions before this matrix was written. | pass |

## 2 Mac × 2 iPhone Matrix

Every row is `substituted` because two independent physical iPhone caches,
silent-push delivery, and Production CloudKit convergence cannot be reproduced
in this one-Mac simulator environment.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | S3, S4 | R3: old readers retain the known stale-session display bug; no wire or cache corruption is introduced. |
| 2 | old | old | old | new | substituted | S1–S5 | R1: real silent-push and independent-cache convergence unverified. |
| 3 | old | old | new | old | substituted | S1–S5 | R1: real silent-push and independent-cache convergence unverified. |
| 4 | old | old | new | new | substituted | S1–S5 | R1–R2: two-reader convergence and real sampling cadence unverified. |
| 5 | old | new | old | old | substituted | S3, S4, S6 | R3: old readers retain the known display bug; mixed-writer integrity is substituted. |
| 6 | old | new | old | new | substituted | S1–S6 | R1–R2: mixed-writer delivery and clock/sampling cadence unverified. |
| 7 | old | new | new | old | substituted | S1–S6 | R1–R2: mixed-writer delivery and clock/sampling cadence unverified. |
| 8 | old | new | new | new | substituted | S1–S6 | R1–R2: two-reader convergence and clock/sampling cadence unverified. |
| 9 | new | old | old | old | substituted | S3, S4, S6 | R3: symmetric mixed-writer evidence; old readers retain the known display bug. |
| 10 | new | old | old | new | substituted | S1–S6 | R1–R2: mixed-writer delivery and clock/sampling cadence unverified. |
| 11 | new | old | new | old | substituted | S1–S6 | R1–R2: mixed-writer delivery and clock/sampling cadence unverified. |
| 12 | new | old | new | new | substituted | S1–S6 | R1–R2: two-reader convergence and clock/sampling cadence unverified. |
| 13 | new | new | old | old | substituted | S3, S4, S6 | R3: old readers retain the known display bug; no incompatible payload was added. |
| 14 | new | new | old | new | substituted | S1–S6 | R1–R2: real cache transition and sampling cadence unverified. |
| 15 | new | new | new | old | substituted | S1–S6 | R1–R2: real cache transition and sampling cadence unverified. |
| 16 | new | new | new | new | substituted | S1–S6 | R1–R2: four-device convergence and sampling cadence unverified. |

## Residual Risks

- **R1 — Physical delivery and cache convergence:** two iPhones have not
  independently received foreground fetches and silent pushes from two Mac
  device records.
- **R2 — Real sampling cadence and clock skew:** the two-hour freshness grace is
  covered with deterministic timestamps, but not with two physical Mac clocks,
  missed hourly samples, sleep/wake, and delayed CloudKit delivery.
- **R3 — Old-reader behavior:** old iOS readers remain compatible and do not
  lose data, but they retain the reported stale-session selection bug. The fix
  is intentionally reader-side and requires the new iOS build.

## Remaining Release QA

Before releasing build 191 as iOS 1.19.1, execute all
16 rows on two Macs and two physical iPhones. For each applicable row, retain a
screenshot or diagnostic log showing:

1. both Mac device records and their utilization histories remain present;
2. each new iPhone uses current `session` history when fresh and falls back to
   the freshest semantic series when `session` is stale;
3. both iPhones converge after foreground fetch and silent push without ghost
   providers, duplicated series, or cache regressions;
4. upgrading either iPhone preserves the cache and corrects the stale-session
   aggregate without requiring data deletion.

Until this evidence exists, the final iOS release-gate result remains
`substituted`, not a physical-device `pass`.
