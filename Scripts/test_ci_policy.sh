#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p \
  "$fixture/.github/workflows" \
  "$fixture/.agents/skills/codexbar-git-workflow"
cp "$ROOT_DIR/AGENTS.md" "$fixture/AGENTS.md"
cp "$ROOT_DIR/.agents/skills/codexbar-git-workflow/SKILL.md" \
  "$fixture/.agents/skills/codexbar-git-workflow/SKILL.md"
cp "$ROOT_DIR/.github/workflows/pr-fast.yml" "$fixture/.github/workflows/pr-fast.yml"
cp "$ROOT_DIR/.github/workflows/ci.yml" "$fixture/.github/workflows/ci.yml"

CI_POLICY_ROOT="$fixture" "$ROOT_DIR/Scripts/check_ci_policy.sh" >/dev/null

expect_rejected() {
  local name="$1"
  local trigger="$2"
  local workflow="$fixture/.github/workflows/review-regression.yml"
  printf 'name: Review regression\n%b\njobs:\n  placeholder:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' \
    "$trigger" > "$workflow"
  if CI_POLICY_ROOT="$fixture" "$ROOT_DIR/Scripts/check_ci_policy.sh" >/dev/null 2>&1; then
    printf 'expected CI policy to reject %s PR trigger\n' "$name" >&2
    exit 1
  fi
  rm "$workflow"
}

expect_rejected mapping 'on:\n  pull_request:'
expect_rejected scalar 'on: pull_request'
expect_rejected inline-list 'on: [push, pull_request]'
expect_rejected block-list 'on:\n  - push\n  - pull_request'
expect_rejected indented-block-list 'on:\n    - push\n    - pull_request'
expect_rejected target-scalar 'on: pull_request_target'
expect_rejected quoted-key '"on": pull_request'
expect_rejected quoted-scalar 'on: "pull_request"'
expect_rejected single-quoted-scalar "on: 'pull_request'"
expect_rejected quoted-inline-list 'on: [push, "pull_request"]'
expect_rejected quoted-block-list 'on:\n  - push\n  - "pull_request"'
expect_rejected quoted-event-key 'on:\n  "pull_request":'

printf 'CI policy trigger-form tests passed\n'
