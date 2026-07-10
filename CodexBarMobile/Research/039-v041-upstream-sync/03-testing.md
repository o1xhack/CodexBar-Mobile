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
| Upstream merge | pending | |
| Mac build | pending | |
| Mac lint | pending | |
| Mac focused tests | pending | |
| Mac full tests | pending | |
| Multi-account / multi-device tests | pending | |
| Parser version/hash | pending | |
| iOS xcodegen/build/tests | pending | |
| Widget/provider display tests | pending | |
| Four-language localization | pending | |
| CloudKit Production audit | pending | |
| Signed/notarized artifacts | pending | |
| Candidate appcast | pending | |
| GitHub draft release | pending | no push or published tag allowed |
| Final review blockers | pending | |

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

Preliminary verdict: no deploy expected. Final verdict remains pending until
post-implementation output is recorded.

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
