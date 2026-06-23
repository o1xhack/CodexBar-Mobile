# 032 Testing — iOS Sync Device Management

Status: `done`

## Automated Tests

| Test | Result | Evidence |
|---|---|---|
| DeviceLifecycleEvent Codable round trip | pass | `DeviceLifecycleEventTests.lifecycleCodableRoundTrip` |
| CKRecord encode/decode round trip | pass | `DeviceLifecycleEventTests.lifecycleCKRecordRoundTrip` verifies no reserved `recordID` field is written. |
| alias replay collapses duplicate IDs | pass | `DeviceLifecycleEventTests.aliasCollapsesDuplicateMacIDs` |
| unalias restores duplicate IDs | pass | `DeviceLifecycleEventTests.unaliasRestoresDuplicateMacIDs` |
| archive excludes device from active list | pass | `DeviceLifecycleEventTests.archiveExcludesRetiredDevice` |
| unarchive restores active device | pass | `DeviceLifecycleEventTests.unarchiveRestoresDevice` |
| same-name Macs do not auto-merge | pass | `DeviceLifecycleEventTests.sameNameMacsDoNotAutoMerge` |
| local-cost providers are not double-counted inside alias group | pass | `DeviceLifecycleEventTests.aliasDoesNotDoubleCountLocalCost` |

Command evidence:

```bash
cd CodexBarMobile
xcodegen generate
xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile \
  -destination 'id=05045514-6035-4CE2-8AE9-E340DF1411BC' \
  -only-testing:CodexBarMobileTests/DeviceLifecycleEventTests test
# Result: 8 tests passed.

xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile \
  -destination 'id=05045514-6035-4CE2-8AE9-E340DF1411BC' \
  -only-testing:CodexBarMobileTests test
# Result: 460 tests passed.

xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile \
  -configuration Release -destination 'generic/platform=iOS Simulator' build
# Result: BUILD SUCCEEDED.
```

Shared/Mac compile surface:

```bash
swift build
# Result: Build complete.

swift test
# Result: build completed; full root suite reported 2 unrelated timing failures:
# - CommandCodeUsageFetcherTests subscription grace elapsed 1.176s > 300ms
# - DeepSeekUsageFetcherTests balance grace elapsed 1.391s > 300ms

swift test --filter CommandCodeUsageFetcherTests
swift test --filter DeepSeekUsageFetcherTests
# Result: both failing suites passed when rerun in isolation.
```

## Sync Compatibility Matrix

This change touches CloudKit record types and cross-version device rendering,
so the canonical 16-case matrix applies.

For this release, "new Mac" and "old Mac" both use the existing v0.36.1 Mac
producer payload. There is no Mac release and no Mac-side lifecycle writer.
The cross-version risk is therefore iOS-reader behavior around an additive
`DeviceLifecycleEvent` record type:

- old iOS builds never query `DeviceLifecycleEvent`, so existing provider sync
  display remains unchanged;
- new iOS builds query lifecycle events and apply alias/archive display
  semantics locally;
- raw provider/device records are not deleted or rewritten, so old/new iOS
  devices can coexist against the same CloudKit data;
- before TestFlight or release, Production schema must be deployed so new iOS
  devices can save lifecycle events in Production CloudKit.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted pass | unchanged path | No new lifecycle query or Mac payload change. |
| 2 | old | old | old | new | substituted pass | full iOS tests + reducer tests | New iOS can read existing snapshots; old iOS ignores lifecycle records. |
| 3 | old | old | new | old | substituted pass | full iOS tests + reducer tests | Same as case 2 with device roles swapped. |
| 4 | old | old | new | new | substituted pass | full iOS tests + reducer tests | Both new iPhones apply the same additive lifecycle semantics. |
| 5 | old | new | old | old | substituted pass | unchanged Mac payload | New Mac state is equivalent because no Mac release exists for this feature. |
| 6 | old | new | old | new | substituted pass | full iOS tests + reducer tests | Mixed iOS readers remain compatible with unchanged provider records. |
| 7 | old | new | new | old | substituted pass | full iOS tests + reducer tests | Same as case 6 with iPhone roles swapped. |
| 8 | old | new | new | new | substituted pass | full iOS tests + reducer tests | New iPhones see lifecycle-managed active/archived rows. |
| 9 | new | old | old | old | substituted pass | unchanged Mac payload | Same as case 5 with Mac roles swapped. |
| 10 | new | old | old | new | substituted pass | full iOS tests + reducer tests | Same as case 6 with Mac roles swapped. |
| 11 | new | old | new | old | substituted pass | full iOS tests + reducer tests | Same as case 7 with Mac roles swapped. |
| 12 | new | old | new | new | substituted pass | full iOS tests + reducer tests | Same as case 8 with Mac roles swapped. |
| 13 | new | new | old | old | substituted pass | unchanged Mac payload | Old iOS behavior unchanged. |
| 14 | new | new | old | new | substituted pass | full iOS tests + reducer tests | Old iOS ignores lifecycle events; new iOS applies them. |
| 15 | new | new | new | old | substituted pass | full iOS tests + reducer tests | Same as case 14 with iPhone roles swapped. |
| 16 | new | new | new | new | substituted pass | full iOS tests + reducer tests | Full new-reader behavior covered by lifecycle tests. |

Hardware QA status: the physical 2 Mac x 2 iPhone matrix has not been run in
this implementation PR. It remains a pre-release QA gate after CloudKit
Production schema deploy and before iOS 1.14.0 TestFlight/release sign-off.

## CloudKit Schema Audit

Production schema deploy is required before TestFlight or release because this
PR adds the `DeviceLifecycleEvent` CKRecord type in `DeviceProvidersZone`.
Do not deploy without explicit user confirmation.
