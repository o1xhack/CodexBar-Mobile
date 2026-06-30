# 034 — iOS WidgetKit Suite

Status: `done`
Date: 2026-06-28
Scope: CodexBar Mobile iOS widgets for small, medium, and large Home Screen families.

## Goal

Ship a release-grade WidgetKit suite that lets users inspect synced CodexBar state without opening the app:

- provider usage pressure and error state
- provider focus / top provider
- today's cost and token activity
- sync health, device count, stale data, and no-data/error states

## Source Research

Local app architecture:

- `SyncedUsageData` is the app's main observable state. It hydrates from SwiftData/KVS, fetches CloudKit per-provider and legacy zones, resolves device lifecycle/linkage state, then publishes a merged `SyncedUsageSnapshot`.
- `CodexBarSync` already owns the public CloudKit/KVS sync surface and shared Codable wire models (`SyncedUsageSnapshot`, `ProviderUsageSnapshot`, `SyncCostSummary`).
- `project.yml` is the source of truth for targets. `.xcodeproj` must be regenerated with XcodeGen.
- The app target has Production CloudKit entitlements. The existing push extension already mirrors Production CloudKit/KVS entitlements.

Apple guidance checked:

- WidgetKit timelines are snapshots. The extension should provide placeholder, snapshot, and timeline entries, then request future refreshes instead of assuming live UI updates.
- Configurable widgets use `WidgetConfigurationIntent` / App Intents with small fixed enums when the choice set is stable.
- Widgets execute in an extension process. App Group is the standard shared-container path for app-authored cache files, but the Goal requires pausing before adding App Group entitlements.
- iOS 17+ widgets should use `containerBackground(for: .widget)` so the system can render backgrounds correctly across placements.

References:

- Apple WidgetKit: `https://developer.apple.com/documentation/widgetkit`
- Apple App Intents: `https://developer.apple.com/documentation/appintents`
- Apple App Groups: `https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups`

## Design

### Target layout

- New app extension target: `CodexBarMobileWidgets`
- Shared pure summary layer: `CodexBarWidgetShared/`
- Widget UI / timeline / AppIntent configuration: `CodexBarMobileWidgets/`
- App and widget both depend on `CodexBarSync`.
- `CodexBarMobileTests` cover the pure summary builder through the app target.

### Data channel

Approved path for this implementation pass:

1. Widget timeline reads real synced data through `CloudSyncManager.shared.fetchAllDeviceSnapshots()`.
2. If CloudKit returns empty/error, widget falls back to `CloudSyncManager.shared.fetchKVSSnapshot()`.
3. `CodexBarWidgetSnapshotBuilder` reduces synced snapshots into a compact widget summary.
4. Widget refresh policy:
   - loaded: next refresh after 15 minutes
   - empty/error/syncing: next refresh after 5-10 minutes

Deferred ideal cache path:

- App Group shared cache remains the better long-term path because the app can publish its fully resolved `SyncedUsageData` output, including account linkages and device lifecycle decisions.
- This pass does not add App Group entitlements because the Goal explicitly says to pause before App Group entitlement work.

### Widget kinds / variants

One configurable widget kind, `CodexBarStatusWidget`, uses `WidgetConfigurationIntent` with `CodexBarWidgetMode`:

- `Overview` — max usage pressure, provider count, cost and sync status.
- `Provider Focus` — top provider and highest-pressure provider rows.
- `Today Cost` — today's spend, 30-day spend, and token activity.
- `Sync Health` — last sync, stale flag, device count, provider count, and error count.

All four modes support `.systemSmall`, `.systemMedium`, and `.systemLarge`. Layout is not a stretched single view:

- Small: one hero metric or one top provider.
- Medium: metric strip plus provider/cost/sync rows.
- Large: dashboard combining metric strip, provider rows, and sync health rows.

### State handling

- Placeholder: deterministic sample data for widget gallery and previews.
- Snapshot: preview returns sample data; runtime snapshot returns syncing state.
- Timeline loaded: CloudKit/KVS data decoded and summarized.
- No data: no snapshots or providers found.
- Syncing: timeline/snapshot is reading iCloud data.
- Stale: latest sync older than 6 hours.
- Error: CloudKit/KVS unavailable or unauthenticated.
- Privacy: no account email is displayed; value labels are marked `.privacySensitive()`.

### Release and compatibility

- No CloudKit schema changes.
- No destructive migration.
- No Mac-only files are modified.
- No App Group capability is added in this pass.
- New widget extension target may need Apple Developer provisioning before archive/TestFlight, same as any new extension target.

## Test Plan

