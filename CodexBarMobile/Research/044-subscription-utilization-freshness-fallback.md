# Subscription Utilization Fresh-Series Fallback

Status: `done`
Date: 2026-07-26
Branch: `fix/subscription-utilization-window`

## Incident

The iPhone Cost tab showed:

- `Today 0%`
- `This Week 0%`
- `14 Days 0%`
- `30 Days 31%`
- no visible recent bars after approximately July 12

Raw Sync Data and the Mac history files still contained current quota data.
This ruled out a missing CloudKit payload or a failed history write.

## Evidence

The live, locally persisted Mac history was inspected with account identifiers
omitted:

| Provider | Series | Latest capture | Recent evidence |
|----------|--------|----------------|-----------------|
| Claude | `session` | 2026-07-26 | current samples, genuinely 0% |
| Claude | `weekly` | 2026-07-26 | current samples, genuinely 0% |
| Codex | `session` | 2026-07-12 | stale; no later samples |
| Codex | `weekly` | 2026-07-26 | current daily peaks through today |

This exactly explains the screenshot. The aggregate still had older Codex
session peaks for the 30-day card, but its 14-day window contained only current
Claude zeroes. Codex weekly data was present but ignored.

`UtilizationAggregateView.buildModel` selected all `session` series whenever
any session series existed:

```swift
let sessionSeries = history.filter { $0.name == "session" }
let chosen = sessionSeries.isEmpty ? Array(history.prefix(1)) : sessionSeries
```

The fallback therefore handled a provider that never emitted `session`, but
not a provider whose retained session history stopped advancing.

Recent upstream work expanded and isolated plan-utilization histories across
more semantic lanes. No upstream issue or pull request provides an iOS
aggregate fix; this view exists only in the mobile fork.

## Design

Select one semantic quota family per provider:

1. Group non-empty histories by series name.
2. Prefer `session` while its newest capture is within two hourly sample
   buckets of the provider's freshest family.
3. If `session` falls farther behind, use the freshest family instead.
4. Union duplicate series with the selected name before computing daily peaks,
   preserving the existing cross-version merge defense.
5. Select by timestamps, never by `usedPercent`, so a current real 0% session
   remains 0% rather than being replaced by a non-zero weekly value.

The two-hour grace matches the Mac history's one-hour sampling buckets and
prevents one partial refresh from making the chart jump between semantics.

The section subtitle changes from session-specific wording to a general quota
trend because a provider may legitimately use weekly or another fresh quota
family as its fallback.

## Test Plan

- Reproduce a stale session plus current weekly history and assert Today,
  14 Days, provider average, and the latest bar use weekly data.
- Pair a fresh 0% session with a fresh non-zero weekly history and assert the
  session remains selected.
- Re-run the existing bursty-session, duplicate-session, provider compatibility,
  cache identity, and CloudKit merge tests.
- Build the iOS app and visually verify the aggregate with deterministic mock
  data if simulator state is available.

## Scope

This is an iOS aggregation fix. It does not change Mac history persistence,
Shared/CloudKit payloads, schema, provider API reads, cost data, or release
artifacts.

## Verification

- `SubscriptionUtilizationCompatTests`: 11 passed, including the stale-session
  fallback and current-zero-session regressions.
- `CloudKitMergeTests` + `ViewCacheIdentityTests` +
  `MultiAccountForEachIdentityTests`: 72 passed.
- Complete `CodexBarMobileTests` target: 606 passed, 0 failed.
- Simulator Debug build, install, and launch: passed on iPhone 17 Pro Max,
  iOS 26.4.
- `./Scripts/lint.sh lint`: passed; SwiftFormat clean, SwiftLint 0 violations,
  all app locales translated, all iOS source localization keys present.
- Post-consolidation generic iOS Simulator Debug build: passed for the app,
  push extension, widgets, and sync framework.
- `git diff --check`: passed.

The built-in demo snapshot currently has no `utilizationHistory`, so it cannot
render this section for visual comparison. The aggregate was instead verified
with deterministic model fixtures matching the production incident shape.

## Sync Compatibility Gate

The canonical 2 Mac × 2 iPhone gate applies because this changes
cross-version rendering of already-synced utilization history. The complete
16-case ledger, substituted evidence, and residual physical-device risks are in
[`044/03-testing.md`](044-subscription-utilization-freshness-fallback/03-testing.md).
Its current verdict is `substituted`: code review may complete, but build 190
still requires the physical four-device matrix before public iOS release.

## Release Notes Consolidation

The public App Store upgrade path is `1.17.0` → `1.19.0` → `1.19.1`; iOS
`1.18.0` was a TestFlight candidate and was never released. The in-app history
preserves the public `1.19.0` entry and adds a concise `1.19.1` hotfix entry.
The 1.19.1 App Store source notes use the same concise content in English,
Japanese, Simplified Chinese, and Traditional Chinese.

## App Store Connect Handoff

- Removed the previously approved `1.19.0 (188)` version from its release
  submission. App Store Connect returned the version to
  `DEVELOPER_REJECTED`, allowing its build and metadata to be replaced.
- Generated and uploaded archive
  `/tmp/CodexBarMobile-20260726-131255.xcarchive`. The app, push extension, and
  widget extension all report `1.19.0 (189)`, and the archived app entitlement
  uses CloudKit `Production`.
- App Store Connect processed Build 189 as `VALID`, unexpired, and the
  `1.19.0` version build relationship was changed from Build 188 to Build 189.
- Updated and read back `whatsNew` for `en-US`, `ja`, `zh-Hans`, and
  `zh-Hant`; every remote value exactly matches its checked-in
  `AppStoreMetadata/1.19.0` source file.
- Created review submission
  `3e56387c-e997-4e5b-a22f-c5f7b5273bc5` and submitted it at
  `2026-07-26T20:20:21.459Z`. Final API readback shows both the submission and
  App Store version in `WAITING_FOR_REVIEW`.
- Release control remains `MANUAL`. This handoff did not publish the version
  to the public App Store.
- App Store Connect now reports build 189 and iOS `1.19.0` as
  `READY_FOR_SALE`. Build 189 predates the later Alibaba iOS presentation
  additions, so it is not the complete fix.
- Archived and uploaded
  `/tmp/CodexBarMobile-20260727-144448.xcarchive`. The app, push extension,
  widget extension, and sync extension all report `1.19.1 (190)`, and the
  archived app entitlement uses CloudKit `Production`.
- App Store Connect processed build 190 as `VALID` and unexpired. Created the
  manual-release `1.19.1` version, bound build 190, and read back
  `PREPARE_FOR_SUBMISSION`.
- Updated and read back `whatsNew` for `en-US`, `ja`, `zh-Hans`, and
  `zh-Hant`; every remote value exactly matches its checked-in
  `AppStoreMetadata/1.19.1` source file. No App Review submission was created.
