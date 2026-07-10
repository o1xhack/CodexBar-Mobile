# v0.41.0 Upstream Sync + iOS 1.18.0 Overview

Status: `done`
Date: 2026-07-09
Completed: 2026-07-10
Branch: `upstream-sync/v0.41.0-mobile.1.18.0`
Issues:
- [#42](https://github.com/o1xhack/CodexBar-Mobile/issues/42) — upstream `v0.40.0`
- [#44](https://github.com/o1xhack/CodexBar-Mobile/issues/44) — upstream `v0.41.0`
- [#46](https://github.com/o1xhack/CodexBar-Mobile/issues/46) — consolidated `v0.40.0` + `v0.41.0`

## Branch Preflight

The worktree was clean. Local `mobile-dev` was 43 commits behind and was
fast-forwarded from `d52e5d87` to `8248714e`, matching `origin/mobile-dev`.
The required branch was then created before any research or implementation
file was written:

```text
git switch mobile-dev
git pull --ff-only origin mobile-dev
git switch -c upstream-sync/v0.41.0-mobile.1.18.0
git rev-parse HEAD
# 8248714e2ccd17014c43f29015589b658fa2bba8
git rev-parse origin/mobile-dev
# 8248714e2ccd17014c43f29015589b658fa2bba8
```

All work for this train stayed on that branch. The initial Goal did not
authorize a branch push, merge, live release, TestFlight upload, or published
tag. On 2026-07-10 the user explicitly authorized the branch push, release tag,
GitHub draft assets, and TestFlight upload. Merge and live Mac release remain
outside the authorization boundary.

## Authoritative Baseline

`version.env` on the refreshed `mobile-dev` is the alignment source of truth:

| Field | Baseline |
|---|---|
| `MARKETING_VERSION` | `0.39.0.1` |
| `BUILD_NUMBER` | `97.1` |
| `MOBILE_VERSION` | `1.17.0` |
| `UPSTREAM_VERSION` | `v0.39.0` |
| `UPSTREAM_SYNC_DATE` | `2026-07-04` |

All four iOS targets in `CodexBarMobile/project.yml` are `1.17.0 (185)`.
The latest published fork release is
`v0.39.0.1-mobile.1.17.0`, published `2026-07-07T00:14:39Z`.

## Upstream Facts

GitHub Releases for `steipete/CodexBar` are the upstream release source of
truth. The open issues overlap, so this train intentionally consolidates them
into one user-visible target:

| Release | Published UTC | Tag commit | Source |
|---|---:|---|---|
| `v0.40.0` | `2026-07-05T23:10:19Z` | `9d59a767239578b47b6ec0faf959150618572a7a` | `gh release view v0.40.0 --repo steipete/CodexBar` |
| `v0.41.0` | `2026-07-06T23:46:03Z` | `0c33e1141c64d0a056547444d2e74c4c61808cf4` | `gh release view v0.41.0 --repo steipete/CodexBar` |

The baseline upstream tag is
`29ca9403637298b862481a56e368e6c671446d6a` (`v0.39.0`). The range
`v0.39.0..v0.41.0` contains 59 non-merge commits and changes 235 files with
14,277 insertions and 1,303 deletions.

## Historical Upstream-sync Prior Art

The historical review covered closed issues
[#39](https://github.com/o1xhack/CodexBar-Mobile/issues/39) (`v0.38.0`),
[#40](https://github.com/o1xhack/CodexBar-Mobile/issues/40) (`v0.38.1`), and
[#41](https://github.com/o1xhack/CodexBar-Mobile/issues/41) (`v0.39.0`), plus
`Research/037-v039-upstream-sync/`. Those issues closed together when the fork
advanced to the current `v0.39.0` baseline. Carried-forward lessons for this
train are: consolidate overlapping release issues into one user-visible
version, branch before research or implementation, preserve both fork and raw
upstream changelog sections, bump both parser version/hash when parser inputs
move, audit opaque payload changes separately from CloudKit schema, and record
all 16 compatibility rows without presenting substituted evidence as hardware
QA.

## Release Scope

### v0.40.0

- Claude read-only `claude-swap` stacked accounts and account switching.
- Calendar-correct raw Codex Today/30-day credit totals.
- Unit-safe cost chart scale labels.
- Cursor Linux token/manual-cookie/XDG support.
- Devin optional extra-usage balance.
- Mistral Mac widget selection.
- Fixed Settings sizing, provider-scoped refresh, Claude history isolation,
  fresh-install provider detection, reset precision, and Mistral non-finite
  balance handling.
- Reduced Codex cost-history filesystem/CPU work.

### v0.41.0

- New responsive `codexbar cards` CLI and `--brief` output.
- Antigravity pace details.
- Kimi Weekly/Rate Limit/Monthly widget rows and Code 7-day quota.
- Claude `Max 5x` / `Max 20x` plan labels.
- Alibaba International Model Studio support.
- Browser Safe Storage prompt suppression after the first denial.
- Corrected Claude fractional utilization and year-boundary reset dates.
- Gemini consumer-tier migration guidance and Flash quota selection.
- Kimi/Kimi K2 parser, endpoint, ordering, timestamp, and non-finite fixes.
- Codex weekly-cap session availability and passive credit-error fixes.
- Unified positive sub-1% formatting as `<1%`.
- Tahoe blocked menu-bar recovery and macOS 27 Settings selector fixes.

## Target Version Plan

Upstream `v0.41.0` declares:

```text
MARKETING_VERSION=0.41.0
BUILD_NUMBER=100
```

Per `docs/versioning.md`, the one-train fork target is:

| Artifact | Target |
|---|---|
| Mac `MARKETING_VERSION` | `0.41.0.1` |
| Mac `BUILD_NUMBER` | `100.1` |
| iOS `MOBILE_VERSION` | `1.18.0` |
| iOS `CURRENT_PROJECT_VERSION` | `186` |
| Sparkle `sparkle:version` / app CFBundleVersion | `100.1.1.18.0` |
| Local/draft release tag name | `v0.41.0.1-mobile.1.18.0` |
| Work branch | `upstream-sync/v0.41.0-mobile.1.18.0` |

The upstream movement resets the fork patch to `.1`; iOS advances one feature
version because provider-visible behavior and formatting change. The iOS build
increments once from 185 to 186 for this release train.

## Mac Merge Surface and Risks

The upstream delta includes provider runtime, menu/UI, widget, CLI, cost-cache,
browser-cookie/Keychain safety, localization, tests, CI, release tooling,
`appcast.xml`, and `version.env`.

`git merge-tree --write-tree HEAD refs/upstream-tags/v0.41.0` forecasts content
conflicts in:

- `.github/workflows/ci.yml`
- `.github/workflows/upstream-monitor.yml`
- `CHANGELOG.md`
- `Scripts/sign-and-notarize.sh`
- `Sources/CodexBarCore/Generated/CodexParserHash.generated.swift`
- `Sources/CodexBarCore/Host/Process/SubprocessRunner.swift`
- `Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardBrowserCookieImporter+Deadline.swift`
- `WidgetExtension/CodexBarWidgetExtension.xcodeproj/project.pbxproj`
- `appcast.xml`
- `version.env`

Conflict policy is defined in `01-design.md`: retain the upstream functional,
security, performance, and test changes while preserving fork release,
CloudKit Production, composite version, Mobile pane, sync, and iOS behavior.

## iOS and Shared Impact

| Upstream item | Decision before merge |
|---|---|
| Kimi Monthly + Code 7-day quota | Already represented as additive `extraRateWindows` (`kimi-monthly`, `kimi-code-7d`). Existing `SyncCoordinator` serializes every named extra window into `ProviderUsageSnapshot.rateWindows`; iOS generic cards can render them. Add focused mapping/render tests; no new wire field expected. |
| Kimi Weekly / 5-hour ordering | Primary and secondary are already serialized in order, then extras. Verify resulting iOS order and mixed-version decode. |
| Claude Max 5x / 20x | Upstream writes the branded label into `ProviderIdentitySnapshot.loginMethod`; existing Shared payload already carries optional `loginMethod`. Verify iOS displays it and old clients tolerate the changed string. |
| Positive sub-1% formatting | iOS currently rounds a positive fraction to `0%`/`1%`. Update the shared mobile display helper to emit `<1%` for `0 < displayedPercent < 1`, with used/remaining tests and accessibility-safe output. |
| Devin extra-usage / Mistral widget selection | Mac widget/menu features. Existing provider data and iOS provider coverage remain; audit after merge for any structured value lost by the CloudKit mapper. |
| Antigravity pace | Mac menu/widget presentation. Existing rate windows sync; no new wire field unless pace is only available as a non-serializable display calculation. |
| Claude-swap switching | Mac credential/runtime and menu action; iOS remains read-only and must not attempt Mac-local account switching. Multi-account record emission is audited for identity compatibility. |
| CLI, Settings, Tahoe, Linux, browser-cookie, parser/cache fixes | Mac-only behavior, still required in the merge and Mac regression gates. |

No new upstream `UsageProvider` case appears in this range, so the provider
registry/mock/color count gate is an audit rather than an expansion.

## Compatibility and CloudKit Gates

The 16-combination gate applies because provider display data, Kimi rendering,
Claude plan rendering, and cross-version behavior change. All 16 cases will be
listed in `03-testing.md`; unavailable hardware combinations must use explicit
substituted evidence and retain a residual-risk note.

The preliminary CloudKit verdict is **no Production schema deploy expected**:
upstream does not modify `Shared/` or the fork CloudKit record schema, and the
planned iOS formatter/tests do not change payload shape. This is not final
until the post-implementation audit against the latest published fork tag is
recorded in `03-testing.md`.

## Authorization Boundary and Handoff

Initially authorized by this Goal:

- research, merge, implementation, tests, local commits, signed/notarized Mac
  artifacts, appcast/draft preparation, compatibility evidence, and review;
- local GitHub **draft** preparation without branch push or a published tag.

Explicitly authorized by the user on 2026-07-10 and completed:

- pushed `upstream-sync/v0.41.0-mobile.1.18.0` to `origin`;
- pushed annotated tag `v0.41.0.1-mobile.1.18.0`, targeting `81f43ecb`;
- created the GitHub draft release and uploaded the notarized ZIP and dSYM;
- archived and uploaded iOS `1.18.0 (186)` to TestFlight; ASC reports `VALID`.

Still not authorized without a later explicit instruction:

- live GitHub release;
- App Store submission;
- CloudKit Dashboard Production deploy;
- merge, force operations, or destructive Git.
