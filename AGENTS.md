# CodexBar Mobile — Agent Workflow

This file is the repo-level routing and quality gate for AI agents working on
CodexBar Mobile (iOS). Detailed operational workflows live in skills.

> **Scope:** We only work on the iOS app (`CodexBarMobile/`). Mac-side code is maintained upstream.
>
> **Current upstream alignment:** see `version.env` at repo root — `UPSTREAM_VERSION` and `UPSTREAM_SYNC_DATE` are the authoritative fields. Do NOT consult `plan.md` for this — it's a human-curated planning doc and lags reality.

## Required Skills

- Use `$codexbar-git-workflow` for branch creation, commit cadence, Git/GitHub
  push, PR, review loop, branch cleanup, and Todoist handoff.
- Use `$release-codexbar` for Mac signing/notarization/appcast/GitHub release
  work.
- Use `$qa-test` for live provider QA, menu proof, and release smoke tests.

---

## Development Lifecycle

Every feature or fix follows these 7 steps in order:

```
┌───────────────────┬─────────────────────────────────────────────────┬─────────────────────┐
│       Step        │                   Description                   │       Output        │
├───────────────────┼─────────────────────────────────────────────────┼─────────────────────┤
│ 1. Research       │ Understand the problem, read code/SDK/data      │ Root cause or       │
│                   │ Check upstream repo + PRs for prior art         │ requirements doc    │
├───────────────────┼─────────────────────────────────────────────────┼─────────────────────┤
│ 2. Design         │ Write research doc in Research/, mark draft     │ Research/NNN-*.md   │
│                   │ Get user confirmation on approach               │                     │
├───────────────────┼─────────────────────────────────────────────────┼─────────────────────┤
│ 3. Implementation │ Write code in phases, protocol-first            │ Code changes        │
├───────────────────┼─────────────────────────────────────────────────┼─────────────────────┤
│ 4. Testing        │ Build, simulator, real device if needed         │ Tests pass          │
├───────────────────┼─────────────────────────────────────────────────┼─────────────────────┤
│ 5. Documentation  │ Update CHANGELOG, in-app release notes,         │ Traceable record    │
│                   │ research doc status → done                      │                     │
├───────────────────┼─────────────────────────────────────────────────┼─────────────────────┤
│ 6. Commit         │ Branch/commit/GitHub handoff via skill         │ git commit / PR     │
├───────────────────┼─────────────────────────────────────────────────┼─────────────────────┤
│ 7. Push & Release │ Push to remote, archive, upload to TestFlight   │ User-installable    │
└───────────────────┴─────────────────────────────────────────────────┴─────────────────────┘
```

### Repository map

| Remote / branch | Role |
|-----------------|------|
| `upstream` / `steipete/CodexBar` | Original open-source repo, read only |
| `origin` / `o1xhack/CodexBar-Mobile` | Our fork |
| `mobile-dev` | Main working branch |
| `main` | Upstream-alignment branch; do not modify directly |

Use Git/GitHub for branch and commit operations. Create a task branch before
implementation unless the request is read-only. Do not require Goal prompts to
spell out branch names; choose the right branch shape from
`$codexbar-git-workflow`.

### Definition of Done for release / upstream-sync work

For release and upstream-sync tasks, **done** means user-installable artifacts
exist, not just "code committed" or "pushed":

- Mac: signed + notarized Sparkle draft/release flow completed as requested
- iOS: archive/export/upload flow completed when upload/TestFlight is in scope
- appcast, versioning, CloudKit audit, release notes, and Todoist state are
  updated

Credentials live on the user's Mac. CodexBar-specific release secrets such as
Sparkle live under `~/.codexbar-secrets/`; Apple App Store Connect App Manager
credentials are global Apple release/signing credentials under
`~/.codex-secrets/apple/app-store-connect/`; the Developer ID certificate is in
Keychain. When the user has authorized release/upload work, run the release
commands on this machine instead of only listing commands for the user. The
complete release gate is
[`docs/RELEASE-CHECKLIST.md`](docs/RELEASE-CHECKLIST.md); read it before every
release or upstream-sync completion check.

### Collaboration roles

