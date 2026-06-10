# v0.32.5 Upstream Sync Testing

Status: `in-progress`
Date: 2026-06-10
Branch: `upstream-sync/v0.32.5-mobile.1.12.0`

## Required Gates

- Mac build and relevant unit tests.
- Mac menu/provider regression checks for upstream v0.32.5 focus areas.
- Parser/pricing hash verification for models.dev memoization.
- iOS build and relevant tests.
- 4-language localization check for new iOS strings.
- CloudKit Production schema audit.
- `docs/ios-sync-compatibility-testing.md` 2 Mac x 2 iPhone compatibility gate.
- Final diff review with blocking issues fixed.

## CloudKit Production Schema Audit

Result: no deploy required. The only Shared model additions are optional fields
inside the existing encoded provider payload; no CloudKit record types, zones,
subscriptions, top-level fields, or index-affecting predicates changed.

| Check | Result | Evidence |
|---|---|---|
| New CK record type | Pass | `git diff v0.32.4.1-mobile.1.11.0 -- Shared/iCloud/CloudConstants.swift` produced no diff. |
| New CK field/index predicate | Pass | Grep for added `recordType`, `CKRecordZone`, `CKSubscription`, `setObject`, and indexed predicate changes produced no schema-relevant additions. |
| New zone/subscription | Pass | No added zone/subscription definitions. |
| Opaque payload-only additions | Pass | Diff only adds `ProviderUsageSnapshot.subscriptionExpiresAt` and `subscriptionRenewsAt`; both decode via `decodeIfPresent`. |
| Deploy needed? | No | Production schema deploy is not required for additive optional JSON/Data payload keys. |

Commands:

```text
gh release list --repo o1xhack/CodexBar-Mobile --limit 5
git diff v0.32.4.1-mobile.1.11.0 -- Shared/iCloud/CloudConstants.swift
git diff v0.32.4.1-mobile.1.11.0 -- Shared/Models/UsageSnapshot.swift | \
  grep -E '^+.*public let|^-.*public let|^+.*CodingKeys|^-.*CodingKeys|^+.*decode|^-.*decode'
rg -n 'subscriptionExpiresAt|subscriptionRenewsAt' Shared/Models/UsageSnapshot.swift \
  CodexBarMobile/Shared/Models/UsageSnapshot.swift
```

## 2 Mac x 2 iPhone Old/New Compatibility Matrix

Definitions for this release:

- Old Mac: shipped `0.32.4.1` baseline.
- New Mac: branch build `0.32.5.1`.
- Old iPhone: shipped `1.11.1`.
- New iPhone: branch build `1.12.0`.

The matrix is required because the release adds Shared sync payload fields and
changes provider rendering data. A physical 2 Mac x 2 iPhone lab was not run in
this session. The table therefore records substituted verification against the
same compatibility risks:

- E1: old payload decoding test (`SyncModelTests`) proves new iOS accepts old
  Mac payloads with missing subscription keys.
- E2: Swift Codable/additive JSON behavior plus optional fields proves old iOS
  ignores new keys from new Mac payloads.
- E3: `CloudKitMergeTests.sameProviderPreservesSubscriptionMetadata` proves one
  old Mac plus one new Mac cannot erase subscription metadata.
- E4: `SwiftDataBridgeTests.testSubscriptionMetadataRoundTrip` proves local iOS
  cache/relaunch path preserves new metadata.
- E5: iOS simulator build and focused test suite prove new iOS UI/model path
  compiles and passes.
- E6: CloudKit schema audit proves all combinations share the same Production
  schema and do not require deploy.

