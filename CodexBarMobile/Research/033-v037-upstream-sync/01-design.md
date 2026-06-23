# v0.37.2 Upstream Sync Design

Status: `in-progress`
Date: 2026-06-23

## Design Principle

Merge upstream `v0.36.1..v0.37.2` into one fork release while preserving
fork-owned release tooling, CloudKit Production behavior, iOS sync contracts,
and the four-segment Mac versioning scheme. iOS should support user-visible
provider data that Mac produces and syncs through CloudKit. iOS should not
reimplement Mac-only credential acquisition, browser cookie import, Keychain
probing, local process inspection, menu bar UI, widgets, CLI server behavior, or
website localization.

## Mac Merge Strategy

1. Merge target upstream tag `v0.37.2` into the branch created from
   `origin/mobile-dev`.
2. Keep upstream provider implementations, parser/runtime fixes, security
   hardening, menu reliability fixes, widgets, tests, resources, docs, and CI
   support where compatible.
3. In conflicts, keep fork semantics for:
   - `version.env` four-segment Mac marketing version and subdecimal build;
   - `MOBILE_VERSION` and Sparkle composite `BUILD_NUMBER.MOBILE_VERSION`;
   - `o1xhack/CodexBar-Mobile` GitHub release target and appcast URL;
   - `com.o1xhack.codexbar` bundle ID, app group, iCloud container, and
     CloudKit Production entitlements;
   - `CodexBarMobile/`, `Shared/`, `Sources/CodexBar/Sync/`, and iOS release
     docs/tests that upstream does not own;
   - existing fork release scripts unless upstream changes are compatible.
4. Re-run build/lint/tests and fix non-exhaustive provider/switch fallout rather
   than dropping upstream provider changes.

## Shared and iOS Sync Design

### Wire Compatibility Default

Default to no new CloudKit schema and no `providerPayloadVersion` bump unless
audit proves a user-visible upstream value cannot be represented by existing
optional payload fields.

Preferred representation order:

1. existing `rateWindows`, `primary`, `secondary`, `budget`, `costSummary`, and
   dedicated optional payloads;
2. additive optional shared payload fields decoded with `decodeIfPresent`;
3. dedicated iOS UI only when generic rendering would hide important user value.

Never introduce required shared fields in this round.

Final implementation:

- `ProviderUsageSnapshot` gained optional `codexResetCredits` and
  `usageDataConfidence` fields.
- `SyncCodexResetCredits` / `SyncCodexResetCredit` are additive Codable models
  with optional/default-tolerant decode behavior.
- Existing provider snapshots without these fields decode to `nil`, so old Mac
  payloads remain readable by new iOS.
- New Mac payloads keep these values inside the existing compressed provider
  payload blob, so CloudKit schema does not parse or index them.

### Bedrock CloudWatch Activity

Upstream adds optional rolling 14-day Claude token/request totals from
CloudWatch. Audit `BedrockUsageStats`, `BedrockCloudWatchUsage`, and
`SyncCoordinator.mapBedrockCost` after merge.

Expected iOS behavior:

- monthly spend/budget continues through `SyncBedrockCost`;
- if 14-day tokens/requests appear as generic rate/cost rows, iOS renders them
  with existing generic sections;
- if they are Mac-only menu rows, document as Mac-only unless a small optional
  payload can expose the summary safely.

Audit result: no dedicated iOS wire field was needed for this release. Bedrock
continues through existing spend/budget/cost-summary structures; the new
CloudWatch activity is a Mac-side provider detail and does not require a new
CloudKit field or iOS-specific card.

### Codex Profile-Home Accounts

Upstream exposes explicitly configured Codex profile homes as switchable accounts
without copying credentials. iOS should preserve account identity and avoid
duplicate-card regressions.

Audit points:

- `CodexVisibleAccountProjection`;
- `CodexAccountReconciliation`;
- `SyncCoordinator` per-account provider fan-out;
- iOS `ProviderAccountGroup` and identity merge tests.

No iOS credential UI is planned.

Audit result: no credential or login UI was added on iOS. Existing
multi-account fan-out and account identity tests cover the profile-home account
shape, and the focused `AccountIdentity|MultiAccount|DualZoneReader` gate
passed.

### Codex Reset Credits

Upstream shows manual rate-limit reset credits and next expiry for Codex OAuth
accounts. If this is represented as `RateWindow`, budget, or cost rows, iOS can
render it generically. If it is only a Mac menu-section model, add either:

- an optional shared payload with credit count and next expiry plus compact iOS
  display, or
- a documented no-iOS-support decision if the source is dashboard-only and not
  stable enough for sync.

Final implementation: reset credits are user-visible on Mac and are not fully
represented by the existing generic rate-window model, so this release adds an
optional shared payload and an iOS Codex detail card. The card shows available
reset credits and expiry when Mac provides them, and older payloads simply hide
the section.

