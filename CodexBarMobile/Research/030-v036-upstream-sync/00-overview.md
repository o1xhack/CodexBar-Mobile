# v0.36.1 Upstream Sync + iOS 1.13.0 Overview

Status: `done`
Date: 2026-06-16
Branch: `upstream-sync/v0.36.1-mobile.1.13.0`
Issue: [#28](https://github.com/o1xhack/CodexBar-Mobile/issues/28)

## Baseline

This branch was created from latest `origin/mobile-dev` commit `7b565366` before
implementation started. `version.env` is the upstream baseline source of truth:

| Field | Current `mobile-dev` value |
|---|---|
| `MARKETING_VERSION` | `0.35.0.1` |
| `BUILD_NUMBER` | `85.1` |
| `MOBILE_VERSION` | `1.12.0` |
| `UPSTREAM_VERSION` | `v0.35.0` |
| `UPSTREAM_SYNC_DATE` | `2026-06-14` |

GitHub Releases for `steipete/CodexBar` are authoritative for upstream facts.
On 2026-06-16 they show `v0.36.1` as latest:

| Upstream release | Published | Source |
|---|---:|---|
| `v0.36.0` | 2026-06-15 23:50:55 UTC | `gh release view v0.36.0 --repo steipete/CodexBar` |
| `v0.36.1` | 2026-06-16 05:07:28 UTC | `gh release view v0.36.1 --repo steipete/CodexBar` |

Open upstream-sync issue #28 covers both releases and is handled as one user
visible version. No split patch releases are planned.

## Closed Issue Pattern

Closed upstream-sync issues #22, #23, #24, and #26 were previously consolidated
into the shipped `v0.35.0.1-mobile.1.12.0` release. The reusable pattern is:

- compare `version.env` `UPSTREAM_VERSION` to upstream GitHub Releases;
- group all open release-tracking issues into one sync scope;
- assess iOS impact before implementation;
- preserve fork release, CloudKit, iOS sync, and versioning behavior;
- record versioning, CloudKit, compatibility matrix, testing, and review
  evidence in this Research folder.

## Target Version Plan

Per `docs/versioning.md` and the upstream `v0.36.1` `version.env` build number:

| Artifact | Target |
|---|---|
| Mac `MARKETING_VERSION` | `0.36.1.1` |
| Mac `BUILD_NUMBER` | `88.1` |
| iOS `MOBILE_VERSION` | `1.13.0` |
| iOS `CURRENT_PROJECT_VERSION` | `154` |
| Sparkle `sparkle:version` | `88.1.1.13.0` |
| Release tag | `v0.36.1.1-mobile.1.13.0` |
| Work branch | `upstream-sync/v0.36.1-mobile.1.13.0` |

`UPSTREAM_VERSION` should only become `v0.36.1` when this synchronized build is
actually shipped to users. During branch preparation, version fields can be
staged for the target release, but the shipped-baseline semantics must remain
explicit in release notes and final evidence.

## Upstream Diff Shape

`git diff --stat v0.35.0..v0.36.1` reports 416 files changed, 27,930 insertions,
and 4,570 deletions. Main buckets:

- New providers: LiteLLM, Poe, Chutes, and Zed.
- Provider display updates: Antigravity quota grouping and structured reset
  times, Copilot shared quota reset date, MiMo/OpenCode Go/Codebuff/Command
  Code optional enrichment behavior, and bounded provider refreshes.
- Mac menu and process reliability: provider switcher background fix, open menu
  in-place refresh, hosted submenu refresh timing, helper pipe draining,
  spawned process cleanup, Kiro/Gemini/DeepSeek/OpenRouter optional waits, and
  token-account scoped refreshes.
- Configuration and provider infrastructure: XDG config path support,
  explicit provider registry, shared API token fetch strategy, provider
  environment resolver, and cookie settings resolver.
- Localization and website: Mac app/site language catalog expands to 21
  languages, including Italian, Indonesian, Polish, Arabic, Persian, and Thai.
  iOS remains under this repo's mandatory four-language rule.
- Docs/assets/tests: provider docs and icons for LiteLLM/Poe/Chutes/Zed, sharded
  Swift test helpers, app/site locale audits, and focused provider tests.

## Related Upstream PRs

| PR | Release | iOS relevance |
|---|---|---|
| [#1542](https://github.com/steipete/CodexBar/pull/1542) LiteLLM provider | `v0.36.0` | Add provider identity/color/mock/render support if synced usage appears. Credential acquisition stays Mac-side. |
| [#1191](https://github.com/steipete/CodexBar/pull/1191) Poe provider | `v0.36.1` | Add provider identity/color/mock/render support for current balance and recent points history. |
| [#1496](https://github.com/steipete/CodexBar/pull/1496) Chutes provider | `v0.36.1` | Add provider identity/color/mock/render support for subscription/quota/pay-as-you-go windows. |
| [#1517](https://github.com/steipete/CodexBar/pull/1517) Zed provider | `v0.36.1` | Add provider identity/color/mock/render support for plan, edit-prediction quota, billing cycle, and overdue invoice state. Keychain session stays Mac-only. |
| [#1509](https://github.com/steipete/CodexBar/pull/1509) Antigravity quota summary | `v0.36.0` | iOS should render named Gemini / Claude + GPT session and weekly windows from synced payload. |
| [#1553](https://github.com/steipete/CodexBar/pull/1553) Antigravity resetTime | `v0.36.0` | iOS should preserve/render structured reset dates if present in synced `RateWindow.resetsAt`. |
| [#1562](https://github.com/steipete/CodexBar/pull/1562) XDG config path | `v0.36.0` | Mac-only config path resolution; no iOS runtime work. |
| [#1558](https://github.com/steipete/CodexBar/pull/1558) provider switcher background | `v0.36.1` | Mac menu UI only. |

## iOS Impact Summary

| Area | iOS action |
|---|---|
| LiteLLM | Add iOS provider catalog/color/mock coverage and verify budget rows render through existing usage/budget lanes. |
| Poe | Add iOS provider catalog/color/mock coverage and verify current balance/history text survives sync. |
| Chutes | Add iOS provider catalog/color/mock coverage and verify quota windows/subscription/pay-as-you-go rows render generically. |
| Zed | Add iOS provider catalog/color/mock coverage and verify plan/quota/billing-cycle rows render generically. |
| Antigravity quota/reset changes | Audit Shared payload and iOS render path for named windows and structured reset dates. |
| Copilot reset date | Confirm existing rate-window reset date path covers it; add tests if needed. |
| 21-language Mac catalog | Merge Mac resources. Do not expand iOS beyond English, Simplified Chinese, Traditional Chinese, and Japanese. |
| Mac menu/process/security fixes | Merge and regression-test Mac. iOS only changes if synced provider data or shared models are affected. |

## Release Boundaries

The original Goal authorized one-version sync, Mac/iOS implementation, local
packaging, notarization if credentials are available, CloudKit audit, and
review, but required confirmation before TestFlight upload, tag push, GitHub
draft release, live release, merge, or branch push.

Follow-up user confirmation on 2026-06-16 authorized:

- skipping the unshipped iOS 1.12 App Store release and uploading iOS 1.13.0
  directly;
- folding the unreleased iOS 1.12 notes into a productized iOS 1.13 in-app
  release-notes entry;
- creating a Mac GitHub Draft Release.

Still not authorized: live GitHub release publication, Sparkle appcast
finalization/push, TestFlight submission/release, branch merge, and branch push.

## Current Outcome

Research, branch setup, upstream merge, Mac/iOS implementation, sync audit,
CloudKit audit, test gates, and local Mac notarized artifacts are complete on
`upstream-sync/v0.36.1-mobile.1.13.0`.

`version.env` is staged for the target release:

| Field | Branch value |
|---|---|
| `MARKETING_VERSION` | `0.36.1.1` |
| `BUILD_NUMBER` | `88.1` |
| `MOBILE_VERSION` | `1.13.0` |
| `UPSTREAM_VERSION` | `v0.36.1` |
| `UPSTREAM_SYNC_DATE` | `2026-06-16` |

The user-facing iOS release train skips 1.12: App Store Connect still shows
`1.11.0` as the last ready-for-sale iOS version, while the 1.13 in-app notes now
include the unreleased 1.12 work plus the 1.13 provider/sync additions.

Mac draft release is complete, but live publication is not:

- Tag: `v0.36.1.1-mobile.1.13.0`
- Draft release: `https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-813eb73fe202a0b9c8ae`
- Assets:
  - `CodexBar-0.36.1.1-mobile.1.13.0.zip`
  - `CodexBar-0.36.1.1-mobile.1.13.0.dSYM.zip`
- `gh release view` confirms `isDraft=true`.

iOS upload is complete:

- Archive: `/tmp/CodexBarMobile-20260616-220825.xcarchive`
- Xcode export/upload result: `Upload succeeded`, `EXPORT SUCCEEDED`
- App Store Connect build status: `VALID`, build `154`, uploaded
  2026-06-16 22:10:55 PDT.

No live release, Sparkle appcast finalize/push, TestFlight submission/release,
branch merge, or branch push was performed.
