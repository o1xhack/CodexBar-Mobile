# 058 — iOS 2.2.0 Widget Redesign and Token Activity Heatmaps

Status: `done` (PR #152; clean CR, build 221 uploaded and bound to 2.2.0)
Date: 2026-09-25
Branch: `feature/ios-220-widget-redesign`

## Product requirement

Make the Home Screen widget suite glanceable and visually quieter. Add configurable
Token Activity heatmaps for small, medium, large, and iPad extra-large families.
Small and medium show one selected source; large shows two selected sources;
extra-large offers independently chosen sources. Each widget instance retains
its own selection. The source menu must reflect providers with real token data,
including All, Claude Code, and Codex when available.

## Current-state findings

- `CodexBarWidgets.swift` exposes one configurable widget kind in all four
  families. Its modes are Overview, Provider Focus, Today Cost, and Sync Health.
  Configuration currently has only Mode and Mono/Colorful Style.
- `CodexBarWidgetView.swift` combines metrics, provider rows, sync rows, dividers,
  labels, and footer across large layouts. The single widget kind is stretched
  across unrelated information goals, which is the main density problem.
- The widget timeline fetches CloudKit/KVS and builds `CodexBarWidgetSnapshot`.
  That snapshot stores only current totals and six top providers, not daily
  history. Existing simulator mock data is independent of the app's heatmap.
- The app's `TokenActivitySection` loads up to 365 days through
  `CostHistoryWorker.tokenActivity` when the local cost-window ledger is enabled;
  otherwise it uses current synced blobs. `TokenActivity.series` and
  `TokenActivity.dailyTotals` preserve unknown, known zero, and partial lower
  bounds; `TokenActivityColorScale` ranks positive days by annual quartiles.
  A widget reading only the current sync blob can therefore disagree with the
  app if the local ledger holds older history.
- Neither iOS app nor widget extension currently has an App Group entitlement.
  `ModelContainerFactory` has a prospective group path but falls back to app
  storage today. The widget cannot safely assume it can read the app's store.
  Crucially, granting the entitlement would make `defaultStoreURL()` switch
  automatically to the group path on the next launch; there is no store-file
  migration in that factory. A naive capability addition would strand existing
  local history in the old app sandbox.
- The widget bundle already compiles the shared localization catalog. The
  shipping deployment target is iOS 17, and `.systemExtraLarge` is for iPad.
- Upstream and fork open-PR searches for widget/heatmap prior art returned none
  on 2026-09-25. This is an iOS-only feature; Mac code remains out of scope.

## Apple design references

- [Human Interface Guidelines: Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets):
  prioritize essential, timely, glanceable information and size-appropriate
  composition.
- [Widget families](https://developer.apple.com/documentation/widgetkit/widgetfamily/):
  small can focus on one critical item, while large can hold more complex charts.
- [Accented rendering and Liquid Glass](https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass):
  test system-tinted/clear appearances, removable backgrounds, and legible
  primary/accent groups rather than assuming full-color rendering.
- [Making a configurable widget](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget):
  use an `AppEntity`/`EntityQuery` for source choices that change with synced
  data; `suggestedEntities()` feeds the system widget edit sheet.

## Proposed experience

1. Keep the existing status widget available to installed users, but simplify
   each mode to one primary answer and only the minimum context needed to
   interpret it. Remove redundant metric strips, divider chains, decorative
   symbols, and unrelated sync rows. Show a concise freshness/error cue only
   when it changes the meaning of the selected content.
2. Add two focused Token Activity widget kinds: a single-source widget for
   small/medium and a comparison widget for large/extra-large. This keeps the
   edit sheet from showing unused second-source controls on small widgets.
   The comparison widget has exactly two ordered, independently selected
   sources in both families; extra-large gives each panel more time and room.
   Default selections should be useful without editing; duplicate selections
   should be prevented or handled clearly. Each placed widget stores its own
   App Intent configuration.
3. The source choices come from the currently available token-bearing provider
   identities, plus All. Display names match the app; internally use stable
   provider IDs and account identity where needed, not labels. If a configured
   provider disappears, show a localized unavailable state rather than
   silently switching to another provider. Implement the dynamic list through
   a widget-visible `AppEntity` query, backed by the published projection.
4. Render a compact calendar heatmap with a time window appropriate to the
   family. Small emphasizes recent activity; medium adds temporal labels;
   large compares two independent source panels; extra-large uses its space
   for longer/clearer independently selected panels. No horizontal scroll or
   shrunk 365-day chart. Visual intensity follows the app's existing token
   semantics and annual scale. Unknown and confirmed zero use distinct visual
   treatments and accessible labels. A partial day remains a lower bound.
5. Adapt to light, dark, tinted/clear, and Dynamic Type. Keep colors subordinate
   to shape, contrast, and labels. Tapping opens the relevant in-app Token
   Activity detail when feasible; the widget remains useful without a tap.

### Layout targets for first rendered prototype

| Family | Selection | Primary visual | Supporting information |
|---|---|---|---|
| Small | One source | Recent 5-week calendar grid | Source name and one concise activity summary |
| Medium | One source | Recent 12-week calendar grid | Source name, time range, and compact legend |
| Large | Two sources | Two 10-to-12-week grids | One header per source, one shared explanation of missing days |
| Extra-large | Two sources | Two longer grids, side by side when space permits | Clear source headers and readable month markers |

These are density targets, not fixed day counts: measure actual WidgetKit
dimensions and Dynamic Type before choosing the final week count. Preserve
seven-day columns and touch-free readability; do not add a KPI dashboard around
the grids. For the status widget, a small family shows one value and a short
label; medium and larger families may add one relevant comparison or trend but
must not fill extra space with unrelated metrics.

## Data design and decision point

**Recommended:** The main app materializes a small, versioned, atomic read-only
Token Activity projection after its normal history refresh. The widget reads
that projection from an App Group container and never opens or mutates the
SwiftData ledger. This keeps per-day and provider identity semantics aligned
with the app, preserves past days no longer in the latest sync blob, and avoids
running ledger migration/aggregation in a short-lived widget extension. The
App Group entitlement and provisioning change must be validated before release.
The iOS SwiftData store must stay at its existing app-sandbox location in 2.2.0;
only the new read-only projection goes into the App Group. Explicitly adjust
`ModelContainerFactory` before enabling the capability and test an upgrade with
preexisting history, including cold launch and failed projection publication.
The projection records source identity/name, day keys, known/zero/partial/unknown
state, annual scale inputs, generation time, and app refresh state. Read failures
must not become fabricated zero days. On cold install before the first app
publication, show a clear setup/no-history state; do not silently substitute a
shorter CloudKit view and call it equivalent.

Alternative: rebuild from CloudKit inside the extension. This is simpler to
provision but fails historical parity whenever local ledger history exceeds
Mac's current sync window. It is unsuitable for the requested consistency bar.

## Implementation slices after design approval

1. Introduce a shared, deterministic Token Activity projection and provider
   selection model. Test identity, device/account merge, day-key/time-zone,
   known zero, unknown, partial totals, stale data, and disappearing sources.
2. Publish the projection from the app's existing history refresh path, then
   read it in widget timelines through an atomic App Group file. Keep widget
   refresh bounded and cache-aware. Pin the current SwiftData store URL so the
   new entitlement does not relocate or hide existing history. Verify this
   upgrade path plus entitlement/signing in Production.
3. Add focused App Intent configuration and responsive heatmap views for all
   four families. Simplify existing status modes without changing their meaning.
4. Update four-language strings, `project.yml` to 2.2.0 with the next coherent
   build number, changelog, and one 2.2.0 in-app release-note block.
5. Regenerate project, compile and run focused data/render/configuration tests,
   then inspect actual SpringBoard widgets and edit sheets on iPhone/iPad in
   normal and tinted appearances. Record simulator and physical-device evidence
   separately; run release checklist gates that apply to this data path.

## Acceptance evidence

- Every family displays the selected source(s) and the correct number of panels;
  independent widget instances retain distinct configurations after refresh.
- Day values and unknown/zero/lower-bound semantics agree with the app for the
  same fixture and date range, including a ledger history longer than the
  current sync blob.
- No clutter, clipping, or unreadable cell states in loaded, syncing, stale,
  empty, missing-provider, and error cases across four locales and supported
  Home Screen appearances.
- Actual SpringBoard placement/editing proves the configuration choices and
  rendered result. Unit previews alone do not meet this gate.
- Source version, tests, simulator findings, physical-device findings, signing
  status, and remaining release gaps are recorded before handoff. Push, merge,
  TestFlight upload, and public release remain separately authorized actions.

## 2026-09-25 implementation and QA record

- Version 2.2.0 (214) now contains the two heatmap widget kinds, App Intent
  source choices, a versioned App Group projection, a pinned app-sandbox
  SwiftData URL, and simplified status layouts. The widget computes no ledger
  history itself. Failed refreshes retain the previous published history and
  label it as an error.
- `ios220-widget-focused7.xcresult`: five XCTest render cases and nine Swift
  Testing cases across projection and SwiftData storage passed. The render
  matrix covers four families, light/dark, full-color/accented, and loaded,
  syncing, empty, and error states. Exported images were inspected; the
  extra-large comparison was vertically centered after review. The final
  `Scripts/lint.sh lint` run passed with zero violations; all four languages
  are complete and all 363 source keys are present.
- On the iOS 26.5 `CodexBar Compact QA` simulator, SpringBoard placed and
  rendered the small widget from synthetic 365-day data in the simulator App
  Group container. The edit picker exposed All, Claude Code, and Codex.
  Selecting Claude Code remained visible when the edit sheet was reopened.
  Large comparison also loaded as All + Claude Code. Its two independent
  picker fields were visible, and changing the second to Codex remained
  visible when reopening the edit sheet. The displayed timelines still showed
  their previous selections immediately after editing. Subsequent test app
  launch overwrote the synthetic projection with an error state, so
  configuration-to-render propagation remains to be verified with a normally
  signed build and a stable projection.
- The iPad Pro 13-inch iOS 27.0 simulator showed the extra-large comparison
  in the system gallery and accepted it on SpringBoard. Its ad-hoc build
  could not load the synthetic App Group data and displayed the localized
  read-error state. A separate offscreen extra-large render with the same
  SwiftUI view showed both selected panels without clipping. Medium loaded
  layout was also checked offscreen, but not placed on SpringBoard.
- Follow-up implementation on 2026-09-25 aligned the widget publication task's
  refresh key with `TokenActivitySection`: local-history clear tombstones,
  source revisions, and producer/reader day boundaries now trigger a new
  projection. The medium and comparison layouts show compact month ranges
  after a full localized date range proved too long in rendered Chinese
  previews. `ios220-widget-focused10.xcresult` passed six XCTest cases and ten
  Swift Testing cases, including a historical ledger point absent from the
  current sync blob and missing/duplicate-source rendering.
- A manually ad-hoc-signed app with App Group entitlements could be installed
  but the system rejected its widget extension at launch with
  `OS_REASON_CODESIGNING` / restricted entitlements. A normal simulator build
  launched the extension and rendered the synthetic shared-container fixture;
  this does not prove a valid development/distribution profile or physical
  device App Group access. Production signing and real-device verification
  remain release gates. The connected iPhone was not modified for this QA run.
- On iPad, the scheduled WidgetKit timeline refresh loaded the synthetic
  projection and rendered the extra-large comparison on SpringBoard as All +
  Claude Code. The second source was changed to Codex in the edit sheet, and
  SpringBoard immediately rendered All + Codex; reopening the editor confirmed
  the saved value. This proves the edit and immediate snapshot path on that
  simulator. Visual review found the 9-point extra-large cells too small on
  the 13-inch iPad; a fixed 14-point change then clipped both panels in the
  narrow extra-large render. The final layout derives cell size from widget
  width. `ios220-widget-focused15.xcresult` passed all six render cases, and
  its exported narrow extra-large image was visually inspected without
  clipping.
- A subsequent unsigned simulator reinstall removed the simulator's synthetic
  App Group container. Its picker then showed only All, exposing that the
  query depended entirely on the projection file. The query now always offers
  All, Claude Code, and Codex, and appends any additional projected sources.
  The unsigned simulator cannot verify App Group persistence across reinstall;
  signed-device QA is still needed.
- The iPhone simulator also placed a loaded medium widget from the synthetic
  projection, with a readable title, active-day summary, month range, and
  12-week grid. Its edit sheet offered the three standard sources and saved a
  Codex selection, but the rendered timeline still displayed All. `chronod`
  serialized the selected `codex` entity; the extension logged
  `WidgetActivitySourceEntity is not a registered AppEntity identifier` during
  resolution. A scheduled 15-minute timeline refresh did not change the
  displayed source. The App Intent entity types now live only in the widget
  extension target, avoiding duplicate app/extension metadata definitions.
  An unsigned reinstall removed the simulator App Group registration and a
  further simulator probe still emitted the entity-registration diagnostic.
  Source-to-render propagation therefore remains unverified until a build
  signed with the real team/profile can be tested. The picker fallback itself
  remains available before the first projection is published.
- An iOS 27.0 iPad simulator test-host run exited before XCTest bootstrap:
  the crash stack points to `CKContainer.init` after an unsigned test launch
  without CloudKit entitlements. This is test infrastructure evidence, not a
  failure of the heatmap assertions. A later iOS 26.5 iPhone simulator run
  also exited before XCTest bootstrap after an unsigned reinstall removed its
  App Group registration. Xcode's `Sign to Run Locally` simulator build put
  CloudKit and App Group values in a simulated `.xcent` but signed the actual
  binary with an empty entitlement dictionary. Manually signing with those
  simulated entitlements let the app install but the simulator denied launch
  for restricted entitlements. The test host now recognizes XCTest launch,
  uses existing preview data, and defers `CloudSyncManager.shared` until an
  actual sync operation. This keeps unit/render tests free of live CloudKit
  initialization: `ios220-widget-focused14.xcresult` passed six XCTest and
  four Swift Testing cases, `ios220-model-store-focused.xcresult` passed six
  Swift Testing cases, and `ios220-widget-focused15.xcresult` passed the six
  render cases after the adaptive layout fix. Signed-device QA is still
  required for the App Group and App Intent selection pipeline.
- Apple Developer inspection found the widget extension App ID had iCloud but
  no App Groups capability. The existing Xcode-managed widget development
  profile also lacked the group entitlement. On 2026-09-25, the extension App
  ID was assigned the existing `group.com.o1xhack.codexbar` group. A new
  development profile (`7f06dbc8-b960-492d-a2ef-538677eaaabe`) includes the
  iPhone Air and the App Group; Xcode then refreshed its managed widget profile
  (`3e43cea1-65a8-4af7-be93-b652110f13f2`). A device Debug build succeeded
  with `-allowProvisioningUpdates`. Inspection of the built app and widget
  extension shows the same App Group and Production CloudKit entitlements.
  The build was installed on the paired iPhone Air without removing app data.
  The device screen was off during the first `sim-use` preflight and screenshot,
  so no physical widget behavior has yet been claimed.
- An App Store Connect widget profile was not generated: the Developer Portal
  currently offers no distribution certificate for that profile type. This is
  a future archive/upload preparation item, not part of the Debug-device
  signing proof. Do not infer distribution readiness from the development build.
- The widget's active-day summary previously counted the last `weeks × 7` data
  points, while its grid begins on a Monday. Early in a week that included
  days outside the visible grid. Both the summary and grid now use the same
  Monday-aligned start date. `ios220-summary-test.xcresult` passed all five
  projection tests, including the boundary and future-day case. Full lint
  passed with zero violations and all four locales complete. The updated
  signed Debug build was installed on the iPhone Air without removing data;
  the device remained locked, so physical widget behavior is still unverified.
- The signed widget extension's extracted App Intents metadata contains both
  source entities, their queries, and the single/comparison configuration
  parameters. This rules out missing compile-time metadata in that artifact;
  only a signed SpringBoard configuration change can prove runtime resolution.
  The source picker now uses exactly the sources in a nonempty published
  projection (plus All). Before the first projection, it offers All, Claude
  Code, and Codex so the edit sheet is usable during setup. A disappeared
  configured source still resolves to the explicit unavailable state. The
  device Debug build compiled and was reinstalled after this change; the
  iPhone Air still needs to be unlocked for its Home Screen QA.
- A second comparison widget was placed on page 2 of the iPadOS 27 simulator
  beside the existing extra-large comparison on page 1. Its editor saved
  Codex + Claude Code, while reopening the first widget had previously saved
  All + Codex. The new large widget remained at its placeholder, including
  after a simulator reboot. `CodexBarMobileWidgets` logged an XPC interruption
  while linking the App Intent, followed by `No AppIntent in timeline(for:with:)`
  and WidgetKit's empty-view-collection error. The first extra-large widget
  continued to display its cached All + Codex timeline. Thus the simulator
  proves the two edit-sheet values can differ, but does **not** prove that the
  second selection rendered independently. A signed-device run must verify
  that full path; do not count cached first-widget pixels as fresh timeline
  success for the second widget.
- The device-signed extension artifact contains the new configuration intents,
  source entities, and queries in `Metadata.appintents`. The main app artifact
  does not contain those new intent definitions because their source file is
  extension-only; the simulator's serialized App Intent descriptor names the
  main app bundle. This is a plausible registration mismatch, but the observed
  XPC interruption and unsigned simulator leave causality unproven. Apple
  documents [shared intent code across app and extension targets](https://developer.apple.com/documentation/appintents/app-extension)
  and [execution target selection](https://developer.apple.com/documentation/appintents/intentexecutiontargets);
  it does not establish that duplicating these widget
  configuration types would fix this particular runtime error. Preserve the
  signed-device test as the decisive gate before changing intent ownership.
- The signed 2.2.0 (214) Debug build was then exercised on the paired iPhone Air
  through iPhone Mirroring. The device's CodexBar app showed real Token Activity
  history. The widget gallery offered the existing status widget and the new
  Token Activity small, medium, and large families. All three heatmap sizes
  were placed on the actual Home Screen and rendered real data; the earlier
  unsigned-simulator App Intent registration diagnostic did not reproduce on
  this signed device.
- The small widget's edit sheet offered All, Claude Code, and Codex. Selecting
  Codex produced 33 active days in its five-week grid; selecting Claude Code
  produced one active day and the sparse pattern visible in the app's Token
  Activity detail. Reopening the editor retained the chosen source. A separate
  medium widget on another Home Screen page showed All with 76 active days in
  12 weeks; selecting Codex updated its title and grid while retaining 76
  active days. The medium selection was independent of the small widget's
  Claude Code selection.
- The large comparison widget initially rendered All (76 active days) above
  Claude Code (one active day). Its editor exposed two separate source fields.
  Changing the first to Codex yielded Codex (76) above Claude Code (one), and
  reopening the editor confirmed both stored choices. Changing only the second
  to All changed the lower panel to All (76) while the upper Codex panel stayed
  unchanged. The second source was restored to Claude Code and the real Home
  Screen again showed Codex (76) above Claude Code (one). This verifies both
  configuration fields, per-instance persistence, and configuration-to-timeline
  propagation on a normally signed physical device.
- Extra-large is iPad-only. The iPadOS simulator loaded its All + Codex
  comparison on SpringBoard and retained edited choices, and the final adaptive
  layout passed narrow-width render inspection. No signed physical iPad was
  available for an additional device check. Distribution signing and upload
  remain a separate release task; the Developer Portal currently has no
  distribution certificate for the widget profile. No push, PR, TestFlight
  upload, or public release was performed in this development task.

## 2026-09-26 visual revision after Home Screen review

The first signed-device screenshots exposed a layout mistake: medium spent most
of its width on a narrow text column, while large used 12-week grids with wide
left margins and a decorative rule between sources. The blue default tint also
ignored the app's Codex/Claude provider colors. The user rejected that visual
hierarchy and asked for a denser, GitHub-like contribution calendar that fits
Apple's current widget appearance.

- [GitHub's contribution calendar](https://docs.github.com/en/account-and-profile/concepts/contributions-on-your-profile)
  makes the day grid the primary visual. The revised medium widget uses 27 full
  Monday-aligned weeks, or 189 day positions. Even when the current week has
  six future days, 183 past dates remain visible. At the narrow 338-point render
  size, 11-point side margins and 2-point cell gaps leave approximately 9.8-point
  square cells. This is a six-month calendar without horizontal scrolling.
- The large widget now stacks two full-width 18-week grids (126 day positions
  each), with neither a side column nor a dividing rule. Extra-large stacks two
  full-width 38-week grids (266 positions each) on iPad. Small remains a five-
  week compact grid. Source name leads each panel; active-day count is secondary.
- The widget extension compiles the app's `ProviderColorPalette` source. The
  published projection carries an optional synced icon tint for each provider,
  so built-in and Mac-supplied provider colors match the app; All remains blue.
  Unknown dates use a restrained outline, confirmed zero a neutral fill, and
  positive days a quartile-scaled provider color. Stale/sync/error replaces the
  secondary count only when it changes the meaning of a displayed history.
- [Apple's widget margins guidance](https://developer.apple.com/design/human-interface-guidelines/widgets)
  permits 11-point margins for graphics. The heatmap configurations disable
  WidgetKit's default content margins and supply 11 points themselves. The
  system owns the removable widget background and [Liquid Glass/tinted
  rendering](https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass);
  the content uses accent groups rather than another custom blur layer.
- The iOS 26.5 compact simulator's focused render/projection run passed eight
  tests with 12 light, dark, and accented family images exported for inspection.
  The signed Debug build was installed on the paired iPhone Air without clearing
  app data. Its Home Screen showed the revised small Claude widget, plus a
  second page with the full-width medium Codex grid and the large Codex +
  Claude comparison. The latter had aligned left edges and no dividing rule.
  The physical Home Screen capture is at
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/WidgetScreenshots/ios-220-large-medium-iphone-air.png`.

## 2026-09-26 sparse-state and typography refinement

Signed iPhone review found that the earlier 0.6-point outline on every unknown
day looked like an empty form grid when Claude Code had only two active days.
The source tint itself already came from `ProviderColorPalette`, but the widget
applied a different opacity curve from the in-app Token Activity grid and
colored the full source heading. Thus the hue was shared while the visible
intensity and text treatment differed.

- Unknown days now use a very light neutral fill without a stroke; confirmed
  zero days use a slightly stronger neutral fill. Future dates stay invisible.
  Positive days use the projection's quartile intensity directly, matching the
  in-app `TokenActivityGrid` opacity instead of applying another curve.
- Source labels use the system primary foreground and a semibold subheadline.
  A six-point provider-color marker carries the accent. The active-day count
  was removed from the normal widget view; sync, stale, or error state still
  appears as secondary text when needed. In accented mode, WidgetKit owns the
  content tint and the source marker joins its accent group.
- The production widget view was rendered in all four sizes with light, dark,
  and tinted appearances. The signed build was installed on the paired iPhone
  Air and inspected with real sparse Claude Code data on small and large
  widgets, alongside the medium Codex grid. Captures:
  `WidgetScreenshots/ios-220-neutral-empty-small-iphone-air.png` and
  `WidgetScreenshots/ios-220-neutral-empty-large-medium-iphone-air.png` under
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/`.

## 2026-09-26 TestFlight submission

- Uploaded iOS 2.2.0 (214) from source commit
  `78bf2e4cd092a2d649beea65117f5bb6a18053c5` on
  `feature/ios-220-widget-redesign`. Xcode archive and App Store Connect
  upload succeeded; App Store Connect build
  `31a610b1-936c-4d44-9533-08d01c06e1fc` reached `VALID` at
  `2026-09-26T13:07:24-07:00`.
- Archive:
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-20260926-130321/CodexBarMobile.xcarchive`.
  The archived app reports 2.2.0 (214); its main executable SHA-256 is
  `03d58b4f92c9edb8793f717a6fd3786d56acd7e0d9fd83269d12af8b162347f4`.
  App and widget extension archive signatures include the same App Group and
  CloudKit `Production` environment. The compiled 120-pixel app icon has no
  alpha channel. The CloudKit schema diff against the latest published tag
  found no new fields or record types, so no Production schema deploy is needed.
- The focused iOS simulator suite passed 36 test cases with zero failures,
  covering widget render families, snapshot building, and activity projection.
  The upload preflight passed repository lint (2,683 Swift files, zero
  violations), four-language iOS localization (363 source keys), and the iOS
  upload contract. Signed physical iPhone QA from the preceding visual pass
  covers the small, medium, and large widgets. Extra-large was verified on an
  iPad simulator; no signed physical iPad check was available for this beta.
- This TestFlight upload did not push the task branch, open or merge a PR, or
  publish an App Store release. Public release remains a separate gate.

## 2026-09-26 repair after TestFlight feedback

The owner reported that build 214's Token Activity widgets showed no data and
that long-press source selection did not work. The sparse visual design also had
an unaligned blue source dot. Treat the earlier signed-device screenshots as
visual evidence only; they did not prove the distributed binary's selected
configuration reached its timeline provider.

- On a clean iOS 26.5 simulator, the 214 `AppEntity` picker saved `codex` in
  SpringBoard while the timeline still received `all`. Several App Intent
  variants reproduced that mismatch. A fixed SiriKit intent definition and
  `IntentTimelineProvider` produced a three-choice menu on a clean iOS 27.0
  iPhone Air simulator, matching the owner's phone OS. Selecting Codex changed
  the medium widget's actual home-screen title and synthetic App Group heatmap;
  changing the first source of a large widget showed Codex above Claude Code,
  each with a distinct pattern and app palette color. The extension log also
  recorded the selected enum value in `getTimeline`.
- The system edit controls were still English in an existing simulator
  installation after adding localized intent resources. A clean install with
  the intent definition under `Base.lproj` and companion strings for English,
  Simplified Chinese, Traditional Chinese, and Japanese displayed `数据源` and
  `全部` in the Chinese edit sheet. The existing cached edit sheet was not valid
  evidence of the new localization.
- An upgrade experiment placed a 214 App Intent heatmap widget, then installed
  the repaired build using the same widget kind. The old widget kept a cached
  image and its edit sheet said `无法加载` because the serialized configuration
  formats differ. The replacement uses V2 widget kinds; users must remove the
  old Token Activity widgets and add them again. The 2.2.0 release notes state
  that action explicitly.
- The blue source dot was removed. The main app now writes current synced days
  to its App Group projection before reading the longer ledger and preserves
  the previous projection during a `syncing` phase. Simulator heatmaps use a
  synthetic projection, so real owner-account CloudKit-to-widget loading still
  needs beta validation.

### Build 215 verification

- On an iOS 27.0 iPhone Air simulator, a freshly added V2 medium widget was
  edited from All to Codex. The home-screen title and cells changed to the
  Codex source; see `ios27-v2-codex-final.png` in the BuildScratch evidence.
- On the same simulator, a V2 large widget exposed separate first and second
  source controls. Selecting Codex and Claude Code rendered distinct magenta
  and orange histories on the home screen; see `ios27-v2-compare-final.png`.
- On an iPadOS 27.0 iPad Pro 13-inch simulator, a V2 extra-large widget exposed
  the same independent controls. Selecting Codex and Claude Code changed both
  live histories; see `ipad-xl-codex-final.png`. All of these histories were
  synthetic App Group data, not the owner's CloudKit data.
- The focused `WidgetSnapshotBuilderTests`, `WidgetActivityProjectionTests`,
  and `CodexBarWidgetRenderMatrixTests` passed. `swift build`, repository lint,
  and four-language catalog audit passed. The full Mac `swift test` process
  crashed under broad parallel execution with failures in unrelated Mac suites;
  this is a recorded beta validation gap, not evidence that those suites pass.
- CloudKit Production entitlements remain set on the iOS app and widget
  extension. This repair changed no CloudKit record type or schema field, so
  the Production schema needs no deploy for build 215.

### Build 215 TestFlight upload

- Archived and uploaded iOS 2.2.0 (215) from source commit
  `f4b03083466851c3f794a0cfa7a40f131724b8d3` on
  `feature/ios-220-widget-redesign`. Xcode archive and App Store Connect
  export/upload succeeded. The archived main app and widget extension both
  report build 215; their signatures include CloudKit `Production` and the
  same `group.com.o1xhack.codexbar` App Group.
- Archive:
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-20260926-230000/CodexBarMobile.xcarchive`.
  Archived main executable SHA-256:
  `939514b6980dc5d4794c39ee7ad71f53a7fcad74fe1a204c6971b1ec8e5dbd7a`.
- App Store Connect build `290b4d40-8552-4052-9189-f7d327937540`
  reached `VALID`; `uploadedDate=2026-09-26T23:03:26-07:00`.
  The source commit was not pushed, and this beta upload did not create or
  merge a PR or publish an App Store release.
- Remaining beta QA: install build 215 on the owner's phone, remove and re-add
  old build-214 Token Activity widgets, then confirm the owner's real synced
  CloudKit history and source choice appear on the home screen. The simulator
  verification above covers synthetic App Group projection and WidgetKit
  configuration, not real account sync.

## 2026-09-27 owner layout feedback and refinement

The owner installed build 215 and reported that the core widget behavior looks
mostly correct. All heatmap cells feel too tightly packed. The small widget's
cells are too large, and its date order runs sideways rather than ending with
today in the bottom-right corner. Medium and large widgets have too much empty
space above the source name and below the grid, while their horizontal margins
are narrow. This is owner feedback on the installed build, not a new physical
device QA result collected by the agent.

Implementation approach:

- Keep the calendar-week order in medium, large, and extra-large widgets. Give
  them one consistent inset on every edge, and use the available panel height
  to increase row spacing while keeping the title near the rounded top edge.
- Render the small widget as 35 consecutive days in five rows of seven. The
  oldest date starts at top-left and today is bottom-right. Cap its square size
  and center its title/grid block within the same horizontal boundaries.
- Increase spacing in the in-app Token Activity heatmap as well, because the
  owner described every heatmap as too dense. Preserve the existing source
  colors and distinguish unknown days from recorded zero days.
- Verify date ordering with a non-Sunday reference day and visually inspect
  all four production widget sizes after the change.

### Build 216 local verification

- The small widget now places 35 consecutive dates in a seven-column grid.
  A Wednesday reference-date test confirms the final cell is today, rather
  than relying on the reference date falling on a Sunday.
- The iOS 27 iPhone Air SpringBoard rendered a small Codex widget after its
  source was changed in the actual system edit sheet. Its five rows have
  smaller cells and 5-point gaps; the latest day is at bottom right. The same
  simulator rendered a medium Codex widget and a large Codex + Claude Code
  comparison with balanced 16-point card insets and wider cell spacing.
- The iPad Pro 13-inch iPadOS 27 SpringBoard rendered the extra-large
  comparison with the same inset and wider gaps. Evidence images in
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/` are
  `widget-layout-216-small-codex-final.png`,
  `widget-layout-216-large-medium-final.png`, and
  `widget-layout-216-ipad-final.png`. All displayed day values came from a
  synthetic App Group projection, not the owner's CloudKit account.
- Focused `WidgetActivityProjectionTests`, `CodexBarWidgetRenderMatrixTests`,
  and `WidgetSnapshotBuilderTests` passed: 31 Swift Testing cases and six
  XCTest render cases. The owner independently reported that build 215 was
  installed and its basic widget behavior looked correct, then supplied the
  layout refinements above. Build 216 still needs owner-device visual QA.

### Build 216 TestFlight upload

- Repository lint and four-language source/catalog audit passed with zero
  violations. CloudKit Production entitlements and the matching App Group
  are present in the archived main app and widget extension. The 215-to-216
  diff changes no CloudKit record type, field, query, index, or subscription;
  no Production schema deploy is required.
- Archived and uploaded iOS 2.2.0 (216) from source commit
  `7d2cd31bcd098223e4958ef1f4b8525c558b02c8` on
  `feature/ios-220-widget-redesign`. Both the app and widget extension in the
  archive report build 216. Xcode cloud signing and upload succeeded.
- Archive:
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-20260927-102430/CodexBarMobile.xcarchive`.
  Archived main executable SHA-256:
  `a77a20d3443b2ffd8e3c1a68eda6b0db710c53772d8315459978fedcc37ddf45`.
- App Store Connect build `36954fdc-847e-456f-ae73-7eca0fe63510`
  reached `VALID`; `uploadedDate=2026-09-27T10:28:14-07:00`.
  The task branch was not pushed, and this beta upload did not create or
  merge a PR or publish an App Store release.
- Owner-device validation remains: install build 216, inspect small/medium/
  large heatmaps and the chosen sources on real synced data, and confirm the
  same spacing in the app's Token Activity view. Simulator screenshots prove
  layout and configuration with synthetic day values only.

## 2026-09-27 follow-up on small-widget direction

The owner clarified that the small widget must fill recent days **upward**:
today is the bottom-right cell, yesterday is immediately above it, and the
day before that is one more cell above. Build 216 instead filled rows from
left to right, so three recent days appeared along the bottom row. The five
rows also left uneven top/bottom space in the small card. Medium and large
were accepted visually and should retain their current layout.

The small-widget correction uses seven rows and seven columns (49 days),
ordered down each column before moving right. Its cell size is constrained by
the available card height as well as width, so the title plus seven rows fit
within the same 16-point vertical inset used by the larger widgets. A
non-Sunday date test pins the last three days in the rightmost column.

The owner also reports that tapping Codex inside CodexBar often fails. The
specific entry point is being clarified separately; a simulator tap on the
Usage tab's demo Codex card did open the Codex detail view, so that one
synthetic path does not yet reproduce the reported failure.

Local small-widget evidence: `widget-layout-217.xcresult` passed 31 Swift
Testing cases and six XCTest render cases, including the upward date-order
assertion. On an iOS 27 iPhone Air SpringBoard, editing a freshly placed
small widget to Claude Code with only 2026-09-25, 26, and 27 present in a
synthetic projection produced three cells in the rightmost column, ending
at bottom right. The screenshot is
`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/widget-layout-217-claude-three-days-edit.png`.
The app and widget are still build 216 locally at this point; this is not
owner-device evidence or a new TestFlight upload.

### Build 217 TestFlight upload

- Final build-217 focused tests passed: 31 Swift Testing cases and six XCTest
  render cases. Repository lint passed with zero violations, and the updated
  release note has all four translations. The corrected iPhone SpringBoard
  screenshot above proves the three-day column visually with synthetic data.
- Archived and uploaded 2.2.0 (217) from source commit
  `fc8534b130ea1a062dca0efe0af0b3052df486f9` on
  `feature/ios-220-widget-redesign`. Main app and widget extension both
  report build 217 and CloudKit `Production`; this layout-only change needs
  no Production schema deploy.
- Archive:
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-20260927-111655/CodexBarMobile.xcarchive`.
  Archived main executable SHA-256:
  `bf7854e07da0e617e8c67dc5ec6ff090883e0152ee094628c36856ba6e50e937`.
- App Store Connect build `3d750a1b-93df-49a6-8ed6-a7570a5d357b`
  reached `VALID`; `uploadedDate=2026-09-27T11:21:02-07:00`.
  The task branch remains local; this beta upload did not merge or publish
  the app.
- At the time of upload, owner-device layout QA and the Codex tap report
  remained open. The latter was clarified and exercised in the follow-up
  below.

## 2026-09-27 owner clarification and build 218

The owner clarified that both issues concern the **small Home Screen widget**.
The edit-sheet complaint is specifically the source value on the back of the
widget: touching it sometimes closes the choice menu without giving a usable
chance to pick All, Claude Code, or Codex. The earlier Usage-card diagnosis
does not apply.

The build-217 screenshot shows a roughly 29-point horizontal inset versus
17–19 points above and below the visible content. This came from fixing cell
size to the available height and then centering a narrower seven-column grid.
The small layout now uses nine columns and seven rows (63 days): the cell size
comes from the card width after a 16-point inset on each side, while the row
gap fills the available height after the title. A small-only title glyph offset
accounts for its font's invisible top leading. The medium, large, and extra-
large layouts are unchanged. The date-order test now covers the 63-day window
and still pins today, yesterday, and the day before in the rightmost column.

The iOS 27 simulator's native edit sheet showed the three SiriKit source
choices. A fast second tap at the source button's coordinates landed on the
menu's first row, selected All, and dismissed the menu. The paired iPhone Air's
iPhone Mirroring showed the same edit path: a single tap opened all three
choices; selecting Codex updated the real Home Screen widget and selecting
Claude Code afterward restored its prior state. Tapping the original button
position again while the menu was open selected All and closed it. This is a
concrete accidental-selection path. WidgetKit constructs the edit UI from the
intent definition; the app cannot set its popover hit region. Build 218 changes
the edit-sheet description to explicitly say to tap the current source once,
then choose from the list. It does not claim to replace the system menu.

The phone inspected through Mirroring had a development-installed 2.2.0 build
whose bundle build number was 214; its widget code and cached state cannot be
used as proof of the uploaded 217 artifact. The build-218 visual change still
requires a new SpringBoard render, archive validation, and owner beta QA.

### Build 218 local verification

- The focused projection, widget render, and snapshot-builder test run passed
  (`widget-218-final.xcresult`); repository lint passed with zero violations,
  and the changed strings have all four required translations.
- An iOS 27 iPhone Air SpringBoard rendered build 218's nine-column small
  Codex widget with the title and grid visually aligned to the same inset on
  every side. The synthetic seven active days occupy the rightmost column,
  newest at bottom right. Screenshot:
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/widget-small-218-after-select-settled.png`.
- The native long-press Edit Widget sheet showed the new one-tap guidance and
  offered All, Claude Code, and Codex. Selecting Codex rendered that source.
  One separate simulator widget retained a cached no-data timeline when switched
  to Claude Code despite the synthetic projection containing three days; this
  is not evidence that the build 218 owner-device data path is validated.
  Physical beta validation must check both source choices with real data.

### Build 218 TestFlight upload

- Uploaded 2.2.0 (218) from source commit
  `1760f0e4a8a4980398054b071afd6347dbf88e02` on the local
  `feature/ios-220-widget-redesign` branch. No push, PR, merge, or public
  release was performed.
- Archive:
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-20260927-120220/CodexBarMobile.xcarchive`.
  Archived main executable SHA-256:
  `bae7152b166e430e1520e0c2614092d58946660c06a07deb68a22ef7b809fa30`.
  Both the main app and widget extension are build 218. The signed app uses
  CloudKit `Production`. This widget layout/text update introduces no CloudKit
  record schema change and needs no Production schema deploy.
- Xcode reported `ARCHIVE SUCCEEDED` and `EXPORT SUCCEEDED`. App Store Connect
  build `6f0bf3a4-68b6-4ae3-a282-a56c78f3cd06` reached `VALID` with
  `uploadedDate=2026-09-27T12:05:46-07:00`.
- The paired owner phone was only inspected with an older development build
  (214). Build 218 still needs owner-device TestFlight verification of the
  small widget's real source data, appearance, and edit-sheet selection.

## 2026-09-27 spacing and collapsed-row follow-up

The owner reports that build 218's small and especially medium heatmaps have
too much space between cells relative to cell size. At the render-test sizes,
the medium widget used 24 columns in a 306-point content width: 8.44-point
cells, 4.5-point column gaps, and the capped 7.5-point row gap. Extra-large
used approximately 9.51-point cells and 4.5-point gaps in both directions.
The medium's row gap was almost as tall as the cell, confirming the visual
inconsistency. The small widget's 5-point column gap and height-filling row
gap also inflated white space around its nine-column grid.

The revised target keeps the same card inset and seven-row reading order. A
20-column medium grid gives 140 days, approximately 11-point cells, and
4.5-point gaps on both axes. This trades four weeks for much more legible
cells. The nine-column small grid keeps 63 days, uses a 3.5-point column gap
and caps row gaps at 4.5 points; its cells grow within the same content box.
Large and extra-large layouts remain as previously accepted. Rendered
light/dark/tinted images and the real SpringBoard grid must be inspected again.

The focused build-219 projection, render-matrix, and collapsed-name tests
passed on the iOS 27 iPhone Air simulator. Inspected production-view render
attachments for all four families: the new medium grid's 20 columns fill its
width with larger cells and approximately equal 4.5-point row/column gaps;
the small grid retains 63-day order with smaller gaps; large and extra-large
look unchanged. The images are in
`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/widget-219-attachments/`.
The iOS 27 SpringBoard edit sheet exposed the same three source choices after
changing an installed small widget to medium; selecting Codex updated the edit
control. That simulator widget retained its cached `noData` timeline after a
synthetic App Group file was injected, so this Home Screen view does not prove
the refreshed build-219 grid. The rendered production view above is the visual
evidence for its spacing.

The owner also asks that collapsed "Others" entries reveal the first few
hidden names, for example Codex and Claude Code. The Cost dashboard has
top-five-plus-Others sections for provider share, model/service mix, budgets,
and subscription utilization; share cards also aggregate a provider tail.
These previews will list at most two distinct tail labels in parentheses,
with an ellipsis if more distinct labels remain. Existing counts and drill-
down behavior stay available.

### Build 219 TestFlight upload

- Focused iOS tests passed for the projection/layout, widget rendering matrix,
  collapsed-name preview, and `WidgetSnapshotBuilderTests`. Repository lint and
  the four-language catalog audit passed. The simulator's SpringBoard source
  picker was exercised; its cached no-data timeline and a subsequent simulator
  boot/data-migration failure prevented a trustworthy placed-widget image of
  build 219. The production-view images above show the geometry with synthetic
  data. Owner-device TestFlight appearance and real-data checks remain open.
- Uploaded 2.2.0 (219) from source commit
  `4ba243668ac35d6998328af3c5d6850f158fed3f` on the local
  `feature/ios-220-widget-redesign` branch. No push, PR, merge, or public
  release was performed.
- Archive:
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-20260927-164505/CodexBarMobile.xcarchive`.
  Archived main executable SHA-256:
  `dae48fa150f212617ce9ee4371fbf721f83d087cafbd2ac0cd6813ea624275c6`.
  Main app and widget extension both report build 219; the signed app uses
  CloudKit `Production`. No CloudKit record schema change was introduced.
- Xcode reported `ARCHIVE SUCCEEDED` and `EXPORT SUCCEEDED`. App Store Connect
  build `6adacd85-c7f1-45ed-9e65-3ebadc1809cf` reached `VALID` with
  `uploadedDate=2026-09-27T16:49:01-07:00`.

## 2026-09-28 release candidate 2.2.0 (220)

- Source commit: `1201f9a89fb4d2f1f1485190ebcbd746dd940b53` on
  `feature/ios-220-widget-redesign`. The app now presents the current release
  notes once after a marketing-version change, keeps a visible Setup button at
  the top, and opens Setup Guide only when requested. The empty sync state no
  longer defaults to the full guide. Full release-note history remains in
  Settings.
- The focused UI test
  `testVersionUpdateShowsReleaseNotesAndSetupGuideOnDemand` passed twice on
  Simulator: fresh install showed the 2.2.0 notes, Setup opened the guide,
  dismissing the notes recorded the version, and relaunch did not show them a
  second time. The second result bundle is
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/ios-220-release-notes-ui-2.xcresult`.
  The launch-notes screenshot is
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/ios-220-release-notes-attachments-2/DB644F79-3ECF-4ED9-B79D-293F251750D2.png`.
  The Setup Guide screenshot is
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/ios-220-release-notes-attachments-2/1E272333-AF2A-4124-A550-11DF72CDD516.png`.
- `bash Scripts/lint.sh lint` passed across 2,683 files with zero violations;
  the four-language catalog has all 368 source keys translated. The app,
  widget, and push-extension archive targets report version 2.2.0, build 220.
- Xcode archive and cloud-signing upload succeeded. Archive:
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-20260928-105507/CodexBarMobile.xcarchive`.
  Archived main executable SHA-256:
  `4b41b6ce5fe6d44da39308431737a1bed808d5b001a2ca5e3a76e75a8c3fb271`.
  `codesign --verify --deep --strict` passed; the signed app uses CloudKit
  `Production`. The release-note and Setup changes do not change CloudKit
  schema.
- App Store Connect build `47fd6bbb-268f-417a-a5d7-0ca5bc3a207e` (version
  220) reached `VALID` and was initially bound to App Store version
  `35be3819-d4d8-40f0-a1de-2ac0cd11aeca`. It predates the CR fix below and is
  no longer the selected candidate.
- The first Codex review on PR #152 found that starting Demo from Setup Guide
  left the first-launch notes cover active. The callback now records the
  current marketing version before entering Demo, and
  `testChoosingDemoFromSetupGuideDismissesFirstLaunchReleaseNotes` passes on
  the iOS 27 iPhone 18 Pro Simulator. A second Codex review found no major
  issues; the P2 thread was replied to and resolved, and the PR review gate
  passed with zero unresolved threads on head
  `b5e27d5d1c34782b5134e615d7e135e895317f14`.
- Build 221 was archived from that reviewed source at
  `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-20260928-114542/CodexBarMobile.xcarchive`.
  The main executable SHA-256 is
  `de3b38b67305a8e9bd8b4ddbe124f770ab28271bd85351dca422531591911e11`;
  codesign verification passed and CloudKit is `Production`. App Store Connect
  build `8862da8a-6fb0-4b9d-acd7-d72df535c4fb` (version 221) reached `VALID`,
  uploaded at `2026-09-28T11:49:23-07:00`, and is now bound to the 2.2.0 App
  Store version. The version remains `PREPARE_FOR_SUBMISSION` with manual
  release and matching `whatsNew` text for `en-US`, `zh-Hans`, `zh-Hant`, and
  `ja`; it has not been submitted for App Review or released.
- Build 221's release-notes and Setup paths have Simulator UI-test evidence;
  this exact build has not yet been rechecked on the owner's physical iPhone.
  Earlier signed-device widget verification belongs to build 214 and should
  not be treated as build-221 evidence.
