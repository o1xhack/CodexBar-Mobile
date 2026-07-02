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
| Config preservation | SpringBoard/AppIntent-edited mode and color style must not reset to Overview/Mono | Added in this audit; current-run SpringBoard UI test opens the real edit panel, shows the system picker, selects Today Cost, and verifies the Home Screen widget changes |
| No data / stale / error | Empty, stale, and authenticated-error states must have deterministic snapshots | Covered by `surfaces no-data, stale, and error states` |
| Real widget preview parity | Settings preview must frame the exact `CodexBarWidgetView` spacing, not an unrelated data browser | Current-run app preview screenshots captured on iPhone and iPad |
| Light/Dark | Widget background and foreground must follow system appearance | Current-run app-preview evidence captured; current-run real SpringBoard Light and Dark screenshots captured for the placed medium widget |
| Tinted/accented | Key metric/progress regions must be `widgetAccentable` and readable in tinted Home Screen mode | `CodexBarWidgetRenderMatrixTests` now renders loaded/state widgets with `widgetRenderingMode = .accented` and checks visible contrast; SpringBoard tinted visual still requires a direct system-state pass |
| Mono/Colorful | Both color styles must keep the native widget structure and avoid old dashboard clutter | Current-run Mono and Colorful app-preview evidence captured |
| Render matrix | Overview, Today Cost, Provider Focus, Sync Health must render for small/medium/large/iPad extra-large, Mono/Colorful, Light/Dark, and full-color/accented WidgetKit rendering modes | Covered by `CodexBarWidgetRenderMatrixTests`, which renders 128 loaded-state combinations through the exact `CodexBarWidgetView` and checks visible contrast plus Colorful full-color accent saturation |
| State render matrix | No-data, syncing, and error states must not go blank across supported families | Covered by `CodexBarWidgetRenderMatrixTests` error/no-data/syncing family pass in accented rendering mode with visible contrast checks |
| All modes on SpringBoard | Overview, Today Cost, Provider Focus, Sync Health must be verified in the real Home Screen configuration surface | App preview gallery captured through small/medium/large/iPad extra-large; current-run SpringBoard picker lists all four modes and one real mode switch to Today Cost is automated |
| iPad | Extra-large and regular iPad placements must not stretch/clamp incorrectly | Current-run iPad Pro 11-inch extra-large evidence captured |
| Localization | All user-facing strings must have en, zh-Hans, zh-Hant, ja translations | `bash Scripts/lint.sh lint` rerun passed; CodexBarMobile source-vs-catalog audit found all 358 source keys present |
| Packaging | Extension bundle must include WidgetKit extension point and AppIntents metadata | Current archive contains `CodexBarMobileWidgets.appex`; upload event succeeded without packaging errors |
| Release | TestFlight build must contain the final binary changes; docs/Todoist/PR must identify the exact build | Build 179 contains the final binary changes and is `VALID` on App Store Connect |

## Testing Plan For This Audit

1. Local static gates:
   - `bash Scripts/lint.sh lint`
   - `xcodebuild` or XcodeBuildMCP focused test for `WidgetSnapshotBuilderTests`
   - XcodeBuildMCP focused test for `CodexBarWidgetRenderMatrixTests`
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
- SpringBoard tinted/accented appearance is still a visual/system-context check. `ImageRenderer` now exercises WidgetKit accented rendering mode and catches blank/low-contrast branches, but it does not replace a real Home Screen tinted screenshot on a configured simulator/device.
- Widget preview screenshots can confirm spacing in the app, but they cannot replace real SpringBoard widget evidence because WidgetKit may apply container and rendering changes outside the app.
- `CodexBarWidgetRenderMatrixTests` forces every branch to render through `ImageRenderer` and now checks visible pixel contrast plus Colorful saturation, but it is not a pixel-diff/layout-overlap assertion. It prevents blank/crashing/disconnected/color-style-dead branches; visual spacing still needs screenshots or human/visual review.
- Full continuous SpringBoard switching across Provider Focus, Today Cost, and Sync Health was attempted, but the long chained UI test became unstable while reopening the system edit panel for the third switch. Do not mark this audit done on that basis; keep the stable gate at "real panel + all options listed + one real switch" until the long-chain path is made reliable.

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
- 2026-07-02: Added `CodexBarMobileUITests/testSpringBoardWidgetConfigurationPanelOpens` as an explicit local SpringBoard widget gate. It is skipped by default and runs only with `UI_TEST_SPRINGBOARD_WIDGET=1` / `TEST_RUNNER_UI_TEST_SPRINGBOARD_WIDGET=1` so CI does not assume a pre-placed Home Screen widget.
- 2026-07-02: XcodeBuildMCP focused UI test passed:
  - `test_sim -only-testing:CodexBarMobileUITests/CodexBarMobileUITests/testSpringBoardWidgetConfigurationPanelOpens` with `UI_TEST_SPRINGBOARD_WIDGET=1`
  - Result bundle: `/Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/result-bundles/test_sim_2026-07-02T09-01-00-111Z_pid82893_8891d19c.xcresult`
  - Exported attachments: `/tmp/codexbar-springboard-xcattachments-final3/`
  - `SpringBoard Widget Configuration Panel`: `/tmp/codexbar-springboard-xcattachments-final3/A2A4D250-A044-4690-A0C0-93587C498AD5.png`
  - `SpringBoard Widget Type Picker`: `/tmp/codexbar-springboard-xcattachments-final3/046906BE-9A32-479B-81B5-567EB668CCBF.png`
  - `SpringBoard Today Cost Configuration Selected`: `/tmp/codexbar-springboard-xcattachments-final3/2ED9BE72-7472-409E-8D1F-3F5FABCF08A8.png`
  - `SpringBoard Today Cost Widget`: `/tmp/codexbar-springboard-xcattachments-final3/AE4CCBDD-0B0F-4640-A220-7419A5B5BDC0.png`
