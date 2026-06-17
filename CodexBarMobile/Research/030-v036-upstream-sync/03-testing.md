# v0.36.1 Upstream Sync Testing

Status: `done`
Date: 2026-06-16
Branch: `upstream-sync/v0.36.1-mobile.1.13.0`

## Required Gates

- Mac build and lint.
- Full or sharded Mac test suite.
- Focused provider and registry tests for LiteLLM, Poe, Chutes, Zed,
  Antigravity, Copilot, process cleanup, and provider icon/resources.
- Parser/pricing hash verification if `CostUsageScanner.swift` or pricing logic
  changes require it.
- iOS project generation, build, and relevant tests.
- iOS four-language localization audit.
- CloudKit Production schema audit.
- 2 Mac x 2 iPhone old/new sync compatibility matrix.
- Final diff review with blocking issues fixed.

## CloudKit Production Schema Audit

Status: complete. Verdict: no CloudKit Production schema deploy is needed.

Audit commands:

```text
LAST_TAG=$(gh release list --repo o1xhack/CodexBar-Mobile --limit 10 --json tagName,isDraft | python3 -c 'import json,sys; tags=[r["tagName"] for r in json.load(sys.stdin) if not r["isDraft"]]; print(tags[0])')
git diff $LAST_TAG..HEAD 2>&1 | grep -E "^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)"
git diff $LAST_TAG..HEAD -- Shared/iCloud/CloudConstants.swift
git diff $LAST_TAG..HEAD -- Shared/Models/UsageSnapshot.swift | grep -E "^\+.*public let|^-.*public let"
```

Result:

```text
LAST_TAG=v0.35.0.1-mobile.1.12.0

-- schema keyword additions --

-- CloudConstants diff --

-- UsageSnapshot public field additions/removals --
```

Interpretation:

- no `CKRecord` type, `CKRecordZone`, index, subscription, or payload-version
  addition appears in the release diff;
- `Shared/iCloud/CloudConstants.swift` is unchanged;
- `Shared/Models/UsageSnapshot.swift` has no public-field additions/removals;
- new provider values stay inside the existing compressed provider payload and
  existing quota-transition zone pattern.

Therefore this release does not require CloudKit Dashboard schema deploy.

## 2 Mac x 2 iPhone Old/New Compatibility Matrix

Definitions for this release:

- Old Mac: shipped baseline before this branch, `0.35.0.1` / Sparkle
  `85.1.1.12.0`.
- New Mac: target branch build `0.36.1.1` / Sparkle `88.1.1.13.0`.
- Old iPhone: shipped `1.12.0`.
- New iPhone: target branch build `1.13.0 (154)`.

The matrix applies because this release changes provider display data and may
touch Shared payload/rendering paths for new provider identities and structured
rate windows.

Real 2 Mac x 2 iPhone hardware mixing was not executed because this branch has
not produced or published draft/release artifacts, and the Goal forbids tag
publish, push, live release, and TestFlight upload without explicit
confirmation. The matrix below records substituted validation and residual risk
for each combination.

Shared substitute evidence:

- CloudKit schema audit is empty; no new record type/field/index/subscription is
  required.
- `UsageSnapshot` public field shape is unchanged, so old/new payload decoding
  remains additive.
- New provider support uses existing generic provider payload fields; Poe was
  bridged into generic `RateWindow` rows rather than adding a Poe-only wire
  field.
- Mac full sharded suite passes, including sync and quota-warning push tests.
- iOS simulator suite passes 487 tests, including provider list, colors,
  decoding, and UI tests.

