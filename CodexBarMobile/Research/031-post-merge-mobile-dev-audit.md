# Post-Merge Mobile Dev Audit

Status: `done`
Date: 2026-06-17
Branch: `review/post-merge-upstream-audit-20260617`

## Scope

This audit intentionally reviews only content already merged into `mobile-dev`.
No `upstream/main` commits were merged or included in this branch.

The release commit for iOS build 155 intentionally contains only the iOS app /
push-extension diagnostics fix. Shared cleanup found during the same audit is
split into a follow-up commit so this App Store upload remains iOS-scoped.

The user-requested review window was the recent `0.2G -> 0.353G` mobile-dev
range. The closest concrete local release-tag range used for code review was:

```text
v0.26.4-mobile.1.7.0..v0.35.0.1-mobile.1.12.0
```

## Reviewed Areas

- Quota transition push subscription registration and diagnostics.
- Notification Service Extension quota-warning body rewrite path.
- iOS localization catalog coverage.
- iOS simulator build and test gates.
- Project lint/test gates, excluding Mac-only source changes.

## Findings and Fixes

### Warning subscriptions were misclassified in Developer Tools diagnostics

iOS 1.13.0 registers quota push subscriptions for each provider and state:
depleted, restored, and warning. The diagnostic formatter grouped depleted and
restored subscription IDs, but did not group `quota-*-warning-sub`, so warning
subscriptions appeared under `other`.

This made the Developer Tools subscription summary look drifted even when the
warning subscriptions were expected. The fix adds a dedicated
`quota-*-warning-sub` group, updates the stale subscription-count comment, and
adds a pure unit test for the warning grouping.

### Reviewed iOS code emitted avoidable compiler diagnostics

The review also cleaned up warnings in the audited iOS paths:

- `NotificationService` destructures the named associated values in
  `QuotaWarningEvaluation.success` directly, avoiding deprecated tuple-style
  pattern matching.
- `QuotaTransitionSubscriptions` no longer awaits synchronous MainActor
  diagnostic calls.

## Verification

- `cd CodexBarMobile && xcodegen generate` succeeded.
- `git diff --check` passed.
- `./Scripts/lint.sh audit-i18n` passed.
- Focused iOS simulator test:
  `CodexBarMobileTests/QuotaTransitionSubscriptionsTests` passed
  (`5 passed / 0 failed`).
- Full iOS simulator test suite passed (`488 passed / 0 failed / 0 warnings`).
- `./Scripts/lint.sh lint` passed.
