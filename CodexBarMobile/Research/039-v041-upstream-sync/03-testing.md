# v0.41.0 Upstream Sync Testing

Status: `in-progress`
Date: 2026-07-09
Branch: `upstream-sync/v0.41.0-mobile.1.18.0`

## Release Targets

| Item | Expected |
|---|---|
| Mac short version | `0.41.0.1` |
| Mac build / Sparkle version | `100.1.1.18.0` |
| iOS version/build | `1.18.0 (186)` |
| Artifact stem | `CodexBar-0.41.0.1-mobile.1.18.0` |
| Draft tag name | `v0.41.0.1-mobile.1.18.0` |

## Gate Ledger

| Gate | Result | Evidence |
|---|---|---|
| Branch isolation | pass | branch and `origin/mobile-dev` both began at `8248714e`; work branch is `upstream-sync/v0.41.0-mobile.1.18.0` |
| Upstream release facts | pass | GitHub Releases: v0.40.0 at `2026-07-05T23:10:19Z`; v0.41.0 at `2026-07-06T23:46:03Z` |
| Upstream merge | pass | merge commit `00a13189`; all ten conflicts resolved; target tag is second parent |
| Mac build | pass | `swift build` completed in 30.49s after conflict resolution |
| Mac lint | pass | `bash Scripts/lint.sh lint`: SwiftFormat 0 pending files; SwiftLint 0 violations across 1,348 files; localization and parser-version audits passed |
| Mac focused tests | pass | 241 tests across SubprocessRunner, browser-cookie deadline/context, Kimi, Claude plan, widget snapshots, and CostUsage passed; Kimi isolated rerun also passed |
| Mac full tests | pass | `swift test --no-parallel`: 5,810 tests in 588 suites, 0 failures, 225.321s |
| Multi-account / multi-device tests | pass | release-checklist filter: 76 tests in 10 suites, 0 failures, 2.184s |
| Parser version/hash | pass | `parserLogicVersion=8`; generated hash `67c76db38c18af6a`; audit scripts pass |
| iOS xcodegen/build/tests | pass | XcodeBuildMCP iPhone 17 / iOS 26.4: build+launch 28.8s; focused 10/10; full unit target 582/582 |
| Widget/provider display tests | pass | full iOS unit run includes WidgetSnapshotBuilder and CodexBarWidgetRenderMatrix; Mac Kimi/Claude sync tests pass |
| Four-language localization | pass | all locales translated; source-vs-catalog 401/401 |
| CloudKit Production audit | pass | no schema keywords, CloudConstants diff, or UsageSnapshot field diff; Mac/iOS entitlements are Production; no deploy required |
| Signed/notarized artifacts | pending | |
| Candidate appcast | pending | |
| GitHub draft release | pending | no push or published tag allowed |
| Final review blockers | pending | |

### Mac full-test concurrency note

Swift Testing 1902 runs tests in-process and in parallel by default. On this
56-worker Mac, both `swift test --parallel` and
`swift test --parallel --num-workers 8` overloaded deadline-sensitive suites:
the runs completed all 5,810 tests but reported 21-24 timing/cancellation
issues. The worker flag only reduced outer XCTest workers and did not limit
Swift Testing task-group concurrency.

Every suite named by those runs was then rerun in an isolated filter: 141 tests
across Command Code, DeepSeek, Kimi, Claude web deadlines, Antigravity,
SubprocessRunner, Codex login, CLI serve routing, and memory-pressure handling
passed. The one later cache-fixture hit also passed 7/7 in isolation. Finally,
the Apple-documented global switch `swift test --no-parallel` passed the full
5,810-test set. This is classified as a high-core-count test-runner scheduling
risk, not a product regression; CI should still be observed after any future
push.

## CloudKit Production Schema Audit

Baseline published fork tag:

```text
v0.39.0.1-mobile.1.17.0
```

Final audit commands:

```text
git diff v0.39.0.1-mobile.1.17.0..HEAD -- \
  ':(exclude)docs' ':(exclude)CodexBarMobile/Research' | \
  grep -E '^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)'

git diff v0.39.0.1-mobile.1.17.0..HEAD -- Shared/iCloud/CloudConstants.swift

git diff v0.39.0.1-mobile.1.17.0..HEAD -- Shared/Models/UsageSnapshot.swift | \
  grep -E '^\+.*public let|^-.*public let'
```

Recorded output on 2026-07-09:

```text
LAST_TAG=v0.39.0.1-mobile.1.17.0
SCHEMA_KEYWORDS=(no output)
CLOUD_CONSTANTS=(no output)
USAGE_SNAPSHOT_FIELDS=(no output)
iOS entitlement=Production
Scripts/package_app.sh entitlement=Production
```

Final verdict: **no CloudKit Dashboard Production schema deploy is required**.
Kimi and Claude reuse keys inside the existing opaque payload; the iOS
formatter change is consumer-only.

## 2 Mac x 2 iPhone Compatibility Matrix

Old versions are published Mac `0.39.0.1` / iOS `1.17.0`; new versions are
Mac `0.41.0.1` / iOS `1.18.0`. Mac A and Mac B are distinct writers; iPhone A
and iPhone B are distinct readers.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes / residual risk |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | pending | | |
| 2 | old | old | old | new | pending | | |
| 3 | old | old | new | old | pending | | |
| 4 | old | old | new | new | pending | | |
| 5 | old | new | old | old | pending | | |
| 6 | old | new | old | new | pending | | |
| 7 | old | new | new | old | pending | | |
| 8 | old | new | new | new | pending | | |
| 9 | new | old | old | old | pending | | |
| 10 | new | old | old | new | pending | | |
| 11 | new | old | new | old | pending | | |
| 12 | new | old | new | new | pending | | |
| 13 | new | new | old | old | pending | | |
| 14 | new | new | old | new | pending | | |
| 15 | new | new | new | old | pending | | |
| 16 | new | new | new | new | pending | | |

For substituted rows, record why hardware was unavailable, the exact unit/
mock/simulator/code-audit evidence, and remaining risk. No row may remain
`pending` at closeout.

## Review Ledger

| Round | Reviewer | Findings | Fix/retest |
|---|---|---|---|
| Merge | pending | | |
| Shared/iOS | pending | | |
| Release/testing | pending | | |
