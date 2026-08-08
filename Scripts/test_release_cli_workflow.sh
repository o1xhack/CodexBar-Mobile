#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKFLOW="$ROOT/.github/workflows/release-cli.yml"
ASSET_CHECKER="$ROOT/Scripts/check-release-assets.sh"

fail() {
  echo "release-cli workflow test failed: $*" >&2
  exit 1
}

[[ -f "$WORKFLOW" ]] || fail "missing $WORKFLOW"
[[ -f "$ASSET_CHECKER" ]] || fail "missing $ASSET_CHECKER"

# The fork's signed app and dSYM use CodexBar-<full-tag-version> rather than
# upstream's CodexBar-macos-<arch>-<version> convention.
grep -Fq 'ARTIFACT_PREFIX="CodexBar-${TAG#v}"' "$ASSET_CHECKER" || \
  fail "release asset checker must use the fork tag-derived app prefix"
grep -Fq 'gh release view "$TAG" --repo o1xhack/CodexBar-Mobile' "$ASSET_CHECKER" || \
  fail "release asset checker must pin GitHub reads to the fork"

# Fork releases must keep producing the release assets. Only the upstream-owned
# Homebrew dispatch is repository-gated.
grep -F -A 2 -- "- name: Upload release assets" "$WORKFLOW" \
  | grep -Fqx "        if: github.event_name == 'release'" || \
  fail "release asset upload gate is missing"
grep -F -A 2 -- "- name: Upload workflow artifact (manual runs)" "$WORKFLOW" \
  | grep -Fqx "        if: github.event_name == 'workflow_dispatch'" || \
  fail "manual artifact upload gate is missing"
grep -Fq "if: github.event_name == 'release' && github.repository == 'steipete/CodexBar'" "$WORKFLOW" || \
  fail "Homebrew job must run only for upstream release events"

# Preserve the upstream behavior exactly when that repository runs the job.
grep -Fq -- "--repo steipete/homebrew-tap" "$WORKFLOW" || \
  fail "upstream Homebrew tap target changed"
grep -Fq -- "-f repository=steipete/CodexBar" "$WORKFLOW" || \
  fail "upstream release source changed"
grep -Fq 'GH_TOKEN: ${{ secrets.HOMEBREW_TAP_TOKEN }}' "$WORKFLOW" || \
  fail "upstream Homebrew token wiring changed"

echo "release-cli workflow fork/upstream gates OK"
