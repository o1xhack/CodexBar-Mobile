# v0.35.0 Upstream Sync Development Log

Status: `in-progress`
Date: 2026-06-14
Branch: `upstream-sync/v0.35.0-mobile.1.12.0`

## Round 0 — Research and Branch Setup

Evidence:

```text
git status --short --branch
Result: upstream-sync/v0.32.5-mobile.1.12.0 with two Research docs dirty.

git commit -m "docs: record v0.32.5 release evidence"
Result: f5f710f4, local only, preserves prior release evidence.

git switch -c upstream-sync/v0.35.0-mobile.1.12.0 origin/mobile-dev
Result: branch created from 848c37c8 docs: update appcast for 0.32.5.1.
```

Rules and source material read:

- `AGENTS.md`
- `docs/versioning.md`
- `docs/ios-sync-compatibility-testing.md`
- `docs/cloudkit-deploy-audit.md`
- `docs/RELEASE-CHECKLIST.md`
- open upstream-sync issues #22/#23/#24/#26
- closed upstream-sync issue format (#15-#20)
- upstream GitHub Releases `v0.32.5`, `v0.33.0`, `v0.34.0`, `v0.35.0`
- `git diff --stat v0.32.4..v0.35.0`

Initial decisions:

- Target upstream: `v0.35.0`.
- Target Mac: `0.35.0.1`, build `85.1`.
- Target iOS: `1.12.0 (153)`.
- This release supersedes the old v0.32.5-only branch; all open upstream-sync
  issues are handled as one version.

## Implementation Notes

Not started yet.

