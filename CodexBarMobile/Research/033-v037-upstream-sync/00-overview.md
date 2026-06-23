# v0.37.2 Upstream Sync + iOS 1.15.0 Overview

Status: `in-progress`
Date: 2026-06-23
Branch: `upstream-sync/v0.37.2-mobile.1.15.0`
Release gate: code/test/review evidence is complete through the local merge
commit; Mac draft release is waiting for explicit authorization because the
repo phase1 script signs, notarizes, pushes the release tag, and creates a
GitHub draft release.
Issues:
- [#30](https://github.com/o1xhack/CodexBar-Mobile/issues/30) `v0.37.0`
- [#32](https://github.com/o1xhack/CodexBar-Mobile/issues/32) `v0.37.1`
- [#33](https://github.com/o1xhack/CodexBar-Mobile/issues/33) `v0.37.2`

## Baseline

This branch was created from latest `origin/mobile-dev` commit `ba4be051`
before implementation started. `version.env` is the upstream baseline source of
truth:

| Field | Current `mobile-dev` value |
|---|---|
| `MARKETING_VERSION` | `0.36.1.1` |
| `BUILD_NUMBER` | `88.1` |
| `MOBILE_VERSION` | `1.13.0` |
| `UPSTREAM_VERSION` | `v0.36.1` |
| `UPSTREAM_SYNC_DATE` | `2026-06-16` |

iOS `project.yml` is already on `1.14.0 (163)` for the Sync Device Management
work, and that release line is already under review. This upstream sync must
therefore target the next iOS release train, `1.15.0`, rather than adding more
scope to `1.14.0`. The last shipped Mac release in `version.env` still points at
`MOBILE_VERSION=1.13.0`.

## Upstream Facts

GitHub Releases for `steipete/CodexBar` are authoritative for upstream facts.
On 2026-06-23 they show `v0.37.2` as latest:

| Upstream release | Published UTC | Commit | Source |
|---|---:|---|---|
| `v0.37.0` | 2026-06-20 02:07:44 | `33a5f436` | `gh release view v0.37.0 --repo steipete/CodexBar` |
| `v0.37.1` | 2026-06-21 23:16:27 | `244b31e8` | `gh release view v0.37.1 --repo steipete/CodexBar` |
| `v0.37.2` | 2026-06-22 09:42:05 | `f3802870` | `gh release view v0.37.2 --repo steipete/CodexBar` |

Open upstream-sync issues #30, #32, and #33 are handled as one user-visible
version. No split patch releases are planned.

## Closed Issue Pattern

Recent closed upstream-sync issues establish the reusable pattern:

- #28 (`v0.36.0` + `v0.36.1`) was consolidated into one release train;
- the Research folder records upstream scope, iOS impact, versioning, CloudKit
  audit, compatibility matrix, testing evidence, and review evidence;
- fork-owned release tooling, CloudKit Production behavior, iOS sync contracts,
  and versioning semantics take priority during upstream merge conflicts;
- GitHub draft release is allowed only when requested, while live release,
  appcast finalization, branch push/merge, and TestFlight release require
  explicit confirmation.

## Target Version Plan

Per `docs/versioning.md` and upstream `v0.37.2` `version.env`:

| Artifact | Target |
|---|---|
| Mac `MARKETING_VERSION` | `0.37.2.1` |
| Mac `BUILD_NUMBER` | `92.1` |
| iOS `MOBILE_VERSION` | `1.15.0` |
| iOS `CURRENT_PROJECT_VERSION` | `164` unless a later build bump is required by final commit policy |
| Sparkle `sparkle:version` | `92.1.1.15.0` |
| Release tag | `v0.37.2.1-mobile.1.15.0` |
| Work branch | `upstream-sync/v0.37.2-mobile.1.15.0` |

Rationale:

- upstream `v0.37.2` has `BUILD_NUMBER=92`;
- fork edits are required for release tooling, iOS bridge/docs, and packaging,
  so the fork build becomes `92.1`;
- Mac marketing version follows the four-segment fork rule and resets the fork
  patch counter on upstream movement: `0.37.2.1`;
- iOS `1.14.0` is already in review, so this release uses the next user-facing
  mobile train, `1.15.0`, for any new iOS support and release notes.

## Upstream Diff Shape

`git diff --stat v0.36.1^{}..v0.37.2^{}` reports 365 files changed, 21,474
insertions, and 2,455 deletions. Main buckets:

- Mac widgets: single-window and combined burn-down charts for Codex and Claude
  session/weekly windows.
- Provider data: Bedrock CloudWatch 14-day activity, Codex profile-home
  accounts, Codex reset credits, Cursor personal on-demand spend, Mistral Vibe
  monthly-plan usage, LiteLLM budget row refinements, Antigravity quota-label
  fallback fixes, MiniMax detailed token-plan recovery, Claude CLI/web
  reliability, Kiro/MiMo/OpenCode Go/Command Code fixes.
- Security: endpoint override hardening for Deepgram, z.ai, Xiaomi MiMo, and
  Azure OpenAI; Codex OAuth `auth.json` permissions are tightened.
- Diagnostics and CLI: redacted provider diagnose output files; `/health`
  reports startup build version; provider quota fixture contract coverage.
- Menu/performance: menu refresh remains open with in-place progress, provider
  spacing alignment, memory-pressure cache trimming, cost-history parser
  caching, storage segmented breakdown, and package size reduction.
- Packaging/CI/lint: static Linux musl artifacts upstream, lint path changes,
  app locale checker improvements, package stripping tests.
- Mac app resources and docs: 21-language catalog updates, website docs, and a
  new upstream read-only `codexbar` agent skill.

## iOS Impact Summary

| Area | iOS action |
|---|---|
| Bedrock CloudWatch activity | Audit whether existing `SyncBedrockCost`, generic `costSummary`, and rate-window rows cover the new 14-day activity totals; add a bridge only if the Mac snapshot has user-visible values not serialized today. |
| Codex profile-home accounts | Preserve multi-account identity in Mac sync. Confirm profile-home account identities produce stable `accountIdentities`/account rows on iOS without copying credentials. |
| Codex reset credits | Audit whether reset credit counts/expiry are generic rows or Mac-only menu rows. If user-visible and not synced, add an optional shared payload and iOS display. |
| Cursor personal on-demand spend | Existing iOS Cursor Extra budget gauge may already cover synced budget rows; verify mapper and detail rendering after merge. |
| Mistral Vibe monthly plan | Existing Mistral daily cost and renewal UI may need monthly-plan usage rows; prefer generic rate-window/budget serialization before dedicated UI. |
| Provider usage confidence | Upstream adds provider-neutral confidence metadata. Decide whether it is user-visible enough for iOS or remains diagnostic-only. |
| Diagnostics output files and CLI `/health` | Mac/CLI-only. No iOS UI unless sync payload uses app/build version differently. |
| Security hardening | Mac-only runtime/security fixes must be merged. iOS only needs compatibility tests to ensure no sync regression. |
| Widget and menu UI | Mac-only. iOS does not need widget extension parity for this sync. |

## Release Boundaries

The Goal authorizes the one-version sync, research/design docs, implementation,
Mac draft release preparation, Mac/iOS test gates, CloudKit audit, compatibility
matrix evidence, and review loop on this branch.

Still not authorized without a new explicit user confirmation:

- live GitHub release publication;
- Sparkle appcast finalization/push;
- TestFlight upload or App Store submission;
- CloudKit Dashboard Production schema deploy;
- tag publication beyond draft-release tooling needs;
- branch merge or push.

## Current Outcome Snapshot

- Branch correction applied: this work targets `1.15.0`, because `1.14.0` is
  already in review.
- Upstream `v0.37.0`, `v0.37.1`, and `v0.37.2` are handled as one release
  train ending at upstream commit `f3802870`.
- Local branch HEAD is a merge commit from `origin/mobile-dev` `ba4be051` and
  upstream `v0.37.2` `f3802870`; the worktree is clean for release phase1
  preflight once authorization is granted.
- Mac version fields are staged as `0.37.2.1`, `92.1`,
  `MOBILE_VERSION=1.15.0`, `UPSTREAM_VERSION=v0.37.2`, and
  `UPSTREAM_SYNC_DATE=2026-06-22`.
- iOS version fields are staged as `1.15.0 (164)`.
- Shared/iOS bridge work adds only optional compressed-payload keys for Codex
  reset credits and provider usage confidence; no required wire field is
  introduced.
- CloudKit incremental audit against `origin/mobile-dev` found no new record
  type, field, zone, subscription, index, `providerPayloadVersion`, or
  `encodingVersion` change for this upstream-sync round.
- Full Mac sharded tests, lint, focused multi-account/sync tests, iOS simulator
  build, iOS simulator tests, and iOS localization audit passed.
- `./Scripts/release.sh` phase1 was not run because it requires release
  credentials and performs `git push -f origin <tag>` before creating a draft
  GitHub release.
