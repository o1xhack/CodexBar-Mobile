#!/usr/bin/env bash
set -euo pipefail

# release.sh — two-phase Sparkle release orchestration.
#
# Phase 1 (default): build + sign + notarize + create DRAFT GitHub release
#                    with uploaded assets, then stop.
#     Usage: ./Scripts/release.sh
#
# Phase 2 (--finalize): publish the existing draft, generate + sign the
#                       appcast entry, commit + push appcast.xml, verify.
#     Usage: ./Scripts/release.sh --finalize
#
# The draft gate between phases is the human-review checkpoint. Once you
# finalize, the release is live and Sparkle clients will start seeing it
# on their next check-for-updates cycle.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/version.env"
source "$ROOT/Scripts/load-release-secrets.sh"
source "$ROOT/Scripts/release_dsym_paths.sh"
source "$ROOT/Scripts/sparkle_helpers.sh"

APPCAST="$ROOT/appcast.xml"
APP_NAME="CodexBar"
RELEASE_ASSET_BASENAME="${APP_NAME}-${MARKETING_VERSION}-mobile.${MOBILE_VERSION}"
ARTIFACT_PREFIX="CodexBar-"
BUNDLE_ID="com.o1xhack.codexbar"
RELEASE_BRANCH="mobile-dev"
export CODEXBAR_RELEASE_BRANCH="$RELEASE_BRANCH"
FEED_URL="https://raw.githubusercontent.com/o1xhack/CodexBar-Mobile/${RELEASE_BRANCH}/appcast.xml"
TAG="v${MARKETING_VERSION}-mobile.${MOBILE_VERSION}"
RELEASE_TITLE="${APP_NAME} ${MARKETING_VERSION} Mobile ${MOBILE_VERSION}"
ARTIFACT_INPUTS=(
  Package.swift
  Package.resolved
  Sources
  Shared
  WidgetExtension
  Icon.icon
  Icon.icns
  Scripts/package_app.sh
  Scripts/package_product_paths.sh
  Scripts/release_dsym_paths.sh
  Scripts/sign-and-notarize.sh
  Scripts/sparkle_signing_paths.sh
  version.env
)

artifact_git_commit() {
  local zip=$1
  unzip -p "$zip" CodexBar.app/Contents/Info.plist 2>/dev/null \
    | plutil -extract CodexGitCommit raw -o - - 2>/dev/null
}

artifact_matches_current_inputs() {
  local zip=$1 embedded_commit
  embedded_commit=$(artifact_git_commit "$zip") || return 1
  git rev-parse --verify "${embedded_commit}^{commit}" >/dev/null 2>&1 || return 1
  git merge-base --is-ancestor "$embedded_commit" HEAD || return 1
  git diff --quiet "$embedded_commit"..HEAD -- "${ARTIFACT_INPUTS[@]}"
}

artifact_pair_matches() {
  local zip=$1 dsym_zip=$2 temp_dir status=0
  temp_dir=$(mktemp -d /tmp/codexbar-artifact-pair.XXXXXX)

  unzip -q "$zip" "CodexBar.app/Contents/MacOS/CodexBar" -d "$temp_dir/app" || status=$?
  if [[ "$status" -eq 0 ]]; then
    unzip -q "$dsym_zip" "CodexBar.dSYM/Contents/Resources/DWARF/CodexBar" -d "$temp_dir/dsym" || status=$?
  fi
  if [[ "$status" -eq 0 ]]; then
    codexbar_verify_dsym_matches_binary \
      "$temp_dir/app/CodexBar.app/Contents/MacOS/CodexBar" \
      "$temp_dir/dsym/CodexBar.dSYM/Contents/Resources/DWARF/CodexBar" \
      arm64 x86_64 || status=$?
  fi

  rm -rf "$temp_dir"
  return "$status"
}

