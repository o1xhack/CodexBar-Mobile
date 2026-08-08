#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/sparkle_helpers.sh"

TAG=${1:-$(git describe --tags --abbrev=0)}
ARTIFACT_PREFIX="CodexBar-${TAG#v}"

check_assets "$TAG" "$ARTIFACT_PREFIX"

VERSION=${TAG#v}
assets=$(gh release view "$TAG" --repo o1xhack/CodexBar-Mobile --json assets --jq '.assets[].name')
missing=0
for target in \
  macos-arm64 \
  macos-x86_64 \
  linux-aarch64 \
  linux-x86_64
do
  asset="CodexBarCLI-v${VERSION}-${target}.tar.gz"
  checksum="${asset}.sha256"
  if ! printf "%s\n" "$assets" | grep -Fxq "$asset"; then
    echo "ERROR: CLI asset missing on release $TAG: $asset" >&2
    missing=1
  fi
  if ! printf "%s\n" "$assets" | grep -Fxq "$checksum"; then
    echo "ERROR: CLI checksum missing on release $TAG: $checksum" >&2
    missing=1
  fi
done

if [[ "$missing" == "1" ]]; then
  exit 1
fi

echo "Release $TAG has all CodexBarCLI tarballs and checksums."
