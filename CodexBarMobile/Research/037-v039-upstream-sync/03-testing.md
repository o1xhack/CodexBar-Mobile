# v0.39.0 Upstream Sync Testing

Status: `in-progress`
Date: 2026-07-04
Branch: `upstream-sync/v0.39.0-mobile.1.17.0`

## Required Gates

- Mac build and lint.
- Full or sharded Mac test suite.
- Focused provider tests for new providers and changed providers:
  `sakana`, `qoder`, `crossmodel`, `clawrouter`, Codex, Claude, Kimi, Mistral,
  Doubao, OpenCode, OpenAI, Alibaba, and Keychain no-prompt safety.
- Parser version/hash gate for changed `CostUsageScanner*` and cost cache code.
- `swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'`.
- iOS project generation, build, and relevant tests.
- iOS four-language localization audit.
- CloudKit Production schema audit.
- 2 Mac x 2 iPhone old/new compatibility matrix because this release changes
  provider display data and likely Shared payload/rendering paths.
- Final diff review with all blocking issues fixed.

## CloudKit Production Schema Audit

Status: completed with no Production deploy required.

Latest published fork release from `gh release list`:

```text
v0.37.2.1-mobile.1.15.0
publishedAt: 2026-06-24T20:57:30Z
```

Worktree-inclusive pre-commit audit:

```text
git diff v0.37.2.1-mobile.1.15.0 -- ':(exclude)docs' ':(exclude)CodexBarMobile/Research' | grep -E "^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)"
# no code output

git diff v0.37.2.1-mobile.1.15.0 -- Shared/iCloud/CloudConstants.swift
# no output

git diff v0.37.2.1-mobile.1.15.0 -- Shared/Models/UsageSnapshot.swift | grep -E "^\+.*public let|^-.*public let"
+    public let crossModelUsage: SyncCrossModelUsage?
```

Notes:

- The only Shared model surface addition is an optional payload-internal JSON
  field decoded with `decodeIfPresent`.
- `CloudConstants.swift` did not change.
- No code diff added a CloudKit record type, zone, subscription, index,
  `providerPayloadVersion`, or `encodingVersion` change.

Verdict: no CloudKit Dashboard deploy required for this release.

Post-commit documented audit form matched the same result:

```text
git diff v0.37.2.1-mobile.1.15.0..HEAD -- Shared/iCloud/CloudConstants.swift
# no output

git diff v0.37.2.1-mobile.1.15.0..HEAD -- Shared/Models/UsageSnapshot.swift | grep -E "^\+.*public let|^-.*public let"
+    public let crossModelUsage: SyncCrossModelUsage?

git diff v0.37.2.1-mobile.1.15.0..HEAD -- ':(exclude)docs' ':(exclude)CodexBarMobile/Research' | grep -E "^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|encodingVersion)"
# no code output
```

## 2 Mac x 2 iPhone Old/New Compatibility Matrix

Definitions for this release:

- Old Mac: latest published fork Mac, `0.37.2.1` / Sparkle `92.1.1.15.0`.
- New Mac: target branch build `0.39.0.1` / Sparkle `97.1.1.17.0`.
- Old iPhone: current `1.16.0` shipped/TestFlight line before this branch.
- New iPhone: target branch build `1.17.0`.

This matrix applies because the release changes provider display data, new
providers, Shared payload candidate fields, cache/parser behavior, and
cross-version rendering.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 01 | old | old | old | old | substituted-pass | Latest published release `v0.37.2.1-mobile.1.15.0`; no baseline schema change. | Shipped behavior used as baseline. |
| 02 | old | old | old | new | substituted-pass | iOS simulator full test scheme; old-payload decode tests. | New iOS decodes old optional-missing payloads. |
| 03 | old | old | new | old | substituted-pass | Same evidence as case 02. | Phone role order does not affect payload decode. |
| 04 | old | old | new | new | substituted-pass | iOS simulator full test scheme; old-payload decode tests. | Both new phones should render old visible state. |
| 05 | old | new | old | old | substituted-pass | `ProviderUsageSnapshot` unknown-field tolerance; optional `crossModelUsage`; no `providerPayloadVersion` bump. | Old iOS should ignore unknown top-level payload field. |
| 06 | old | new | old | new | substituted-pass | Sync mapper + wire-format tests; iOS full simulator test. | Mixed read path covered by old/new optional decode. |
| 07 | old | new | new | old | substituted-pass | Same evidence as case 06. | Phone role order does not affect merge/read behavior. |
| 08 | old | new | new | new | substituted-pass | Sync mapper + wire-format tests; iOS full simulator test. | Both new phones converge on mixed writers in code-level substitute. |
| 09 | new | old | old | old | substituted-pass | Same evidence as case 05. | Mac writer order does not affect payload compatibility. |
| 10 | new | old | old | new | substituted-pass | Same evidence as case 06. | Mac writer order does not affect mixed read path. |
| 11 | new | old | new | old | substituted-pass | Same evidence as case 07. | Mac/phone order swapped. |
| 12 | new | old | new | new | substituted-pass | Same evidence as case 08. | Mac writer order swapped. |
| 13 | new | new | old | old | substituted-pass | Optional payload and unknown-field tolerance; CloudKit schema audit. | Highest old-iOS risk remains real-device old-build rendering, not schema. |
| 14 | new | new | old | new | substituted-pass | Sync mapper + wire-format tests; iOS simulator full test. | Mixed phone rendering covered by substitute only. |
| 15 | new | new | new | old | substituted-pass | Same evidence as case 14. | Phone roles swapped. |
| 16 | new | new | new | new | substituted-pass | XcodeBuildMCP iOS simulator full test, CrossModel card tests, sync mapper tests. | Full new-stack path covered by simulator substitute. |

