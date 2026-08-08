#!/usr/bin/env bash
#
# sparkle_helpers.sh — in-repo replacement for the external
# `~/Projects/agent-scripts/release/sparkle_lib.sh` that upstream commit
# 6ac9d0c7 (2025-11-25) introduced as a dependency. Our fork never had
# access to steipete's private library; this file gives us self-hosted,
# repeatable release orchestration.
#
# Source this from any release script:
#   source "$ROOT/Scripts/sparkle_helpers.sh"
#
# Side effect: prepends the SPM-downloaded Sparkle binaries (generate_appcast,
# sign_update, BinaryDelta) to PATH so callers don't have to.

# Idempotent — safe to source multiple times.
if [[ -n "${CODEXBAR_SPARKLE_HELPERS_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi

_SPARKLE_HELPERS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
_SPARKLE_BIN_DIR="$_SPARKLE_HELPERS_ROOT/.build/artifacts/sparkle/Sparkle/bin"
if [[ -d "$_SPARKLE_BIN_DIR" ]]; then
  case ":$PATH:" in
    *":$_SPARKLE_BIN_DIR:"*) ;;
    *) export PATH="$_SPARKLE_BIN_DIR:$PATH" ;;
  esac
fi

err() { echo "ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# require_clean_worktree
#   Aborts if there are uncommitted changes in the CodexBar working tree.
# ---------------------------------------------------------------------------
require_clean_worktree() {
  if [[ -n "$(git -C "$_SPARKLE_HELPERS_ROOT" status --porcelain)" ]]; then
    err "Working tree not clean — commit or stash first."
  fi
}

# ---------------------------------------------------------------------------
# ensure_changelog_finalized <version>
#   Delegates to Scripts/validate_changelog.sh: top CHANGELOG section must
#   match the version exactly and not be labeled Unreleased.
# ---------------------------------------------------------------------------
ensure_changelog_finalized() {
  local version=$1
  "$_SPARKLE_HELPERS_ROOT/Scripts/validate_changelog.sh" "$version"
}

# ---------------------------------------------------------------------------
# ensure_appcast_monotonic <appcast> <version> <build>
#   Refuses to proceed if any existing appcast <item> already has a
#   shortVersionString >= <version> or sparkle:version >= <build>. Uses
#   dotted-numeric comparison (CFBundleVersion friendly: 55.2.1.2.0 is
#   ordered after 55.1.2.0 but before 56.0).
# ---------------------------------------------------------------------------
ensure_appcast_monotonic() {
  local appcast=$1 version=$2 build=$3
  [[ -f "$appcast" ]] || err "appcast not found: $appcast"

  python3 - "$appcast" "$version" "$build" <<'PY'
import sys
import xml.etree.ElementTree as ET

appcast, new_short, new_build = sys.argv[1], sys.argv[2], sys.argv[3]
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}

def version_tuple(s):
    try:
        return tuple(int(p) for p in s.strip().split("."))
    except ValueError:
        return None

new_short_t = version_tuple(new_short)
new_build_t = version_tuple(new_build)
if new_short_t is None:
    sys.exit(f"ERROR: new MARKETING_VERSION '{new_short}' is not a dotted-numeric string")
if new_build_t is None:
    sys.exit(f"ERROR: new BUILD_NUMBER '{new_build}' is not a dotted-numeric string")

tree = ET.parse(appcast)
for item in tree.getroot().findall("./channel/item"):
    s = item.findtext("sparkle:shortVersionString", default="", namespaces=ns)
    b = item.findtext("sparkle:version", default="", namespaces=ns)
    st = version_tuple(s) if s else None
    bt = version_tuple(b) if b else None
    if st is not None and st >= new_short_t:
        sys.exit(
            f"ERROR: appcast already has shortVersionString={s} >= new {new_short}. "
            "Bump MARKETING_VERSION or remove the stale entry before releasing."
        )
    if bt is not None and bt >= new_build_t:
        sys.exit(
            f"ERROR: appcast already has sparkle:version={b} >= new {new_build}. "
            "Bump BUILD_NUMBER (or its fork-patch slot) before releasing."
        )
print(f"appcast monotonic OK: new {new_short} / {new_build} is greater than all existing entries.")
PY
}

# ---------------------------------------------------------------------------
# clean_key <keyfile>
#   Writes a sanitized (single base64 line, no comments/blanks) copy of the
#   Sparkle ed25519 private key to a 0600-mode tempfile and prints the
#   tempfile path on stdout. Caller is responsible for trap-cleaning it.
# ---------------------------------------------------------------------------
clean_key() {
  local src=$1 key_lines tmp
  [[ -f "$src" ]] || err "Sparkle key file not found: $src"
  key_lines=$(grep -v '^[[:space:]]*#' "$src" | sed '/^[[:space:]]*$/d')
  if [[ $(printf "%s\n" "$key_lines" | wc -l) -ne 1 ]]; then
    err "Sparkle key file must contain exactly one base64 line (no comments/blank lines)."
  fi
  tmp=$(mktemp)
  printf "%s" "$key_lines" > "$tmp"
  chmod 600 "$tmp"
  echo "$tmp"
}

