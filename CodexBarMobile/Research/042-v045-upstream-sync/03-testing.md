# v0.45.2 Upstream Sync Test Evidence

Status: `done`
Date: 2026-07-19

## Environment

- Old Mac: published fork `0.41.0.1 (100.1.1.18.0)`
- New Mac: candidate `0.45.2.1 (109.1.1.19.0)`
- Old iPhone: iOS `1.18.0 (187)`
- New iPhone: candidate iOS `1.19.0 (188)`
- Branch base: `6e4d605f`
- Upstream target: `v0.45.2`, peeled commit `91560ca9`

## Command Evidence

Commands that can prompt for Keychain or touch real provider sessions are
excluded unless separately authorized.

| Gate | Command / evidence | Result |
|---|---|---|
| Merge build | `swift build` | pass |
| Shared mapper/wire focus | `swift test --filter 'AccountIdentityComputerTests\|SyncProviderMapperTests\|SyncWireFormatRoundTripTests'` | 52 tests / 3 suites pass |
| iOS identity/CWL/presentation focus | `xcodebuild` with CWL writer/aggregate, SwiftData bridge, snapshot cache, CloudKit merge and v0.45 presentation suites | 159 tests / 6 suites pass |
| iOS unit gate | `xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,id=624F0D2B-C204-44BF-A979-3A7F0AAA0EF3' -only-testing:CodexBarMobileTests test` | pass; 566 tests / 41 suites, 0 failures, 4.063 s |
| iOS Release build | `xcodebuild ... -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` | `BUILD SUCCEEDED`; app, widget and push extension compiled for arm64 and x86_64 simulator |
| Provider subscriptions | focused `QuotaProviderListTests` | 33 tests pass; 65 providers × 3 notification kinds = 195 IDs |
| Mac locale catalog | `node Scripts/check-app-locales.mjs` | pass; 22 complete catalogs, 1,369 English keys after plural-key de-duplication |
| Portable/release lint | `bash Scripts/lint.sh lint` | pass; package/signing/release CLI, sharding, CI policy, repository size, shell/docs/site locale, SwiftFormat (0/1,627) and iOS catalog (303 source keys) gates all pass |
| SwiftLint | `.build/lint-tools/bin/swiftlint --strict --quiet` | pass, 0 violations |
| Full Mac tests | `swift test --no-parallel` | pass; 7,531 tests / 732 suites, 0 failures, 281.346 s |
| Sync compatibility focus | `swift test --no-parallel --filter 'AccountIdentity|MultiAccount|DualZoneReader'` | pass; 81 Swift Testing tests / 11 suites plus 1 XCTest, 0 failures |
| Working-tree integrity | `git diff --check`; `git diff --cached --check`; unresolved-path query | pass; no whitespace errors and no unresolved merge paths |

## Release Artifact Evidence

| Check | Result |
|---|---|
| Merge commit | `e1f1b346e1c6b7cef0e9cbe772e20105877e8c72`; parents `bc45da1d` + `91560ca9` |
| Notarization | submission `3464f526-9ace-47c8-ba77-51af175200ed`; `Accepted`; staple validate pass |
| Signing / Gatekeeper | Developer ID `3TUERHN53E`; deep strict codesign pass; `source=Notarized Developer ID` |
| Packaged plist | Mac `0.45.2.1`; Sparkle `109.1.1.19.0`; Mobile `1.19.0`; commit `e1f1b346` |
| App archive | 55,674,294 bytes; SHA-256 `ee7760516aafbcf331b3927188fc0d2f64206379634b469c06c1181f01ff6700` |
| dSYM archive | 42,783,846 bytes; SHA-256 `d3a5c465da4953f435530a8eaf4a1e5913ac698b3ff37ff003ab2dfdc3a7606f` |
| Architectures / UUIDs | `x86_64` `A51C5DA5-7B5C-3C2A-B9BF-7A35CF67ADAD`; `arm64` `1A49E406-1FBE-3551-827A-B5856E9870D3`; both match dSYM |
| CloudKit entitlement | packaged app contains `com.apple.developer.icloud-container-environment=Production` |
| Draft release | release ID `356471765`; `draft=true`; two uploaded assets and server digests match local hashes |
| Publication boundary | no local/remote tag; no push/merge/live publish/TestFlight; appcast unchanged |

