# v0.35.0 Upstream Sync Design

Status: `in-progress`
Date: 2026-06-14

## Design Principle

Merge upstream `v0.32.5..v0.35.0` into one fork release and preserve fork-owned
release, CloudKit, iOS sync, and versioning behavior. iOS should support every
new user-visible provider datum that can reasonably flow through the Mac ->
CloudKit -> iOS path. Mac-only AppKit, browser-cookie, Keychain, Launch at Login,
and CLI process fixes stay Mac-side unless they change synced display values.

## Mac Merge Strategy

1. Merge target upstream tag `v0.35.0` into this branch from `mobile-dev`.
2. For conflicts in release tooling, preserve fork package naming,
   `mobile-dev` appcast target, Sparkle signing, CloudKit Production, and
   mobile suffix rules.
3. Preserve upstream provider fixes, parser changes, tests, and resources.
4. Reapply fork-specific iOS bridge work from the superseded v0.32.5 branch only
   where upstream merge does not already provide equivalent behavior.

Known fork boundary from the previous release: `release-cli.yml` still has
upstream Homebrew tap assumptions. Do not treat Homebrew tap dispatch as part of
the Mac Sparkle release until a fork tap/token strategy is explicitly decided.

## Shared and iOS Sync Design

### MiniMax Subscription Metadata

The v0.32.5 branch already proved this should be an additive payload-only
change:

- `ProviderUsageSnapshot.subscriptionExpiresAt`
- `ProviderUsageSnapshot.subscriptionRenewsAt`

Required behavior:

- Mac maps upstream `UsageSnapshot.subscriptionExpiresAt` and
  `subscriptionRenewsAt` into the shared provider payload.
- iOS decodes both with optional fallback and preserves them through merge/cache.
- Mixed old/new Mac writers cannot erase the metadata when one payload lacks the
  new keys.
- iOS renders the dates in a generic provider detail section with 4-language
  strings.

### New or Expanded Providers

| Provider / feature | Expected iOS approach |
|---|---|
| Devin | Add provider identity, colors, mock/sample coverage, and render generic daily/weekly windows. Add dedicated UI only if upstream data is not expressible through existing `rateWindows` / budget lanes. |
| Amp | Add provider identity, colors, mock/sample coverage, and preserve account/workspace credit balance fields if present. |
| Copilot budgets | Prefer existing budget/rate-window lanes. Add optional shared fields only if budget windows are otherwise lost. |
| Kimi Code API usage | Existing Kimi card should keep rendering usage. Proxy configuration is Mac-only unless a synced user-visible field changes. |
| MiMo paid/granted balances | Prefer existing `providerCost`/budget display; add optional component fields only if paid vs granted composition would otherwise be lost. |
| Weekly pace work days | Treat Mac as the source of truth for computed pace. Verify iOS does not independently recompute a conflicting value. |

### iOS Localization

iOS stays on the project-mandated 4-language rule:

- English
- Simplified Chinese
- Traditional Chinese
- Japanese

Upstream Mac adds more native/selectable app languages, but this release does
not expand iOS language count.

## Versioning Design

| File / field | Target |
|---|---|
| `version.env` `MARKETING_VERSION` | `0.35.0.1` |
| `version.env` `BUILD_NUMBER` | `85.1` |
| `version.env` `MOBILE_VERSION` | `1.12.0` |
| `CodexBarMobile/project.yml` `MARKETING_VERSION` | `1.12.0` |
| `CodexBarMobile/project.yml` `CURRENT_PROJECT_VERSION` | `153` |
| Sparkle version | `85.1.1.12.0` |
| GitHub tag | `v0.35.0.1-mobile.1.12.0` |

Build `152` was used by the superseded v0.32.5 TestFlight upload, so this
single-version sync uses `1.12.0 (153)` to avoid App Store Connect duplicate
build rejection while keeping one user-visible iOS version.

## CloudKit Design

Default target is payload-only optional fields inside the existing compressed
provider payload. That should not require Production schema deploy. The audit
must still inspect:

- `Shared/iCloud/CloudConstants.swift`
- new `CKRecord` types or fields
- new subscriptions/zones/indexed predicates
- `providerPayloadVersion`
- non-optional shared payload fields

## Testing Design

Minimum gates:

- `swift build`
- `bash Scripts/lint.sh lint`
- focused Mac provider/parser tests for changed providers
- iOS `xcodegen generate`
- focused iOS sync/model/cache/rendering tests
- CloudKit Production schema audit
- 16-combination 2 Mac x 2 iPhone compatibility matrix in `03-testing.md`
- final diff review with blockers fixed

## Open Questions for Implementation Audit

- Whether Devin/Amp/Copilot budget/MiMo component data already fits existing
  `UsageSnapshot` -> shared payload mapping.
- Whether upstream parser/pricing changes require both parser hash regeneration
  and `parserLogicVersion` bump.
- Whether any release tooling changes in `Scripts/` should be kept from
  upstream or replaced with fork release pipeline variants.

