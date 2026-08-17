#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKFLOW="$ROOT/.github/workflows/release-cli.yml"
ASSET_CHECKER="$ROOT/Scripts/check-release-assets.sh"
SPARKLE_HELPERS="$ROOT/Scripts/sparkle_helpers.sh"

fail() {
  echo "release-cli workflow test failed: $*" >&2
  exit 1
}

[[ -f "$WORKFLOW" ]] || fail "missing $WORKFLOW"
[[ -f "$ASSET_CHECKER" ]] || fail "missing $ASSET_CHECKER"
[[ -f "$SPARKLE_HELPERS" ]] || fail "missing $SPARKLE_HELPERS"

# The fork's signed app and dSYM use CodexBar-<full-tag-version> rather than
# upstream's CodexBar-macos-<arch>-<version> convention.
grep -Fq 'ARTIFACT_BASENAME="CodexBar-${TAG#v}"' "$ASSET_CHECKER" || \
  fail "release asset checker must use the fork tag-derived app basename"
grep -Fq 'gh release view "$TAG" --repo o1xhack/CodexBar-Mobile' "$ASSET_CHECKER" || \
  fail "release asset checker must pin GitHub reads to the fork"

asset_test_dir=$(mktemp -d)
trap 'rm -rf "$asset_test_dir"' EXIT
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$TEST_RELEASE_ASSETS"' \
  > "$asset_test_dir/gh"
chmod +x "$asset_test_dir/gh"

run_asset_check() (
  export PATH="$asset_test_dir:$PATH"
  export TEST_RELEASE_ASSETS=$1
  # A parent release shell used to export this sentinel without exporting the
  # helper functions, causing child lint tests to skip the helper definitions.
  export CODEXBAR_SPARKLE_HELPERS_LOADED=1
  # shellcheck disable=SC1090
  source "$SPARKLE_HELPERS"
  check_assets "v1.2.3-mobile.4.5.6" "CodexBar-1.2.3-mobile.4.5.6"
)

both_assets=$'CodexBar-1.2.3-mobile.4.5.6.zip\nCodexBar-1.2.3-mobile.4.5.6.dSYM.zip'
run_asset_check "$both_assets" >/dev/null || fail "complete fork assets must pass"
if run_asset_check 'CodexBar-1.2.3-mobile.4.5.6.dSYM.zip' >/dev/null 2>&1; then
  fail "dSYM-only release must not satisfy the app ZIP check"
fi
if run_asset_check 'CodexBar-1.2.3-mobile.4.5.6.zip' >/dev/null 2>&1; then
  fail "app-only release must not satisfy the dSYM check"
fi
similar_assets=$'CodexBar-1x2x3-mobilex4x5x6-old.zip\nCodexBar-1x2x3-mobilex4x5x6-old.dSYM.zip'
if run_asset_check "$similar_assets" >/dev/null 2>&1; then
  fail "similarly named release assets must not satisfy exact tag checks"
fi

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
