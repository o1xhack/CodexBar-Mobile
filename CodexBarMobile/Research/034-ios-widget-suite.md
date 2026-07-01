# 034 — iOS WidgetKit Suite

Status: `done`
Date: 2026-06-28
Scope: CodexBar Mobile iOS widgets for small, medium, large, and iPad extra-large Home Screen families.

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

All four modes support `.systemSmall`, `.systemMedium`, `.systemLarge`, and iPad `.systemExtraLarge`. Layout is not a stretched single view:

- Small: one hero metric or one top provider.
- Medium: metric strip plus provider/cost/sync rows.
- Large: dashboard combining metric strip, provider rows, and sync health rows.
- Extra Large: two-column iPad layout combining primary metrics with provider rows.

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

Cross-device widget QA follow-up on 2026-06-30:

- User QA found the previous widget visual pass was still incomplete: it
  validated the default Overview path but not every configurable mode, did not
  cover iPad extra-large widgets, and did not prove the layout adapted across
  narrow iPhone, Pro Max, and iPad Home Screen sizes.
- Moved `CodexBarWidgetConfigurationIntent` into `CodexBarWidgetShared/` and
  built it into both the app target and widget extension. This fixes SpringBoard
  configuration metadata so edited widgets can produce the correct App Intent
  action at runtime.
- Removed the explicit `.overview` reset from the App Intent default
  initializer. Before this fix, the SpringBoard edit panel could save
  `Provider Focus`, `Today Cost`, or `Sync Health`, but the timeline view still
  fell back to Overview.
- Added `.systemExtraLarge` support and an iPad-specific two-column layout.
- Tuned medium Provider Focus and Sync Health layouts so 2x4 widgets do not
  clip content after editing the widget mode.
- Actual SpringBoard QA evidence:
  - iPhone 17e small widget:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_3a8766ac-233a-45a2-b28d-225979c47b60.jpg`.
  - iPhone 17 Pro Max medium Overview:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_f03686d3-491e-4a95-92ec-4c239c3bd198.jpg`.
  - iPhone 17 Pro Max medium Provider Focus after editing the widget:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_99c822a3-50a4-451d-85c7-09bfff74a7cb.jpg`.
  - iPhone 17 Pro Max medium Today Cost after editing the widget:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_7beb4206-ac1b-4e04-837d-51b2dd88b801.jpg`.
  - iPhone 17 Pro Max medium Sync Health after editing the widget:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_5a765baa-2644-499f-97af-f4f4b828b0cd.jpg`.
  - iPhone 17 Pro Max large Overview:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_bdda66f1-00ed-492a-8480-ffe805d971c9.jpg`.
  - iPhone 17 Pro Max large Overview in Dark appearance:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_553690e3-b21e-477a-abe4-d5f782c85bf7.jpg`.
  - iPad Pro 11-inch extra-large two-column widget:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_d242f87d-14ce-4d87-a90e-3fbf1a8b417e.jpg`.
- Prepared corrective TestFlight build `1.16.0 (172)`.
- `xcodegen generate` — regenerated `CodexBarMobile.xcodeproj` from
  `project.yml`.
- `bash Scripts/lint.sh lint` — passed, including SwiftFormat, SwiftLint,
  parser audits, documentation link checks, and `Localizable.xcstrings`
  source-vs-catalog audit.
- `build_sim` via XcodeBuildMCP, `CodexBarMobile`, iPhone 17 Pro Max simulator
  — passed with 0 warnings.
- `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` —
  passed 3 tests, 0 failures. Test compilation still emits existing Swift 6
  actor/#require warnings in unrelated test files.
- `build_run_sim` with `UI_TEST_PREVIEW_DATA UI_TEST_SKIP_ONBOARDING` — final
  build installed and launched on the iPhone 17 Pro Max simulator with 0
  warnings.
- Bundle inspection — `Metadata.appintents` exists in both
  `CodexBarMobile.app` and `CodexBarMobileWidgets.appex`, app version is
  `1.16.0 (172)`, and the widget extension point remains
  `com.apple.widgetkit-extension`.
- `./Scripts/upload_ios_testflight.sh` — pre-flight lint passed, Release
  archive succeeded, App Store Connect export/upload succeeded.