# ---------------------------------------------------------------------------
# probe_sparkle_key <cleaned-keyfile>
#   Quick liveness test: ask sign_update to sign a dummy payload with the
#   key. Non-zero exit means the key is malformed or sign_update is unhappy.
# ---------------------------------------------------------------------------
probe_sparkle_key() {
  local key=$1 tmp
  [[ -f "$key" ]] || err "probe_sparkle_key: key file not found: $key"
  command -v sign_update >/dev/null || err "sign_update not on PATH (did SPM install Sparkle tools?)"
  tmp=$(mktemp /tmp/sparkle-probe.XXXXXX)
  printf "codexbar-release-probe" > "$tmp"
  if ! sign_update "$tmp" --ed-key-file "$key" >/dev/null 2>&1; then
    rm -f "$tmp"
    err "sign_update rejected the Sparkle key at $key"
  fi
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# clear_sparkle_caches <bundle_id>
#   Wipes per-app and Sparkle framework caches so Check-for-Updates tests
#   don't see stale appcast/download state.
# ---------------------------------------------------------------------------
clear_sparkle_caches() {
  local bundle=$1
  rm -rf \
    "$HOME/Library/Caches/$bundle" \
    "$HOME/Library/Caches/org.sparkle-project.Sparkle" \
    2>/dev/null || true
}

# ---------------------------------------------------------------------------
# extract_notes_from_changelog <version> <outfile>
#   Pulls the `## <version> …` section out of CHANGELOG.md and writes the
#   body (without the heading itself) to <outfile>. Used as --notes-file for
#   `gh release create`.
# ---------------------------------------------------------------------------
extract_notes_from_changelog() {
  local version=$1 outfile=$2
  local changelog="$_SPARKLE_HELPERS_ROOT/CHANGELOG.md"
  [[ -f "$changelog" ]] || err "CHANGELOG.md not found at $changelog"
  awk -v version="$version" '
    BEGIN { in_section = 0 }
    /^## / {
      if (in_section) exit
      if ($0 ~ "^## " version "($| )") { in_section = 1; next }
    }
    in_section { print }
  ' "$changelog" > "$outfile"
  if [[ ! -s "$outfile" ]]; then
    err "No CHANGELOG.md section found for version $version"
  fi
}

# ---------------------------------------------------------------------------
# verify_appcast_entry <appcast> <version> <cleaned-keyfile>
#   Downloads the enclosure, checks content length, and verifies the
#   ed25519 signature with sign_update. Delegates to verify_appcast.sh
#   which already implements this (and needs SPARKLE_PRIVATE_KEY_FILE set).
# ---------------------------------------------------------------------------
verify_appcast_entry() {
  local appcast=$1 version=$2 key=$3
  SPARKLE_PRIVATE_KEY_FILE="$key" \
    "$_SPARKLE_HELPERS_ROOT/Scripts/verify_appcast.sh" "$version"
}

# ---------------------------------------------------------------------------
# check_assets <tag> <artifact-basename>
#   Confirms the GitHub release at <tag> has the exact <basename>.zip and
#   <basename>.dSYM.zip assets.
# ---------------------------------------------------------------------------
check_assets() {
  local tag=$1 basename=$2
  local missing=0
  local assets
  # --repo pinned to fork explicitly. Without it, gh inspects local
  # remotes and may pick the upstream remote (steipete/CodexBar)
  # which doesn't have our fork's tags. See feedback_gh_release_repo_pin.md.
  assets=$(gh release view "$tag" --repo o1xhack/CodexBar-Mobile --json assets -q '.assets[].name' 2>&1) || {
    err "gh release view failed for $tag: $assets"
  }
  if ! printf "%s\n" "$assets" | grep -Fxq "${basename}.zip"; then
    echo "MISSING: ${basename}.zip" >&2
    missing=1
  fi
  if ! printf "%s\n" "$assets" | grep -Fxq "${basename}.dSYM.zip"; then
    echo "MISSING: ${basename}.dSYM.zip" >&2
    missing=1
  fi
  [[ "$missing" -eq 0 ]] || err "GitHub release $tag is missing expected assets."
  echo "Release $tag assets OK (${basename}.zip + ${basename}.dSYM.zip present)."
}

export CODEXBAR_SPARKLE_HELPERS_LOADED=1
