# v0.35.0 Upstream Sync + iOS 1.12.0 Overview

Status: `done`
Date: 2026-06-14
Branch: `upstream-sync/v0.35.0-mobile.1.12.0`
Issues: [#22](https://github.com/o1xhack/CodexBar-Mobile/issues/22),
[#23](https://github.com/o1xhack/CodexBar-Mobile/issues/23),
[#24](https://github.com/o1xhack/CodexBar-Mobile/issues/24),
[#26](https://github.com/o1xhack/CodexBar-Mobile/issues/26)

## Baseline

This branch was created from latest `mobile-dev` commit `848c37c8`.
`version.env` is the source of truth for the shipped upstream baseline:

| Field | Current `mobile-dev` value |
|---|---|
| `MARKETING_VERSION` | `0.32.4.1` |
| `BUILD_NUMBER` | `79.1` |
| `MOBILE_VERSION` | `1.11.1` |
| `UPSTREAM_VERSION` | `v0.32.4` |
| `UPSTREAM_SYNC_DATE` | `2026-06-06` |

Although `v0.32.5.1-mobile.1.12.0` was published from the previous sync branch,
that code was not merged back to `mobile-dev`. The current open issue set is
therefore treated as one release range from `v0.32.5` through `v0.35.0`.

## Open Upstream-Sync Scope

| Issue | Upstream release | Published | Source of truth |
|---|---|---:|---|
| #22 | `v0.32.5` | 2026-06-09 07:30:36 UTC | `gh release view v0.32.5 --repo steipete/CodexBar` |
| #23 | `v0.33.0` | 2026-06-11 05:35:14 UTC | `gh release view v0.33.0 --repo steipete/CodexBar` |
| #24 | `v0.34.0` | 2026-06-12 16:06:25 UTC | `gh release view v0.34.0 --repo steipete/CodexBar` |
| #26 | `v0.35.0` | 2026-06-14 01:41:46 UTC | `gh release view v0.35.0 --repo steipete/CodexBar` |

Closed upstream-sync issues (#15-#20) establish the expected pattern: group
release notes by upstream tag, assess iOS impact, then complete one concrete
sync checklist. This release follows that pattern and does not split the open
issues into multiple user-visible versions.

Issue #22 still contains an unrelated external `ColumbusLabs` comment about
`QuotaKit`; it remains non-actionable for this repo.

## Target Version Plan

Per `docs/versioning.md` and the prior `1.12.0 (152)` TestFlight upload from
the superseded v0.32.5 branch:

| Artifact | Target |
|---|---|
| Mac `MARKETING_VERSION` | `0.35.0.1` |
| Mac `BUILD_NUMBER` | `85.1` |
| iOS `MOBILE_VERSION` | `1.12.0` |
| iOS `CURRENT_PROJECT_VERSION` | `153` |
| Sparkle `sparkle:version` | `85.1.1.12.0` |
| Release tag | `v0.35.0.1-mobile.1.12.0` |
| Branch | `upstream-sync/v0.35.0-mobile.1.12.0` |

`UPSTREAM_VERSION` and `UPSTREAM_SYNC_DATE` remain the shipped baseline until
the synced build is live to users. Draft-release branch work may stamp
`MARKETING_VERSION`, `BUILD_NUMBER`, and `MOBILE_VERSION`; the shipped-baseline
fields move only when the full release is closed.

## Upstream Diff Shape

`git diff --stat v0.32.4..v0.35.0` reports 424 files changed, 54,087
insertions, and 2,742 deletions. Main buckets:

- Mac menu bar stability and performance: merged-menu tracking, status item
  appearance, shortcut handling, provider switching, hosted menu recycling,
  geometry stability, and main-thread hang detection.
- Provider data and display changes: Amp local usage, Devin daily/weekly quota,
  Copilot billing budgets, Kimi Code API usage, Xiaomi MiMo balance components
  and session-log fallback, Cursor legacy/team/storage projections,
  Antigravity CLI fallback and summaries, OpenAI Admin pagination, Claude Fable
  pricing, Codex degraded/local-cost visibility, Doubao zero-limit handling,
  Grok billing recovery, and MiniMax subscription metadata.
- Cost pipeline: serial cost scan executor, models.dev churn fallback,
  Codex priority-turn memoization, Claude Fable pricing, and parser hash churn.
- Mac localization: French, Ukrainian, Dutch, Vietnamese, Japanese, Korean,
  German, and Turkish resources added upstream. iOS remains on this project's
  mandatory 4-language rule: English, Simplified Chinese, Traditional Chinese,
  Japanese.
- Release tooling: package/sign/notarize path helpers, dSYM path helpers,
  Sparkle signing helpers, and related tests.
- Security and diagnostics: credential redirect validation, endpoint override
  validation, cookie/keychain access gates for test/infrastructure paths,
  provider timeout isolation, and browser-cookie import hardening.

## iOS Impact Summary

| Area | iOS action |
|---|---|
| v0.32.5 MiniMax subscription dates | Reapply the prior branch bridge: optional `subscriptionExpiresAt` / `subscriptionRenewsAt` on `ProviderUsageSnapshot`, Mac sync mapping, iOS merge/cache preservation, and iOS rendering. |
| v0.34 Devin provider | Add iOS provider identity support, card/color/mock coverage as needed, and verify daily/weekly quota windows render through existing generic lanes. |
| v0.34 Amp provider | Add iOS provider identity support and verify account/workspace credit balances render or are explicitly unsupported. |
| v0.34 Copilot budgets | Audit `CopilotUsageModels` and synced payloads; add generic optional budget fields only if Mac data is not already represented by existing budget/rate-window lanes. |
| v0.35 Kimi Code API | Existing Kimi card should receive usage via existing provider lanes; verify no new iOS network/proxy behavior is needed. |
| v0.35 Xiaomi MiMo balance components | Audit whether paid/granted components flow through current budget/provider-cost lanes; add optional Shared fields only if needed for user-visible composition. |
| Weekly pace work days | Mac computes pace; iOS should render synced values consistently. Audit whether iOS recomputes weekly pace anywhere. |
| Cost/parser changes | Regenerate parser hash and bump parser logic version if upstream changed parser/pricing semantics since current baseline. |
| Mac localizations | Merge Mac resources. Do not expand iOS beyond the required 4 languages unless project rules change. |
| Menu bar/AppKit/security/tooling fixes | Merge and regression-test Mac. iOS impact only when synced payload or shared model fields change. |

## Release Gates

This sync changes provider display data and is expected to update Shared payloads
for at least the v0.32.5 MiniMax metadata. Therefore
`docs/ios-sync-compatibility-testing.md` applies and `03-testing.md` must list
all 16 old/new combinations.

CloudKit deploy expectation is unknown until after merge audit. Additive keys
inside the existing compressed payload do not require deploy; new CloudKit
record types, top-level fields, indexes, zones, or subscriptions do.

## Upstream Check During Implementation

On 2026-06-14, `steipete/CodexBar` GitHub Releases still reported `v0.35.0`
as latest. `upstream/main` had already moved to unreleased app version
`0.35.1` / build `86` at commit `ae7455bad6e2e2a71de4bd46b7ae3816053efed1`,
23 commits ahead of `v0.35.0`. The target remains `v0.35.0` because this Goal
uses GitHub Releases as the upstream source of truth.

One unreleased upstream stability fix, `ae7455ba fix: keep token account menu
data scoped (#1530)`, was selectively backported after the v0.35.0 test suite
exposed the same token-account switcher race. This is not a target-version
change and does not pull the branch to unreleased `0.35.1`.

## Current Outcome

Started on branch `upstream-sync/v0.35.0-mobile.1.12.0` from latest
`mobile-dev`. The branch was fast-forwarded into `mobile-dev` and released as
`v0.35.0.1-mobile.1.12.0`.

Release outcome:

- GitHub release:
  <https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.35.0.1-mobile.1.12.0>
- Sparkle appcast:
  <https://raw.githubusercontent.com/o1xhack/CodexBar-Mobile/mobile-dev/appcast.xml>
- `version.env` shipped upstream baseline updated to `UPSTREAM_VERSION=v0.35.0`
  and `UPSTREAM_SYNC_DATE=2026-06-14`.
- The notarized production Mac app was installed at `/Applications/CodexBar.app`
  and launched locally as `0.35.0.1` / `85.1.1.12.0`.

The release contains the v0.35.0 Mac sync, iOS 1.12.0 Shared/presentation
updates for MiniMax subscription metadata, Devin iOS provider identity coverage,
release notes, localization, CloudKit audit, Mac/iOS test evidence, the 16-case
sync compatibility substitution matrix, and review fixes for SwiftData
rich-payload hydration plus Mac MiniMax localization.