### Cursor Personal On-Demand Spend

iOS already has a Cursor Extra budget gauge path. After merge, verify upstream's
personal on-demand spend maps to `SyncBudgetSnapshot` or cost summary fields and
does not require a new field.

Audit result: no new iOS wire field was required. Existing budget/cost snapshot
rendering remains the compatibility path.

### Mistral Vibe Monthly Plan

Mistral already syncs cost/usage data to iOS. The new Vibe monthly-plan usage
should use generic windows or existing Mistral usage snapshots if possible.
Only add dedicated UI if generic rendering drops the monthly-plan headline.

Audit result: no dedicated Mistral iOS UI was added. Generic synced usage rows
and existing provider detail sections remain sufficient for this upstream
round.

### Provider Usage Confidence

Upstream diagnostics can report provider-neutral confidence and exact Codex OAuth
windows. Treat this as diagnostic metadata unless the Mac UI presents it as a
user-facing state. If not synced, document why no iOS wire/schema change is
needed.

Final implementation: confidence is carried as an optional string and rendered
as a low-key notice only when Mac sends a non-`exact`, non-`unknown` value. This
keeps the field useful for cross-version display without making it a required
contract.

### Security and Endpoint Hardening

Merge upstream endpoint validation and file-permission fixes in full. They are
Mac runtime/security changes. iOS testing should focus on ensuring the shared
sync path still decodes old and new payloads.

## iOS Localization

iOS remains under the mandatory four-language rule:

- English;
- Simplified Chinese;
- Traditional Chinese;
- Japanese.

New iOS user-facing strings must be represented in `Localizable.xcstrings` with
all four translations and `"state": "translated"`.

Mac upstream 21-language resources should be merged as Mac resources. They do
not expand iOS language scope for this release.

## Versioning Design

| File / field | Target |
|---|---|
| `version.env` `MARKETING_VERSION` | `0.37.2.1` |
| `version.env` `BUILD_NUMBER` | `92.1` |
| `version.env` `MOBILE_VERSION` | `1.15.0` |
| `version.env` `UPSTREAM_VERSION` | `v0.37.2` |
| `version.env` `UPSTREAM_SYNC_DATE` | `2026-06-22` |
| `CodexBarMobile/project.yml` `MARKETING_VERSION` | `1.15.0` |
| `CodexBarMobile/project.yml` `CURRENT_PROJECT_VERSION` | `164` unless final commit policy requires a later bump |
| Sparkle version | `92.1.1.15.0` |
| GitHub tag | `v0.37.2.1-mobile.1.15.0` |

If this branch stops at draft packaging, the Research outcome must clearly state
which fields are staged for the target release and which release steps are still
not live.

## CloudKit Design

Expected default: no CloudKit Production deploy unless audit finds one of:

- new `CKRecord` type;
- new record field outside the compressed provider payload;
- new zone;
- new subscription or predicate/index field;
- `providerPayloadVersion` or `encodingVersion` change.

Known pre-existing iOS 1.14.0 work added `DeviceLifecycleEvent`; that required
a CloudKit Production schema deploy before the already-reviewing iOS 1.14.0
release. The deploy is now confirmed complete by Production schema export. This
upstream-sync round targets iOS 1.15.0 and must distinguish whether new Mac
changes add any additional CloudKit deploy need.

Audit result for this upstream-sync round: no additional CloudKit Production
schema deploy is needed beyond the already-deployed iOS 1.14.0
`DeviceLifecycleEvent` schema. The v0.37.2 bridge adds optional keys inside the
existing provider payload `Data` blob and leaves `CloudConstants.swift`
unchanged relative to `origin/mobile-dev`.

## Testing Design

Minimum gates:

- `swift build`;
- `bash Scripts/lint.sh lint`;
- full SwiftPM test suite or repo sharded equivalent;
- focused provider tests for Bedrock, Codex accounts/reset credits, Cursor,
  Mistral, MiniMax, Antigravity, endpoint validation, and sync/account identity;
- `swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'`;
- `cd CodexBarMobile && xcodegen generate`;
- iOS simulator build/test;
- iOS localization audit;
- CloudKit Production schema audit;
- 16-combination 2 Mac x 2 iPhone sync compatibility matrix in
  `03-testing.md` if Shared/sync/provider-display changes are present;
- self-review and agent/review loop until blocking findings are fixed.

Release packaging note: `./Scripts/release.sh` phase1 is the correct Mac draft
release command, but it signs, notarizes, pushes the release tag to `origin`,
and creates the draft GitHub release. That crosses the Goal's explicit pause
boundary for release credentials and tag publication, so it must wait for user
confirmation.
