# v0.45.2 Upstream Sync Development Log

Status: `done`
Date: 2026-07-19
Branch: `upstream-sync/v0.45.2-mobile.1.19.0`

## Evidence Ledger

### Round 0 — Preflight and research

- Verified clean `mobile-dev` at `6e4d605f`, equal to `origin/mobile-dev`.
- Created the required upstream-sync branch before writing files.
- Read repo workflow, versioning, compatibility, CloudKit and release gates.
- Queried open and historical closed upstream-sync issues.
- Queried authoritative upstream and fork GitHub Releases.
- Froze one release range, v0.42.0-v0.45.2, with target iOS 1.19.0.
- Fetched upstream tags into collision-safe `refs/upstream-tags/*` refs.
- Audited upstream commits, provider registry, Shared paths, release notes,
  parser surfaces and a merge-tree conflict forecast.

### Round 1 — Provenance-preserving upstream merge

- Merged collision-safe `refs/upstream-tags/v0.45.2`; the tag object is
  `64495789` and the released commit is `91560ca9`.
- Resolved 42 conflicted paths. Fork-owned PR Fast/Final CI triggers,
  CloudKit/mobile release scripts, appcast, Mobile Settings, composite
  versioning and Production entitlements were preserved.
- Integrated upstream implementation/security improvements into the fork
  policy rather than restoring upstream's heavy PR-update CI.
- Unioned upstream locale additions with Mobile/iCloud strings. The complete
  catalog gate now validates all 22 non-English Mac catalogs.
- Combined upstream cost/parser changes with the fork's pricing fingerprint
  and fallback logic; advanced `parserLogicVersion` to 9 and regenerated
  `CodexParserHash` to `5b23d719648d20de` after the final pricing fix.
- Kept upstream removal of `kimik2` and `crossmodel` from the Mac provider
  registry while preserving their Shared/iOS decoding, colors, cards and
  notification IDs for rolling-upgrade compatibility.

### Round 2 — Shared wire and iOS bridge

- Added optional `SyncSub2APIUsage`, `SyncWayfinderUsage` and
  `SyncProviderAmount` typed payloads. All decode with `decodeIfPresent`;
  `providerPayloadVersion` remains 1. `SyncProviderAmount` keeps
  Neuralwatt/ZenMux balances and ai& uncapped spend out of the budget lane, so
  iOS never renders `$X / $0`.
- Mapped all generic third-and-later quota lanes into named `rateWindows`, so
  ClinePass, LongCat, Neuralwatt, ZenMux and future providers do not lose
  Daily/Weekly/Monthly/Additional windows.
- Added a single Shared `hasUsableSignal` contract used by both the Mac
  per-provider writer and iOS `SnapshotCache`. This fixed a review-discovered
  bug where typed-only Wayfinder telemetry was misclassified as a ghost and
  only 76 of 77 QA envelopes reached CloudKit.
- Tail-appended eight new notification provider IDs. The list now covers 65
  current-plus-legacy providers and 195 deterministic subscriptions; old IDs
  were not reordered or removed.
- Added first-class provider colors, 77 QA snapshots across 67 IDs, typed
  sub2api/Wayfinder detail cards, merger preservation, wire round trips and
  cache tests. New Mac debug data distinguishes 63 current IDs, two legacy
  compatibility IDs and two synthetic fallback IDs.
- Added iOS 1.19.0 release notes in all four required languages, technical
  CHANGELOG entries and version/build updates for every target.

### Round 3 — One-version and release preparation

- Applied Mac `0.45.2.1 (109.1)`, iOS `1.19.0 (188)`, composite Sparkle build
  `109.1.1.19.0`, and candidate tag
  `v0.45.2.1-mobile.1.19.0`.
- Updated `UPSTREAM_VERSION=v0.45.2` and
  `UPSTREAM_SYNC_DATE=2026-07-19`.
- Regenerated the Xcode project from `project.yml`; no `.xcodeproj` field was
  hand-edited.
- CloudKit diff audit against the last live fork tag returned `NO_DEPLOY`:
  only optional JSON members inside the existing compressed provider payload
  changed. CKRecord types/fields/indexes/predicates did not. The eight appended
  warning providers do create 24 new per-user runtime custom-zone/subscription
  instances, but all reuse the existing `QuotaTransition` schema and therefore
  require no Dashboard deploy.

### Round 4 — Test/review fixes found during integration

- Fixed upstream v0.45.2's exact built-in Codex pricing path, which accepted
  `cacheWriteInputTokens` but failed to pass it to the calculator. GPT-5.6 and
  Pi cache invalidation tests now exercise the corrected cost.
- Fixed upstream plural rendering on systems whose current locale differs
  from the selected app language. Duplicate `.strings` entries no longer
  mask `.stringsdict`, and formatting now uses the app-selected locale, so
  English correctly renders `1 window`.
- Adapted one upstream segmented-cache test to explicitly exercise Mac-only
  behavior with iCloud disabled. Separate fork tests keep iCloud-on
  multi-account fan-out mandatory.
- Applied the same isolation to the ordinary selected-account quota-warning
  test; the iCloud-on fan-out contract remains pinned by sync-specific suites.
- Made subscription expiry and plural formatting use the app-selected locale,
  then corrected the MiniMax fixture helper so tests assert the same contract.