| User intent | Agent role | Action |
|-------------|------------|--------|
| 调研 / research | Architect | Run Steps 1-2 and write/update `Research/` |
| 开发 / implement | Developer | Run Steps 3-4 with focused implementation + tests |
| 开分支 / branch | Developer | Use `$codexbar-git-workflow` |
| 提交 | Release Engineer | Use `$codexbar-git-workflow` commit flow |
| 提交推送 / PR | Release Engineer | Use `$codexbar-git-workflow` push/PR/Todoist flow |
| 上传 / Archive | Release Engineer | Run Step 7 archive/upload flow |
| 安装到手机 | Release Engineer | Generate project if needed and install to a real device |

---

## Step 1 — Research

Before writing any code, understand the problem space.

- Read relevant source code, SDK docs, and real synced data
- Check upstream (steipete/CodexBar) for existing implementations or open PRs
- Save findings to `CodexBarMobile/Research/NNN-feature-name.md`

## Step 2 — Design

- Write or update the research doc with chosen approach, data models, key files
- Set status appropriately (see research status flow below)
- Get user confirmation before proceeding to implementation

### Research document status flow

```
draft → ready → in-progress → done
  │
  ├→ blocked-upstream   (waiting for upstream PR to merge)
  └→ dropped            (decided not to pursue)
```

Full status definitions and index are in `CodexBarMobile/Research/README.md`.

## Step 3 — Implementation

- Follow protocol-first design: define interfaces before writing logic
- Phase large features into incremental, buildable steps
- Follow all coding rules below (localization, file conventions, etc.)

## Step 4 — Testing

- Build with `xcodebuild` to verify compilation
- Run unit tests if applicable
- Verify on simulator or real device as needed
- Add or extend XCTest / Swift Testing coverage for provider, parser, model,
  and settings changes. Prefer backticked sentence names for Swift Testing
  cases and clear fictitious model names when test data is synthetic.
- Run focused `swift test --filter ...` checks for parser/provider fixes when
  possible, then the broader gate required by the release checklist.
- Never run tests/checks or ad-hoc validation that can display macOS Keychain prompts. Live provider probes, browser-cookie imports, `codexbar usage` against real accounts, and real SecItem reads must be explicitly requested; otherwise use parser tests, stubs, test stores, or `KeychainNoUIQuery`.
- macOS CI is brittle around headless AppKit status/menu tests. Prefer stable state/model seams (`MenuDescriptor`, `ProvidersPane`, `CodexAccountsSectionState`, etc.) over live `NSStatusBar` / `NSMenu` flows unless the AppKit wiring itself is under test.

### Multi-device iCloud Sync Compatibility Gate

When a release changes Mac→CloudKit→iOS sync, Shared payloads, CloudKit schema, provider display data, cache behavior, or cross-version rendering, testing must follow **[`docs/ios-sync-compatibility-testing.md`](docs/ios-sync-compatibility-testing.md)**. This is the canonical 2 Mac × 2 iPhone old/new compatibility gate. The release `Research/NNN-*/03-testing.md` records that release's actual pass/fail/substituted evidence; it is not the source of the reusable rule.

### CI Policy — Fork Invariant

CI uses the durable two-layer policy in **[`docs/ci-policy.md`](docs/ci-policy.md)**:

- Every PR update runs only `PR Fast Checks` (portable lint and policy guards).
- Expensive macOS/Linux matrices run once after merge, selected by the final diff,
  or by explicit manual full-CI dispatch.
- A verified `upstream-sync/*` merge reuses the published upstream release's
  successful heavy checks; fork-specific local/release gates still apply.
- During upstream merges, preserve `.github/workflows/pr-fast.yml`, the fork
  trigger model in `.github/workflows/ci.yml`, and `Scripts/check_ci_policy.sh`.
  Never resolve an upstream workflow conflict by restoring heavy CI on PR
  `synchronize` events.

`Scripts/check_ci_policy.sh` is part of portable lint and fails if another
workflow adds a PR update trigger or the fast workflow gains heavy jobs. This
policy is repository state, not agent memory.

## Step 5 — Documentation

After code is complete:

1. Update `CodexBarMobile/CHANGELOG.md` — Keep a Changelog format (Added / Changed / Fixed)
2. Update in-app release notes in `MobileReleaseNotesCatalog` (in `ContentView.swift`) — plain language, 4-language localized
   - **Same MARKETING_VERSION = same release notes block.** As long as only the build number changes (e.g. 1.0.0 (15) → 1.0.0 (16)), all changes belong to the same release notes entry. Before adding a new line:
     1. Check if an existing line already covers this feature area.
     2. If yes → merge the new detail into that line (rewrite it to include the update).
     3. If no existing line covers it → add a new line.
   - Only create a separate `ReleaseNotesVersion` entry when `MARKETING_VERSION` itself changes (e.g. 1.0.0 → 1.1.0).
3. Update research doc status to `done`

### Release notes — two audiences

| File | Audience | Style |
|------|----------|-------|
| `CodexBarMobile/CHANGELOG.md` | Developers, App Review | Technical, concise |
| `MobileReleaseNotesCatalog` in `ContentView.swift` | End users (in-app) | Plain language, no jargon, localized |

## Step 6 — Branch, Commit & GitHub Handoff

When work needs a branch, commit, push, PR, review loop, branch cleanup, or
Todoist status update, load and follow `$codexbar-git-workflow`.

For large Goals, the agent may make staged Git commits when the Goal or user
authorizes implementation work. Do not push, merge, tag, publish a live release,
or upload unless the user explicitly asks or the active Goal explicitly includes
that handoff.

### Version number format

**iOS (project.yml)** — these are CFBundle fields:
- `MARKETING_VERSION` = user-facing version, e.g. `1.7.0` (feature releases only)
- `CURRENT_PROJECT_VERSION` = build number, e.g. `129`
- Displayed as: **1.7.0 (129)**

**Mac (version.env)** — fork-specific scheme with subdecimal patches.
Full rules + decision tree + sparkle:version explanation:
→ **[`docs/versioning.md`](docs/versioning.md)** (read this first when bumping
Mac MARKETING_VERSION / BUILD_NUMBER / MOBILE_VERSION / UPSTREAM_VERSION).

## Step 7 — Push & Release

### CloudKit Environment — CRITICAL

All builds (Mac and iOS) **must** use CloudKit **Production** environment:

- **Mac** (`Scripts/package_app.sh`): entitlements must include `com.apple.developer.icloud-container-environment` = `Production`
- **iOS** (`CodexBarMobile/CodexBarMobile.entitlements`): must include `com.apple.developer.icloud-container-environment` = `Production`
- **iOS via Xcode debug**: also uses Production (set in entitlements), so Xcode installs and TestFlight share the same CloudKit database

If this entitlement is missing, Mac defaults to Development environment and TestFlight iOS uses Production — data goes to different databases and sync appears broken.

### CloudKit Schema Deploy — pre-release audit

Before every Mac release: run the audit in **[`docs/cloudkit-deploy-audit.md`](docs/cloudkit-deploy-audit.md)** to decide whether the Production schema needs a Dashboard deploy. Catches the recurring "I added a field but forgot to deploy" trap. Verdict table + grep commands + historical record live in that doc.

### iOS — Archive & Upload

When the user asks to upload / archive / release:

```bash
# 1. Generate Xcode project
cd CodexBarMobile && xcodegen generate

# 2. Archive
xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath /tmp/CodexBarMobile.xcarchive archive -allowProvisioningUpdates

# 3. Export & upload to App Store Connect
xcodebuild -exportArchive \
  -archivePath /tmp/CodexBarMobile.xcarchive \
  -exportOptionsPlist /tmp/ExportOptions.plist \
  -allowProvisioningUpdates
```

### Mac — Sign, Notarize & Release

**Complete workflow:** [`docs/RELEASING-MOBILE.md`](docs/RELEASING-MOBILE.md)

Quick summary:
1. Update `CHANGELOG.md` — Mobile changes first, upstream second
2. `./Scripts/sign-and-notarize.sh` — builds, signs with `Developer ID Application: Yuxiao Wang (3TUERHN53E)`, notarizes
3. Generate appcast with `make_appcast.sh` (set `SPARKLE_DOWNLOAD_URL_PREFIX` to full tag URL)
4. Create GitHub release on `o1xhack/CodexBar-Mobile` (not upstream)
5. Push appcast to `mobile-dev`

