# v0.32.5 Upstream Sync Development Log

Status: `in-progress`
Date: 2026-06-10
Branch: `upstream-sync/v0.32.5-mobile.1.12.0`

## Checklist

- [x] Confirm latest `mobile-dev` baseline: `fe11a1c23efd1787bf4da6c0b54645484a5bbd86`.
- [x] Create branch from `mobile-dev`: `upstream-sync/v0.32.5-mobile.1.12.0`.
- [x] Confirm only open upstream-sync issue: #22.
- [x] Confirm upstream target release: `v0.32.5`, published 2026-06-09.
- [x] Draft Research scope/design/testing documents.
- [x] Merge upstream `v0.32.5`.
- [x] Resolve conflicts while preserving fork versioning, release, CloudKit, and iOS sync constraints.
- [x] Add Shared subscription metadata fields.
- [x] Map Mac `UsageSnapshot.subscriptionExpiresAt` / `subscriptionRenewsAt` into sync payload.
- [x] Preserve subscription metadata during iOS merge and SwiftData cache round-trip.
- [x] Render subscription metadata in iOS with 4-language localization.
- [x] Update Mac/iOS changelogs and release notes.
- [x] Update version fields for draft packaging.
- [x] Run local builds, focused tests, lint, parser hash audit, and CloudKit schema audit.
- [ ] Mac signed/notarized draft release packaging.
- [ ] Final local merge commit after release-boundary decision.
- [ ] Record final release draft link and review result.

## Evidence Log

### Branch

```text
git status --short --branch
## upstream-sync/v0.32.5-mobile.1.12.0
```

### Open Issues

```text
gh issue list --repo o1xhack/CodexBar-Mobile --state open --search 'upstream-sync OR 上游同步'
#22 上游同步：steipete/CodexBar 已发布 v0.32.5（当前基线 v0.32.4）
```

### Upstream Release

```text
gh release view v0.32.5 --repo steipete/CodexBar --json tagName,publishedAt,url
tagName: v0.32.5
publishedAt: 2026-06-09T07:30:36Z
url: https://github.com/steipete/CodexBar/releases/tag/v0.32.5
```

### Version Targets

```text
Mac MARKETING_VERSION: 0.32.5.1
Mac BUILD_NUMBER: 80.1
iOS MOBILE_VERSION: 1.12.0
iOS CURRENT_PROJECT_VERSION: 152
Sparkle version: 80.1.1.12.0
```

## Implementation Notes

### Upstream Merge

Merged upstream tag `v0.32.5` into the branch with fork-local conflict
resolutions:

- `CHANGELOG.md`: kept fork release chronology and added a pending
  `0.32.5.1 (Mobile 1.12.0 · build 80.1)` entry for the one-version sync.
- `version.env`: set draft packaging versions to `MARKETING_VERSION=0.32.5.1`,
  `BUILD_NUMBER=80.1`, and `MOBILE_VERSION=1.12.0`; kept
  `UPSTREAM_VERSION=v0.32.4` and `UPSTREAM_SYNC_DATE=2026-06-06` because the
  synced build is not live yet.
- `appcast.xml`: kept the currently published fork item; draft release packaging
  must regenerate appcast metadata rather than accepting upstream appcast state.
- `UsageFetcher.swift`: preserved fork rich provider payload fields while adding
  upstream `subscriptionExpiresAt` and `subscriptionRenewsAt`.
- `CodexParserHash.generated.swift`: regenerated after merge to
  `dd86017647affbc8`.

### Shared Sync Payload

Added additive optional fields to both Shared model copies:

- `ProviderUsageSnapshot.subscriptionExpiresAt: Date?`
- `ProviderUsageSnapshot.subscriptionRenewsAt: Date?`

The custom decoder uses `decodeIfPresent`, so old payloads remain valid and old
apps ignore the extra JSON keys.

### Mac Sync Mapping

`SyncCoordinator.buildProviderUsageSnapshot` now copies upstream
`UsageSnapshot.subscriptionExpiresAt` and `subscriptionRenewsAt` into the shared
provider payload. MiniMax is the current upstream provider that populates these
fields; future providers can reuse the same generic lane.

### iOS Merge, Cache, and UI

- `CloudSyncReader.mergeProviderEntries` preserves subscription metadata with
  `latestNonNil` semantics, so an older Mac snapshot cannot erase metadata from
  a newer Mac.
- The same merge now also preserves existing rich account/provider fields with
  `latestNonNil` instead of losing them when a newer primary entry lacks a
  specific optional payload.
- `SwiftDataBridge` and `ProviderSnapshotModel` persist and restore the two new
  dates across offline/relaunch cache reads.
- `ProviderUsageView` renders a compact localized metadata row:
  - `Renews %@`
  - `Plan expires %@`

### iOS Release Metadata

- `CodexBarMobile/project.yml`: `MARKETING_VERSION=1.12.0`,
  `CURRENT_PROJECT_VERSION=152`.
- Regenerated `CodexBarMobile.xcodeproj` with `xcodegen generate`.
- `CodexBarMobile/CHANGELOG.md`: added `1.12.0 (152)` entry for the v0.32.5
  sync.
- `MobileReleaseNotesCatalog`: added `1.12.0` as `Latest` and demoted `1.11.1`.
- `Localizable.xcstrings`: added all new user-facing iOS strings in English,
  Simplified Chinese, Traditional Chinese, and Japanese.

### Current Boundary

Mac code sync, iOS support, local build/test/lint, and CloudKit audit are ready.
Signed/notarized Mac draft release creation has not been run because it crosses
the release-credential / remote draft-release boundary for this Goal.
