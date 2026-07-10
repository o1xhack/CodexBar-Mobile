# v0.41.0 Upstream Sync Development Log

Status: `in-progress`
Date: 2026-07-09
Branch: `upstream-sync/v0.41.0-mobile.1.18.0`

## Evidence Ledger

This file records implementation decisions, conflict resolutions, commit IDs,
and scope changes. Command outputs and final pass/fail results belong in
`03-testing.md`.

## Round 0 — Preflight and Research

- Refreshed clean `mobile-dev` to `origin/mobile-dev` at `8248714e`.
- Created the required work branch before editing files.
- Consolidated open upstream-sync issues #42, #44, and #46 into target
  `v0.41.0` / iOS `1.18.0`.
- Fetched upstream tags into the collision-safe `refs/upstream-tags/*`
  namespace because old fork tags and upstream tags share names.
- Verified `v0.39.0` is already an ancestor of the branch.
- Audited the upstream tag range, release notes, current Shared mapper, Kimi
  snapshot shape, Claude plan label, mobile formatter, versioning, sync
  compatibility, CloudKit deploy, and release docs.
- Forecast ten merge conflicts; see `00-overview.md`.

## Planned Rounds

### Round 1 — Upstream merge

- Merged `refs/upstream-tags/v0.41.0` as `00a13189`.
- Resolved all ten forecast conflicts. Fork-owned release/appcast/monitor files
  retained their fork targets; upstream CI toolchain pinning, Mac features,
  security changes, and tests were preserved.
- Combined `SubprocessRunner` semantics: fork wall-clock timeouts remain, while
  upstream infinite-timeout `runToCompletion` no longer installs a timer.
- Combined browser cookie semantics: explicit retry context now survives the
  GCD hop while the fork's single-completion wall-clock timeout remains.
- Bumped `parserLogicVersion` 7 → 8 and regenerated parser hash
  `67c76db38c18af6a` because upstream changes persisted cost-cache completion
  and Claude Desktop project discovery.
- Stabilized the upstream Kimi total-budget timing test so a loaded shard still
  distinguishes the 20 ms join grace from awaiting the full enrichment call.
- `swift build` passed; the 241-test merge/conflict filter passed after the
  timing-test stabilization; release secret-loader tests passed.

### Round 2 — Shared/iOS bridge and UX

- Code audit proved no new Shared field is required:
  - Kimi primary/secondary/extra windows map into existing `rateWindows`;
  - Claude Max multiplier maps into existing optional `loginMethod`.
- Added Mac-to-iOS tests for Kimi lane order and Claude Max 20x encode/decode.
- Updated `UsagePercentDisplayMode` so positive displayed values below 1% use
  `<1%` in both Used and Remaining modes; exact zero remains `0%`.
- Added three focused iOS formatter tests.
- XcodeBuildMCP build/run succeeded on booted iPhone 17 / iOS 26.4 and the app
  launched into the Chinese onboarding UI.
- Focused iOS formatting tests passed 10/10; the complete iOS unit target passed
  582/582, including WidgetSnapshotBuilder and widget render-matrix suites.
- Independent review found that a fresher old Mac could hide the Kimi Code
  7-day lane or replace Claude Max 5x/20x with a generic Max label. Added a
  narrow rolling-upgrade merge policy: overlapping Kimi values still come from
  the freshest writer while named missing lanes survive, and only generic
  Claude Max yields to a specific 5x/20x label. A genuinely different fresh
  plan still wins.
- Rewrote the 1.18 release notes in plain user language across all four
  locales. A second review made the Claude rule provenance-aware: only a
  generic value from a source app older than 0.41 yields to 5x/20x; a current
  generic value and genuinely different current plan remain authoritative.
  Post-review focused merge tests passed 49/49; full iOS passed 589 with 0
  failures and 4 skipped; build+launch passed on iPhone 17 / iOS 26.4.

### Round 3 — Version and release documentation

- Set Mac `0.41.0.1` / `100.1`, Mobile `1.18.0`, upstream bookmark `v0.41.0` /
  `2026-07-06`, and iOS `1.18.0 (186)` across all targets.
- Updated root/iOS changelogs and generated-project settings.
- Added the 1.18 in-app release block and complete English, Simplified Chinese,
  Traditional Chinese, and Japanese translations; 401/401 source keys pass the
  catalog audit with no `state=new` entries.
- `changelog-to-html.sh 0.41.0.1` selects the fork section and safely renders
  the less-than-one-percent text.
- CloudKit audit against `v0.39.0.1-mobile.1.17.0` found no schema keyword,
  `CloudConstants.swift`, or `UsageSnapshot.swift` field diff. Mac/iOS
  entitlements remain Production. Verdict: no Dashboard deploy required.

### Round 4 — Release artifacts and full gates

- Imported the upstream SwiftFormat policy mechanically across 33 Swift files;
  this converted legacy Swift Testing names to sentence-style backticked names
  and removed one redundant generic annotation. Split the two v0.41 sync tests
  into their own suite to keep `SyncCoordinatorTests` below the SwiftLint body
  limit.
- Full repository lint passes with zero SwiftFormat/SwiftLint violations.
- The release-checklist multi-account filter passes 76/76. All suites exposed
  by high-core-count parallel timing flakes pass in focused runs, and the
  complete `swift test --no-parallel` gate passes 5,810/5,810.
- Recorded all 16 compatibility rows with explicit substituted evidence and
  real-hardware residual risk.
- Signed, notarized, stapled, launch-verified, and packaged the universal Mac
  app plus dSYM. Apple accepted submission
  `90287227-c47a-409d-96b4-91ca190b4be9`.
- Generated and locally verified the candidate appcast against the exact ZIP.
- Remote draft creation is correctly blocked: creating an accurate draft
  requires publishing the target commit/tag, which this Goal did not authorize.

### Round 5 — Review loop

- Self-review and three independent agent reviews completed.
- Fixed the mixed-writer compatibility blocker, technical iOS release notes,
  historical changelog collision, CloudKit evidence false positive,
  release-branch changelog link, and missing historical prior-art ledger.
- Reran focused/full iOS, build+launch, lint/i18n, source-only CloudKit audit,
  appcast validation, and Sparkle verification. Authorized-scope blocker count
  is zero; only remote draft push/tag authority remains.
