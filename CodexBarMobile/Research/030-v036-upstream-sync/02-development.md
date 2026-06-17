# v0.36.1 Upstream Sync Development Log

Status: `done`
Date: 2026-06-16
Branch: `upstream-sync/v0.36.1-mobile.1.13.0`

## Completed

- Created the work branch from `origin/mobile-dev` at `7b565366`.
- Confirmed current baseline in `version.env`: `UPSTREAM_VERSION=v0.35.0`,
  `UPSTREAM_SYNC_DATE=2026-06-14`.
- Confirmed upstream latest release through GitHub Releases:
  `v0.36.1`, published 2026-06-16.
- Confirmed open upstream-sync scope is issue #28, covering `v0.36.0` and
  `v0.36.1`.
- Read required process docs:
  - `AGENTS.md`;
  - `docs/versioning.md`;
  - `docs/ios-sync-compatibility-testing.md`;
  - `docs/cloudkit-deploy-audit.md`;
  - `docs/RELEASE-CHECKLIST.md`.
- Read prior sync evidence in `CodexBarMobile/Research/029-v035-upstream-sync/`.
- Merged upstream tag `v0.36.1` into the branch and resolved conflicts while
  preserving fork release tooling, CloudKit Production behavior, iOS release
  notes, and mobile versioning.
- Staged target versions in `version.env`: Mac `0.36.1.1`, build `88.1`, mobile
  `1.13.0`, `UPSTREAM_VERSION=v0.36.1`, `UPSTREAM_SYNC_DATE=2026-06-16`.
- Added iOS provider readiness for LiteLLM, Poe, Chutes, and Zed:
  `QuotaProviderList`, provider colors, mock profiles, and count/collision
  tests.
- Added Poe generic sync rows in `PoeUsageSnapshot` so current balance and
  recent points history can render on iOS through existing generic windows.
- Updated non-exhaustive Mac fork switches for the new providers:
  `AccountIdentityComputer`, `SyncCoordinator`, mock injection, and quota
  subscription support.
- Preserved upstream Mac v0.36.0/v0.36.1 changes: LiteLLM/Poe/Chutes/Zed
  providers, Antigravity quota/reset improvements, provider switcher background
  fix, process-pipe cleanup, XDG config handling, Mac 21-language resources, and
  provider reliability fixes.
- Removed duplicate conflict leftovers from `UsageStore` and `MenuCardView`
  after upstream split quota-warning/model helper extensions.
- Restored quota-warning CloudKit push writes when
  `notificationPushToiOSEnabled` is true.
- Updated root `CHANGELOG.md`, iOS `CHANGELOG.md`, `MobileReleaseNotesCatalog`,
  `Localizable.xcstrings`, and `CodexBarMobile/project.yml`; regenerated the
  Xcode project with `xcodegen generate`.

## Commands / Evidence

```text
git switch -c upstream-sync/v0.36.1-mobile.1.13.0 origin/mobile-dev
Result: switched to new branch.

gh issue list --repo o1xhack/CodexBar-Mobile --state open --search upstream-sync --json ...
Result: issue #28 only.

gh release list --repo steipete/CodexBar --limit 10
Result: latest upstream release is v0.36.1.

git diff --stat v0.35.0..v0.36.1
Result: 416 files changed, 27,930 insertions, 4,570 deletions.

git merge --no-commit --no-ff v0.36.1
Result: conflicts resolved on branch upstream-sync/v0.36.1-mobile.1.13.0.

bash Scripts/regenerate-codex-parser-hash.sh
Result: CodexParserHash.generated.swift = 72dddb100a729cd3.

cd CodexBarMobile && xcodegen generate
Result: CodexBarMobile.xcodeproj regenerated for iOS 1.13.0 build 154.
```

## Pending / Boundary

- Local signed/notarized Mac artifacts are complete.
- GitHub draft-release creation is pending explicit confirmation because
  `Scripts/release.sh` phase 1 pushes tag `v0.36.1.1-mobile.1.13.0` and uploads
  release assets to GitHub.
- No live release, TestFlight upload, merge, or push has been performed.
