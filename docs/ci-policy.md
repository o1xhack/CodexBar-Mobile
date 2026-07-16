# CI Policy — Fast Review, One Final Gate

This is a fork-owned policy. Preserve it when merging `steipete/CodexBar`.
Upstream workflow changes may be adopted deliberately, but must not replace
this trigger model as an incidental merge-conflict resolution.

## Required trigger model

| Stage | Workflow | What runs |
| --- | --- | --- |
| Every PR update | `PR Fast Checks` (`pr-fast.yml`) | portable lint, repository checks, CI-policy guard |
| PR merged to `mobile-dev` | `Final CI` (`ci.yml`) | lint plus only the macOS/Linux matrices selected by the merged diff |
| Trusted `upstream-sync/*` merge | `Final CI` | verifies the published upstream tag/checks, then reuses upstream heavy CI |
| Exceptional/risky change | `Final CI` manual dispatch | complete macOS and Linux matrices |
| Release | release workflows and `docs/RELEASE-CHECKLIST.md` | local build/test, signing, notarization, Sparkle and release verification |

PR review commits must not launch macOS Swift-test shards or dual-architecture
Linux builds. Review can iterate as many times as needed while `PR Fast Checks`
provides the inexpensive syntax, lint and repository-contract signal.

## Final-CI path selection

- `Sources/`, root `Shared/`, `Tests/` and package manifests select macOS tests.
- `CodexBarCore`, `CodexBarCLI`, `CSQLite3`, package manifests and `TestsLinux`
  select Linux CLI tests.
- iOS-only, docs, appcast, release metadata and workflow-only changes rely on
  the fast portable checks and do not start cold macOS/Linux runners.
- An empty or unclassifiable diff is handled conservatively by running both.
- Manual `full=true` always runs both matrices.

## Upstream-sync reuse

An `upstream-sync/*` merge may skip the duplicate heavy remote matrices only
when automation verifies all of the following:

1. `version.env` contains a valid `UPSTREAM_VERSION`.
2. That tag is a published, non-prerelease `steipete/CodexBar` release.
3. The upstream tag commit is an ancestor of the merged fork commit.
4. The upstream commit has successful checks and no blocking check conclusion.

If any evidence is missing or the GitHub API is unavailable, Final CI falls
back to the normal path-selected matrices. Reusing upstream CI does not waive
fork-specific local testing: conflict resolutions, Shared/Sync/CloudKit/iOS,
versioning and release behavior still follow `AGENTS.md` and the release
checklist before merge/release.

## Protection against regression

`Scripts/check_ci_policy.sh` runs inside portable lint and enforces:

- `pr-fast.yml` is the only workflow that handles PR update events;
- `ci.yml` listens only to PR `closed`, not `synchronize`;
- the PR workflow contains no macOS runner, Swift build/test or Linux matrix;
- this policy remains routed through `AGENTS.md` and the Git workflow skill.

Because the guard runs on every PR update, an upstream workflow that introduces
another PR trigger cannot silently restore the expensive per-commit behavior.
Resolve such conflicts by preserving this fork policy and deliberately porting
only useful upstream job implementation changes.
