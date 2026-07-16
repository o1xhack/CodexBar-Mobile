# Release CLI Fork Homebrew Gate

Status: `done`
Date: 2026-07-16
Issue: [#50](https://github.com/o1xhack/CodexBar-Mobile/issues/50)
Branch: `fix/release-cli-fork-homebrew-gate`

## Incident

Publishing `v0.41.0.1-mobile.1.18.0` triggered the inherited
`.github/workflows/release-cli.yml`. All six CLI matrix jobs built, smoke-tested,
packaged, and uploaded their archives and checksums successfully. The workflow
then failed only in `update-homebrew-tap` because that job unconditionally
requires the upstream-owned `HOMEBREW_TAP_TOKEN` and dispatches
`steipete/homebrew-tap` using `steipete/CodexBar` as its release source.

The live Mac/iOS release and CLI assets are valid. The failure is a fork
orchestration error after publication, not an artifact failure, and does not
require withdrawing or rebuilding `0.41.0.1 / 1.18.0`.

## Design

- Keep `build-cli` unchanged for both upstream and fork releases.
- Keep manual `workflow_dispatch` artifact builds unchanged.
- Gate the complete `update-homebrew-tap` job to release events in the exact
  `steipete/CodexBar` repository.
- Preserve the upstream tap repository, release source, token, and dispatch
  behavior when the workflow runs upstream.
- Add a portable regression test to the existing lint gate so future upstream
  merges cannot silently restore the fork failure.

## Risk and Test Plan

- Job-level repository gating avoids exposing or probing an unavailable secret
  in the fork and makes the job visibly skipped rather than falsely successful.
- The fork's CLI archives remain required because their build/upload steps are
  in the separate, ungated `build-cli` job.
- Validate the workflow's release, manual-artifact, repository, tap target,
  release source, and token invariants with `Scripts/test_release_cli_workflow.sh`.
- Run shell syntax checks, the portable lint suite, workflow YAML parsing, and
  `git diff --check` before handoff.

## Evidence

- GitHub Actions run
  [`29459511840`](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/29459511840):
  all six `build-cli` matrix jobs succeeded; only `update-homebrew-tap` failed
  at `Dispatch tap update` because the fork has no upstream tap token.
- Added the exact job condition
  `github.event_name == 'release' && github.repository == 'steipete/CodexBar'`.
  Fork release events therefore keep the `build-cli` matrix and asset uploads
  but skip the upstream-only job; upstream release events retain the prior tap
  dispatch and wait behavior.
- `./Scripts/test_release_cli_workflow.sh` — passed. The assertions are scoped
  to the concrete release and manual artifact upload steps, plus the Homebrew
  job, tap target, release source, and token wiring.
- `bash -n Scripts/test_release_cli_workflow.sh` — passed.
- Ruby `YAML.parse_file` for `.github/workflows/release-cli.yml` — passed.
- `./Scripts/lint.sh lint-linux` — passed: portable release/package checks,
  repository and documentation audits, SwiftLint over 1,350 files with zero
  violations, and parser-version audit all passed.
- `git diff --check` — passed.

No runtime Swift, Mac app, Shared sync, iOS, CloudKit, version, appcast, or
release artifact source changed. A remote Actions evaluation remains for the
PR handoff because this task did not authorize pushing the branch.

## Post-merge review follow-up

PR #52 was merged before its asynchronous Codex review finished. The completed
review identified two valid CI-policy defects, handled on
`review/pr52-review-fixes`:

- Upstream check reuse previously rejected only selected blocking conclusions,
  so a `cancelled` check could be accepted alongside any successful check. The
  gate now requires every reported check run to be completed successfully and
  otherwise falls back to fork Final CI.
- The workflow guard previously missed scalar and block-list PR trigger syntax.
  It now rejects mapping, scalar, inline-list, and block-list forms for both
  `pull_request` and `pull_request_target`, including quoted `on` keys.

Regression coverage is part of portable lint in
`Scripts/test_ci_upstream_check_gate.sh` and `Scripts/test_ci_policy.sh`.
Portable lint first runs `Scripts/check_ci_policy.sh` against the real repository
workflows, then runs the isolated trigger-form fixtures; this preserves both the
production guard and its syntax regression coverage.