require_remote_asset_matches_local() {
  local local_path=$1 asset_name asset_record remote_size remote_digest local_size local_digest
  asset_name=$(basename "$local_path")
  asset_record=$(gh release view "$TAG" \
    --repo o1xhack/CodexBar-Mobile \
    --json assets \
    --jq ".assets | map(select(.name == \"${asset_name}\")) | if length == 1 then .[0] | [.size, .digest] | @tsv else empty end")
  [[ -n "$asset_record" ]] || err "Draft release must contain exactly one asset named ${asset_name}."

  IFS=$'\t' read -r remote_size remote_digest <<<"$asset_record"
  local_size=$(stat -f%z "$local_path")
  local_digest="sha256:$(shasum -a 256 "$local_path" | awk '{print $1}')"
  [[ "$remote_size" == "$local_size" ]] || \
    err "Remote ${asset_name} size does not match the local release artifact; rerun phase 1."
  [[ "$remote_digest" == "$local_digest" ]] || \
    err "Remote ${asset_name} digest does not match the local release artifact; rerun phase 1."
}

verify_local_appcast_artifact() {
  local zip=$1 key=$2 metadata expected_url signature expected_length actual_length
  metadata=$(mktemp /tmp/codexbar-appcast-metadata.XXXXXX)
  python3 - "$APPCAST" "$MARKETING_VERSION" >"$metadata" <<'PY'
import sys
import xml.etree.ElementTree as ET

appcast, version = sys.argv[1:]
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
root = ET.parse(appcast).getroot()
for item in root.findall("./channel/item"):
    if item.findtext("sparkle:shortVersionString", default="", namespaces=ns) != version:
        continue
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise SystemExit(f"Missing enclosure for {version}")
    values = (
        enclosure.get("url"),
        enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"),
        enclosure.get("length"),
    )
    if not all(values):
        raise SystemExit(f"Missing url/signature/length for {version}")
    print(*values, sep="\n")
    break
else:
    raise SystemExit(f"No appcast entry found for {version}")
PY
  expected_url="https://github.com/o1xhack/CodexBar-Mobile/releases/download/${TAG}/$(basename "$zip")"
  [[ "$(sed -n '1p' "$metadata")" == "$expected_url" ]] || {
    rm -f "$metadata"
    err "Generated appcast enclosure URL does not match the release asset."
  }
  signature=$(sed -n '2p' "$metadata")
  expected_length=$(sed -n '3p' "$metadata")
  actual_length=$(stat -f%z "$zip")
  rm -f "$metadata"
  [[ "$actual_length" == "$expected_length" ]] || \
    err "Generated appcast length does not match the local release artifact."
  sign_update --verify "$zip" "$signature" --ed-key-file "$key" >/dev/null || \
    err "Generated appcast signature does not verify against the local release artifact."
}

require_finalize_checkout() {
  require_clean_worktree

  local current_branch local_head remote_head tag_commit
  current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  [[ "$current_branch" == "$RELEASE_BRANCH" ]] || \
    err "Finalize must run from '$RELEASE_BRANCH' (current: '${current_branch:-detached}')."

  git fetch --quiet origin "$RELEASE_BRANCH"
  local_head=$(git rev-parse HEAD)
  remote_head=$(git rev-parse "origin/${RELEASE_BRANCH}")
  [[ "$local_head" == "$remote_head" ]] || \
    err "Finalize checkout is not identical to origin/${RELEASE_BRANCH}; update it first."

  tag_commit=$(git rev-parse "${TAG}^{commit}" 2>/dev/null) || \
    err "Release tag $TAG is missing. Run phase 1 after PR approval."
  git merge-base --is-ancestor "$tag_commit" HEAD || \
    err "Release tag $TAG is not contained in $RELEASE_BRANCH. Merge/retag before finalize."
}