## 2 Mac x 2 iPhone Compatibility Matrix

Every row is required because provider identity, display data, rate windows,
multi-account merge, caches and legacy-provider behavior change. No row below
is claimed as a physical-device pass.

Substituted evidence bundles:

- **S0 — published-old control:** the old side is the unchanged live Mac
  `0.41.0.1` / iOS `1.18.0` pair; no candidate code participates in the
  all-old control.
- **S1 — old writer → new reader:** old-shaped fixtures omit every new key;
  new `ProviderUsageSnapshot` uses `decodeIfPresent`, and focused wire plus
  legacy snapshot suites decode them. `SnapshotCache` and
  `ProviderSnapshotMerger` preserve per-device/account ownership.
- **S2 — new writer → old reader:** the live 1.18 decoder was audited at the
  published tag. JSON decoding ignores unknown keys and all new members are
  additive optionals inside the existing payload; required keys and payload
  version are unchanged, so decoding does not crash. However, the published
  1.18 ghost filter only recognizes generic fields: typed-only Wayfinder and a
  wallet-only sub2api snapshot can be filtered from rendering. This known
  forward-rendering gap cannot be fixed in the already-published binary.
  Published 1.18 also upserts its local cache by
  `providerID|accountEmail`, ignores `accountRecordKey`, and interprets the
  third CloudKit record-name component as that same email key when processing
  incremental deletes. Therefore two new-Mac token accounts with the same
  editable label can collapse on an old reader, and a UUID-keyed delete can
  leave the old email/label-keyed cache row stale until a full replay. These
  are old-reader cache/identity limitations, not decode failures. This is
  code-audit substitution, not an executed old binary or a claim of full
  new-provider or multi-account preservation.
- **S3 — mixed writers/readers:** `SyncMultiAccountEdgeCases`, account identity,
  snapshot priority/cache, merger and ghost-cleanup suites exercise two device
  IDs, account switching, legacy/per-provider priority, stale deletion and
  latest-non-nil typed fields. Claude named lanes are unioned in both freshness
  orders. On the new reader, source-marked editable-label fallbacks use opaque
  token UUIDs while authenticated email/org identities still merge the same
  account across Macs; Wayfinder device keys keep two gateways distinct. These
  identity guarantees do not apply to the published 1.18 cache path described
  in S2.
- **S4 — provider rollout:** eight IDs are tail-appended while `kimik2` and
  `crossmodel` remain subscribed/renderable. Tests pin 65 provider IDs × 3
  notification kinds, 77 QA records, distinct CK record names and stable
  ordering.
- **S5 — typed payload safety:** wire round trips cover sub2api and Wayfinder;
  Mac+iOS share `hasUsableSignal`; the 77-envelope test proves typed-only
  Wayfinder is not filtered as a ghost.
- **S6 — candidate reader/UI:** full iOS unit/build gates cover new cards,
  palette, generic lanes, release catalog, localization, cache and widgets.
  Formatter/presentation assertions directly cover sub2api balance/mode,
  Wayfinder status, uncapped monetary values and the four semantic window
  labels. The final candidate gate passed 566 tests / 41 suites; the focused
  identity/CWL/presentation gate passed 159 tests / 6 suites; the final Release
  simulator build succeeded after review.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | S0 | Historical live baseline; not rerun on four devices |
