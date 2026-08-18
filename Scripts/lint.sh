#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${ROOT_DIR}/.build/lint-tools/bin"

ensure_swiftformat() {
  "${ROOT_DIR}/Scripts/install_lint_tools.sh" swiftformat
}

ensure_swiftlint() {
  "${ROOT_DIR}/Scripts/install_lint_tools.sh" swiftlint
}

# Audit every iOS `*.xcstrings` file for untranslated entries and for source
# keys missing from the catalog. Xcode can otherwise leave non-English users
# with English fallback text even when SwiftPM checks pass.
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

  local ios_xcstrings="$ROOT_DIR/CodexBarMobile/CodexBarMobile/Localizable.xcstrings"
  if [[ -f "$ios_xcstrings" ]]; then
    if ! python3 "$ROOT_DIR/Scripts/audit_localized_keys.py" "$ios_xcstrings" \
         "$ROOT_DIR/CodexBarMobile/CodexBarMobile"; then
      rc=1
    fi
  fi

  return "$rc"
}

# Guard: any semantic Codex / Claude cost-usage parser change must bump
# parserLogicVersion so persisted attribution caches are invalidated.
audit_parser_version() {
  if [[ "${ALLOW_PARSER_CHANGE:-0}" == "1" ]]; then
    echo "parser-version audit: ALLOW_PARSER_CHANGE=1 → skipping"
    return 0
  fi

  local base="${PARSER_LINT_BASE:-origin/mobile-dev}"
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
    echo "       In CI, ensure your checkout fetches origin/mobile-dev (for example fetch-depth: 0)." >&2
    echo "       Locally, run: git fetch origin mobile-dev" >&2
    return 1
  fi

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

  if git -C "$ROOT_DIR" diff "$base"...HEAD -- "$pricing_file" \
       | grep -E '^[+-][[:space:]]*static[[:space:]]+let[[:space:]]+parserLogicVersion' >/dev/null; then
    echo "parser-version audit: parser code changed AND parserLogicVersion bumped — OK"
    return 0
  fi

  echo "ERROR: parser code changed since $base but parserLogicVersion was not bumped." >&2
  echo "       Files changed:" >&2
  printf '         - %s\n' "${changed_parser[@]}" >&2
  echo "       Bump 'static let parserLogicVersion = N' in $pricing_file." >&2
  return 1
}

ensure_oxlint() {
  "${ROOT_DIR}/Scripts/install_lint_tools.sh" oxlint
}

ensure_oxfmt() {
  "${ROOT_DIR}/Scripts/install_lint_tools.sh" oxfmt
}

ensure_typescript() {
  "${ROOT_DIR}/Scripts/install_lint_tools.sh" typescript
}

check_codex_parser_hash() {
  "${ROOT_DIR}/Scripts/regenerate-codex-parser-hash.sh" --check
}

check_provider_manifests() {
  "${ROOT_DIR}/Scripts/regenerate-provider-manifests.sh" --check
}

check_plugin_javascript() {
  "${ROOT_DIR}/Scripts/regenerate-plugin-js.sh" --check
}

check_package_product_paths() {
  "${ROOT_DIR}/Scripts/test_package_product_paths.sh"
}

check_package_strip() {
  "${ROOT_DIR}/Scripts/test_package_strip.sh"
}

check_package_signing() {
  "${ROOT_DIR}/Scripts/test_package_signing.sh"
}

check_package_info_plist() {
  "${ROOT_DIR}/Scripts/test_package_info_plist.sh"
}

check_release_dsym_paths() {
  "${ROOT_DIR}/Scripts/test_release_dsym_paths.sh"
}

check_release_checksum() {
  "${ROOT_DIR}/Scripts/test_release_checksum.sh"
}

check_sparkle_signing_paths() {
  "${ROOT_DIR}/Scripts/test_sparkle_signing_paths.sh"
}

check_release_secret_loading() {
  "${ROOT_DIR}/Scripts/test_load_release_secrets.sh"
}

check_release_cli_workflow() {
  "${ROOT_DIR}/Scripts/test_release_cli_workflow.sh"
}

check_pr_review_gate() {
  "${ROOT_DIR}/Scripts/test_pr_review_gate.sh"
}

check_swift_test_sharding() {
  "${ROOT_DIR}/Scripts/test_swift_test_sharding.sh"
}

check_ci_path_gate() {
  "${ROOT_DIR}/Scripts/test_ci_path_gate.sh"
}

check_ci_upstream_check_gate() {
  "${ROOT_DIR}/Scripts/test_ci_upstream_check_gate.sh"
}

check_ci_policy() {
  "${ROOT_DIR}/Scripts/check_ci_policy.sh"
  "${ROOT_DIR}/Scripts/test_ci_policy.sh"
}

