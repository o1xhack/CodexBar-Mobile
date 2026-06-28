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

## Residual Risks

- Direct CloudKit reads from widgets can be budget-constrained. If widget freshness is poor in real use, switch to the deferred App Group cache path after explicit entitlement approval.
- Direct widget reads do not apply the app's local pending linkage/device lifecycle cache before CloudKit returns it. The app remains source of truth for the richest resolved view.
- New extension archive/upload may require Developer Portal capability/provisioning work.
