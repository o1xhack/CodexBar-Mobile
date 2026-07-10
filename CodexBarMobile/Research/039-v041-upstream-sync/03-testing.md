# v0.41.0 Upstream Sync Testing

Status: `done`
Date: 2026-07-09
Completed: 2026-07-10
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
| iOS xcodegen/build/tests | pass | XcodeBuildMCP iPhone 17 / iOS 26.4: post-review build+launch 5.7s; mixed-writer merge 49/49; full target 589 passed, 0 failed, 4 skipped |
| Widget/provider display tests | pass | full iOS run includes WidgetSnapshotBuilder and CodexBarWidgetRenderMatrix; Kimi/Claude single- and mixed-writer tests pass |
| Four-language localization | pass | all locales translated; source-vs-catalog 401/401 |
| CloudKit Production audit | pass | no runtime/source schema keywords, CloudConstants diff, or UsageSnapshot field diff; Mac/iOS entitlements are Production; no deploy required |
| Signed/notarized artifacts | pass | notary `90287227-c47a-409d-96b4-91ca190b4be9` Accepted; stapled ZIP and matching universal dSYM verified |
| Signed candidate safe regression | pass | extracted CLI reports `CodexBar 0.41.0.1`; top-level and new `cards --help` render; signed app stayed alive for 3s; no provider/Keychain probes used |
| Candidate appcast | pass | XML/HTML valid; `mobile-dev` feed/changelog links; length `47418362`; EdDSA verified locally |
| Remote branch and tag | pass | branch pushed at `81f43ecb`; annotated tag `v0.41.0.1-mobile.1.18.0` resolves to the same commit |
| GitHub draft release | pass | `draft=true`; draft `untagged-14030a96acdd8839768b`; ZIP and dSYM uploaded with GitHub digests matching local SHA-256 |
| iOS TestFlight upload | pass | Xcode 26.6 archive/export succeeded; app + both extensions are `1.18.0 (186)`; archive CloudKit entitlement is `Production`; ASC build `d2cb9121-ab21-4242-af36-660e55550308` is `VALID` |
| Final review blockers | pass | 0 code, compatibility, evidence, artifact, draft, or TestFlight blockers; live Mac release and merge intentionally remain out of scope |

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

git diff v0.39.0.1-mobile.1.17.0..HEAD -- \
  Shared Sources CodexBarMobile/CodexBarMobile \
  CodexBarMobile/CodexBarWidgetShared CodexBarMobile/CodexBarWidget | \
  grep -E '^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)'

git diff v0.39.0.1-mobile.1.17.0..HEAD -- Shared/iCloud/CloudConstants.swift

git diff v0.39.0.1-mobile.1.17.0..HEAD -- Shared/Models/UsageSnapshot.swift | \
  grep -E '^\+.*public let|^-.*public let'
