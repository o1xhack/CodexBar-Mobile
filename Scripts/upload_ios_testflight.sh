#!/usr/bin/env bash
#
# Archive the iOS app (CodexBarMobile) and upload to App Store Connect
# (which dispatches to TestFlight) via Xcode's cloud-signing flow.
#
# How it works:
#   - `xcodebuild archive` produces a Development-signed .xcarchive (the
#     Apple Development cert in our Keychain is sufficient for this stage).
#   - `xcodebuild -exportArchive` with `destination: upload` in the export
#     options plist signs + uploads in one step. Cloud signing uses Xcode's
#     logged-in Apple ID session (Settings → Accounts), NOT a local Apple
#     Distribution cert. `-allowProvisioningUpdates` lets xcodebuild fetch
#     the Managed Distribution certificate / provisioning profile as
#     needed.
#
# Prereq: Xcode → Settings → Accounts has the developer Apple ID logged in.
# That's the one-time setup; Xcode's session persists across runs.
#
# Explicitly DO NOT pass `-authenticationKeyPath` / `-authenticationKeyID`
# to xcodebuild. When present, they override the Xcode session and force
# the API-key-based cloud-signing path. CodexBar's upload path is intentionally
# based on the logged-in Xcode Apple ID session, while the global App Manager
# ASC key is reserved for App Store Connect / Developer API write operations.
#
# Usage: ./Scripts/upload_ios_testflight.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Pre-flight: run lint (Swift + i18n xcstrings audit) before spending ~2 min
# on archive + upload. Catches the regression class where new
# `String(localized:)` strings ship without zh-Hant / ja translations
# (Builds 55 and 92 hit this before the audit was wired in).
echo "==> Pre-flight lint (Swift + i18n)..."
"$ROOT/Scripts/lint.sh" lint

STAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE_PATH="/tmp/CodexBarMobile-$STAMP.xcarchive"
# `.plist` suffix after the mktemp X's makes the template literal on
# macOS (BSD mktemp only substitutes trailing X's) — drop the suffix.
OPTIONS_PLIST=$(mktemp /tmp/cbm-export-options.XXXXXX)

cat > "$OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>3TUERHN53E</string>
    <key>destination</key>
    <string>upload</string>
    <key>uploadSymbols</key>
    <true/>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST

trap 'rm -f "$OPTIONS_PLIST"' EXIT

BUILD=$(grep CURRENT_PROJECT_VERSION CodexBarMobile/project.yml | head -1 | awk '{print $2}' | tr -d '"')
echo "==> Archiving CodexBarMobile (Build $BUILD)..."
xcodebuild archive \
  -project CodexBarMobile/CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  | tail -30

echo ""
echo "==> Signing + uploading to App Store Connect (cloud signing via Xcode session)..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$OPTIONS_PLIST" \
  -allowProvisioningUpdates \
  | tail -30

echo ""
echo "==> Upload dispatched. ASC will process in 5-30 min and email when the"
echo "    build appears in TestFlight. Archive saved at:"
echo "    $ARCHIVE_PATH"
