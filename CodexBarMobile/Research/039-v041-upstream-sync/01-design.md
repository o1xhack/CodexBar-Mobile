# v0.41.0 Upstream Sync Design

Status: `done`
Date: 2026-07-09

## Design Principle

Merge upstream `v0.39.0..v0.41.0` as one fork release. Preserve upstream Mac
functionality, fixes, performance work, security hardening, tests, and provider
behavior. Preserve fork-owned release/versioning, CloudKit Production,
Mac-to-iOS sync, Mobile Settings pane, and iOS app behavior when resolving
conflicts.

## Merge Strategy

1. Merge `refs/upstream-tags/v0.41.0` into the isolated branch with a merge
   commit so upstream provenance stays reviewable.
2. For conflict files:
   - take upstream functional changes first;
   - retain fork CI jobs and upstream-release monitor semantics;
   - combine root changelog content with fork Mobile highlights first;
   - keep fork signing/notarization and composite Sparkle version behavior,
     while incorporating compatible upstream security/reliability changes;
   - regenerate parser hash instead of choosing either generated side;
   - preserve fork no-Keychain-prompt process/cookie behavior and merge the
     new upstream timeout/prompt-suppression semantics;
   - preserve fork widget bundle IDs, signing, CloudKit Production, and
     composite versioning;
   - keep the current published fork appcast until a new draft artifact is
     locally verified; never replace it with upstream's appcast;
   - set `version.env` to the target values in `00-overview.md`.
3. Re-run formatter/lint/build/tests and fix every non-exhaustive switch,
   parser-hash, release-script, and generated-project failure.

## Shared / Sync Contract

Prefer existing additive structures:

1. `primary`, `secondary`, and `rateWindows` for quota lanes;
2. `loginMethod` for plan/source labels;
3. `budget`, `costSummary`, and existing optional typed snapshots for money;
4. a new optional `decodeIfPresent` field only if a user-visible upstream value
   cannot be represented without loss.

Do not bump `providerPayloadVersion` or `encodingVersion` unless implementation
proves it is necessary. Do not add required fields.

### Kimi

Upstream `KimiUsageSnapshot.toUsageSnapshot()` produces:

- primary Weekly window;
- secondary 5-hour Rate Limit window;
- named `kimi-monthly` / `Monthly` window;
- named `kimi-code-7d` / `Code 7-day` window.

The current mapper serializes primary, secondary, then all
`extraRateWindows`. The implementation task is therefore tests and UI ordering,
not a new Kimi-specific payload.

### Claude plan multiplier

Upstream `ClaudePlan.brandedLoginMethod(rateLimitTier:)` produces
`Claude Max 5x` or `Claude Max 20x`. The current mapper serializes
`snapshot.identity.loginMethod`. Tests must prove this survives encode/decode
and is visible on the iOS detail surface. No schema change is planned.

### Percent formatting

`UsagePercentDisplayMode.percentageValueText(for:)` becomes the iOS source of
truth:

- exactly zero stays `0%`;
- every finite positive value below one becomes `<1%`;
- values at or above one retain current rounded whole-percent display;
- the rule applies to both used and remaining modes after mode selection.

Update focused unit tests and any hard-coded legacy UI paths in scope. Avoid
introducing a new localized string because `<1%` is a numeric symbol.

## CloudKit Design

Expected verdict: no Production deploy.

- no new record type, zone, subscription, predicate, or index;
- no new CloudKit record field;
- no planned Shared payload key;
- no provider/encoding version bump;
- Kimi and Claude reuse opaque compressed JSON fields already stored by the
  existing record type.

The final audit runs the commands from `docs/cloudkit-deploy-audit.md` against
`v0.39.0.1-mobile.1.17.0..HEAD` and records exact output in `03-testing.md`.
If implementation unexpectedly adds a CK schema field, the Goal pauses before
Dashboard deploy.

## Versioning

| Field | Target |
|---|---|
| Mac marketing | `0.41.0.1` |
| Mac build | `100.1` |
| Mobile | `1.18.0` |
| Upstream bookmark | `v0.41.0` / `2026-07-06` |
| iOS build | `186` |
| Sparkle/app CFBundleVersion | `100.1.1.18.0` |
| Tag name | `v0.41.0.1-mobile.1.18.0` |

## Test Plan

- Mac: `swift build`, `bash Scripts/lint.sh lint`, focused provider/parser/
  formatter/security tests, multi-account/multi-device filter, then the full
  suite or the repository sharded equivalent.
- Parser: audit `CostUsageScanner*` / `CostUsageCache` changes, bump
  `parserLogicVersion` if required by the release checklist, regenerate and
  verify `CodexParserHash`.
- Release scripts: `Scripts/test_load_release_secrets.sh`, packaging/signing
  tests, composite version/appcast extraction, codesign, notarization/staple,
  Gatekeeper, bundle IDs, widget signing, and Production CloudKit entitlement.
- iOS: xcodegen, relevant Swift tests, simulator build/test, Kimi order,
  Claude multiplier, sub-1%, payload old/new decode, provider/widget snapshot,
  and localization audit.
- Compatibility: all 16 2 Mac x 2 iPhone old/new combinations, using real
  hardware where available and explicit substituted evidence otherwise.
- Review: self-review after merge, bridge/iOS, and release rounds; then
  independent agents review diff, sync/versioning, and release/test evidence.

## Release Plan

1. Produce clean versioned local commits.
2. Run `Scripts/sign-and-notarize.sh` to create signed, notarized, stapled zip
   and dSYM artifacts.
3. Generate/validate a candidate appcast using the full future tag download
   prefix without pushing it to `mobile-dev`.
4. Under the original Goal boundary, create a GitHub draft release only if
   GitHub accepts a draft targeting an existing remote commit without pushing
   the branch or publishing the tag. Otherwise record the blocker and stop for
   authorization.
5. The user supplied that follow-up authorization on 2026-07-10. The branch,
   annotated tag, GitHub draft assets, and TestFlight upload were then
   completed. Release finalize/live appcast publication, merge, App Store
   submission, and CloudKit deploy remain prohibited without another explicit
   instruction.