| 2 | old | old | old | new | substituted | S0, S1, S3 | New reader, legacy writers |
| 3 | old | old | new | old | substituted | S0, S1, S3 | Independent new-reader cache |
| 4 | old | old | new | new | substituted | S1, S3, S6 | Both new readers, legacy writers |
| 5 | old | new | old | old | substituted | S0, S2, S3, S4, S5 | Both old readers have typed-only, duplicate-label collapse and incremental-delete stale-cache gaps |
| 6 | old | new | old | new | substituted | S1-S6 | New reader preserves data; old reader has all S2 gaps |
| 7 | old | new | new | old | substituted | S1-S6 | Mirrored order; old reader has all S2 gaps |
| 8 | old | new | new | new | substituted | S1, S3-S6 | Mixed writers, both new readers |
| 9 | new | old | old | old | substituted | S0, S2-S5 | Reversed writers; both old readers have all S2 gaps |
| 10 | new | old | old | new | substituted | S1-S6 | Reversed order; old reader has all S2 gaps |
| 11 | new | old | new | old | substituted | S1-S6 | New reader preserves data; old reader has all S2 gaps |
| 12 | new | old | new | new | substituted | S1, S3-S6 | Reversed writers, both new readers |
| 13 | new | new | old | old | substituted | S2-S5 | Decode-safe; both old readers have typed-only, duplicate-label collapse and incremental-delete stale-cache gaps |
| 14 | new | new | old | new | substituted | S2-S6 | New reader complete; old reader has all S2 gaps |
| 15 | new | new | new | old | substituted | S2-S6 | New reader complete; old reader has all S2 gaps |
| 16 | new | new | new | new | substituted | S3-S6 | Full candidate automated environment |

Required observations per row: both writers retain distinct device/account
ownership; all readers decode without crash; new readers preserve provider
rows and quota lanes without duplication or disappearance; representable
generic fields remain readable on old readers; both phones converge within
the limits of their renderer; retired provider records remain readable;
stale/ghost records do not reappear on the new reader; and balances/costs do
not become impossible values. The S2 typed-only rendering, duplicate-label
collapse and incremental-delete stale-cache behaviors are the explicit
exceptions for rows containing a new Mac and old iPhone.

Substitution limitation common to all rows: these suites do not prove real
CloudKit silent-push delivery, background scheduling, independently persisted
device IDs, propagation latency, or eventual convergence between two physical
iPhones. Cases containing an old reader also lack executable old-binary proof;
their forward-compatibility result is based on the published decoder source and
JSON's unknown-key behavior.

## CloudKit Production Audit

Verdict: **`NO_DEPLOY`**. No CloudKit Dashboard action is authorized or
required for this train.

- Audit base: live fork tag `v0.41.0.1-mobile.1.18.0`.
- `CloudConstants.swift`: no diff; `providerPayloadVersion` remains `1`.
- Record types, CKRecord field names, indexes, subscription predicates and
  container identifiers: no change.
- Shared change: four additive optionals (`wayfinderUsage`, `sub2APIUsage`,
  `providerAmount`, `accountRecordKey`) in `ProviderUsageSnapshot`, encoded
  inside the existing zlib-compressed JSON payload. Old decoders ignore
  unknown JSON keys; new decoders use `decodeIfPresent` for missing keys.
- Mac packaging and iOS entitlements both explicitly select CloudKit
  `Production`.
- The eight appended providers create 24 new runtime private custom-zone and
  `CKRecordZoneSubscription` instances (provider × below/above/recovery).
  They reuse the existing `QuotaTransition` record fields, query contract and
  per-user zone creation path, so they do not require Dashboard fields,
  indexes or a Production schema deploy.

## Residual Risk

The available environment has one Mac and Simulator, not two independently
version-pinned Macs plus two independently version-pinned physical iPhones.
The matrix therefore cannot be represented as real-device pass evidence; each
row will be marked `substituted` with exact automated/code-audit evidence and
the unverified push/background/convergence risk.
Rows with a new Mac and old iPhone additionally retain the documented iOS 1.18
typed-only ghost-filter rendering gap, same-label token-account collapse, and
UUID incremental-delete stale-cache gap until full replay. JSON decode
compatibility is proven; full presentation, multi-account identity and
incremental-delete convergence compatibility are not.
