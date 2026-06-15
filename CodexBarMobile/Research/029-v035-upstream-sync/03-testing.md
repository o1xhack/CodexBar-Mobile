# v0.35.0 Upstream Sync Testing

Status: `done`
Date: 2026-06-14
Branch: `upstream-sync/v0.35.0-mobile.1.12.0`

## Required Gates

- Mac build and relevant unit tests.
- Mac menu/provider regression checks for upstream `v0.32.5..v0.35.0`.
- Parser/pricing hash verification if CostUsage parser or pricing changed.
- iOS build and relevant tests.
- 4-language localization check for new iOS strings.
- CloudKit Production schema audit.
- `docs/ios-sync-compatibility-testing.md` 2 Mac x 2 iPhone compatibility gate.
- Final diff review with blocking issues fixed.

## CloudKit Production Schema Audit

Status: complete. No CloudKit Production schema deploy is required for this
branch.

Last non-draft release tag used for comparison:

```text
v0.32.5.1-mobile.1.12.0
```

Audit commands and outcomes:

```text
LAST_TAG=$(gh release list --repo o1xhack/CodexBar-Mobile --limit 5 --json tagName,isDraft | python3 -c 'import json,sys;[print(r["tagName"]) for r in json.load(sys.stdin) if not r["isDraft"]][0]')
git diff $LAST_TAG..HEAD 2>&1 | grep -E "^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)"
Result: no schema keyword changes outside docs/research/changelog.

git diff $LAST_TAG..HEAD -- Shared/iCloud/CloudConstants.swift
Result: no changes.

git diff $LAST_TAG..HEAD -- Shared/Models/UsageSnapshot.swift | grep -E "^\+.*public let|^-.*public let"
Result: no public field delta versus the last non-draft release tag. Against
origin/mobile-dev the only new fields are optional JSON payload fields
subscriptionExpiresAt and subscriptionRenewsAt.
```

Verdict: this release only preserves additive optional keys inside the existing
opaque provider payload. Devin was added to the client-side quota provider
catalog, which creates subscriptions using the existing `QuotaTransition`
record/zone naming contract. There are no new CloudKit record types, top-level
fields, zones, indexes, or encoding-version changes.

## 2 Mac x 2 iPhone Old/New Compatibility Matrix

Definitions for this release:

- Old Mac: shipped baseline before this branch, `0.32.4.1` / `1.11.1` appcast
  line. The prior `0.32.5.1` release exists but was not merged to `mobile-dev`;
  compatibility notes must explicitly account for it if used as a QA old/new
  stand-in.
- New Mac: target branch build `0.35.0.1`.
- Old iPhone: shipped `1.11.1`.
- New iPhone: target branch build `1.12.0 (153)`.

The matrix is required because this release changes provider display data and
is expected to add or preserve optional Shared payload fields.

| Case | Mac A | Mac B | iPhone A | iPhone B | Expected | Result | Evidence |
|---:|---|---|---|---|---|---|---|
| 01 | Old | Old | Old | Old | Existing shipped behavior unchanged | Baseline carryforward | No branch code participates; released baseline behavior is unchanged by this sync branch. |
| 02 | Old | Old | Old | New | New iPhone decodes old payloads | Substituted pass | `SyncModelTests`, `CloudKitMergeTests`, and SwiftData optional-nil coverage verify old payload decode. |
| 03 | Old | Old | New | Old | Same as case 02 with phone order swapped | Substituted pass | Same decode path as case 02; phone order does not affect CloudKit record shape. |
| 04 | Old | Old | New | New | Both new phones decode old Mac payloads | Substituted pass | Same old-payload decode tests; iOS xcodebuild test suite passed on the target app. |
| 05 | Old | New | Old | Old | Old phones ignore new optional fields from one Mac | Substituted pass | Additive JSON-only keys; Swift Codable ignores unknown keys; CloudKit schema audit shows no record/schema change. |
| 06 | Old | New | Old | New | New phone renders new metadata; old phone remains stable | Substituted pass | New iOS decode/merge/render tests cover metadata; old iOS stability follows additive optional JSON/no-schema-change audit. |
| 07 | Old | New | New | Old | Same as case 06 with phone order swapped | Substituted pass | Same as case 06; phone order does not alter provider payload merge. |
| 08 | Old | New | New | New | Both phones merge old/new Macs without field loss | Substituted pass | `CloudKitMergeTests` preserves latest non-nil metadata; SwiftData full payload bridge round trip preserves rich fields. |
| 09 | New | Old | Old | Old | Same as case 05 with Mac order swapped | Substituted pass | Same additive-key/no-schema-change evidence as case 05. |
| 10 | New | Old | Old | New | Same as case 06 with Mac order swapped | Substituted pass | Same mixed old/new decode and render evidence as case 06. |
| 11 | New | Old | New | Old | Same as case 07 with Mac order swapped | Substituted pass | Same mixed old/new decode and render evidence as case 07. |
| 12 | New | Old | New | New | Same as case 08 with Mac order swapped | Substituted pass | Same merge/SwiftData preservation evidence as case 08. |
| 13 | New | New | Old | Old | Old phones ignore new optional fields from both Macs | Substituted pass | Two new Macs still emit the same additive optional JSON keys; no CloudKit schema change. |
| 14 | New | New | Old | New | New phone renders all new data; old phone stable | Substituted pass | New iOS render tests and iOS xcodebuild suite passed; old app risk limited to unknown JSON keys. |
| 15 | New | New | New | Old | Same as case 14 with phone order swapped | Substituted pass | Same as case 14; phone order does not affect shared CloudKit records. |
| 16 | New | New | New | New | Full new behavior on all devices | Substituted pass | Mac sync mapping, iOS merge/cache/render, SwiftData full payload round trip, localization, and iOS suite passed. |

