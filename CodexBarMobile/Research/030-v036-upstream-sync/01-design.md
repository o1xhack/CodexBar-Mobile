# v0.36.1 Upstream Sync Design

Status: `done`
Date: 2026-06-16

## Design Principle

Merge upstream `v0.35.0..v0.36.1` into one fork release while preserving
fork-owned release tooling, CloudKit Production behavior, iOS sync contracts,
and versioning semantics. iOS should support user-visible provider data that is
already produced by the Mac and synced through CloudKit. iOS should not
reimplement Mac-only credential acquisition, browser cookie import, Keychain
probing, local process inspection, menu bar UI, or website localization.

## Mac Merge Strategy

1. Merge target upstream tag `v0.36.1` into the branch created from
   `origin/mobile-dev`.
2. Keep upstream provider implementations, descriptor infrastructure, parser
   fixes, menu/process reliability fixes, tests, resources, and docs.
3. In conflicts, keep fork release semantics for:
   - `version.env` four-segment Mac marketing version and subdecimal build;
   - `mobile-dev` appcast and GitHub release target;
   - CloudKit Production entitlements;
   - iOS companion release notes and build versioning;
   - existing fork release scripts unless upstream changes are compatible.
4. Re-run build/lint/tests and fix non-exhaustive provider switch fallout rather
   than dropping provider cases.

## Shared and iOS Sync Design

### Provider Identity and Presentation

The upstream release adds four providers: LiteLLM, Poe, Chutes, and Zed. For each
provider, iOS should include:

- provider ID recognition in the client-side provider catalog;
- stable colors and icons/labels where the existing iOS abstractions require
  them;
- mock data coverage for demos/tests where applicable;
- generic rendering through existing quota, budget, balance, `RateWindow`, and
  extra-row paths before adding dedicated UI.

Tail-append provider IDs where ordered lists affect CloudKit subscription IDs or
mock count assertions.

Implementation result:

- `Shared/Notifications/QuotaProviderList.swift` tail-appends `litellm`, `poe`,
  `chutes`, and `zed`; quota subscription coverage is now 53 providers x 3
  transitions = 159 zones.
- `ProviderColorPalette` gives all four providers first-class iOS colors and
  adds collision tests.
- `MockProviderInjector` includes all four providers in borrowed real-provider
  mocks and simple profiles, with updated count assertions.
- Existing iOS generic usage-card rendering is used for synced windows, balance,
  budget, and cost rows. No new iOS credential, API-key, browser-cookie, or
  Keychain UI is added.

### LiteLLM

Mac fetches personal/team budget usage from a configured virtual key and proxy
URL. iOS should render the synced result. iOS does not need virtual-key settings
or network calls. Expected path: existing budget/rate-window rows, with provider
catalog/color/mock coverage.

Audit result: LiteLLM snapshots already flatten to the existing generic
usage/budget fields, so no provider-specific shared wire field is needed.

### Poe

Mac fetches current point balance and recent points history from API key
endpoints. iOS should render current balance and recent history if those values
are present in the synced generic payload. If recent history is only represented
as Mac-specific menu rows, add payload-preserving tests and document unsupported
dedicated history UI instead of inventing a partial UI.

Implementation result: `PoeUsageSnapshot` now synthesizes generic `RateWindow`
rows for the current point balance and 30-day points history while preserving the
Mac-specific `poeUsage` history. This lets iOS 1.13.0 render the useful Poe
summary through existing generic rows without adding a Poe-only shared payload.

### Chutes

Mac fetches subscription usage, quota windows, and pay-as-you-go usage. iOS
should render windows and usage percentages through generic rate-window/usage
lanes. No API-key settings are needed on iOS.

Audit result: Chutes uses existing generic subscription/quota/pay-as-you-go
windows and does not require a new shared schema field.

### Zed

Mac reads the signed-in editor Keychain session and reports plan, edit-prediction
quota, billing cycle, and overdue invoice state. iOS should only display synced
provider values. No Keychain session access or Zed settings UI is needed on iOS.

Audit result: Zed's editor session remains Mac-only. Synced display values use
the existing generic plan/quota/window payload.

### Antigravity and Reset Dates

Upstream now groups Antigravity quota summaries into Gemini and Claude + GPT
session/weekly buckets and decodes structured `resetTime`. iOS should preserve:

- named rate-window labels;
- `RateWindow.resetsAt` if already present in the shared payload;
- fallback display when only legacy text is available.

If current shared decoding already uses optional dates and named windows, no
wire/schema change is needed; add audit evidence.

Audit result: named windows and structured resets already pass through
`RateWindow` labels and optional reset-date fields. No shared type change is
needed for Antigravity or Copilot reset dates.

### CloudKit Schema

Expected default: no Production deploy. New providers and provider-display rows
should use the existing compressed provider payload and existing
`QuotaTransition` record type. The audit must still inspect:

- `Shared/iCloud/CloudConstants.swift`;
- new top-level `CKRecord` fields, zones, subscriptions, and indexes;
- `providerPayloadVersion` or `encodingVersion`;
- non-optional shared payload fields.

## iOS Localization

iOS remains on the mandatory four-language rule:

- English;
- Simplified Chinese;
- Traditional Chinese;
- Japanese.

New iOS user-facing release notes or strings must have all four translations in
`Localizable.xcstrings` with `"state": "translated"`.

Mac upstream 21-language resources should be merged as Mac resources. They do
not change iOS language scope for this release.

## Versioning Design

| File / field | Target |
|---|---|
| `version.env` `MARKETING_VERSION` | `0.36.1.1` |
| `version.env` `BUILD_NUMBER` | `88.1` |
| `version.env` `MOBILE_VERSION` | `1.13.0` |
| `CodexBarMobile/project.yml` `MARKETING_VERSION` | `1.13.0` |
| `CodexBarMobile/project.yml` `CURRENT_PROJECT_VERSION` | `154` |
| Sparkle version | `88.1.1.13.0` |
| GitHub tag | `v0.36.1.1-mobile.1.13.0` |

`UPSTREAM_VERSION=v0.36.1` and `UPSTREAM_SYNC_DATE=2026-06-16` are the intended
post-ship baseline. If this branch stops at local draft packaging, clearly mark
whether those fields are staged or already safe to treat as shipped baseline.

## Testing Design

Minimum gates:

- `swift build`;
- `bash Scripts/lint.sh lint`;
- full SwiftPM test suite or the repo sharded equivalent;
- focused provider tests for LiteLLM, Poe, Chutes, Zed, Antigravity, Copilot,
  and provider registry/icon coverage;
- `swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'`;
- `cd CodexBarMobile && xcodegen generate`;
- iOS simulator build/test;
- iOS localization audit;
- CloudKit Production schema audit;
- 16-combination sync compatibility matrix in `03-testing.md`;
- self-review and external/agent review loop until blocking findings are fixed.

## Open Questions for Implementation Audit

- Shared payload audit resolved: LiteLLM, Chutes, Zed, Antigravity, and Copilot
  use existing generic fields; Poe needed a Mac-side generic-row bridge, not a
  new wire/schema field.
- Parser audit resolved: `CostUsageScanner.swift` changed upstream; the parser
  logic version was bumped to `6`, and `CodexParserHash.generated.swift` now
  contains `fa49db79f97efca3`.
- Release audit resolved: `Scripts/release.sh` phase 1 signs/notarizes, pushes
  the tag, uploads ZIP/dSYM assets, and creates a GitHub Draft Release. This
  was run only after explicit user confirmation; live release/appcast
  finalization, TestFlight release, branch merge, and branch push remain outside
  the current boundary.