| Case | Mac A | Mac B | iPhone A | iPhone B | Expected | Result | Evidence |
|---:|---|---|---|---|---|---|---|
| 01 | Old | Old | Old | Old | Existing 0.32.4.1 / 1.11.1 behavior unchanged | Substituted pass | No schema change (E6); no old-code changes executed. |
| 02 | Old | Old | Old | New | New iPhone decodes old payload, subscription fields nil | Pass | Old JSON decode coverage in `SyncModelTests` (E1, E5). |
| 03 | Old | Old | New | Old | Same as case 02, both phones stable | Pass | Same decode path as case 02; phone order does not change payload (E1, E5, E6). |
| 04 | Old | Old | New | New | Both new phones decode old Mac payload | Pass | Same old-payload decode path on two new clients (E1, E5). |
| 05 | Old | New | Old | Old | Old phones ignore new fields from one Mac | Substituted pass | Additive JSON optional fields; no schema change (E2, E6). |
| 06 | Old | New | Old | New | New phone uses latest non-nil new fields; old phone remains stable | Pass | Old/new merge test preserves metadata; additive old-client path (E2, E3, E5). |
| 07 | Old | New | New | Old | Same as case 06 with phone order swapped | Pass | Same merge and additive decode behavior; client order independent (E2, E3, E5). |
| 08 | Old | New | New | New | Both phones merge old/new Macs without field loss | Pass | Merge preservation plus cache round-trip on new iOS (E3, E4, E5). |
| 09 | New | Old | Old | Old | Same as case 05 with Mac order swapped | Substituted pass | Additive JSON optional fields; Mac order does not change old-client ignore behavior (E2, E6). |
| 10 | New | Old | Old | New | Same as case 06 with Mac order swapped | Pass | `latestNonNil` merge handles swapped provider entry order (E3, E5). |
| 11 | New | Old | New | Old | Same as case 07 with Mac order swapped | Pass | Same as case 10; phone order independent (E2, E3, E5). |
| 12 | New | Old | New | New | Same as case 08 with Mac order swapped | Pass | Merge preservation plus cache round-trip on new iOS (E3, E4, E5). |
| 13 | New | New | Old | Old | Old phones ignore new fields from both Macs | Substituted pass | Additive JSON optional fields; no Production schema change (E2, E6). |
| 14 | New | New | Old | New | New phone renders subscription metadata; old phone stable | Pass | New iOS UI/model tests plus additive old-client path (E2, E4, E5). |
| 15 | New | New | New | Old | Same as case 14 with phone order swapped | Pass | Same as case 14; client order independent (E2, E4, E5). |
| 16 | New | New | New | New | Full new behavior on all devices | Pass | New payload, SwiftData, merge, localization, build, and focused tests pass (E3, E4, E5). |

## Test Evidence

### Build and Lint

```text
swift build
Result: passed.

bash Scripts/lint.sh lint
Result: passed.
SwiftFormat: 0/1067 files require formatting.
SwiftLint: 0 violations in 1066 files.
i18n audit: all 324 source keys present; no missing translations.
parser hash: dd86017647affbc8.

git diff --check
Result: passed.

jq empty CodexBarMobile/CodexBarMobile/Localizable.xcstrings
Result: passed.
```

`plutil -lint` was not used as the final `.xcstrings` validator because this
machine's `plutil` rejects JSON `.xcstrings` with `Unexpected character { at
line 1`; `jq` and the Xcode build cover syntax here.

### Mac Tests

```text
swift test --filter SyncCoordinatorTests
Result: passed. 23 tests in 1 suite.

swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'
Result: passed. 81 tests in 13 suites.

swift test --filter MiniMax
Result: passed. 96 tests in 15 suites.

swift test --filter 'ModelsDevPricing|LocalizationLanguageCatalog|LocalizationBundleCache|MenuCardHeightFingerprint|StatusMenuHeightCache|StatusMenuReadinessBaseline|StatusItemIconObservation|CursorMenuCardModel|AntigravityStatusProbe|CodexAccountRefreshProjection'
Result: passed. 112 tests in 9 suites.
```

Full `swift test` was also attempted. It hit the known parallel-suite
`SyncCoordinatorTests` L1 retry flake documented in the release checklist:
`L1: delete failure does NOT advance lastPushedRecordNames (retries next cycle)`
expected delete count `2` but saw `1`, followed by a Swift Testing runner
`Index out of range`. The isolated suite passes, so this is recorded as the
known full-suite runner/parallelism risk rather than a v0.32.5 regression.

### iOS Build and Tests

```text
cd CodexBarMobile && xcodegen generate
Result: passed.

xcodebuild test -project CodexBarMobile/CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -destination 'id=E1DD6B03-ACA4-4962-BA33-AF21EFB1B2BB' \
  -only-testing:CodexBarMobileTests/SyncModelTests \
  -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/SwiftDataBridgeTests
Result: passed. 67 tests in 3 suites.

