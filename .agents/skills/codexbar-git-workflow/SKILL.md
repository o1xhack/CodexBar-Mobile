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

Follow `AGENTS.md` and `docs/development-quality.md`: ordinary development has
standing authorization for a task-branch push and PR **after** local validation
and independent local review are clean. Read-only/research-only, local-only and
explicit user limits override that default. This authorization does not include
merge, auto-merge, tags or release/upload actions.

### Local review before every push

Self-review the complete base-to-candidate diff, then use an independent local
Codex review agent to inspect it with the relevant callers, tests, configuration
and release inputs. Save the actual report and reviewed commit (plus dirty-diff
fingerprint if needed). Fix all findings, rerun affected checks and repeat the
independent review until clean. Review commits after the last clean local result
before pushing again, including fixes prompted by the remote review. A local
clean result must cover the complete current candidate, not only one fix hunk.

The user's standing local-review authorization is not authorization to replace
GitHub Codex review with an owner-authored substitute; that remains governed by
`docs/independent-subthread-review.md`. If a required review capability is
unavailable, preserve evidence and report the blocker rather than skip it.

### Publish the reviewed branch

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

Use draft PRs while the review loop is incomplete. Always attach a created PR to
the current chat with the app's attach-artifact tool. After clean local and remote
review and required PR checks, mark the PR ready, verify the gate below, then stop
for the user's merge/release decision unless those actions are already authorized.

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
means review is complete. After merge, check Final CI before public release; a failure
is fixed forward and public release remains blocked until the relevant final gate
passes. TestFlight beta uploads are independent of this remote CI gate.

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

1. Record the current `headRefOid`, review request URL/start time, last meaningful
   progress time, and recovery-attempt count. Trigger `@codex review` and monitor
   with the stalled-review procedure below. Do not merge while the requested
   review is still in flight.
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

Use these exact non-empty fields so the merge gate can validate the audit:

```text
Codex review architecture audit
Head: <current head SHA>
Repeated finding pattern: <what keeps recurring>
Root design/requirements problem: <shared underlying cause>
Revised approach: <what will be redesigned or rewritten>
```

For release/upstream-sync work, **merge, tag creation, Mac live release,
and appcast publication are blocked until this PR review gate passes**.
Review-fix and closeout PR merges are not exceptions.

### Decision handoff after a clean PR

Run `Scripts/check_pr_review_gate.sh <pr>` on the current open, non-draft PR and
confirm required PR checks pass before asking the user to decide. Include the PR
URL/head, local validation/review evidence, unresolved-thread count, material
risks, and applicable delivery choices. Do not claim post-merge Final CI ran.

Ask separately about merge, Mac live release, and the intended iOS stage
(TestFlight, App Review, or public release); omit inapplicable actions. Do not
enable auto-merge or publish merely because the gate passed. Reuse existing
explicit action authorization without asking again; otherwise wait for it.
Immediately before an authorized merge, reconfirm the head, checks and gate.

### Stalled Review Diagnosis And Recovery

Own review progress without waiting for the user to notice or chase it.
**By default, 15 minutes without meaningful review progress triggers diagnosis.**
This is an operational threshold, not an OpenAI service guarantee; investigate
earlier on an explicit error or a clear anomaly relative to comparable reviews.
A repeated `Running` label, a new polling timestamp, or CI progress does not reset
the review timer. Actual review-stage/log progress or a review result does.

1. **Diagnose instead of repeating the same poll.** Re-read the live head,
   review summary and its timestamps, request reactions, review threads, and CI.
   Separate a CI failure from a stalled Codex review. Check available task/log
   views, repository connection and account/workspace alignment, usage limits,
   and official service status. Use supported tools and the user's configured
   browser. An empty ordinary task list does not prove a review task is absent;
   a null review-limit field does not prove quota is available; an operational
   public status page does not rule out an individual failure. If internal logs
   are unavailable, state that the exact cause is unknown rather than inventing
   a queue, outage, or successful run.
