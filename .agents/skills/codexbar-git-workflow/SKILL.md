---
name: codexbar-git-workflow
description: "CodexBar Git/GitHub workflow for creating feature, fix, upstream-sync, release, review, and cleanup branches; making staged commits; pushing branches; opening PRs; checking CI/review state; and replacing the old jj commit/branch steps with git and gh. Use whenever CodexBar work needs branch planning, commits, push, PR handoff, branch cleanup, or Todoist sync after pushed code."
---

# CodexBar Git Workflow

Use Git and GitHub for CodexBar branch, commit, push, PR, and branch cleanup work. Do not use `jj` unless the user explicitly re-enables it.

## Preflight

Start every branch/commit operation from the repo root.

```bash
git status --short --branch
git remote -v
git fetch origin --prune
```

If the work must start from the latest mainline:

```bash
git switch mobile-dev
git pull --ff-only origin mobile-dev
```

Do not discard, stash, reset, or overwrite unrelated user changes. If the worktree is dirty, inspect it first and either work with it or ask before moving it.

## Branches

Create a task branch before implementation unless the user only asked for read-only analysis.

Pick the branch name yourself from the task; the user should not need to put branch names in Goal prompts.

| Work type | Branch shape |
|-----------|--------------|
| New user-facing feature | `feature/<short-slug>` |
| Smaller function/tooling addition | `function/<short-slug>` |
| Bug fix | `fix/<short-slug>` |
| Research/docs-only investigation | `research/<short-slug>` |
| Upstream sync | `upstream-sync/<target-upstream>-mobile.<target-mobile>` |
| Release preparation | `release/<version-or-slug>` |
| Post-merge/review cleanup | `review/<short-slug>` |

Create the branch:

```bash
git switch -c <branch-name>
git status --short --branch
```

Never push to `upstream`. Only push branches to `origin`.

## Commit Cadence

For large Goals, make coherent staged commits instead of one giant final commit. Good checkpoints are:

- research/design docs and product matrix
- project/target scaffolding
- shared data/cache/model layer
- UI or feature slices
- localization and release notes
- tests and review fixes

Each commit should be reviewable and preferably buildable. If a checkpoint cannot fully build yet, document why in the research/testing notes before committing it.

Use focused staging:

```bash
git status --short
git diff --stat
git diff
git add <paths>
git diff --cached --stat
git diff --cached
```

Run the relevant checks before committing. At minimum, run the narrow build/test/lint that matches the files changed; for release-facing or sync-facing work, run the stronger gates required by `AGENTS.md` and docs.

Commit with Git:

```bash
git commit -m "<type>(<scope>): <summary>"
```

Message examples:

- `docs(research): plan iOS widget suite`
- `feat(ios): add widget shared snapshot cache`
- `feat(widgets): add provider usage widgets`
- `fix(sync): preserve stale provider timestamps`
- `test(widgets): cover widget entry formatting`

## Version And Release Notes

Do not bump build numbers for every internal checkpoint commit on a long-lived branch.

Bump `CodexBarMobile/project.yml` and update `CodexBarMobile/CHANGELOG.md` plus `MobileReleaseNotesCatalog` when a user-facing iOS change is ready for handoff, release prep, TestFlight upload, or merge to `mobile-dev`.

Rules:

- Increment all `CURRENT_PROJECT_VERSION` values together.
- Do not change `MARKETING_VERSION` unless explicitly requested or required by the release plan.
- Keep same-`MARKETING_VERSION` in-app release notes in one block; merge related bullets instead of creating duplicate lines.
- Follow the 4-language localization rule for release notes and all user-facing text.

For Mac/versioning decisions, read `docs/versioning.md` before editing `version.env`.

## Push And PR

Push only when the user asked to push, open a PR, run remote CI, or the active Goal explicitly authorizes pushed branch handoff.

```bash
git push -u origin <branch-name>
```

Open PRs against `mobile-dev` unless release docs or the user say otherwise:

```bash
gh pr create \
  --repo o1xhack/CodexBar-Mobile \
  --base mobile-dev \
  --head <branch-name> \
  --draft \
  --title "<title>" \
  --body "<body>"
```