- Replaced an invalid escaped-quote Swift backticked iOS test identifier that
  the Mac-only build could not compile; the final iOS gate then passed all 553
  tests.
- The pre-review automated gates passed before the identity/CWL hardening
  below; the final post-review counts are recorded in Round 6 and
  `03-testing.md`.

### Round 5 — Independent review blockers

- Restored 32 existing Simplified Chinese Mac strings that an upstream merge
  fallback had replaced with English, and corrected the 77-snapshot/67-ID mock
  subtitle across every Mac locale.
- Added `accountRecordKey` so token account CloudKit IDs use persisted UUIDs,
  not duplicate/renameable labels or strings containing `|`. Record, cache,
  SwiftData and SwiftUI identity paths prefer the opaque key while retaining
  the label for display. Wayfinder uses the same lane with a stable device key.
- Extended mixed-version lane merging to Claude: overlapping lanes take the
  freshest writer while scoped lanes from a new Mac survive when an old Mac is
  slightly fresher.
- Localized canonical Daily/Weekly/Monthly/Additional wire labels at the iOS
  rendering boundary; provider-specific names such as Web Sonnet remain
  untouched. Added presentation-level assertions for sub2api amount/mode and
  Wayfinder status.
- Documented the unavoidable forward-rendering limit: iOS 1.18 decodes new
  payloads without crashing, but its old ghost filter can hide typed-only
  Wayfinder and wallet-only sub2api. iOS 1.19 fixes that via `hasUsableSignal`.
- Review-fix gate passed focused mapper/wire and iOS identity/CWL/presentation
  suites. Full final gates were rerun after the final review.

### Round 6 — Final identity, ledger and review closeout

- Marked synthesized editable token-account labels explicitly so Mac identity
  mapping never treats a user-editable label as an authenticated email.
  Authenticated email/org identities still merge one account across Macs;
  persisted opaque UUID record keys keep equal-label accounts distinct.
- Extended iOS Cost Window Ledger rows and rollups with the opaque record key
  plus the complete account identity set. Overlap-union now joins mixed
  email-only, org+email and org-only writers without collapsing record-only
  accounts that happen to share a label.
- Added an in-place legacy ledger rekey before incremental CloudKit deletes,
  including same-delta upsert/migrate/delete ordering and record-name parsing
  that preserves legacy labels containing `|`. Long history therefore survives
  the 1.18-to-1.19 identity-key transition.
- Localized all canonical generic quota-window and provider-amount period
  labels in English, Simplified Chinese, Traditional Chinese and Japanese;
  unknown provider-defined values intentionally remain verbatim.
- The first final Mac run exposed one stale test fixture: it expected an email
  record name after the production contract had moved token accounts to opaque
  keys. The fixture now uses real Settings account IDs and verifies Bob's
  opaque record is the sole two-cycle deletion. Its suite passed 11/11 before
  the full rerun.
- Final gates: lint and release-policy checks passed with 0 SwiftLint findings,
  22 Mac catalogs / 1,369 keys and 303 iOS source keys; Mac passed 7,531 tests /
  732 suites; iOS passed 566 tests / 41 suites; compatibility focus passed 81
  Swift Testing tests / 11 suites plus 1 XCTest; iOS Release simulator build
  succeeded.
- Two independent final review tracks reported **0 blockers**: Shared/iOS sync,
  identity, ledger, old-reader and localization; and Mac merge, versioning,
  CI/release/appcast/draft-only boundaries.

### Round 7 — Merge commit, notarization and draft release

- Created provenance-preserving merge commit `e1f1b346`; its parents are fork
  research commit `bc45da1d` and upstream v0.45.2 commit `91560ca9`. The
  artifact embeds `CodexGitCommit=e1f1b346`.
- The first package attempt found a stale Xcode-derived Commander repository
  missing the v0.2.3 tree. The cache was repaired by fetching the exact locked
  tag. A later widget resolve waited in SwiftPM Keychain authorization while
  downloading Sparkle; the locked Sparkle 2.9.4 archive was instead downloaded
  directly, verified against checksum
  `cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0`,
  and registered only in the ignored derived workspace. The independent
  universal widget Release build then succeeded.
- Signed every nested component with `Developer ID Application: Yuxiao Wang
  (3TUERHN53E)`. Apple notarization submission
  `3464f526-9ace-47c8-ba77-51af175200ed` returned `Accepted`; staple validation,
  Gatekeeper assessment and the two-second direct launch gate all passed.
- Packaged `CodexBar-0.45.2.1-mobile.1.19.0.zip` and matching dSYM. The app is
  universal `x86_64 arm64`; both app UUIDs match the dSYM; the Production
  CloudKit entitlement is present.
- Created GitHub release ID `356471765` as `draft=true`, target `mobile-dev`,
  with both assets uploaded and server digests matching local SHA-256 values:
  <https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-25ceca7188ab7ee13644>.
- Confirmed the candidate tag is absent locally and on `origin`; `appcast.xml`
  remains byte-identical to `origin/mobile-dev`. Candidate Sparkle version
  `109.1.1.19.0` matches the packaged plist and is monotonic over published
  `100.1.1.18.0`.

The authorized draft-only train is complete. Push, merge, tag publication,
live release, appcast publication, TestFlight upload and CloudKit deploy remain
intentionally unperformed.
