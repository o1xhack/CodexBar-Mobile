#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GATE="$ROOT/Scripts/check_pr_review_gate.sh"
FIXTURES=$(mktemp -d)
trap 'rm -rf "$FIXTURES"' EXIT

fail() {
  echo "PR review gate test failed: $*" >&2
  exit 1
}

write_fixture() {
  local name=$1
  local reviews=$2
  local comments=$3
  local threads=$4
  cat > "$FIXTURES/$name.json" <<EOF
{
  "number": 100,
  "url": "https://github.com/o1xhack/CodexBar-Mobile/pull/100",
  "state": "OPEN",
  "isDraft": false,
  "headRefOid": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "reviews": {"nodes": $reviews},
  "comments": {"nodes": $comments},
  "reviewThreads": {"nodes": $threads}
}
EOF
}

expect_pass() {
  "$GATE" --fixture "$FIXTURES/$1.json" >/dev/null || fail "$1 should pass"
}

expect_fail() {
  if "$GATE" --fixture "$FIXTURES/$1.json" >/dev/null 2>&1; then
    fail "$1 should fail"
  fi
}

codex='{"login":"chatgpt-codex-connector"}'
owner='{"login":"o1xhack"}'
clean_body='Codex Review: Didn'"'"'t find any major issues. Hooray! **Reviewed commit:** `aaaaaaaaaa`'
clean_comment="[{\"author\":$codex,\"body\":\"$clean_body\",\"createdAt\":\"2026-08-17T00:00:00Z\"}]"

write_fixture no-review '[]' '[]' '[]'
expect_fail no-review

write_fixture clean '[]' "$clean_comment" '[]'
expect_pass clean

stale_comment="[{\"author\":$codex,\"body\":\"Codex Review: Didn't find any major issues. **Reviewed commit:** \\\`bbbbbbbbbb\\\`\",\"createdAt\":\"2026-08-17T00:00:00Z\"}]"
write_fixture stale-clean '[]' "$stale_comment" '[]'
expect_fail stale-clean

unresolved="[{\"id\":\"thread-1\",\"isResolved\":false,\"isOutdated\":true,\"comments\":{\"nodes\":[{\"author\":$codex,\"body\":\"finding\",\"path\":\"README.md\",\"url\":\"https://example.test/thread-1\"}]}}]"
write_fixture outdated-unresolved '[]' "$clean_comment" "$unresolved"
expect_fail outdated-unresolved

six_reviews="[
  {\"author\":$codex,\"commit\":{\"oid\":\"1111111111111111111111111111111111111111\"}},
  {\"author\":$codex,\"commit\":{\"oid\":\"2222222222222222222222222222222222222222\"}},
  {\"author\":$codex,\"commit\":{\"oid\":\"3333333333333333333333333333333333333333\"}},
  {\"author\":$codex,\"commit\":{\"oid\":\"4444444444444444444444444444444444444444\"}},
  {\"author\":$codex,\"commit\":{\"oid\":\"5555555555555555555555555555555555555555\"}}
]"
write_fixture six-rounds-no-audit "$six_reviews" "$clean_comment" '[]'
expect_fail six-rounds-no-audit

audit_comment="{\"author\":$owner,\"body\":\"Codex review architecture audit\\nHead: aaaaaaaaaa\\nRoot issue and revised approach recorded.\",\"createdAt\":\"2026-08-17T00:01:00Z\"}"
write_fixture six-rounds-with-audit "$six_reviews" "${clean_comment%]} ,$audit_comment]" '[]'
expect_pass six-rounds-with-audit

cp "$FIXTURES/clean.json" "$FIXTURES/truncated.json"
jq '.reviewThreads.pageInfo.hasNextPage = true' "$FIXTURES/truncated.json" \
  > "$FIXTURES/truncated.tmp"
mv "$FIXTURES/truncated.tmp" "$FIXTURES/truncated.json"
expect_fail truncated

echo "PR review gate tests passed."
