# v0.39.0 Upstream Sync + iOS 1.17.0 Overview

Status: `in-progress`
Date: 2026-07-04
Branch: `upstream-sync/v0.39.0-mobile.1.17.0`
Issue:
- [#37](https://github.com/o1xhack/CodexBar-Mobile/issues/37) `v0.38.0` + `v0.38.1` + `v0.39.0`

## Branch Preflight

This branch was created from latest `mobile-dev` after:

```text
git fetch origin --prune --tags
git switch mobile-dev
git pull --ff-only origin mobile-dev
git switch -c upstream-sync/v0.39.0-mobile.1.17.0
```

The worktree was clean before branch creation:

```text
## mobile-dev...origin/mobile-dev
```

`git fetch upstream --prune --tags` fetched new upstream refs and the new
`v0.38.0`, `v0.38.1`, and `v0.39.0` tags, but exited non-zero because older
local tags would be clobbered. The relevant target tags were verified with
`git ls-remote --tags upstream` and local `git rev-parse`; all four target refs
match:

| Tag | Commit |
|---|---|
| `v0.37.2` | `05b42e7ef95850191c12e64014aa17eeddc8849e` |
| `v0.38.0` | `2b245a4e75946c3f365c7440cbcc1eb246141cb` |
| `v0.38.1` | `3edc623cddf6cb9ea68863167f8c87e2b69545ce` |
| `v0.39.0` | `29ca9403637298b862481a56e368e6c671446d6a` |

## Baseline

`version.env` is the authoritative upstream alignment baseline:

| Field | Current `mobile-dev` value |
|---|---|
| `MARKETING_VERSION` | `0.37.2.1` |
| `BUILD_NUMBER` | `92.1` |
| `MOBILE_VERSION` | `1.16.0` |
| `UPSTREAM_VERSION` | `v0.37.2` |
| `UPSTREAM_SYNC_DATE` | `2026-06-22` |

iOS `CodexBarMobile/project.yml` is currently `1.16.0 (180)` for all targets.
This upstream sync carries new Mac provider data and display behavior, so the
mobile target for this branch is the next feature train, `1.17.0`.

The latest published fork release is:

| Release | Published UTC |
|---|---:|
| `v0.37.2.1-mobile.1.15.0` | `2026-06-24T20:57:30Z` |

## Upstream Facts

GitHub Releases for `steipete/CodexBar` are the upstream source of truth. On
2026-07-04 they show `v0.39.0` as the latest official release:

| Upstream release | Published UTC | Source |
|---|---:|---|
| `v0.38.0` | `2026-07-03T11:18:17Z` | `gh release view v0.38.0 --repo steipete/CodexBar` |
| `v0.38.1` | `2026-07-04T09:21:15Z` | `gh release view v0.38.1 --repo steipete/CodexBar` |
| `v0.39.0` | `2026-07-04T20:01:15Z` | `gh release view v0.39.0 --repo steipete/CodexBar` |

Open issue #37 explicitly consolidates the pending upstream releases into one
sync train. No split user-visible fork versions are planned for this goal.

## Release Note Scope

### v0.38.0

Major upstream additions include:

- new providers and data lanes: Doubao Coding Plan, CrossModel, Qoder, Sakana
  AI, z.ai token-account team usage, status submenus, Codex/Claude combined
  session + weekly metric, and CLI session pace;
- Settings redesign to a System Settings-style sidebar window;
- menu grouping for Plan Usage, Cost, and Storage rows;
- many provider fixes around refresh timing, reset boundaries, Keychain prompt
  safety, parser reliability, cost history, localization, and menu rendering.

### v0.38.1

Major upstream additions include:

- Russian and Galician localization;
- ClawRouter API-key usage tracking;
- Claude model-scoped weekly quota windows;
- Adaptive refresh cadence;
- Codex 1.5x pace-headroom hint;
- branding and website redesign;
- architecture decisions for custom HTTP JSON providers, predictive warnings,
  Claude read-only multi-account display, and OpenCode Go multi-workspace fanout;
- fixes for Gemini helpers, monthly quota pace, z.ai parsing, Claude MCP-only
  background refresh, and non-finite OpenAI/OpenCode values.

### v0.39.0

Major upstream additions include:

- Codex reset-credit expiry inventory and compact timeline;
- 7/30/90-day cost comparison windows;
- Codex local cost grouping by project/worktree;
- Sakana pay-as-you-go balance and recent usage;
- Kimi monthly subscription usage;
- Mistral billing-session credit balance;
- repository size/build artifact guards;
- more Keychain no-prompt protections and tests.

## Target Version Plan

Per `docs/versioning.md`, upstream `v0.39.0` has:

```text
MARKETING_VERSION=0.39.0
BUILD_NUMBER=97
```

The fork target is:

| Artifact | Target |
|---|---|
| Mac `MARKETING_VERSION` | `0.39.0.1` |
| Mac `BUILD_NUMBER` | `97.1` |
| iOS `MOBILE_VERSION` | `1.17.0` |
| iOS `CURRENT_PROJECT_VERSION` | `181` unless final upload policy requires a later build |
| Sparkle `sparkle:version` | `97.1.1.17.0` |
| Release tag | `v0.39.0.1-mobile.1.17.0` |
| Work branch | `upstream-sync/v0.39.0-mobile.1.17.0` |

Rationale:

- the first three Mac marketing segments copy upstream `v0.39.0`;
- upstream movement resets the fork patch segment to `.1`;
- `BUILD_NUMBER` uses upstream integer `97` plus fork subdecimal `.1`;
- iOS receives feature-level upstream provider/display parity work, so
  `MOBILE_VERSION` advances from `1.16.0` to `1.17.0`.

## Upstream Diff Shape

`git diff --stat v0.37.2..v0.39.0` reports 579 files changed, 50,002
insertions, and 6,401 deletions.

Important buckets:

- Provider additions: `sakana`, `qoder`, `crossmodel`, and `clawrouter` are new
  `UsageProvider` / `IconStyle` cases upstream.
- Provider data changes: Claude model-scoped weekly windows, Kimi monthly
  usage, Mistral billing credit balance, Sakana pay-as-you-go, Qoder credit
  usage, CrossModel wallet spend, Doubao monthly pace, and Codex reset-credit
  expiry inventory.
- Shared-ish Mac data models: upstream changed `UsageFetcher.swift`,
  `CostUsageModels.swift`, `CreditsModels.swift`, `WidgetSnapshot.swift`, and
  `UsageStore+WidgetSnapshot.swift`. It did not directly modify `Shared/` or
  `CodexBarMobile/` in the upstream tag range.
- Parser/cache: `Sources/CodexBarCore/Vendored/CostUsage/*` and
  `CodexParserHash.generated.swift` changed, so the parser logic/hash gate is
  in scope.
- Security and no-prompt safety: Alibaba, Claude, OpenCode, browser discovery,
  tests, and Keychain access paths changed and must be preserved.
- Release/tooling: appcast, packaging, repository size checks, CI, lint, website
  assets, localization, and release scripts changed. Fork release tooling must
  retain `o1xhack/CodexBar-Mobile`, Sparkle composite versions, and local
  signing/notarization rules.

## iOS Impact Summary

| Area | iOS action |
|---|---|
| New providers `sakana`, `qoder`, `crossmodel`, `clawrouter` | Add to iOS provider list, mock inventory, color palette, release notes, and tests. Prefer generic cards when upstream exposes `rateWindows`, `budget`, or `costSummary`; add dedicated optional payloads only when generic rendering loses primary user value. |
| Claude model-scoped weekly windows | Existing `extraRateWindows` mapping should render them generically. Verify labels, sorting, and old/new decode; add tests if the model windows expose `usageKnown=false` or nonstandard cadences. |
| Kimi monthly subscription usage | Audit upstream `KimiUsageSnapshot.toUsageSnapshot()` after merge. If represented as generic rate/budget rows, no new wire field is needed; otherwise add an optional Kimi payload. |
| Mistral billing credit balance | Existing `mistralUsage` -> `SyncCostSummary` covers daily spend but may not show available credit balance. Audit after merge for `providerCost`/budget representation before deciding on a new optional field. |
| Sakana pay-as-you-go balance/recent usage | New provider. Audit whether pay-as-you-go balance maps to `ProviderCostSnapshot`, `budget`, or `costSummary`; add dedicated payload only if necessary. |
| Codex reset-credit expiry inventory | Existing iOS 1.15 bridge has `codexResetCredits` count/next expiry. v0.39.0 adds full expiry inventory and compact timeline; audit whether current `SyncCodexResetCredits.credits` already carries enough detail for iOS or needs UI copy changes. |
| Codex project/worktree cost rollups | Existing `SyncCostSummary` has daily/model/service breakdowns but no project/worktree dimension. Audit upstream cost model. If project/worktree is user-visible and not serializable today, add optional bounded payload or document Mac-only scope. |
| Widget snapshot `usageBarsShowUsed` | Mac widget payload changed. iOS WidgetKit uses CloudKit synced snapshots, not Mac App Group widget snapshots, but parser/tests must cover additive `WidgetSnapshot` decode if shared tests touch it. |
| Adaptive refresh, Settings redesign, website, branding | Mac-only. Preserve upstream implementation, no iOS UI needed except release notes when user-visible via sync compatibility. |
| Keychain no-prompt safety and test hardening | Mac-only runtime/security. Must be merged and validated without running live Keychain-prompting probes. |

## Release Boundaries

The active goal authorizes research/design, implementation, tests, Mac draft
release preparation, CloudKit audit, sync compatibility matrix documentation,
and review loop on this branch.

Still not authorized without explicit confirmation:

- live GitHub release publication;
- Sparkle appcast finalize/push to `mobile-dev`;
- TestFlight upload or App Store submission;
- CloudKit Dashboard Production schema deploy;
- branch push, merge, or tag publication beyond draft-release tooling needs;
- destructive git operations.

## Current Outcome Snapshot

- Branch is correctly isolated on `upstream-sync/v0.39.0-mobile.1.17.0`.
- Target upstream release is `v0.39.0`; range is `v0.38.0`, `v0.38.1`, and
  `v0.39.0` together.
- Target fork versions are `0.39.0.1`, `97.1`, iOS `1.17.0`, Sparkle
  `97.1.1.17.0`.
- Upstream `v0.39.0` is merged and fork conflict resolutions preserve Mobile,
  CloudKit Production, release tooling, and the Settings Mobile pane.
- iOS provider parity is implemented for Sakana AI, Qoder, CrossModel, and
  ClawRouter. CrossModel receives the only new typed optional Shared payload in
  this release.
- Version files, iOS/root changelogs, in-app release notes, localization, mock
  data, provider list, provider colors, parser cache invalidation, and focused
  tests are updated.
- CloudKit audit shows no Production schema deploy is required because the only
  Shared model addition is an optional field inside the existing compressed
  provider payload.
- Focused Mac gates and the full iOS simulator scheme pass. Full Mac
  `swift test` still has timing-sensitive residual failures outside the
  upstream-sync surface; see `03-testing.md`.
- Local Mac artifacts were built, signed, notarized, stapled, launch-verified,
  zipped, and dSYM-packaged with `Scripts/sign-and-notarize.sh`.
- Mac GitHub draft release has not been run because `Scripts/release.sh`
  phase 1 publishes the release tag to `origin` and creates a remote draft
  release.
