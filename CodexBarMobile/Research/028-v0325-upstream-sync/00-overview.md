# v0.32.5 Upstream Sync + iOS 1.12.0 Overview

Status: `in-progress`
Date: 2026-06-10
Branch: `upstream-sync/v0.32.5-mobile.1.12.0`
Issue: [#22](https://github.com/o1xhack/CodexBar-Mobile/issues/22)
Upstream release: [steipete/CodexBar v0.32.5](https://github.com/steipete/CodexBar/releases/tag/v0.32.5)

## Baseline

`version.env` is the source of truth for the shipped upstream baseline:

| Field | Current value |
|---|---|
| `MARKETING_VERSION` | `0.32.4.1` |
| `BUILD_NUMBER` | `79.1` |
| `MOBILE_VERSION` | `1.11.1` |
| `UPSTREAM_VERSION` | `v0.32.4` |
| `UPSTREAM_SYNC_DATE` | `2026-06-06` |

The only open upstream-sync issue is #22. It covers one upstream release:

| Release | Published | Notes source |
|---|---:|---|
| `v0.32.5` | 2026-06-09 07:30:36 UTC | `gh release view v0.32.5 --repo steipete/CodexBar` |

Closed upstream-sync issues (#15-#20) show the expected issue format: release notes grouped by upstream tag, iOS impact table, then a concrete sync checklist. #22 now matches that pattern after the upstream monitor fix in Research/027.

## #22 Comment Triage

#22 contains one external comment from `ColumbusLabs` claiming upstream tracking moved to `ColumbusLabs/QuotaKit`. That account is not a collaborator on this repo, and the comment references a different project. Treat it as an unrelated cross-repo automation/comment mistake. It is not evidence for this sync.

## Target Version Plan

Per `docs/versioning.md`:

| Artifact | Target |
|---|---|
| Mac `MARKETING_VERSION` | `0.32.5.1` |
| Mac `BUILD_NUMBER` | `80.1` |
| iOS `MOBILE_VERSION` | `1.12.0` |
| iOS `CURRENT_PROJECT_VERSION` | `152` |
| Sparkle `sparkle:version` | `80.1.1.12.0` |
| Branch | `upstream-sync/v0.32.5-mobile.1.12.0` |

`UPSTREAM_VERSION` and `UPSTREAM_SYNC_DATE` should remain at the shipped baseline until the synced build is actually live to users. The draft-release branch can update `MARKETING_VERSION`, `BUILD_NUMBER`, and `MOBILE_VERSION` for packaging evidence, but live-baseline fields should only move after release completion.

## Upstream Scope

`git diff --stat v0.32.4..v0.32.5` reports 137 changed files, 17,026 insertions, and 822 deletions. Main buckets:

- Mac localization: new French, Ukrainian, Dutch, and Vietnamese `.lproj` resources.
- Menu bar stability and performance: provider switching, merged-menu close/open rebuilds, readiness signatures, hosted chart sizing, icon observation, switcher quota bar constraints, Quit deferral.
- Codex account refresh correctness: auth fingerprint isolation, visible-account reset/window backfill, managed login timeout, stale auth result rejection.
- Provider display fixes: Cursor billing-cycle deficit/run-out pace, Codex Spark pace detail, Claude selected metric reserve, Antigravity CLI quota detection and most-constrained summary.
- MiniMax token plan work: token-plan quotas, metadata host fallback, unlimited rows, subscription metadata, points balance via `providerCost`.
- Pricing performance: memoized models.dev catalog load outcomes and updated `CodexParserHash`.
- Tests: new and expanded coverage across menu performance, Codex account state, MiniMax, localization, Antigravity, Cursor, and shutdown.

## iOS Impact Summary

| Area | iOS action |
|---|---|
| Mac menu/AppKit performance fixes | Merge and regression-test Mac. No direct iOS UI change. |
| Mac localization languages | Merge Mac resources. iOS remains on the project-mandated 4-language rule: English, Simplified Chinese, Traditional Chinese, Japanese. Do not expand iOS languages in this release. |
| MiniMax points balance | Should flow through existing `providerCost -> SyncBudgetSnapshot -> budget` lane. Verify after merge. |
| MiniMax subscription dates | New upstream `UsageSnapshot.subscriptionExpiresAt` / `subscriptionRenewsAt` do not exist on the Shared payload. Add optional generic fields to `ProviderUsageSnapshot`, map them in `SyncCoordinator`, retain them during iOS merge/cache, and render them on iOS. |
| Codex reset/window backfill | Existing `SyncRateWindow` carries reset timestamp/window metadata. Verify Codex and Codex Spark windows still render correctly. |
| Cursor/Codex Spark/Claude pace detail | Mac-only menu detail today; iOS does not have a generic pace-detail wire lane. Verify no regression and record as not yet wire-exposed unless a needed field appears during merge. |
| Antigravity summary | Existing rate windows should carry the corrected upstream selected summary. Verify Antigravity mock/sample data and no iOS-specific schema needed. |
| models.dev memoization | Mac performance change. Verify parser hash and run relevant cost tests; no iOS payload change expected. |

## Release Gate

This sync touches Mac provider snapshots and adds a Shared payload field, so `docs/ios-sync-compatibility-testing.md` is triggered. Testing must record the 2 Mac x 2 iPhone old/new compatibility matrix in `03-testing.md`.

CloudKit deploy expectation: no Production schema deploy for additive JSON fields inside the existing compressed payload, unless the merge introduces new CloudKit record types, top-level CK fields, indexes, zones, or subscriptions.

## Current Outcome

Implemented on branch `upstream-sync/v0.32.5-mobile.1.12.0`:

- Upstream `v0.32.5` Mac code, resources, docs, and tests are merged with fork
  release/appcast/versioning constraints preserved.
- Mac sync now forwards upstream `UsageSnapshot.subscriptionExpiresAt` and
  `subscriptionRenewsAt` into the shared provider payload.
- iOS `1.12.0 (152)` decodes, merges, persists, and renders those subscription
  dates with required 4-language localization.
- iOS old/new multi-Mac merge behavior now preserves rich optional provider
  fields with `latestNonNil`, preventing old Mac payloads from erasing new
  payload details.
- CloudKit Production schema audit found no deploy requirement.
- Local build, lint, parser hash, focused Mac tests, iOS simulator build, and
  focused iOS tests pass; details are in `03-testing.md`.

Remaining release boundary:

- Signed/notarized Mac draft release packaging has not been run yet because it
  requires explicit confirmation for release credentials / remote draft-release
  actions under this Goal.