- Unit tests:
  - widget summary metrics from real `SyncedUsageSnapshot` values
  - provider account dedupe by latest update
  - no-data, stale, and error states
- Build:
  - regenerate `CodexBarMobile.xcodeproj` from `project.yml`
  - build app scheme for iOS simulator
  - run focused widget builder tests
- Preview/simulator:
  - Widget source includes `#Preview` timelines for small, medium, and large loaded/error states.
  - Simulator verification should confirm the app installs with the widget extension and the extension bundle is embedded.

## Verification Results

Completed on 2026-06-28:

- `xcodegen generate` — regenerated `CodexBarMobile.xcodeproj` from `project.yml`.
- `build_sim` via XcodeBuildMCP, `CodexBarMobile`, iPhone 17 simulator — passed with 0 warnings after stripping Dropbox/Finder extended attributes from generated build products.
- `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` — passed 3 tests, 0 failures.
- Full `test_sim` for the `CodexBarMobile` scheme — passed 508 tests, 0 failures.
- `build_run_sim` with `UI_TEST_PREVIEW_DATA UI_TEST_SKIP_ONBOARDING` — app installed and launched on simulator.
- Bundle inspection — `CodexBarMobileWidgets.appex` is embedded under `CodexBarMobile.app/PlugIns`, has `NSExtensionPointIdentifier = com.apple.widgetkit-extension`, includes `Metadata.appintents`, and ships `en`, `zh-Hans`, `zh-Hant`, and `ja` localization bundles.
- Localization audit — every localized catalog entry has translated `en`, `zh-Hans`, `zh-Hant`, and `ja` values; no `"state": "new"` entries were found.
- App Group audit — no App Group entitlement was added; release remains within the stated approval boundary.

Release upload on 2026-06-28:

- Version advanced for TestFlight: iOS `MARKETING_VERSION` `1.16.0`, `CURRENT_PROJECT_VERSION` `166`, root `MOBILE_VERSION` `1.16.0`.
- `bash Scripts/lint.sh lint` — passed, including SwiftFormat, SwiftLint, parser audits, documentation link checks, and `Localizable.xcstrings` source-vs-catalog audit.
- XcodeBuildMCP focused test `-only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` — passed 3 tests, 0 failures.
- `./Scripts/upload_ios_testflight.sh` — pre-flight lint passed, Release archive succeeded, App Store Connect export/upload succeeded.
- Archive path: `/tmp/CodexBarMobile-20260628-225334.xcarchive`.
- App Store Connect build check — `1.16.0 (166)` uploaded at `2026-06-28T22:56:25-07:00`, build id `b7589850-3726-4a20-9d0b-cdbd2f981bf0`, `processingState=VALID`.

Follow-up QA on 2026-06-29:

- User QA found the first uploaded widget build rendered a dark widget background even when iOS was in Light Mode; this means the initial WidgetKit suite did not meet the full light/dark appearance bar.
- Fixed `CodexBarWidgetView` to use a `colorScheme`-driven palette for widget background, tile background, tile border, brand color, and usage severity colors.
- Added explicit light and dark `PreviewProvider` variants for small, medium, and large widget families.
- Prepared corrective TestFlight build `1.16.0 (167)`.
- `build_sim` via XcodeBuildMCP, `CodexBarMobile`, iPhone 17 simulator — passed with 0 warnings.
- `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` — passed 3 tests, 0 failures.
- `bash Scripts/lint.sh lint` — passed, including i18n source-vs-catalog audit.
- `./Scripts/upload_ios_testflight.sh` — pre-flight lint passed, Release archive succeeded, App Store Connect export/upload succeeded.
- Archive path: `/tmp/CodexBarMobile-20260629-140710.xcarchive`.
- App Store Connect build check — `1.16.0 (167)` uploaded at `2026-06-29T14:10:26-07:00`, build id `93d4c8b4-e5f5-41df-8ce5-12fffec26bf2`, `processingState=VALID`.

Visual design follow-up on 2026-06-30:

- User QA found the widget suite still felt unlike a native iOS widget because
  the implementation used a dark dashboard look, gradients, and several
  simultaneous data colors.
- Reviewed Apple Weather-style system widgets, Flighty-style high-contrast
  travel widgets, and Fin-style tinted/dark appearance expectations. The shared
  design constraint is glanceability: one dominant metric, restrained typography,
  system appearance adaptation, and no multi-color dashboard palette.
- Reworked `CodexBarWidgetView` to use neutral Light/Dark backgrounds, a
  single-color foreground system, thin separators, monochrome provider markers,
  and progress lines instead of colorful metric tiles.