Use draft PRs for long-running feature branches until local verification and the review loop are complete.

## Review And CI Loop

This repository deliberately separates review feedback from expensive CI. The
fork-owned invariant is documented in `docs/ci-policy.md`:

- Every PR push runs only `PR Fast Checks`; do not add macOS/Linux matrices to
  `pull_request` synchronize events while addressing review feedback.
- Merge to `mobile-dev` triggers one diff-selected Final CI run.
- Verified `upstream-sync/*` merges reuse upstream release checks instead of
  repeating the complete upstream matrix.
- Use manual Final CI with `full=true` only for unresolved provenance, risky
  conflict resolution, or an explicitly requested complete rerun.

Code review may therefore finish before heavy CI exists on the PR. PR Fast
Checks and Codex Code Review are independent gates: a green check run never
means review is complete. After merge, check Final CI before release; a failure
is fixed forward and release remains blocked until the relevant final gate
passes.

After pushing or opening a PR, check status from GitHub, not memory:

```bash
gh pr view --repo o1xhack/CodexBar-Mobile <number-or-url> --json state,isDraft,headRefName,baseRefName,mergeStateStatus,reviewDecision,statusCheckRollup,url
gh run list --repo o1xhack/CodexBar-Mobile --branch <branch-name> --limit 10
```

If checks fail, inspect the failed run and logs, fix, retest locally, commit, and push again:

```bash
gh run view --repo o1xhack/CodexBar-Mobile <run-id> --log-failed
git push
```

For every PR, including docs-only, review-fix, and release-closeout PRs:

1. Record the current `headRefOid`, trigger `@codex review`, and keep polling.
   Do not merge while the requested review is still in flight.
2. Inspect thread-aware review state, not only checks or flat comments. Every
   finding must be fixed and retested.
3. Reply to the finding with the fix commit/evidence, explicitly resolve the
   GitHub review thread, then push and request another Codex review.
4. Any new push invalidates the previous clean result. The final clean review
   must name the exact current head, and every thread—including outdated
   threads—must show `isResolved=true`.
5. Run `Scripts/check_pr_review_gate.sh <pr>` immediately before merge. A pass
   requires the current-head `Didn't find any major issues` result and zero
   unresolved threads. CI must also be green.

The loop is `review -> fix -> test -> reply -> resolve -> push -> review` until
clean. After five review rounds, do not continue making narrow patches by
reflex. Before a sixth review, stop and write a `Codex review architecture
audit` PR comment that includes the current head, repeated finding pattern,
root design/requirements problem, and revised approach. Re-plan or rewrite the
affected slice, then resume the loop. The audit is not a merge override: the
final current-head clean review and zero-thread gate still apply.

For release/upstream-sync work, **merge, tag creation, Mac live release,
appcast publication, and TestFlight upload are blocked until this PR review
gate passes**. Review-fix and closeout PRs are not exceptions.

## Todoist Handoff

After pushed commits for CodexBar Mobile, update Todoist if the tools are available.

- Project: `Dev`
- Required label: `CodexBar-Mobile`
- Add `Bug` for bug/crash/fix work.
- Add `商业化` for paid/member-facing work.
- Move active work to `In Progress`.
- After pushed code is complete, move it to `Code Complete`; do not mark complete.
- After human QA/TestFlight/user validation, move it to `Release`.
- Only mark done after user confirmation.

Comment format:

```text
[YYYY-MM-DD] <concise progress summary>
https://github.com/o1xhack/CodexBar-Mobile/commit/<sha>
```

Point Todoist comments to the commit or `CHANGELOG.md`; do not duplicate full release notes there.

## Branch Cleanup

Only clean up branches after the user confirms merge/release closure or the PR merge operation itself includes cleanup.

Before deleting:

```bash
git fetch origin --prune
git branch --merged mobile-dev
gh pr view --repo o1xhack/CodexBar-Mobile <number-or-url> --json state,mergedAt,headRefName,url
```

Delete only merged branches:

```bash
git branch -d <branch-name>
git push origin --delete <branch-name>
```

Use `-D` or force-push only with explicit user authorization.
