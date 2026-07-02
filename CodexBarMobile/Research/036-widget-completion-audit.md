# 036 - Widget Completion Audit

Status: `in-progress`
Date: 2026-07-02
Scope: CodexBar Mobile widget suite completion gate for data correctness, layout quality, configuration, localization, and release handoff.

## Goal

Make widget quality verifiable before it reaches the user. User screenshots must be treated as bug reports after a gate failure, not as the gate itself.

This audit covers the full widget feature surface:

- `Overview`, `Today Cost`, `Provider Focus`, and `Sync Health`.
- Small, medium, large, and iPad extra-large WidgetKit families.
- iPhone narrow/regular/Pro Max style widths and iPad layouts.
- Light, Dark, tinted/accented Home Screen appearances, and both app-configured color styles.
- Synced data correctness across CloudKit multi-device records and KVS fallback.
- App Settings widget preview parity with the real widget view.
- TestFlight/App Store Connect/Todoist/GitHub handoff evidence.

## External Requirements Checked

Apple references used as the product/API baseline:

- Configurable widgets should use App Intents / `WidgetConfigurationIntent`: https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget
- Widgets must provide the right system background through WidgetKit background APIs: https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background
- Widgets need to adapt to additional contexts and appearances: https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances
- Tinted/accented rendering should use system accentable regions instead of hand-rolled color assumptions: https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass
- `AppIntentConfiguration` is the expected configuration entry point for AppIntent-backed widgets: https://developer.apple.com/documentation/widgetkit/appintentconfiguration/init(kind:intent:provider:content:)

## Current Implementation Facts

- Widget kind: `CodexBarStatusWidget`.
- Configuration: `CodexBarWidgetConfigurationIntent` with `mode` and `colorStyle`.
- Supported families: `.systemSmall`, `.systemMedium`, `.systemLarge`, `.systemExtraLarge`.
- Shared reducer: `CodexBarWidgetSnapshotBuilder` now calls `ProviderSnapshotMerger.mergeSnapshots`, matching the app's Cost dashboard merge semantics.
- Runtime timeline: CloudKit multi-device snapshots first, then KVS fallback.
- Visual rendering: app preview and real widget both use `CodexBarWidgetView`.
- Packaging: `CodexBarMobileWidgets.appex` is generated from `project.yml` and embedded by the app target.
- Entitlements: widget extension has Production CloudKit/KVS entitlements; no App Group entitlement is used in this release line.

## Acceptance Matrix

| Area | Required proof | Current status |
|------|----------------|----------------|
| Data parity | Widget Today totals must equal Cost dashboard totals for the same synced snapshots | Covered by `keeps Today Cost widget totals in parity with the Cost dashboard` |
| Multi-device local-cost providers | Same provider/account across devices must sum when cost is local-device generated | Covered by `sums local-cost provider accounts across devices` |
| Account-level providers | Account-level provider cost must use latest account record and avoid double counting | Covered by `uses account-level latest cost without double counting` |
| Screenshot-shaped Codex regression | `$20.59 + $80.53` must render as `$101.12`, not `$20.59` | Covered by `matches cost dashboard today totals for multi-device Codex data` |
| CloudKit empty fallback | KVS fallback data must stay visible when CloudKit returns no records | Added in this audit |
| CloudKit error fallback | KVS fallback totals must stay visible with stale/error context when CloudKit errors | Added in this audit |
| Config preservation | SpringBoard/AppIntent-edited mode and color style must not reset to Overview/Mono | Added in this audit |
| No data / stale / error | Empty, stale, and authenticated-error states must have deterministic snapshots | Covered by `surfaces no-data, stale, and error states` |
| Real widget preview parity | Settings preview must frame the exact `CodexBarWidgetView` spacing, not an unrelated data browser | Current-run app preview screenshots captured on iPhone and iPad |
| Light/Dark | Widget background and foreground must follow system appearance | Current-run Light and Dark app-preview evidence captured |
| Tinted/accented | Key metric/progress regions must be `widgetAccentable` and readable in tinted Home Screen mode | Code path present; SpringBoard tinted visual still requires a direct system-state pass |
| Mono/Colorful | Both color styles must keep the native widget structure and avoid old dashboard clutter | Current-run Mono and Colorful app-preview evidence captured |
| All modes | Overview, Today Cost, Provider Focus, Sync Health must be verified across families | App preview gallery captured through small/medium/large/iPad extra-large; SpringBoard mode-switch editing was partially blocked by AX exposure |
| iPad | Extra-large and regular iPad placements must not stretch/clamp incorrectly | Current-run iPad Pro 11-inch extra-large evidence captured |
| Localization | All user-facing strings must have en, zh-Hans, zh-Hant, ja translations | `bash Scripts/lint.sh lint` rerun passed; CodexBarMobile source-vs-catalog audit found all 358 source keys present |
| Packaging | Extension bundle must include WidgetKit extension point and AppIntents metadata | Current archive contains `CodexBarMobileWidgets.appex`; upload event succeeded without packaging errors |
| Release | TestFlight build must contain the final binary changes; docs/Todoist/PR must identify the exact build | Build 179 contains the final binary changes and is `VALID` on App Store Connect |

