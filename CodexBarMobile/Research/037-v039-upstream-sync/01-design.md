# v0.39.0 Upstream Sync Design

Status: `in-progress`
Date: 2026-07-04

## Design Principle

Merge upstream `v0.37.2..v0.39.0` into one fork release while preserving fork
release tooling, CloudKit Production behavior, Mac-to-iOS sync contracts,
versioning semantics, and no-prompt test safety. iOS should expose user-visible
provider data that Mac already produces and can safely serialize through
CloudKit. iOS should not reimplement Mac-only credential acquisition, browser
cookie import, Keychain probing, menu bar UI, settings panes, website pages, or
CLI/server behavior.

## Mac Merge Strategy

1. Merge target upstream tag `v0.39.0` into this branch.
2. Preserve upstream provider implementations, parser/runtime fixes, security
   hardening, Settings redesign, menu fixes, widgets, tests, resources, docs,
   repository-size guards, and CI support where compatible.
3. In conflicts, keep fork semantics for:
   - `version.env` four-segment Mac marketing version and subdecimal build;
   - `MOBILE_VERSION` and Sparkle composite `BUILD_NUMBER.MOBILE_VERSION`;
   - `o1xhack/CodexBar-Mobile` release target and appcast URL;
   - `com.o1xhack.codexbar` bundle ID, app group, iCloud container, and
     CloudKit Production entitlements;
   - `CodexBarMobile/`, `Shared/`, `Sources/CodexBar/Sync/`, iOS release docs,
     and iOS tests that upstream does not own;
   - fork release scripts unless upstream changes are compatible.
4. Re-run build/lint/tests and fix non-exhaustive provider/switch fallout
   instead of dropping upstream provider changes.

## Provider Additions

Upstream adds four `UsageProvider` cases after the current fork baseline:

- `sakana`
- `qoder`
- `crossmodel`
- `clawrouter`

Required fork/iOS work:

- append provider identifiers to `Shared/Notifications/QuotaProviderList.swift`
  without reordering existing cases;
- update `MockProviderInjector.swift` borrowed real-provider IDs, simple
  profiles, and count assertions;
- update `ProviderColorPalette.swift`, with more specific substring matches
  before generic ones;
- update in-app release notes and `Localizable.xcstrings` in English,
  Simplified Chinese, Traditional Chinese, and Japanese;
- audit `PreviewData.swift` by card type and add examples only where existing
  card families do not cover the new data shape;
- run the new-provider switch coverage through `swift build` and focused tests.

## Shared and iOS Sync Design

### Wire Compatibility Default

Default to additive optional fields decoded with `decodeIfPresent`, and avoid
`providerPayloadVersion` changes unless a user-visible value cannot be carried
by current optional payloads.

Preferred representation order:

1. existing `rateWindows`, `primary`, `secondary`, `budget`, `costSummary`, and
   existing dedicated optional payloads;
2. additive optional shared payload fields with tolerant decode;
3. dedicated iOS UI only when generic rendering would hide important user
   value.

Do not introduce required shared fields in this round.

### Current Bridge Coverage

The current fork already has the v0.37 bridge:

- `ProviderUsageSnapshot.codexResetCredits`
- `ProviderUsageSnapshot.usageDataConfidence`
- `SyncCoordinator.mapCodexResetCredits`
- `SyncCoordinator.mapUsageDataConfidence`

This means v0.39.0's Codex reset-credit expiry inventory may already be
serializable if upstream continues to populate `CodexRateLimitResetCredits`.
The required audit is whether iOS UI needs to show more than current count and
next expiry.

### Implemented Bridge Decisions

| Upstream data | Default plan |
|---|---|
| ClawRouter monthly budget/spend/requests/tokens/routed providers | Generic rendering is sufficient for this release. No dedicated Shared payload was added. |
| CrossModel wallet balance + day/week/month spend | Added `SyncCrossModelUsage` as an optional payload because wallet balance, uncollected amount, and multiple period windows would be flattened by generic budget rows. CrossModel native spend also maps to `SyncCostSummary` so Cost views can include it. |
| Qoder big-model credit usage | Generic provider card, quota zones, color, mock data, and tests are sufficient for this release. No dedicated Shared payload was added. |
| Sakana subscription + pay-as-you-go balance/recent usage | Generic provider card, quota zones, color, mock data, and tests are sufficient for this release. No dedicated Shared payload was added. |
| Kimi monthly subscription usage | Prefer generic monthly `RateWindow` or `budget`. Add optional Kimi payload only if the upstream model exposes structured subscription details not captured by generic rows. |
| Mistral billing credit balance | Existing Mistral `SyncCostSummary` covers daily billing spend. Add optional field only if available credit balance is lost. |
| Codex project/worktree cost rollups | Existing `SyncCostSummary` has model/service breakdowns, not project/worktree. Add a bounded optional payload if project/worktree rollups are high-value and already available in Mac data structures. |
| Claude model-scoped weekly windows | Existing `extraRateWindows` -> `rateWindows` should cover this. Validate with fixtures/tests and no new wire field unless labels/cadence are lost. |
| Widget `usageBarsShowUsed` | Mac WidgetSnapshot-only. No iOS CloudKit bridge unless iOS widget rendering consumes that exact shared store. Add decode test if the shared model stays in the build. |