- Archive path: `/tmp/CodexBarMobile-20260630-181013.xcarchive`.
- App Store Connect build check — `1.16.0 (172)` uploaded at
  `2026-06-30T18:13:25-07:00`, build id
  `83c53dbb-edb3-43b8-8657-f324f47a7845`, `processingState=VALID`.

Content hierarchy and in-app preview follow-up on 2026-07-01:

- User QA found the widget pass was still too header-heavy and that medium
  Today Cost mixed 30-day usage context into a widget that should answer
  today's spend at a glance. The app also lacked a first-party place to preview
  every widget size/mode before adding widgets to the Home Screen.
- Moved `CodexBarWidgetView` and `CodexBarWidgetEntry` into
  `CodexBarWidgetShared/` so the app Settings preview and the WidgetKit
  extension render the same SwiftUI view rather than separate approximations.
- Removed redundant loaded-state mode headers from small, medium, large, and
  iPad extra-large widget layouts. Loading, empty, and error states still keep
  explicit labels because those states need explanatory context.
- Changed Today Cost widgets to use today's spend, today's tokens, and only
  providers with positive `todayCostUSD`; they no longer fall back to 30-day
  cost/provider rows in the Today Cost mode.
- Hid the loaded footer when the widget body already contains sync timing:
  Sync Health across all families, plus large/iPad extra-large Overview and
  Provider Focus where `syncSummaryStrip` or `syncHealthRows` already includes
  Last Sync.
- Added `Settings → Widget Setting → Preview`, with a segmented size control
  and swipeable Overview, Today Cost, Provider Focus, and Sync Health pages.
  iPhone shows small/medium/large; iPad also shows iPad extra-large.
- Prepared iOS build metadata for the next TestFlight upload:
  `MARKETING_VERSION` remains `1.16.0`, `CURRENT_PROJECT_VERSION` is `173`.
- `./Scripts/upload_ios_testflight.sh` — pre-flight lint passed, Release archive
  succeeded, and App Store Connect export/upload succeeded.
- App Store Connect build check — `1.16.0 (173)` uploaded at
  `2026-07-01T13:54:52-07:00`, build id
  `5b34d477-ca61-4d88-9672-6b49c5382d0e`, `processingState=VALID`.
- Validation:
  - `xcodegen generate` — regenerated `CodexBarMobile.xcodeproj` from
    `project.yml`.
  - `build_sim` via XcodeBuildMCP, iPhone 17 Pro Max simulator — passed with
    0 warnings.
  - `build_run_sim` with
    `UI_TEST_PREVIEW_DATA UI_TEST_SKIP_ONBOARDING UI_TEST_RESET_DEFAULTS` —
    passed with 0 warnings on iPhone 17 Pro Max, iPad Pro 11-inch, and the
    Pro Max simulator that retained a SpringBoard widget.
  - `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` —
    passed 3 tests, 0 failures.
  - `bash Scripts/lint.sh lint` — passed, including SwiftFormat, SwiftLint,
    parser audits, documentation link checks, and
    `Localizable.xcstrings` source-vs-catalog audit.
  - `python3 -m json.tool CodexBarMobile/CodexBarMobile/Localizable.xcstrings`
    — passed.
  - `git diff --check` — passed.
- App preview QA evidence:
  - iPhone 17 Pro Max medium Overview:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_c675d1a6-0788-4b54-9b60-72c591e4c486.jpg`.
  - iPhone 17 Pro Max medium Today Cost:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_972ca9cc-7aaa-4e6e-99f6-3c1186183d1a.jpg`.
  - iPhone 17 Pro Max medium Provider Focus:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_6ebb54a8-7773-4040-94dc-f32133934e30.jpg`.
  - iPhone 17 Pro Max medium Sync Health after footer dedupe:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_c5aba08f-baa7-47f2-8cc6-517033cbb12d.jpg`.
  - iPhone 17 Pro Max small Sync Health:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_7cc6cd9e-aa4c-4e81-b495-4fd7f8506ef5.jpg`.
  - iPhone 17 Pro Max large Sync Health:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_babc2ded-ca74-4a52-9722-c56ac897f18a.jpg`.
  - iPad Pro 11-inch iPad extra-large Overview after footer dedupe:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_25af89c3-7c20-44b0-b752-628b45999a7b.jpg`.
- SpringBoard QA evidence:
  - iPhone 17 Pro Max existing Home Screen large widget after installing the
    final build:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_2ba9a2f6-a7a6-4ffa-aed4-cf479c12661e.jpg`.

