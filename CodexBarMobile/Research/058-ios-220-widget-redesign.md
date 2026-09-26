# 058 — iOS 2.2.0 Widget Redesign and Token Activity Heatmaps

Status: `in-progress` (user approved implementation on 2026-09-25)
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