Substitution policy:

- Use `substituted` only when real 2 Mac x 2 iPhone hardware is unavailable.
- Each substituted row must name the replacement evidence: old/new payload
  decode tests, mock CloudKit records, simulator builds/tests, code audit,
  focused sync/account tests, or manual QA notes.
- Residual risk must be explicit for silent push delivery, two-phone
  convergence, old iOS unknown-field behavior, and real CloudKit Production
  latency.

## Test Evidence

Passing gates:

```text
swift build
# passed

bash Scripts/regenerate-codex-parser-hash.sh
bash Scripts/lint.sh audit-parser-hash
# regenerated hash 2a1382d8999e497f; audit passed

bash Scripts/lint.sh lint-macos
# passed; app locale audit reported optional missing locales but exited 0

swift test --filter 'QuotaWarningPushFireTests|SyncProviderMapperTests|SyncWireFormatRoundTripTests|MockProviderInjector|QuotaProviderListTests'
# passed: 108 tests / 6 suites

swift test --filter 'LocalizationLanguageCatalogTests|TokenAccountSyncCoverageTests'
# passed: 25 tests / 2 suites

swift test --filter 'CodexLoginRunnerTests|SubprocessRunnerTests|AntigravityDeadlineTests|AntigravityQuotaSummaryTests|CommandCodeUsageFetcherTests|DeepSeekUsageFetcherTests|KimiUsageResponseParsingTests|CLIServeRouterTests|OpenAIDashboardBrowserCookieImporterTests|MemoryPressureCacheTrimTests'
# passed: 148 tests / 10 suites

swift test --filter 'OpenAIDashboardBrowserCookieImporterTests|AdaptiveRefreshTimerTests|MockProviderInjectorIntegrationTests'
# passed: 67 tests / 3 suites

swift test --filter 'SubprocessRunnerTests|CodexLoginRunnerTests|CommandCodeUsageFetcherTests|DeepSeekUsageFetcherTests|KimiUsageResponseParsingTests|CLIServeRouterTests|OpenAIDashboardBrowserCookieImporterTests'
# passed after wall-clock timeout hardening: 130 tests / 7 suites

swift test --parallel --num-workers 1 --filter 'CodexLoginRunnerTests|SubprocessRunnerTests|AntigravityDeadlineTests|AntigravityQuotaSummaryTests|AntigravityCLIHTTPSFetchStrategyTests|CommandCodeUsageFetcherTests|DeepSeekUsageFetcherTests|KimiUsageResponseParsingTests|CLIServeRouterTests|MemoryPressureCacheTrimTests'
# passed after wall-clock timeout hardening: 166 tests / 10 suites

swift test --no-parallel --jobs 1
# passed: 5551 tests / 564 suites in 266.617 seconds

cd CodexBarMobile && xcodegen generate
# passed

XcodeBuildMCP test_sim, project CodexBarMobile.xcodeproj, scheme CodexBarMobile,
simulator iPhone 17, iOS 26.5
# passed: 531 passed, 0 failed, 4 skipped

bash Scripts/changelog-to-html.sh 0.39.0.1
# passed; extracted "CodexBar 0.39.0.1-Mobile 1.17.0"

bash Scripts/lint.sh audit-parser-version
# passed: parser code changed AND parserLogicVersion bumped

bash Scripts/lint.sh lint
# passed after release-gate cleanup:
# - package signing fixture passes because sign-and-notarize packages with CODEXBAR_SIGNING=identity;
# - repository-size gate passes after optimizing two pre-existing 1.16 nomination PNGs below 2 MiB;
# - SwiftLint passes with scoped suppressions for existing oversized store declarations;
# - iOS xcstrings audit passes with all 370 source keys present.
```

Full Mac suite residual:

```text
swift test
# failed after 44.553s with 19 issues before follow-up test stabilization

swift test --jobs 1
# failed after 76.394s with 16 issues; --jobs only limits build concurrency

swift test --parallel --num-workers 1
# failed after 60.928s with 14 issues

swift test --parallel --num-workers 1
# failed after wall-clock timeout hardening in 78.108s with 23 issues
```