The implemented Shared change is intentionally additive:

- `ProviderUsageSnapshot.crossModelUsage` is optional and decoded with
  `decodeIfPresent`;
- `with(quotaWarnings:)` preserves the optional CrossModel payload;
- no `providerPayloadVersion` or `encodingVersion` bump is required;
- old iOS builds should ignore unknown top-level JSON fields, and new iOS
  builds should decode old payloads with `crossModelUsage == nil`.

## CloudKit Design

Expected default: no CloudKit Production deploy unless the merge adds one of:

- new `CKRecord` type;
- new record field outside the compressed provider payload;
- new zone;
- new subscription or predicate/index field;
- `providerPayloadVersion` or `encodingVersion` change.

New providers should not require CloudKit schema deployment by themselves,
because provider usage records use existing `DeviceProvidersZone` /
`ProviderUsageEnvelope` payloads. This must be verified by the audit in
`docs/cloudkit-deploy-audit.md` after implementation:

```text
git diff <latest-published-fork-tag>..HEAD -- | grep -E "^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)"
git diff <latest-published-fork-tag>..HEAD -- Shared/iCloud/CloudConstants.swift
git diff <latest-published-fork-tag>..HEAD -- Shared/Models/UsageSnapshot.swift | grep -E "^\+.*public let|^-.*public let"
```

## iOS Localization

Every new iOS user-facing string must use `String(localized:)` and have full
translations in:

- `en`
- `zh-Hans`
- `zh-Hant`
- `ja`

No `"state": "new"` or missing locale entries may remain.

## Versioning Design

| File / field | Target |
|---|---|
| `version.env` `MARKETING_VERSION` | `0.39.0.1` |
| `version.env` `BUILD_NUMBER` | `97.1` |
| `version.env` `MOBILE_VERSION` | `1.17.0` |
| `version.env` `UPSTREAM_VERSION` | `v0.39.0` |
| `version.env` `UPSTREAM_SYNC_DATE` | `2026-07-04` |
| `CodexBarMobile/project.yml` `MARKETING_VERSION` | `1.17.0` |
| `CodexBarMobile/project.yml` `CURRENT_PROJECT_VERSION` | `181` unless final upload policy requires a later bump |
| Sparkle version | `97.1.1.17.0` |
| GitHub tag | `v0.39.0.1-mobile.1.17.0` |

## Testing Design

Minimum gates:

- `swift build`
- `bash Scripts/lint.sh lint`
- full Mac suite through repo sharded equivalent
- `swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'`
- focused tests for new providers, parser/hash, no-Keychain-prompt safety,
  provider switch coverage, sync mappers, old/new payload decode, and mock
  inventory counts
- parser logic/version/hash gate because `CostUsageScanner*`,
  `CostUsageCache.swift`, `CostUsagePricing.swift`, and
  `CodexParserHash.generated.swift` changed upstream
- `cd CodexBarMobile && xcodegen generate`
- iOS simulator build and relevant tests
- iOS four-language localization audit
- CloudKit Production schema audit
- 16-row 2 Mac x 2 iPhone compatibility matrix because provider display data,
  Shared payload, and cross-version rendering are in scope
- final diff self-review and agent/review loop with blocking findings fixed

## Release Design

This goal requires a Mac draft release, not live publication. The release
workflow must stop before live release/appcast finalization unless the user
explicitly confirms those steps.

Required release prep:

- update root `CHANGELOG.md` with fork mobile highlights and upstream summary;
- verify `bash Scripts/changelog-to-html.sh 0.39.0.1` extracts the fork section;
- run signing/notarization/draft-release flow only through the fork scripts and
  only after version/docs/tests are ready;
- record draft release URL, artifact names, appcast/Sparkle version evidence,
  and remaining live-release steps in `03-testing.md`.
