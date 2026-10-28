# Development Quality and Handoff

This is the shared quality contract for features, fixes, refactoring, upstream
sync, and workflow/documentation changes. `AGENTS.md` routes here;
`.agents/skills/codexbar-git-workflow/SKILL.md` owns Git commands, review loops,
stalled-review recovery, and Todoist handoff. A Goal supplies the intended
outcome, task-specific scope, and any narrower authorization.

## Default endpoint: reviewed PR, awaiting the user's decision

1. Work on a task branch; understand and document the approach before coding.
   An already-confirmed request/Goal does not require another design approval.
2. Complete implementation, applicable documentation/versioning and local
   validation. Self-review the complete diff against the task's base branch.
3. Have an independent local Codex review agent inspect the full candidate diff
   and relevant callers, tests, configuration, and release inputs. Fix findings,
   rerun affected checks, and repeat review until no findings remain.
4. Only after that local gate, push the task branch to `origin`, create/update
   a PR, and request GitHub Codex Code Review. Fix and retest every finding,
   reply with evidence, explicitly resolve threads, recheck locally before each
   push, then request review of the new head. Keep iterating until clean.
5. Verify the exact current PR head has a clean completed review, no pending
   review request, no unresolved threads (including outdated ones), and passing
   required PR checks. Mark a draft PR ready when appropriate, run
   `Scripts/check_pr_review_gate.sh <pr>`, and present the decision-ready result.
6. Stop and ask the user whether to merge, and whether to perform the applicable
   Mac and iOS delivery actions. Ask only for actions not already authorized.
   Do not enable auto-merge or treat a clean review as release permission.

These defaults are the user's standing authorization for local review agents,
task-branch pushes, PR creation and the PR review conversation. Read-only,
research-only, local-only, or other explicit limits override them. If local
review tooling or a required external gate is unavailable, report the blocker
and continue independent work; do not label that stage clean or silently skip
it. Follow the Git skill's bounded recovery instead of polling forever.

Local review is a separate stage from remote PR review. It does not authorize
posting an owner-authored substitute review. Any remote substitute still needs
the explicit authorization and evidence in
[Independent Subthread Review](independent-subthread-review.md).

At handoff, give the PR URL and head, local test/review evidence, remote
review/thread/check state, material limitations, and requested next actions.
Distinguish PR checks from post-merge Final CI: under [CI Policy](ci-policy.md),
heavy Final CI normally runs after an authorized merge, and must be checked
before public release. Never describe it as passed in advance.

Mac draft creation, live release/appcast, tags, iOS upload/TestFlight/App Review,
and CloudKit schema deployment require their own scope authorization. When
asking about "iOS release", distinguish TestFlight upload, App Review submission,
and public release. An iOS-only change does not require a Mac release; a docs-only
change normally needs only the merge decision. Explicitly authorized standalone
TestFlight uploads retain the independent workflow in `AGENTS.md`.

## Protect existing product behavior

Choose regression coverage from the final diff and shared consumers, not just
the new feature. Preserve Summary, Usage, Cost, settings, sharing, and widgets
where affected; an upstream merge is not permission to replace fork behavior.

- Keep stable provider/account/device identity, multi-Mac deduplication and cost
  ownership, cache/fallback behavior, and existing user settings.
- Keep unknown, stale, error, and real zero values distinct. Preserve units,
  quota/reset cycles, time zones, currencies, and observed-versus-estimated
  meanings. Do not fabricate history or connect unrelated accounts/reset cycles.
- Trace a data change through producer → serialization/sync → cache/merge → UI
  and shared consumers such as widgets. Reusing a payload does not prove its
  meaning or presentation remains compatible.
- Preserve deployment targets and older-system fallbacks. Confirm the effective
  Xcode/SDK/runtime before SDK-dependent work; historical toolchain notes are
  evidence, not the current toolchain requirement.

## Duo and adaptive UI regression

