#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${ROOT_DIR}/.build/lint-tools/bin"

ensure_tools() {
  # Always delegate to the installer so pinned versions are enforced.
  # The installer is idempotent and exits early when the expected versions are already present.
  "${ROOT_DIR}/Scripts/install_lint_tools.sh"
}

# Audit every `*.xcstrings` file under the iOS app for entries left in
# `state: "new"`. Xcode auto-creates such entries with the English source
# as a fallback `value` whenever a developer adds a new `String(localized:)`
# call, and the build / TestFlight upload still succeeds — so non-English
# locales silently ship the English text. Build 55 (1.1.0 release notes
# English-only on Chinese / Japanese iPhones) and Build 92 (same regression
# for the 1.3.0 catalog) both shipped this way before user-reported.
# Failing lint here forces every new string to carry real translations
# for all 4 locales (en / zh-Hans / zh-Hant / ja) before it can be merged.
audit_xcstrings() {
  command -v jq >/dev/null 2>&1 || { echo "jq is required for i18n audit; install via brew install jq" >&2; return 2; }
  command -v python3 >/dev/null 2>&1 || { echo "python3 is required for i18n audit; install via xcode-select --install" >&2; return 2; }

  local rc=0
  while IFS= read -r -d '' xcstrings; do
    local missing
    missing=$(jq -r '
      .strings | to_entries
      | map(
          .key as $k
          | ((.value.localizations // {}) | to_entries
              | map(select(.value.stringUnit.state == "new") | "\(.key)|\($k)")
            )
        )
      | flatten | .[]
    ' "$xcstrings")

    if [[ -n "$missing" ]]; then
      local count
      count=$(printf '%s\n' "$missing" | wc -l | tr -d ' ')
      echo "ERROR: $xcstrings has $count locale entries in state=\"new\" (untranslated, English fallback):" >&2
      printf '%s\n' "$missing" | awk -F'|' '{printf "  [%s] %s\n", $1, substr($2, 1, 100) (length($2) > 100 ? "…" : "")}' | head -30 >&2
      [[ "$count" -gt 30 ]] && echo "  … ($((count - 30)) more)" >&2
      echo "Provide proper translations and set state=\"translated\" for each locale." >&2
      rc=1
    else
      echo "i18n audit: $xcstrings — all locales translated"
    fi
  done < <(find "$ROOT_DIR" -name '*.xcstrings' -not -path '*/.build/*' -not -path '*/DerivedData/*' -print0)

  # Cross-check: every String(localized:) in Swift source must have a
  # matching entry in the iOS Localizable.xcstrings. Xcode only auto-extracts
  # new keys on a full Xcode build — swift test / lint never trigger that
  # extraction. Build 130 of iOS 1.7.0 shipped 21 untranslated keys (the
  # entire 1.7.0 in-app release-notes catalog + CloudKit sync status text)
  # to zh-Hans / ja / zh-Hant users as English fallback. The original
  # state="new" audit above passed because the catalog had no orphan
  # entries — but couldn't see that 21 source keys had no catalog entry
  # at all. This second pass closes that gap.
  local ios_xcstrings="$ROOT_DIR/CodexBarMobile/CodexBarMobile/Localizable.xcstrings"
  if [[ -f "$ios_xcstrings" ]]; then
    if ! python3 "$ROOT_DIR/Scripts/audit_localized_keys.py" "$ios_xcstrings" \
         "$ROOT_DIR/CodexBarMobile/CodexBarMobile"; then
      rc=1
    fi
  fi

  return "$rc"
}

# Guard: any change to the Codex / Claude cost-usage parser must come
# with a `parserLogicVersion` bump in CostUsagePricing.swift, so the
# pricingFingerprint rolls and every user's on-disk cache (which carries
# token attributions baked-in by the previous parser) gets invalidated
# on next launch.
#
# Why this exists: the 0.23.3 hotfix had to ship because a pre-existing
# parser bug (32 KB prefixBytes truncating Codex CLI 0.125 turn_context
# events) silently misattributed ~93% of token usage to gpt-5. The cache
# wouldn't have rolled itself even after the parser fix without the
# manual parserLogicVersion bump. Easy to forget; this lint catches it.
#
# Escape hatch: set ALLOW_PARSER_CHANGE=1 for cosmetic / comment-only
# edits where invalidating user caches would be wasteful.
audit_parser_version() {
  if [[ "${ALLOW_PARSER_CHANGE:-0}" == "1" ]]; then
    echo "parser-version audit: ALLOW_PARSER_CHANGE=1 → skipping"
    return 0
  fi

  local base="${PARSER_LINT_BASE:-origin/mobile-dev}"

  # If the base ref isn't in the local repo (typical in shallow CI
  # checkouts), try to fetch it. We MUST NOT silently skip — a missing
  # base would otherwise let parser changes ship without a fingerprint
  # bump, defeating the cache-invalidation contract this audit exists
  # to enforce. Caught in 0.23.3 code review as P1-1.
  if ! git -C "$ROOT_DIR" rev-parse --verify "$base" >/dev/null 2>&1; then
    if [[ "$base" == */* ]]; then
      local remote="${base%%/*}"
      local branch="${base#*/}"
      git -C "$ROOT_DIR" fetch --quiet --no-tags --depth=50 "$remote" "$branch" 2>/dev/null || true
    fi
  fi

  if ! git -C "$ROOT_DIR" rev-parse --verify "$base" >/dev/null 2>&1; then
    if [[ "${ALLOW_MISSING_BASE:-0}" == "1" ]]; then
      echo "parser-version audit: ALLOW_MISSING_BASE=1 → skipping (base ref '$base' unavailable)"
      return 0
    fi
    echo "ERROR: parser-version audit can't find base ref '$base'." >&2
    echo "       In CI, ensure your checkout fetches origin/mobile-dev" >&2
    echo "       (e.g., actions/checkout@v4 with fetch-depth: 0)." >&2
    echo "       Locally, run: git fetch origin mobile-dev" >&2
    echo "       To intentionally skip (e.g., on a fresh fork clone with" >&2
    echo "       no network), set ALLOW_MISSING_BASE=1." >&2
    return 1
  fi

  # Parser-semantics-bearing files. Editing any of these without bumping
  # parserLogicVersion risks shipping a fix whose results never reach
  # users (their caches stay frozen with the old parser's attribution).
  local guarded_files=(
    "Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift"
    "Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner+Claude.swift"
    "Sources/CodexBarCore/Vendored/CostUsage/CostUsageJsonl.swift"
  )
  local pricing_file="Sources/CodexBarCore/Vendored/CostUsage/CostUsagePricing.swift"

  local changed_parser=()
  local f
  for f in "${guarded_files[@]}"; do
    if ! git -C "$ROOT_DIR" diff --quiet "$base"...HEAD -- "$f"; then
      changed_parser+=("$f")
    fi
  done

  if [[ ${#changed_parser[@]} -eq 0 ]]; then
    echo "parser-version audit: no parser code changes since $base"
    return 0
  fi

  # Parser code changed. Look for a +/- on the parserLogicVersion line
  # in CostUsagePricing.swift. Pricing-table key edits don't count —
  # those roll the fingerprint via sorted keys already; we want a
  # genuine parserLogicVersion bump.
  if git -C "$ROOT_DIR" diff "$base"...HEAD -- "$pricing_file" \
       | grep -E '^[+-][[:space:]]*static[[:space:]]+let[[:space:]]+parserLogicVersion' >/dev/null; then
    echo "parser-version audit: parser code changed AND parserLogicVersion bumped — OK"
    return 0
  fi

  echo "ERROR: parser code changed since $base but parserLogicVersion was not bumped." >&2
  echo "       Files changed:" >&2
  printf '         - %s\n' "${changed_parser[@]}" >&2
  echo "" >&2
  echo "       Bump 'static let parserLogicVersion = N' in:" >&2
  echo "         $pricing_file" >&2
  echo "       so the pricingFingerprint rolls and every user's on-disk" >&2
  echo "       cache (with old-parser attributions baked in) is invalidated" >&2
  echo "       and re-scanned with the fixed parser on next launch." >&2
  echo "" >&2
  echo "       For comment-only / non-semantic edits set ALLOW_PARSER_CHANGE=1." >&2
  return 1
}

# Guard: the committed Sources/CodexBarCore/Generated/CodexParserHash.generated.swift
# must match a fresh hash of the Codex cost-usage parser source. That hash feeds the
# cache `producerKey` invalidation axis that the v0.29.0 upstream merge combined into
# CostUsageCache.swift (alongside the fork's pricingFingerprint axis). A stale hash
# silently freezes producerKey so a later parser-source change would not roll it.
# This complements audit_parser_version (which guards the parserLogicVersion
# fingerprint axis). Regenerate via:
#   bash Scripts/regenerate-codex-parser-hash.sh
check_codex_parser_hash() {
  "${ROOT_DIR}/Scripts/regenerate-codex-parser-hash.sh" --check
}

check_package_product_paths() {
  "${ROOT_DIR}/Scripts/test_package_product_paths.sh"
}

check_release_dsym_paths() {
  "${ROOT_DIR}/Scripts/test_release_dsym_paths.sh"
}

check_sparkle_signing_paths() {
  "${ROOT_DIR}/Scripts/test_sparkle_signing_paths.sh"
}

check_swift_test_sharding() {
  "${ROOT_DIR}/Scripts/test_swift_test_sharding.sh"
}

check_site_locales() {
  node "${ROOT_DIR}/Scripts/check-app-locales.mjs"
  node "${ROOT_DIR}/Scripts/check-site-locales.mjs"
  node --check "${ROOT_DIR}/docs/site.js"
}

cmd="${1:-lint}"

case "$cmd" in
  lint)
    check_package_product_paths
    check_release_dsym_paths
    check_sparkle_signing_paths
    check_swift_test_sharding
    check_site_locales
    ensure_tools
    "${BIN_DIR}/swiftformat" Sources Tests --lint
    "${BIN_DIR}/swiftlint" --strict
    audit_xcstrings
    audit_parser_version
    check_codex_parser_hash
    ;;
  format)
    ensure_tools
    "${BIN_DIR}/swiftformat" Sources Tests
    ;;
  audit-i18n)
    audit_xcstrings
    ;;
  audit-parser-version)
    audit_parser_version
    ;;
  audit-parser-hash)
    check_codex_parser_hash
    ;;
  *)
    printf 'Usage: %s [lint|format|audit-i18n|audit-parser-version|audit-parser-hash]\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