2. **Preserve evidence before recovery.** Save the PR URL, exact head, original
   request/start and last-update times, observed responses/errors, and a concise
   diagnosis. Keep observations separate from suspected causes and omit secrets.
   Resolve an explicit authorization, quota, or configuration blocker within the
   existing task scope before considering a retry.
3. **Use at most one controlled retry per unchanged head.** When diagnosis
   supports a stalled request or stale status, no actual ongoing review progress
   is visible, and no explicit blocker explains it, existing authorization to
   run the review covers one recovery request. Reconfirm the head is unchanged,
   then post `@codex review` with the head, prior request time, and retry reason.
   Preserve the original request. Do not push an empty commit, change code or
   settings merely to force a trigger, enable paid overages, or repeatedly
   retrigger. This recovery does not reset the code-fix review-round audit.
4. **Verify acceptance and completion separately.** Record whether the bot
   responds or the review start time advances; neither is a clean review. Track
   the recovery attempt and apply the same progress deadline. Merge only after
   the latest requested review finishes clean on the current head, all threads
   are resolved, CI passes, and the existing review gate passes immediately
   before merge. Keep recovery evidence separate from release provenance.
5. **Escalate a failed recovery; do not poll indefinitely.** If the retry is
   rejected, fails, or again exceeds the progress deadline without a further
   authorized remedy, record the external blocker, prepare support-ready
   evidence, and give the user one concise update with the next available step.
   Contacting support still requires authorization. Continue independent work;
   stop a polling-only follow-up once its recovery budget is exhausted. Do not
   create another retry loop or label the review passed.

Automated follow-ups must carry the exact head, last meaningful progress time,
deadline, and retry count forward. They must perform diagnosis when overdue,
not merely return the same `Running` status on every run. Keep ordinary unchanged
pending checks quiet, report material recovery/results/blockers, and remove the
follow-up when its work is complete or its bounded recovery plan is exhausted.

## Independent TestFlight Beta Uploads

When the user authorizes TestFlight, upload directly from the task branch if needed.
A PR, completed Codex review, merge to mobile-dev, and remote CI completion are
not prerequisites. Do not create a PR solely to unlock TestFlight.

Retain relevant local builds/tests, version and build-number checks, four-language
release notes, signing, and CloudKit Production checks. Record the source commit,
uploaded version/build, Apple processing/beta-access results, and known validation
gaps. An upload does not authorize merging, tagging, or a public App Store release.
If a PR exists, its review/CI workflow continues independently; beta upload does
not mark those gates passed or waive them for a later merge.

Before promoting a beta build to App Review/public release, verify its recorded
archive source commit and tree against the clean reviewed release source. The
selected ASC build must contain the exact reviewed code, resources, build settings
and version; an unrelated clean review on a newer head is not evidence for an
older binary. Record the archive/IPA hash and ASC build ID with that provenance.
If review fixes change any shipped inputs, or provenance cannot be established,
archive and upload a new build and select that build for submission. Docs-only
follow-ups do not require a new binary when the shipped inputs are identical.

## Todoist Handoff

After pushed commits for CodexBar Mobile, update Todoist if the tools are available.

- Project: `Dev`
- Required label: `CodexBar-Mobile`
- Add `Bug` for bug/crash/fix work.
- Add `商业化` for paid/member-facing work.
- Board columns: `Backlog` → `Next` → `In Progress` → `Code Complete` → `QA` → `Release`.
- Keep `Next` short: only the picks queued to start soon; other candidates stay in `Backlog`.
- Move active work to `In Progress`.
- After pushed code is complete, move it to `Code Complete`; do not mark complete.
- Move it to `QA` for human QA/TestFlight/user validation.
- After QA passes, move it to `Release` when it is submitted to App Review or a release is published.
- Only mark done (in `Release`) after user confirmation or verified release truth (for example App Store `READY_FOR_SALE` or a live GitHub release).

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
