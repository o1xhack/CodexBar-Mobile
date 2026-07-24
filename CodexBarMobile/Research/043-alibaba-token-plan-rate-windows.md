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

1. Apply the contributor's provider-only commit without rewriting its logic.
2. Review the endpoint, authentication-header, parser, fallback, and snapshot
   mapping changes for credential leakage and cross-region regressions.
3. Preserve `GetSubscriptionSummary` as the fallback and optional monthly
   credits window.
4. Keep the existing Mac-to-iOS generic `primary` / `secondary` rate-window
   sync path; do not change CloudKit schema, entitlements, or app groups.
5. Treat this as a fork hotfix ahead of upstream, not as an upstream sync.

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

## Authorization Boundary

This task authorizes branch work, testing, PR handoff, and merge after the
gates pass. It does not authorize live Alibaba account probes, Keychain reads,
tagging, notarization, TestFlight upload, App Store actions, appcast
publication, or a live GitHub release. User-installable publication remains a
separate release decision after the merged hotfix is green.