xcodebuild test -project CodexBarMobile/CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -destination 'id=E1DD6B03-ACA4-4962-BA33-AF21EFB1B2BB' \
  -only-testing:CodexBarMobileTests/CWLMigrationTests \
  -only-testing:CodexBarMobileTests/CWLSchemaTests \
  -only-testing:CodexBarMobileTests/ModelContainerFactoryTests
Result: passed. 9 tests in 3 suites.

xcodebuild build -project CodexBarMobile/CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -destination 'id=E1DD6B03-ACA4-4962-BA33-AF21EFB1B2BB'
Result: passed.
```

The simulator build emitted Production CloudKit entitlements for the app and
push extension, matching the project release requirement.

### Mac Draft Release Preflight

No remote write actions were run in this pass because `./Scripts/release.sh`
phase 1 pushes the release tag and creates a GitHub draft release. The current
Goal explicitly forbids tag publish / push unless the user confirms it in the
target run.

Local/read-only preflight:

```text
git status --short --branch
Result: clean branch upstream-sync/v0.32.5-mobile.1.12.0 at 29a2dc5b.

bash Scripts/validate_changelog.sh 0.32.5.1
Result: Changelog OK for 0.32.5.1.

bash Scripts/changelog-to-html.sh 0.32.5.1
Result: generated notes headed "CodexBar 0.32.5.1-Mobile 1.12.0" and extracted
the fork sync notes.

source Scripts/sparkle_helpers.sh
ensure_appcast_monotonic appcast.xml 0.32.5.1 80.1
Result: appcast monotonic OK: new 0.32.5.1 / 80.1 is greater than all existing entries.

gh release view v0.32.5.1-mobile.1.12.0 --repo o1xhack/CodexBar-Mobile
Result: release not found.

git tag --list v0.32.5.1-mobile.1.12.0
git ls-remote --tags origin refs/tags/v0.32.5.1-mobile.1.12.0
Result: no local or remote release tag exists yet.

ls .build/artifacts/sparkle/Sparkle/bin
Result: generate_appcast and sign_update are present.
```

Expected phase 1 asset names:

```text
CodexBar-0.32.5.1-mobile.1.12.0.zip
CodexBar-0.32.5.1-mobile.1.12.0.dSYM.zip
```

### iOS Compatibility Tests Added

- `SyncModelTests`: subscription metadata round-trips, and old JSON without the
  new keys decodes with nil optional values.
- `CloudKitMergeTests.sameProviderPreservesSubscriptionMetadata`: an old Mac
  snapshot with fresher usage cannot erase subscription metadata from a new Mac
  snapshot.
- `SwiftDataBridgeTests.testSubscriptionMetadataRoundTrip`: SwiftData mirror
  persists and restores subscription metadata.

### Not Executed

- Physical four-device iCloud propagation test on two Macs and two iPhones.
- Real provider probes against live accounts.
- Signed/notarized Mac draft release packaging.

These require physical devices and/or release credentials. The code-level and
simulator-level compatibility risks are covered above; remaining risk is limited
to real CloudKit propagation timing, physical device UI rendering, and release
packaging credentials.

## Review

Local self-review completed over the fork-specific diff:

- Confirmed no merge conflict markers remain.
- Confirmed Shared model copies stay aligned.
- Confirmed new fields are optional/additive and do not require CloudKit schema
  deploy.
- Confirmed iOS merge/cache paths preserve subscription metadata and do not drop
  other rich optional provider fields during old/new Mac merges.
- Confirmed new iOS strings are localized in the required four languages.

Blocking code issues found during review:

1. `ProviderUsageView` initially used `Date.FormatStyle` with a `TimeZone` value
   and failed iOS compilation. Fixed by using `DateFormatter` with explicit
   timezone selection.
2. Parser hash mismatch after upstream merge. Fixed by regenerating
   `CodexParserHash.generated.swift`.
3. `MiniMax` Mac tests were region-sensitive because
   `MenuCardModelTests` expected an English renewal date while product code
   intentionally uses `Locale.current`. Fixed the test to generate the expected
   date from the current locale and MiniMax timezone, preserving product
   localization behavior.

Open release boundary:

- Mac draft release packaging is still pending and should be run only after
  explicit confirmation for release credentials / remote draft-release actions.
