# 058 — iOS 2.2.0 Widget Redesign and Token Activity Heatmaps

Status: `draft` (design proposed; implementation awaits user confirmation under `AGENTS.md`)
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
2. Add a dedicated Token Activity widget kind so configuration remains focused.
   Use one source selector for small/medium, two ordered source slots for large,
   and configurable source slots suited to extra-large's available space.
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
