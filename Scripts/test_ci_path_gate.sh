#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

assert_gate() {
  local expected_macos="$1"
  local expected_linux="$2"
  local name="$3"
  local paths_file="${tmp_dir}/${name}.paths"
  local output_file="${tmp_dir}/${name}.output"
  shift 3

  printf '%s\n' "$@" > "$paths_file"
  GITHUB_OUTPUT="$output_file" "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$paths_file" >/dev/null
  local actual
  actual="$(sed -n 's/^macos-tests=//p' "$output_file")"
  if [[ "$actual" != "$expected_macos" ]]; then
    printf '%s: expected macos-tests=%s, got %s\n' "$name" "$expected_macos" "${actual:-<empty>}" >&2
    exit 1
  fi

  local reason
  reason="$(sed -n 's/^macos-tests-reason=//p' "$output_file")"
  if [[ -z "$reason" ]]; then
    printf '%s: expected macos-tests-reason output\n' "$name" >&2
    exit 1
  fi

  local path_count
  path_count="$(sed -n 's/^changed-path-count=//p' "$output_file")"
  if ! [[ "$path_count" =~ ^[0-9]+$ ]]; then
    printf '%s: expected numeric changed-path-count output, got %s\n' \
      "$name" "${path_count:-<empty>}" >&2
    exit 1
  fi

  local actual_linux
  actual_linux="$(sed -n 's/^linux-tests=//p' "$output_file")"
  if [[ "$actual_linux" != "$expected_linux" ]]; then
    printf '%s: expected linux-tests=%s, got %s\n' \
      "$name" "$expected_linux" "${actual_linux:-<empty>}" >&2
    exit 1
  fi

  local linux_reason
  linux_reason="$(sed -n 's/^linux-tests-reason=//p' "$output_file")"
  if [[ -z "$linux_reason" ]]; then
    printf '%s: expected linux-tests-reason output\n' "$name" >&2
    exit 1
  fi
}

assert_gate false false docs-only $'M\tdocs/providers.md' $'M\tREADME.md'
assert_gate false false configuration-doc $'M\tdocs/configuration.md'
assert_gate false false agents-contract $'M\tAGENTS.md'
assert_gate true false mac-source $'M\tSources/CodexBar/App.swift'
assert_gate true true portable-source $'M\tSources/CodexBarCore/UsageFormatter.swift'
assert_gate true true cli-source $'M\tSources/CodexBarCLI/CLIEntry.swift'
assert_gate false true linux-test $'M\tTestsLinux/PlatformGatingTests.swift'
assert_gate true false shared-sync $'M\tShared/iCloud/CloudSyncManager.swift'
assert_gate false false ios-only $'M\tCodexBarMobile/CodexBarMobile/ContentView.swift'
assert_gate false false appcast-only $'M\tappcast.xml'
assert_gate false false workflow-only $'M\t.github/workflows/ci.yml'
assert_gate true true unknown-root-path $'M\tNewBuildContract.json'
assert_gate false false docs-site $'M\tdocs/index.html' $'M\tdocs/site.css' $'M\tdocs/site.js' \
  $'M\tdocs/site-locales.mjs' $'M\tdocs/social.html' $'M\tdocs/social.png' \
  $'M\tdocs/CNAME' $'M\tdocs/.nojekyll' $'M\tdocs/llms.txt'
assert_gate false false docs-site-assets $'M\tdocs/icon.png' $'M\tdocs/logos/provider-logo.svg'
assert_gate true true package-manifest $'M\tPackage.swift'
assert_gate true true empty
assert_gate true false source-to-docs $'R100\tSources/CodexBar/App.swift\tdocs/App.md'
assert_gate true false docs-to-source $'R100\tdocs/App.md\tSources/CodexBar/App.swift'
assert_gate false false docs-to-site $'R100\tdocs/old.md\tdocs/site.css'

force_paths="${tmp_dir}/force.paths"
force_output="${tmp_dir}/force.output"
printf '%s\n' $'M\tREADME.md' > "$force_paths"
CI_FORCE_FULL=true GITHUB_OUTPUT="$force_output" \
  "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$force_paths" >/dev/null