## Testing Plan For This Audit

1. Local static gates:
   - `bash Scripts/lint.sh lint`
   - `xcodebuild` or XcodeBuildMCP focused test for `WidgetSnapshotBuilderTests`
   - broader sync merge test slice if reducer code changes
2. Simulator app gate:
   - build/run `CodexBarMobile` with deterministic preview data
   - open Settings -> Widget Setting
   - capture the app preview gallery in Light and Dark
   - switch Mono/Colorful and small/medium/large/extra-large where available
3. SpringBoard widget gate:
   - add or inspect actual Home Screen widgets for small/medium/large on iPhone
   - edit widget mode to Today Cost, Provider Focus, and Sync Health
   - verify mode changes are reflected in the actual widget body
   - repeat at least one large/dark and one iPad extra-large case
4. Release handoff gate:
   - if product code changes, bump build, update changelog/release notes/metadata, archive, upload, and poll ASC to `VALID`
   - if only tests/docs change after a valid uploaded product binary, record why no new upload is needed
   - update PR/Todoist with the exact evidence

## Open Risks

- Direct widget CloudKit/KVS reads still do not use an app-authored App Group cache. This is acceptable only because App Group entitlement work was explicitly deferred earlier; it remains the better long-term architecture for publishing the app's fully resolved local view to the widget.
- SpringBoard tinted/accented appearance is a visual/system-context check. Unit tests can verify data and configuration, but not whether iOS renders tinted foreground contrast acceptably.
- Widget preview screenshots can confirm spacing in the app, but they cannot replace real SpringBoard widget evidence because WidgetKit may apply container and rendering changes outside the app.

## Current Audit Log

