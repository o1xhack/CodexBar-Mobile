#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$ROOT_DIR/Scripts/ci_check_runs_are_reusable.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

write_checks() {
  local name="$1"
  local body="$2"
  printf '%s\n' "$body" > "$tmp_dir/$name.json"
}

expect_reusable() {
  local name="$1"
  "$gate" "$tmp_dir/$name.json" \
    || { printf 'expected %s checks to be reusable\n' "$name" >&2; exit 1; }
}

expect_rejected() {
  local name="$1"
  if "$gate" "$tmp_dir/$name.json"; then
    printf 'expected %s checks to be rejected\n' "$name" >&2
    exit 1
  fi
}

write_checks success '{"check_runs":[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"success"}]}'
write_checks cancelled '{"check_runs":[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"cancelled"}]}'
write_checks pending '{"check_runs":[{"status":"completed","conclusion":"success"},{"status":"in_progress","conclusion":null}]}'
write_checks neutral '{"check_runs":[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"neutral"}]}'
write_checks skipped '{"check_runs":[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"skipped"}]}'
write_checks failure '{"check_runs":[{"status":"completed","conclusion":"failure"}]}'
write_checks empty '{"check_runs":[]}'

expect_reusable success
expect_rejected cancelled
expect_rejected pending
expect_rejected neutral
expect_rejected skipped
expect_rejected failure
expect_rejected empty

printf 'upstream check reuse gate tests passed\n'