Residual QA risk: this matrix has not been run on two physical Macs and two
physical iPhones in a live iCloud account during this implementation pass. The
automated substitution proves wire compatibility, decode behavior, merge
preservation, cache persistence, and UI rendering, but real-device CloudKit
push timing and account convergence should still be checked during manual QA.

## Test Evidence

Mac checks:

```text
swift build
Result: passed.

39-shard SwiftPM test suite
Result: passed, RC=0.
Log: /tmp/codexbar-swift-shards-20260614-rerun.log

swift test --filter StatusMenuTokenAccountSwitcherTests
Result: passed, 8 tests.

swift test --filter SyncMultiAccountEdgeCasesTests
Result: passed, 10 tests.

swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'
Result: passed, 81 tests.

swift test --filter SyncCoordinatorTests
Result: passed, 23 tests.

swift test --filter SyncCoordinatorTests/l1DeleteFailurePreservesRetry
Result: passed.

swift test --filter CostUsageCacheTests
Result: passed, 16 tests.

swift test --filter AccountIdentityComputerTests
Result: passed, 15 tests.

swift test --filter 'MiniMaxMenuCardModelPlanTests|MockProviderInjectorTests|MockProviderInjectorIntegrationTests|QuotaProviderListTests'
Result: passed, 72 tests across 4 suites.
```

Known non-regression note: one bare `swift test` run hit the existing
`SyncCoordinatorTests/l1DeleteFailurePreservesRetry` L1 retry flake documented
in the release checklist. The focused test passed, and the subsequent sharded
suite passed cleanly.

iOS checks:

```text
cd CodexBarMobile && xcodegen generate
Result: passed.

xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test
Result: ** TEST SUCCEEDED **, 441 unit tests in 35 suites plus 3 UI tests passed.
xcresult: /Users/yuxiao/Library/Developer/Xcode/DerivedData/CodexBarMobile-fywzrshyicotmkhjufflfswwbceb/Logs/Test/Test-CodexBarMobile-2026.06.14_17-14-51--0700.xcresult

./Scripts/upload_ios_testflight.sh
Result: passed. Pre-flight lint passed, archive succeeded, export/upload
succeeded, and App Store Connect accepted the uploaded package for processing.
Uploaded build: CodexBarMobile 1.12.0 (153).
Archive: /tmp/CodexBarMobile-20260614-174608.xcarchive
```

Release and lint gates:

```text
bash Scripts/lint.sh lint
Result: passed. SwiftFormat clean, SwiftLint 0 violations, iOS i18n audit clean,
iOS source-vs-catalog audit clean, parser-version audit clean.

plutil -lint Sources/CodexBar/Resources/*.lproj/Localizable.strings
Result: passed for all Mac localization files.

git diff --check
Result: passed.

bash Scripts/regenerate-codex-parser-hash.sh --check
Result: passed. Hash c87a61d15e601949 is current.

bash -n Scripts/package_app.sh
bash -n Scripts/sign-and-notarize.sh
bash -n Scripts/lint.sh
Result: passed.
```

## Review

Current review findings fixed during testing:

- Added missing Turkish localization keys introduced by upstream resources.
- Removed Swift warnings in `PreferencesMobilePane` and
  `SyncMultiAccountEdgeCasesTests`.
- Fixed MiniMax menu-card date localization to use the app's localized locale.
- Backported upstream token-account scoped-cache fix for the menu selection
  race found by `StatusMenuTokenAccountSwitcherTests`.
- Fixed review finding: SwiftData cold-start hydration now preserves the full
  rich provider payload instead of reconstructing only subset fields.
- Fixed review finding: Mac MiniMax subscription and unlimited-plan text is
  localized in all Mac resource bundles.
- Added Devin iOS quota-provider/color/mock coverage found during the review
  pass.

Blocking review findings were fixed and retested before packaging.

## Mac Release Evidence

Mac release status: live.

```text
./Scripts/release.sh
Result: phase1 passed. Signed, notarized, stapled, packaged, pushed tag
v0.35.0.1-mobile.1.12.0, and created the draft release.
Notarization submission: 0ced6380-2c07-4b02-9976-1792e5e675d6
Notarization result: Accepted.

./Scripts/release.sh --finalize
Result: phase2 passed. Published the draft, generated signed appcast.xml,
committed docs: update appcast for 0.35.0.1, and pushed mobile-dev.

gh release view v0.35.0.1-mobile.1.12.0 --repo o1xhack/CodexBar-Mobile
Result: public, non-draft release with zip and dSYM assets.

Remote appcast parse
Result: title 0.35.0.1, sparkle:version 85.1.1.12.0,
sparkle:shortVersionString 0.35.0.1, release zip URL and signature present.

codesign --verify --deep --strict --verbose=2 /Applications/CodexBar.app
spctl --assess --type execute --verbose /Applications/CodexBar.app
Result: valid on disk, satisfies designated requirement, accepted as
Notarized Developer ID.

codesign -d --entitlements :- /Applications/CodexBar.app
Result: com.apple.developer.icloud-container-environment = Production.

/Applications/CodexBar.app/Contents/Info.plist
Result: CFBundleShortVersionString 0.35.0.1, CFBundleVersion 85.1.1.12.0.
```
