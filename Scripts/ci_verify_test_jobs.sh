#!/usr/bin/env bash

set -euo pipefail

lint_result="${1:-}"
changes_result="${2:-}"
macos_tests_required="${3:-}"
macos_test_result="${4:-}"
linux_tests_required="${5:-}"
linux_glibc_result="${6-<missing>}"
linux_musl_result="${7-<missing>}"

if [[ "$lint_result" != "success" ]]; then
  printf 'lint job finished with %s\n' "${lint_result:-<empty>}" >&2
  exit 1
fi

if [[ "$changes_result" != "success" ]]; then
  printf 'changes job finished with %s\n' "${changes_result:-<empty>}" >&2
  exit 1
fi

case "${macos_tests_required}:${macos_test_result}" in
  true:success)
    printf 'macOS Swift test shards passed.\n'
    ;;
  false:skipped)
    printf 'macOS Swift tests were not required.\n'
    ;;
  *)
    printf 'macOS test gate/result mismatch: required=%s result=%s\n' \
      "${macos_tests_required:-<empty>}" "${macos_test_result:-<empty>}" >&2
    exit 1
    ;;
esac

case "${linux_tests_required}:${linux_glibc_result}:${linux_musl_result}" in
  true:success:success)
    printf 'Linux CLI matrix passed.\n'
    ;;
  false:skipped:skipped)
    printf 'Linux CLI matrix was not required.\n'
    ;;
  *)
    printf 'Linux test gate/result mismatch: required=%s glibc=%s musl=%s\n' \
      "${linux_tests_required:-<empty>}" "${linux_glibc_result:-<empty>}" \
      "${linux_musl_result:-<empty>}" >&2
    exit 1
    ;;
esac

printf 'Final CI aggregate gate passed.\n'