- 2026-07-02: Started full completion audit after user correctly rejected user-driven screenshot validation as insufficient.
- 2026-07-02: Confirmed PR #36 is open, clean, and green on GitHub Actions before adding this audit layer.
- 2026-07-02: Added tests for KVS fallback visibility and AppIntent mode/color preservation.
- 2026-07-02: `xcodebuild test -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,id=EB507A39-11B8-42F2-8A68-F1334CD5A7EB' -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests` passed 9 tests.
- 2026-07-02: `xcodebuild test ... -only-testing:CodexBarMobileTests/CloudKitMergeTests -only-testing:CodexBarMobileTests/AccountIdentityMergeTests -only-testing:CodexBarMobileTests/LinkageRecordMergeTests` passed 71 tests.
- 2026-07-02: `bash Scripts/lint.sh lint` passed; CodexBarMobile i18n source-vs-catalog audit reported all 358 source keys present.
- 2026-07-02: XcodeBuildMCP `build_run_sim` passed on iPhone 17 Pro Max with 0 warnings.
- 2026-07-02: XcodeBuildMCP app preview evidence, iPhone 17 Pro Max:
  - Medium, Light, Mono: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_dd9b6c6e-2df5-4548-9358-7f4d1452ef9b.jpg`
  - Small, Light, Mono: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_b7834401-f25f-4503-8bb7-e58427cf4b92.jpg`
  - Large, Light, Mono, before this audit fix showed the Today Cost gap: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_d4b95816-1ec9-4863-aa52-5edfa3fb9316.jpg`
  - Large, Light, Mono, after this audit fix: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_55b51a8e-fbb5-479f-847b-57a0636f2ffa.jpg`
  - Large, Dark, Mono: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_80c2f6c4-41d9-4026-8ed7-936fca258337.jpg`
  - Large, Dark, Colorful: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_d59b387f-a8f1-4879-9db3-48cdd3668eb4.jpg`
  - Large, Light, Colorful: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_68b46ecf-b8a5-4f86-a306-04e42b5716cf.jpg`
- 2026-07-02: XcodeBuildMCP `build_run_sim` passed on iPad Pro 11-inch (M5) with 0 warnings.
- 2026-07-02: XcodeBuildMCP app preview evidence, iPad Pro 11-inch:
  - Extra-large, Light, Mono, before this audit fix showed sparse Today Cost left-column spacing: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_85e47fec-cf80-4f90-a84b-45f2ffe00ab8.jpg`
  - Extra-large, Light, Mono, after this audit fix: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_73acf391-953a-461a-b70b-f8e470340138.jpg`
- 2026-07-02: SpringBoard evidence, iPhone 17 Pro Max:
  - Real Home Screen large Overview widget rendered outside the app preview: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_895584cf-f0c0-4a02-988a-d30a40b0ecd4.jpg`
  - Real SpringBoard edit panel exposed `Widget Type = Overview` and `Color Style = Mono`: `/var/folders/b0/y4gmssvd7wx0775zy1l3w1tr0000gn/T/screenshot_optimized_9d47e47c-df8c-4c59-8406-2f114d2fa774.jpg`
  - Attempted SpringBoard edit value selection through AX; the floating edit panel did not expose tappable value refs, and coordinate clicking was rejected as unreliable because macOS focused a different Simulator window.
- 2026-07-02: Re-ran SpringBoard semantic automation after the full test pass:
  - Home Screen exposed the CodexBar widget elementRef and long-press menu targets, including `com.apple.springboardhome.application-shortcut-item.configure-widget`.
  - Tapping the configure-widget target dismissed back to Home Screen instead of opening a stable configuration panel on this simulator run.
  - Result: actual SpringBoard render is verified; automated SpringBoard configuration switching is still not a current-run pass.
- 2026-07-02: Full iOS test suite passed on iPhone 17 Pro Max simulator:
  - `xcodebuild test -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -destination 'platform=iOS Simulator,id=EB507A39-11B8-42F2-8A68-F1334CD5A7EB'`
  - Swift tests: 480 tests in 37 suites passed.
  - UI tests: 3 tests passed.
  - Final result: `** TEST SUCCEEDED **`.
- 2026-07-02: Release archive/upload evidence:
  - `./Scripts/upload_ios_testflight.sh` completed pre-flight lint, archive, export, and upload.
  - Archive path: `/tmp/CodexBarMobile-20260702-003408.xcarchive`.
  - Archive `Info.plist`: `CFBundleShortVersionString=1.16.0`, `CFBundleVersion=179`, upload event `Uploaded to Apple`, no errors.
  - App Store Connect REST API: build id `ab87cb07-4a04-494d-96d3-2d4399506b97`, version `179`, pre-release version `1.16.0`, `processingState=VALID`, uploaded `2026-07-02T00:37:10-07:00`.
  - `xcrun altool --build-status --delivery-id ab87cb07-4a04-494d-96d3-2d4399506b97`: `BUILD-STATUS: VALID`, `IMPORT-STATUS: VALID`, `IS-ON-APP-STORE-CONNECT: true`.