Spacing follow-up on 2026-07-01:

- User QA found the large Home Screen widget still left too much blank space
  below the provider/summary content, and medium Today Cost pushed `Updated`
  too far away when only one or two provider rows were visible.
- Removed the unbounded loaded-state `Spacer` from medium and iPad extra-large
  widget bodies, so the footer uses fixed section spacing instead of stretching
  to the bottom of sparse widgets.
- Gave large widgets fixed provider row slots for the three visible rows. This
  keeps the intended three-slot cap while making the rows occupy the central
  area consistently instead of leaving a large empty lower band.
- Capped large Today Cost provider rows at three to match the large-widget slot
  model; iPad extra-large keeps the wider four-row side column.
- Tightened small widget padding from `12` to `10` points to reduce the
  perceived outer-frame waste.
- Prepared iOS build metadata for the next TestFlight upload:
  `MARKETING_VERSION` remains `1.16.0`, `CURRENT_PROJECT_VERSION` is `174`.
- Validation:
  - `build_run_sim` via XcodeBuildMCP on iPhone 17 Pro Max — passed with
    0 warnings.
  - `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` —
    passed 3 tests, 0 failures.
  - `build_run_sim` via XcodeBuildMCP on iPad Pro 11-inch — passed with
    0 warnings.
- App preview QA evidence:
  - iPhone 17 Pro Max medium Overview after removing the footer spacer:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_ad703b06-ddb4-4ed2-9419-d751c77a6ef0.jpg`.
- SpringBoard QA evidence:
  - iPhone 17 Pro Max large Overview after fixed three-row slots:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_4b66e29f-3efe-4a6c-a19c-be0330a97394.jpg`.

In-app preview framing follow-up on 2026-07-01:

- User clarified that `Settings -> Widget Setting` should be an inspection
  surface for actual widget frames. The size selector should be followed by
  one framed preview per widget mode so the user can inspect the outside frame,
  inner spacing, and sparse-data layout, rather than swiping through a data
  browser.
- Replaced the preview `PageTabView` with a vertical gallery of `Overview`,
  `Today Cost`, `Provider Focus`, and `Sync Health` framed previews under the
  selected size.
- Kept the preview content path on the same shared `CodexBarWidgetView` used by
  the WidgetKit extension and passed the selected `WidgetFamily` explicitly.
  The preview shell only adds the mode label, visible frame stroke, and shadow;
  it no longer adds vertical spacers that can stretch or center the widget
  differently from the real Home Screen widget.
- Prepared iOS build metadata for the next TestFlight upload:
  `MARKETING_VERSION` remains `1.16.0`, `CURRENT_PROJECT_VERSION` is `175`.
- Validation:
  - `build_run_sim` via XcodeBuildMCP on iPad Pro 11-inch — passed with
    0 warnings.
  - `build_run_sim` via XcodeBuildMCP on iPhone 17 Pro Max — passed with
    0 warnings.
  - `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` —
    passed 3 tests, 0 failures. The run still reports existing Swift 6
    actor/#require warnings in unrelated test files.
  - `bash Scripts/lint.sh lint` — passed, including SwiftFormat, SwiftLint,
    parser audits, documentation link checks, and `Localizable.xcstrings`
    source-vs-catalog audit.
  - `python3 -m json.tool CodexBarMobile/CodexBarMobile/Localizable.xcstrings`
    and `git diff --check` — passed.