| Case | Mac A | Mac B | iPhone A | iPhone B | Expected | Result | Evidence |
|---:|---|---|---|---|---|---|---|
| 01 | Old | Old | Old | Old | Existing shipped behavior unchanged | Carryforward pass | Previously shipped `0.35.0.1` / `1.12.0`; no branch artifact involved. |
| 02 | Old | Old | Old | New | New iPhone decodes old payloads | Substituted pass | iOS 487-test suite plus unchanged `UsageSnapshot` field audit. |
| 03 | Old | Old | New | Old | Same as case 02 with phone order swapped | Substituted pass | Same decode path as case 02; no phone-order-specific code. |
| 04 | Old | Old | New | New | Both new phones decode old Mac payloads | Substituted pass | Same decode path as case 02 for both phones. |
| 05 | Old | New | Old | Old | Old phones ignore any new optional/display fields from one Mac | Substituted pass | No new shared public fields; new providers use existing payload envelope. |
| 06 | Old | New | Old | New | New phone renders new provider data; old phone remains stable | Substituted pass | Mac sync tests, iOS provider color/list tests, Poe generic-window tests. |
| 07 | Old | New | New | Old | Same as case 06 with phone order swapped | Substituted pass | Same payload/render paths as case 06; phone order is not semantically used. |
| 08 | Old | New | New | New | Both phones merge old/new Macs without field loss | Substituted pass | Existing latest-non-nil merge tests plus unchanged shared shape. |
| 09 | New | Old | Old | Old | Same as case 05 with Mac order swapped | Substituted pass | Mac order does not change CloudKit record schema or decode path. |
| 10 | New | Old | Old | New | Same as case 06 with Mac order swapped | Substituted pass | Same as case 06; old Mac simply omits new provider data. |
| 11 | New | Old | New | Old | Same as case 07 with Mac order swapped | Substituted pass | Same as case 07; no order-dependent logic. |
| 12 | New | Old | New | New | Same as case 08 with Mac order swapped | Substituted pass | Same as case 08; additive generic fields only. |
| 13 | New | New | Old | Old | Old phones ignore new optional/display fields from both Macs | Substituted pass | No new wire fields; old phones may not subscribe to the four new provider zones until upgraded. |
| 14 | New | New | Old | New | New phone renders all new provider data; old phone stable | Substituted pass | New iOS provider catalog covers 53 providers / 159 quota zones. |
| 15 | New | New | New | Old | Same as case 14 with phone order swapped | Substituted pass | Same as case 14; phone order is not semantically used. |
| 16 | New | New | New | New | Full new behavior on all devices | Substituted pass | Mac full suite, iOS simulator suite, lint/i18n, and CloudKit audit all pass. |

Residual risk: old iOS 1.12.0 builds do not know the four newly appended provider
quota zones, so push quota transitions for LiteLLM/Poe/Chutes/Zed are expected
to be visible only after iPhone upgrade. This is an additive subscription-list
gap, not a decode or schema break.

## Test Evidence

### Mac

```text
swift build
Result: Passed.

swift test --filter 'PoeUsageFetcherTests|QuotaProviderListTests|MockProviderInjectorTests|MockProviderInjectorIntegrationTests|MockProviderAdvancedScenariosTests|ProviderColorPaletteTests'
Result: Passed, 97 tests.

swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'
Result: Passed, 81 tests in 13 suites.

node Scripts/check-app-locales.mjs
Result: app locales OK: 3 complete catalogs, 1076 keys.

swift test --filter LocalizationLanguageCatalogTests
Result: Passed, 18 tests.

./Scripts/lint.sh lint
Result: Passed.
- app locales OK: 3 complete catalogs, 1076 keys
- site locales OK: 21 locales, 50 messages
- SwiftFormat: 0 files require formatting
- SwiftLint: 0 violations in 1182 files
- iOS xcstrings: all locales translated, all 330 source keys present
- parser hash: 72dddb100a729cd3

./Scripts/test.sh
Result: Passed. 43/43 shards passed.
Log: /tmp/codexbar-test-full.log
```

Regressions found and fixed during the test loop:

- `MenuCardView+ModelHelpers.subscriptionDateString` now follows upstream's
  `Locale.current` test contract while preserving MiniMax Asia/Shanghai date
  formatting.