```

Recorded output on 2026-07-09:

```text
LAST_TAG=v0.39.0.1-mobile.1.17.0
BROAD_SCHEMA_KEYWORDS=+ func `Wire contract: providerPayloadVersion has NOT been bumped for v0.26 fields`() {
SOURCE_SCHEMA_KEYWORDS=(no output)
CLOUD_CONSTANTS=(no output)
USAGE_SNAPSHOT_FIELDS=(no output)
iOS entitlement=Production
Scripts/package_app.sh entitlement=Production
```

The broad repository grep matched only a Swift test title, not runtime schema
code. A second grep restricted to `Shared`, `Sources`, and the iOS app/widget
source directories produced no output. The match is therefore recorded as a
false positive rather than silently reported as empty.

Final verdict: **no CloudKit Dashboard Production schema deploy is required**.
Kimi and Claude reuse keys inside the existing opaque payload; the iOS
formatter change is consumer-only.

## 2 Mac x 2 iPhone Compatibility Matrix

Old versions are published Mac `0.39.0.1` / iOS `1.17.0`; new versions are
Mac `0.41.0.1` / iOS `1.18.0`. Mac A and Mac B are distinct writers; iPhone A
and iPhone B are distinct readers.

The required physical topology was unavailable in this run. The local host was
one Mac (`the Studio 2023 M2Max`); `devicectl` found one paired physical iPhone
17 Pro Max and one iPhone 17 simulator was used. Installing alternating
old/new builds over the paired phone would not create two independent reader
caches and could overwrite the user's installed app/data, so it was not used
as false 2-phone evidence.

Substitution evidence bundles:

- **E1 — unchanged wire/schema audit:** no Shared model field, encoding
  version, CloudKit record/zone/query, or Production entitlement change. Kimi
  reuses `rateWindows`; Claude reuses optional `loginMethod`.
- **E2 — writer and envelope tests:** Mac full gate 5,810/5,810; v0.41 Kimi
  ordering and Claude Max JSON round-trip 2/2; parser/provider focused gate
  241/241.
- **E3 — reader/merge/cache tests:** post-review iOS full target 589 passed,
  0 failed, and 4 skipped, including
  `CloudKitMergeTests`, `DualZoneReaderTests`, `SnapshotCacheTests`,
  `SameMacMultiAccountMergeTests`, ghost/stale fallback, widget render matrix,
  and old optional-field decode coverage. The focused mixed-writer suite passed
  49/49, covering both freshness orders for Kimi and version-aware generic vs
  specific Claude plans.
- **E4 — distinct/mixed writer identity:** release-checklist
  `AccountIdentity|MultiAccount|DualZoneReader` filter 76/76 plus Mac
  per-provider/legacy dual-write and cleanup tests.
- **E5 — new UI runtime:** XcodeBuildMCP built and launched iOS 1.18.0 on the
  booted iPhone 17 / iOS 26.4 simulator; formatter focused tests 10/10 and
  positive sub-1% behavior is covered in Used/Remaining modes.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes / residual risk |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | published 0.39.0.1/1.17 baseline; E1, E3 | Historical path plus current legacy decode/merge coverage; no live two-phone convergence replay. |
| 2 | old | old | old | new | substituted | E1, E3, E5 | New reader accepts legacy records in tests; silent-push delivery to two real caches unmeasured. |
| 3 | old | old | new | old | substituted | E1, E3, E5 | Symmetric reader ordering covered by deterministic merge tests; real cache timing unmeasured. |
| 4 | old | old | new | new | substituted | E1, E3, E5 | Both logical readers use old-payload fixtures; no two-device foreground/background convergence proof. |
| 5 | old | new | old | old | substituted | E1-E4 | Mixed writers keep distinct device/account keys; old iOS rendering of new values is code-audited, not installed. |
| 6 | old | new | old | new | substituted | E1-E5 | Mixed writer/reader merge and optional fields pass; real CloudKit ordering and silent push remain unmeasured. |
| 7 | old | new | new | old | substituted | E1-E5 | Symmetric mixed-reader ordering passes fixture tests; old physical reader not exercised. |
| 8 | old | new | new | new | substituted | E1-E5 | New readers merge legacy/per-provider buckets; no two-phone cache convergence observation. |
| 9 | new | old | old | old | substituted | E1-E4 | Writer order reversed by deterministic merge inputs; old iOS tolerance relies on unchanged wire fields. |
| 10 | new | old | old | new | substituted | E1-E5 | Writer and reader order reversal covered; production push latency not measured. |
| 11 | new | old | new | old | substituted | E1-E5 | Mixed reader fallback/identity tests pass; no old-build physical install. |
| 12 | new | old | new | new | substituted | E1-E5 | Both new logical readers converge in merge/cache tests; no independent device caches. |
| 13 | new | new | old | old | substituted | E1-E4 | Both writers emit unchanged schema; old readers were not physically exercised against live new records. |
| 14 | new | new | old | new | substituted | E1-E5 | New/old reader optional-field tolerance is covered; live cross-version push remains unmeasured. |
| 15 | new | new | new | old | substituted | E1-E5 | Symmetric mixed-reader evidence; no second physical iPhone. |
| 16 | new | new | new | new | substituted | E1-E5; signed/notarized Mac candidate; iOS simulator launch | Full new/new logic and UI gates pass; production CloudKit and two-device silent-push convergence remain residual risk. |

Matrix verdict: all 16 combinations are enumerated with substituted evidence
and no functional failure. The gate is complete as a substituted pass, with a
non-blocking but explicit residual risk around real Production CloudKit
delivery, two-device cache timing, and silent-push convergence. A later release
run with 2 Macs and 2 iPhones should replace these rows with physical evidence;
this draft does not claim that happened here.

## Review Ledger

| Round | Reviewer | Findings | Fix/retest |
|---|---|---|---|
| Merge/Mac release | independent agent + self-review | Historical fork `0.39.0.1` was mislabeled as raw upstream `0.39.0`; Sparkle list continuation rendered poorly | Restored separate fork/upstream sections; flattened current release bullets for valid HTML; appcast XML/HTML revalidated; reviewer reports 0 Mac/artifact blockers |
| Shared/iOS round 1 | independent agent | Fresh old Mac could hide Kimi Code 7-day and replace Claude Max 5x/20x with generic Max; release notes too technical | Added rolling-upgrade merge policy, both freshness-order tests, real-plan-change guard, plain-language 4-locale notes |
| Shared/iOS round 2 | independent agent | String-only Claude rule could keep a stale specific tier when a current Mac legitimately reports generic Max | Carried source `appVersion` into merge provenance; only pre-0.41 generic yields to a specific tier; added current-generic regression; focused 49/49, full 589 pass/0 fail, build+launch/lint pass |
| Release/evidence round 1 | independent agent | Broad CloudKit grep false positive was recorded as empty; changelog link targeted `main`; historical issue review absent | Recorded/adjudicated false positive, added source-only command, changed link to `mobile-dev`, documented closed #39/#40/#41 + Research/037; lint/appcast audit pass |
| Final re-review | three independent agents | No remaining code, compatibility, evidence, localization, version, signing, notarization, dSYM, or appcast blocker | Blocker count 0 before remote handoff; later branch/tag/draft and TestFlight evidence closed the remaining authorized gates |

## Remote Draft and TestFlight Evidence

```text
branch: upstream-sync/v0.41.0-mobile.1.18.0
tag: v0.41.0.1-mobile.1.18.0
tag commit: 81f43ecb0d2019dcb68f2468a95507239fcada73
draft URL: https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-14030a96acdd8839768b
draft state: true
Mac ZIP GitHub digest: sha256:1c97044fb52786998b1364d7a7180413cf37573d553c7d49441fb65d769193c3
dSYM GitHub digest: sha256:300cb574d7854c3f87b57f60827fa22d639f346fff64f47f0047549f5853ed91
iOS archive: /tmp/CodexBarMobile-20260710-112216.xcarchive
ASC app: 6760216772 / com.o1xhack.codexbar.mobile
ASC build: d2cb9121-ab21-4242-af36-660e55550308
marketing/build: 1.18.0 (186)
processingState: VALID
uploadedDate: 2026-07-10T11:27:00-07:00
```

The draft asset URL uses GitHub's private `untagged-*` path until publication;
the public tag-shaped Sparkle enclosure is therefore expected to stay
unavailable while `draft=true`. Publishing/finalizing the Mac release was not
authorized and was not performed.

## Signed Artifact Evidence

Authoritative release assets (the root `CodexBar.app` is an unstapled packaging
byproduct and is not the candidate):

```text
CodexBar-0.41.0.1-mobile.1.18.0.zip
  bytes: 47418362
  sha256: 1c97044fb52786998b1364d7a7180413cf37573d553c7d49441fb65d769193c3
CodexBar-0.41.0.1-mobile.1.18.0.dSYM.zip
  bytes: 36583185
  sha256: 300cb574d7854c3f87b57f60827fa22d639f346fff64f47f0047549f5853ed91
notary submission: 90287227-c47a-409d-96b4-91ca190b4be9 (Accepted)
artifact CodexGitCommit: 1c01e3a6bd27154b1e7b9bf806274179a790be0b
```

The ZIP contains `0.41.0.1` / `100.1.1.18.0`; app, CLI, and Widget are all
`x86_64 arm64`; codesign deep/strict, Gatekeeper, stapler validation,
Hardened Runtime, Production CloudKit entitlement, and direct two-second launch
gate passed. App/dSYM UUID pairs match:

```text
x86_64 B1C9E041-CFB1-3222-8741-B89CC1883A1E
arm64  B6E0658D-CF06-324B-86C0-9FA98F021BA8
```

A second safe regression run extracted the authoritative ZIP, verified
`CodexBarCLI --version`, rendered top-level help and the new responsive
`cards --help`/`--brief` contract, and kept the signed main app alive for three
seconds. It intentionally did not invoke live usage fetches, browser-cookie
imports, or Keychain-backed providers.

Later commits change only iOS merge/render tests, localized iOS notes, release
documentation, and release-note generation; no Mac runtime, Shared payload,
package, version, signing, or packaging source changed after the artifact
commit. The candidate appcast was regenerated after those documentation fixes
and its enclosure signature verifies against this exact ZIP.
