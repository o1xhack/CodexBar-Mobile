#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository="${1:-}"
commit_sha="${2:-}"
head_ref="${3:-}"
upstream_repository="${UPSTREAM_REPOSITORY:-steipete/CodexBar}"
api_url="${GITHUB_API_URL:-https://api.github.com}"
token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

trusted=false
reason="not an upstream-sync merge"

emit_result() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'trusted-upstream-sync=%s\n' "$trusted" >> "$GITHUB_OUTPUT"
    printf 'trusted-upstream-reason=%s\n' "$reason" >> "$GITHUB_OUTPUT"
  fi
  printf 'trusted-upstream-sync=%s: %s\n' "$trusted" "$reason"
}

if [[ "$head_ref" != upstream-sync/* ]]; then
  emit_result
  exit 0
fi

if [[ -z "$repository" || -z "$commit_sha" ]]; then
  reason="missing repository or merge commit; running final CI conservatively"
  emit_result
  exit 0
fi

if [[ -z "$token" ]]; then
  reason="GitHub token unavailable; running final CI conservatively"
  emit_result
  exit 0
fi

upstream_version="$(sed -n 's/^UPSTREAM_VERSION=//p' "$ROOT_DIR/version.env" | tail -1)"
if [[ ! "$upstream_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$ ]]; then
  reason="version.env has an invalid UPSTREAM_VERSION; running final CI conservatively"
  emit_result
  exit 0
fi

api_get() {
  local path="$1"
  curl --fail --silent --show-error --location \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${token}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${api_url}${path}"
}

release_json="$(api_get "/repos/${upstream_repository}/releases/tags/${upstream_version}")" || {
  reason="upstream release ${upstream_version} could not be verified; running final CI conservatively"
  emit_result
  exit 0
}

if [[ "$(jq -r '.draft or .prerelease' <<< "$release_json")" != false ]]; then
  reason="upstream release ${upstream_version} is not a published stable release"
  emit_result
  exit 0
fi

ref_json="$(api_get "/repos/${upstream_repository}/git/ref/tags/${upstream_version}")" || {
  reason="upstream tag ${upstream_version} could not be resolved; running final CI conservatively"
  emit_result
  exit 0
}
object_type="$(jq -r '.object.type' <<< "$ref_json")"
upstream_sha="$(jq -r '.object.sha' <<< "$ref_json")"
if [[ "$object_type" == tag ]]; then
  tag_json="$(api_get "/repos/${upstream_repository}/git/tags/${upstream_sha}")" || {
    reason="annotated upstream tag ${upstream_version} could not be peeled"
    emit_result
    exit 0
  }
  upstream_sha="$(jq -r '.object.sha' <<< "$tag_json")"
fi

if ! git -C "$ROOT_DIR" cat-file -e "${upstream_sha}^{commit}" 2>/dev/null \
  || ! git -C "$ROOT_DIR" merge-base --is-ancestor "$upstream_sha" "$commit_sha"
then
  reason="upstream tag ${upstream_version} is not contained in the merged commit"
  emit_result
  exit 0
fi

checks_json="$(api_get "/repos/${upstream_repository}/commits/${upstream_sha}/check-runs?per_page=100")" || {
  reason="upstream checks for ${upstream_version} could not be read; running final CI conservatively"
  emit_result
  exit 0
}
if ! printf '%s\n' "$checks_json" | "$ROOT_DIR/Scripts/ci_check_runs_are_reusable.sh"; then
  reason="upstream checks are missing or not all completed successfully; running final CI conservatively"
  emit_result
  exit 0
fi

trusted=true
reason="published ${upstream_repository} ${upstream_version} is contained in this upstream-sync merge and has successful upstream checks"
emit_result