phase1() {
  require_clean_worktree
  ensure_changelog_finalized "$MARKETING_VERSION"
  ensure_appcast_monotonic "$APPCAST" "$MARKETING_VERSION" "$BUILD_NUMBER"

  "$ROOT/Scripts/lint.sh" lint

  # `swift test` is authoritatively gated by CI on every push to
  # mobile-dev; re-running it here is belt-and-suspenders. Some tests
  # (Claude OAuth delegated-refresh, credential prompts) block on real
  # keychain on a developer Mac and hang indefinitely, unlike the
  # sandboxed CI environment where they run to completion. Opt in via
  # RUN_SWIFT_TEST=1 on machines where it works.
  if [[ "${RUN_SWIFT_TEST:-0}" == "1" ]]; then
    swift test
  else
    echo "Skipping swift test locally (CI gates it on every push; set RUN_SWIFT_TEST=1 to run)."
  fi

  if [[ -f "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" \
     && -f "${ROOT}/${RELEASE_ASSET_BASENAME}.dSYM.zip" ]] \
     && artifact_matches_current_inputs "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" \
     && artifact_pair_matches \
       "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" \
       "${ROOT}/${RELEASE_ASSET_BASENAME}.dSYM.zip"; then
    echo "Reusing existing notarized artifacts (delete them to force a fresh build):"
    ls -lh "${RELEASE_ASSET_BASENAME}.zip" "${RELEASE_ASSET_BASENAME}.dSYM.zip"
  else
    if [[ -f "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" \
       || -f "${ROOT}/${RELEASE_ASSET_BASENAME}.dSYM.zip" ]]; then
      echo "Existing artifacts are stale or incomplete; rebuilding from the current Mac inputs."
      rm -f \
        "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" \
        "${ROOT}/${RELEASE_ASSET_BASENAME}.dSYM.zip"
    fi
    "$ROOT/Scripts/sign-and-notarize.sh"
  fi

  local KEY_FILE NOTES_FILE
  KEY_FILE=$(clean_key "$SPARKLE_PRIVATE_KEY_FILE")
  NOTES_FILE=$(mktemp /tmp/codexbar-notes.XXXXXX)
  # Eager-expand paths into the trap so the cleanup still works after
  # phase1's local scope is gone (set -u would otherwise fail on unbound
  # $KEY_FILE / $NOTES_FILE when the EXIT trap fires post-return).
  trap "rm -f '$KEY_FILE' '$NOTES_FILE'" EXIT

  probe_sparkle_key "$KEY_FILE"
  extract_notes_from_changelog "$MARKETING_VERSION" "$NOTES_FILE"

  git tag -a -f -m "${RELEASE_TITLE}" "$TAG"
  git push -f origin "$TAG"

  # gh allows multiple drafts for the same logical tag (the tag doesn't
  # actually materialize on GitHub until the draft is published), so a
  # previous failed phase 1 can leave an orphan draft that sits next to
  # any fresh one we create. Sweep those out before creating the new draft
  # so the user doesn't see two "CodexBar 0.20.x" entries in the UI.
  orphan_ids=$(gh api "repos/o1xhack/CodexBar-Mobile/releases" \
    --jq ".[] | select(.tag_name == \"$TAG\" and .draft == true) | .id" 2>/dev/null || true)
  for id in $orphan_ids; do
    echo "Cleaning up orphan draft id=$id for $TAG (from a previous phase 1 run)."
    gh api -X DELETE "repos/o1xhack/CodexBar-Mobile/releases/$id" >/dev/null
  done

  # Pin --repo to our fork explicitly. Without it, gh inspects local
  # remotes and may pick the upstream remote (steipete/CodexBar) since
  # both `origin` (o1xhack/CodexBar-Mobile) and `upstream` exist —
  # which fails with "tag exists locally but has not been pushed to
  # steipete/CodexBar". Fork tags only live on origin; hard-code the
  # repo to match the orphan-cleanup gh api call above.
  gh release create "$TAG" \
    "${RELEASE_ASSET_BASENAME}.zip" "${RELEASE_ASSET_BASENAME}.dSYM.zip" \
    --repo o1xhack/CodexBar-Mobile \
    --draft \
    --title "${RELEASE_TITLE}" \
    --notes-file "$NOTES_FILE"

  local draft_url
  draft_url=$(gh release view "$TAG" --repo o1xhack/CodexBar-Mobile --json url -q .url)

  cat <<EOF

============================================================
Phase 1 complete — DRAFT release is staged (not public yet).

  Tag:        $TAG
  Review at:  $draft_url

What to verify in the GitHub UI:
  - Title and release notes render correctly
  - ${RELEASE_ASSET_BASENAME}.zip is present (expect ~10-50 MB)
  - ${RELEASE_ASSET_BASENAME}.dSYM.zip is present
  - Tag matches: $TAG

When ready to publish + push appcast:
  ./Scripts/release.sh --finalize

To abort and clean up:
  gh release delete $TAG --yes
  git push origin :$TAG
============================================================
EOF
}

