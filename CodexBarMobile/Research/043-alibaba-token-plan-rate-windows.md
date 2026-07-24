# Alibaba Token Plan Rate Windows Hotfix

Status: `in-progress`
Date: 2026-07-24
Issue: [#59](https://github.com/o1xhack/CodexBar-Mobile/issues/59)
Upstream PR: [steipete/CodexBar#2437](https://github.com/steipete/CodexBar/pull/2437)
Branch: `fix/alibaba-token-plan-rate-windows`

## Problem

Released builds can authenticate Alibaba Token Plan accounts but may show no
usage windows because the legacy `GetSubscriptionSummary` response no longer
supplies the rolling 5-hour and weekly limits. A user submitted a provider-only
fix directly against the current `mobile-dev` commit and requested an ordinary
signed fork release.

The contribution is evidence that the fork has external users who benefit from
timely provider fixes. Waiting for an upstream release is therefore not the
default decision when a small, reviewable patch can be validated independently.

## Upstream and Fork State

- The latest published upstream release is `v0.45.2`, which is already the
  fork's authoritative baseline in `version.env`.
- Upstream PR #2437 remains open. Its fix commit is one commit ahead of current
  upstream `main`, so no upstream release contains the change.
- Contributor commit
  [`7604d2d`](https://github.com/rohitsabu/CodexBar/commit/7604d2d15cc009f340f80489f9b9aaa2c7d3ef0b)
  is based directly on current fork commit `e2817d62`, making it the correct
  provenance for a fork hotfix review.

## Chosen Approach

1. Fetch upstream PR #2437 into the read-only local ref
   `upstream/pr/2437`, inspect its exact head, and compare it with the
   contributor's fork commit.
2. Apply the contributor's provider-only commit without rewriting its logic.
3. Review the endpoint, authentication-header, parser, fallback, and snapshot
   mapping changes for credential leakage and cross-region regressions.
4. Preserve `GetSubscriptionSummary` as the fallback and optional monthly
   credits window.
5. Keep the existing Mac-to-iOS generic `primary` / `secondary` rate-window
   sync path; do not change CloudKit schema, entitlements, or app groups.
6. Treat this as a fork hotfix ahead of upstream, not as an upstream sync.

The upstream PR head is `94827370`, based on six unreleased upstream commits.
Pulling that branch into the fork would therefore import unrelated work. The
contributor's corresponding fork commit applies the same four-file hotfix to
our exact baseline while preserving the fork-only
`alibabaTokenPlanUsage: self` sync hook.

## Review Findings

- The new request uses the existing authenticated Alibaba endpoint family and
  forwards only the same session cookie and browser-like headers already used
  by the provider. No credential is added to logs, persistence, or sync data.
- Response decoding is tolerant of missing items and keeps
  `GetSubscriptionSummary` as a fallback, so an unavailable rate-limit endpoint
  does not remove the legacy monthly-credit display.
- Upstream review found one unresolved P2: the restored windows were still
  presented with the generic `Credits` and `Usage` labels. This branch fixes
  both menu render paths dynamically: true 300-minute and 10,080-minute windows
  display as `5-hour` and `Weekly`, while the legacy monthly fallback retains
  its existing `Credits` label.
- The patch changes provider fetch and presentation code only. It does not
  change credentials, entitlements, app groups, Shared models, CloudKit record
  types, or CloudKit indexes.

## Acceptance Gates

- Focused `AlibabaTokenPlanProviderTests` pass with test-only URL sessions and
  no macOS Keychain prompts.
- Related sync mapping and menu-card tests pass.
- Portable lint and `git diff --check` pass.
- Mac app/CLI builds compile.
- The generated iOS project builds for an unsigned Simulator destination.
- No credentials, cookies, account identifiers, private configuration,
  signing, entitlement, CloudKit, or app-group changes are present.
- PR Fast Checks and review are clear before merge; post-merge Final CI must
  pass before any release.

## Validation Evidence

- `swift test --filter AlibabaTokenPlan`: 44 tests across 10 suites passed.
- `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 swift test --parallel`: complete
  macOS test graph passed with live-account tests disabled.
- `bash Scripts/lint.sh lint`: passed, including SwiftFormat, SwiftLint,
  localization, parser-version, docs, and fork CI-policy guards.
- `swift build --product CodexBar` and
  `swift build --product CodexBarCLI`: passed.
- Generated the iOS project from `project.yml`; `CodexBarMobile` built for an
  iPhone 17 / iOS 26.4 Simulator with zero warnings and zero errors.
- Four-language release-note catalog passes the source/catalog audit and JSON
  validation.
- CloudKit release audit against
  `v0.45.2.1-mobile.1.19.0`: no schema-related or Shared model diff, so no
  Production schema deploy is required.
- No live Alibaba request, browser-cookie import, Keychain read, signing,
  notarization, archive, upload, or release action was performed.

## Authorization Boundary

This task authorizes branch work, testing, fixes, and PR handoff. The PR must
remain unmerged for user review. It does not authorize live Alibaba account
probes, Keychain reads, merging, tagging, notarization, TestFlight upload,
App Store actions, appcast publication, or a live GitHub release.
User-installable publication remains a separate decision after the reviewed
hotfix is green.
