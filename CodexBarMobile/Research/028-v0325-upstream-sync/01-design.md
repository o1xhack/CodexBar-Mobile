# v0.32.5 Upstream Sync Design

Status: `in-progress`
Date: 2026-06-10
Branch: `upstream-sync/v0.32.5-mobile.1.12.0`

## Goals

1. Merge upstream `v0.32.5` as one fork release, not as multiple user-visible versions.
2. Preserve fork-specific release, Sparkle, CloudKit, iOS sync, and versioning rules.
3. Keep all upstream Mac features/fixes unless they conflict with fork release or sync constraints.
4. Add the iOS support needed for new upstream user-visible provider data.
5. Produce test evidence for Mac, iOS, CloudKit audit, and the 16-case sync compatibility matrix.

## Merge Strategy

- Merge target: upstream tag `v0.32.5`.
- Preserve fork ownership for:
  - `version.env` fork fields.
  - `appcast.xml` fork appcast until draft release packaging replaces it.
  - fork-only CloudKit/iOS sync files under `Shared/`, `Sources/CodexBar/Sync/`, and `CodexBarMobile/`.
  - release notes/changelog sections that describe mobile-only work.
- Accept upstream Mac changes for menu, provider, localization, Codex, MiniMax, Antigravity, Cursor, Claude, Kiro, and pricing unless they break fork constraints.

## Shared Payload Extension

Upstream `v0.32.5` introduces generic subscription metadata on `UsageSnapshot`:

- `subscriptionExpiresAt: Date?`
- `subscriptionRenewsAt: Date?`

Mac uses those fields to show notes such as `Renews: ...` and `Plan expires: ...`. MiniMax currently populates these fields, and future providers can reuse the same lane.

Design:

- Add optional `subscriptionExpiresAt` and `subscriptionRenewsAt` to `ProviderUsageSnapshot`.
- Use `decodeIfPresent` and default initializer values so old Mac and old iOS payloads remain compatible.
- Keep `providerPayloadVersion` unchanged; this is an additive optional JSON field inside the existing payload.
- Map from `UsageSnapshot` in `SyncCoordinator.buildProviderUsageSnapshot`.
- During iOS multi-device merge, use `latestNonNil` semantics so an old Mac cannot erase a newer Mac's subscription metadata.
- Persist through the SwiftData mirror using encoded optional fields or direct optional dates so app relaunch/offline cache does not lose the values.
- Render on iOS near provider header or detail surface with localized strings:
  - `Renews %@`
  - `Plan expires %@`

## MiniMax Points Balance

Upstream `MiniMaxUsageSnapshot.toUsageSnapshot()` maps points balance into `providerCost` with currency `Points`. The fork already maps `providerCost` to `SyncBudgetSnapshot` and iOS renders provider `budget`. No new wire field is planned for points balance unless merge evidence shows `providerCost` is not populated.

## Pace / Deficit Details

Cursor, Codex Spark, and Claude pace/reserve improvements are currently Mac menu presentation logic. Existing sync fields include window percentages, reset dates, and labels, but not generic pace-detail labels. This release will not invent a synthetic iOS pace wire lane unless implementation shows upstream exposes a reusable data model that can be mapped without guessing.

Verification requirement:

- Confirm iOS still receives and displays the corrected windows.
- Record the gap explicitly if Mac-only pace labels cannot be represented on iOS without a new upstream/fork contract.

## iOS Localization Scope

The Mac app gains selectable French, Ukrainian, Dutch, and Vietnamese language resources. iOS remains governed by AGENTS.md's mandatory 4-language rule:

- English
- Simplified Chinese
- Traditional Chinese
- Japanese

This release does not expand iOS language support. New iOS strings must still include all four existing languages.

## CloudKit Design

No CloudKit Production schema deploy is expected if all new data stays inside existing compressed sync payloads. Audit must still run:

- grep for new `CKRecord` field writes.
- grep for new record types/zones/subscriptions/index-affecting predicates.
- document verdict in `03-testing.md`.

## Versioning

Per `docs/versioning.md`:

- Upstream Mac base: `0.32.5` / `80`.
- Fork patch: `.1`.
- Target Mac: `0.32.5.1`, build `80.1`.
- Target mobile: `1.12.0`, build `152`.
- Sparkle version: `80.1.1.12.0`.

Do not update `UPSTREAM_VERSION` to `v0.32.5` until the synced release is live to users.

## Risks

| Risk | Mitigation |
|---|---|
| Large upstream menu refactor conflicts with fork sync code | Merge in small conflict batches; run Mac build/tests before iOS work. |
| New subscription fields decode on new iOS but are absent on old Mac | Optional decode + `latestNonNil` merge. |
| Old iOS ignores new fields from new Mac | Additive JSON fields are ignored by old app versions. |
| SwiftData mirror drops newly added fields on relaunch | Persist the new values in the mirror path. |
| Parser hash mismatch after models.dev memoization | Run parser-hash/check or relevant cost tests; regenerate if required. |
| CloudKit schema accidentally changed | Run `docs/cloudkit-deploy-audit.md` commands and record verdict. |