check_homebrew_tap_wait() {
  "${ROOT_DIR}/Scripts/test_wait_for_homebrew_tap_update.sh"
}

check_repository_size() {
  "${ROOT_DIR}/Scripts/check_repository_size.sh"
  "${ROOT_DIR}/Scripts/test_repository_size.sh"
}

check_shell_scripts() {
  local count=0
  local script
  for script in "${ROOT_DIR}"/Scripts/*.sh "${ROOT_DIR}"/Scripts/mac-release; do
    [[ -f "$script" ]] || continue
    bash -n "$script"
    count=$((count + 1))
  done
  printf 'shell scripts OK: %d files\n' "$count"
}

check_app_locales() {
  node "${ROOT_DIR}/Scripts/check-app-locales.mjs" --test
  node "${ROOT_DIR}/Scripts/check-app-locales.mjs"
}

check_site_locales() {
  node "${ROOT_DIR}/Scripts/check-site-locales.mjs"
  node --check "${ROOT_DIR}/docs/site.js"
}

check_documentation_links() {
  node "${ROOT_DIR}/Scripts/check-documentation-links.mjs"
}

check_llms_index() {
  node "${ROOT_DIR}/Scripts/generate-llms.mjs" --check
}

run_portable_checks() {
  check_codex_parser_hash
  check_provider_manifests
  check_plugin_javascript
  check_package_product_paths
  check_package_strip
  check_package_signing
  check_package_info_plist
  check_release_dsym_paths
  check_release_checksum
  check_sparkle_signing_paths
  check_release_secret_loading
  check_release_cli_workflow
  check_pr_review_gate
  check_swift_test_sharding
  check_ci_path_gate
  check_ci_upstream_check_gate
  check_ci_policy
  check_homebrew_tap_wait
  check_repository_size
  check_shell_scripts
  check_documentation_links
  check_llms_index
  check_site_locales
}

run_swiftformat_lint() {
  ensure_swiftformat
  "${BIN_DIR}/swiftformat" Sources Tests --lint
}

run_swiftlint() {
  ensure_swiftlint
  "${BIN_DIR}/swiftlint" --strict
}

collect_javascript_files() {
  JAVASCRIPT_FILES=("${ROOT_DIR}/docs/site.js")
  local file
  for file in "${ROOT_DIR}"/Scripts/*.mjs "${ROOT_DIR}"/Sources/CodexBarCore/Resources/Plugins/*.js \
    "${ROOT_DIR}"/Sources/CodexBarCore/Resources/Plugins/*.ts
  do
    [[ -f "$file" ]] || continue
    case "$(basename "$file")" in
      sucrase-*.min.js) continue ;;
    esac
    JAVASCRIPT_FILES+=("$file")
  done
}

run_oxfmt_check() {
  ensure_oxfmt
  collect_javascript_files
  "${BIN_DIR}/oxfmt" --config "${ROOT_DIR}/.oxfmtrc.json" --check "${JAVASCRIPT_FILES[@]}"
}

run_oxlint() {
  ensure_oxlint
  collect_javascript_files
  "${BIN_DIR}/oxlint" \
    --config "${ROOT_DIR}/.oxlintrc.json" \
    --deny-warnings \
    --report-unused-disable-directives \
    "${JAVASCRIPT_FILES[@]}"
}

run_typescript_check() {
  ensure_typescript
  node "${ROOT_DIR}/.build/lint-tools/typescript/bin/tsc" --project "${ROOT_DIR}/tsconfig.plugins.json"
}

run_javascript_checks() {
  run_oxfmt_check
  run_oxlint
  run_typescript_check
}

cmd="${1:-lint}"

case "$cmd" in
  lint)
    check_app_locales
    run_portable_checks
    run_javascript_checks
    run_swiftformat_lint
    run_swiftlint
    audit_xcstrings
    audit_parser_version
    ;;
  lint-linux)
    run_portable_checks
    run_javascript_checks
    run_swiftlint
    audit_parser_version
    ;;
  lint-macos)
    check_app_locales
    run_javascript_checks
    run_swiftformat_lint
    audit_xcstrings
    ;;
  format)
    ensure_swiftformat
    "${BIN_DIR}/swiftformat" Sources Tests
    ensure_oxfmt
    collect_javascript_files
    "${BIN_DIR}/oxfmt" --config "${ROOT_DIR}/.oxfmtrc.json" --write "${JAVASCRIPT_FILES[@]}"
    "${ROOT_DIR}/Scripts/regenerate-plugin-js.sh" --write
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
    printf 'Usage: %s [lint|lint-linux|lint-macos|format|audit-i18n|audit-parser-version|audit-parser-hash]\n' "$(basename "$0")" >&2
    exit 2
    ;;
esac