phase2() {
  require_finalize_checkout

  if [[ ! -f "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" ]]; then
    err "Release zip not found at ${RELEASE_ASSET_BASENAME}.zip. Did phase 1 run?"
  fi
  if [[ ! -f "${ROOT}/${RELEASE_ASSET_BASENAME}.dSYM.zip" ]]; then
    err "Release dSYM not found at ${RELEASE_ASSET_BASENAME}.dSYM.zip. Did phase 1 run?"
  fi
  artifact_matches_current_inputs "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" || \
    err "Release zip does not match the Mac inputs in $RELEASE_BRANCH; rerun phase 1."
  artifact_pair_matches \
    "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" \
    "${ROOT}/${RELEASE_ASSET_BASENAME}.dSYM.zip" || \
    err "Release dSYM does not match the app binary; rerun phase 1."

  local is_draft
  if ! is_draft=$(gh release view "$TAG" --repo o1xhack/CodexBar-Mobile --json isDraft -q .isDraft 2>&1); then
    err "No release found for tag $TAG. Run phase 1 first (./Scripts/release.sh)."
  fi
  [[ "$is_draft" == "true" ]] || \
    err "Release $TAG is already public. Finalize only accepts a reviewed draft."

  require_remote_asset_matches_local "${ROOT}/${RELEASE_ASSET_BASENAME}.zip"
  require_remote_asset_matches_local "${ROOT}/${RELEASE_ASSET_BASENAME}.dSYM.zip"

  local KEY_FILE
  KEY_FILE=$(clean_key "$SPARKLE_PRIVATE_KEY_FILE")
  trap "rm -f '$KEY_FILE'" EXIT

  clear_sparkle_caches "$BUNDLE_ID"

  SPARKLE_PRIVATE_KEY_FILE="$KEY_FILE" \
    SPARKLE_RELEASE_VERSION="$MARKETING_VERSION" \
    SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/o1xhack/CodexBar-Mobile/releases/download/${TAG}/" \
    "$ROOT/Scripts/make_appcast.sh" \
    "${RELEASE_ASSET_BASENAME}.zip" \
    "$FEED_URL"

  verify_local_appcast_artifact \
    "${ROOT}/${RELEASE_ASSET_BASENAME}.zip" \
    "$KEY_FILE"

  echo "Publishing reviewed draft release $TAG..."
  gh release edit "$TAG" --repo o1xhack/CodexBar-Mobile --draft=false

  verify_appcast_entry "$APPCAST" "$MARKETING_VERSION" "$KEY_FILE"

  git add "$APPCAST"
  git commit -m "docs: update appcast for ${MARKETING_VERSION}"
  git push origin "$RELEASE_BRANCH"

  if [[ "${RUN_SPARKLE_UPDATE_TEST:-0}" == "1" ]]; then
    local PREV_TAG
    PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')
    [[ -z "$PREV_TAG" ]] && err "RUN_SPARKLE_UPDATE_TEST=1 but no previous tag found"
    "$ROOT/Scripts/test_live_update.sh" "$PREV_TAG" "$TAG"
  fi

  check_assets "$TAG" "$ARTIFACT_PREFIX"
  # Note: the release tag was already pushed in phase 1
  # (git push -f origin "$TAG"). Running `git push origin --tags` here
  # tries to push ALL local tags — including the upstream tag namespace
  # inherited via `remote add upstream` — which hits conflicts on any
  # old tag origin doesn't have in the same shape. Skip it.

  cat <<EOF

============================================================
Phase 2 complete — Release ${MARKETING_VERSION} is LIVE.

  Release:    https://github.com/o1xhack/CodexBar-Mobile/releases/tag/$TAG
  Appcast:    $FEED_URL
  CFBundle:   ${BUILD_NUMBER}.${MOBILE_VERSION}

Sparkle clients will prompt upgrade on their next check-for-updates
cycle (raw.githubusercontent.com cache may take a few minutes to
propagate).
============================================================
EOF
}

case "${1:-phase1}" in
  phase1|--phase1|"")
    phase1
    ;;
  phase2|--phase2|--finalize)
    phase2
    ;;
  *)
    err "Usage: $0 [--finalize]"
    ;;
esac
