---
summary: "Fork Mac release workflow: build, sign, notarize, appcast, and publish with composite build numbers."
read_when:
  - Releasing a new Mac build for the fork (mobile version bump or upstream merge)
  - Troubleshooting Sparkle update detection or broken download URLs
---

# Mac Release — Fork Workflow

This is the complete release workflow for the o1xhack/CodexBar-Mobile fork.
For upstream release docs see `docs/RELEASING.md`.

## Prerequisites

| Item | Location |
|------|----------|
| Sparkle Ed25519 private key | `~/.codexbar-secrets/sparkle_ed25519.key` |
| App Store Connect App Manager key | `~/.codex-secrets/apple/app-store-connect/` |
| CodexBar release env | `~/.codexbar-secrets/codexbar-release.env` |
| Signing identity | `Developer ID Application: Yuxiao Wang (3TUERHN53E)` |
| `generate_appcast` | `.build/artifacts/sparkle/Sparkle/bin/generate_appcast` (built by SwiftPM) |

## Build Number Scheme

The fork uses a **composite** `CFBundleVersion` to avoid collisions with upstream:

```
CFBundleVersion = BUILD_NUMBER.MOBILE_VERSION
                  53.1.1.0
```

- `BUILD_NUMBER` in `version.env` tracks the upstream base build number.
- `MOBILE_VERSION` in `version.env` tracks the iOS companion version.
- `package_app.sh` joins them automatically.
- Sparkle compares dot-separated components numerically, so `53 < 53.1.0.0 < 53.1.1.0 < 54`.

**When to bump what:**

| Scenario | Action |
|----------|--------|
| Mobile-only update (iOS sync changes) | Bump `MOBILE_VERSION` only |
| Merge upstream (new Mac version) | Update `BUILD_NUMBER` to match upstream, keep `MOBILE_VERSION` |
| Both | Update both |

## CHANGELOG Structure

The `CHANGELOG.md` for version 0.19.0 is structured as:

```
## 0.19.0 — DATE

### Highlights — Mobile X.Y.Z     ← Our changes first
- ...

### Mobile (previous version)      ← Previous mobile changes
- ...

### CodexBar 0.19.0 (Upstream)     ← Upstream changes, clearly labeled
- ...

### Providers & Usage              ← Upstream detail sections
- ...
```

`Scripts/changelog-to-html.sh` reads `MOBILE_VERSION` from `version.env` and generates the title as:
```
CodexBar 0.19.0-Mobile 1.1.0
```

## Release Steps

### 1. Update version.env (if needed)

```bash
# Only if bumping versions
vim version.env
# MARKETING_VERSION=0.19.0   ← follows upstream
# BUILD_NUMBER=54             ← follows upstream
# MOBILE_VERSION=1.1.0        ← our mobile version
```

### 2. Update CHANGELOG.md

Add/update the "Highlights — Mobile X.Y.Z" section at the top of the current version entry.

### 3. Build, sign, and notarize

```bash
./Scripts/sign-and-notarize.sh
```

This produces:
- `CodexBar-{MAC_VER}-mobile.{MOBILE_VER}.zip` (signed + notarized)
- `CodexBar-{MAC_VER}-mobile.{MOBILE_VER}.dSYM.zip`

**Verify the build:**
```bash
plutil -p CodexBar.app/Contents/Info.plist | grep CFBundleVersion
# → "53.1.1.0"

codesign -dvvv CodexBar.app 2>&1 | grep Authority
# → Developer ID Application: Yuxiao Wang (3TUERHN53E)
```

### 4. Generate appcast

```bash
source version.env
TAG="v${MARKETING_VERSION}-mobile.${MOBILE_VERSION}"

PATH="$PWD/.build/artifacts/sparkle/Sparkle/bin:$PATH" \
  SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/o1xhack/CodexBar-Mobile/releases/download/${TAG}/" \
  SPARKLE_RELEASE_VERSION="$MARKETING_VERSION" \
  ./Scripts/make_appcast.sh \
  "CodexBar-${MARKETING_VERSION}-mobile.${MOBILE_VERSION}.zip" \
  "https://raw.githubusercontent.com/o1xhack/CodexBar-Mobile/mobile-dev/appcast.xml"
```

**Important:** `SPARKLE_DOWNLOAD_URL_PREFIX` must include the full tag (e.g. `v0.19.0-mobile.1.1.0/`), not just the marketing version.

### 5. Create tag and GitHub release

```bash
git tag -f -m "CodexBar ${MARKETING_VERSION} Mobile ${MOBILE_VERSION}" "$TAG"
git push -f origin "$TAG"

gh release create "$TAG" \
  "CodexBar-${MARKETING_VERSION}-mobile.${MOBILE_VERSION}.zip" \
  "CodexBar-${MARKETING_VERSION}-mobile.${MOBILE_VERSION}.dSYM.zip" \
  --repo o1xhack/CodexBar-Mobile \
  --title "CodexBar ${MARKETING_VERSION} — Mobile ${MOBILE_VERSION}" \
  --notes-file <(changelog excerpt)
```

**Note:** Always use `--repo o1xhack/CodexBar-Mobile` to avoid accidentally creating on upstream.

### 6. Commit and push appcast

```bash
git add appcast.xml CHANGELOG.md
git commit -m "Release ${MARKETING_VERSION}-mobile.${MOBILE_VERSION}: update appcast"
git push origin mobile-dev
```

### 7. Verify

```bash
# Appcast served correctly
curl -s "https://raw.githubusercontent.com/o1xhack/CodexBar-Mobile/mobile-dev/appcast.xml" \
  | grep "sparkle:version"

# Download URL works
curl -sIL "https://github.com/o1xhack/CodexBar-Mobile/releases/download/${TAG}/CodexBar-${MARKETING_VERSION}-mobile.${MOBILE_VERSION}.zip" \
  | grep "^HTTP"
# Should be: 302 → 200
```

Then open CodexBar on Mac → Settings → About → **Check for Updates** to confirm.

## Automated Release (alternative)

`Scripts/release.sh` automates steps 3–6 in one command but also runs `swiftformat`, `swiftlint`, and `swift test` first. Use it when the full test suite passes:

```bash
./Scripts/release.sh
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Sparkle says "up to date" | Build number not higher than installed | Check `CFBundleVersion` in app vs `sparkle:version` in appcast |
| Download fails (404) | Release is draft or tag mismatch | Verify release is published: `gh api repos/o1xhack/CodexBar-Mobile/releases/tags/$TAG --jq .draft` |
| `generate_appcast` not found | Not in PATH | Prefix with `PATH="$PWD/.build/artifacts/sparkle/Sparkle/bin:$PATH"` |
| Appcast URL wrong | `SPARKLE_DOWNLOAD_URL_PREFIX` missing | Must set to full tag URL, not just marketing version |
| CDN stale after push | raw.githubusercontent.com cache | Wait 2-5 minutes, or `curl -H "Cache-Control: no-cache"` to check |