**Build number:** `BUILD_NUMBER.MOBILE_VERSION` (e.g. `53.1.1.0`). See `docs/sparkle.md` for details.

---

## Coding Rules

### Version Control — Git/GitHub

Use Git/GitHub for branch, commit, push, PR, review, and branch cleanup work.
Do not use `jj` unless the user explicitly re-enables it. Operational details
belong in `$codexbar-git-workflow`, not in individual Goal prompts.

### Operational guardrails

- Do not modify Mac-only files such as `Sources/` or `Tests/` unless the user
  explicitly asks for Mac/upstream-sync/release work.
- Never push to `upstream`; only push to `origin`.
- Do not hand-edit `.xcodeproj`; update `project.yml` and run `xcodegen
  generate`.
- Do not skip build numbers, changelog, release notes, CloudKit audit, or
  localization checks when their step applies.
- Do not add full build/test matrices to PR update events. Follow
  `docs/ci-policy.md`; full CI belongs after merge or explicit manual dispatch.

### Localization — Mandatory 4-Language Rule

**Every user-facing text change MUST include all 4 languages. No exceptions.**

Languages: English (`en`), Simplified Chinese (`zh-Hans`), Traditional Chinese (`zh-Hant`), Japanese (`ja`).

- Source language is English
- All strings use `String(localized:)` — the key is the English text itself
- Translations live in `Localizable.xcstrings` (JSON format)
- Every entry must have all 4 translations with `"state": "translated"`

**Needs translation:** UI labels, buttons, titles, descriptions, footers, placeholders, error messages, in-app release notes, onboarding text, empty states.

**Does NOT need translation:** Code comments, log messages, debug strings, accessibility identifiers, keys, enum raw values, format specifiers.

#### Self-check before finishing

- [ ] Every new `String(localized:)` has a matching entry in `Localizable.xcstrings`
- [ ] Every entry has all 4 languages with `"state": "translated"`
- [ ] No `"state": "new"` or missing language keys left behind

---

## Quick Reference

### Trigger phrases

| User says | Action |
|-----------|--------|
| 调研 | Steps 1–2 (research, save to Research/) |
| 开发 / implement | Steps 3–4 (implementation + tests) |
| 开分支 / branch | Use `$codexbar-git-workflow` |
| 提交 | Use `$codexbar-git-workflow` commit flow |
| 提交推送 / PR | Use `$codexbar-git-workflow` push/PR/Todoist flow |
| 上传 / Archive | Step 7 (xcodegen, archive, upload to TestFlight) |
| 安装到手机 | Generate project if needed, then install to a real device |

### Key paths

| Path | Purpose |
|------|---------|
| `CLAUDE.md` | Project overview + pointers |
| `AGENTS.md` | This file — repo routing and quality gates |
| `.agents/skills/codexbar-git-workflow/SKILL.md` | Git/GitHub branch, commit, push, PR, and handoff workflow |
| `CodexBarMobile/Research/` | Feature research docs |
| `CodexBarMobile/project.yml` | Build number + version |
| `CodexBarMobile/CHANGELOG.md` | Technical changelog |
| `CodexBarMobile/CodexBarMobile/ContentView.swift` | Main views + in-app release notes |
| `CodexBarMobile/CodexBarMobile/Localizable.xcstrings` | 4-language translations |
| `CodexBarMobile/CodexBarMobile/Views/` | Feature views |
| `CodexBarMobile/CodexBarMobile/Models/` | Data models and formatters |
| `CodexBarMobile/CodexBarMobile/Preview Content/PreviewData.swift` | Demo / preview data |
| `CodexBarMobile/Shared/` | Shared iCloud sync layer |
| `version.env` | Current ship version + upstream alignment (`UPSTREAM_VERSION`, `UPSTREAM_SYNC_DATE`) |
| `docs/versioning.md` | Mac/iOS versioning decision tree and Sparkle rules |
| `docs/cloudkit-deploy-audit.md` | CloudKit Production schema deploy audit |
| `docs/ios-sync-compatibility-testing.md` | Canonical 2 Mac × 2 iPhone old/new sync compatibility gate |
| `docs/RELEASE-CHECKLIST.md` | Release/upstream-sync Definition of Done and acceptance checklist |