- 2026-07-02: Re-ran XcodeBuildMCP data parity gate after user explicitly rejected user-driven validation as the backstop:
  - `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests`
  - Result: 9 passed, 0 failed, 0 skipped.
  - Result bundle: `/Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/result-bundles/test_sim_2026-07-02T09-12-23-606Z_pid82893_d8ab0fed.xcresult`
- 2026-07-02: Added `CodexBarWidgetRenderMatrixTests` so widget branches are checked before TestFlight/user screenshots:
  - Loaded state renders 4 modes × 4 families × 2 color styles × 2 color schemes through the exact `CodexBarWidgetView`.
  - Error, no-data, and syncing states render across all supported families.
  - XcodeBuildMCP focused test passed: `test_sim -only-testing:CodexBarMobileTests/CodexBarWidgetRenderMatrixTests`.
  - Result bundle: `/Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/result-bundles/test_sim_2026-07-02T09-24-58-517Z_pid82893_11f7e6c1.xcresult`
- 2026-07-02: Re-ran XcodeBuildMCP data parity gate after adding the render matrix:
  - `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests`
  - Result: 9 passed, 0 failed, 0 skipped.
  - Result bundle: `/Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/result-bundles/test_sim_2026-07-02T09-25-09-415Z_pid82893_404af98e.xcresult`
- 2026-07-02: Added widget-specific release checklist gates to `docs/RELEASE-CHECKLIST.md`: data parity must be tested with `WidgetSnapshotBuilderTests`, and widget layout/config changes require a real SpringBoard gate before TestFlight.
- 2026-07-02: Tightened the release checklist again so widget layout/config/rendering changes also require `CodexBarWidgetRenderMatrixTests`; user-visible screenshots are not an acceptable primary gate.
- 2026-07-02: Strengthened `CodexBarWidgetRenderMatrixTests` from nil-image smoke to pixel-level smoke:
  - Loaded and state renders must have foreground/background luminance contrast.
  - Colorful loaded-state renders must have visible accent saturation.
  - XcodeBuildMCP focused test passed: `test_sim -only-testing:CodexBarMobileTests/CodexBarWidgetRenderMatrixTests`.
  - Result bundle: `/Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/result-bundles/test_sim_2026-07-02T10-07-15-046Z_pid82893_ac368bbb.xcresult`
- 2026-07-02: Extended `CodexBarWidgetRenderMatrixTests` to include WidgetKit accented rendering mode:
  - Loaded state now renders 4 modes × 4 families × 2 color styles × 2 color schemes × 2 rendering modes (`.fullColor`, `.accented`) = 128 combinations.
  - Error, no-data, and syncing state renders now smoke-test accented rendering mode across supported families.
  - XcodeBuildMCP focused test passed: `test_sim -only-testing:CodexBarMobileTests/CodexBarWidgetRenderMatrixTests`.
  - Result bundle: `/Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/result-bundles/test_sim_2026-07-02T10-48-26-741Z_pid82893_740c933d.xcresult`
- 2026-07-02: Re-ran data parity gate after strengthening the render matrix:
  - `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests`
  - Result: 9 passed, 0 failed, 0 skipped.
  - Result bundle: `/Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/result-bundles/test_sim_2026-07-02T10-07-43-693Z_pid82893_fc86adeb.xcresult`
- 2026-07-02: Re-ran data parity gate after adding accented rendering coverage:
  - `test_sim -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests`
  - Result: 9 passed, 0 failed, 0 skipped.
  - Result bundle: `/Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/result-bundles/test_sim_2026-07-02T10-49-26-732Z_pid82893_fd24395f.xcresult`
- 2026-07-02: Re-ran the stable SpringBoard configuration gate after adding accented rendering coverage:
  - `test_sim -only-testing:CodexBarMobileUITests/CodexBarMobileUITests/testSpringBoardWidgetConfigurationPanelOpens` with `UI_TEST_SPRINGBOARD_WIDGET=1`
  - Result: 1 passed, 0 failed, 0 skipped.
  - Result bundle: `/Users/yuxiao/Library/Developer/XcodeBuildMCP/workspaces/CodexBar-feb004820bff/result-bundles/test_sim_2026-07-02T10-49-38-917Z_pid82893_1b7b4c06.xcresult`
  - Exported attachments: `/tmp/codexbar-springboard-xcattachments-accented-pass/`
  - `SpringBoard Widget Type Picker`: `/tmp/codexbar-springboard-xcattachments-accented-pass/96D266C6-A89A-43FE-AACC-17EEA6C3768E.png`
  - `SpringBoard Today Cost Configuration Selected`: `/tmp/codexbar-springboard-xcattachments-accented-pass/12758D1B-D93B-4CE0-A1A1-B46C4A7CC746.png`
  - `SpringBoard Today Cost Widget`: `/tmp/codexbar-springboard-xcattachments-accented-pass/A0767AAB-381A-4031-8998-2FDE5591C692.png`
- 2026-07-02: Current-run real SpringBoard appearance evidence:
  - Light: `/tmp/codexbar-widget-springboard-light-current.png`
  - Dark: `/tmp/codexbar-widget-springboard-dark-current.png`
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
