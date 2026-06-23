# v0.37.2 Upstream Sync Testing

Status: `in-progress`
Date: 2026-06-23
Branch: `upstream-sync/v0.37.2-mobile.1.15.0`

## Required Gates

- Mac build and lint.
- Full or sharded Mac test suite.
- Focused provider and registry tests for Bedrock, Codex, Cursor, Mistral,
  MiniMax, Antigravity, endpoint validation, account identity, and sync.
- Parser/pricing hash verification if upstream parser files require it.
- iOS project generation, build, and relevant tests.
- iOS four-language localization audit.
- CloudKit Production schema audit.
- 2 Mac x 2 iPhone old/new sync compatibility matrix if Shared/sync/provider
  display changes are present.
- Final diff review with blocking issues fixed.

## CloudKit Production Schema Audit

Status: complete for this branch.

Last published fork release:

```text
gh release list --repo o1xhack/CodexBar-Mobile --limit 20 --json tagName,isDraft,publishedAt
```

Result: latest non-draft published release is
`v0.36.1.1-mobile.1.13.0` (`2026-06-17T21:13:22Z`).

Full published-tag-to-working-tree keyword audit:

```text
git diff v0.36.1.1-mobile.1.13.0 -- | grep -E "^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)"
git diff v0.36.1.1-mobile.1.13.0 -- Shared/iCloud/CloudConstants.swift
git diff v0.36.1.1-mobile.1.13.0 -- Shared/Models/UsageSnapshot.swift | grep -E "^\+.*public let|^-.*public let"
```

Result:

- Shows pre-existing `DeviceLifecycleEvent` / subscription additions from the
  iOS `1.14.0` Sync Device Management work.
- Shows `Shared/Models/UsageSnapshot.swift` additions:
  - `public let codexResetCredits: SyncCodexResetCredits?`
  - `public let usageDataConfidence: String?`

Incremental upstream-sync audit against this branch's starting point:

```text
git diff origin/mobile-dev -- | grep -E "^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)"
git diff origin/mobile-dev -- Shared/iCloud/CloudConstants.swift
git diff origin/mobile-dev -- Shared/Models/UsageSnapshot.swift | grep -E "^\+.*public let|^-.*public let"
```

Result:

- No CloudKit schema keyword output relative to `origin/mobile-dev`.
- No `Shared/iCloud/CloudConstants.swift` diff relative to `origin/mobile-dev`.
- Only the two optional `ProviderUsageSnapshot` fields above are added by this
  branch.

Verdict:

- This `v0.37.2` / iOS `1.15.0` upstream-sync round does **not** add a new
  CloudKit Production schema deploy requirement.
- The new reset-credit/confidence values live inside the existing compressed
  provider payload `Data` blob and are decoded with optional/default-tolerant
  logic.
- The already-reviewing iOS `1.14.0` `DeviceLifecycleEvent` schema deploy is
  confirmed complete in Production. Recheck command:

```text
xcrun cktool export-schema --team-id 3TUERHN53E \
  --container-id iCloud.com.o1xhack.codexbar \
  --environment production \
  --output-file /tmp/codexbar-production-schema-20260623-165615.json
```

Result:

```text
RECORD TYPE DeviceLifecycleEvent (
    "___recordID"         REFERENCE QUERYABLE,
    confirmedAt           TIMESTAMP,
    confirmedFromDeviceID STRING,
    kind                  STRING,
    note                  STRING,
    primaryDeviceID       STRING,
    relatedDeviceIDs      LIST<STRING>,
    GRANT WRITE TO "_creator",
    GRANT CREATE TO "_icloud",
    GRANT READ TO "_world"
);
```

## 2 Mac x 2 iPhone Old/New Compatibility Matrix

Definitions for this release:

- Old Mac: shipped baseline before this branch, `0.36.1.1` / Sparkle
  `88.1.1.13.0`.
- New Mac: target branch build `0.37.2.1` / Sparkle `92.1.1.15.0`.
- Old iPhone: current shipped/validated iOS line before this branch.
- New iPhone: target branch build `1.15.0`.