Follow-up stabilization fixed the compile-time `#expect` argument issue in
`MockProviderInjectorIntegrationTests`, made `OpenAIDashboardBrowserCookieImporterTests`
wait for serialized cookie work to enter the queue before asserting timeout
ordering, made the adaptive timer restart assertions wait for the startup
refresh count to settle, and moved shared timeout callbacks from cooperative
task sleeps / Dispatch timers to `WallClockTimeout` for
`BoundedTaskJoin`, `SubprocessRunner`, `CodexLoginRunner`, and OpenAI cookie
deadline helpers. The focused suites covering those changes pass.

The remaining `swift test --parallel --num-workers 1` full-run failures are
still timing-sensitive elapsed-time or queue-completion assertions in
pre-existing suites such as
`CodexLoginRunnerTests`, `SubprocessRunnerTests`,
`AntigravityQuotaSummaryTests`, `AntigravityDeadlineTests`,
`CommandCodeUsageFetcherTests`, `DeepSeekUsageFetcherTests`,
`KimiUsageResponseParsingTests`, `CLIServeRouterTests`, and
`MemoryPressureCacheTrimTests`. The same residual cluster passes when isolated
with `swift test --parallel --num-workers 1 --filter ...`, and the complete
Mac suite passes with `swift test --no-parallel --jobs 1`. Treat the explicit
no-parallel full suite as the release gate; do not use the overloaded
full-repo `--parallel --num-workers 1` run as a release blocker unless the
test runner scheduling model changes.

## Draft Release Evidence

Local artifact build completed.

`Scripts/release.sh` phase 1 is the repo's Mac draft release path. It performs
a clean-worktree check, runs `bash Scripts/lint.sh lint`, builds/signs/notarizes
or reuses artifacts, pushes tag `v0.39.0.1-mobile.1.17.0` to `origin`, and
creates a GitHub draft release.

Because phase 1 publishes a remote tag and creates a remote draft release, it
must not be run unless that remote side effect is explicitly authorized by the
active release boundary. The local artifact-only path was run with
`./Scripts/sign-and-notarize.sh`.

Local artifact evidence:

```text
./Scripts/sign-and-notarize.sh
# notarization accepted, submission id 28159ee0-a1ce-453c-9f34-25fdc05aa2a2
# stapler validate passed
# direct launch verification passed
# Done: CodexBar-0.39.0.1-mobile.1.17.0.zip

CodexBar-0.39.0.1-mobile.1.17.0.zip       44M (du: 45M)
CodexBar-0.39.0.1-mobile.1.17.0.dSYM.zip  34M (du: 35M)
CodexBar.app                              107M

CFBundleShortVersionString: 0.39.0.1
CFBundleVersion: 97.1.1.17.0
codesign --verify --deep --strict --verbose=2 CodexBar.app
# valid on disk; satisfies Designated Requirement
spctl --assess --type execute --verbose CodexBar.app
# accepted; source=Notarized Developer ID
```

GitHub draft release URL: not created. Remote tag
`v0.39.0.1-mobile.1.17.0` was not pushed.

Appcast generation status: not run. `appcast.xml` was not changed.

Remaining release steps:

- if remote draft release is authorized, run `./Scripts/release.sh` phase 1
  from a clean tree; it should reuse the existing zip/dSYM artifacts;
- if a parallel full-suite gate is required in the future, split it into
  smaller shards instead of running all 564 suites in one parallel worker burst;
- do not run `./Scripts/release.sh --finalize`, publish appcast, push
  `mobile-dev`, upload TestFlight, or deploy CloudKit without explicit
  confirmation.

## Review

Local final diff review completed after the artifact-evidence commit.

Reviewed areas:

- `Shared/Models/UsageSnapshot.swift` and `Shared/Models/V039Snapshots.swift`:
  `crossModelUsage` is additive, optional, decoded with `decodeIfPresent`, and
  preserved through `with(quotaWarnings:)`.
- `Sources/CodexBar/Sync/SyncCoordinator.swift`: CrossModel mapping is
  provider-gated; generic cost summary data remains preferred before the
  CrossModel native fallback.
- `CodexBarMobile/CodexBarMobile/Views/CrossModelUsageCard.swift` and
  `ProviderDetailView.swift`: iOS renders the dedicated card only when the
  CrossModel provider ID and typed payload are both present.
- `Shared/Notifications/QuotaProviderList.swift`,
  `MockProviderInjector.swift`, and provider color tests: the four v0.38/v0.39
  providers are registered without changing earlier provider ordering.
- `Scripts/sign-and-notarize.sh`, `Scripts/package_app.sh`, and
  `Scripts/test_package_signing.sh`: release packaging now uses identity
  signing when the notarization path stages the app.
- `Scripts/release.sh`: phase 1 still pushes tag
  `v0.39.0.1-mobile.1.17.0` to `origin` before creating a GitHub draft release,
  so it was not run under the current no-tag-publish boundary.

No blocking implementation findings were found in the local review. Remaining
open items are release-policy/test-evidence items, not unreviewed code paths.