- Marked key values and progress fills with `.widgetAccentable()` so tinted
  Home Screen rendering stays single-color and system-driven.
- Prepared corrective TestFlight build `1.16.0 (170)`.
- `build_sim` via XcodeBuildMCP, `CodexBarMobile`, iPhone 17 simulator — passed
  with 0 warnings.
- `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` —
  passed 3 tests, 0 failures.
- `build_run_sim` with `UI_TEST_PREVIEW_DATA UI_TEST_SKIP_ONBOARDING` — app
  installed and launched on the iPhone 17 simulator; a light-mode simulator
  screenshot was captured for runtime smoke.
- `bash Scripts/lint.sh lint` — passed, including SwiftFormat, SwiftLint, parser
  audits, documentation link checks, and `Localizable.xcstrings`
  source-vs-catalog audit.
- `./Scripts/upload_ios_testflight.sh` — pre-flight lint passed, Release archive
  succeeded, App Store Connect export/upload succeeded.
- Archive path: `/tmp/CodexBarMobile-20260630-113022.xcarchive`.
- App Store Connect build check — `1.16.0 (170)` uploaded at
  `2026-06-30T11:33:12-07:00`, build id
  `f8efa2b1-d068-488e-a1eb-aa65882ccd7a`, `processingState=VALID`.

Home Screen QA follow-up on 2026-06-30:

- User QA found the previous TestFlight build was not actually validated
  through SpringBoard widget addition. Small and medium widgets could still
  show clipped headers, long provider error strings, and cramped rows even
  though build/test checks passed.
- Added a simulator-only widget timeline fixture so the widget extension shows
  deterministic loaded mock data when installed on iOS Simulator. Device and
  TestFlight builds still use CloudKit/KVS runtime data.
- Reworked small, medium, and large widget layouts to remove the duplicated
  brand header, shorten provider error subtitles to `Sync Error`, move errored
  providers after healthy providers, and avoid drawing stray progress bullets
  when usage is unavailable.
- Localized widget dashboard section labels that were still rendering in
  English under Simplified Chinese (`Providers`, `Errors`).
- Actual SpringBoard QA evidence, iPhone 17 simulator, Simplified Chinese
  locale:
  - Small widget added from the app/widget long-press menu:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_e753354b-5d7c-40bd-9df6-cd600354b941.jpg`.
  - Medium widget added from the same SpringBoard menu:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_9386ba7c-1c13-4227-99a6-aa41cd3fab5a.jpg`.
  - Large widget added from the same SpringBoard menu:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_a275976d-da14-420c-a2db-2af63b75a361.jpg`.
  - System `编辑小组件` panel for the large widget:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_9782e15c-9698-4260-a7e1-cc82d3ac1282.jpg`.
- Result: small, medium, and large Home Screen widgets render in the simulator
  with light appearance, localized edit/configuration labels, no long raw error
  text, and no visible row clipping in the tested default overview mode.
- Prepared corrective TestFlight build `1.16.0 (171)`.
- `bash Scripts/lint.sh lint` — passed, including SwiftFormat, SwiftLint,
  parser audits, documentation link checks, and `Localizable.xcstrings`
  source-vs-catalog audit.
- `build_sim` via XcodeBuildMCP, `CodexBarMobile`, iPhone 17 simulator —
  passed with 0 warnings.
- `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` —
  passed 3 tests, 0 failures. A first run with `CODE_SIGNING_ALLOWED=NO`
  failed before test bootstrap because the test host lacked iCloud/KVS
  entitlements; rerunning without that compile-only override passed.
- `build_run_sim` with `UI_TEST_PREVIEW_DATA UI_TEST_SKIP_ONBOARDING` — final
  build 171 installed and launched on the iPhone 17 simulator.
- `./Scripts/upload_ios_testflight.sh` — pre-flight lint passed, Release
  archive succeeded, App Store Connect export/upload succeeded.
- Archive path: `/tmp/CodexBarMobile-20260630-161504.xcarchive`.
- App Store Connect build check — `1.16.0 (171)` uploaded at
  `2026-06-30T16:18:33-07:00`, build id
  `8a216604-2d47-495c-b09b-6e5b799482cb`, `processingState=VALID`.

## Residual Risks

- Direct CloudKit reads from widgets can be budget-constrained. If widget freshness is poor in real use, switch to the deferred App Group cache path after explicit entitlement approval.
- Direct widget reads do not apply the app's local pending linkage/device lifecycle cache before CloudKit returns it. The app remains source of truth for the richest resolved view.
- New extension archive/upload may require Developer Portal capability/provisioning work.
