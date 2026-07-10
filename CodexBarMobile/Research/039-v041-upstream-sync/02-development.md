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

- Merge `refs/upstream-tags/v0.41.0`.
- Resolve conflicts with fork constraints.
- Regenerate parser hash/project files as appropriate.
- Run Mac build and focused tests.

### Round 2 — Shared/iOS bridge and UX

- Prove Kimi and Claude reuse existing wire fields.
- Add/fix `<1%` mobile formatting.
- Add mixed-version encode/decode, mapping, display, and widget snapshot tests.

### Round 3 — Version and release documentation

- Update Mac/iOS version fields, root/iOS changelogs, in-app release notes,
  four-language catalog, Research status, and CloudKit audit history.

### Round 4 — Release artifacts and full gates

- Run Mac/iOS full gates and 16-row compatibility evidence.
- Sign, notarize, staple, package, and appcast-validate.
- Create a remote draft only within the no-push/no-published-tag boundary.

### Round 5 — Review loop

- Self-review complete diff.
- Independent agent reviews.
- Fix blocking findings and rerun affected gates until blocker count is zero.
