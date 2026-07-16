#!/usr/bin/env bash

set -euo pipefail

changed_paths_file="${1:-}"

if [[ -z "$changed_paths_file" || ! -f "$changed_paths_file" ]]; then
  printf 'Usage: %s <changed-paths-file>\n' "$(basename "$0")" >&2
  exit 2
fi

macos_tests=false
macos_tests_reason=""
linux_tests=false
linux_tests_reason=""
path_count=0

require_macos_tests() {
  local path="$1"
  local reason="$2"

  macos_tests=true
  if [[ -z "$macos_tests_reason" ]]; then
    macos_tests_reason="${path}: ${reason}"
  fi
}

require_linux_tests() {
  local path="$1"
  local reason="$2"

  linux_tests=true
  if [[ -z "$linux_tests_reason" ]]; then
    linux_tests_reason="${path}: ${reason}"
  fi
}

classify_path() {
  local path="$1"
  [[ -z "$path" ]] && return

  path_count=$((path_count + 1))

  case "$path" in
    Package.swift|Package.resolved|Sources/CSQLite3/*|Sources/CodexBarCore/*|Sources/CodexBarCLI/*)
      require_macos_tests "$path" "changes Swift package code shared by macOS"
      require_linux_tests "$path" "changes the portable core or CLI"
      ;;
    Sources/*|Shared/*|Tests/*|Scripts/test.sh|Scripts/ci_swift_test_by_suite.py)
      require_macos_tests "$path" "changes macOS runtime or test behavior"
      ;;
    TestsLinux/*)
      require_linux_tests "$path" "changes Linux-only test behavior"
      ;;
    CodexBarMobile/*|.agents/*|.github/*|docs/*|Scripts/*|*.md|appcast.xml|version.env|.mac-release.env|.gitignore|.swiftformat|.swiftlint.yml)
      # PRs already run portable lint and repository policy checks. iOS-only,
      # release metadata, docs, workflow and other non-runtime paths do not
      # justify cold macOS or dual-architecture Linux builds after merge.
      ;;
    *)
      require_macos_tests "$path" "path is not classified as non-runtime"
      require_linux_tests "$path" "path is not classified as platform-specific"
      ;;
  esac
}

invalid_row=false
while IFS=$'\t' read -r status first_path second_path extra_path \
  || [[ -n "${status:-}${first_path:-}${second_path:-}${extra_path:-}" ]]
do
  [[ -z "${status}${first_path:-}${second_path:-}${extra_path:-}" ]] && continue

  case "$status" in
    R*|C*)
      if ! [[ "$status" =~ ^[RC][0-9]{1,3}$ ]] \
        || ((10#${status:1} > 100)) \
        || [[ -z "${first_path:-}" || -z "${second_path:-}" || -n "${extra_path:-}" ]]
      then
        invalid_row=true
        break
      fi
      classify_path "$first_path"
      classify_path "$second_path"
      ;;
    A|D|M|T|U|X|B)
      if [[ -z "${first_path:-}" || -n "${second_path:-}" || -n "${extra_path:-}" ]]; then
        invalid_row=true
        break
      fi
      classify_path "$first_path"
      ;;
    *)
      invalid_row=true
      break
      ;;
  esac
done < "$changed_paths_file"

if [[ "$invalid_row" == true ]]; then
  printf 'Invalid git name-status row; refusing to skip macOS tests.\n' >&2
  exit 2
fi

if [[ "${CI_FORCE_FULL:-false}" == true ]]; then
  require_macos_tests '<manual run>' 'full final CI was requested explicitly'
  require_linux_tests '<manual run>' 'full final CI was requested explicitly'
elif [[ "${CI_TRUSTED_UPSTREAM_SYNC:-false}" == true ]]; then
  macos_tests=false
  linux_tests=false
  macos_tests_reason="trusted upstream-sync release; fork-specific gates were completed before merge"
  linux_tests_reason="trusted upstream-sync release; upstream portable CLI checks are reused"
elif [[ "$path_count" -eq 0 ]]; then
  require_macos_tests '<empty diff>' 'no changed paths were reported'
  require_linux_tests '<empty diff>' 'no changed paths were reported'
fi

[[ -n "$macos_tests_reason" ]] || macos_tests_reason="no macOS runtime or test paths changed"
[[ -n "$linux_tests_reason" ]] || linux_tests_reason="no portable core, CLI, or Linux test paths changed"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'macos-tests=%s\n' "$macos_tests" >> "$GITHUB_OUTPUT"
  printf 'macos-tests-reason=%s\n' "$macos_tests_reason" >> "$GITHUB_OUTPUT"
  printf 'linux-tests=%s\n' "$linux_tests" >> "$GITHUB_OUTPUT"
  printf 'linux-tests-reason=%s\n' "$linux_tests_reason" >> "$GITHUB_OUTPUT"
  printf 'changed-path-count=%s\n' "$path_count" >> "$GITHUB_OUTPUT"
fi

if [[ "$macos_tests" == true ]]; then
  printf 'macOS Swift tests required for this change set: %s.\n' "$macos_tests_reason"
else
  printf 'Skipping macOS Swift tests: %s.\n' "$macos_tests_reason"
fi

if [[ "$linux_tests" == true ]]; then
  printf 'Linux CLI tests required for this change set: %s.\n' "$linux_tests_reason"
else
  printf 'Skipping Linux CLI tests: %s.\n' "$linux_tests_reason"
fi
