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
  jq empty "$FIXTURES/$name.json" || fail "$name fixture must be valid JSON"
}

expect_pass() {
  "$GATE" --fixture "$FIXTURES/$1.json" >/dev/null || fail "$1 should pass"
}

expect_fail() {
  local exit_code=0
  "$GATE" --fixture "$FIXTURES/$1.json" >/dev/null 2>&1 || exit_code=$?
  [[ "$exit_code" == "1" ]] || fail "$1 should fail through the gate (exit 1), got exit $exit_code"
}

codex='{"login":"chatgpt-codex-connector"}'
owner='{"login":"o1xhack"}'
clean_body='Codex Review: Didn'"'"'t find any major issues. Hooray! **Reviewed commit:** `aaaaaaaaaa`'
clean_comment="[{\"author\":$codex,\"body\":\"$clean_body\",\"createdAt\":\"2026-08-17T00:00:06Z\"}]"

write_fixture no-review '[]' '[]' '[]'
expect_fail no-review

write_fixture clean '[]' "$clean_comment" '[]'
expect_pass clean

stale_body='Codex Review: Didn'"'"'t find any major issues. **Reviewed commit:** `bbbbbbbbbb`'
stale_comment=$(jq -nc --arg body "$stale_body" \
  '[{author:{login:"chatgpt-codex-connector"},body:$body,createdAt:"2026-08-17T00:00:00Z"}]')
write_fixture stale-clean '[]' "$stale_comment" '[]'
expect_fail stale-clean

later_finding=$(jq -nc --argjson author "$codex" '[{
  author:$author,
  body:"Codex finding after clean. Reviewed commit: `aaaaaaaaaa`",
  submittedAt:"2026-08-17T00:00:07Z",
  commit:{oid:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
}]')
write_fixture later-finding-same-head "$later_finding" "$clean_comment" '[]'
expect_fail later-finding-same-head

review_request=$(jq -nc --argjson author "$owner" \
  '{author:$author,body:"@codex review",createdAt:"2026-08-17T00:00:07Z"}')
connector_noise="[{\"author\":$codex,\"body\":\"\",\"submittedAt\":\"2026-08-17T00:00:08Z\",\"commit\":{\"oid\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}}]"
write_fixture review-still-in-flight "$connector_noise" "${clean_comment%]} ,$review_request]" '[]'
expect_fail review-still-in-flight

paired_reviews=$(jq -nc --argjson author "$codex" '[
  {author:$author,body:"Reviewed commit: `1111111111`",submittedAt:"2026-08-17T00:00:01Z",commit:{oid:"1111111111111111111111111111111111111111"}},
  {author:$author,body:"Reviewed commit: `2222222222`",submittedAt:"2026-08-17T00:00:03Z",commit:{oid:"2222222222222222222222222222222222222222"}},
  {author:$author,body:"Reviewed commit: `aaaaaaaaaa`",submittedAt:"2026-08-17T00:00:05Z",commit:{oid:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}
]')
paired_comments=$(jq -nc --argjson author "$codex" '[
  {author:$author,body:"Codex Review: Didn\u0027t find any major issues. **Reviewed commit:** `1111111111`",createdAt:"2026-08-17T00:00:02Z"},
  {author:$author,body:"Codex Review: Didn\u0027t find any major issues. **Reviewed commit:** `2222222222`",createdAt:"2026-08-17T00:00:04Z"},
  {author:$author,body:"Codex Review: Didn\u0027t find any major issues. **Reviewed commit:** `aaaaaaaaaa`",createdAt:"2026-08-17T00:00:06Z"}
]')
write_fixture full-short-pairs "$paired_reviews" "$paired_comments" '[]'
expect_pass full-short-pairs

unresolved="[{\"id\":\"thread-1\",\"isResolved\":false,\"isOutdated\":true,\"comments\":{\"nodes\":[{\"author\":$codex,\"body\":\"finding\",\"path\":\"README.md\",\"url\":\"https://example.test/thread-1\"}]}}]"
write_fixture outdated-unresolved '[]' "$clean_comment" "$unresolved"
expect_fail outdated-unresolved

six_reviews=$(jq -nc --argjson author "$codex" '[
  {author:$author,body:"Reviewed commit: `1111111111`",submittedAt:"2026-08-17T00:00:01Z",commit:{oid:"1111111111111111111111111111111111111111"}},
  {author:$author,body:"Reviewed commit: `2222222222`",submittedAt:"2026-08-17T00:00:02Z",commit:{oid:"2222222222222222222222222222222222222222"}},
  {author:$author,body:"Reviewed commit: `3333333333`",submittedAt:"2026-08-17T00:00:03Z",commit:{oid:"3333333333333333333333333333333333333333"}},
  {author:$author,body:"Reviewed commit: `4444444444`",submittedAt:"2026-08-17T00:00:04Z",commit:{oid:"4444444444444444444444444444444444444444"}},
  {author:$author,body:"Reviewed commit: `5555555555`",submittedAt:"2026-08-17T00:00:05Z",commit:{oid:"5555555555555555555555555555555555555555"}}
]')
write_fixture six-rounds-no-audit "$six_reviews" "$clean_comment" '[]'
expect_fail six-rounds-no-audit

audit_body=$'Codex review architecture audit\nHead: aaaaaaaaaa\nRepeated finding pattern: Review findings share an ownership-boundary flaw.\nRoot design/requirements problem: The gate encoded comments without an explicit lifecycle.\nRevised approach: Model ordered review evidence and validate the pre-sixth checkpoint.'
late_audit=$(jq -nc --argjson author "$owner" --arg body "$audit_body" \
  '{author:$author,body:$body,createdAt:"2026-08-17T00:00:07Z"}')
write_fixture six-rounds-late-audit "$six_reviews" "${clean_comment%]} ,$late_audit]" '[]'
expect_fail six-rounds-late-audit

marker_only=$(jq -nc --argjson author "$owner" \
  '{author:$author,body:"Codex review architecture audit\nHead: aaaaaaaaaa",createdAt:"2026-08-17T00:00:00Z"}')
write_fixture six-rounds-marker-only "$six_reviews" "${clean_comment%]} ,$marker_only]" '[]'
expect_fail six-rounds-marker-only

audit_comment=$(jq -nc --argjson author "$owner" --arg body "$audit_body" \
  '{author:$author,body:$body,createdAt:"2026-08-17T00:00:00Z"}')
write_fixture six-rounds-with-audit "$six_reviews" "${clean_comment%]} ,$audit_comment]" '[]'
expect_pass six-rounds-with-audit

full_head_audit=${audit_body/Head: aaaaaaaaaa/Head: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}
full_head_comment=$(jq -nc --argjson author "$owner" --arg body "$full_head_audit" \
  '{author:$author,body:$body,createdAt:"2026-08-17T00:00:00Z"}')
write_fixture six-rounds-with-full-head-audit "$six_reviews" \
  "${clean_comment%]} ,$full_head_comment]" '[]'
expect_pass six-rounds-with-full-head-audit

cp "$FIXTURES/clean.json" "$FIXTURES/truncated.json"
jq '.reviewThreads.pageInfo.hasNextPage = true' "$FIXTURES/truncated.json" \
  > "$FIXTURES/truncated.tmp"
mv "$FIXTURES/truncated.tmp" "$FIXTURES/truncated.json"
expect_fail truncated

echo "PR review gate tests passed."
