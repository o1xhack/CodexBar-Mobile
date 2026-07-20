# v0.45.2 Upstream Sync Design

Status: `done`
Date: 2026-07-19

## Design Principle

Merge the published `v0.41.0..v0.45.2` range as one provenance-preserving
upstream merge. Keep all upstream Mac behavior unless it conflicts with a
fork-owned Mobile, sync, CloudKit Production, CI, release or versioning
contract.

## Merge Strategy

1. Merge `refs/upstream-tags/v0.45.2` into the isolated branch with a merge
   commit.
2. Preserve fork-owned `.github/workflows/pr-fast.yml`, Final-CI trigger
   semantics, `Scripts/check_ci_policy.sh`, the version-driven upstream
   monitor, signing/notarization scripts, appcast, Mobile Settings entry,
   CloudKit Production entitlements and composite version construction.
3. Incorporate upstream CI implementation/security improvements deliberately
   into the fork trigger model instead of choosing either conflict side in
   bulk.
4. For Mac localizations, retain every upstream translation and reapply the
   fork's Mobile/iCloud strings; audit catalog parity afterward.
5. For parser conflicts, combine upstream scanner/cache fixes with fork cost
   integrity work, bump `parserLogicVersion`, and regenerate the hash from the
   resolved sources.
6. Keep the published fork appcast unchanged until local candidate artifacts
   are signed, notarized and verified.

## Shared and Provider Contract

The preferred wire contract remains additive and generic:

- quota lanes use `primary`, `secondary` and named `rateWindows`;
- multi-account ownership uses the existing stable account identity fields;
- balances, spend and limits use existing credits/budget/cost summary fields;
- plan/source/expiry detail uses existing optional identity/metadata fields;
- old clients must ignore absent or new optional values;
- new clients must preserve legacy provider IDs and records during rollout.

Do not bump `providerPayloadVersion` or `encodingVersion` unless a required
wire migration is proven. Do not add a required payload key. If an upstream
value cannot be represented losslessly, first classify whether it is a local
Mac-only operation (credentials, gateway control, hooks, menu actions) or a
user-visible synced value. Only the latter can justify a new optional field.

Post-merge decision: generic fields cover six providers losslessly. sub2api
account totals and Wayfinder routing/savings do not fit the generic contract,
so `SyncSub2APIUsage` and `SyncWayfinderUsage` are additive optional fields.
Neuralwatt/ZenMux balances and ai& uncapped spend also cannot be represented
as a zero-limit budget without producing an impossible `$X / $0` UI, so they
use additive `SyncProviderAmount`. Token accounts receive an opaque,
non-secret UUID-derived `accountRecordKey`; the editable display label remains
in `accountEmail`. Wayfinder uses a device-scoped record key so two local
gateways never collapse into one card. None of these changes bumps either
payload version or adds a required CloudKit field.

Storage identity and cross-device merge identity are deliberately separate.
SwiftData/CWL uniqueness prefers `accountRecordKey`, while a stored complete
identity set lets rollups union mixed-version writers when any authenticated
email/org identity overlaps. Legacy rows are rekeyed before applying an
incremental delete from the same CloudKit delta, so an iOS 1.18 email-keyed
history is not lost when iOS 1.19 first observes the UUID-keyed record. A
record-only account never unions on its editable label.

## iOS Provider Coverage

For the eight new provider IDs:

1. Tail-append them to `QuotaProviderList`; retain `kimik2` and `crossmodel`
   for old-Mac compatibility.
2. Add first-class mock profiles and update all cardinality/collision tests.
3. Add distinct `ProviderColorPalette` entries with specific substring rules
   before broad matches.
4. Exercise generic provider cards, rate-window ordering, multi-account
   identity and cost/balance formatting with focused fixtures.
5. Add dedicated rendering only when the generic wire/card loses a real
   user-visible value.

`PreviewData.swift` is audited by card type; generic providers do not each
need a separate preview when the new data shapes are already represented.

Removed Mac providers remain accepted by iOS decode/cache/render paths. This
is a rolling-upgrade compatibility decision, not a promise that new Mac builds
continue fetching them.

## Versioning and Documentation

- Mac: `0.45.2.1 (109.1)`
- iOS: `1.19.0 (188)` for all four targets
- Sparkle/app build: `109.1.1.19.0`
- candidate tag: `v0.45.2.1-mobile.1.19.0`
- root changelog: Mobile summary first, then intact upstream release sections
- iOS changelog: technical compatibility/provider changes
- in-app release notes: one `1.19.0` block, plain language, four locales

## CloudKit Design

Expected verdict: no Production schema deploy.

- no planned record type, CKRecord field, subscription predicate or index
  change;
- the eight provider IDs add 24 runtime private custom zone/subscription
  instances (provider × warning state), all reusing the existing
  `QuotaTransition` record contract; this is per-user runtime data, not a
  Dashboard schema deployment;
- Shared JSON remains inside the existing compressed opaque payload;
- retained legacy subscriptions avoid a destructive mixed-version cleanup.

The final audit follows `docs/cloudkit-deploy-audit.md` against
`v0.41.0.1-mobile.1.18.0..HEAD`. Any actual record-schema change pauses the
Goal before Dashboard deploy.

## Test Plan

- Merge/conflicts: `swift build`, portable lint, CI policy guard, locale audit,
  release-script tests and conflict-focused Mac tests.
- Mac: full `swift test`, multi-account/multi-device filters, new provider
  parsers, process/PTY/TaskLocal regressions, cost scanner/cache, settings,
  widgets and existing-provider regressions.
- Parser: focused scanner/JSONL/cache tests, parser version audit and generated
  hash audit.
- Shared/iOS: provider mapper, old/new wire round trips, quota subscriptions,
  mock coverage, palette, generic cards, costs, account identity, widgets and
  complete iOS unit target.
- Builds: Mac release build; iOS simulator and generic-device Release build.
- Compatibility: all 16 old/new device combinations, real hardware when
  available and explicit substituted evidence/risk otherwise.
- Release: signed/notarized/stapled local app and archives, Production
  entitlement, Gatekeeper, candidate appcast/version checks, no live publish.
- Review: self-review after merge, Shared/iOS, and release rounds; use available
  independent review capability and repeat until blocking findings are zero.

## Authorization Boundary

Local commits, tests, signed/notarized artifacts, a candidate appcast and draft
release metadata are authorized. Do not push, merge, publish a tag, publish a
live release, upload TestFlight, submit to the App Store or deploy CloudKit.
