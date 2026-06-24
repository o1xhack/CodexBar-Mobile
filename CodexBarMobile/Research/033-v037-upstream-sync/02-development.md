# v0.37.2 Upstream Sync Development Log

Status: `in-progress`
Date: 2026-06-23
Branch: `upstream-sync/v0.37.2-mobile.1.15.0`

## Starting State

- Created branch from `origin/mobile-dev` at `ba4be051`.
- Current baseline in `version.env`: `0.36.1.1`, `88.1`,
  `MOBILE_VERSION=1.13.0`, `UPSTREAM_VERSION=v0.36.1`,
  `UPSTREAM_SYNC_DATE=2026-06-16`.
- iOS project already targets `1.14.0 (163)` from Sync Device Management, and
  that release is already in review. This upstream sync targets `1.15.0`.
- Open upstream-sync issues: #30 (`v0.37.0`), #32 (`v0.37.1`), #33
  (`v0.37.2`).

## Planned Phases

1. Merge upstream `v0.37.2` and resolve conflicts preserving fork-owned files.
2. Compile and address provider/sync integration errors.
3. Audit Mac-to-iOS payloads for Bedrock, Codex profile-home accounts/reset
   credits, Cursor on-demand spend, Mistral Vibe usage, and provider confidence.
4. Implement any required optional shared/iOS support.
5. Update versions, changelogs, release notes, localization, and Research
   evidence.
6. Run test gates, CloudKit audit, compatibility matrix, and review loop.

## Evidence Log

### Branch and Merge

- Created the work branch from latest `origin/mobile-dev` at `ba4be051`.
- Renamed the initial branch after user correction so the final branch is
  `upstream-sync/v0.37.2-mobile.1.15.0`.
- Fetched upstream tags and merged `v0.37.2^{}` with `--no-commit --no-ff`.
- Resolved merge conflicts while preserving fork release/versioning/CloudKit/iOS
  sync behavior.
- `git diff --name-only --diff-filter=U`: no unresolved merge conflicts remain.
- Created a local merge commit so the branch has a clean worktree for release
  phase1 preflight once the release credential/tag-push authorization is
  explicitly granted. No branch push or release tag was created.

### Conflict Resolution Notes

- Kept upstream Mac resource updates where conflicts were pure localization
  changes.
- Kept fork release semantics for `version.env`, appcast/release targeting,
  `Scripts/lint.sh`, CI branch coverage, and mobile/iOS docs.
- Reconciled upstream split lint/test/sharding changes with fork checks:
  `audit-i18n`, parser-version audit, parser-hash audit, documentation links,
  package strip, release dSYM path, Sparkle path, and CI path gates.
- Regenerated `Sources/CodexBarCore/Generated/CodexParserHash.generated.swift`
  after parser-hash audit reported stale hash `800a06dead603ea7`; final hash is
  `4ac7fb39e0884e62`.

### Mac Sync and Upstream Scope

Mac code now includes upstream `v0.37.2` features/fixes across provider
fetching, menu/card rendering, widgets, endpoint override security, diagnostics,
CLI, package stripping, localization, docs, and tests. Fork-specific additions
preserved during the merge include:

- o1xhack bundle/app group/iCloud identifiers and Production CloudKit
  entitlements;
- fork release scripts and Sparkle composite versioning;
- Mac-to-iOS sync coordinator and shared payload contracts;
- iOS app, changelog, release notes, and localization.

### Shared and iOS Bridge

Added:

- `Shared/Models/V037Snapshots.swift`
- `CodexBarMobile/Shared/Models/V037Snapshots.swift`
- `CodexBarMobile/CodexBarMobile/Views/CodexResetCreditsCard.swift`
- `Tests/CodexBarTests/V037SnapshotsCodableTests.swift`

Updated:

- `Shared/Models/UsageSnapshot.swift`
- `CodexBarMobile/Shared/Models/UsageSnapshot.swift`
- `Sources/CodexBar/Sync/SyncCoordinator.swift`
- `CodexBarMobile/CodexBarMobile/Views/ProviderDetailView.swift`

New bridge behavior:

- Mac maps Codex reset credits into optional `SyncCodexResetCredits`.
- Mac maps provider confidence into optional `usageDataConfidence`.
- iOS renders Codex reset credits only when present and non-empty.
- iOS renders confidence only when Mac reports a non-`exact`, non-`unknown`
  value.
- Old payloads decode without the new fields; future/partial reset-credit
  payloads are tolerated.

### Version and Release Notes

Updated:

- `version.env`:
  - `MARKETING_VERSION=0.37.2.1`
  - `BUILD_NUMBER=92.1`
  - `MOBILE_VERSION=1.15.0`
  - `UPSTREAM_VERSION=v0.37.2`
  - `UPSTREAM_SYNC_DATE=2026-06-22`
- `CodexBarMobile/project.yml`: `MARKETING_VERSION=1.15.0`,
  `CURRENT_PROJECT_VERSION=164` for app, tests, and UI tests.
- Root `CHANGELOG.md`: added `0.37.2.1 (Mobile 1.15.0 · build 92.1)`.
- `CodexBarMobile/CHANGELOG.md`: added `1.15.0 (164)`.
- `MobileReleaseNotesCatalog`: added localized `1.15.0` entry and demoted
  `1.14.0` from `Latest`.
- `Localizable.xcstrings`: added four-language translations for the new iOS
  release-note and Codex reset-credit/confidence strings.
- `CodexBarMobile.xcodeproj`: regenerated with `xcodegen generate`.

### Release Packaging Boundary

`./Scripts/release.sh` phase1 was inspected and confirmed to:

- require a clean worktree;
- run release gates;
- sign and notarize with local release credentials;
- create and force-push tag `v0.37.2.1-mobile.1.15.0` to `origin`;
- create a draft GitHub release with uploaded artifacts.

Because release credentials and tag publication require explicit confirmation in
the Goal, phase1 was not executed in this pass.
