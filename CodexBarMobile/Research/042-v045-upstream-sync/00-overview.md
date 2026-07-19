# v0.45.2 Upstream Sync + iOS 1.19.0 Overview

Status: `in-progress`
Date: 2026-07-19
Branch: `upstream-sync/v0.45.2-mobile.1.19.0`
Open issues:
- [#48](https://github.com/o1xhack/CodexBar-Mobile/issues/48) — upstream `v0.42.1`
- [#51](https://github.com/o1xhack/CodexBar-Mobile/issues/51) — upstream `v0.43.0`

## Branch Preflight

The worktree was clean and local `mobile-dev` exactly matched
`origin/mobile-dev` at `6e4d605f`. Before any research or implementation file
was written, the branch required by the Goal was created:

```text
git switch mobile-dev
git pull --ff-only origin mobile-dev
git switch -c upstream-sync/v0.45.2-mobile.1.19.0
```

All research, merge, implementation, versioning, testing, packaging, and
review work for this train stays on that branch. Push, merge, a published tag,
live release, TestFlight upload, and CloudKit Production deploy remain outside
the authorization boundary.

## Authoritative Baseline

`version.env` is the fork alignment source of truth:

| Field | Baseline |
|---|---|
| `MARKETING_VERSION` | `0.41.0.1` |
| `BUILD_NUMBER` | `100.1` |
| `MOBILE_VERSION` | `1.18.0` |
| `UPSTREAM_VERSION` | `v0.41.0` |
| `UPSTREAM_SYNC_DATE` | `2026-07-06` |

All four iOS targets are currently `1.18.0 (187)`. The latest published fork
release is `v0.41.0.1-mobile.1.18.0`, published on 2026-07-15.

## Upstream Facts and One-Version Scope

GitHub Releases for `steipete/CodexBar` are authoritative. Open issues #48 and
#51 were created for v0.42.1 and v0.43.0, but the release source of truth had
already advanced through v0.45.2 when this Goal started. Per the Goal's
single-version rule, the complete stable range is consolidated into one train:

| Release | Published UTC | Principal scope |
|---|---:|---|
| `v0.42.0` | 2026-07-11 03:48 | Agent Sessions, Wayfinder, reset countdowns, predictive pace alerts, Codex Spark/pricing, scoped Claude windows, refresh and account-isolation fixes |
| `v0.42.1` | 2026-07-12 04:25 | Factory API auth, adaptive replay tooling, settings grouping, Cursor widgets, auth/reset/cost-history fixes |
| `v0.43.0` | 2026-07-14 12:48 | sub2api, Kimi CLI credential reuse, process/PTY hardening, provider cleanup, cost debounce and Ultra-lineage fixes |
| `v0.44.0` | 2026-07-17 16:57 | ZenMux, ClinePass, LongCat, Neuralwatt, local Usage & Spend/share card, secure hooks/serve, provider cost and identity fixes |
| `v0.45.0` | 2026-07-18 17:33 | Custom menu layouts, weekly forecast, guard/cookie CLI, adaptive refresh, OpenRouter multi-account, ai&, DeepInfra, Doubao and cost improvements |
| `v0.45.1` | 2026-07-19 07:59 | claude-swap scoped windows, OpenCode Go history, six-provider overview, period-alignment and share-card fixes |
| `v0.45.2` | 2026-07-19 17:23 | macOS 14 TaskLocal crash fix, menu/widget rendering fixes, weekly-window selection, sub-1% and OpenCode Go source fixes |

The target release tag object is `64495789`; it peels to commit
`91560ca98e776b96fdf910d4a0423c2f0c07a3b9`. The published baseline tag is
already an ancestor of the fork branch. The upstream range contains 937 total
commits (667 non-merge commits) and changes 1,017 files, so the merge must keep
upstream provenance and cannot be replaced with a selective feature cherry-pick.

Notable related upstream commits/PRs include `121e9ca1` (Factory API, #2062),
`bf92f4ab` (sub2api), `59f22361`/`3544b634` (Wayfinder), `59c08133`
(ZenMux, #2133), `3cb9d0d9` (ClinePass), `479e1284` (Neuralwatt), `f4b31523`
(LongCat), `c8307313` (DeepInfra), `324d9fa0`/`55679cef` (ai&), `da84f161`
(claude-swap windows), and `088fdf8c` (macOS 14 launch crash).

## Historical Upstream-sync Prior Art

Closed upstream-sync issues #4-#46 and Research 037/039 establish the reusable
pattern: overlapping monitor issues close through one release train; branch
before edits; retain both raw upstream and fork Mobile changelog sections;
preserve fork CI/release/CloudKit policy; regenerate parser version/hash when
scanner inputs move; keep old-provider compatibility during rolling upgrades;
and record all 16 compatibility combinations without calling substituted
evidence real-device QA.

## Mac Functional Scope

The merge includes all upstream Mac functionality, fixes, performance work,
security hardening, tests, CLI behavior, provider changes, settings, widgets,
localizations, and packaging improvements through v0.45.2. Fork conflicts are
resolved only where needed to preserve Mobile Settings, Mac-to-iOS sync,
CloudKit Production, composite versioning, appcast/release ownership, and the
fork CI trigger model.

The merge forecast identifies conflicts in fork CI/monitor scripts, the root
changelog, CI gate helpers, Mobile Settings files, 22 Mac localization files,
provider/token-account state, parser cache/pricing files and tests, appcast,
and `version.env`. The full conflict ledger is maintained in
`02-development.md`.

## iOS and Shared Impact

Upstream adds eight provider IDs and retires two:

| Provider | Upstream data | iOS decision |
|---|---|---|
| ClinePass | 5-hour, weekly, monthly quotas | Generic rate-window card; add subscription, mock, color and wire tests |
| DeepInfra | balance, monthly spend/limit, suspension | Reuse existing budget/cost/credits fields where lossless; document any Mac-only detail |
| Neuralwatt | subscription kWh and prepaid credits | Generic quota/credit rendering with first-class identity/color |
| LongCat | quota and fuel-pack tracking | Generic quota/credit rendering; credentials remain Mac-only |
| sub2api | daily/weekly/monthly quotas, multi-account, wallet, expiry | Reuse rate windows, account identity, credits and plan metadata; add multi-account wire proof |
| Wayfinder | gateway health, routing, savings and latency | Sync only the existing generic usage/cost values; local gateway operations remain Mac-only |
| ZenMux | 5-hour/weekly quotas, expiry, PAYG balance | Reuse rate windows, plan/expiry text and credits/budget |
| ai& | 30-day organization spend with partial-result label | Reuse existing cost summary and provider identity; preserve partial-result honesty if serialized |

`kimik2` and `crossmodel` are removed from the new Mac provider registry. New
iOS keeps their legacy rendering/subscriptions during this train so old Macs
and cached records remain readable; new Mac code stops producing them.

The preliminary source audit found no upstream changes under fork `Shared/`.
The design therefore prefers the existing opaque payload fields rather than a
new CloudKit record field. Final decisions depend on post-merge mapper audits
and focused encode/decode tests.

## Target Version Plan

Upstream v0.45.2 declares `MARKETING_VERSION=0.45.2` and `BUILD_NUMBER=109`.
`docs/versioning.md` yields one fork release:

| Artifact | Target |
|---|---|
| Mac `MARKETING_VERSION` | `0.45.2.1` |
| Mac `BUILD_NUMBER` | `109.1` |
| iOS `MOBILE_VERSION` | `1.19.0` |
| iOS `CURRENT_PROJECT_VERSION` | `188` |
| Sparkle/app `CFBundleVersion` | `109.1.1.19.0` |
| Local/draft tag name | `v0.45.2.1-mobile.1.19.0` |
| Upstream bookmark | `v0.45.2` / `2026-07-19` |

Upstream movement resets the fork patch to `.1`; iOS advances one feature
minor because provider-visible identities, quota windows, costs and
cross-version rendering change.

## Gates and Risks

- The 16-case 2 Mac x 2 iPhone gate applies because provider IDs, display data,
  account identity, payload mapping, caches and rolling-upgrade rendering move.
- Production CloudKit deploy is not expected if all additions remain optional
  data inside the existing opaque payload. The final audit must compare the
  last published fork tag to HEAD and may override this preliminary verdict.
- Parser scanner/cache sources move, so `parserLogicVersion` and generated
  `CodexParserHash` must both advance.
- Removed providers must not cause old Mac records, subscription cleanup, or
  cached iOS data to disappear during the mixed-version window.
- Release preparation may produce signed/notarized local artifacts and a draft
  manifest. A remote draft link must not be fabricated by pushing a branch or
  publishing a tag under the current authorization boundary.
