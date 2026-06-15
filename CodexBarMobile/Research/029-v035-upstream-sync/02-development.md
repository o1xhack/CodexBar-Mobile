# v0.35.0 Upstream Sync Development Log

Status: `done`
Date: 2026-06-14
Branch: `upstream-sync/v0.35.0-mobile.1.12.0`

## Round 0 — Research and Branch Setup

Evidence:

```text
git status --short --branch
Result: upstream-sync/v0.32.5-mobile.1.12.0 with two Research docs dirty.

git commit -m "docs: record v0.32.5 release evidence"
Result: f5f710f4, local only, preserves prior release evidence.

git switch -c upstream-sync/v0.35.0-mobile.1.12.0 origin/mobile-dev
Result: branch created from 848c37c8 docs: update appcast for 0.32.5.1.
```

Rules and source material read:

- `AGENTS.md`
- `docs/versioning.md`
- `docs/ios-sync-compatibility-testing.md`
- `docs/cloudkit-deploy-audit.md`
- `docs/RELEASE-CHECKLIST.md`
- open upstream-sync issues #22/#23/#24/#26
- closed upstream-sync issue format (#15-#20)
- upstream GitHub Releases `v0.32.5`, `v0.33.0`, `v0.34.0`, `v0.35.0`
- `git diff --stat v0.32.4..v0.35.0`

Initial decisions:

- Target upstream: `v0.35.0`.
- Target Mac: `0.35.0.1`, build `85.1`.
- Target iOS: `1.12.0 (153)`.
- This release supersedes the old v0.32.5-only branch; all open upstream-sync
  issues are handled as one version.

## Implementation Notes

## Round 1 — Mac Upstream Merge

Merged upstream `v0.35.0` into
`upstream-sync/v0.35.0-mobile.1.12.0` and kept fork-specific release and mobile
constraints:

- Preserved fork appcast/Sparkle release feed and mobile release workflow.
- Preserved CloudKit/iOS sync/versioning guidance in `AGENTS.md`.
- Kept `version.env` shipped-baseline fields at `UPSTREAM_VERSION=v0.32.4` and
  `UPSTREAM_SYNC_DATE=2026-06-06` until this sync is actually released.
- Stamped target Mac values for branch work:
  `MARKETING_VERSION=0.35.0.1`, `BUILD_NUMBER=85.1`,
  `MOBILE_VERSION=1.12.0`.
- Regenerated parser hash to `c87a61d15e601949`.
- Merged upstream release tooling helpers for package product paths, dSYM paths,
  and Sparkle signing paths.

## Round 2 — iOS Shared and Presentation Work

MiniMax subscription metadata was the only new upstream user-visible field that
required an iOS wire/cache/render update:

- Added optional `subscriptionExpiresAt` and `subscriptionRenewsAt` to
  `Shared/Models/UsageSnapshot.swift`.
- Mapped the metadata from Mac `SyncCoordinator`.
- Preserved the metadata through iOS `CloudSyncReader`, SwiftData schema, and
  SwiftData bridge round trips.
- Rendered the date on the iOS provider card as `Renews %@` or
  `Plan expires %@`, with 4-language translations.
- Added merge, decode, SwiftData, and iOS display test coverage.

Other v0.34-v0.35 providers and data paths were audited:

- Devin now has iOS provider identity support in the quota notification catalog,
  provider color palette, and mock sync coverage. Daily/weekly quota windows
  render through existing generic usage lanes.
- Amp, Kimi Code API, MiMo balance components, Copilot budgets, weekly pace, and
  cost/parser changes either flow through existing provider, budget, cost, or
  pace lanes, or remain Mac-only behavior.
- No additional Shared wire fields or CloudKit schema fields were required.

## Round 3 — Upstream Stability Backport

The full Mac test shard exposed a token-account menu race in
`StatusMenuTokenAccountSwitcherTests`: selecting a cached token account while a
global refresh is in flight could briefly show data from the wrong account.
Upstream had already fixed this after `v0.35.0` in unreleased commit
`ae7455ba fix: keep token account menu data scoped (#1530)`.

Backported only the scoped-cache pieces needed for the release branch:

- `UsageStore+TokenAccounts.activateCachedTokenAccountSnapshot(provider:accountID:)`
  activates the selected account's cached snapshot immediately.
- The menu selection handler validates the selected index, activates the scoped
  snapshot, and defers switcher rebuild only while the same provider menu is
  still visible.
- Added upstream regression coverage for cached selected-account display and
  stale-cache clearing while a refresh is in flight.

This is a stability backport, not a move to unreleased upstream `0.35.1`.

## Round 4 — Versioning and Release Notes

- `CodexBarMobile/project.yml`: `MARKETING_VERSION=1.12.0`,
  `CURRENT_PROJECT_VERSION=153`.
- `CodexBarMobile.xcodeproj` regenerated with `xcodegen generate`.
- `CodexBarMobile/CHANGELOG.md`: added `1.12.0 (153)`.
- `MobileReleaseNotesCatalog`: added localized `1.12.0` release notes.
- Root `CHANGELOG.md`: added `0.35.0.1 (Mobile 1.12.0, build 85.1)` with
  mobile-first notes and upstream scope.

## Round 5 — Review Fixes

Targeted review found two blocking issues after the first pass; both were fixed
before packaging:

- iOS `SwiftDataBridge` previously reconstructed cold-start provider snapshots
  from a subset of decomposed columns. Added optional `providerPayloadData` to
  `ProviderSnapshotModel`, encoded the full `ProviderUsageSnapshot` on upsert,
  and made cold-start hydration prefer the canonical payload while preserving
  the old decomposed-column fallback for existing stores. This prevents rich
  optional fields such as `accountIdentities`, `quotaWarnings`, billing
  summaries, and future additive provider payloads from disappearing until the
  next CloudKit refresh.
- Mac MiniMax menu text now localizes `Renews: %@`, `Plan expires: %@`, and
  `∞ Unlimited` through `L(...)`; all Mac resource bundles contain those keys.
- Devin was added to the iOS quota provider list, iOS color palette, and Mac
  mock provider injector/test counts so manual sync QA can exercise the new
  upstream provider without a live Devin account.