grep -Fxq 'macos-tests=true' "$force_output"
grep -Fxq 'linux-tests=true' "$force_output"

trusted_paths="${tmp_dir}/trusted.paths"
trusted_output="${tmp_dir}/trusted.output"
printf '%s\n' $'M\tSources/CodexBarCore/UsageFormatter.swift' > "$trusted_paths"
CI_TRUSTED_UPSTREAM_SYNC=true GITHUB_OUTPUT="$trusted_output" \
  "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$trusted_paths" >/dev/null
grep -Fxq 'macos-tests=false' "$trusted_output"
grep -Fxq 'linux-tests=false' "$trusted_output"

assert_gate_fails() {
  local name="$1"
  local paths_file="${tmp_dir}/${name}.paths"
  local output_file="${tmp_dir}/${name}.output"
  shift

  printf '%s\n' "$@" > "$paths_file"
  if GITHUB_OUTPUT="$output_file" "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$paths_file" >/dev/null 2>&1; then
    printf '%s: malformed gate input unexpectedly succeeded\n' "$name" >&2
    exit 1
  fi
  if [[ -s "$output_file" ]]; then
    printf '%s: malformed gate input emitted an output\n' "$name" >&2
    exit 1
  fi
}

assert_gate_fails missing-rename-target $'R100\tREADME.md'
assert_gate_fails extra-modified-path $'M\tREADME.md\tdocs/configuration.md'
assert_gate_fails missing-rename-score $'R\tREADME.md\tdocs/README.md'
assert_gate_fails invalid-rename-score $'Rfoo\tREADME.md\tdocs/README.md'
assert_gate_fails out-of-range-rename-score $'R101\tREADME.md\tdocs/README.md'

unterminated_paths="${tmp_dir}/unterminated.paths"
unterminated_output="${tmp_dir}/unterminated.output"
printf '%s' $'M\tREADME.md\tdocs/configuration.md' > "$unterminated_paths"
if GITHUB_OUTPUT="$unterminated_output" \
  "${ROOT_DIR}/Scripts/ci_macos_test_gate.sh" "$unterminated_paths" >/dev/null 2>&1
then
  printf 'unterminated malformed gate input unexpectedly succeeded\n' >&2
  exit 1
fi
if [[ -s "$unterminated_output" ]]; then
  printf 'unterminated malformed gate input emitted an output\n' >&2
  exit 1
fi

verify="${ROOT_DIR}/Scripts/ci_verify_test_jobs.sh"
"$verify" success success true success true success success >/dev/null
"$verify" success success false skipped false skipped skipped >/dev/null
"$verify" success success true success false skipped skipped >/dev/null

assert_verify_fails() {
  if "$verify" "$@" >/dev/null 2>&1; then
    printf 'unexpected aggregate success: %s\n' "$*" >&2
    exit 1
  fi
}

assert_verify_fails success success true skipped true success success
assert_verify_fails success success false success false skipped skipped
assert_verify_fails success success "" skipped false skipped skipped
assert_verify_fails failure success true success true success success
assert_verify_fails success failure true success true success success
assert_verify_fails success success true success true skipped success
assert_verify_fails success success true success true success skipped
assert_verify_fails success success true success true failure success
assert_verify_fails success success true success true success cancelled
assert_verify_fails success success false skipped false success skipped
assert_verify_fails success success false skipped false skipped success
assert_verify_fails success success true success true success

workflow="${ROOT_DIR}/.github/workflows/ci.yml"
grep -Fq '      - build-linux-cli' "$workflow"
grep -Fq '      - build-linux-musl-cli' "$workflow"
[[ "$(grep -Fc "if: \${{ needs.changes.outputs.linux-tests == 'true' }}" "$workflow")" -eq 2 ]]
grep -Fq '            "${{ needs.build-linux-cli.result }}" \' "$workflow"
grep -Fq '            "${{ needs.build-linux-musl-cli.result }}"' "$workflow"

printf 'CI final path gate tests passed.\n'
