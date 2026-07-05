# v0.39.0 Upstream Sync Development Log

Status: `in-progress`
Date: 2026-07-04
Branch: `upstream-sync/v0.39.0-mobile.1.17.0`

## Checkpoints

### 2026-07-04 Research and Branch Setup

Evidence gathered:

```text
git status --short --branch
git fetch origin --prune --tags
git fetch upstream --prune --tags
git switch mobile-dev
git pull --ff-only origin mobile-dev
gh issue list --repo o1xhack/CodexBar-Mobile --state open --limit 100 --json number,title,labels,createdAt,updatedAt,url,body
gh issue list --repo o1xhack/CodexBar-Mobile --state closed --search "upstream-sync OR 上游" --limit 30 --json number,title,closedAt,labels,url
gh release list --repo steipete/CodexBar --limit 30 --json tagName,name,publishedAt,isDraft,isPrerelease,isLatest
gh release view v0.38.0 --repo steipete/CodexBar --json tagName,name,publishedAt,body
gh release view v0.38.1 --repo steipete/CodexBar --json tagName,name,publishedAt,body
gh release view v0.39.0 --repo steipete/CodexBar --json tagName,name,publishedAt,body
git ls-remote --tags upstream 'v0.37.2' 'v0.38.0' 'v0.38.1' 'v0.39.0'
git show v0.39.0:version.env
git diff --stat v0.37.2..v0.39.0
git diff --name-only v0.37.2..v0.39.0 -- Sources/CodexBarCore/Sync Shared CodexBarMobile Sources/CodexBarCore/UsageFetcher.swift Sources/CodexBarCore/WidgetSnapshot.swift Sources/CodexBar/UsageStore+WidgetSnapshot.swift Sources/CodexBarCore/ProviderCostSnapshot.swift Sources/CodexBarCore/CostUsageModels.swift Sources/CodexBarCore/CreditsModels.swift
git diff --name-only v0.37.2..v0.39.0 -- Sources/CodexBarCore/Providers
```

Result:

- `mobile-dev` was up to date with `origin/mobile-dev`.
- Work branch created: `upstream-sync/v0.39.0-mobile.1.17.0`.
- Open upstream-sync issue scope is #37 only.
- Closed upstream-sync issues confirm prior one-version consolidation pattern.
- Upstream latest official release is `v0.39.0`.
- Target fork versions are `0.39.0.1`, `97.1`, `1.17.0`, Sparkle
  `97.1.1.17.0`.

## Pending Implementation Steps

1. Merge `v0.39.0`. Done in `dfce1caa`.
2. Resolve conflicts, preserving fork release/sync/iOS constraints. Done.
3. Fix provider switch exhaustiveness for `sakana`, `qoder`, `crossmodel`, and
   `clawrouter`. Done.
4. Audit and implement iOS support for new provider data and any lost
   user-visible upstream values. Done for provider parity and CrossModel.
5. Update version files, changelogs, release notes, localization, tests, and
   mock/preview data. Done.
6. Run build/lint/test gates and compatibility matrix substitutions or real
   hardware evidence. In progress; focused gates and iOS simulator gate pass,
   full Mac `swift test` has existing timing residuals recorded in
   `03-testing.md`.
7. Run draft release prep and record artifact evidence. Pending clean commit and
   explicit boundary decision for remote tag/GitHub draft creation.
8. Run final review loop and fix all blockers. Pending.

## Merge Notes

- `AGENTS.md`: kept fork workflow plus upstream testing additions.
- `CHANGELOG.md` and `appcast.xml`: preserved fork release surface.
- `.github/workflows/upstream-monitor.yml`: kept fork release-based upstream
  monitor.
- `.github/workflows/ci.yml`: retained fork CI shape and upstream checkout
  update.
- `Scripts/sign-and-notarize.sh`: kept fork signing/notarization path instead
  of upstream wrapper behavior.
- `PreferencesView.swift`, `PreferencesSidebar.swift`, and
  `PreferencesSelection.swift`: merged upstream `NavigationSplitView` settings
  while preserving the Mobile pane.
- `PreferencesAboutPane.swift`: preserved fork repository and updater links.
- `UsageStore.swift`: combined upstream on-screen alert control with the fork's
  iOS push warning writer.
- `PiSessionCostCache.swift`: advanced artifact/version invalidation for the
  upstream parser/cache shape.
- `UsageFetcher.swift`: unioned upstream and fork fields, including provider
  display data required by the sync bridge.
- `CodexParserHash.generated.swift`: regenerated after the parser logic bump.
- Localized string conflicts were resolved by retaining fork-specific Mobile
  strings and upstream provider/settings text.

## iOS Bridge Notes

- Added `Shared/Models/V039Snapshots.swift` with `SyncCrossModelUsage` and its
  day/week/month `Window` entries.
- Added optional `ProviderUsageSnapshot.crossModelUsage` with tolerant decode
  and preservation through `with(quotaWarnings:)`.
- Added `SyncCoordinator.mapCrossModelUsage(provider:snapshot:)` and
  `mapCrossModelCostSummary(provider:snapshot:)`.
- Registered `sakana`, `qoder`, `crossmodel`, and `clawrouter` in
  `QuotaProviderList` and updated iOS quota-transition scale comments from 159
  to 171 zones.
- Added `CrossModelUsageCard` and conditionally render it in
  `ProviderDetailView`.
- Added provider colors for the v0.38/v0.39 provider set.
- Updated Mac mock injection to 69 synthetic providers across 59 unique IDs,
  including CrossModel structured payload data.
- Updated iOS release notes, iOS/root changelogs, and four-language
  translations for the new iOS 1.17.0 provider parity surface.
- Updated parser cache invalidation by bumping `parserLogicVersion` to 7 and
  regenerating the parser hash.

## Review Notes

- `PreviewData.swift` was audited by card type. No new preview fixture was
  added because CrossModel receives focused mock-provider and detail-card tests,
  while the other new providers use existing generic provider card families.
- The CloudKit schema audit is expected to require no Production deploy:
  CrossModel is an optional JSON field inside the existing compressed provider
  payload, and no CloudKit record type/zone/subscription/index changes were
  made in code.
- The GitHub draft release step is intentionally not run from a dirty tree.
  `Scripts/release.sh` phase 1 also pushes the release tag to `origin`, so the
  final remote draft boundary needs explicit confirmation if the active goal
  does not already authorize tag publication.