For changes to iOS UI, navigation, rendering data, or their shared dependencies,
identify the affected ordinary-device and Duo flows before implementation. Use
`$apple-workflow-skills` and the current source; Research 078 and 080's Duo
correction record explain earlier decisions without certifying the current build.

- Summary uses the available width for independent metric cards by default.
  Expansion/rotation must not automatically open account details. Explicit
  selection opens details; returning retains the provider filter.
- Preserve each page's own layout purpose: Usage list/detail and stable account
  selection; Cost overview/trends and report/date context; sharing preview/editor
  and draft/cancel semantics. Do not impose one universal two-column layout.
- During fold/unfold, rotation and resizing, keep valid navigation, selection,
  search/edit state, and operation identity. A transition must not switch targets,
  duplicate a write/export, discard a draft, or make controls unreachable. When a
  target disappears, use the existing explicit invalidation/fallback behavior.
- For affected flows, run actual Duo outer/inner portrait and landscape scenarios
  and relevant transitions, then perform an action after the transition. Include
  partial folds, intermediate sizes, keyboard/presentations, text size, themes,
  and localization when the changed behavior makes them relevant; do not impose
  every combination on unrelated work.
- Regress the same affected paths on ordinary iPhone/iPad and relevant older-OS
  fallbacks. A documentation-only change needs no device matrix.

Verify the active display and actual viewport/orientation. A rotate-command
receipt, generic wide hosting render, or old screenshot does not prove the native
Duo behavior. Capture the actual app with system bars and its subsequent action.
Separate source audit, rendering, simulator interaction, and physical-device
evidence. Retain failed/cancelled attempts; unavailable required coverage remains
an explicit limitation/blocker, not an invented pass.

## Validation and evidence

Use the existing authoritative gates instead of copying them into Goals:

| Trigger | Canonical requirements |
| --- | --- |
| User-facing iOS change | `AGENTS.md`: versions, four-language localization, CHANGELOG and in-app notes |
| Mac/iOS sync, payload, display data, cache or cross-version change | [16-case compatibility gate](ios-sync-compatibility-testing.md) |
| Mac release preparation / CloudKit impact | [Production schema audit](cloudkit-deploy-audit.md); audit does not authorize deploy |
| Release scope, provider/parser/widget regression | Applicable sections of [Release Checklist](RELEASE-CHECKLIST.md) |
| Workflow/documentation-only change | Diff, links, consistency, relevant policy/skill checks, both review stages |

Run focused checks during implementation and required full gates at the delivery
milestone. After review fixes, rerun affected checks and review the resulting
complete candidate; retain still-valid evidence with its original provenance.
Never use a known-flake label to dismiss a new failure without diagnosis.

Record source commit and any relevant dirty diff, commands/results, build SDK,
runtime/device/posture, and evidence paths in the task's existing Research record
or PR. Use `03-testing.md` for release compatibility evidence; do not create a
product-research directory or bump versions just to edit workflow docs.
Report pass, fail, substituted, blocked, and untested accurately. The sync
document's allowed substitutions require reasons, validation and residual risk;
they are not real-device passes. Do not defer in-scope correctness defects as
"later" to obtain a clean result.

## Candidate and release provenance

When packaging is in scope, bind candidate artifacts to the reviewed source,
resources, build configuration and version. Record source SHA, artifact hashes,
signing/Production entitlement results and ZIP/dSYM identity where applicable.
If review fixes change shipped inputs, rebuild affected artifacts and replace
stale draft assets; a clean newer PR does not validate an older binary.

For explicitly authorized Mac draft preparation without tag push, use
`Scripts/release.sh --draft-no-tag-push` with the required local gates and SSD
staging paths. Record the actual artifact source and any placeholder draft target;
retarget to the authorized reviewed release commit before publication. Default
`release.sh` can push a tag and is not a substitute for this bounded mode.

A clean PR, signed archive, uploaded build, draft release, App Review submission,
and public release are separate states. Do not close upstream-sync issues at PR
merge or draft creation; follow the checklist after the Mac public release.