The matrix is expected to apply because this release changes Mac provider
display data and adds optional Shared payload/rendering paths for existing Codex
provider details.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 01 | old | old | old | old | substituted | Existing shipped behavior unchanged; no branch-specific payload fields present. Baseline risk covered by prior release plus no `CloudConstants` delta from this branch. | No real 2 Mac x 2 iPhone hardware run in this pass. |
| 02 | old | old | old | new | substituted | `V037SnapshotsCodableTests` old-payload test confirms new iOS decodes payloads with missing `codexResetCredits` / `usageDataConfidence`. iOS simulator tests passed. | New iOS hides new Codex sections when old Macs omit fields. |
| 03 | old | old | new | old | substituted | Same old-payload decode coverage as case 02; old iPhone receives old payload only. | No new writer present. |
| 04 | old | old | new | new | substituted | `V037SnapshotsCodableTests` old-payload nil semantics + iOS test suite. | Both new iPhones should converge to old visible state after fetch. |
| 05 | old | new | old | old | substituted | New Mac writes optional fields only. Optional-key addition is payload-internal; old iOS compatibility is inferred from additive JSON/object payload policy and no required field/schema bump. | Residual risk: old iOS exact rendering not manually reinstalled. |
| 06 | old | new | old | new | substituted | `V037SnapshotsCodableTests` round-trip/partial/future tests, `SyncWireFormatRoundTripTests`, focused multi-account gate. | New iOS renders new Mac Codex reset credits when present; old iOS should ignore unknown optional fields. |
| 07 | old | new | new | old | substituted | Same as case 06 with iPhone roles swapped. | Device identity ordering covered by multi-account sync tests, not real hardware. |
| 08 | old | new | new | new | substituted | New iOS build/test + wire round-trip tests; mixed old/new Mac writer semantics covered by optional decode and multi-account snapshot tests. | Both new iPhones expected to converge after CloudKit fetch/push. |
| 09 | new | old | old | old | substituted | Same as case 05 with Mac roles swapped. | Old iOS real-device rendering not manually captured. |
| 10 | new | old | old | new | substituted | Same as case 06 with Mac writer order swapped; tests cover decode independent of writer order. | |
| 11 | new | old | new | old | substituted | Same as case 07 with Mac writer order swapped. | |
| 12 | new | old | new | new | substituted | Same as case 08 with Mac writer order swapped. | |
| 13 | new | new | old | old | substituted | Two new Macs emit same additive optional fields. No schema/providerPayloadVersion bump; old iOS unknown-field behavior inferred from additive optional JSON payload policy. | Highest residual risk for old iOS because not physically run. |
| 14 | new | new | old | new | substituted | `AccountIdentity|MultiAccount|DualZoneReader` focused gate passed 81 tests; `V037SnapshotsCodableTests` verifies new optional payloads. | Mixed phone convergence not manually verified. |
| 15 | new | new | new | old | substituted | Same as case 14 with iPhone roles swapped. | |
| 16 | new | new | new | new | substituted | Full new-stack automated evidence: Mac full tests, iOS simulator tests, lint, i18n, parser hash/version, and focused sync/account tests passed. | No real-device CloudKit push latency proof in this pass. |

Substitution rationale:

- Real 2 Mac x 2 iPhone hardware was not exercised in this branch run.
- The branch's sync change is additive and payload-internal: no new CK record
  type/field/index, no zone/subscription change, no `providerPayloadVersion`
  bump, and no required decode field.
- Automated replacement evidence targets the failure modes in
  `docs/ios-sync-compatibility-testing.md`: old payload decode, new optional
  payload round-trip, partial/future payload tolerance, multi-account writer
  identity, and iOS rendering/build stability.

Residual risk:

- Old iOS clients were not reinstalled and pointed at a real CloudKit
  Production account with new Mac payloads.
- Silent push delivery and two-phone convergence were not proven with real
  devices.
- Pre-existing iOS 1.14 `DeviceLifecycleEvent` Production schema deploy status
  is verified by `cktool export-schema --environment production`.

## Test Evidence

Passed:

- `swift build`
- `swiftc -parse Sources/CodexBarCore/UsageFetcher.swift`
- `swift test --filter V037SnapshotsCodableTests`
  - 6 tests passed.
  - Covers full round-trip, old payload nil fields, partial reset-credit
    payload defaults, partial credit-entry defaults, and future raw values.
- `swift test --filter SyncWireFormatRoundTripTests`
  - 12 tests passed.
- `bash Scripts/lint.sh audit-i18n`
- `bash Scripts/lint.sh audit-parser-version`
- `bash Scripts/lint.sh audit-parser-hash`
  - Initially failed with stale hash `800a06dead603ea7`.
  - `Scripts/regenerate-codex-parser-hash.sh` regenerated
    `4ac7fb39e0884e62`.
  - Rerun passed.
- `cd CodexBarMobile && xcodegen generate`
- iOS simulator debug build:
  - `xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'generic/platform=iOS Simulator' -configuration Debug build`
  - Result: `BUILD SUCCEEDED`.
  - Rerun after the partial-credit compatibility fix also passed.
- iOS simulator tests:
  - `xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,id=E1DD6B03-ACA4-4962-BA33-AF21EFB1B2BB' -configuration Debug test`
  - Initial result: `TEST SUCCEEDED`, 467 unit tests and 3 UI tests passed.
  - Initial `.xcresult`:
    `/Users/yuxiao/Library/Developer/Xcode/DerivedData/CodexBarMobile-fywzrshyicotmkhjufflfswwbceb/Logs/Test/Test-CodexBarMobile-2026.06.23_15-56-12--0700.xcresult`
  - Review-fix rerun result: `TEST SUCCEEDED`, 468 unit tests and 3 UI tests
    passed.
  - Review-fix rerun `.xcresult`:
    `/Users/yuxiao/Library/Developer/Xcode/DerivedData/CodexBarMobile-fywzrshyicotmkhjufflfswwbceb/Logs/Test/Test-CodexBarMobile-2026.06.23_16-23-25--0700.xcresult`
