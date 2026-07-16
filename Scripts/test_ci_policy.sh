#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

ruby -c "$ROOT_DIR/Scripts/workflow_has_pr_trigger.rb" >/dev/null

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

expect_allowed() {
  local name="$1"
  local body="$2"
  local workflow="$fixture/.github/workflows/review-regression.yml"
  printf 'name: Review regression\n%b\n' "$body" > "$workflow"
  CI_POLICY_ROOT="$fixture" "$ROOT_DIR/Scripts/check_ci_policy.sh" >/dev/null \
    || { printf 'expected CI policy to allow %s\n' "$name" >&2; exit 1; }
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
expect_rejected multiline-flow-list 'on: [\n  push,\n  pull_request\n]'
expect_rejected anchored-multiline-flow-list 'on: &events [\n  push,\n  pull_request\n]'
expect_rejected anchored-block-mapping 'on: &events\n  push:\n  pull_request:'
expect_rejected aliased-event-list 'x-events: &events [push, pull_request]\non: *events'
expect_allowed non-trigger-matrix 'on: workflow_dispatch\njobs:\n  test:\n    strategy:\n      matrix:\n        mode:\n          - pull_request\n    runs-on: ubuntu-latest\n    steps:\n      - run: true'
expect_allowed nested-on-value 'on:\n  push:\n    branches:\n      - pull_request\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true'
expect_allowed nested-flow-on-value 'on: { push: { branches: [pull_request] } }\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true'
expect_allowed trigger-name-in-comments 'on: # pull_request is handled by pr-fast\n  workflow_dispatch: # no pull_request trigger here\njobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: true'

printf 'CI policy trigger-form tests passed\n'