- Quota-warning CloudKit push writes are restored when
  `notificationPushToiOSEnabled` is true.
- Token-account sync sentinel updated for LiteLLM as the only new token-account
  catalog provider in v0.36.1.

### iOS

```text
cd CodexBarMobile && xcodegen generate
Result: CodexBarMobile.xcodeproj regenerated.

XcodeBuildMCP build_sim
Project: CodexBarMobile/CodexBarMobile.xcodeproj
Scheme: CodexBarMobile
Simulator: iPhone 17 Pro, iOS 26.5
Extra args: -skipPackagePluginValidation
Result: SUCCEEDED
Log: /Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/logs/build_sim_2026-06-16T22-10-02-526Z_pid96757_e69bb266.log

XcodeBuildMCP test_sim
Project: CodexBarMobile/CodexBarMobile.xcodeproj
Scheme: CodexBarMobile
Simulator: iPhone 17 Pro, iOS 26.5
Extra args: -skipPackagePluginValidation
Result: SUCCEEDED, 487 passed, 0 failed
Log: /Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/logs/test_sim_2026-06-16T22-10-19-300Z_pid96757_28241510.log
Result bundle: /Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/result-bundles/test_sim_2026-06-16T22-10-19-301Z_pid96757_21e17960.xcresult
```

## Review

Self-review completed against the merge diff:

- checked for unresolved conflict markers;
- checked CloudKit schema diff;
- checked version targets in `version.env` and `CodexBarMobile/project.yml`;
- checked iOS release notes and four-language strings;
- fixed the blocking test regressions listed above.

External/agent review completed. Findings:

- draft-release creation is blocked pending explicit authorization because
  `Scripts/release.sh` phase 1 pushes tag `v0.36.1.1-mobile.1.13.0` and uploads
  draft-release assets;
- CloudKit audit evidence command needed the corrected one-tag `LAST_TAG`
  expression above; no actual schema deploy requirement was found.

## Mac Release Evidence

Local signing/notarization was completed without pushing a tag or creating a
GitHub release:

```text
./Scripts/sign-and-notarize.sh
Result: Passed.
Apple notarization submission: 387ecffb-5318-4a6e-9657-66b11c02cb26
Apple notarization status: Accepted
Staple/validate on staged app: OK
Launch verification: OK
Artifacts:
- CodexBar-0.36.1.1-mobile.1.13.0.zip (51M)
- CodexBar-0.36.1.1-mobile.1.13.0.dSYM.zip (32M)
```

Release ZIP verification:

```text
plutil -p <unzipped>/CodexBar.app/Contents/Info.plist
Result: CFBundleShortVersionString=0.36.1.1, CFBundleVersion=88.1.1.13.0,
        SUFeedURL=https://raw.githubusercontent.com/o1xhack/CodexBar-Mobile/mobile-dev/appcast.xml

codesign -dvvv <unzipped>/CodexBar.app
Result: Developer ID Application: Yuxiao Wang (3TUERHN53E), TeamIdentifier=3TUERHN53E

spctl -a -t exec -vv <unzipped>/CodexBar.app
Result: accepted, source=Notarized Developer ID

stapler validate <unzipped>/CodexBar.app
Result: The validate action worked.
```

GitHub draft release is not complete. `Scripts/release.sh` phase 1 was
inspected. It performs the full sign/notarize/draft flow, but also:

- requires a clean worktree;
- creates annotated tag `v0.36.1.1-mobile.1.13.0`;
- pushes that tag to `origin`;
- uploads ZIP and dSYM ZIP assets;
- creates a GitHub draft release.

Because this Goal explicitly forbids tag publish, push, live release, and
TestFlight upload without confirmation, the GitHub draft-release step remains
pending user confirmation. No live release, tag push, GitHub draft, appcast push,
merge, or TestFlight upload has been performed.
