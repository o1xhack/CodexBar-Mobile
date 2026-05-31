#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexBar"
APP_IDENTITY="Developer ID Application: Yuxiao Wang (3TUERHN53E)"
APP_BUNDLE="CodexBar.app"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"
# Load local-only release secrets from ~/.codexbar-secrets if available.
source "$ROOT/Scripts/load-release-secrets.sh"
RELEASE_ASSET_BASENAME="${APP_NAME}-${MARKETING_VERSION}-mobile.${MOBILE_VERSION}"
ZIP_NAME="${RELEASE_ASSET_BASENAME}.zip"
DSYM_ZIP="${RELEASE_ASSET_BASENAME}.dSYM.zip"
RELEASE_STAGE_DIR=$(mktemp -d /tmp/codexbar-release.XXXXXX)
STAGED_APP_BUNDLE="${RELEASE_STAGE_DIR}/${APP_BUNDLE}"

if [[ -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing App Store Connect release settings (key id or issuer id)." >&2
  exit 1
fi
if [[ -z "${APP_STORE_CONNECT_API_KEY_FILE:-}" && -z "${APP_STORE_CONNECT_API_KEY_P8:-}" ]]; then
  echo "Set APP_STORE_CONNECT_API_KEY_FILE or APP_STORE_CONNECT_API_KEY_P8." >&2
  exit 1
fi
if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  echo "SPARKLE_PRIVATE_KEY_FILE is required for release signing/verification." >&2
  exit 1
fi
if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Sparkle key file not found: $SPARKLE_PRIVATE_KEY_FILE" >&2
  exit 1
fi
key_lines=$(grep -v '^[[:space:]]*#' "$SPARKLE_PRIVATE_KEY_FILE" | sed '/^[[:space:]]*$/d')
if [[ $(printf "%s\n" "$key_lines" | wc -l) -ne 1 ]]; then
  echo "Sparkle key file must contain exactly one base64 line (no comments/blank lines)." >&2
  exit 1
fi

NOTARIZATION_TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codexbar-notarize.XXXXXX")
chmod 700 "$NOTARIZATION_TEMP_DIR"
API_KEY_PATH="$NOTARIZATION_TEMP_DIR/codexbar-api-key.p8"
NOTARIZATION_ZIP="$NOTARIZATION_TEMP_DIR/${APP_NAME}Notarize.zip"
trap 'rm -rf "$NOTARIZATION_TEMP_DIR" "$RELEASE_STAGE_DIR"' EXIT

if [[ -n "${APP_STORE_CONNECT_API_KEY_FILE:-}" ]]; then
  if [[ ! -f "$APP_STORE_CONNECT_API_KEY_FILE" ]]; then
    echo "App Store Connect API key file not found: $APP_STORE_CONNECT_API_KEY_FILE" >&2
    exit 1
  fi
  cp "$APP_STORE_CONNECT_API_KEY_FILE" "$API_KEY_PATH"
else
  (
    umask 077
    printf '%s' "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > "$API_KEY_PATH"
  )
fi
chmod 600 "$API_KEY_PATH"

# Allow building a universal binary if ARCHES is provided; default to universal (arm64 + x86_64).
ARCHES_VALUE=${ARCHES:-"arm64 x86_64"}
ARCH_LIST=( ${ARCHES_VALUE} )
for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c release --arch "$ARCH"
done
CODEXBAR_STAGED_APP_PATH="$STAGED_APP_BUNDLE" CODEXBAR_WIDGET_METADATA_MODE=required ARCHES="${ARCHES_VALUE}" ./Scripts/package_app.sh release
APP_BUNDLE="$STAGED_APP_BUNDLE"

ENTITLEMENTS_DIR="$ROOT/.build/entitlements"
APP_ENTITLEMENTS="${ENTITLEMENTS_DIR}/CodexBar.entitlements"
WIDGET_ENTITLEMENTS="${ENTITLEMENTS_DIR}/CodexBarWidget.entitlements"

echo "Signing with $APP_IDENTITY"
if [[ -f "$APP_BUNDLE/Contents/Helpers/CodexBarCLI" ]]; then
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
    "$APP_BUNDLE/Contents/Helpers/CodexBarCLI"
fi
if [[ -f "$APP_BUNDLE/Contents/Helpers/CodexBarClaudeWatchdog" ]]; then
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
    "$APP_BUNDLE/Contents/Helpers/CodexBarClaudeWatchdog"
fi
if [[ -d "$APP_BUNDLE/Contents/PlugIns/CodexBarWidget.appex" ]]; then
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
    --entitlements "$WIDGET_ENTITLEMENTS" \
    "$APP_BUNDLE/Contents/PlugIns/CodexBarWidget.appex/Contents/MacOS/CodexBarWidget"
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
    --entitlements "$WIDGET_ENTITLEMENTS" \
    "$APP_BUNDLE/Contents/PlugIns/CodexBarWidget.appex"
fi
codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP_BUNDLE"

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$NOTARIZATION_ZIP"

echo "Submitting for notarization"
xcrun notarytool submit "$NOTARIZATION_ZIP" \
  --key "$API_KEY_PATH" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

# Strip any extended attributes that would create AppleDouble files when zipping
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"

spctl -a -t exec -vv "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

# Launch verification — last gate before declaring the build good.
# spctl / stapler / notarization passed, but those checks don't cover
# every failure mode. Most notably: a bundle missing
# Contents/embedded.provisionprofile passes all of the above but is
# rejected by AMFI at launch time with "Launchd job spawn failed"
# (POSIX 163). The only way to catch this class of failure is to
# actually try to launch the binary.
echo "Launch verification — direct exec of stapled bundle, must stay alive 2s"
"$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 &
LAUNCH_TEST_PID=$!
sleep 2
if kill -0 "$LAUNCH_TEST_PID" 2>/dev/null; then
  kill -TERM "$LAUNCH_TEST_PID" 2>/dev/null || true
  sleep 1
  if kill -0 "$LAUNCH_TEST_PID" 2>/dev/null; then
    kill -KILL "$LAUNCH_TEST_PID" 2>/dev/null || true
  fi
  wait "$LAUNCH_TEST_PID" 2>/dev/null || true
  echo "Launch verification: OK"
else
  wait "$LAUNCH_TEST_PID" 2>/dev/null || true
  echo "" >&2
  echo "FATAL: $APP_NAME exited within 2s of launch." >&2
  echo "  spctl, stapler, and notarization all passed, but AMFI / Launch" >&2
  echo "  Services rejected the binary at runtime. Most common cause:" >&2
  echo "  Contents/embedded.provisionprofile is missing or malformed" >&2
  echo "  (entitlements with com.apple.application-identifier require it)." >&2
  echo "" >&2
  echo "  Inspect: ls -la \"$APP_BUNDLE/Contents/embedded.provisionprofile\"" >&2
  echo "  Reproduce:  \"$APP_BUNDLE/Contents/MacOS/$APP_NAME\"" >&2
  echo "" >&2
  echo "  Refusing to publish — removing $ZIP_NAME." >&2
  rm -f "$ZIP_NAME"
  exit 1
fi

echo "Packaging dSYM"
FIRST_ARCH="${ARCH_LIST[0]}"
PREFERRED_ARCH_DIR=".build/${FIRST_ARCH}-apple-macosx/release"
DSYM_PATH="${PREFERRED_ARCH_DIR}/${APP_NAME}.dSYM"
if [[ ! -d "$DSYM_PATH" ]]; then
  echo "Missing dSYM at $DSYM_PATH" >&2
  exit 1
fi
if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
  MERGED_DSYM="${PREFERRED_ARCH_DIR}/${APP_NAME}.dSYM-universal"
  rm -rf "$MERGED_DSYM"
  cp -R "$DSYM_PATH" "$MERGED_DSYM"
  DWARF_PATH="${MERGED_DSYM}/Contents/Resources/DWARF/${APP_NAME}"
  BINARIES=()
  for ARCH in "${ARCH_LIST[@]}"; do
    ARCH_DSYM=".build/${ARCH}-apple-macosx/release/${APP_NAME}.dSYM/Contents/Resources/DWARF/${APP_NAME}"
    if [[ ! -f "$ARCH_DSYM" ]]; then
      echo "Missing dSYM for ${ARCH} at $ARCH_DSYM" >&2
      exit 1
    fi
    BINARIES+=("$ARCH_DSYM")
  done
  lipo -create "${BINARIES[@]}" -output "$DWARF_PATH"
  DSYM_PATH="$MERGED_DSYM"
fi
"$DITTO_BIN" --norsrc -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"

echo "Done: $ZIP_NAME"
