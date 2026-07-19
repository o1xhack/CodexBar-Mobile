# v0.45.2 Upstream Sync Development Log

Status: `in-progress`
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

### Planned Round 1 — Upstream merge

- Merge `refs/upstream-tags/v0.45.2` with provenance.
- Resolve fork CI, Mobile Settings, locale, parser, changelog, appcast and
  version conflicts under `01-design.md`.
- Record the merge commit and conflict decisions here.

### Planned Round 2 — Shared/iOS bridge

- Prove or amend lossless mapping for eight new providers.
- Preserve old-provider decode/subscription compatibility.
- Add iOS provider metadata, colors, mocks, localized release notes and tests.

### Planned Round 3 — Version/release preparation

- Apply the one-version plan, build/test both platforms, audit CloudKit,
  complete the 16-case matrix, sign/notarize local artifacts, validate the
  candidate appcast and record the draft boundary.

### Planned Round 4 — Review and closeout

- Review final diff and evidence, fix/retest all blocking findings, set all
  Research files to `done`, and leave the branch local and unpushed.
