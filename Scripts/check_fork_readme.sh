#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
README_PATH=${CODEXBAR_FORK_README_PATH:-"$ROOT_DIR/README.md"}
EXPECTED_SHA256="3f32de3d292247fb2af3edc3cdc5fb96126fd8145165fe59550f30e19b2aecca"

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "ERROR: shasum or sha256sum is required for the fork README guard." >&2
    return 1
  fi
}

if [[ ! -f "$README_PATH" ]]; then
  echo "ERROR: fork-owned README is missing: $README_PATH" >&2
  exit 1
fi

actual_sha256=$(sha256_file "$README_PATH")
if [[ "$actual_sha256" != "$EXPECTED_SHA256" ]]; then
  echo "ERROR: README.md differs from the reviewed fork-owned version." >&2
  echo "       During an upstream merge, keep README.md exactly from the fork/mobile-dev side." >&2
  echo "       Do not update EXPECTED_SHA256 merely to accept the upstream README wholesale." >&2
  echo "       After separately auditing upstream facts, review any intentional fork README edit and this hash together." >&2
  exit 1
fi

echo "fork README guard passed"
