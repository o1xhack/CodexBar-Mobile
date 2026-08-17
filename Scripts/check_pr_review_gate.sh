#!/usr/bin/env bash
set -euo pipefail

REPO="o1xhack/CodexBar-Mobile"

usage() {
  cat <<'EOF'
Usage:
  Scripts/check_pr_review_gate.sh <pr-number-or-url>
  Scripts/check_pr_review_gate.sh --fixture <pull-request.json>

The gate passes only when Codex has reported a clean review for the current PR
head, every review thread is explicitly resolved, and review rounds above five
have a current-head architecture-audit comment.
EOF
}

if [[ "${1:-}" == "--fixture" ]]; then
  [[ -n "${2:-}" && -f "$2" ]] || {
    usage >&2
    exit 2
  }
  pr_json=$(cat "$2")
elif [[ -n "${1:-}" ]]; then
  command -v gh >/dev/null || {
    echo "PR review gate failed: gh is required" >&2
    exit 2
  }
  pr_number=$(gh pr view "$1" --repo "$REPO" --json number --jq '.number')
  pr_json=$(gh api graphql -F number="$pr_number" -f query='
    query($number: Int!) {
      repository(owner: "o1xhack", name: "CodexBar-Mobile") {
        pullRequest(number: $number) {
          number
          url
          state
          isDraft
          headRefOid
          reviews(first: 100) {
            pageInfo { hasNextPage }
            nodes {
              author { login }
              state
              submittedAt
              body
              commit { oid }
              comments(first: 100) {
                pageInfo { hasNextPage }
                nodes { body }
              }
            }
          }
          comments(first: 100) {
            pageInfo { hasNextPage }
            nodes {
              author { login }
              body
              createdAt
            }
          }
          reviewThreads(first: 100) {
            pageInfo { hasNextPage }
            nodes {
              id
              isResolved
              isOutdated
              comments(first: 20) {
                nodes {
                  author { login }
                  body
                  createdAt
                  path
                  line
                  url
                }
              }
            }
          }
        }
      }
    }
  ' | jq -c '.data.repository.pullRequest')
else
  usage >&2
  exit 2
fi

summary=$(jq -c '
  def is_codex:
    ((.author.login // "") | test("^chatgpt-codex-connector(\\[bot\\])?$"));
  def reviewed_oid:
    (.body // ""
      | (try capture("Reviewed commit:[^`]*`(?<oid>[0-9a-f]{7,40})`").oid catch null) // null);
  def is_clean:
    ((.body // "") | contains("Didn\u0027t find any major issues"));
  def is_substantive_review_comment:
    (.body // "") as $body
    | (($body | length) > 0)
      and (($body | startswith("To use Codex here,")) | not);
  def normalize_oid($oid; $fullOids):
    if $oid == null then null
    elif ($oid | length) == 40 then $oid
    else
      ([$fullOids[] | select(startswith($oid))] | unique) as $matches
      | if ($matches | length) == 1 then $matches[0] else $oid end
    end;
  def has_audit_field($name):
    ((.body // "") | test("(?m)^" + $name + ":[ \\t]*[^ \\t\\r\\n]"));
  def audit_head_oid:
    (.body // ""
      | try capture("(?m)^Head:[ \\t]*(?<oid>[0-9a-f]{7,40})[ \\t]*$").oid catch null);

  .headRefOid as $head
  | ([$head] + [(.reviews.nodes // [])[].commit.oid]
      | map(select(. != null and length == 40))
      | unique) as $fullOids
  | [(.reviews.nodes // [])[]
      | select(is_codex)
      | reviewed_oid as $bodyOid
      | ([((.comments.nodes // [])[]) | select(is_substantive_review_comment)]
          | length > 0) as $hasFinding
      | (if ($bodyOid != null) or $hasFinding then .commit.oid
         else null
         end) as $rawOid
      | {oid: normalize_oid($rawOid; $fullOids),
         at: .submittedAt,
         clean: (is_clean and ($hasFinding | not))}
      | select(.oid != null and .at != null)] as $reviewEvents
  | [(.comments.nodes // [])[]
      | select(is_codex)
      | reviewed_oid as $rawOid
      | {oid: normalize_oid($rawOid; $fullOids), at: .createdAt, clean: is_clean}
      | select(.oid != null and .at != null)] as $commentEvents
  | ($reviewEvents + $commentEvents) as $allReviewEvents
  | ($allReviewEvents
      | group_by(.oid)
      | map(min_by(.at))
      | sort_by(.at)) as $distinctReviewEvents
  | ($distinctReviewEvents[5] // null) as $sixthReview
  | ($allReviewEvents
      | map(select(.oid == $head))
      | sort_by(.at)) as $currentHeadEvents
  | (($currentHeadEvents | map(.at) | max) // null) as $latestCurrentHeadAt
  | (if $latestCurrentHeadAt == null then null
     else {
       oid: $head,
       at: $latestCurrentHeadAt,
       clean: ([$currentHeadEvents[] | select(.at == $latestCurrentHeadAt)]
         | all(.[]; .clean == true))
     }
     end) as $latestCurrentHeadEvent
  | ([((.comments.nodes // [])[])
      | select((is_codex | not))
      | select((.body // "") | test("(?im)^[ \\t]*@codex[ \\t]+review[ \\t]*$"))
      | .createdAt]
      | sort
      | .[-1] // null) as $latestReviewRequestAt
  | (($latestReviewRequestAt != null)
      and (($latestCurrentHeadEvent == null)
        or ($latestReviewRequestAt >= $latestCurrentHeadEvent.at))) as $reviewInFlight
  | (($latestCurrentHeadEvent != null)
      and ($latestCurrentHeadEvent.clean == true)
      and ($reviewInFlight | not)) as $currentClean
  | [(.reviewThreads.nodes // [])[] | select(.isResolved != true)] as $unresolved
  | [(.comments.nodes // [])[]
      | select((is_codex | not))
      | select((.body // "") | contains("Codex review architecture audit"))
      | select($sixthReview != null)
      | audit_head_oid as $auditHead
      | select($auditHead != null)
      | select($sixthReview.oid | startswith($auditHead))
      | select(has_audit_field("Repeated finding pattern"))
      | select(has_audit_field("Root design/requirements problem"))
      | select(has_audit_field("Revised approach"))
      | select(.createdAt < $sixthReview.at)] as $architectureAudits
  | {
      number,
      url,
      state,
      isDraft,
      head: $head,
      rounds: ($distinctReviewEvents | length),
      currentClean: $currentClean,
      reviewInFlight: $reviewInFlight,
      latestCurrentHeadEvent: $latestCurrentHeadEvent,
      unresolvedCount: ($unresolved | length),
      unresolved: [$unresolved[] | {
        id,
        isOutdated,
        url: (.comments.nodes[0].url // null),
        path: (.comments.nodes[0].path // null)
      }],
      architectureAuditRequired:
        (($distinctReviewEvents | length) > 5),
      architectureAuditRecorded: (($architectureAudits | length) > 0),
      sixthReview: $sixthReview,
      truncated:
        ((.reviews.pageInfo.hasNextPage // false)
          or (.comments.pageInfo.hasNextPage // false)
          or (.reviewThreads.pageInfo.hasNextPage // false)
          or ([((.reviews.nodes // [])[].comments.pageInfo.hasNextPage // false)] | any))
    }
' <<< "$pr_json")

failed=0
state=$(jq -r '.state' <<< "$summary")
is_draft=$(jq -r '.isDraft' <<< "$summary")
current_clean=$(jq -r '.currentClean' <<< "$summary")
review_in_flight=$(jq -r '.reviewInFlight' <<< "$summary")
unresolved_count=$(jq -r '.unresolvedCount' <<< "$summary")
audit_required=$(jq -r '.architectureAuditRequired' <<< "$summary")
audit_recorded=$(jq -r '.architectureAuditRecorded' <<< "$summary")
truncated=$(jq -r '.truncated' <<< "$summary")

if [[ "$state" != "OPEN" ]]; then
  echo "PR review gate failed: PR state is $state, expected OPEN" >&2
  failed=1
fi
if [[ "$is_draft" == "true" ]]; then
  echo "PR review gate failed: PR is still draft" >&2
  failed=1
fi
if [[ "$review_in_flight" == "true" ]]; then
  echo "PR review gate failed: requested Codex review is still in flight" >&2
  failed=1
elif [[ "$current_clean" != "true" ]]; then
  echo "PR review gate failed: current head has no clean Codex review" >&2
  failed=1
fi
if [[ "$unresolved_count" != "0" ]]; then
  echo "PR review gate failed: $unresolved_count review thread(s) are not explicitly resolved" >&2
  jq -r '.unresolved[] | "  - \(.url // .id) [\(.path // "unknown path")] outdated=\(.isOutdated)"' \
    <<< "$summary" >&2
  failed=1
fi
if [[ "$audit_required" == "true" && "$audit_recorded" != "true" ]]; then
  echo "PR review gate failed: more than five review rounds require a current-head architecture audit" >&2
  failed=1
fi
if [[ "$truncated" == "true" ]]; then
  echo "PR review gate failed: GitHub review evidence exceeds the audited 100-item page" >&2
  failed=1
fi

if [[ "$failed" == "1" ]]; then
  jq . <<< "$summary" >&2
  exit 1
fi

printf 'PR review gate passed: PR #%s head=%s rounds=%s unresolved=0\n' \
  "$(jq -r '.number' <<< "$summary")" \
  "$(jq -r '.head' <<< "$summary")" \
  "$(jq -r '.rounds' <<< "$summary")"
