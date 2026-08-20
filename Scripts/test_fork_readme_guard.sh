#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexbar-fork-readme.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$ROOT_DIR/README.md" "$TMP_DIR/README.md"
CODEXBAR_FORK_README_PATH="$TMP_DIR/README.md" "$ROOT_DIR/Scripts/check_fork_readme.sh" >/dev/null

printf '\nupstream overwrite probe\n' >> "$TMP_DIR/README.md"
if CODEXBAR_FORK_README_PATH="$TMP_DIR/README.md" \
    "$ROOT_DIR/Scripts/check_fork_readme.sh" >/dev/null 2>&1; then
  echo "fork README guard accepted changed content" >&2
  exit 1
fi

echo "fork README guard tests passed"
