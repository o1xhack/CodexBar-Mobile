#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${CI_POLICY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
workflow_dir="$ROOT_DIR/.github/workflows"
pr_fast="$workflow_dir/pr-fast.yml"
final_ci="$workflow_dir/ci.yml"
rc=0

fail() {
  printf 'CI policy error: %s\n' "$1" >&2
  rc=1
}

workflow_has_pr_trigger() {
  local workflow="$1"
  grep -Eq \
    '^(on|"on"|'"'"'on'"'"'):[[:space:]]*pull_request(_target)?[[:space:]]*$|^(on|"on"|'"'"'on'"'"'):[[:space:]]*\[[^]]*pull_request(_target)?[^]]*\][[:space:]]*$|^[[:space:]]+-[[:space:]]*pull_request(_target)?([[:space:]]|$)|^[[:space:]]+pull_request(_target)?:([[:space:]]|$)' \
    "$workflow"
}

[[ -f "$pr_fast" ]] || fail ".github/workflows/pr-fast.yml is missing"
[[ -f "$final_ci" ]] || fail ".github/workflows/ci.yml is missing"

if [[ -f "$pr_fast" ]]; then
  grep -Eq '^  pull_request:$' "$pr_fast" \
    || fail "PR Fast Checks must own the synchronize trigger"
  grep -Fq '    types: [opened, synchronize, reopened, ready_for_review]' "$pr_fast" \
    || fail "PR Fast Checks must run for every normal PR update"
  if grep -Eiq 'runs-on:.*macos|swift[[:space:]]+(build|test)|Scripts/test\.sh|build-linux-cli' "$pr_fast"; then
    fail "PR Fast Checks contains an expensive build or test command"
  fi
fi

if [[ -f "$final_ci" ]]; then
  grep -Fq '# FORK CI POLICY: preserve during upstream merges.' "$final_ci" \
    || fail "Final CI fork-policy marker is missing"
  grep -Eq '^    types: \[closed\]$' "$final_ci" \
    || fail "Final CI may only use the pull_request closed event"
  push_block="$(awk '
    /^  push:$/ { in_push=1; next }
    /^  [[:alnum:]_-]+:$/ { in_push=0 }
    in_push { print }
  ' "$final_ci")"
  grep -Fq 'branches: [main]' <<< "$push_block" \
    || fail "Final CI push fallback must be limited to main"
  if grep -Fq 'mobile-dev' <<< "$push_block"; then
    fail "Final CI must use the merged PR event, not duplicate mobile-dev push runs"
  fi
fi

while IFS= read -r workflow; do
  [[ -f "$workflow" ]] || continue
  if workflow_has_pr_trigger "$workflow"; then
    case "$workflow" in
      "$pr_fast"|"$final_ci") ;;
      *) fail "$(basename "$workflow") adds a PR trigger outside the two-layer CI policy" ;;
    esac
  fi
done < <(find "$workflow_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print | sort)

grep -Fq 'CI Policy — Fork Invariant' "$ROOT_DIR/AGENTS.md" \
  || fail "AGENTS.md is missing the fork CI invariant"
grep -Fq 'docs/ci-policy.md' "$ROOT_DIR/AGENTS.md" \
  || fail "AGENTS.md does not route agents to docs/ci-policy.md"
grep -Fq 'This repository deliberately separates review feedback from expensive CI.' \
  "$ROOT_DIR/.agents/skills/codexbar-git-workflow/SKILL.md" \
  || fail "codexbar-git-workflow does not preserve the two-layer CI handoff"

if [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi

printf 'CI policy guard passed: PR updates stay fast; expensive CI runs only after merge or manually.\n'