- App preview QA evidence:
  - iPad Pro 11-inch medium gallery with one framed preview per widget mode:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_532d3b3a-1bb0-4223-97c4-802c8593ae0b.jpg`.
  - iPad Pro 11-inch iPad extra-large gallery:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_a5456d22-d89f-4ea2-8ab4-4fd90f888c66.jpg`.
  - iPhone 17 Pro Max medium gallery:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_c1462e11-49cb-42a5-b9ea-2cd9f0e630ca.jpg`.
  - iPhone 17 Pro Max large gallery after scrolling to inspect sparse
    Today Cost and Provider Focus frames:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_68b23412-f407-4512-8071-85e26a193af6.jpg`.
  - iPhone 17 Pro Max small gallery:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_0dc2a883-01f7-4a5c-9701-c5f7a0bd40c9.jpg`.
- `./Scripts/upload_ios_testflight.sh` — pre-flight lint passed, Release
  archive succeeded, and App Store Connect export/upload succeeded.
- Archive path: `/tmp/CodexBarMobile-20260701-150821.xcarchive`.
- App Store Connect build check — `1.16.0 (175)` uploaded at
  `2026-07-01T15:11:09-07:00`, build id
  `ee7c2ff7-b379-4821-b1aa-0b7ec074e5a4`, `processingState=VALID`.

Widget color style follow-up on 2026-07-01:

- Added a second `WidgetConfigurationIntent` parameter,
  `CodexBarWidgetColorStyle`, so each placed Home Screen widget can keep the
  default `Mono` appearance or opt into a new `Colorful` appearance through
  the system widget edit sheet.
- Kept `Mono` as the default to preserve existing widgets and the native
  Light/Dark/tinted behavior from the prior visual-design pass.
- Designed `Colorful` as a restrained accent layer rather than a return to the
  old multi-color dashboard: neutral widget backgrounds and primary text stay
  system-like, while key metrics, provider markers, and progress fills receive
  mode-appropriate accent colors.
- Added a matching `Color Style` segmented control to
  `Settings -> Widget Setting`; the in-app framed previews pass the same
  configuration into `CodexBarWidgetView` as the WidgetKit extension.
- Prepared iOS build metadata for the next TestFlight upload:
  `MARKETING_VERSION` remains `1.16.0`, `CURRENT_PROJECT_VERSION` is `176`.
- Validation:
  - `python3 -m json.tool CodexBarMobile/CodexBarMobile/Localizable.xcstrings`
    — passed.
  - `bash Scripts/lint.sh audit-i18n` — passed; all 357 source keys are present
    and all supported locales are translated.
  - `bash Scripts/lint.sh lint` — passed, including SwiftFormat, SwiftLint,
    parser audits, documentation link checks, and
    `Localizable.xcstrings` source-vs-catalog audit.
  - `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` —
    passed 3 tests, 0 failures. The run still reports existing Swift 6
    actor/#require warnings in unrelated test files.
  - `build_run_sim` via XcodeBuildMCP on iPhone 17 Pro Max — passed with
    0 warnings.
  - `build_run_sim` via XcodeBuildMCP on iPad Pro 11-inch — passed with
    0 warnings.
- App preview QA evidence:
  - iPhone 17 Pro Max medium Mono gallery:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_afeb2442-fcd2-474d-a7bb-0d22b07cc5a7.jpg`.
  - iPhone 17 Pro Max medium Colorful gallery:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_92153353-55f2-4679-865d-91d41f7b6706.jpg`.
  - iPhone 17 Pro Max large Colorful gallery:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_733084fa-9147-459c-a161-3d13f9def384.jpg`.
  - iPhone 17 Pro Max large Colorful gallery in Dark appearance:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_2b0bd75c-aba6-46f5-a1ae-a4344307c684.jpg`.
  - iPad Pro 11-inch iPad extra-large Colorful gallery:
    `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_bea97f96-906b-4918-acf5-b355dae419f6.jpg`.
- `./Scripts/upload_ios_testflight.sh` — pre-flight lint passed, Release
  archive succeeded, and App Store Connect export/upload succeeded.
- Archive path: `/tmp/CodexBarMobile-20260701-162102.xcarchive`.
- App Store Connect build check — `1.16.0 (176)` uploaded at
  `2026-07-01T16:24:22-07:00`, build id
  `d7c12b94-0e91-475a-9f90-6ae0cd92999b`, `processingState=VALID`.

## Residual Risks

- Direct CloudKit reads from widgets can be budget-constrained. If widget freshness is poor in real use, switch to the deferred App Group cache path after explicit entitlement approval.
- Direct widget reads do not apply the app's local pending linkage/device lifecycle cache before CloudKit returns it. The app remains source of truth for the richest resolved view.