- iOS targeted merge regression after review:
  - `xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,id=E1DD6B03-ACA4-4962-BA33-AF21EFB1B2BB' -configuration Debug test -only-testing:CodexBarMobileTests/CloudKitMergeTests`
  - Result: `TEST SUCCEEDED`, 42 tests passed.
  - `.xcresult`:
    `/Users/yuxiao/Library/Developer/Xcode/DerivedData/CodexBarMobile-fywzrshyicotmkhjufflfswwbceb/Logs/Test/Test-CodexBarMobile-2026.06.23_16-22-38--0700.xcresult`
- `bash Scripts/lint.sh lint`
  - App locale checker OK; non-strict missing-locale warnings remain for
    existing non-iOS Mac locale coverage.
  - Parser hash current.
  - Package path, strip, release dSYM path, Sparkle path, sharding, CI path,
    docs links, llms index, site locales passed.
  - SwiftFormat: 0 files require formatting.
  - SwiftLint: 0 violations, 0 serious.
  - iOS i18n: all locales translated; all 348 source keys present.
  - Parser-version audit: no parser code changes since `origin/mobile-dev`.
- `swift test --no-parallel --filter LocalizationLanguageCatalogTests`
  - 18 tests passed after adding the fork mobile sync keys to strict Mac
    locale catalogs and avoiding an unchanged Italian value.
- `CODEXBAR_TEST_SUITE_TIMEOUT=240 bash Scripts/test.sh`
  - Full sharded Mac suite completed with exit code 0.
  - 45/45 Swift test shards passed.
- `swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'`
  - 81 tests in 13 suites passed.
- `bash Scripts/changelog-to-html.sh 0.37.2.1 >/tmp/codexbar-changelog-0.37.2.1.html && wc -c /tmp/codexbar-changelog-0.37.2.1.html`
  - Generated 4963-byte HTML changelog excerpt.

Known non-blocking warnings:

- iOS simulator tests logged expected App Group / iCloud account warnings in the
  simulator environment.
- Mac locale checker reports warnings for non-strict upstream catalogs, but the
  strict catalogs and iOS four-language catalog passed the required gates.

## Review

Self-review and agent review were run.

Findings fixed:

- P1: iOS multi-device merge rebuilt `ProviderUsageSnapshot` without forwarding
  the new `codexResetCredits` and `usageDataConfidence` fields. Fixed
  `CloudSyncReader.mergeProviderEntries` to use `latestNonNil` for both fields
  and added `CloudKitMergeTests.sameProviderPreservesV037CodexFields`.
- P1: `version.env` comment described `UPSTREAM_VERSION` as already shipped,
  conflicting with the in-progress release boundary. Kept
  `UPSTREAM_VERSION=v0.37.2` per `docs/versioning.md` merge-bookmark rule, but
  changed the comment to say it is the upstream tag merged into this
  branch/release train and only becomes the next shipped baseline after live
  release.

Verification after fixes:

- `swift test --filter V037SnapshotsCodableTests`: 6 tests passed.
- `xcodebuild ... -only-testing:CodexBarMobileTests/CloudKitMergeTests`: 42
  tests passed.
- Full `xcodebuild ... test`: `TEST SUCCEEDED`, 468 unit tests and 3 UI tests
  passed.
- `git diff --check`: passed.

Remaining release blocker:

- Mac draft release phase1 requires explicit user authorization because it uses
  release credentials and pushes the release tag before creating a draft GitHub
  release.

## Continuation Audit — 2026-06-23

Read-only external-state verification after the local merge commit:

- `gh issue list --repo o1xhack/CodexBar-Mobile --state open --search 'upstream-sync'`
  still returns only issues #30 (`v0.37.0`), #32 (`v0.37.1`), and #33
  (`v0.37.2`) for this sync scope.
- `gh release list --repo steipete/CodexBar --limit 10` still reports
  `v0.37.2` as the latest upstream release.
- `gh release view v0.37.2.1-mobile.1.15.0 --repo o1xhack/CodexBar-Mobile`
  returns `release not found`; no draft release exists yet.
- `git tag --list 'v0.37.2.1-mobile.1.15.0'` and
  `git ls-remote --tags origin 'v0.37.2.1-mobile.1.15.0'` return no tag.
- `Scripts/release.sh` phase1 is confirmed to require a clean worktree, run
  lint, sign/notarize or reuse notarized artifacts, create and force-push the
  release tag to `origin`, and then create the draft GitHub release.

Conclusion: current code/test/review evidence is complete through the local
merge commit, but the requested Mac draft release remains blocked on explicit
authorization for the release-credential/tag-push phase1 boundary.
