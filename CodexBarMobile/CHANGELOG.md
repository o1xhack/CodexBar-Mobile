# Changelog — CodexBar Mobile (iOS)

All notable changes to the CodexBar iOS companion app will be documented in this file.

## [1.14.0 (162)] — 2026-06-22 — sync device management review fixes

### Fixed

- **Sync Device Management** — Restoring a merged Mac device now queues
  unarchive events for every alias identity locally before waiting for
  CloudKit saves, so the row leaves Archived immediately even on a slow
  network.

### Notes

- iOS-only PR review fix; `MARKETING_VERSION` remains `1.14.0`.
- iOS `CURRENT_PROJECT_VERSION`: 161 → 162.

---

## [1.14.0 (161)] — 2026-06-22 — sync device management review fixes

### Fixed

- **Sync Device Management** — Device lifecycle replay now respects event
  chronology for merge/unmerge actions, so a user can unmerge duplicate Mac
  identities and later manually merge the same devices again.

### Notes

- iOS-only PR review fix; `MARKETING_VERSION` remains `1.14.0`.
- iOS `CURRENT_PROJECT_VERSION`: 160 → 161.

---

## [1.14.0 (160)] — 2026-06-22 — sync device management review fixes

### Fixed

- **Sync Device Management** — Unmerge now fully separates multi-step merged
  Mac identity groups instead of leaving older pairwise alias edges active.
- **Sync Device Management** — Archiving or restoring a merged Mac device now
  applies to every alias identity in that physical device group, so a later
  sync from another alias cannot make an archived device active again.

### Notes

- iOS-only PR review fix; `MARKETING_VERSION` remains `1.14.0`.
- iOS `CURRENT_PROJECT_VERSION`: 159 → 160.

---

## [1.14.0 (159)] — 2026-06-22 — provider detail chart QA fix

### Fixed

- **Provider detail Daily Spend chart** — Provider detail pages now show compact
  weekly x-axis labels instead of cramming every daily label into the chart.

### Notes

- iOS-only PR QA fix; `MARKETING_VERSION` remains `1.14.0`.
- iOS `CURRENT_PROJECT_VERSION`: 158 → 159.

---

## [1.14.0 (158)] — 2026-06-21 — sync device management QA polish

### Fixed

- **Archived device grouping** — Settings → About & Sync now separates active
  Macs from archived Macs so retired devices are clearly outside the active
  sync list.
- **Archive confirmation layout** — Archive, Restore, and Unmerge confirmation
  sheets now use full-width bottom controls without partial list separators.

### Notes

- iOS-only TestFlight fix; `MARKETING_VERSION` remains `1.14.0`.
- iOS `CURRENT_PROJECT_VERSION`: 157 → 158.

---

## [1.14.0 (157)] — 2026-06-21 — sync device management UI fix

### Fixed

- **Device management action sheets** — Settings → About & Sync now presents
  Merge, Archive, Restore, and Unmerge flows as bottom sheets instead of a
  top-anchored confirmation popover.

### Notes

- iOS-only TestFlight fix; `MARKETING_VERSION` remains `1.14.0`.
- iOS `CURRENT_PROJECT_VERSION`: 156 → 157.

---

## [1.14.0 (156)] — 2026-06-20 — sync device management

### Added

- **Sync Device Management** — Settings → About & Sync can now merge duplicate
  Mac device identities created by a Mac reinstall, archive real retired Macs,
  restore archived devices, and unmerge mistaken device identity merges.
- **Non-destructive device lifecycle records** — iOS stores user decisions as
  additive CloudKit lifecycle events instead of deleting or rewriting existing
  provider/device history.

### Fixed

- **Duplicate Mac display semantics** — merged aliases are removed from active
  stale-sync warnings while preserving raw diagnostic data.
- **Retired device warnings** — archived devices remain inspectable but no
  longer count as active Mac devices.
- **Local-cost duplicate counting** — local CLI cost providers are not summed
  inside a merged same-physical-Mac alias group.

### Notes

- iOS-only feature; no Mac release or `version.env` bump is required.
- Adds a new `DeviceLifecycleEvent` CloudKit record type in
  `DeviceProvidersZone`; Production schema deploy is required before release.

---

## [1.13.0 (155)] — 2026-06-19 — quota warning diagnostics hotfix

### Fixed

- **Developer Tools push diagnostics** — `quota-*-warning-sub` CloudKit
  subscriptions are now grouped separately instead of being reported as
  `other`. This keeps the iPhone-side push setup summary accurate for the
  1.13.0 three-state subscription matrix: depleted, restored, and warning.
- **Quota warning notification extension** — updated the warning-body rewrite
  path to use Swift's named associated-value pattern matching, clearing the
  deprecation warning without changing notification behavior.
- **Quota subscription setup diagnostics** — removed redundant `await`s around
  synchronous MainActor diagnostic calls.

### Notes

- iOS-only hotfix; `MARKETING_VERSION` remains `1.13.0`.
- iOS `CURRENT_PROJECT_VERSION`: 154 → 155.
- App Store and in-app 1.13.0 release notes remain unchanged because this
  fixes diagnostic accuracy rather than adding a new user-facing feature.

---

## [1.13.0 (154)] — 2026-06-16 — v0.36.1 upstream sync

### Added

- **Combined 1.12 + 1.13 update train** — 1.12.0 did not ship separately, so
  the in-app 1.13.0 release notes now fold together the v0.35.0 and v0.36.1
  iPhone-facing sync work.
- **New upstream providers in push and mock coverage** — Devin, LiteLLM, Poe,
  Chutes, and Zed are covered by the iPhone-facing sync/push readiness work.
  LiteLLM, Poe, Chutes, and Zed are appended to the shared quota provider list
  so iOS subscribes to their depleted / restored / warning CloudKit zones. Mock
  sync data covers the new v0.36 providers for end-to-end iPhone QA.
- **Provider colors** — LiteLLM, Poe, Chutes, and Zed have first-class iOS tint
  colors and collision tests for nearby provider families.
- **Richer synced provider details** — MiniMax renewal/expiration dates, Copilot
  budget windows, MiMo balance/token-plan updates, Kimi Code API usage, and Poe
  point history are represented through existing generic synced fields where iOS
  can display them.

### Changed

- **Mac sync pairing** — pairs with Mac **0.36.1.1 / build 88.1**, which folds
  upstream v0.35.0 through v0.36.1 iPhone-facing companion work into one App
  Store/TestFlight train. Existing generic synced rate-window and cost payloads
  carry the new provider data; no new CloudKit schema field is required for iOS
  1.13.0.
- **Rolling-upgrade compatibility** — rich synced provider details are preserved
  when one Mac is updated and another Mac is still on an older build.

### Notes

- Wire-format change is additive only: older iOS builds ignore unknown provider
  data/zones until upgraded, and iOS 1.13.0 remains compatible with older Mac
  builds.

---

## [1.12.0 (153)] — 2026-06-14 — v0.35.0 upstream sync

### Added

- **MiniMax subscription metadata** — when Mac CodexBar 0.35.0.1 syncs renewal
  or expiration dates, iOS preserves the fields and shows a compact
  renewal/expiration line on the provider card. 4-language localized.
- **v0.33.0–v0.35.0 sync surface** — shared payload support is ready for the
  upstream provider data that matters to mobile, including Devin quotas,
  Copilot budget windows, MiMo balance/token-plan updates, and Kimi Code API
  usage where iOS can display the generic synced windows.

### Fixed

- **Cross-version multi-Mac merge** — rich account-level synced fields are now
  preserved with latest-non-nil merge semantics when one Mac is updated and
  another Mac is still on an older build. This prevents optional provider
  details from flickering to empty after an older Mac refreshes.
- **SwiftData cold-start mirror** — subscription renewal/expiration metadata
  survives the CloudKit → SwiftData → in-memory snapshot round-trip.

### Notes

- Wire-format change is additive only: older iOS builds ignore the new payload
  keys, and newer iOS builds decode old Mac payloads with subscription fields nil.
- Paired Mac version: **0.35.0.1 / build 85.1**; this single release covers
  upstream v0.32.5 through v0.35.0.

---

## [1.11.1 (151)] — 2026-06-06 — Daily Spend chart scroll fix

### Fixed

- **Daily Spend chart (Cost tab)** — no longer crams the entire accumulated window
  (50 / 90 / 365 days) into one non-scrollable screen with overlapping marks. It now
  shows a ≤30-day viewport and scrolls horizontally through the full history, with the
  newest day pinned to the right edge. `visibleDayCount` caps the on-screen window at
  30 (`min(30, span + 1)`); `.chartScrollableAxes(.horizontal)` + `.chartXVisibleDomain`
  reveal older days by scrolling — no day-count cap. Supersedes the unreleased build 150
  (same fix); re-versioned as **1.11.1** because 1.11.0 (build 149) is already in App
  Store review.

---

## [1.11.0 (149)] — 2026-06-04 — Usage provider search

### Added

- **Provider search on the Usage tab** — a search bar pinned at the top of the Usage
  list filters provider cards by name / ID. Helps when many providers are synced (20+)
  and scrolling to find one is tedious; shows a "no matching providers" state on no hits.
  4-language localized.

---

## [1.11.0 (148)] — 2026-06-03 — v0.32.4 upstream sync (refinements, no new iOS code)

### Changed

- Paired with Mac **0.32.4.1 / build 79.1** (upstream v0.32.0–v0.32.4 sync). No
  functional iOS code change — the improvements reach iPhone through the existing
  Mac → iCloud sync. Added the in-app 1.11.0 "What's New" entry (4 languages).

### Improved (Mac-side, delivered to iOS via synced data)

- **Antigravity** quota rows are cleaner (image / lite / autocomplete / internal noise
  rows filtered, #1209).
- **Copilot** zero-entitlement usage % is no longer misleading (#1258).
- **Augment** parsing fixed for the new upstream `auggie` status format (#1224).
- **Claude** keeps the last good usage snapshot through brief auth hiccups (#1220).
- **Codex / Claude cost** re-scanned by the v0.32 cost-scanner update (cache invalidated
  via parserLogicVersion 4→5 + parser-hash regen).

### Notes

- No wire-format / schema change; older iOS and older Macs interoperate safely.

---

## [1.10.0 (147)] — 2026-06-03 — In-app 1.10.0 release notes

### Fixed

- **In-app "What's New" was missing the 1.10.0 entry** — `MobileReleaseNotesCatalog`
  still showed 1.9.0 as the latest. Added the 1.10.0 release-notes entry (DeepSeek card,
  Codex Spark / Antigravity lanes, cost request counts + synced currency, upstream
  value fixes) in all 4 languages and removed the stale "Latest" badge from 1.9.0. No
  functional change; build 146 → 147 carries it to TestFlight / the App Store submission.

---

## [1.10.0 (146)] — 2026-06-02 — Mac cost-cache invalidation hotfix (no iOS code change)

### Changed

- Version bump to pair with Mac **0.31.0.2 / build 73.2**, which bumps `parserLogicVersion`
  and regenerates the Codex parser-source hash so the Codex / Claude cost-usage caches
  re-scan after the v0.31.0 parser update. No iOS app code change from build 145 — the
  corrected cost numbers reach iOS through the existing Mac → iCloud sync.

---

## [1.10.0 (145)] — 2026-05-30 — v0.31.0 upstream sync (DeepSeek, Codex Spark, cost requests)

### Added

- **DeepSeek usage card** — web-session usage + cost: today / this-month tokens, spend, and
  request counts beside the balance, dispatched in `ProviderDetailView` (4-language).
- **Codex Spark** (5-hour + weekly) and **Antigravity** per-model quota lanes now render on
  iOS via the generic `rateWindows` pass-through.
- **Cost cards** show request counts ("N req") and format amounts in the synced currency
  (EUR / CNY) instead of hardcoded USD.

### Notes

- Wire format is additive (`SyncDeepSeekUsage` plus optional cost request/currency fields);
  older iOS ignores them and older Macs simply don't send them. No crashes across any
  new/old device combination.

---

## [1.9.0 (144)] — 2026-05-29 — Cost Overview headline follows the CWL window

### Fixed

- **Cost dashboard → Overview headline**: when the Cost Window Ledger is ON, the
  "N Days" card now reflects the window you selected (7 / 30 / 90 / 365) instead
  of the largest `historyDays` across providers. Previously a provider with a
  90-day Mac window made the headline read "90 Days" even when you'd picked a
  30-day CWL window. CWL OFF is unchanged (still the max provider window).

---

## [1.9.0 (143)] — 2026-05-29 — Cost daily-spend chart follows the selected window

### Changed

- **Cost dashboard → Daily Spend chart**: the visible window now follows the
  data span instead of a fixed 30-day viewport, so picking a longer Cost
  History (CWL) window — 30 / 90 / 365 — actually widens the chart to show that
  much history (floored at 30 days; the axis-label stride widens with the
  window, and the initial scroll anchors so the newest day sits at the right
  edge). Previously a 90-day window still showed ~30 days unless you scrolled.

### Testing (Mac mock injector — not user-facing)

- Simple single-account mocks now synthesize ~55 days of daily cost so they
  populate the Cost Window Ledger (previously only the Codex mock had per-day
  data, so CWL looked nearly empty); Codex Alice extended 30 → 55 days; a few
  headline providers (Cursor / Factory / Gemini) carry realistic heavy spend so
  the dashboard's big-number + top-5/Others paths are exercisable.

---

## [1.9.0 (142)] — 2026-05-29 — Codex Std/Fast split now shown in the Cost UI

The Codex standard-vs-fast (priority) spend split (upstream #1070) was only
rendered in Developer Tools → Raw Sync Data. It now appears in the normal,
user-facing Cost UI — at parity with the Mac's cost-history "Std / Fast"
detail. (Non-Codex providers and pre-0.29 Mac payloads are unaffected.)

### Changed

- **Cost dashboard → Model Mix**: each Codex model row now shows a
  "Std $X · Fast $Y" sub-line (summed over the window), for models that carry
  the split. Both aggregation paths carry it — the iCloud-blob path
  (`CostDashboardInsights.init(snapshot:)`) and the Cost Window Ledger path
  (`CostLedgerService.aggregate` → `fromLedger`) — so the value is identical
  whether the ledger is on or off.
- **Codex provider detail → Daily Spend**: selecting a day in the chart now
  shows that day's "Std $X · Fast $Y" beneath the cost/tokens line — the iOS
  mirror of the Mac cost-history hover.

### Internal

- New `CodexCostSplit` formatter is the single source of truth for the
  sub-line (reuses the existing 4-language `Std %@ · Fast %@` string, no new
  catalog key) — replaces the inline `codexSplitText` in the Raw Sync Data
  inspector.
- Fixed a stale `ShareCardData.displayProviders` test that still asserted the
  pre-1.9.0 top-3 cap; added a 5-vs-6 boundary test for the top-5 + Others rule.

---

## [1.9.0 (141)] — 2026-05-29 — Cost Window Ledger (beta, opt-in)

Adds an opt-in on-device cost ledger so the Cost tab can show a longer cost
history than the Mac's current window — independent of the Mac's `historyDays`
setting. **Default OFF**: untouched users keep exactly the build-140 behavior
(the existing iCloud blob path). Research doc 024.

### Added

- **Settings → Cost Setting → Cost History**: a "Local cost history" toggle
  + a window picker (7 / 30 / 90 / 365 days), a local-ledger diagnostics
  panel (days collected / providers / devices / since), and a "Clear local
  cost history" action (confirmation dialog).
- **`DailyCostPoint` SwiftData entity**: per-device, per-provider,
  per-account, per-day ledger. Each iCloud sync appends/dedupes its daily
  points (keyed by `(deviceID, providerID, accountEmail, dayKey)`, newest
  `lastUpdated` wins) instead of replacing the whole blob — so history
  accumulates beyond the Mac window.
- **Enable = seed**: turning the toggle on imports the current blob history
  into the ledger so the dashboard is populated immediately (no wait for the
  next Mac sync). Seed failure reverts the toggle.

### Notes

- iOS-only: no Mac change, no CloudKit envelope change. The ledger reads the
  same `SyncCostSummary.daily` data the Mac already pushes; it just keeps it.
- When ON, the Cost dashboard's totals / Provider Share / Model Mix re-window
  from the ledger; Subscription Utilization + the daily-spend chart are
  unchanged. Multi-account providers stay split per account.

---

## [1.9.0 (140)] — 2026-05-28 — Cost dashboard: top-5 + Others cap + drill-down

Consistency pass across every list-style section in the iOS Cost tab. Sections
with **≥ 6 entries** now show **top 5 + a tappable "Others" row** that
aggregates the tail; tap drills into a full list (same row design) in the
existing NavigationStack. Sections with ≤ 5 entries still show all (no Others
bucket). Closes the silent-drop behavior where small spenders ranked outside
the top 6 vanished from the Provider Share list even though they counted
toward the headline 30-day total (e.g. Mistral at $0.85 in mock).

### Changed

- **`contributionSection`** (Provider Share / Model Mix / Codex Service Mix
  — all three call into this one helper) — was `prefix(6)` with no Others,
  now top 5 + Others → drill-down to `FullBreakdownListView`.
- **Budgets** (`budgetSection`) — was uncapped; same cap rule. The Others
  row has no aggregate metric (summing budgets across different limits /
  currencies isn't meaningful) — just the count and a chevron. Drill-down:
  `FullBudgetListView`.
- **Subscription Utilization** (`UtilizationAggregateView.providerShares`)
  — was uncapped; same cap rule. The tail's `sharePercent` is additive
  across providers, so the "Others X%" is meaningful. Drill-down:
  `FullProviderUtilizationListView` (nested struct).
- **Cost Share card** (`CostShareService.displayProviders` / `topModels`)
  — top 3 → top 5 + Others, for consistency.
- **`CyberShareCardView`** — intentionally left at `prefix(3)`: its 3-column
  ArcGauge / cost-row layout is built around exactly 3 columns and would
  overflow if widened to 5.

### Localization

- New key `"+%lld more"` (en / ja / zh-Hans / zh-Hant). The existing
  `Others` key is reused across all four new section caps.

---

## [1.9.0 (139)] — 2026-05-26 — upstream v0.29.0 sync + Mac↔iOS parity gap-fills

MOBILE_VERSION 1.8.0 → 1.9.0, build 137 → 139. Pairs with Mac CodexBar 0.29.0
(fork build 68.1). Surfaces the three new upstream v0.28/v0.29 providers AND
closes a set of pre-existing Mac↔iOS display-parity gaps found in a full audit
(2026-05-26) — data the Mac rendered that iOS dropped.

### Parity gap-fills (Mac↔iOS audit)

- **A — Codex standard/fast cost split** (#1070): the std vs fast (priority)
  spend/token split was computed + shown on Mac but dropped at the bridge.
  Added to `SyncCostBreakdown`; iOS shows a "Std $X · Fast $Y" sub-line per model.
- **C — Mistral daily cost**: was a one-line "$X" on iOS; now feeds the existing
  Cost dashboard (30-day chart + model mix) via a mapped `SyncCostSummary`.
- **D — OpenRouter**: balance / lifetime credits / rolling day-week-month key
  usage / rate limit → new `OpenRouterStatsCard` (was a one-line balance).
- **E — Azure OpenAI**: endpoint / deployment / model / API version →
  `AzureOpenAIInfoCard` (the endpoint host was dropped entirely before).
- **F — Cost-history window**: per-provider + Cost-tab cards now label the real
  1–365 day window (`historyDays`) instead of a hardcoded "30 Days".
- **G — Alibaba Token Plan (Bailian)**: structured plan + used/total/remaining
  credits → `AlibabaTokenPlanCard`. (T3 Chat is already adequately surfaced via
  the generic 2-window card; its remaining fields are Mac-debug-only.)
- **B — Antigravity multi-account**: Mac now threads the Google-OAuth account
  list (`mapAntigravityAccounts`) so the iOS AntigravityAccountSwitcher — shipped
  since 1.7.0 but never fed — lights up for > 1 account.

### Added (initial 1.9.0 — provider registration)

- **Azure OpenAI** (`azureopenai`) — deployment-status usage card (primary
  RateWindow). Registered in `QuotaProviderList` (push-eligible) +
  `ProviderColorPalette` (Azure blue) + `MockProviderInjector`.
- **Alibaba Token Plan / Bailian** (`alibabatokenplan`) — monthly token-plan
  quota card (used/total credits + reset date).
- **T3 Chat** (`t3chat`) — web-session usage card with a 4-hour base window
  plus a monthly overage window (primary + secondary).
- `MobileReleaseNotesCatalog` 1.9.0 entry, localized in all 4 languages
  (en / zh-Hans / zh-Hant / ja).

### Changed

- `QuotaProviderList`: 45 → 48 providers (144 push zones at ×3 states).
  Appended at the tail so existing CK subscription IDs stay stable.
- `MockProviderInjector`: 57 → 60 mocks across 50 IDs (+3 v0.28/v0.29 simple
  profiles). Debug "Mock Provider Data" subtitle updated (en/zh-Hans).

### Fixed

- iOS `QuotaProviderListTests`: corrected two PRE-EXISTING stale assertions
  the v0.27 sync left behind — the tail-order check still pinned `bedrock`
  (it never picked up the 5 v0.27 providers), and the catalog zone-count test
  used a 2-state `×2` formula instead of the current `×3`.

### Notes

- Scope is upstream **v0.28.0 + v0.29.0** only. The v0.29.1 fixes (Claude
  OAuth extra-usage currency fix #1114, Grok reset-window labels #1148, Groq
  icon #1112, workday markers #1102, zh-Hant Mac strings) are **deferred** to
  a future sync.
- Codex standard/fast spend splits (#1070) stay as a combined total on iOS for
  1.9.0; OpenCode workspace renewal dates (#1099) ride the existing
  `renewalAt` envelope field. No new CloudKit schema fields.

## [1.8.0 (137)] — 2026-05-25 — Opus 2nd-pass CR follow-ups

Same MOBILE_VERSION (1.8.0), build 136 → 137. Pairs with Mac
CodexBar 0.27.0 fork build 65.4 → 65.5. Closes 3 low-priority
follow-ups from the Opus 4.7 SECOND-pass review of build 136 (the
build that closed the FIRST-pass review). All non-blocking, but
the user asked for "前面 CR 的全部修复" (fix everything from CR),
so cleaned up before ship.

### Fixed (build 137 — 2nd-pass CR follow-ups)

- **UsageStore Cursor diagnostic dump leaks accountEmail** —
  `Sources/CodexBar/UsageStore.swift:1310`'s `debugCursorLog`
  rendered the Cursor account email cleartext. Even though the
  log is user-initiated (Preferences → Cursor → Copy Diagnostics),
  consistency with the OSLog redaction in build 136 demanded the
  same `EmailRedaction.redact()` treatment. Added `import
  CodexBarSync` to `UsageStore.swift` so the helper is in scope.
- **`mapCodexWorkspace` lacked direct integration test** — The
  build 136 commit message + CHANGELOG promised "integration
  tests exercising mapClaudeAdminUsage / mapMiniMaxBilling /
  mapOpenCodeGoZenBalance" but silently dropped `mapCodexWorkspace`
  (the only non-static mapper in the v0.27 set). Refactored
  `mapCodexWorkspace` into a thin wrapper that delegates to a new
  pure-function `buildCodexWorkspaceContext(activeAccount:,
  snapshot:)` static helper. Added 4 tests covering: empty inputs
  → nil, workspace-label-only path, weekly-pace-only path, and
  weekly-vs-session window selection. No behaviour change —
  static helper has the exact same body as the inlined logic.
- **`EmailRedaction` lacks unit coverage** — Added
  `Tests/CodexBarTests/EmailRedactionTests.swift` with 8 edge-case
  tests: nil / empty / no-@ / standard email / empty local-part /
  multiple @ / Unicode local / very-long input. Mac swift test:
  8/8 pass.

### Test counts

- `EmailRedactionTests`: 8/8 pass
- `SyncCoordinatorV027MapperTests`: 16/16 pass (was 12 in build 136 — added 4 codex workspace tests)
- `V027SnapshotsCodableTests`: 9/9 unchanged
- Total V027-related tests now: **33**

### What WAS NOT changed (Opus 2nd-pass refuted)

- `EmailRedaction.redact()` not gated on `hidePersonalInfo` toggle.
  Defensible by design — the helper is "PII-safe rendering", not
  "PII suppression". Source gate at `quotaWarningAccountDisplayName`
  already short-circuits to nil when the toggle is set.
- `ClaudeUsageFetcher.swift:688`, `AugmentStatusProbe.swift:616`,
  and `OpenAIDashboardBrowserCookieImporter.swift:716` also log
  accountEmail cleartext — these are upstream-owned
  files. Per `CLAUDE.md` policy "do not modify Mac-only files
  unless explicitly asked", left alone for upstream to handle.

### Required Mac version

Mac CodexBar 0.27.0 fork build 65.5. Forward-compatible:
iPhone 1.8.0 b137 + Mac 65.4 still works — the only Mac change
in 65.5 is the UsageStore diagnostic-log redaction, which doesn't
affect wire format or push behaviour.

---

## [1.8.0 (136)] — 2026-05-25 — code-review fixes pre-ship: PII redaction + deploy script + integration tests

Same MOBILE_VERSION (1.8.0), build 135 → 136. Pairs with Mac
CodexBar 0.27.0 fork build 65.3 → 65.4. No new features —
addresses findings from the Opus 4.7 code review of build 135.

### Fixed (build 136 — code-review pre-ship)

- **OSLog PII redaction** — `CloudSyncManager.writeQuotaTransition` /
  `writeQuotaWarningTransition` and the iOS NSE invocation log
  used to render `accountEmail` cleartext in the log metadata.
  Even though the upstream `UsageStore.quotaWarningAccountDisplayName`
  helper already gates the field at SOURCE on the
  `hidePersonalInfo` privacy toggle, Apple's defensive convention
  is to also redact identity strings at the log layer. New
  `Shared/Utilities/EmailRedaction.swift` helper renders emails
  as `a***@example.com` for both Mac OSLog and the iOS NSE
  invocation diagnostic log.
- **Deploy script `set -euo pipefail` dead branch** —
  `Scripts/deploy_quota_account_email_field.sh` had an
  unreachable `if [ $? -ne 0 ]` after an `awk` invocation. With
  the strict shell mode, awk's non-zero exit aborts the script
  before the check can fire. Wrapped the awk in `if ! awk ...`
  so the friendly error message actually surfaces.
- **Deploy script race warning** — Added a `RACE WARNING` banner
  before `cktool import-schema --environment DEVELOPMENT` to
  remind the operator that the import has full-schema overwrite
  semantics; if another developer has added a Dev schema field
  in the ~5-second window since the script fetched the schema,
  that field will be wiped.

### Added (build 136 — integration test gap)

- `SyncCoordinatorV027MapperTests` — 12 integration tests
  exercising `mapClaudeAdminUsage` / `mapMiniMaxBilling` /
  `mapOpenCodeGoZenBalance` with synthetic `UsageSnapshot`
  fixtures. Verifies wrong-provider early-return, missing-payload
  early-return, empty-window nil-pruning, and the top-list cap
  invariants (top-8 models / top-8 cost-items / top-3
  method+model breakdowns). Closes the integration-test gap
  flagged by the Opus 4.7 review — only Codable round-trip was
  previously covered.

### Documentation

- `NotificationService.formatTitle` — translator note added
  explaining why `Push.Quota.titleWithAccount` is identical
  (`%1$@ · %2$@`) in all 4 locales: mid-dot is universal and
  the order is fixed by lock-screen UX requirements regardless
  of locale grammar.

### Code review verdicts (recorded for posterity)

The Opus 4.7 reviewer also flagged but DID NOT recommend
fixing:
- `mapClaudeExtraUsage` false-positive (verified safe — only
  two Mac code paths populate Claude `providerCost` and both
  gate on extra_usage being enabled).
- `codexWeeklyWindow` 1-day-or-more filter (verified safe —
  `UsagePace.weekly` correctly uses `windowMinutes ?? 10080`).
- `formatTitle` `%` in email (verified safe — `String(format:
  "%@", ...)` treats arg as NSString data, not format spec).

Recorded here so future engineers don't re-investigate the
same questions.

### Required Mac version

Mac CodexBar 0.27.0 (fork build 65.4) or later. iPhone 1.8.0
build 136 is forward-compatible with Mac 65.3 — the PII
redaction is purely log-layer, so the wire format is identical
and the only user-visible change is logs in Console.app /
sysdiagnose now mask emails.

---

## [1.8.0 (135)] — 2026-05-20 — v0.27 deferred features close: quota account identity + Codex workspace populator

Same MOBILE_VERSION (1.8.0), build 134 → 135. Pairs with Mac CodexBar
0.27.0 fork build 65.2 → 65.3. Closes the two remaining items from
the 1.8.0 research matrix that build 134 explicitly deferred —
brings the v0.27 surface to full parity in one combined release.

### Added (build 135 — v0.27 deferred features)

- **Quota warning account identity** end-to-end. Multi-account
  providers (Codex managed accounts, Claude multi-account, OpenAI
  token accounts, etc.) now include the triggering account in
  every CloudKit-backed push notification. Title format:
  "Codex · admin@example.com" instead of bare "Codex". Honours
  the existing Mac `Preferences → Privacy → Hide personal info`
  toggle — when set, accountEmail is suppressed and the push
  title falls back to provider-only.
- **Codex workspace + weekly pace badge** on the Codex detail
  page lights up. Mac populates `SyncCodexWorkspaceContext` from
  the active `ManagedCodexAccount.workspaceLabel` +
  `workspaceAccountID` plus a fresh `UsagePace.weekly(...)`
  computation against the snapshot's weekly RateWindow. iOS
  already shipped the receiver UI in build 134; the badge is
  now driven by real Mac data.

### Shared envelope

- `Shared/iCloud/CloudSyncManager.swift` —
  `writeQuotaTransition(..., accountEmail:)` and
  `writeQuotaWarningTransition(..., accountEmail:)` gain an
  optional `accountEmail` parameter. Stored as a 6th CKRecord
  field on `QuotaTransition`. Optional + only written when
  non-empty, so pre-65.3 iOS NSE doesn't see a missing key.
  **Requires a CloudKit Production schema deploy** (see
  `docs/cloudkit-deploy-audit.md`) — the first record write
  from Mac will fail until the field is in the Prod schema.

### Mac side wiring

- `QuotaTransitionWriting` protocol — both `write(...)` and
  `writeQuotaWarning(...)` gain `accountDisplayName: String?`.
- `UsageStore.handleSessionQuotaTransition(...)` extracts the
  per-snapshot account display name (existing
  `quotaWarningAccountDisplayName` helper, respects
  `settings.hidePersonalInfo`) and passes it to the writer for
  both depleted/restored and warning paths.
- `SyncCoordinator.mapCodexWorkspace` is now an instance
  method that reads
  `settings.codexAccountReconciliationSnapshot.activeStoredAccount`
  for workspace metadata and runs `UsagePace.weekly(...)` over
  the snapshot's weekly RateWindow (auto-detected as the
  largest ≥1-day window across primary/secondary/tertiary).

### iOS NSE wiring

- `CodexBarMobilePushExtension/NotificationService.swift` —
  `desiredKeys` extended to include `accountEmail`; new
  `formatTitle(providerName:, accountEmail:)` helper joins
  provider + account with `·` separator via the new
  `Push.Quota.titleWithAccount` localized template (4 locales).
  Pre-65.3 Macs leave the field absent and the helper falls
  back to bare providerName — title text matches build 134.
- `fetchLatestProviderInfo(in:)` consolidates the depleted /
  restored fetch + accountEmail read; the legacy
  `fetchLatestProviderName(in:)` wraps it for source compat.

### Localized strings

1 new key — `Push.Quota.titleWithAccount` ("%1$@ · %2$@") in
all 4 locales (en / zh-Hans / zh-Hant / ja). xcstrings audit:
276 / 276 source keys present.

### Cross-version compatibility matrix

Verified-by-construction for every 2-Mac × 2-iOS new/old combo
(`Mac_old=63.4` / `Mac_new=65.3`, `iOS_old=1.7.0` /
`iOS_new=1.8.0 b135`):

- **iOS_old + Mac_old**: untouched, baseline behaviour.
- **iOS_old + Mac_new**: 1.7 NSE doesn't request accountEmail
  via `desiredKeys`, CloudKit returns the field but the NSE
  ignores unknown keys — push title stays as bare providerName.
  Envelope decoder uses `decodeIfPresent` for the 5 build-134
  optional fields + the existing build-135 ones — old iOS skips
  them silently.
- **iOS_new + Mac_old**: 1.8 b135 NSE requests accountEmail in
  desiredKeys, record doesn't have the field, fetch returns
  nil → `formatTitle` falls back to bare providerName. iOS
  decodes the old envelope (no new fields), all new cards
  render as "data not available" placeholders / hidden.
- **iOS_new + Mac_new**: full functionality.

### CloudKit deploy

**Required.** `QuotaTransition` CKRecord gains a 6th field
(`accountEmail: String`). See `docs/cloudkit-deploy-audit.md`
for the deploy procedure: write a record from Mac in Dev env
to populate Dev schema, then Dashboard → Deploy Schema Changes
to Production. Without the deploy, Production saves with the
new field will be rejected by CloudKit and push notifications
will stop firing.

### Required Mac version

Mac CodexBar 0.27.0 (fork build 65.3) or later for the quota
account identity + Codex workspace badge data. Forward-compat:
iPhone on 1.8.0 build 135 paired with Mac on 65.2 still
renders build-134 functionality; the new title format and
Codex workspace badge stay dormant until Mac is on 65.3.

---

## [1.8.0 (134)] — 2026-05-19 — v0.27 existing-provider extensions (Anthropic Admin API + spend-limit + OpenAI window picker + OpenCode Zen + MiniMax billing)

Same MOBILE_VERSION (1.8.0), build 133 → 134. Pairs with Mac CodexBar
0.27.0 fork build 65.1 → 65.2. Closes the remaining v0.27.0 surface
gap for existing providers — Claude Admin API, Claude Enterprise
spend-limit, OpenAI Admin dashboard window picker, OpenCode Go Zen
balance, and MiniMax 30-day billing all flow end-to-end now.

### Added (build 134 — v0.27 existing-provider extensions)

- **Claude Anthropic Admin API section** on the Claude detail page.
  Mirrors the OpenAI Admin Dashboard layout: Today / 7d / 30d cost
  summary cards (USD + total tokens) plus top-5 models and top-5
  cost items. Renders only when Mac has an Admin API key
  (`sk-ant-admin…`) configured in Preferences → Providers → Claude.
- **Claude Extra usage / spend-limit** dedicated card for
  Enterprise and Team-with-extra-usage plans. Shows utilization
  bar, monthly spend / limit gauge ("$38.50 / $100.00"), plan tier
  badge, and a "disabled" caption when the user hasn't enabled
  extra-usage billing on the Anthropic console. Detected
  heuristically from `providerCost` when Web cookies expose the
  monthly cap; OAuth-only accounts continue to surface the
  spend-limit via the existing primary rate window.
- **OpenAI Admin Dashboard window picker** — header pill now lets
  you switch the 30-day chart range across 7 / 30 / 90 / 180 / 365
  days, clamped to whatever Mac actually fetched (Mac configures
  the upper bound in Preferences → Providers → OpenAI API → History
  window). The Today / 7d / 30d summary cards stay fixed as
  comparison metrics.
- **OpenCode Go Zen balance card** below the rolling / weekly /
  monthly rate windows. Reads the workspace pay-as-you-go USD
  balance Mac scraped from the OpenCode workspace dashboard and
  shows the workspace ID as a caption when configured.
- **MiniMax 30-day billing card** — Today + 30-day token and USD
  totals, a 30-day bar chart, and top-3 method / model breakdowns.
  Populated from the upstream `MiniMaxBillingSummary` lane
  (requires an API-key configured account; Web-cookie accounts
  continue with the existing prompts card).
- **Codex workspace + weekly pace badge** scaffolding — UI shell is
  in place so the badge lights up the moment Mac threads workspace
  data through `UsageSnapshot`. Mac side currently emits nil for
  this lane (sketched as a follow-up because it touches the G1–G6
  multi-account paths and warrants its own focused test sweep);
  iOS quietly hides the badge until then.

### Shared envelope — Shared/Models/V027Snapshots.swift

Five new Codable structs, all decoded via `decodeIfPresent` for
backward compatibility with build 133 payloads:

- `SyncClaudeAdminUsage` (+ `Window` / `Model` / `CostItem` helpers)
- `SyncClaudeExtraUsage`
- `SyncOpenCodeGoZenBalance`
- `SyncMiniMaxBillingHistory` (+ `Day` / `Breakdown` helpers)
- `SyncCodexWorkspaceContext`

### Shared envelope — Shared/Models/V026Snapshots.swift

- `SyncOpenAIAPIDashboard.historyDays` added (default 30, clamped
  1–365). Pre-1.8.0 build-134 payloads decode the field as 30 so
  the picker still surfaces a sensible range.

### Mac side wiring

- `SyncCoordinator` gains 5 new mappers
  (`mapClaudeAdminUsage` / `mapClaudeExtraUsage` /
  `mapOpenCodeGoZenBalance` / `mapMiniMaxBilling` /
  `mapCodexWorkspace`). All read directly from existing
  `UsageSnapshot` fields and the snapshot's `providerCost` lane;
  no upstream-side changes required.
- `mapOpenAIAPIDashboard` now propagates the Mac-resolved
  `historyDays` so iOS can size the picker correctly.

### iOS UI — 5 new view files

`ClaudeAdminUsageCard` / `ClaudeExtraUsageCard` /
`OpenCodeGoZenBalanceCard` / `MiniMaxBillingCard` /
`CodexWorkspaceBadge`, plus `OpenAIDashboardSection` extended with
the window picker. Each new card uses the same dispatch pattern as
the v0.26 / v0.27 dedicated cards (`if providerID == "X", let
payload = provider.fieldX`).

### Localized strings

21 new keys added to `Localizable.xcstrings` across the 5 cards
(en / zh-Hans / zh-Hant / ja, all `state=translated`). xcstrings
audit: 270 / 270 source keys present.

### CloudKit deploy

No new fields on CKRecord schema — all five extensions live inside
the existing `payload` blob field. No Production schema deploy
required.

### Quota warning account identity (deferred)

Upstream v0.27.0 adds "include triggering account in quota
warnings" — implementing it requires a 6th field on the
`QuotaTransition` CKRecord type (the schema currently caps at 5
fields, with `(window, threshold)` packed into the recordName as
a workaround). A 6th field needs a CloudKit Production deploy,
which has bitten this project before; deferring to 1.8.1 so the
schema migration can be batched with a focused test sweep.

### Required Mac version

Mac CodexBar 0.27.0 (fork build 65.2) or later for the new tile
data. Forward-compatible: an iPhone on 1.8.0 build 134 paired with
Mac on build 65.1 keeps the build 133 behaviour — new tiles stay
hidden until Mac is on 65.2.

---

## [1.8.0 (133)] — 2026-05-19 — upstream v0.27.0 provider alignment + 5 dedicated cards

Pairs with Mac CodexBar 0.27.0 (fork build 65.1). MOBILE_VERSION
1.7.0 → 1.8.0; CURRENT_PROJECT_VERSION 131 → 133. New MARKETING_VERSION
because the provider catalog grew by 5 + Kiro card gained a new
data lane (overage) + 5 new dedicated provider cards landed; all
user-visible.

### Added (build 133 — dedicated cards)

- **5 new dedicated provider cards** with rich data instead of the
  generic rate-window fallback:
  - `GrokBillingCard` — monthly USD spend + plan tier badge +
    percent badge + reset date (CLI billing source) or just
    percent + reset date (web-billing source)
  - `ElevenLabsCreditsCard` — character credits primary row,
    voice slots + pro voice slots optional rows, tier badge,
    renewal date
  - `DeepgramUsageCard` — speech / agent / total hours,
    request count, agent tokens (input → output), TTS character
    count, project badge with "(of N)" hint when multiple
    projects
  - `GroqMetricsCard` — three columns of live rates (req/min,
    tok/min, cache/min) plus cache-hit percentage badge
  - `LLMProxyStatsCard` — lowest remaining percent headline,
    credential pool summary, request/token totals with reset
    date, top-3 upstream providers with per-provider req/tok/cost
- **Shared envelope** `V027Snapshots.swift` — 5 new structs
  (`SyncGrokBilling` / `SyncElevenLabsCredits` / `SyncDeepgramUsage`
  / `SyncGroqMetrics` / `SyncLLMProxyStats`) all
  `decodeIfPresent`-backwards-compat. iOS 1.7.x clients on the
  same iCloud zone ignore these fields entirely.
- **20+ new localized strings** across the 5 cards (en /
  zh-Hans / zh-Hant / ja, all `state=translated`). xcstrings audit:
  250 / 250 source keys present.
- **Mac side wiring**: `UsageSnapshot` gains
  `grokUsage / elevenLabsUsage / groqUsage / llmProxyUsage`
  optional fields populated by each provider's `toUsageSnapshot()`
  factory. `SyncCoordinator` gains 5 mappers
  (`mapGrokBilling` / `mapElevenLabsCredits` / `mapDeepgramUsage`
  / `mapGroqMetrics` / `mapLLMProxyStats`) that translate rich
  upstream snapshots into the iOS-facing `V027Snapshots` shapes.
- `ProviderDetailView` adds 5 new `if provider.providerID == "X",
  let payload = provider.fieldX { CardX(...) }` dispatch blocks
  matching the existing v0.26 pattern (Kiro / Bedrock / Moonshot
  / z.ai / OpenAI Dashboard / Antigravity).

### Added (build 132 — initial 1.8.0)

### Added

- **5 new provider brand colours** in `ProviderColorPalette` so cards
  for the upstream v0.27.0 additions render with brand-aligned tints
  instead of the generic `.blue` fallback:
  - Grok (xAI) → charcoal (#1A1A1A)
  - ElevenLabs → sage-green (#7AAE82)
  - Deepgram → brand purple (#7C3AED)
  - GroqCloud → orange-red (#F55036)
  - LLM Proxy → neutral slate-blue (#5C7A99)
  All choices avoid existing palette zones — Mistral red, Codex /
  Cursor purple, Gemini cyan, OpenAI / ChatGPT green, etc. — and
  remain distinct in dark mode + the stacked-bar utilisation chart.
- **Kiro overage badge** on `KiroCreditsCard`. When Mac surfaces
  `overage_credits_used` and / or `estimated_overage_cost_usd` (Kiro
  plan exhausted, paying per-credit), the card adds a Divider + a
  third row showing "+N credits" and / or "$N.NN" in orange. Hidden
  when both are nil / zero so the layout is unchanged for users on
  unexhausted plans. Mirrors Mac's v0.27.0 overage-credit and
  overage-cost menu bar display modes.
- **Localized strings**: `kiro_overage_label`, `kiro_overage_credits_format`
  in all 4 locales (en / zh-Hans / zh-Hant / ja).

### Shared sync layer

- `SyncKiroCredits` (Shared/Models/V026Snapshots.swift) gained two
  optional fields — `overageCreditsUsed: Double?` and
  `estimatedOverageCostUSD: Double?`. Decoded via `decodeIfPresent`
  so pre-1.8.0 envelopes (no overage data) still decode cleanly.
- `SyncCoordinator.mapKiroCredits` populates both fields from the
  upstream `KiroUsageDetails` values when Mac is on v0.27.0+.

### CloudKit deploy

No new fields on CKRecord schema — `SyncKiroCredits` is part of the
existing `payload` blob field. No Production schema deploy required.

### Required Mac version

Mac CodexBar 0.27.0 (fork build 65.1) or later for the new provider
data and Kiro overage. Forward-compatible: an iPhone on 1.8.0 paired
with Mac 0.26.x just keeps the existing 1.7.0 behaviour — new fields
stay nil and the overage row stays hidden.

---

## [1.7.0 (131)] — 2026-05-19 — i18n hotfix: 21 missing translations

Same marketing version (1.7.0), bumped build (130 → 131). Translation-only
fix — no behavior change, no new features.

### Fixed

- **21 `String(localized:)` keys were missing from `Localizable.xcstrings`**,
  so zh-Hans / zh-Hant / ja users on build 130 saw English fallback text
  on: the full 1.7.0 in-app release-notes catalog (Summary + 7 "What's
  New" bullets + "Required Mac version"), and 12 CloudKit sync status
  strings ("Syncing…", "Sync Error", "No Mac data found", "Waiting for
  Mac to push data", "Per-device unmerged data for debugging", etc.).
  Root cause: Xcode auto-extracts new `String(localized:)` keys only on
  full Xcode build; our swift-test + lint flow never triggered it, so
  the keys lived in source but had no catalog entry. Now all 4 locales
  (en / zh-Hans / zh-Hant / ja) translated for every source key.

### Tooling

- **New `Scripts/audit_localized_keys.py`** + lint integration. The
  existing `state="new"` xcstrings audit can't detect orphan source
  keys (keys present in `.swift` files but not in the catalog at all)
  — that's exactly what shipped in build 130. The new pre-build
  check fails lint when any `String(localized:)` literal in
  `CodexBarMobile/` has no matching xcstrings entry. Same enforcement
  pattern as the existing parser-version audit. Closes the gap that
  let build 55 (1.1.0), build 92 (1.3.0), and build 130 (1.7.0) all
  ship English-only screens to non-English users.

### Mac compatibility

Unchanged from build 130 — pairs with Mac 0.26.4 (or 0.26.2 from prior
release; the hotfix is iOS-side only). All Phase G multi-account UI
behavior carries over.

---

## [1.7.0 (130)] — 2026-05-18 — Universal multi-account tab UI (Phase G)

Same marketing version (1.7.0), bumped build (129 → 130). Pairs with
Mac 0.26.2 (fork build 63.3) which fans out **all 18 token-account
providers** to multi-account via CloudKit. Before this build, the iOS
Usage list rendered N separate rows for any provider with N accounts
on Mac (codex × 3, claude × 2, OpenAI admin × 2, etc.) and offered no
tab switcher — diverging from Mac's "one menu card with tabs at top"
UX.

### Added

- **`Models/ProviderAccountGroup.swift`** — generic post-merge
  grouping primitive (`[ProviderUsageSnapshot].groupedByProvider()`)
  that collapses snapshots sharing a providerID into one
  `ProviderAccountGroup` with helpers for tab labeling and stable
  accessibility IDs.
- **`Views/ProviderDetailView` segmented account-tab bar** — when
  `group.hasMultipleAccounts`, renders a SwiftUI Picker at the top
  with one tab per account. Tab labels prefer email local-part
  (e.g., "admin-msxiao113"), fall back to loginMethod, then
  "Account N". Selecting a tab re-renders all downstream cards
  (rate-window cards, cost summary, daily chart, Phase B typed cards
  including OpenAI Dashboard / Bedrock / Moonshot / Kiro / z.ai
  hourly chart) against that account's snapshot. `selectedDate` for
  the daily chart hover state resets on tab switch.
- **Multi-account row count badge** — `ProviderUsageView` shows
  "· N" after the provider name in the Usage list when the row
  represents a multi-account group. Hidden for single-account groups
  (no "· 1" leak).

### Changed

- `ContentView.swift` UsageTab iterates over groups
  (`liveProviders.groupedByProvider()`) instead of raw snapshots.
  One row per providerID. Linkage-candidate logic surfaces on the
  group row when any account in the group has an open candidate.
- `ProviderDetailView` signature: new `init(group:)` is preferred;
  legacy `init(provider:)` wraps a single snapshot into a
  1-account group for backwards-compat with `RawProviderDetailView`
  and SwiftUI previews. No external consumers needed to change.

### Backward compatibility

- Wire format **unchanged** — Phase G is consumer-side. Mac pushes
  more `ProviderUsageSnapshot` records of the existing schema (one
  per token account); iOS render layer groups them.
- iOS 1.6.0 (126) on TestFlight reading payloads from a Phase G Mac:
  still works — sees more cards under the same providerID, same
  pre-existing multi-account Codex/Claude code path handles it.
- Mac 0.25.2 / pre-Phase-G + iOS 1.7.0 (130): graceful degradation —
  groups have one account each, tab bar hidden, ProviderDetailView
  body identical to pre-G single-account rendering.

### Tests

- `CodexBarMobileTests/ProviderAccountGroupTests.swift` (11 tests)
  — grouping correctness, first-appearance order, tab-label fallback
  chain, accessibility IDs.
- `CodexBarMobileTests/MultiAccountTabRenderingTests.swift` (6 tests)
  — ImageRenderer smoke for 1 / 2 / 3-account groups, missing-email
  fallback, ProviderUsageView count badge.

### Required Mac version

- Mac 0.26.2 (fork build 63.3) or later to actually see tabs for
  the 7 newly-fanned-out providers (openai/deepseek/antigravity/
  manus/copilot/venice/stepfun). On older Mac, those providers still
  show single-account on iPhone.
- iPhone 1.7.0 (130) is forward-compatible with older Mac builds —
  graceful degradation.

---

## [1.7.0 (129)] — 2026-05-18 — Upstream v0.26.1 fold-in: six new dedicated provider cards + settings

iOS 1.7.0 is the iOS-side development track that pairs with the
**fork Mac 0.26.1** release. Mac ships first (matched with the
currently-installed iOS 1.6.0 on TestFlight); when 1.7.0 is verified
on TestFlight, a follow-up Mac release will pair against it. The
intermediate state — Mac 0.26.1 paired with iOS 1.6.0 (126) on users'
devices — works because every new envelope field is `decodeIfPresent`
optional, so 1.6.0 ignores the new keys while 1.7.0 renders the cards.

### Added

- **OpenAI API Dashboard** — `Views/OpenAIDashboardSection.swift`. On
  the `openai` provider detail page when `openAIAPIDashboard != nil`:
  3-card Today / 7d / 30d summary, 30-day spend bar chart, top models
  + top line items lists. Mirrors upstream v0.26.1 menu addition.
- **Kiro credits card** — `Views/KiroCreditsCard.swift`. Plan tag +
  primary credit progress + optional bonus pool with localized expiry
  countdown (1 day / N days / expired). Mirrors upstream PR #933.
- **AWS Bedrock cost card (NEW provider)** — `Views/BedrockCostCard.swift`.
  Monthly spend + optional budget gauge with 75% / 90% threshold colors
  + active AWS region (read from `SettingsStore.bedrockRegion`, not
  the composite display string). Mirrors PR #897.
- **Moonshot / Kimi API balance card (NEW provider)** —
  `Views/MoonshotBalanceCard.swift`. Balance amount + ISO 4217 currency
  + region. Balance parsed from the upstream `loginMethod` string so
  iOS shows the real dollar value, not `0.00`. Mirrors PR #911.
- **z.ai hourly chart** — `Views/ZaiHourlyChart.swift` — stacked
  per-model hourly token bars over the active 24-hour window with chart
  legend. Mirrors upstream PR #913.
- **Antigravity multi-account switcher** —
  `Views/AntigravityAccountSwitcher.swift`. Read-only linked Google
  account list with active marker + relative token expiry. Renders
  when Mac populates antigravityAccounts (Mac side stub for now).
- **Settings: Hide quota-warning markers** —
  `MobileSettingsKeys.hideQuotaWarningMarkers` (mirrors upstream PR #918).
- **Settings: Show provider changelog links** —
  `MobileSettingsKeys.showProviderChangelogLinks` — wires a new
  "Provider changelogs" section in Settings → About & Sync with
  Codex CLI / Claude Code / Gemini CLI links (mirrors upstream PR #929).

### Changed

- Wire schema extension — `ProviderUsageSnapshot` gains six optional
  `decodeIfPresent` fields (`openAIAPIDashboard`, `zaiHourlyUsage`,
  `kiroCredits`, `bedrockCost`, `moonshotBalance`, `antigravityAccounts`).
  `providerPayloadVersion` deliberately NOT bumped — additive optional
  fields stay wire-compatible with iOS 1.6.0 (126) readers.
- `ProviderDetailView.primaryUsageSection` now skips the generic
  rate-window list when a dedicated typed card (Kiro / Bedrock /
  Moonshot) claims the primary slot — avoids double-rendering.

### Backward compatibility

- Old Mac (pre-0.26.1 fork patch) clients: every new field decodes to
  `nil`, every new card stays hidden. The detail page falls through to
  the existing rate-window / cost-summary / utilization-history /
  daily-chart sections exactly as in 1.6.0 (126).
- iOS 1.6.0 (126) reading a NEW Mac payload (post-0.26.1): same —
  unknown keys ignored, baseline cards render normally. This is what
  lets the Mac 0.26.1 release ship paired with the currently-installed
  iOS 1.6.0 before iOS 1.7.0 itself reaches users.

### Required Mac version

- Mac 0.26.1 (fork build 63.2 or later) for the new typed cards. iOS
  1.7.0 (129) is forward-compatible with the previous Mac build
  (0.25.2 / 61.2) — new cards stay hidden, other functionality
  unchanged.

### Added

- **OpenAI API Dashboard** — `Views/OpenAIDashboardSection.swift`. On
  the `openai` provider detail page when `openAIAPIDashboard != nil`:
  3-card Today / 7d / 30d summary, 30-day spend bar chart, top models
  + top line items lists. Mirrors upstream v0.26.1 menu addition.
- **Kiro credits card** — `Views/KiroCreditsCard.swift`. Plan tag +
  primary credit progress + optional bonus pool with localized expiry
  countdown (1 day / N days / expired). Mirrors upstream PR #933.
- **AWS Bedrock cost card (NEW provider)** — `Views/BedrockCostCard.swift`.
  Monthly spend, optional budget gauge with 75% / 90% threshold colors,
  active region. Mirrors upstream PR #897.
- **Moonshot / Kimi API balance card (NEW provider)** —
  `Views/MoonshotBalanceCard.swift`. Balance amount + currency + region.
  Mirrors upstream PR #911.
- **z.ai hourly chart** — `Views/ZaiHourlyChart.swift`. Stacked per-model
  hourly token bars over the active 24-hour window, with chart legend.
  Mirrors upstream PR #913.
- **Antigravity multi-account switcher** —
  `Views/AntigravityAccountSwitcher.swift`. Read-only list of linked
  Google accounts with active marker + relative token expiry. Surfaces
  when Mac populates `antigravityAccounts` (follow-up plumbing).
- **Settings: Hide quota-warning markers** —
  `MobileSettingsKeys.hideQuotaWarningMarkers`. Suppresses the
  tick-marks on usage bars while leaving the quota-warning notification
  intact. Mirrors upstream PR #918.
- **Settings: Show provider changelog links** —
  `MobileSettingsKeys.showProviderChangelogLinks`. Opt-in toggle for a
  future "Provider changelogs" section. Mirrors upstream PR #929.
- **6 new entries in `Preview Content/PreviewData.swift`** — kiroProvider,
  bedrockProvider, moonshotProvider, zaiProvider, openAIDashboardProvider,
  antigravityMultiAccountProvider — all wired into `sampleSnapshot`.
- **Provider color palette additions** — moonshot (indigo), bedrock
  (AWS orange), kiro (emerald), zai (slate teal), antigravity (magenta).
  Removes fallback `.blue` for these providers.

### Changed

- Wire schema extension — `ProviderUsageSnapshot` gains six optional
  `decodeIfPresent` fields (`openAIAPIDashboard`, `zaiHourlyUsage`,
  `kiroCredits`, `bedrockCost`, `moonshotBalance`, `antigravityAccounts`).
  `providerPayloadVersion` deliberately NOT bumped — additive optional
  fields stay wire-compatible with iOS 1.6.0 readers (the older app
  silently ignores the new keys).
- `ProviderDetailView.primaryUsageSection` now hides the generic
  rate-window list when a dedicated typed card (Kiro / Bedrock /
  Moonshot) claims the primary slot — avoids double-rendering.

### Backward compatibility

- Old Mac (pre-0.26.2) clients: every new field decodes to `nil`,
  every new card stays hidden. The detail page falls through to the
  existing rate-window / cost-summary / utilization-history /
  daily-chart sections exactly as in 1.6.0.
- Old iOS (1.6.0) clients reading a new Mac payload: same — unknown
  keys ignored, baseline cards render normally.

### Required Mac version

- Mac 0.26.2 or later for the new typed cards (Kiro / Bedrock /
  Moonshot / z.ai / OpenAI Dashboard / Antigravity). iPhone is
  forward-compatible with Mac 0.26.1 — new cards stay hidden, all
  other functionality still works.

---

## [1.6.0 (126)] — 2026-05-16 — Quota warning markers + Mac→iOS push (S4 closing 1.6.0)

iOS 1.6.0 closes Stage 2 with quota warning markers + the Mac→iOS
warning push pipeline so the iPhone alerts the user at configured
thresholds (e.g. 50%, 20% remaining) instead of only at full depletion.
iOS is a pure receiver: thresholds + enable flags live on Mac per
provider × window; Mac packs the resolved config into each
`ProviderUsageSnapshot` and iOS renders matching tick marks on every
usage bar.

### Added

- **Quota warning markers on the Usage bar** — `UsageCardView` overlays
  threshold tick marks at the `100 - remainingPercent` positions on
  the progress bar. When the user crosses the most critical threshold
  (lowest remaining-percent value, e.g. 20%), an
  `exclamationmark.triangle.fill` icon appears next to the card title.
  Default thresholds match Mac: `[50, 20]` = 50% remaining and 20%
  remaining. Per-provider overrides on Mac flow through transparently.
- **Mac → iOS quota warning push** — when usage crosses a threshold on
  Mac, the iPhone receives a localized push that names the specific
  window + threshold ("Codex session usage at 50% threshold" /
  "Codex 会话用量已达 50% 阈值"). Subscription matrix expands 76 → 114
  zones (38 providers × 3 states: depleted + restored + warning).
  Per-provider × window debounce so multi-threshold crossings within
  the same hour don't suppress each other.

### Changed

- Wire schema: `ProviderUsageSnapshot.quotaWarnings` (new optional
  `SyncQuotaWarningConfig` field). Optional + `decodeIfPresent` so a
  pre-1.6.0 iOS reading a new payload (or a new iOS reading a pre-Mac
  0.25.2 payload) decodes cleanly with `nil`, which iOS then falls
  back to Mac's documented defaults `[50, 20]` for visual rendering.
- iOS `Localizable.xcstrings` +5 keys × 4 languages for the warning
  push body + window labels (session/weekly).
- `QuotaZoneNotificationParser.isQuotaPushZone` now recognizes
  per-provider zones (`Quota-{provider}-{state}Zone`). Side-effect:
  fixes a pre-existing silent bug where the NSE wasn't enriching
  depleted/restored pushes either since Build 54 introduced
  per-provider zones (the parser had stayed pinned to the old global
  zones `QuotaDepletedZone` / `QuotaRestoredZone`).

### Fixed

Three bugs caught during pre-release on-device QA, all required for
the rich push body to actually surface on the iPhone — fold into the
1.6.0 release notes as one set since none of them ever reached real
users.

- **NSE wake-up flag.** `QuotaTransitionSubscriptions` was creating
  every `CKSubscription.NotificationInfo` without
  `shouldSendMutableContent = true`, so APNS delivered the static
  fallback alertBody only and the `NotificationService` extension
  never ran — making the rich body rewrite dead on arrival.
  Drift detection now re-saves subscriptions missing the flag so an
  in-place upgrade picks up the fix on first launch without manual
  cleanup. 4 new `QuotaTransitionSubscriptionsTests` pin the
  `NotificationInfo` factory so the regression can't recur.
- **NSE staleness — fetch returned the wrong record.** The NSE
  originally sorted by `transitionAt desc` server-side and took
  resultsLimit:1, but CloudKit updates that secondary index
  **asynchronously after record save** — the push fires BEFORE the
  index catches up, so the sorted+limited query routinely returned
  the previous burst's record instead of the one that just fired.
  On-device repro confirmed `Claude session 20` rewriting a push
  triggered by `Claude weekly 10`. Replaced with a no-sort fetch
  (resultsLimit:100) + client-side sort by server-authoritative
  `record.creationDate`, which doesn't go through a secondary
  index. 5/5 burst test verified correct body content end-to-end.
- **CloudKit Production schema deploy.** `transitionAt` was
  Queryable but not Sortable on the Production schema, so the
  original sort-based fetch failed with `code=12 Field 'transitionAt'
  is not marked sortable` and the NSE delivered the static fallback
  on every push. After the staleness fix above we no longer depend
  on this index, but Sortable was deployed during diagnosis and is
  fine to keep.

### Tests

- 18 new tests for `SyncQuotaWarningConfig` (Codable round-trip,
  backward-compat decoding, threshold sanitize, fallback chain).
- 10 new tests for `QuotaZoneNotificationParser` covering all three
  per-provider states + recordName parsing edge cases.
- 3 new Mac tests for the push fire path (gate on, gate off,
  multi-threshold crossings).
- 4 new `QuotaTransitionSubscriptionsTests` for the NSE wake-up flag.
- Updated Mac and iOS `QuotaProviderListTests` to 114 zones (38 × 3).

### Versions

- iOS `MARKETING_VERSION`: 1.6.0 (unchanged)
- iOS `CURRENT_PROJECT_VERSION`: 120 → 126
- Mac partner release: 0.25.2 with `CloudSyncManager.writeQuotaWarningTransition`
  + `QuotaTransitionWriter.writeQuotaWarning` + `UsageStore` fire hook.
  Ships in our fork; upstream sync is independent. If the user is on
  Mac 0.25.1 the iPhone still renders Mac-default markers via the
  fallback chain, just no active push until the Mac update lands.

## [1.6.0 (120)] — 2026-05-13 — Stage 2 catch-up: 11 new providers + Claude peak-hours

iOS 1.6.0 closes the catch-up gap from Mac 0.25.1: the 11 new providers
that arrived in upstream v0.24+v0.25 (Windsurf / Codebuff / DeepSeek /
Manus / Xiaomi MiMo / Doubao / Command Code / StepFun / Crof / Venice /
OpenAI API) now render natively in iOS — distinct brand colors across
Usage / Cost / Subscription tabs and a push subscription for each so
quota events fire notifications. Plus Claude's peak-hours indicator
from v0.24 finally surfaces on the iOS Claude detail page.

### Added

- **11 new providers native rendering** (S1, commit `0369d816`).
  ProviderColorPalette extended with 10 brand-aligned colors (openai
  inherits the existing ChatGPT-green rule). 36 palette tests pin
  perceptual distinctness against existing colors (Mistral red, Abacus
  brown, Claude orange-tan, etc.) so a future palette retune can't
  silently collapse two providers into the same color.
- **11 new providers push subscriptions** (S2, commit `ab34cdd6`).
  `QuotaProviderList` 27 → 38, subscription zone count 54 → 76. New
  IDs appended at the tail so existing 54 CK subscription IDs stay
  byte-identical across the upgrade (no re-subscribe churn for
  installed users).
- **Claude peak-hours iOS indicator** (S5, commit `18b0080b`).
  iOS port of Mac's `ClaudePeakHours` (v0.24 PR #611) — pure
  client-side time-of-day computation (8am-2pm America/New_York,
  weekdays). Shows "Peak · ends in 2h 30m" or "Off-peak · peak in
  5h" on the Claude detail page. 20 locale-aware tests pin the
  detection logic.
- **MockProviderInjector 32 → 43** (S6, commit `98d732ea`). 11 new
  simple-mock entries for the v0.24+v0.25 providers, with realistic
  usage / cost values so QA can flip `CODEXBAR_MOCK_PROVIDERS=1` and
  exercise every new iOS render path without real subscriptions.
  Mac fork-private change; needs a Mac rebuild to surface (does NOT
  trigger a Mac MARKETING_VERSION bump per the
  "match-upstream-tag" policy).

### Changed

- iOS `xcstrings` +3 keys × 4 languages for the peak-hours labels.
- Mac fork's `realProviderIDsBorrowedByMocks` Set extended with the
  11 new IDs; comment notes the three-way invariant
  (`simpleProviderProfiles` ↔ `realProviderIDsBorrowedByMocks` ↔
  `QuotaProviderList`).
- User-facing mock subtitle strings updated: "32 synthetic ... 24
  simple omitted" → "43 synthetic ... 35 simple omitted".

### Deferred to 1.6.1

- **Codex stacked/segmented switcher iOS mirror** (R7.3): iOS card
  layout is already inherently "segmented" (one card per account);
  Mac's stacked mode is a menu-bar compactness trade-off iOS doesn't
  need. Decision: not mirrored.
- **pt-BR localization**: in upstream 0.26-dev (unreleased). Per
  "only track released tags" policy, hold until upstream tags v0.26.

### Versions

- iOS `MARKETING_VERSION`: 1.5.3 → 1.6.0
- iOS `CURRENT_PROJECT_VERSION`: 119 → 120
- Mac unchanged (still v0.25.1-mobile.1.5.3 → next Mac release will
  bump `MOBILE_VERSION` to 1.6.0)

## [1.5.3 (119)] — 2026-05-12 — In-app release notes for 1.5.3 + archive plan.md

Builds 114–118 shipped the 1.5.3 fixes/features but forgot to update
the in-app `MobileReleaseNotesCatalog` (`ContentView.swift`). Users
opening Settings → Release Notes after installing 1.5.3 still saw
1.5.2 as Latest. Build 119 fixes that.

### In-app release notes catalog

- New `1.5.3` entry inserted as `Latest`; 1.5.2 demoted to historical.
- Content mirrors `AppStoreMetadata/1.5.3/en-US/release_notes.txt`:
  single-line summary + 5-bullet "Recent updates" section + Mac
  version requirement.
- 8 new strings added to `Localizable.xcstrings` (314 → 322 keys),
  each with English / Simplified Chinese / Traditional Chinese /
  Japanese translations mirroring the App Store release notes files
  (`AppStoreMetadata/1.5.3/<locale>/release_notes.txt`).

### plan.md archived

- Moved `plan.md` → `Archive/plan-archived-2026-05-12.md`.
- Added ARCHIVED header at top of the file pointing to new sources
  of truth (the prior content was already 4 versions stale and led
  an automation routine to read v0.19.0 as the current upstream
  alignment when reality was v0.25.1).
- `CLAUDE.md` updated to remove both references to `plan.md`.
- Authoritative current state now lives in:
  - `version.env` — current version + upstream alignment
  - `AGENTS.md` — workflow + agent rules
  - `CodexBarMobile/CHANGELOG.md` — iOS changelog
  - Todoist project "Dev" — task tracking

### Versions

- iOS CURRENT_PROJECT_VERSION: 118 → 119
- Marketing version stays 1.5.3
- Mac unchanged

## [1.5.3 (118)] — 2026-05-12 — App Store submission build (no source changes from 117)

Build-number bump only. App Store Review and TestFlight are kept on
distinct build numbers per our install discipline. Source identical
to build 117 (same crash fix + audit hardening + Research/019 L3
LinkageRecord). No code, tests, or assets touched.

### App Store release notes generated

4 localized release_notes.txt files under
`CodexBarMobile/AppStoreMetadata/1.5.3/{en-US,zh-Hans,zh-Hant,ja}/`.
Single-line 1.5.3 callout + 5-bullet "Recent updates" condensed
recap of the 1.5.0 highlights. Plain text, ready to paste into ASC's
What's New in This Version localized fields.

### Versions

- iOS CURRENT_PROJECT_VERSION: 117 → 118
- Marketing version stays 1.5.3
- Mac unchanged

## [1.5.3 (117)] — 2026-05-11 — Post-review hardening for the 116 hotfix

Same crash fix as 116, plus the formal post-commit code-review pass
that was skipped before pushing 116:

### Audit test added

New `CKRecordReservedKeyAuditTests` source-scan suite (2 tests):
1. `reservedNameAssignmentsAbsent` — regex-scans the audited source
   files for `record["recordID"] = ...` style assignments using any of
   CloudKit's 7 reserved field names. Failing this test means a new
   commit reintroduced the build-115 crash class.
2. `auditCoverageCompletes` — walks the project tree, finds every
   `.swift` file that writes CKRecord fields (excluding tests), and
   verifies all of them are listed in `auditedRelativePaths`. Adding a
   new file that writes CKRecord fields fails this test until the
   developer updates the audit list.

Why source-scan vs unit test: a unit test that "expects a crash"
doesn't work for ObjC exceptions because they terminate the test
runner. Static-source check is the portable equivalent.

### Retry-loop trade-offs documented

The `performFullFetch` retry that re-saves locally-cached linkages
absent from CloudKit (the build-115 recovery path) was already correct
but lacked inline notes on the deliberate trade-offs:
- No exponential backoff (acceptable given typical 1-5 fetches per
  session and 1-2 pending linkages).
- No in-flight save deduplication (CKDatabase.save is idempotent on
  identical recordID; cost is one wasted round-trip).
- `pending` captured by value, `[weak self]` defensive.

Comment now documents these explicitly so future reviewers don't
mistake them for missing functionality.

### Versions

- iOS CURRENT_PROJECT_VERSION: 116 → 117
- Marketing version stays 1.5.3
- Mac unchanged

### Tests

- 304 tests / 24 suites passing (302 from build 116 + 2 audit).
- Lint: 0 violations.
- Mac swift build: passes.

## [1.5.3 (116)] — 2026-05-11 — Fix LinkageRecord ObjC-exception crash on "Same account?" tap

Hotfix on top of build 115. User QA found the inline "Yes, same
account" button crashes the app with `SIGABRT` from an ObjC
`NSException`.

### Root cause

`CloudSyncManager.saveProviderAccountLinkage(_:)` set
`record["recordID"] = linkage.recordID as CKRecordValue`.
`recordID` is a **reserved CKRecord field name** — it shadows the
built-in `CKRecord.recordID: CKRecord.ID` property. CloudKit's
`-[CKRecordValueStore setObject:forKey:]` raises an `NSException`
when a reserved key is targeted, which Swift can't catch because
it's an ObjC exception, so the app `abort()`s.

Crash trace (from user's incident report):
```
13 CodexBarSync CloudSyncManager.saveProviderAccountLinkage(_:) + 300 (CloudSyncManager.swift:967)
12 CloudKit     CKRecord.subscript.setter
11 CloudKit     -[CKRecord setObject:forKey:]
10 CloudKit     -[CKRecordValueStore setObject:forKey:]
 9 libobjc      objc_exception_throw
```

### Fix

The linkage UUID is already encoded in the CKRecord's name (the
`"linkage-{UUID}"` `recordName` prefix). Removing the redundant
payload field eliminates the collision:

- `saveProviderAccountLinkage` no longer sets `record["recordID"]`.
- `decodeLinkage` reads the linkage UUID back from
  `record.recordID.recordName` (strips the `"linkage-"` prefix).
  Records that lack the prefix return `nil` (defensive: a foreign
  record type that hit our query is not ours).

### Recovery of build-115 stranded merges

A user who tapped "Yes, same account" on build 115 had their
linkage applied locally (UserDefaults cache) but it never reached
CloudKit. Build 116 retries the save on next full fetch: any
locally-cached linkage NOT present in the CloudKit fetch result
gets re-saved through `saveProviderAccountLinkage`. Side effect of
the existing local↔cloud union path in `performFullFetch`. Fires
quietly in the background; failures stay local and re-retry on the
next refresh.

### Tests

- New `LinkageRecordMergeTests`: CKRecord round-trip without the
  reserved-field-name collision + foreign-record-name rejection.
  Both build an in-memory `CKRecord` (no CloudKit auth needed) and
  exercise `decodeLinkage` directly.
- 302 tests total (300 from build 115 + 2 regressions) passing.
- `./Scripts/lint.sh lint`: 0 violations.

### Versions

- iOS `CURRENT_PROJECT_VERSION`: 115 → 116
- Marketing version unchanged (still 1.5.3)
- Mac unchanged (0.25.1 / 61)

## [1.5.3 (115)] — 2026-05-11 — Ship Research/019 §7 + §9 (cross-version account-link)

Supersedes build 114. Adds the iOS half of the Research/019
multi-version account-identity merge that was design-locked but never
shipped, on top of the build-114 ForEach id collision fix.

### Why we needed this

Build 114 fixed three SwiftUI id collisions so two-Mac users with one
Mac extracting `accountEmail` and another not would at least render
both cards correctly. It did NOT merge them. The user (with Mac
0.23.6 + Mac 0.25.1 on the same Codex account) still saw two cards
on the Usage tab because the union-find merge keys never overlap
across legacy-no-identity and email-bucket entries — designed
behavior per Research/019 §8.7, expected to be bridged by §7 L3
LinkageRecord which had never been implemented.

### What's now built

**L3 user-confirmed merge** (§7 + §7.4):
- New CKRecord type `ProviderAccountLinkage` in `DeviceProvidersZone`.
  Fields: `recordID` (UUID), `providerID`, `linkedIdentifiers`,
  `confirmedAt`, `confirmedFromDeviceID`, `unmerge` (bool).
- Saved by `CloudSyncManager.saveProviderAccountLinkage(_:)`, fetched
  by `fetchProviderAccountLinkages()`. Rides the existing per-provider
  zone subscription so concurrent iPhone confirmations propagate
  through the same change-token stream.
- `CloudSyncReader.mergeSnapshots(_:linkages:)` applies linkages as
  additional union-find edges AFTER the L1+L2 identifier-based pass.
- Unmerge: an inverse linkage with `unmerge=true` carries the same
  `linkedIdentifiers` (set-equality canonical key); on next read,
  the corresponding merge edge is suppressed. Order-independent.

**Inline UI** (§9):
- New `MultiAccountLinkageCandidate` model identifies the
  "one-named + N-legacy" cross-version pattern. Detector skips
  ambiguous (≥2 named) cases — multi-account-on-named requires a
  picker UI, deferred.
- `ProviderUsageView` shows an inline prompt on the LEGACY card with
  "Yes, same account" / "Keep separate" buttons. The body text
  mentions the older Mac's CodexBar version (e.g. "0.23.6") when iOS
  knows it, hinting that upgrading would auto-link.
- Long-press on a merged card → context menu "Unmerge Accounts"
  writes the inverse linkage.

**Persistence**:
- Linkages cached in UserDefaults so cold-start applies them BEFORE
  the first CloudKit fetch returns. CloudKit remains the source of
  truth; the cache is repopulated on every full fetch.
- Local linkage appends survive a concurrent refresh:
  `performFullFetch` unions cloud results with locally-confirmed
  records that haven't round-tripped through CK yet, deduping by
  `recordID`.

**Localization**:
- 5 new keys in `Localizable.xcstrings` × 4 languages each:
  `Yes, same account`, `Keep separate`, `Unmerge Accounts`,
  `linkage-prompt-headline`, `linkage-prompt-detail-with-version`,
  `linkage-prompt-detail`.

### Tests

- New `LinkageRecordMergeTests` (10 cases): §8.11 override, §7.4
  unmerge + order-independence, concurrent merge idempotence,
  wrong-providerID no-op, no-overlap no-op, Codable round-trip,
  missing-unmerge backward-compat decode, inverseUnmerge helper,
  UserDefaults cache round-trip, empty cache load.
- New `MultiAccountLinkageDetectorTests` (8 cases): unambiguous emit,
  multi-legacy fan-out, two-named-skip, zero-named-skip,
  single-card-skip, cross-provider isolation, appVersion surfacing,
  deterministic ordering.
- Existing `AccountIdentityMergeTests` (§8.1–§8.10) still pass.
- Full iOS test suite: 300 tests / 23 suites passing.
- `./Scripts/lint.sh lint`: 0 violations across 820 files.
- Mac `swift build`: passes.

### Versions

- iOS `MARKETING_VERSION`: 1.5.3 (unchanged from build 114)
- iOS `CURRENT_PROJECT_VERSION`: 114 → 115 (supersedes prior upload)
- Mac unchanged (still 0.25.1 / 61)

### Out of scope (deferred)

- Multi-named-card picker UI for the ambiguous (≥2 real accounts on
  the named side + ≥1 legacy) case. Currently the detector emits no
  candidate so the cards stay split — user has to upgrade the older
  Mac for auto-merge. Tracked as `MultiAccountLinkageDetector` rule
  §7-A future-work in `Research/019.md` §14.5.
- Research/017 items 2 and 3 (orphan subscription cleanup, latestNonNil
  accountEmail merge). Item 3 is superseded by L3 LinkageRecord;
  item 2 is unrelated to the current pain and stays open.

## [1.5.3 (114)] — 2026-05-11 — Fix multi-account ForEach id collisions

Single-purpose bug-fix release that closes three latent SwiftUI
`ForEach` id collisions exposed when a user has the same provider
authenticated on two Macs but only one of them populates
`accountEmail`. Shipped ahead of any Mac feature release that
introduces per-account email extraction (e.g. upstream 0.25's
Codex multi-account refactor) so users are protected before Mac
upgrades reach them.

### Bug

User has two Macs running CodexBar. Both write a snapshot for the
same provider (Codex, in the reproduction case). Mac-A captured
`accountEmail = "user@…"`, Mac-B captured `accountEmail = nil`.
After merge, iOS holds two distinct `ProviderUsageSnapshot` rows
with the same `providerName = "Codex"` but different
`accountEmail`s — they're correctly two separate cards on the
Usage tab (which keys on `cardIdentityKey = providerID|accountEmail`).

On the Cost tab and Subscription Utilization aggregate, however,
three downstream identity sites still keyed on `providerID` or
`providerName` alone:
1. `CostBreakdownRow.id = label` (provider name) — Provider Share
   list collapsed both Codex rows into one rendering slot, then
   re-rendered both with the first row's data; the second
   account's $$$ vanished.
2. `CostBudgetRow.id = providerID` — same collapse for budget
   tracking.
3. `UtilizationAggregateView.ProviderShare.id = providerID` and
   `DaySegment` ForEach iterating on `\.providerID` — daily-bar
   stacking and 30-day share list rendered the second account
   with the first's data.

User-visible symptom: Cost dashboard's Provider Share row for
Codex shows the same $$$ value twice, the second account's cost
silently dropped from the total contribution view even though
the running total at the top includes both (because the running
total iterates the underlying `providerRows`, not the rendered
view).

### Fix

Switch all three id sites to the multi-account-aware composite
key (`providerID|accountEmail`, already exposed as
`ProviderUsageSnapshot.cardIdentityKey`):

- `CostBreakdownRow` gains an optional `identityOverride: String?`
  that the Provider Share construction site fills with
  `ProviderRow.id` (= `cardIdentityKey`). Existing Model Mix /
  Codex Service Mix call sites pass `nil` and continue keying on
  `label`, which is already unique for those breakdowns.
- `CostBudgetRow.id` switches to `provider.cardIdentityKey`.
- `UtilizationAggregateView.buildModel` now puts `cardIdentityKey`
  into `providerData.id` (which feeds both `ProviderShare.id` and
  the per-day `DaySegment.providerID` ForEach key).
  `DaySegment.providerID` field name retained for source
  stability — a docstring marks it as an opaque ForEach id.

Single-Mac / single-account users see zero behavior change: when
there's only one row per provider, the composite key is just
`providerID|<email>` and remains unique.

### Test coverage

- `xcodebuild test -only-testing:CodexBarMobileTests` on iPhone 17
  Pro / iOS 26.4: passes.
- Manual repro: two Macs with same Codex account, one with email
  populated, one without — Cost tab now shows two distinct rows
  with distinct $$$ values.

### Not in this release

- `QuotaProviderList.providers` expansion for upstream's new
  providers (openai/manus/windsurf/mimo/doubao/deepseek/codebuff/
  crof/venice/commandcode/stepfun): that's a push-subscription
  feature addition, not a bug fix. Deferred to a future iOS
  release that lands alongside specific iOS UI for those
  providers. Old Mac never wrote to those zones; new Mac writes
  but no push fires on 1.5.3, by design.

## [1.5.2 (113)] — 2026-05-06 — Fix cold-launch crash (App Store rejection)

App Store Review rejected 1.5.2 (112) with "App crashed after the
initial launch". Crash captured on a fresh iOS 26.2 simulator
(`CodexBarMobile-2026-05-06-171237.ips`):

```
EXC_BREAKPOINT (SIGTRAP) on com.apple.cloudkit.CKProcessScopedStateManager.notificationQueue
_swift_task_checkIsolatedSwift
@objc AppDelegate.iCloudAccountChanged() (CodexBarMobileApp.swift:166)
__CFNOTIFICATIONCENTER_IS_CALLING_OUT_TO_AN_OBSERVER__
```

Root cause: `AppDelegate` is implicitly `@MainActor`-isolated under
Swift 6 strict concurrency (because of `UIApplicationDelegate`
conformance). The `@objc` `iCloudAccountChanged()` method was
registered as a `NotificationCenter` observer for `.CKAccountChanged`,
which CloudKit posts on a background notification queue. The
runtime's executor-isolation check trapped on the very first
account-state read. Crash fired on every cold launch on a fresh
device — including Apple's review device.

Fix: marked `iCloudAccountChanged()` as `nonisolated`. The body
already hops to `@MainActor` via `Task { @MainActor in ... }` for
the actual subscription setup, so this is purely a thread-safety
annotation on the entry point.

Verified on a fresh iOS 26.2 simulator with no iCloud account
signed in — app now stays alive across cold launches. Build 113
is ready for App Store resubmission.

## [1.5.2 (112)] — 2026-05-05 — Bump Mac pairing version to 0.23.6 + gate Mock UI

Mac version bumped 0.23.5 → 0.23.6 (0.23.5 was internal-only,
never shipped). All catalog + xcstrings + release-notes draft
references updated to "Mac 0.23.6". Plus Mac-side gate: the
Settings → Mobile → Debug · Mock Provider Data section is now
hidden unless Mac is launched with `CODEXBAR_MOCK_PROVIDERS`
env var, keeping the Settings pane clean for normal users while
preserving toggle access during debug sessions. Build 112 is
content-only on the iOS side; the gate change is in the Mac
binary (0.23.6 / 58.6).

## [1.5.2 (111)] — 2026-05-05 — Rewrite 1.5.2 release notes in product-style language

User feedback: previous catalog entry led with developer-facing
feature names (MOCK badge, top banner, settings diagnostics, etc.)
that meant nothing to end users. Rewritten to lead with the
user-facing fix that drove this release — multiple Codex accounts
not displaying on iPhone — followed by the value-add (27-provider
real-data regression test suite for sync stability) and the
remaining minor fixes. Drops first-person "we" and marketing
fluff. Build 111 is content-only; same code as 110.

## [1.5.2 (110)] — 2026-05-05 — Merge in-app release notes into a single 1.5.2 entry

In-app `MobileReleaseNotesCatalog` had two separate 1.5.2 entries
(`1.5.2 (103)` and `1.5.2 (108)`) — build numbers should never appear
as user-facing catalog entries. Merged into one `1.5.2` entry covering
the mock-visual-treatment items + the build-107 mock orphan filter
fixes + the Required Mac version pairing. Build 110 is content-only;
same code as 109. Updates Localizable.xcstrings with merged-summary
translations across en / ja / zh-Hans / zh-Hant.

## [1.5.2 (109)] — 2026-05-05 — Localize Raw Sync Data row strings (R3 review)

Codex MCP review of f6958cb8..889555ee flagged 3 hardcoded English
strings I introduced in `RawProviderRow` while wiring up the diagnostic
upgrade in 107: `(no email)`, `$%.2f / 30d`, `$%.2f / today`. These
violated the project's 4-language localization contract — Chinese /
Japanese users would see English fragments inside the otherwise
localized Raw Sync Data view.

Wrapped all 3 in `String(localized:)` with `comment:` for translator
context, and added zh-Hans / zh-Hant / ja translations in xcstrings.
No other code change.

## [1.5.2 (108)] — 2026-05-05 — Release notes refresh

In-app release notes catalog updated for the 1.5.2 (107) hotfix per
user feedback: shorter, less technical, no `Important` callout, and
adds an explicit Mac-version-pairing section pointing users to the
required Mac 0.23.6 build. No code change beyond the catalog text +
Build 108 bump so the binary embeds the updated copy. Pairs with
Mac 0.23.6 hotfix (commit `4e633c02`) which adds CloudKit reconcile
on Mac startup so stranded mock CKRecords from previous Mac sessions
get cleaned up automatically.

## [1.5.2 (107)] — 2026-05-04 — Mock injection no longer wipes real accountless providers

User QA hit a critical regression after mock-injector landed in
1.5.2 (103) + Mac 0.23.6: real Claude data ($2029 / 30 days) disappeared
from the iOS Cost dashboard while mock Claude entries remained visible.
Root-caused in `SnapshotCache.dropOrphansAndStale` — both filter rules
(Build 94 ghost-orphan + stale-TTL) treated synthetic mock entries the
same as real OAuth-completed accounts, which:

1. **Rule 1 false-positive** — when mock Claude entries had emails (by
   design — `*-mock@*.test` is the universal mock signal) and real
   Claude has nil email (Anthropic doesn't expose one via OAuth), the
   real entry got flagged as a "pre-OAuth orphan" and dropped. Affected
   any provider that's structurally accountless: Claude, Ollama,
   Copilot subscription without enterprise tenant, etc.
2. **Rule 2 false-positive** — mock `lastUpdated` tracks injection time
   (refreshes on every Mac push cycle ≈ 1min) which pushed
   `deviceFreshest` forward, slid the 30-min TTL cutoff, and force-staled
   real nil-email entries that hadn't refreshed in the last cycle.

### Fixed

- `SnapshotCache.dropOrphansAndStale`:
  - Rule 1's `hasRealEmail` check now ignores mock entries — only real
    OAuth siblings count toward "is there a real email here?".
  - Rule 2's `deviceFreshest` is computed from real entries only;
    falls back to all-entries freshest only if every entry is a mock
    (dev/CI scenario). Mocks themselves bypass both filters and are
    always kept.
  - Build 94's original orphan-cleanup intent is fully preserved: a
    real nil-email orphan alongside a real email-bearing sibling
    still drops as before. The fix only changes behavior when mocks
    are present, restoring real accountless providers to the view.

### Added

- 4 new tests in `SnapshotCacheTests.swift` covering the mock-vs-real
  interaction:
  - Real nil-email Claude survives when only mock siblings have email
  - Mock fresher timestamp does not stale-out real nil-email entry
  - Mock-only device falls back gracefully to anyFreshest in Rule 2
  - Mock with nil email kept when sibling mock has email (defensive)

### Changed

- `RawSyncDataView` provider rows now show `accountEmail` as a
  subtitle and `last30DaysCostUSD` (not session) inline, so
  multi-device sync issues become visible at the row level without
  needing to drill into detail.

## [1.5.2 (103)] — 2026-05-03 — Mock provider visual treatment

Pairs with **Mac 0.23.6** which introduced the synthetic mock-provider
injection layer. iOS 1.5.2 adds the visual treatment that makes mock
data unmistakable so QA / Beta testers can't mistake it for real
spend.

### Added

- `MockProviderDetector` (`Models/MockProviderDetector.swift`) — single
  source of truth for "is this snapshot a mock?". Inspects the universal
  `*-mock@*.test` email TLD AND the synthetic `_mock_*` providerID
  prefix; either signal is sufficient. Real users without mock
  activation never hit either signal.
- `MockBadgeView` (`Views/MockBadgeView.swift`) — purple "MOCK" pill
  shown next to provider name in card header + detail-page toolbar.
  9pt monospaced bold, never localized (industry-standard tag).
- `MockProviderBanner` (`Views/MockProviderBanner.swift`) — top-of-tab
  banner shown above Usage tab and Cost tab whenever the snapshot
  contains synthetic providers. Shows count + instructions for
  toggling off on Mac.
- `ProviderUsageView` purple accent border when card holds mock data.
- `ProviderDetailView` inline mock banner + toolbar MOCK badge.
- Settings → Diagnostics section, visible only when mock data is
  active. Shows live count + instructions.
- 4-language localization for 8 new mock-related user-facing strings
  (en + ja + zh-Hans + zh-Hant).
- `MockProviderDetectorTests.swift` — 17 unit tests pinning detection
  contract: real-borrowed-id+mock-tld is mock, synthetic-prefix is
  mock, real-id+real-email is NOT mock, .test in middle of email is
  NOT mock, snapshot-level helpers correct.

### Changed

- `project.yml` — `MARKETING_VERSION` 1.5.1 → 1.5.2,
  `CURRENT_PROJECT_VERSION` 102 → 103.
- In-app release notes — 1.5.2 entry added to `MobileReleaseNotesCatalog`.

### Unchanged

- Wire format. Mac 0.23.6's mock injection passes through the
  existing CKRecord schema. iOS 1.5.1 users still see mock data as
  ordinary cards (no badge, no banner) — the visual treatment is
  purely additive on iOS 1.5.2.
- Sync layer, push subscriptions, all existing 27 provider rendering.

## [1.5.1 (102)] — 2026-04-29 — GitHub repo renamed to CodexBar-Mobile

Maintenance release on top of 1.5.0 (101). The fork's GitHub repository
was renamed from `o1xhack/CodexBar` to `o1xhack/CodexBar-Mobile` to
avoid confusion with the upstream Mac-only repo. All in-app download /
About / "Update Mac" links now point to the new URL. Existing links
continue to work via GitHub's permanent redirect.

### Changed

- 15 files / 69 hardcoded references updated across iOS user-facing
  strings (`ContentView.swift`, `OnboardingView.swift`),
  `Localizable.xcstrings` keys + 4 language values, in-app release
  notes, project docs, and release tooling scripts.
- README adds a second download badge for the Mac app next to the
  existing App Store badge, both at the same visual size; uses the
  same SVG that the website (codexbarios.o1xhack.com) ships.
- In-app 1.5.1 release notes prepend a single `Important` bullet
  flagging the rename. Rest of the user-visible 1.5.0 release notes
  content is preserved verbatim.

### Unchanged

- Bundle identifiers (`com.o1xhack.codexbar.mobile`, etc.) — TestFlight
  and App Store installs are unaffected.
- iCloud container, push entitlements, CloudKit Production environment.
- Wire format, CloudKit schema, sync layer, all 27 providers, and every
  feature surface from 1.5.0.
- Mac source files (`Sources/CodexBar/About.swift`,
  `PreferencesAboutPane.swift`) still reference the old URL — deferred
  per `CLAUDE.md` (Mac code is upstream-maintained).

## [1.5.0 (101)] — 2026-04-28 — Important callout simplified + tappable download link

Two user-driven polish edits to the in-app 1.5.0 release notes:

- **Important callout merged into one short bullet.** Build 100 had two
  long Important paragraphs (one for new-provider requirement, one
  for Cost-tab parser fix); user feedback was "too complex, two-three
  lines max". Merged into a single sentence noting Mac 0.23.4 is the
  recommended version both for the new providers and for accurate
  Cost numbers.
- **Download URL is now a tappable link.** `ReleaseNotesContent`'s
  bullet rendering switched from `Text(item)` to `Text(.init(item))`
  so SwiftUI parses the string as `LocalizedStringKey`, which honors
  markdown link syntax `[label](url)`. `.tint(.accentColor)` applied
  so the link picks up the system accent color. Existing items
  without markdown render unchanged.
- 1 new merged string × 4 locales (en / zh-Hans / zh-Hant / ja) = 4
  translation entries. The 2 obsoleted Important strings were removed
  from `Localizable.xcstrings`. i18n audit clean.

No code-behavior changes from Build 100. Same union-find merge, same
fallback resolver, same parser-fix wire-format.

## [1.5.0 (100)] — 2026-04-28 — in-app release notes refresh + Mac 0.23.4 partner build

In-app **What's New** for 1.5.0 now covers everything that landed
across Build 96–99 — the original upstream v0.21–0.23 provider
alignment, the model-name fallback resolver / estimated-cost indicator
that landed in Build 97, and the multi-version Mac account merge
(plus the non-ASCII email follow-up) from Build 98–99. Pairs with Mac
**0.23.4** which is now the recommended Mac version for accurate Cost
numbers.

### In-app release notes (`MobileReleaseNotesCatalog.versions[1.5.0]`)

- New **Important** bullet: requires Mac 0.23.4 for accurate Cost-tab
  numbers (earlier 0.23.x had the parser truncation bug that misattributed
  most token usage to gpt-5).
- New **What's New** bullet: estimated cost for newly-released models
  (the iOS half of Build 97's fallback resolver — Provider Detail card
  shows `*` marker when Mac substituted a fallback price).
- New **What's New** bullet: two Macs, one card — covers Build 98's
  union-find account merging and Build 99's non-ASCII email
  normalization fix in a single user-facing summary.

### Localization

- 3 new strings × 4 locales (en / zh-Hans / zh-Hant / ja) = 12
  translation entries added to `Localizable.xcstrings` ahead of the
  build so the i18n audit stays clean. No `state="new"` regressions.

No code-behavior changes from Build 99. Same union-find merge, same
fallback resolver, same parser-fix wire-format. This build just
refreshes what users see in Settings → Update notes.

## [1.5.0 (99)] — 2026-04-28 — non-ASCII email merge fix (P1-3 from 0.23.3 review)

Companion to Mac 0.23.3. Fixes a P1 surfaced by codex-reviewer during
the 0.23.3 audit: iOS legacy-email synthesis used `trim + lowercased`,
but Mac (≥ 0.23) writes identifiers via NFC + percent-encoding + length
cap. For non-ASCII emails (e.g. `café@example.com`) the two normalizers
produced different bytes, so a 0.23+ Mac and a 0.20.x Mac for the same
account split into two cards on iOS.

### Fix

- Extracted shared normalization to `Shared/iCloud/AccountIdentityNormalize.swift`
  (in CodexBarSync). Both Mac (`AccountIdentityComputer.normalize`)
  and iOS (`CloudSyncReader.effectiveIdentifiers`) now produce
  byte-identical strings for the same input.
- Paired contract tests on Mac (`AccountIdentityComputerTests.normalizeMatchesSharedContract`)
  and iOS (`AccountIdentityNormalizeContractTests`) pin both sides to
  the same fixture outputs — drift on either side breaks both tests.

No other behavior changes. All other 1.5.0 functionality unchanged from
Build 98.

## [1.5.0 (98)] — 2026-04-27 — multi-version Mac account merge

Fixes the recurring "two cards for one Codex account when one Mac is on
0.23 and another on 0.20.3" failure surfaced during the Build 57 / 96
QA. Replaces the single-key `(providerID, accountEmail)` grouping in
`CloudSyncReader.mergeSnapshots` with an identifier-set union-find that
tolerates schema drift across Mac versions. Architecture in
[Research/019](Research/019-account-identity-multi-version-merge.md).

### Wire format · `Shared/Models/UsageSnapshot.swift`

- New optional `accountIdentities: [String]?` on `ProviderUsageSnapshot`,
  decoded via `decodeIfPresent`. Mac writes a stable identifier set
  (e.g. `["codex:account:org-abc", "codex:email:user@example.com"]`);
  iOS unions across Macs by shared identifier.
- Old Mac payloads (≤ 0.20.x) decode the field as `nil`. iOS synthesizes
  `"{providerID}:email:<lowered>"` from `accountEmail` when present, so
  legacy and modern Macs sharing the same email **automatically merge**.

### iOS · CloudSyncReader.mergeSnapshots refactor

- Effective-identifier synthesis: explicit accountIdentities → email
  fallback → `"{providerID}:legacy-no-identity"` bucket (preserves the
  pre-019 behavior where multiple all-legacy Macs collapsed into one
  card).
- Union-find via shared identifier strings; connected components reduce
  through `mergeProviderEntries`.
- Provider IDs are baked into every identifier string so two providers
  can never cross-merge even if they share the same email.

### Tests · 15 new XCTest cases

- `AccountIdentityMergeTests` covers the 11-case test matrix from
  Research/019 §8 (same-version, version-behind, version-ahead,
  transition period, hard-drop policy followed/violated, transitive
  merge, cross-provider isolation, legacy bridge, etc.) plus 4
  effective-identifier synthesis tests.
- All 221 existing iOS unit tests continue to pass.

### Mac side · `Sources/CodexBarCore/Sync/AccountIdentityComputer.swift`

- New `AccountIdentityComputer.compute(provider:identity:)` returns an
  identifier set for Codex / Claude / VertexAI (Tier-A); nil for the
  other 24 providers.
- Normalization: lowercase + Unicode NFC + trim + URL-percent-encode
  the value + 256-char cap. Time-bounded values forbidden.
- 14 Mac-side XCTest cases pin the contract.

### Out of scope (Research/019 §11 deferred items)

L3 user-confirmed `LinkageRecord` is documented but not implemented in
this build — it's only triggered when L1 (Mac multi-identifier writes)
+ L2 (iOS union-find) fail, which requires a deprecation-policy
violation we control. Will land if/when that path is exercised.

## [1.5.0 (97)] — 2026-04-27 — model-name fallback resolver (Mac 0.23 partner build)

Ships the iOS half of a fork-only fallback subsystem in the Mac cost
scanner. Closes the recurring "Daily Spend drops to \$0 when a new
model arrives" failure mode that bit Mac 0.20.3 (when `claude-opus-4-7`
shipped before our pricing table did). See
`Research/018-model-fallback-pricing.md` for the design (P0 of P0–P9).

### Wire format additions

- **`SyncCostBreakdown` / `SyncDailyPoint` / `SyncCostSummary`** in
  `Shared/Models/UsageSnapshot.swift` each gain `isEstimated: Bool?`,
  decoded via `decodeIfPresent`. Old Mac (≤ 0.20.x) payloads decode the
  field as `nil` — iOS treats `nil` as "not estimated" so legacy data
  renders identically. New Mac payloads carry `true` when at least one
  per-model breakdown's cost was substituted from a fallback row.

### iOS UI

- **`Views/CostMetricCard`** — accepts `isEstimated: Bool` and appends
  a `*` to the cost value when set. Accessibility hint speaks
  "Estimated".
- **`Views/ProviderDetailView`** — Today / 30 Days cards consult the
  per-day and summary `isEstimated`; a localized footnote appears
  below the cards when at least one is flagged. (Cost-tab Provider
  Share / Daily Spend bars / Model Mix surfaces are out-of-scope for
  1.5.0; the Provider Detail surface is the hottest path where users
  cross-check Mac vs iOS spend.)

### Localization

- `Estimated` and `* Estimated cost · auto-corrects after Mac upgrades
  to the latest pricing table` added to `Localizable.xcstrings` with
  full en / zh-Hans / zh-Hant / ja translations. CI i18n audit clean.

### Tests

- `SyncCostIsEstimatedTests` (10) pin wire-format roundtrip in both
  directions plus SyncCoordinator OR aggregation (per-breakdown →
  per-day → summary).
- All 221 iOS unit tests + 3 UI tests pass. SwiftLint 0 violations.

## [1.5.0 (96)] — 2026-04-27 — upstream v0.21–0.23 alignment (T1–T9)

iOS-side consumption of Mac v0.23. Every user-visible delta from upstream's 0.21 / 0.22 / 0.23 (Abacus AI + Mistral providers, Claude Designs / Daily Routines / Web Sonnet bars, Cursor Extra usage, Synthetic 5h-weekly-search lane labels, Codex Pro $100 plan) flows to iPhone via the existing wire format that Mac v0.23 already populates — no new Codable types added. Skipped 1.4.0 because 1.3.1 was the App Store hotfix train.

### Added · push subscriptions

- **`Shared/Notifications/QuotaProviderList.swift`** — `Provider(id: "abacus", displayName: "Abacus AI")` + `Provider(id: "mistral", displayName: "Mistral")` appended after the 25-provider tail. Subscription set automatically expands to 54 zones (27 providers × 2 states) on first launch via the existing diff-driven `setupIfNeeded()` path.

### Added · provider color palette

- **`ProviderColorPalette.color(for:)`** — Abacus AI gets warm brown `(0.55, 0.37, 0.24)`, Mistral gets vibrant red `(0.90, 0.22, 0.27)`. Both placed BEFORE the broader Claude / Codex rules so substring fallback ordering preserves specificity. Distinctness from Claude pinned via test (Δ > 0.10 perceptual).

### Added · in-app release notes catalog

- **`MobileReleaseNotesCatalog.versions`** — new `1.5.0` entry as `Latest`, demoting `1.3.0` to historical. Three sections (Important / What's New / Under the hood) covering all T1–T9 user-facing items. 12 new strings added to `Localizable.xcstrings` with full 4-language translations (en / zh-Hans / zh-Hant / ja); CI i18n audit clean.

### Tests

- **`ProviderColorPaletteTests`** — 7 new cases covering Abacus + Mistral colors, distinctness from Claude (cause-oriented Δ-pinning), distinctness from each other, normalization (`"Abacus AI"` ↔ `"abacus"`), and fallback unchanged for unknown providers.
- **`QuotaProviderListTests`** — new file, 9 cases. Outcome: count 27, subscription zones 54, abacus + mistral present with correct displayNames. Cause: providerID format invariant (lowercase, no whitespace), zone name template wire-contract, additive append ordering, no duplicates, catalog cross-coupling.
- All 221 iOS tests pass (16 suites). SwiftLint 0 violations. i18n audit clean.

### What did NOT need iOS code changes

T3–T8 reduced to "no code change" after re-examining Mac v0.23's actual `toUsageSnapshot()` data shapes:

- **T3 Abacus detail** — single credit pool maps to one `RateWindow`; iOS rate-window section already renders correctly.
- **T4 Mistral detail** — spend lives in `RateWindow.resetDescription` as `"$X.XXXX this month"`; iOS shows it in subtitle. Cost-style large-number rendering deferred to future polish.
- **T5 Codex Pro $100 / GPT-5.5** — `loginMethod` capsule already renders the plan name string; raw model IDs in cost breakdown are consistent with existing Claude / GPT-5.4 display style. No beautifier added.
- **T6 Claude extras** — Mac v0.23 SyncCoordinator passes through `extraRateWindows` to the existing `rateWindows` array (with `NamedRateWindow.title` as label); iOS detail page already iterates the array.
- **T7 Cursor Extra** — same path as T6.
- **T8 Synthetic 3-lane labels** — Mac's `SyntheticProviderDescriptor.metadata` already pushes `"Five-hour quota"` / `"Weekly tokens"` / `"Search hourly"` as labels via primary / secondary / tertiary; iOS `defaultLabel` fallback never fires.

iOS-side compat with old Mac (still on 0.20.3): every new field is `decodeIfPresent` optional, Build 79 forward-compat regression test pins the silent-drop-unknown-keys behavior. No regression.

### Notes

- Mac v0.23 still in QA (Sparkle draft pending publish). iOS 1.5.0 ships independently; users running iOS 1.5.0 with Mac 0.20.3 see the existing 25 providers fully and don't see Abacus/Mistral until they update Mac.
- 1.3.1 stays as the most recent App Store-shipped train; 1.5.0 enters TestFlight first.

## [1.3.1 (95)] — 2026-04-26 — defense-in-depth + comprehensive test matrix for Build 94 filter

User asked for a thoroughness pass on Build 94: comprehensive tests, deep root-cause analysis, CTO-level architectural sweep, code review. Two parallel investigation agents covered no-cleanup-pattern hunts and filter-coverage tracing across the codebase.

### Round 1 · Tests (24 → 50 cases)

26 new `SnapshotCacheTests`:

- **Rule 1 edges**: empty-string email vs nil, three-way (alice + bob + nil), per-device boundary, real-email never touched even when very stale.
- **Rule 2 edges**: exact 30-min boundary, real-email exempt from TTL, lone nil-email on offline device, multiple nil-email mixed freshness.
- **Combined**: rules-stack interactions, all-filtered → legacy fallback path.
- **Multi-device**: independent per-device filtering (one dirty + one clean).
- **Integration paths**: `replaceFromFullFetch` / `replacePerProviderFromReplay` / `applyDelta` — each verified to filter at read time.
- **Edge cases**: empty cache, future-dated `lastUpdated` (clock skew), only-real-email entries, Build 66 `isGhost` stacking, same-timestamp Rule 1 behavior.
- **Defense-in-depth**: legacy bucket filter applied; clean legacy passthrough.

### Round 2 · Root-cause hunt findings (Agent A + Agent B, both completed)

The bug class is systemic — **the codebase has zero explicit deletion semantics**. The same write-only pattern recurs at 5+ critical sites: per-provider zone records, legacy device snapshots, push subscriptions, custom CloudKit zones, SwiftData rows. All rely on upsert with implicit overwrite via stable identity, which breaks on lifecycle events (provider disable, Mac version upgrade, account switch, device wipe).

Agent B specifically identified **one real coverage gap in Build 94**: SwiftData cold-start hydrate seeds `legacyByDevice` directly, bypassing the per-provider filter. Pre-Build-94 SwiftData rows (written by old code that didn't filter) cause a 1-2 sec orphan flicker on first 1.3.1 launch for users upgrading from 1.3.0.

### Round 3 · CTO architectural categorization

Filed in [`Research/017-ghost-records-defense-in-depth.md`](../Research/017-ghost-records-defense-in-depth.md) — full analysis of bug class as "eventually-consistent distributed cache without lifecycle management", layered defense plan (L1 Mac authoritative cleanup → L5 observability), other places this lurks (push subscription cleanup, dead xcstrings keys, accountEmail cross-version merge). Tracks 4 follow-up items deferred to v0.23 migration / iOS 1.5.0 / future tooling.

### Code review · `dropOrphansAndStale(_:)` + `buildDeviceSnapshots`

Performed inline in Research/017. Verdict: **production-ready**. Pure function, no side effects, comprehensive test coverage, well-documented design rationale, conservative defaults, correct rule sequencing. Two minor nits (cosmetic comment refinement, inline `30 * 60` could be a named constant) — neither warrants change. Two pending follow-ups (Mac L1 cleanup in v0.23, accountEmail latestNonNil) filed as separate work.

### Fixed / hardened in this build

- **Defense-in-depth: filter applied to `legacyByDevice` bucket too.** New `SnapshotCache.filterSnapshotProviders(_:)` round-trips a `SyncedUsageSnapshot.providers` list through the same `dropOrphansAndStale` filter. Triggered on (a) device-only-in-legacy fall-through path, (b) all-per-provider-filtered → legacy fallback path. Includes a clean-path optimization: returns the input snapshot when no filtering happened, avoiding allocation/reordering churn for the common case.
- **Catches the 1.3.0 → 1.3.1 upgrade-cold-start orphan flicker** that Agent B identified — Build 94 alone left this transient gap.

### Notes

- All 50 tests pass on iPhone 17 Pro Simulator. SwiftLint 0 violations. i18n audit clean.
- Build 95's runtime impact is identical to Build 94 for steady-state users (filter applies same way). The added work runs once per `buildDeviceSnapshots` call on legacy-bucket entries, which is sub-microsecond.

## [1.3.1 (94)] — 2026-04-26 — hotfix · ghost provider records causing duplicate cards + stale ghosts after Mac upgrade / disable

> 1.3.0 was approved by App Review during the day. This first 1.3.1 build is a hotfix for a critical regression user-reported within hours of 1.3.0's release: duplicate Codex cards + stale Perplexity card + Cost Provider Share summing to 104%. Marketing version bumped 1.3.0 → 1.3.1 since 1.3.0's TestFlight train is closed for new build submissions.

### Fixed

User-reported regression after upgrading both Macs to 0.20.3: iOS shows duplicate "Codex" + "Codex 2" cards from one Mac, plus a Perplexity card despite the user disabling Perplexity on Mac, plus Cost Provider Share summing to 104% (Claude 80% + Codex 12% + Codex 12%). Three symptoms, one root-cause family — Mac state transitions leave orphan / stale CKRecords in `DeviceProvidersZone` that iOS's existing ghost filter (Build 66) doesn't catch because they carry data, just from the wrong identity or refresh cycle.

**`SnapshotCache.dropOrphansAndStale(_:)`** — new read-time filter applied in `buildDeviceSnapshots`. Two rules:

- **Rule 1 · nil-email-when-real-email-exists**. Per device, per `providerID`: if any sibling entry has a non-empty `accountEmail`, drop entries with `accountEmail == nil`. The nil-email orphans come from Mac's pre-OAuth-load early push, or — the more recent trigger — from a Mac upgrade where Codex's `CodexAccountReconciliation` / `CodexIdentity` refactor (upstream v0.20) changed how the account-identity composite key is derived. The new Mac wrote a record under a new composite key; the old record persists in CloudKit indefinitely with `accountEmail == nil` in payload. Rule 1 fires only when a real-email sibling exists, so it doesn't false-positive on legitimately accountless providers (Claude with hide-email, etc.).
- **Rule 2 · stale relative to device freshness, applied only to nil-email entries**. Drop entries whose `accountEmail` is nil/empty AND whose `lastUpdated` lags more than 30 min behind the device's freshest entry. Catches records of providers the user disabled — Mac stops writing, the record persists with its last-known timestamp. Real-email entries are exempt: legit multi-account providers (e.g., two Codex accounts on the same Mac with different emails) can refresh on independent cadences when one is hot and the other idle, and Mac always assigns emails to such accounts. 30 min is wider than any real-provider refresh cadence (the slowest browser-cookie providers refresh well under that), so won't false-positive on slow-syncing accountless providers.

Filter applies at **read** time (`buildDeviceSnapshots`), not write time, so:
- Incremental delta updates can never trim freshly-arrived peer records that briefly look "stale" before the cycle completes.
- The cache continues to hold raw zone state; only the displayed view is filtered.
- When Mac resumes writing for a disabled provider, the device's freshness moves forward and the previously-filtered record either gets dropped from CloudKit (when Mac 0.23 ships with the proper delete-on-disable hook) or returns to view if Mac re-enables and refreshes it.
- Toggling the user's iOS app off/on doesn't change the filter outcome — it's purely data-driven.

If all per-provider entries for a device are filtered out, the read code falls back to the device's legacy zone snapshot (if any) so the device doesn't disappear entirely.

### Tests

`SnapshotCacheTests` +5 cases:
- `orphanNilEmailDroppedWhenRealEmailSiblingExists` — exact reproduction of user's "Codex + Codex 2" symptom; cache holds both raw entries, but `buildDeviceSnapshots` filters the orphan.
- `multipleNilEmailLegitWhenNoRealEmailSibling` — guards against false-positives when no sibling has a real email.
- `staleTTLDropsLaggingProvider` — Perplexity-after-disable: lagging 45 min behind the device's freshest is dropped.
- `staleTTLPreservesSingleRecordDevice` — offline Mac with hours-old data; single record is its own freshest, kept.
- `staleTTLKeepsRecentlyRefreshedProviders` — typical refresh sequencing with seconds between providers; both kept.
- `combinedOrphanAndStale` — exact 4-card mbp scenario the user reported; result has only the 2 active providers (Codex + Claude).

### Notes

- Existing ghost records persist in CloudKit until the Mac 0.23 release lands the proper Mac-side fixes (`SyncCoordinator` delete-on-disable + identity-drift cleanup, planned in Research/016 Phase 1 follow-ups). Build 94 is the **iOS-only mitigation** that filters them at display so users on iOS 1.3.0 + any Mac version see correct state immediately.
- The cache's existing `isGhost` filter (Build 66, all-nil-data envelopes) is unchanged and stacks with `dropOrphansAndStale`.

## [1.3.0 (93)] — 2026-04-25 — dev build · CI gate against state="new" xcstrings entries

### Added
- **`Scripts/lint.sh` — i18n audit** that walks every `*.xcstrings` file and fails the lint run if any locale entry is in `state: "new"`. Same regression class as Build 55 (1.1.0 release notes English-only on zh-Hant / ja iPhones) and Build 92 (1.3.0 catalog same pattern): Xcode auto-creates `state: "new"` entries with English fallback when a developer adds a new `String(localized:)` call, and the build / upload still succeeds. With this gate wired into the `lint` command, those entries can no longer reach `mobile-dev` (CI runs `./Scripts/lint.sh lint` on every push) and can no longer be uploaded to TestFlight (`Scripts/upload_ios_testflight.sh` now runs the same lint as a pre-flight before archive + export).
- **`Scripts/lint.sh audit-i18n`** as a standalone subcommand for quick local checks without re-running SwiftFormat / SwiftLint.

### Changed
- `Scripts/upload_ios_testflight.sh` now executes `./Scripts/lint.sh lint` before archiving. ~2 min of archive + upload time saved when the audit catches a missing translation.

### Notes
- jq required (already a hard dep in past Mac release scripts).
- 4-locale audit confirmed clean for current state: 261 keys × 4 locales = 0 entries in `state: "new"`.

## [1.3.0 (92)] — 2026-04-25 — dev build · Traditional Chinese + Japanese translations for 1.3.0 in-app release notes

### Fixed
- **All 11 entries of the 1.3.0 in-app release-notes catalog were displaying English on Traditional-Chinese / Japanese iPhones** because their `Localizable.xcstrings` localizations sat at `state: "new"` with English fallback values. The same regression class as Build 55's "1.1.0 release notes were English-only on non-English iPhones" — fix is the same: provide proper translations for both locales. Affected strings: Latest summary, Important (Mac update gate), 5 What's New bullets (Perplexity credit / OpenCode Go / Codex multi-account / push coverage / unified palette), 3 Under the hood bullets (SwiftData cache / per-provider records / silent push), and the section title "Under the hood".
- 4-locale audit pass on `Localizable.xcstrings` confirmed: 0 strings remain at `state: "new"` for any of `en / zh-Hans / zh-Hant / ja`.

### Notes
- Build 90's "Some Mac devices are on older versions…" + "· Update available" already had all 4 languages — those don't regress.
- Translation tone follows the existing zh-Hans copy; technical terms (`provider`, `CloudKit`, `SwiftData`, `Subscription Utilization`, `fallback`) left untranslated for consistency with the Mac app and earlier locales.

## [1.3.0 (91)] — 2026-04-25 — dev build · Fix Mac build-number string in in-app release notes

### Fixed
- **In-app 1.3.0 release notes — Important section** referenced `Mac 0.20.3 (Build 55.3.1.2.0)`, but the Mac 0.20.3 Sparkle release that actually went live (2026-04-24) carries `CFBundleVersion = 55.3.1.3.0` (the `.1.3.0` suffix tracks `MOBILE_VERSION = 1.3.0`, which was bumped from `1.2.0` together with the Sparkle finalize). Updated all four locales (en / zh-Hans / zh-Hant / ja stub) plus the source string literal in `ContentView.swift`, and the `Localizable.xcstrings` lookup key, to read `Build 55.3.1.3.0`. No behavior change — the user-facing gate is still "Mac 0.20.3 or later".

## [1.3.0 (90)] — 2026-04-23 — dev build · Per-device Mac version display + outdated hint

### Added — Settings → About & Sync

**Top-level "Mac App" row** (already showed highest-semver since Build 81)
- **New**: When 2+ Macs sync and at least one runs an older `appVersion`, an orange-tinted caption below shows "Some Mac devices are on older versions. Update them for complete sync data." This nudges users to update so all Macs emit new-schema sync fields (`perplexityCredits`, `loginMethod`, `budget`, etc. — all the `latestNonNil` account-level fields that silently degrade when an old Mac refreshes last).

**Per-device row under "Devices" section**
- **New**: Each device now shows its specific `CodexBar X.Y.Z` version below the sync timestamp + provider count line. Previously you could only see aggregated counts; now each device is identifiable by its version.
- **New**: Devices running behind the highest-semver peer get an orange `· Update available` chip next to their version. Lets users pinpoint *which* Mac needs updating, not just "one of them".

### Behavior rules
- Single-device setups never trip the hint — nothing to compare against.
- Devices that never reported a version (pre-1.1 KVS fallback) are not flagged as outdated; they render without a version line.
- Uses the same `CloudSyncReader.semverLessThan` comparator as `mergeSnapshots`'s `max(by:)` selection, so the "Mac App at top" device never appears flagged as outdated (that'd be self-contradictory).

### Localization
- Two new keys added with zh-Hans / zh-Hant / ja / en: "Some Mac devices are on older versions. Update them for complete sync data." and "· Update available"

### Code
- `ContentView.swift` · `AboutSyncDetailView`: added `hasOutdatedMac` + `isDeviceOutdated(_:)` helpers next to `syncStatusDetail`. Used from both the top-level warning row and per-device rows.

All 88 tests pass; SwiftLint 0.

## [1.3.0 (89)] — 2026-04-23 — dev build · Mac fork-added sync code hardcode comments (Phase 2)

**Phase 2 of the hardcode-comment audit.** iOS Phase 1 (Builds 85-88) closed 50+ sites. Agent 5 audited Mac-side `Sources/CodexBar/Sync/**` for fork-added files (verified via git log). Most wire-contract constants were already protected with "WIRE CONTRACT" comments from earlier hardening passes (Build 68 / Research 012). The 4 real gaps addressed:

### Added comments
- **`Sources/CodexBar/Sync/SyncCoordinator.swift`**:
  - `perProviderHashKey` — documented as the in-memory diff-cache composite key that must match 4 peer sites byte-for-byte (iOS `SnapshotCache.compositeKey`, `ProviderSnapshotModel.makeCompositeKey`, `CloudSyncManager.perProviderRecordName`, delete-by-recordName). Build 67 drift discovery referenced.
  - `stableHash` FNV-1a constants — explicitly named `0xCBF29CE484222325` as the 64-bit offset basis and `0x100000001B3` as the 64-bit FNV prime; changing them invalidates every cached hash and forces full re-upload from every user's Mac on startup.
- **`Shared/iCloud/CloudSyncManager.swift`**:
  - `batchSize = 200` comment beefed up — explicit "CloudKit API hard limit per `CKModifyRecordsOperation.save()`"; raising silently triggers `.limitExceeded` and drops records above 200. Testing requirement documented.
- **`Sources/CodexBar/Sync/QuotaTransitionWriter.swift`**:
  - `debounceInterval = 5 * 60` — documented as a UX constant (push-spam prevention for oscillating quota crossings), not an API limit. Trade-off explained; validation path noted.

### Verified already well-documented (no change)
- `Shared/iCloud/CloudConstants.swift` — all zone/record names got WIRE CONTRACT treatment in Build 85.
- `CloudSyncManager.perProviderRecordName` + `hourBucket` — already thoroughly doc-commented from earlier builds.
- `SyncCoordinator.maxEntriesPerSeries = 730` — inline comment from the original commit already covers the 30-day hourly reasoning.

### Scope boundary
- Agent 5 explicitly verified fork-ownership per file via git log before flagging. Upstream-owned files (vanilla `steipete/CodexBar` code we didn't touch) stayed untouched per CLAUDE.md policy.

### Post-Phase-2 summary
- **5 commits** (Build 85 Shared/ wire + 86 iOS sync + 87 iOS Models/ContentView + 88 iOS Views + 89 Mac fork-added) across **~65 hardcode sites** across the entire fork-owned codebase.
- Each commit passes Codex review clean.
- No runtime behavior changes; pure documentation of load-bearing decisions.
- User's core lesson from Build 84 (write why-comment at point of introduction) now applied retroactively across every discovered hardcode site.

All 88 tests pass; Mac SPM build green; SwiftLint 0.

## [1.3.0 (88)] — 2026-04-23 — dev build · iOS Views hardcode comments (commit 4/4)

### Added comments
- **`UsageCardView.swift`**:
  - `scaleEffect(y: 2)` on ProgressView — explains 1pt native → 2pt visual height for touch-target visibility.
  - `usageColor` 70/90% thresholds — industry-standard quota warning bands (AWS/Azure/GCP + Apple Storage UI); deliberately mirrors BudgetProgressView so every quota-like display flips color at the same percentage.
- **`BudgetProgressView.swift`**:
  - `progressColor` 70/90% thresholds documented as symmetric with UsageCardView.
- **`CostShareCardView.swift`** / **`CyberShareCardView.swift`**:
  - `cardWidth = 390` / `cardHeight = 520` — social-export 3:4 canvas; UIImage export depends on exact pixel dimensions at 2×/3× scale; resizing would reflow card body templates and re-crop existing user screenshots.
- **`CyberShareCardView.swift`**:
  - Arc gauge geometry: `trim(from: 0.15, to: 0.85)` = 252° arc with 30° top gap for center label; `0.15 + 0.7 * value` overlays the proportional fill.
- **`PerplexityCreditsCard.swift`**:
  - `legendDotOpacity` ramp (1.0 / 0.78 / 0.55) encodes **consumption-priority signal** — Perplexity depletes recurring > promo > purchased in that order; brightest dot = spent first. Values tuned for material-background legibility.
- **`UtilizationHistoryView.swift`**:
  - `AxisMarks(values: .automatic(desiredCount: 4))` — 30-bar × 10pt-wide chart fits ~4 labels; more crowds, fewer feels sparse.
- **`ProviderDetailView.swift`**:
  - Daily Spend chart `frame(height: 200)` — empirically tuned for compact iPhone (667pt total height); taller would push utilization history off-screen.

### Post-audit summary (Builds 85–88)
- **50+ hardcodes across iOS** now carry inline "why" comments preventing the Build 81 regression class.
- No runtime changes in any of the 4 commits — pure documentation.
- Each commit passed Codex review clean.
- Total test count stable at 88; SwiftLint 0 throughout.

### Not in this commit
- **Build 89** (Phase 2, next): Mac-side audit of the sync code we add on top of upstream (`Sources/CodexBar/Sync/**`). Same agent pattern, shorter scope because Mac is upstream-owned — only the bits our fork touched need a look.

## [1.3.0 (87)] — 2026-04-23 — dev build · iOS Models + ContentView hardcode comments (commit 3/4)

### Added comments
- **`ContentView.swift`**:
  - `chartVisibleDays: Int = 30` — ties together monthly mental model, matching UtilizationAggregateView / UtilizationHistoryView windowSize; stride-7 gridlines depend on it being exactly 30.
  - `.stride(by: .day, count: 7)` on the Cost chart — one label per week anchors the chart to CostShareService's 7-day-bar pattern; changing requires updating both sides.
  - `BreakdownPalette.color(for:)` — full explanation of why the HSB constants (0.08 model vs 0.52 service hue base, 0.62–0.83 saturation, 0.78–0.93 brightness) are load-bearing for Cost-tab visual clarity. Generic `.random()` or `.palette` API replacement would regress readability on dark mode `.ultraThinMaterial`.
- **`CostShareService.swift`**: month-chart `dayNum % 7` labeling documented — matches ContentView's stride-7 gridlines; share card + dashboard read as a matching pair.
- **`MobileChartAxisFormatter.swift`**: Wilkinson-style rounding algorithm fully explained — what `1.5 / 3 / 7` breakpoints do, why they're not the step sizes, why they ensure round-number axis labels.
  - Default `targetTickCount: Int = 4` rationale (220pt height geometry fit).

### Verified-already-documented
- `SyncedUsageData.syncAge` thresholds `60 / 3600 / 86400` — seconds-per-minute/hour/day are unambiguous.
- `CostShareService.displayProviders` prefix(3) + "Others" — comment at line 76 already covers.
- `PreviewData.recencyBoost pow(…, 1.5)` — inline `// ramps up toward today` sufficient for preview fixture.
- `ContentView.dayKeyFormatter` — comprehensively commented in Build 84.

All 88 tests pass; SwiftLint 0.

## [1.3.0 (86)] — 2026-04-23 — dev build · iOS sync-layer hardcode comments (commit 2/4)

### Added comments
- **`CloudSyncReader.swift`**:
  - `localCostProviders` set now explains *why* these three (claude/codex/vertexai) specifically — per-Mac CLI file reads must SUM, all other providers are account-level API reads and `latestNonNil` is correct; adding a new local-CLI provider is a behavior change.
  - Composite key `""` vs `"_"` sentinel contract documented — `""` in the in-function grouping key is fine because it never leaves the function; `"_"` is required at every layer-crossing site (Build 67 drift hardening, links to 4 peer sites).
  - Single-device passthrough fast path documented — skips `mergeProviderEntries` dedup/sort because downstream consumers bucket into dicts; Build 83 test `mergedUtilizationDisorderedInputProducesSortedOutput` pins that sortedness is a multi-device property.
  - `compactMap(\.costSummary)` / `compactMap(\.utilizationHistory)` — why `compactMap` not `flatMap`: cross-version / partial-install Macs may have nil for these fields; compactMap drops them gracefully, flatMap would crash.
  - `.distantPast` sentinel in `freshestWindowByName` — any real `latestCaptured` overrides on comparison; sentinel only sticks when every device has an empty series for that name (downstream filtered out by `!deduped.isEmpty`).
  - `resetEpoch ?? -1` — out-of-band sentinel never collides with real epochs; Build 77 learned mixing pre/post-reset samples in same hour averages to meaningless 47.5%; regression guarded by `mergedUtilizationCrossResetBoundarySeparatesBuckets`.
- **`SnapshotCache.swift`**: `compositeKey`, `splitRecordName`, `syntheticDeviceID` — all 3 now document the WIRE CONTRACT + 4-site sync + `"legacy:"` UUID-collision guard.
- **`QuotaTransitionSubscriptions.swift`**: `subscriptionID` format `"quota-{providerID}-{state}-sub"` documented as wire contract — changing on a live user orphans their existing subscriptions and silently disables push.

### Verified-already-documented
- `CloudSyncReader.semverLessThan` (Build 77 comments cover rationale fully)
- `SwiftDataSchema.makeCompositeKey` (Build 67 comments already document the drift concern)
- `NotificationService` 30s timeout / `resultsLimit: 1` (already documented at class-level docstring)

All 88 tests pass; SwiftLint 0.

## [1.3.0 (85)] — 2026-04-23 — dev build · wire-contract comments (Shared/)

**Commit 1/4 of the comprehensive hardcode-comment audit.** User pointed out that Build 81's regression (chart labels) was caused by commit `79f207d2` hardcoding `"M/d" + Locale("en_US")` with no inline explanation of the geometry constraint — making the hardcode look like a smell to any future audit. Prevention is to **comment all load-bearing hardcodes at the point of introduction**. 4 agents audited the whole iOS codebase + 1 will audit the Mac sync additions. This commit covers the most dangerous layer: the Mac↔iOS wire contract.

### Added wire-contract comments
- **`Shared/iCloud/CloudConstants.swift`**: `containerIdentifier` / `recordType` / `customZoneName` / `providerRecordType` / `providerZoneName` / `quotaDepletedZoneName` / `quotaRestoredZoneName` — each now carries a "WIRE CONTRACT" warning describing what renaming breaks (orphaned records, silenced pushes, irreversible without user-migration).
- **`Shared/iCloud/CloudSyncManager.swift`**:
  - Added rationale comment on `@unchecked Sendable` (stateless-factory + single-instance + immutable-stored-properties argument; if a mutable stored property lands later, switch to an actor).
  - Documented the `perProviderRecordName` composite format `"{deviceID}|{providerID}|{accountEmail ?? "_"}"` — pipe separator rationale, `"_"` sentinel must match 4 other sites (Build 67 drift hardening), field-order change orphans all records.
- **`Shared/Models/UsageSnapshot.swift`**:
  - `SyncDailyPoint.init(from:)` `?? []` fallback on `modelBreakdowns` / `serviceBreakdowns` — backward-compat for pre-0.18 Mac payloads; removing crashes decode for legacy users.
  - `SyncedUsageSnapshot.CodingKeys.syncVersion` — legacy key retained for Mac 0.17.x–0.19.x compatibility; explicit "do not remove until every user past 0.20.x".
  - `mobileVersion ?? syncVersion` fallback chain — points back to CodingKeys docstring.
- **`Shared/Notifications/QuotaProviderList.swift`**: `quotaZoneName(providerID:state:)` template now has a WIRE CONTRACT warning — zone name format changes silently break push delivery for every existing user with no migration path.

### Not in this commit (follow-up builds)
- **Build 86**: iOS sync layer (`CloudSyncReader` + `SnapshotCache` + `SwiftDataSchema` + subscriptions + push extension) — Agent 3 flagged 13 sites.
- **Build 87**: iOS Models + ContentView — Agent 2 flagged 12 sites (time thresholds, palette HSB, preview fixture curves).
- **Build 88**: iOS Views — Agent 1 flagged 10 sites (color thresholds, card geometry, arc offsets).
- **Build 89**: Mac-side sync audit (Phase 2, separate agent).

All 88 tests pass; SwiftLint 0; Codex review pending.

## [1.3.0 (84)] — 2026-04-23 — dev build · revert Build 81 chart date label locale change

**User flagged a regression introduced in Build 81.** Agent D's audit suggested switching the 30-day chart's day-labels from hardcoded `"M/d" + Locale("en_US")` to `setLocalizedDateFormatFromTemplate("Md") + .current`, framed as an i18n improvement. I applied that blindly.

**Why it was wrong**: the English-POSIX-style `"M/d"` was a *deliberate* design decision from commit `79f207d2` ("use compact numeric date labels"). The chart renders 30 bars at `barWidth: 8pt` each; labels have to stay narrow as `"4/23"` to fit the geometry. The locale-aware template respects the user's interface language, which in Simplified Chinese produces `"4月23日"` — three CJK glyphs per label, overflowing the bar spacing and breaking the chart.

### Reverted
- `UtilizationAggregateView.swift:416-418`: back to hardcoded `M/d` + `Locale("en_US")`. Added a multi-line source comment explaining why this is intentional (geometry constraint, not an i18n oversight) so a future audit can't mistake it for a bug.

### Lesson
- Agent audits are starting points, not instructions. When an agent flags something that conflicts with a *deliberate* design decision visible in git history, I have to `git log` the file first before accepting the fix. Build 81 would have caught this if I'd searched for "M/d" in the commit log — commit `79f207d2` is explicit about the compact-numeric design intent.

### Process improvement (the real prevention)
- User correctly pointed out the root lesson isn't "git-log before accepting agent fixes" — that's the reactive patch. The real prevention is: **when writing a hardcoded value, leave an inline comment explaining the constraint**. Without the comment, any audit (agent or human) will flag it as a smell. With the comment, the constraint is visible at the call site and nobody has to archaeologize.
- Added "why-hardcoded" comments to the other chart geometry / wire-format sites that were previously uncommented and could suffer the same class of regression:
  - `UtilizationHistoryView.axisLabel(for:)` — same `"M/d"` design constraint
  - `UtilizationHistoryView.barWidth / windowSize` — explains the 10pt / 30-bar tuning
  - `UtilizationAggregateView.barWidth / windowSize` — explains the 8pt / 30-bar tuning and why labels can't be locale-aware
  - `ContentView.dayKeyFormatter` — notes it's a machine contract for CloudKit dayKey round-tripping, not user-facing text; plus a note on its thread-safety scope
- Updated memory accordingly: `feedback_git_log_before_accepting_agent_fixes.md` (which used to say "git-log before accepting") now says "hardcoded magic values must carry an inline 'why' comment at the point of introduction".

## [1.3.0 (83)] — 2026-04-23 — dev build · 4-agent perfect-pass fixture extension

**Commit 3 of the post-Build-80 perfect-pass.** Agent C's analysis of `SwiftDataBridgeTests / DualZoneReaderTests / SnapshotCacheTests` found each had zero coverage of production-shaped data: long-idle gaps, cross-reset-boundary same-hour entries, all-zero-but-tracked patterns, bursty-active vs stale-idle multi-device combinations. Build 80 fixed this for `CloudKitMergeTests` only. This build extends the same treatment to the other 3 files and shares the fixture helpers.

### Tests (Agent C · realistic-distribution fixtures)

**New `CodexBarMobileTests/Fixtures/TestFixtures.swift`**: shared helpers so the 4 test files don't re-implement the same realistic patterns.
- `burstySessionSeries(anchor:daysCount:peakHour:peakPercent:deviceOffsetMinutes:)` — moved up from CloudKitMergeTests. UTC calendar deliberately (DST-proof — an earlier `Calendar.current` version would make 720 → 719 on Europe/Paris spring-forward).
- `allZeroSessionSeries(anchor:daysCount:)` — idle-device pattern; must survive every persistence layer.
- `crossResetBoundaryEntries(anchor:)` — two entries in same clock hour, different reset windows.
- `multiAccountProviders(id:emails:lastUpdated:)` — same provider with N distinct accountEmails.

**`SwiftDataBridgeTests` +3 cases**:
- `realisticAllZeroUtilizationRoundtrip`: 720 zero entries survive upsert → fetch. A "prune zero-only as uninteresting" regression would drop the count below 720.
- `realisticCrossResetBoundaryPreservedInStorage`: two entries in same clock hour, different `resetsAt` — both survive. A compositeKey collapse to `(series, capturedAt.hour)` would silently drop one.
- `realisticMultiAccountSameProviderPreserved`: alice + bob on codex → 2 rows, not 1. Regression to providerID-only keying would collapse them.

**`DualZoneReaderTests` +2 cases**:
- `reconstructLongIdlePlusFreshMixedTimestamps`: same device wrote 30-day-old Codex + 7-day-old Claude. Reconstruct preserves both, sorts newest-first, device syncTimestamp = freshest (not min).
- `priorityEmptyPerProviderKeepsLegacyIntact`: empty per-provider + populated legacy → legacy survives as-is. Guards the transient-zone-error fallback path.

**`SnapshotCacheTests` +2 cases**:
- `burstyActiveAndIdleStaleBothPresent`: Mac A fresh (t3) + Mac B stale (t1), same account. Both survive cache; a "drop stale" regression would show 1.
- `multiAccountDeltaOnlyUpdatesTargetAccount`: seed alice + bob at t1, delta alice to t2, bob untouched at t1. Guards against re-keying by providerID alone.

### Test totals
- Pre-Build-83: 81 tests
- Post-Build-83: 88 tests
- All pass; SwiftLint 0; Codex review: clean.

### Audit progress (post Build 83)
- Round 1 (cross-view): ✅ complete (Builds 77, 78, 81)
- Round 2 (multi-device fields): ✅ complete (Builds 77, 78, 81) — `providerName` / `deviceName` ⚠️ documented as rare-edge-case or cosmetic, not patched
- Round 3 (test data distribution): ✅ complete (Builds 80, 83)
- Round 4 (boundary conditions): ✅ documented as intentional / safe
- Round 5 (Codable resilience): ✅ complete (Build 79)

### Deferred to Build 84 (doc-only)
- `Research/015-mac-symmetry-audit.md` recording Agent A's 5 Mac-side findings (`accounts.first` non-deterministic · `Widget providers.first` · `SyncCoordinator "_"` placeholder · Perplexity multi-account no-email-split · OpenAIDashboard dayKey `TimeZone.current` formalization) for future upstream PR. No code change; just documents what we found for when upstream owners (steipete) review.

## [1.3.0 (82)] — 2026-04-23 — dev build · 4-agent perfect-pass P1 polish

**Commit 2 of the post-Build-80 perfect-pass.** Agent B flagged 5+ places where `formatUSD` / `formatTokens` were duplicated across views with subtly different signatures (some returned `"N/A"` for nil, some `"—"`, some crashed). Any future locale / precision / unit-label tweak would need coordinated edits — drift risk. Centralized.

### Fixed — Formatter duplication (Agent B · P1)
- **New `CodexBarMobile/Models/CostFormatting.swift`**: single source of truth `enum CostFormatting` with `usd(_ value: Double)`, `usd(_ value: Double?)`, `tokens(_ count: Int)`, `tokens(_ count: Int?)`. All four variants use `"—"` for nil uniformly.
- `ContentView` (Cost tab + RawDailyPointRow) — 3 call sites routed through `CostFormatting`.
- `ProviderDetailView` — `formatUSD` / `formatTokens` are now 1-line thin wrappers calling `CostFormatting`.
- `ProviderUsageView` — same thin-wrapper shape.
- `CostShareCardView` / `CyberShareCardView` — `formatUSD` unified. `formatTokens` kept local because share cards use a visually compact format (no "tokens" label suffix — the label is implied by card layout). Divergence documented in a source comment.
- Deliberately NOT touched: `RawProviderDetailView.formatCost/Tokens` (developer tool, uses `"N/A"` by design for debug legibility; not user-facing).

### Tests
- `CodexBarMobileTests/CostFormattingTests.swift`: 9 cases pinning the central contract — USD formatting structural properties (locale-independent), optional → "—" behavior, token K/M threshold transitions. Any regression that rewrites the central formatter without updating K/M boundaries or nil handling fails these.

### Not in this commit (Build 83–84)
- **Build 83**: SwiftDataBridgeTests / DualZoneReaderTests / SnapshotCacheTests realistic-distribution fixtures (Agent C's 9 proposed fixtures + shared `TestFixtures.swift`). 3 P1 + 6 P2.
- **Build 84**: `Research/015-mac-symmetry-audit.md` recording Agent A's 5 Mac-side findings for future upstream PR.
- Agent B's remaining ⚠️: Budget `usedAmount` semantics docs, Preview fixture drift, `deviceName` single-vs-merged marker — deferred; all cosmetic, no user-visible correctness risk.
- Agent A's Mac-side bugs (`accounts.first`, `providers.first`, `SyncCoordinator` `"_"` placeholder, Perplexity multi-account) — remain Mac-only; we don't patch `Sources/` per project rule.

## [1.3.0 (81)] — 2026-04-23 — dev build · 4-agent perfect-pass P0 fixes

**Context**: After Build 80 (3-commit systematic audit), I did an honest self-audit and found 14 gaps. User asked for "perfect". Dispatched 4 parallel research agents: Mac-side symmetry / cross-view all-pairs / test-fixture-distribution-3-files / performance-concurrency-a11y. The 4 agents found **4 new ❌ bugs** that the earlier audit missed. This build fixes all 4.

### Fixed — Cross-view consistency (Agent B)
- **`ProviderUsageView.costTeaserText` still read `sessionCostUSD` directly** — Build 78 fixed the `ProviderDetailView` "Today" card but missed this sibling call site. Usage-tab teaser and detail-page "Today" diverged mid-day. Now routes through `cost.todayTotals()` — same class-of-bug as Build 77's Codex-0% aggregate/detail mismatch, now closed across every known reader.
- **`UtilizationAggregateView.providerShareRow` ignored the "Show remaining usage" toggle**. Every other card on the Usage tab flips between "86% used" and "14% remaining"; the share row was hardcoded "% avg use". Added `@AppStorage(MobileSettingsKeys.showRemainingUsage)` matching `UsageCardView`'s declaration (legacy-key migration default included), plus a localized `%.0f%% avg remaining` format with zh-Hans / zh-Hant / ja translations.

### Fixed — Thread safety (Agent D, P0)
- **`SyncCostSummary.iso8601DayKeyFormatter` was a shared `static let DateFormatter`** — documented thread-unsafe on iOS. `todayTotals(now:)` is reachable from both view-body rendering (main actor) and sync-observer paths, so concurrent `string(from:)` calls could crash. Replaced with a per-call factory (`iso8601DayKeyFormatter()`) exposed via a thread-safe `iso8601DayKey(for:)` helper. Also explicitly set `.timeZone = .current` so the contract matches Mac-side `SyncCoordinator.daily[].dayKey` regardless of any future DateFormatter default shifts.
- Agent A's Mac-symmetry audit flagged Mac `OpenAIDashboardModels.swift:93` uses `TimeZone.current` + POSIX locale + "yyyy-MM-dd" — iOS's behavior (prior build) was equivalent since DateFormatter's default timeZone IS `.current`. Making it explicit on iOS pins the contract.

### Fixed — i18n (Agent D, ⚠️)
- **`UtilizationAggregateView` chart date labels were hardcoded `Locale(identifier: "en_US")` with `dateFormat = "M/d"`**. Japanese / Chinese users saw English month-day ordering regardless of interface locale. Switched to `setLocalizedDateFormatFromTemplate("Md")` + `.current` locale so the format follows the user's interface language naturally.

### Tests
- `SubscriptionUtilizationCompatTests` +1: `dayKeyConcurrentCallsSafe` — spawns 64 concurrent `Task`s each computing 30 day keys; asserts all match the single-threaded reference. Would have crashed with `EXC_BAD_ACCESS` pre-fix under the shared DateFormatter.
- Updated existing `todayTotals*` test to drop the removed `hasAnyValue` accessor (YAGNI — only one test was using it).

### Data-structure polish (part of broader Build 82 plan; one bit landed here)
- Removed `SyncCostSummary.TodayTotals.hasAnyValue` — only ever used by one test; callers who need it can inline `costUSD != nil || tokens != nil`. Reduces the API surface.

### Agent A / Mac symmetry — deferred to Build 84 as research doc
- Found 5 Mac-side bugs: accounts.first / providers.first non-deterministic ordering (Widget + Account Switcher) · Perplexity multi-account no accountEmail split · SyncCoordinator `"_"` placeholder for nil email creating ghost CKRecords · dayKey format OK (current policy). These are Mac-only; per project rules (`Sources/` / `Tests/` belong to upstream, read-only for us), they'll land in `Research/015-mac-symmetry-audit.md` for a future upstream PR, not a direct Mac-side patch.

## [1.3.0 (80)] — 2026-04-23 — dev build · 5-round systematic audit follow-up (commit 3/3)

**Commit 3 of 3** addressing the 5-round audit. Closes out Round 3 (测试数据分布 audit): every pre-Build-78 merge test ran on "toy" data (`usedPercent: 50.0`, `costUSD: $1.50`, three entries). Round 3 found every test file had **zero coverage** for long idle / cross-reset boundary / cross-date / deliberately disordered input / all-zero-but-tracked patterns. This commit adds realistic-distribution fixtures that re-exercise the existing merge paths with data shaped like real 30-day usage.

### Tests (Fix D · realistic-distribution regression fixtures)
- `CloudKitMergeTests.swift` +6 cases covering distributions the pre-audit suite never touched:
  - `mergedUtilizationBurstyDistributionPreservesPeaks` — two Macs each with 30 days of hourly Codex samples (peak once per day + 23 zeros, same pattern that surfaced the Build 77 Codex-0% bug). Asserts 720 buckets, monotonic hour order, 30 preserved peak entries at the expected value. Fixture uses a **UTC calendar** so DST transitions in the tester's local timezone (e.g. Europe/Paris spring-forward) can't make the test flaky by producing 719 buckets instead of 720.
  - `mergedUtilizationCrossResetBoundarySeparatesBuckets` — pre- and post-reset entries in the same clock hour, across **two Macs** to force the dedup path (single-Mac passthrough bypasses `dedupByHour`). Pins the `BucketKey(hourSlot, resetEpoch)` separation that prevents `90% ↔ 5%` from collapsing to `47.5%`.
  - `mergedUtilizationDisorderedInputProducesSortedOutput` — two Macs each with entries deliberately shuffled. Merged output is hour-sorted. Also documents that single-Mac passthrough (providers.count == 1) intentionally returns the original snapshot as-is without sorting — downstream consumers bucket into dicts so sortedness is only a multi-device merge property.
  - `mergedUtilizationLongIdleGapPreservesHistory` — Mac A has entries from 30 days ago, Mac B has fresh entries. Merger preserves both; no "stale filter" regression.
  - `mergedUtilizationAllZeroPatternPreserved` — 720 hourly samples all at 0%. Must survive merge: a "zero-pattern provider" must remain visible in Subscription Utilization, not be silently dropped.
  - `mergedCostCrossDateDayKeysPreserved` — daily cost points spanning a month end (2026-01-31 → 2026-02-01), overlap day sums correctly, dayKey strings round-trip untouched.
- Brought test count from 34 → 40 in `CloudKitMergeTests`; full suite 66 → 72.

### Findings from running the realistic tests
- **No regressions exposed** in current merge code — every assertion passed on the first try after one test-setup fix (single-device passthrough path doesn't dedup, which surfaced an over-specific assertion in one of the new tests that I documented and narrowed to the multi-device path where dedup actually runs).
- This confirms the merge layer handles realistic distributions correctly. The Build 77 Codex-0% bug lived at the view layer, not the merge layer — which is why CloudKitMergeTests fixtures didn't catch it. Round 1 (cross-view semantic consistency) was the right lens for that class.

### Audit wrap-up (post Build 80)
- Round 1 (cross-view semantic consistency): ✅ Build 77 (aggregate/detail) + Build 78 Fix A (Cost "Today")
- Round 2 (multi-device merge fields): ✅ Build 77 (appVersion/mobileVersion) + Build 78 Fix B (notificationPushEnabled). One agent-flagged finding verified as false positive (`providerName` — current `base.providerName` is equivalent to `latestNonNil` because providerName is non-optional).
- Round 3 (test data distribution): ✅ Build 80 Fix D
- Round 4 (boundary conditions): Several `⚠️` findings verified and documented as intentional product behavior (email nil vs "" deliberate split, SwiftData stale-record retention for offline Macs, .distantPast sentinel safe behind override branch). No `❌`.
- Round 5 (Codable resilience): ✅ Build 79 Fix C + Fix E

## [1.3.0 (79)] — 2026-04-23 — dev build · 5-round systematic audit follow-up (commit 2/3)

**Commit 2 of 3** addressing the 5-round audit's infrastructure findings (the other P1 code-level fixes landed in Build 78 as Commit 1). This commit fixes Round 5 (Codable resilience) and part of Round 3 (encoder/decoder consistency in tests).

### Fixed (Codable cross-version forward resilience — Fix C)
- **Added regression guard that iOS 1.3.0 tolerates unknown fields sent by future Mac versions.** Scenario: a hypothetical Mac 0.21 adds a new field to `ProviderUsageSnapshot` / `SyncedUsageSnapshot` / `SyncCostSummary` / `SyncPerplexityCreditSummary`. iOS 1.3.0's decoder must silently drop the unknown key and preserve known fields; any throw would cascade up through `CloudSyncManager.decodeEnvelope` → return nil, and that Mac's data would vanish from the iPhone view until the user upgraded iOS. The current synthesized-decoder behavior already tolerates unknown keys (Swift keyed containers never query a key you didn't declare), but there was no test pinning it. A future refactor to a custom strict decoder (e.g. for debug-mode schema validation) could silently break iOS-reading-newer-Mac paths — these tests prevent that.
- Synthesizes the scenario by encoding a real snapshot, JSON-serializing to `[String: Any]`, injecting unknown keys, re-serializing, and asserting the decoder round-trips successfully.

### Fixed (Test infrastructure — Fix E · encoder/decoder factory unification)
- **Replaced 15 `JSONEncoder() / JSONDecoder() + .iso8601` call sites in `SyncModelTests.swift` with `CloudSyncConstants.makeJSONEncoder/Decoder()`.** This aligns the iOS test suite with the Mac `JSONCodecConsistencyTests` convention that has existed since Build 68's hardening pass. Tests now exercise the exact same factory contract production code does — Build 66's silent-decode-failure class of bug (iso8601 vs deferredToDate strategy mismatch) can't re-enter the test layer.

### Tests
- `SyncModelTests.swift` +4 cases:
  - `providerSnapshotTolerantOfFutureFields`
  - `syncedUsageSnapshotTolerantOfFutureFields`
  - `syncCostSummaryTolerantOfFutureFields`
  - `syncPerplexityCreditsTolerantOfFutureFields`
- `SyncModelTests.swift` 15 call sites refactored to go through `CloudSyncConstants` factory (no semantic change; contract alignment only).

### Not in this commit (tracked for Commit 3)
- Realistic-distribution fixtures (bursty / long idle / cross-reset / cross-date / disordered timestamps) across `CloudKitMergeTests / DualZoneReaderTests / SnapshotCacheTests / SwiftDataBridgeTests` — Round 3's primary finding.

## [1.3.0 (78)] — 2026-04-23 — dev build · 5-round systematic audit follow-up (commit 1/3)

**Context**: Build 77 fixed two reported bugs (Subscription Utilization Codex 0%, Mac App version flipping) but the user rightly pointed out that fix is "只是止血" — the same *class* of bug (cross-view semantic mismatch; non-deterministic multi-device field merge) almost certainly repeats elsewhere. I ran a 5-round systematic audit (cross-view semantic consistency · multi-device merge fields · test data distribution · boundary conditions · cross-version Codable compatibility), 3 parallel Explore agents per round, verified agent findings against source. This is commit 1 of 3 addressing the audit's P1 findings.

### Fixed (Cross-view semantic mismatch — same class as Build 77's Codex 0%)
- **"Today" cost number no longer diverges between Cost tab and provider detail page**. The Cost-tab summary card (via `CostDashboardInsights`) already used `daily.first(where: dayKey == todayKey).costUSD` and fell back to `sessionCostUSD` only when no daily point existed for today — the right preference. `ProviderDetailView.costSummarySection`, however, used `cost.sessionCostUSD` directly. Mid-day the two numbers diverged (session cost is the current session's running total; daily-point cost is the committed day-aggregate). Added `SyncCostSummary.todayTotals(now:)` returning a `TodayTotals` pair as a single source of truth; both call sites now route through it.
  - New file: `CodexBarMobile/Models/SyncCostSummary+Today.swift`
  - Updated: `CodexBarMobile/Views/ProviderDetailView.swift` (line ~96)
  - Codex-reviewer caught a midnight-drift P3 in the first patch (separate `todayCostUSD` / `todayTokens` accessors each called `Date()`, so cost and tokens could resolve from different dayKeys across local midnight). Rewrote as a single `todayTotals(now: Date = Date())` call returning both fields atomically, with injectable `now` so tests stay deterministic.

### Fixed (Multi-device merge non-determinism — same class as Build 77's appVersion)
- **`SyncedUsageSnapshot.notificationPushEnabled` merge is now deterministic regardless of CloudKit iteration order.** Pre-fix: `snapshots.contains(where: { $0 == false }) ? false : snapshots.first?.value`. When all Macs had `true`, returned `snapshots.first?.value` — `true`, correct by accident. But when some Macs had `true` and others had `nil` (e.g., one Mac is the reporter of the user's preference, the others predate the field), the result flipped between `true` and `nil` based on whichever snapshot CloudKit returned first. Fixed semantics: any explicit `false` → `false` (conservative: respect any off-signal); else any explicit `true` → `true`; else `nil`.
  - Updated: `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeSnapshots`

### Tests
- `CloudKitMergeTests.swift` +8 cases:
  - `pushEnabledAllTrue / AnyFalseWins / TrueWinsOverNil / FalseWinsOverNil / AllNil` — pin the new `notificationPushEnabled` semantics; `TrueWinsOverNil` and `FalseWinsOverNil` run the same snapshots twice with flipped iteration order to prove order-independence.
  - `todayTotalsPrefersDailyToday / FallsBackToSession / NilWhenNoData / DayKeyCoherence` — pin the new `SyncCostSummary.todayTotals(now:)` preference order, nil-when-empty behavior, and single-dayKey resolution across both fields. Fixtures pin `now` to a fixed Date so the suite is immune to midnight crossings.

### Not included in this commit (tracked for follow-up commits)
- Future-field resilience test (decoder meets unknown keys) — Commit 2
- Test-suite encoder/decoder factory unification (27 call sites still construct `JSONEncoder()` manually) — Commit 2
- Realistic-distribution fixtures across `CloudKitMergeTests / DualZoneReaderTests / SyncModelTests / SwiftDataBridgeTests` (bursty / long idle / cross-reset / cross-date / disordered timestamps) — Commit 3

## [1.3.0 (77)] — 2026-04-22 — dev build · Subscription Utilization aggregate + Mac version determinism

**Reported bug**: Cost tab's "Subscription Utilization" card shows Codex at 0% ("0% avg use") while the Codex detail page shows 16% session usage with 84 visible data points and clear bars on recent days. Also reported: with two Macs on different CodexBar versions, the "Mac App" field in Settings flips between versions across refreshes instead of stabilizing on the newer one.

**Root causes** (two independent issues surfaced together by the multi-device setup):

1. **Semantic mismatch — aggregate vs detail.** `UtilizationAggregateView.buildModel` averaged **raw** utilization entries across the window. For session quotas, a typical hour of samples looks like `[0, 0, 0, 20, 10, 5, 0, 0]` — the burst is real but the raw average is near-zero. Detail view (`UtilizationHistoryView.buildPeriodPoints`) groups by reset-period and takes `max`, surfacing the burst. Consequence: bursty-use providers (Codex) read as 0% in the aggregate while the detail chart clearly shows usage.
2. **Non-deterministic Mac App version.** `mergeSnapshots` used `snapshots.first?.appVersion`, which is whichever snapshot CloudKit iterates first — flips per refresh. Two Macs on 0.19.0 + 0.20.3 would display either version depending on fetch order.

### Fixed
- `CodexBarMobile/Views/UtilizationAggregateView.swift`:
  - `buildModel(from:windowSize:)` now collapses each provider's session entries to **daily peaks** (`max(usedPercent)` per calendar day) before aggregating. Summary cards, daily bar heights, and provider-share math all consume the same per-day peak signal.
  - Hardens against cross-version merge leakage where two "session" series end up in the merged history: aggregate now **unions entries across every session-named series** rather than picking `history.first(where: name == "session")` (which could latch onto the empty/stale one).
- `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeSnapshots`:
  - `appVersion` / `mobileVersion` now take the **highest semver** across devices (new `semverLessThan` helper) instead of `snapshots.first?.appVersion`. Result is stable across refreshes and reflects the most up-to-date client in any multi-Mac setup.
- `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeUtilizationHistories`:
  - Group by series **name** only (was `(name, windowMinutes)`). Cross-version Macs occasionally disagree on `windowMinutes` for what is logically the same account-level series (e.g. a fallback classification on an older build). Pre-fix this split into two entries named `"session"` and left the picker to guess; post-fix the entries union and the freshest device's `windowMinutes` wins.

### Tests
- `CodexBarMobileTests/SubscriptionUtilizationCompatTests.swift` +3 cases:
  - `aggregateBurstyProviderShowsPeakNotZero`: single provider with 1 peak/day + 23 zero samples — pre-fix would show 0%, post-fix shows 16%.
  - `aggregateTwoBurstyProvidersShowCorrectShare`: two providers reflect proportional share (Claude + Codex scenario from the report).
  - `aggregateUnionsMultipleSessionSeries`: empty-first + real-second session series → aggregate picks real data, not the empty stub.
- `CodexBarMobileTests/CloudKitMergeTests.swift` +5 cases:
  - `appVersionTakesHighest`, `appVersionOrderIndependent`, `semverComparison` — Mac App version determinism.
  - `utilizationMismatchedWindowMinutesUnion`, `utilizationEmptySeriesFromOneDeviceDoesNotMaskOther` — mergeUtilizationHistories regression guards.
- Also repaired two pre-existing tests in `CloudKitMergeTests.swift` whose `SyncCostSummary(…)` argument order was wrong and had silently never compiled.

## [1.3.0 (76)] — 2026-04-22 — dev build · cross-version multi-device merge hardening

**Class-of-bug fix**: every optional account-level field on `ProviderUsageSnapshot` that the merger was taking from `base` (the newest-timestamped device) silently dropped data when two Macs running different CodexBar versions synced to the same iCloud account — and the **older** Mac (without the new field) happened to refresh last. This isn't a transition scenario; it's the steady state for any user whose 2 Macs update on different schedules (could be weeks or months apart). Build 74 fixed the `perplexityCredits` instance after Codex-review flagged it; Build 76 generalizes the fix to every account-level field in the same position.

### Fixed
- `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeProviderEntries`:
  - New `latestNonNil<T>(_:_keyPath:)` helper — walks entries newest-first and returns the first non-nil value of the given keyPath. Returns nil only when every device has nil for the field.
  - `perplexityCredits`: take-latest → **latestNonNil**
  - `budget`: take-latest → **latestNonNil** (same bug: account-level API data; one Mac may not have fetched)
  - `costSummary` for non-local-cost providers (Cursor, Perplexity, OpenCode Go, etc.): take-latest → **latestNonNil** (account-level; summing only applies to local-file-backed providers: claude / codex / vertexai)
  - `loginMethod`: take-latest → **latestNonNil** (plan strings — same class)
- Inline docstring on `mergeProviderEntries` now enumerates field-by-field semantics (identity / status / rate / cost / utilization / account-level) so the class of bug is visible at the call site.

### Preserved
- `statusMessage`, `isError`, `rateWindows`, `primary`, `secondary`, `lastUpdated` stay take-latest — for these "most recent state of this device" is the right semantic (e.g. show the latest error if any Mac is erroring right now).
- `costSummary` SUM semantics for local-cost providers (claude / codex / vertexai) unchanged — per-Mac CLI files legitimately contain different data.
- `utilizationHistory` merge-and-dedup semantics unchanged.

### Tests
- `CodexBarMobileTests/CloudKitMergeTests.swift` +4 cases for the cross-version inversion scenario:
  - `perplexityCreditsInvertedFreshnessKeepsData`: older Mac has credits + newer has nil → merged keeps credits
  - `budgetInvertedFreshnessKeepsData`: same pattern on `budget`
  - `nonLocalCostInvertedFreshnessKeepsData`: same pattern on Cursor `costSummary` (non-local-cost)
  - `loginMethodInvertedFreshnessKeepsData`: same pattern on Codex plan label
- Plus `localCostStillSumsAfterRefactor`: guard against accidentally regressing the claude / codex / vertexai SUM semantic when adding the latestNonNil branch for non-local.

## [1.3.0 (75)] — 2026-04-22 — dev build · fix iOS archive: private-type leak in PerplexityCreditsCard

Build 74 archived on Mac CI (`swift test` on Package.swift Mac target) without issue, but `xcodebuild archive` against `CodexBarMobile.xcodeproj` for `iphoneos` failed with two compiler errors — `PerplexityCreditsCard.poolLabel(_:)` and `legendDotOpacity(for:)` were declared `static` (implicit internal) with a `PoolSegment.Kind` parameter whose enclosing struct is `private`. Swift archive compilation rejects the mixed-access signature even when the same code compiles fine under `swift build` on Mac because the Mac package target never touches this iOS-only view.

### Fixed
- `CodexBarMobile/Views/PerplexityCreditsCard.swift`: `poolLabel` / `legendDotOpacity` / `formatCreditsUsed` now explicitly `private static`. These helpers are implementation details of the card view; no external caller (or test) referenced them.

### Process improvement note
- CI today only covers `swift test` against the SPM Package target, which is Mac-scoped. iOS-archive-specific errors (private-type leaks, provisioning profile issues, iOS-only API usage) are only caught by `xcodebuild archive` against `CodexBarMobile.xcodeproj`. Worth adding to the CI workflow before next release.

## [1.3.0 (74)] — 2026-04-22 — dev build · Codex review fix: preserve perplexityCredits through multi-device merge

Codex CLI review (gpt-5.3-codex) on `feature/1.3.0-provider-alignment` vs `mobile-dev` surfaced one P2 regression risk: `ProviderUsageSnapshot.perplexityCredits` was added with a default-nil initializer parameter in Build 71 so that existing constructors would keep compiling. But `CloudSyncReader.mergeProviderEntries` (line 202) never passed the field through — so a user with ≥2 Macs on their iCloud account would see the merged Perplexity snapshot arrive with `perplexityCredits == nil`, making the iOS detail view regress to the legacy 3-bar fallback even when Mac 0.20.3 was sending structured data.

### Fixed
- `CodexBarMobile/iCloud/CloudSyncReader.swift` `mergeProviderEntries`: explicitly forward `base.perplexityCredits` into the rebuilt `ProviderUsageSnapshot`. "Take latest device's credits" matches the identity / loginMethod / statusMessage selection rules (all account-level fields; no cross-device sum semantics apply).

### Tests
- `CodexBarMobileTests/CloudKitMergeTests.swift` +2 cases:
  - `perplexityCreditsPreservedInMultiDeviceMerge`: Mac A (older, nil credits) + Mac B (newer, populated credits) → merged snapshot must carry Mac B's credits, not drop them.
  - `perplexityCreditsPreservedSingleDevice`: trivial single-device passthrough still carries credits (guards against a future "shortcut single-device merge" optimization dropping the field).

### Note
- This is the kind of silent-regression bug that slips through when a required field is added behind a default-nil parameter. CI / type-checker can't catch it; only end-to-end merge-path tests. Worth revisiting every call site the next time we extend `ProviderUsageSnapshot`.

## [1.3.0 (73)] — 2026-04-22 — dev build · T6 Subscription Utilization compatibility with Perplexity / OpenCode Go

Perplexity and OpenCode Go don't emit `utilizationHistory` (Perplexity surfaces three credit pools instead; OpenCode Go reports flat rate windows). The Cost-tab aggregate chart iterates `provider.utilizationHistory` and was already `compactMap`-gated on non-nil, but there were zero tests proving the guard actually trips for these two providers. T6 pins the behavior so a future refactor can't reintroduce a force-unwrap that crashes the Cost tab on launch for users with Perplexity enabled.

### Tests
- New `CodexBarMobile/CodexBarMobileTests/SubscriptionUtilizationCompatTests.swift` (5 cases):
  - Identity key stays stable across repeated calls with Perplexity + no-history in the mix
  - Identity key diverges when Perplexity is swapped for OpenCode Go (no accidental collision)
  - `n=<entries>` suffix correctly excludes zero-history providers from the total count
  - All-no-history provider list still produces a well-formed, non-empty key (no crash path)
  - Palette tints for Perplexity / OpenCode Go resolve to distinct, non-gray, non-equal colors (post-T2 consolidation)

### Notes
- No production-code change — `buildModel`'s `compactMap` + `guard let history = ..., !session.entries.isEmpty else` was already correct. This build locks the contract in unit tests so the invariant is CI-visible.
- iOS project bump 72 → 73 per discipline rule (every install bumps).

## [1.3.0 (72)] — 2026-04-22 — dev build · T5 Codex multi-account card UI + ForEach identity fix

Build 23 merged per-device Codex snapshots by `providerID|accountEmail` in `CloudSyncReader.mergeSnapshots`, so two Codex accounts (e.g., one on Mac-A, one on Mac-B) correctly produced two `ProviderUsageSnapshot` entries in the merged output. The cards never reached the user because `ContentView.swift:174` identified rows by `\.providerID` — SwiftUI collapsed the two entries into one view instance, and `accessibilityIdentifier("provider-card-codex")` double-registered on the same element. T5 fixes the identity bug and adds a nil-email ordinal fallback so every disambiguating render path has a unique, human-readable subtitle.

### Fixed
- **SwiftUI ForEach identity collision.** `ContentView.swift` list now identifies each card by a composite `cardIdentityKey` (`"providerID|accountEmail"`) that matches `mergeSnapshots`'s bucket. Two Codex accounts now render as two distinct cards that animate independently, respect their own navigation destinations, and each own a unique `accessibilityIdentifier`.
- Accessibility identifiers updated to `provider-card-codex|alice@example.com` style — a UI test or accessibility inspector can now resolve the exact card without ambiguity.

### Added
- `CodexBarMobile/Models/ProviderUsageSnapshot+Identity.swift`: iOS-only extension exposing `cardIdentityKey` (`"\(providerID)|\(accountEmail ?? "")"`). Kept iOS-scoped because the Mac target doesn't render cards; Shared stays untouched so no Mac re-release is needed for T5.
- `ProviderUsageView.duplicateOrdinal: Int?`: 1-based ordinal among same-`providerID` siblings. `nil` keeps the pre-T5 single-card subtitle behavior so non-Codex providers render identically.
- Subtitle selection rule: `email (non-empty) > localized "Codex N" ordinal > nil`. Empty-string email treated as nil for defensive parity with the merger's fallback.
- `Localizable.xcstrings`: new key `"provider-account-ordinal"` (`%@ %lld` format) across en / zh-Hans / zh-Hant / ja. Plus T3's Perplexity strings (`"Credits"`, `"Monthly credits"`, `"Bonus credits"`, `"Purchased credits"`, `"exp."`) batched in the same update.

### Tests
- New `CodexBarMobile/CodexBarMobileTests/ProviderUsageViewSubtitleTests.swift` (8 cases):
  - `cardIdentityKey` shape for present / nil email
  - Two distinct accounts produce distinct `cardIdentityKey`s
  - Subtitle rule × 4 branches (single+email / single+nil / multi+email / multi+nil)
  - Empty-string email treated as nil in the multi-card ordinal fallback

### Deferred (tracked as Branch B follow-up)
- Workspace-name as a subtitle source. Mac's `ManagedCodexAccount` / `ObservedSystemCodexAccount` carry `workspaceLabel` but `SyncCoordinator` strips it before push. Adding `workspaceName` to `ProviderUsageSnapshot` would be a Shared-contract change + Mac SyncCoordinator update — coordinated with a Mac release window. For now, ordinal fallback is sufficient to disambiguate nil-email multi-card scenarios.
- Research doc: `CodexBarMobile/Research/014-codex-multi-account-ios.md`.

## [1.3.0 (71)] — 2026-04-22 — dev build · T3 Perplexity 3-segment credit detail page

Upstream `PerplexityUsageSnapshot` (`Sources/CodexBarCore/Providers/Perplexity/`) exposes three distinct credit pools — monthly recurring, promotional/bonus, on-demand purchased — plus Pro/Max plan inference and a renewal date. Mac's `toUsageSnapshot()` collapses all of that into three generic `UsageSnapshot` rate windows for the legacy pipeline, so iOS sees three flat bars in fallback blue and no pool breakdown. T3 extends the shared sync contract with a structured `SyncPerplexityCreditSummary` field and adds a native stacked-bar detail view.

### Added
- `Shared/Models/UsageSnapshot.swift`: new `SyncPerplexityCreditSummary` Codable struct (`recurringTotalCents` / `recurringUsedCents` / `promoTotalCents` / `promoUsedCents` / `promoExpiresAt` / `purchasedTotalCents` / `purchasedUsedCents` / `renewalAt` / `planName` / `balanceCents`, all Optional). Amounts in cents to match upstream's raw units; iOS formats for display.
- `ProviderUsageSnapshot` gains `perplexityCredits: SyncPerplexityCreditSummary?`. All writers default to nil; the custom `init(from:)` uses `decodeIfPresent` so Mac 0.20.2 payloads (no key) continue to decode cleanly with `perplexityCredits == nil`.
- New `CodexBarMobile/Views/PerplexityCreditsCard.swift`: stacked 3-segment horizontal bar (pool widths proportional to each pool's `*TotalCents`), Pro/Max badge, renewal-date countdown, and a per-pool legend. Rendered only when both `providerID == "perplexity"` and `perplexityCredits != nil`; otherwise falls through to the existing generic rate-window list.
- `ProviderDetailView.primaryUsageSection` — the switch point that chooses the card vs the legacy list.
- `ProviderSnapshotModel.perplexityCreditsData: Data?` SwiftData column + `SwiftDataBridge` encode-on-write / decode-on-read passthrough. Keeps the credit breakdown alive across cold starts (matches existing `costSummaryData` / `budgetData` pattern).

### Tests
- `Tests/CodexBarTests/JSONCodecConsistencyTests.swift` +5 cases:
  - Fully-populated `SyncPerplexityCreditSummary` round-trip (both Date fields)
  - All-nil `SyncPerplexityCreditSummary` round-trip (free-tier edge case)
  - `ProviderUsageSnapshot` with populated `perplexityCredits` round-trip
  - Backward-compat: hand-rolled legacy JSON (no `perplexityCredits` key) decodes with `perplexityCredits == nil`
  - `ProviderUsageEnvelope` zlib compression round-trip with `perplexityCredits` populated — covers the full Mac → CloudKit CKRecord → iOS pipeline

### Notes
- **Mac-side mapping (`SyncCoordinator.swift`) is required for the user-facing feature to light up.** Mac currently discards `PerplexityUsageSnapshot` in `toUsageSnapshot()` before `SyncCoordinator` sees it. A follow-up Mac 0.20.3 Sparkle release needs to add `perplexityUsage: PerplexityUsageSnapshot?` on Mac-local `UsageSnapshot` (mirroring the `zaiUsage` / `minimaxUsage` escape-hatch pattern) and map it into the shared struct. Until then iOS 1.3.0 Perplexity detail page silently falls back to the legacy 3-bar rendering.
- Research doc: `CodexBarMobile/Research/013-perplexity-detail.md`.

## [1.3.0 (70)] — 2026-04-22 — dev build · T2 consolidate provider color palette

Provider tint color derivation was duplicated (with subtle drift) across 5 files: `ProviderUsageView.providerColor`, `ProviderDetailView.providerColor`, `UtilizationAggregateView.providerColor(for:)`, `ContentView.providerTint(for:)`, and `CostShareService.providerColor(for:)`. The aggregate view in particular used an exact-match switch with a `.gray` default — every provider not in its explicit 5-case list rendered gray in the utilization charts regardless of what the cards showed. Perplexity + OpenCode Go added in Build 69 would have collapsed into the generic blue fallback in every single site.

### Added
- New `CodexBarMobile/Models/ProviderColorPalette.swift` — single source of truth. `ProviderColorPalette.color(for providerIdentifier:)` accepts either `providerID` (`"opencodego"`) or display name (`"OpenCode Go"`) via a lowercased + space-stripped normalization, so callers in both forms get the same color.
- Perplexity → brand teal `(0.13, 0.50, 0.55)` ≈ #21808D.
- OpenCode Go → `.mint` so it stays visually separable from OpenCode Zen's blue when both cards are on screen.
- Specificity ordering: the `opencodego` match is evaluated **before** the broader `opencode` match. Without the ordering `"opencodego".contains("opencode")` would collapse Go back into Zen's blue — pinned by test `opencodeGoDoesNotCollideWithOpencode`.

### Changed
- `ProviderUsageView.providerColor` / `ProviderDetailView.providerColor` / `ContentView.providerTint(for:)` / `CostShareService.providerColor(for:)` / `UtilizationAggregateView.providerColor(for:)` — all now delegate to `ProviderColorPalette.color(for:)`. Removed 5 copies of the same (drifted) logic.
- `CostShareService` call site switched from `row.provider.providerName` to `row.provider.providerID` — ID is the stable canonical form.
- Aggregate view's legacy `.gray` default for unknown providers replaced by the palette's blue fallback. Net visual change in the utilization chart: providers that were previously gray (e.g. OpenCode, Amp, Kimi, …) now render with their proper color.

### Tests
- New `CodexBarMobile/CodexBarMobileTests/ProviderColorPaletteTests.swift` (10 cases) — brand-color pinning, specificity ordering, ID-vs-displayName equivalence, empty / unknown fallback. Extends `UIColor` with a `isApproximately(_:tolerance:)` helper so two SwiftUI `Color`s round-tripped through `UIColor` don't fail on float drift.

### Notes
- Total deleted lines (5 call sites minus new palette + new tests): net +~50 LOC but now there's exactly one matrix to update when the next upstream provider lands.

## [1.3.0 (69)] — 2026-04-22 — dev build · T1 QuotaProviderList append Perplexity + OpenCode Go

Upstream CodexBar 0.20 introduced two new providers on the Mac side — Perplexity and OpenCode Go. `QuotaProviderList` is the single source of truth for the `(provider, state)` matrix that Mac writes `QuotaTransition` records to and iOS creates `CKRecordZoneSubscription`s for. Without updating both sides, iOS never subscribes to Perplexity / OpenCode Go quota zones — so those providers' quota-depleted / -restored pushes never reach the phone.

### Added
- `Shared/Notifications/QuotaProviderList.swift`: append `Provider(id: "perplexity", displayName: "Perplexity")` and `Provider(id: "opencodego", displayName: "OpenCode Go")`. Display names verified to match `ProviderDescriptor.metadata.displayName` in `Sources/CodexBarCore/Providers/Perplexity/PerplexityProviderDescriptor.swift` and `.../OpenCodeGo/OpenCodeGoProviderDescriptor.swift` so the iOS alert body reads "Perplexity session quota depleted" / "OpenCode Go 的会话额度已耗尽" on the corresponding locale without any extra mapping.
- Provider count 23 → 25. Subscription count 46 → 50 (25 providers × 2 states).

### Tests
- New `Tests/CodexBarTests/QuotaProviderListTests.swift`: pins the provider count, requires Perplexity + OpenCode Go entries with the correct `displayName`, asserts OpenCode Zen + Go stay distinct, forbids duplicate / blank IDs, and verifies `quotaZoneName(providerID:state:)` composes to the exact strings Mac + iOS both depend on. Also spot-checks the derived subscription count stays at 50 so the factor-of-2 state assumption is visible to reviewers.

### Notes
- iOS 1.2.0 users don't get these two new zones (their `QuotaProviderList` is still 23). They'll miss Perplexity / OpenCode Go pushes until they install 1.3.0, but existing 23 provider pushes keep working without interruption.

## [1.3.0 (68)] — 2026-04-21 — dev build · hardening pass (Research/012)

After Codex CLI's 2 P-level findings landed in Build 67, an additional hardening review (Phase 1 Explore agent) surfaced one P1 + several P2/P3. Build 68 fixes them and adds defensive scenario tests so a future regression on the same shape can't slip through silently.

### Fixed
- **P1 · `compositeKey` format drift** (`SwiftDataSchema.makeCompositeKey`). Was emitting `{deviceID}|{providerID}|` (empty for nil email), while `CloudSyncManager.perProviderRecordName` and `SnapshotCache.compositeKey` were emitting `{deviceID}|{providerID}|_`. Today nothing in the live code actually compares CloudKit recordName against SwiftData compositeKey, so the drift wasn't a runtime bug — but ANY future code that does (e.g. delete-by-recordName from CloudKit applied to SwiftData) would silently miss matching rows. Aligned all three sites on `_` for nil. Pinned by new test `compositeKeyNilEmailFormat`.
- **P2 · Concurrent silent-push storm could land an older delta on top of newer cache state**. `SyncedUsageData.fetchFromCloudKit` and `refreshIncremental` now both go through a `coalesceRefresh` funnel — if a refresh task is in flight, additional callers await it instead of starting a parallel fetch. Trades a tiny bit of throughput for race-free state mutation under push storms.
- **P2 · Encoder/decoder strategy drift risk**. New `CloudSyncConstants.makeJSONEncoder()` / `makeJSONDecoder()` factories return JSON codecs with `.iso8601` date strategy on both sides. All production callers (`CloudSyncManager`, `SwiftDataBridge`, `SyncCoordinator.providerDiffEncoder`, the static `decodeEnvelopeStatic`) now use the factories — never construct raw `JSONEncoder()` / `JSONDecoder()`. Build 65/66 root cause cannot recur silently.

### Added (scenario tests, designed around USER-FACING POSSIBILITIES not code paths)
- `JSONCodecConsistencyTests` (Mac, 9 cases) — pins the encoder/decoder factory contract: every `Sync*` type that carries a `Date` is round-tripped explicitly. Two tests assert that mixing the factory codec with the default `JSONEncoder/Decoder` FAILS, which means a future "let me just use `JSONEncoder()`" change will break a test instead of a user.
- `SnapshotCacheTests` +4 cases — multi-account same provider, nil-email + emailed coexistence, compositeKey format pin, delta with email doesn't disturb a nil-email entry.

### Reviewed but no change needed
- Hardcoded `CKModifyRecordsOperation` batch size 200 — within CloudKit's documented limit, deferred.
- `nonisolated(unsafe)` accumulators in `fetchPerProviderZoneChanges` — verified safe (single-threaded accumulation inside `withCheckedThrowingContinuation`).
- AppDelegate `iCloudAccountChanged` observer cleanup — singleton, app-lifetime, no leak.
- `SyncedUsageData` deinit cleanup of NotificationCenter token — `@State`-backed app-lifetime instance + `[weak self]` makes the leak benign; explicit cleanup deferred (would need `@MainActor deinit` workaround).

### Hardening plan
- Full plan + findings log: `CodexBarMobile/Research/012-refactor-1.3.0-hardening-plan.md`.

## [1.3.0 (67)] — 2026-04-21 — dev build · Codex review fixes (2 correctness issues)

Codex CLI review of `refactor-1.3.0` vs `mobile-dev` surfaced two P-level defects — both now fixed.

### Fixed
- **P1 · Transient CloudKit failures no longer blank out cached data** (`SyncedUsageData.fetchFromCloudKit`). Previously `replaceFromFullFetch` was called unconditionally even when both zone queries returned `.error`, wiping the in-memory cache and showing the user a blank screen whenever they launched offline or CloudKit was momentarily unreachable. Now each zone's result is classified: `.success` / `.empty` replace that bucket, `.error` preserves it. If BOTH zones error, the cache is left entirely untouched and only the sync status flips to `.error`. `SnapshotCache.replaceFromFullFetch` now takes optional args where `nil` means "leave this bucket alone."
- **P2 · Partial-encode failures no longer silently skip retries** (`CloudSyncManager.pushPerProviderRecords`). The method used to return `.success(message: "Encoded X / failed Y")` when some envelopes failed to encode; the Mac `SyncCoordinator` then updated `lastProviderHashes` for all submitted providers, including the ones that never reached CloudKit, so they stayed stale until their content changed again. Now partial-encode failures return `.failure` — the coordinator keeps the pre-push hash cache and retries everyone next cycle. Slightly wasteful (re-uploads the ones that did land this cycle) but correct.

### Tests
- `SnapshotCacheTests` +2 cases: `nilPerProviderArgPreserves`, `nilLegacyArgPreserves`.

## [1.3.0 (66)] — 2026-04-20 — dev build · fix Usage cold-start blank (two root causes)

User reported Usage tab shows blank on cold start while Cost shows data instantly. After two rounds of wrong diagnosis (TabView lazy, then `.thickMaterial` GPU cost), Build 64/65 diagnostic prints exposed the actual root causes.

### Fixed
- **Date encoding strategy mismatch in `SwiftDataBridge`.** `upsertProvider` used the default `JSONEncoder` which serialises `Date` as a `TimeInterval` double, while `readAllDeviceSnapshots` configured its decoder with `dateDecodingStrategy = .iso8601` and expected an ISO8601 string. Every `SyncRateWindow` / `SyncBudgetSnapshot.resetsAt` silently failed to decode, `try?` swallowed the throw, and `rateWindows` came back as `[]`. Cost tab was unaffected only because `SyncCostSummary` has no `Date` fields and the user's Claude budget happened to have `resetsAt == nil`. Fix: set `encoder.dateEncodingStrategy = .iso8601` in `SwiftDataBridge.upsertProvider` to match the decoder.
- **Ghost envelopes in `DeviceProvidersZone`.** Mac-side P4 pushed `ProviderUsageSnapshot`s with `accountEmail == nil` during early app startup (before OAuth / cookies loaded), producing CKRecords with recordName `{deviceID}|{providerID}|_`. Once the provider's account email loaded, subsequent pushes went to a DIFFERENT recordName (`{deviceID}|{providerID}|user@example.com`), leaving the empty "ghost" record behind. The iOS side then upserted both into SwiftData and into the merged view, producing a blank third "codex" card overwriting the real data. Fix: `SnapshotCache.isGhost(...)` drops envelopes where `primary`/`secondary`/`rateWindows`/`costSummary`/`budget`/`statusMessage` are all nil/empty and `isError == false`. Applied in `replaceFromFullFetch` / `applyDelta` / `replacePerProviderFromReplay`.
- Mac-side preventative fix (skip empty-data pushes to begin with) is a separate follow-up; this defense eliminates the symptom without a Mac rebuild.

### Tests
- `SnapshotCacheTests` +3 cases: ghost dropped from full fetch, ghost dropped from delta, error-only provider NOT considered ghost.

### Removed
- Diagnostic prints added in Build 62 / 64 / 65 are all cleaned up.

### Also re-verified
- `recordName` Queryable index on `DeviceProviderSnapshot` in CloudKit Production schema (user deployed earlier); per-provider zone query now returns `.success(1 devices)` instead of `.error(Field 'recordName' is not marked queryable)`.

## [1.3.0 (65)] — 2026-04-20 — dev build · trace SwiftData rateWindows write/read

Build 64 confirmed SwiftData hydrate returns `rateWindows=0` on every cold start despite fresh full fetch. Build 65 adds prints inside `SwiftDataBridge.upsertProvider` (what gets encoded) and `readAllDeviceSnapshots` (what gets decoded) to find which side drops the data.

## [1.3.0 (64)] — 2026-04-20 — dev build · deeper diagnostic for Usage cold-start blank

User confirmed Build 63's material swap did NOT fix the perceived blank. So the problem isn't GPU-first-frame cost — it's a data-layer asymmetry between Cost and Usage tabs. Adds `[CodexBar Diag]` prints that log:
- Per-device / per-provider hydrate contents from SwiftData (rateWindows count, costSummary presence, etc.)
- Which branch `UsageTab.body` and `CostTab.body` take (Onboarding vs EmptyState vs content)
- `fetchFromCloudKit` entry + per-zone results
Will be removed once the real root cause is identified.

## [1.3.0 (63)] — 2026-04-20 — dev build · fix Usage-tab cold-start "blank" via material swap

### Fixed
- **Usage tab no longer shows a ~1s blank on cold start.** `ProviderUsageView`'s card background was `.thickMaterial` — the most expensive material in the system (large Gaussian blur radius + heavy tint + independent GPU compositing pass per card). On first render after kill+relaunch, GPU setup for every card's thick material blocked the first frame ~1s. Changed to `.ultraThinMaterial` to match the rest of the app (`CostMetricCard`, `BudgetProgressView`, `ContentView`'s Cost dashboard, `ProviderDetailView`, `UtilizationAggregateView`). Verified via `[CodexBar Timing]` diagnostic prints (Build 62): data was always in memory at body time (`providers=2` within 0.238s of init), the delay was purely GPU first-frame compositing.

### Investigation
- `git blame` showed the `.thickMaterial` was introduced in commit `408ce6f25` (2026-03-19) with unrelated message "Fix mobile metrics and release notes", replacing the original `.regularMaterial + glassEffect` pair. No design discussion recorded; bundled with 5 other unrelated file changes. Cost-side cards (`CostMetricCard` etc.) were never changed to match — the asymmetry was accidental drift, not a deliberate visual choice.

### Removed
- The `[CodexBar Timing]` diagnostic prints added in Build 62 (reverted now that the root cause is confirmed and fixed).

### Visual impact
- On CodexBar's solid `systemGroupedBackground`, `.thickMaterial` and `.ultraThinMaterial` are visually indistinguishable (user inspection confirms). No user-visible change to card appearance.

## [1.3.0 (62)] — 2026-04-20 — dev build · diagnostic timing prints

Non-functional. Adds `[CodexBar Timing]` print lines in `SyncedUsageData.init`, `UsageTab.body`, `ProviderListView.body`, and per-card `onAppear` so I can measure the "Usage tab blank ~1–2s on cold start" observation. To be removed once the root cause is confirmed.

## [1.3.0 (61)] — 2026-04-19 — dev build · P6 + P7 v2 (cache-based, multi-device-safe)

### Re-introduced, re-designed
- **P6 · Change-token incremental sync (v2)** — `CKFetchRecordZoneChangesOperation` on `DeviceProvidersZone` is back, with a clean separation from SwiftData: the v1 bug (stale SwiftData rows from past full-fetch upserts leaking into the per-provider bucket) is eliminated because the incremental path now writes to an in-memory `SnapshotCache` with explicit `perProviderByDevice` vs `legacyByDevice` slots.
- **P7 · Silent-push-driven refresh (v2)** — `CKRecordZoneSubscription` on `DeviceProvidersZone` and the `AppDelegate.didReceiveRemoteNotification` routing are both restored, now triggering `SyncedUsageData.refreshIncremental` which applies the change-token delta to the cache. Legacy bucket is never touched by a silent push.

### Design changes vs v1
- `SnapshotCache` (in `CodexBarMobile/Models/SnapshotCache.swift`) keeps per-zone slots explicitly. Priority merge reads from it and never consults SwiftData.
- Token persistence via `SwiftDataBridge.loadChangeToken` / `saveChangeToken` kept (tokens are explicitly zone-scoped, no ambiguity). `applyPerProviderDelta` deleted — cache replaces its role.
- `SyncedUsageData.fetchFromCloudKit` now calls the two zone queries separately and feeds both into `cache.replaceFromFullFetch`. Prior logic that went through `CloudSyncManager.fetchAllDeviceSnapshots`'s internal priority merge is still available but unused by the cache path — kept for completeness.

### Multi-device trace
Research/011 carries six explicit scenarios (Mac-A-new + Mac-B-old, both new, both legacy, iPhone-old × Mac-new, iPhone-new × Mac-old, 2 iPhones × 2 Macs). The test suite `SnapshotCacheTests` has assertions that mirror three of them directly.

## [1.3.0 (60)] — 2026-04-19 — dev build · rollback P6 + P7

Multi-device data regression reverted. Build 59 shipped P6 (change-token incremental sync) and P7 (silent push → incremental refresh), but the incremental path read per-device state from SwiftData, which also contained historical rows populated by past legacy-zone full-fetch upserts. When Mac A (on the new per-provider zone) triggered a silent push, the incremental path wrote Mac A's fresh delta to SwiftData, then reconstructed the "per-provider zone set" by reading SwiftData — which wrongly included stale Mac B rows from legacy history. The priority merge then let stale Mac B data win over the fresh legacy fetch, producing flicker / missing-data symptoms in multi-Mac setups.

### Reverted
- **P7 · Silent-push-driven refresh** — subscription setup, AppDelegate `didReceiveRemoteNotification` handler, and the `SyncedUsageData.refreshIncremental` observer are all removed. Silent pushes to `DeviceProvidersZone` no longer trigger any iOS work.
- **P6 · Change-token incremental sync** — `CKFetchRecordZoneChangesOperation` path, change-token persistence, `SwiftDataBridge.applyPerProviderDelta`, and the `CodexBarMobileTests/Storage/PerProviderDeltaTests` suite are all removed.

### Kept (still correct)
- **P3 · SwiftData cold-start hydrate** — unchanged, no multi-device issue.
- **P4 · Mac dual-write** — Mac still writes per-provider records to `DeviceProvidersZone` alongside the monolithic legacy record. Shared types (`ProviderUsageEnvelope`, `PayloadCompression`) retained.
- **P5 · Dual-zone reader** — the FULL-fetch path (app open / pull-to-refresh) queries both zones fresh from CloudKit every time and priority-merges per device. This path never touched SwiftData for the priority decision, so it didn't have the bug.

### Design debt carried forward
The incremental + silent-push behavior needs a redesign before it can come back. The lesson: SwiftData is a read-through cache, not a per-zone "what's in this zone" mirror, because full-fetch upserts and delta upserts both write to it indiscriminately. Any future incremental path must either track zone-of-origin on `DeviceRecord`, or stop reading SwiftData for priority decisions and query CloudKit fresh each push.

## [1.3.0 (59)] — 2026-04-19 — dev build (refactor-1.3.0)

Internal-only build. No user-visible feature changes yet; the tap target is the sync pipeline, which reshapes how device data flows from Mac → CloudKit → iPhone.

### Refactored (sync layer, invisible to users on this build)
- **P3 · SwiftData-hydrated cold start** — `SyncedUsageData.init` now tries the local SwiftData mirror before falling back to KVS, so the Cost tab no longer flashes a stale "$46" before settling on the real total a second later. First launch on a fresh phone still uses KVS (SwiftData empty).
- **P4 · Mac dual-write** (requires Mac 0.20.1+) — Mac writes each provider into its own CloudKit record in a new `DeviceProvidersZone`, zlib-compressed, in addition to the monolithic `DeviceSnapshot` legacy zone. Older iOS builds keep reading legacy; this build can use either.
- **P5 · Dual-zone reader with priority merge** — iOS queries both zones; per-device, the new per-provider records win over the legacy monolithic record, with graceful fallback when either side is empty.
- **P6 · Change-token incremental sync** — `CKFetchRecordZoneChangesOperation` with persisted `CKServerChangeToken` replaces the full-table query for the per-provider zone. Typical sync transfer drops from ~2 MB to a few dozen KB. `changeTokenExpired` triggers a transparent full replay.
- **P7 · Silent-push-driven refresh** — new `CKRecordZoneSubscription` with `shouldSendContentAvailable = true` on `DeviceProvidersZone`. When Mac writes, iOS wakes silently, runs the change-token fetch, applies to SwiftData, and views refresh — without the user pulling to refresh.

### Notes
- End-to-end (new zone actually populated) requires a Mac running 0.20.1+ AND the CloudKit Production schema to be deployed for the new record type. Until both land, iOS silently falls back to legacy, zero regression.
- Build 59 includes Build 58's bug fix for compositeKey format mismatch between SwiftData and CloudKit record names (aligned on `"_"` for nil `accountEmail`).

## [1.2.0 (58)] — 2026-04-15

### Reverted (partially) + improved
- **Restored the Setup Guide upgrade-notice block** that Build 57 deleted. The decision to drop it was wrong — that orange "Important" callout is a prominent way to tell new users they need a specific Mac version before iPhone features will work, and removing it left the Setup Guide silent on the Mac requirement (only Step 1 said "install on Mac" without specifying which Mac version).
- Block text updated for the 1.2.0 era: title `"v1.2.0 — New Mac App Required"`, body `"Subscription Utilization and Mac→iPhone push notifications need CodexBar Mac 0.19.0 (Build 54.1.2.0) or later."`. Both strings added to `Localizable.xcstrings` with full en / ja / zh-Hans / zh-Hant translations — the gap that made the original Build 56-and-earlier text fall back to English on non-English iPhones.

## [1.2.0 (57)] — 2026-04-15

### Fixed
- **Setup Guide (onboarding) had hardcoded English text "v1.1.0 — New Mac App Required" at the top of the Chinese/Japanese/Traditional-Chinese pages.** The upgrade-notice block was introduced for the 1.0.0 → 1.1.0 transition, never updated for 1.2.0, and never added to `Localizable.xcstrings`. Dropped the entire block — the same information (download Mac app from GitHub) is already covered by Step 1 of the setup and by the Important section of the 1.2.0 release notes. One less thing to keep in sync across four languages.
- **Audit of all `Text(…)` literals found 7 more hardcoded English strings missing from `Localizable.xcstrings`**: `"Data pushed by Mac · Pull to check for updates"` (the Usage/Cost tab status bar), `"Mac Update Available"` + `"Your Mac is using legacy sync. …"` + `"Download Latest Mac Version"` (the legacy-sync upgrade banner in About & Sync), `"Sync Status"` + `"No devices synced yet"` + `"No device data available"` (About & Sync section labels / empty states). Added 4-language translations for all 7. Developer Tools strings deliberately left in English per earlier decision.

### Notes
- The onboarding trigger logic is unchanged: it compares `@AppStorage("onboardingSeenVersion")` against `CFBundleShortVersionString` (the marketing version, e.g. `1.2.0`), not the build number. A build-only update from 1.2.0 (56) to 1.2.0 (57) **does not** retrigger onboarding. Onboarding only auto-shows on a marketing version bump (e.g. 1.1.0 → 1.2.0) or when the user explicitly taps `Settings → Setup Guide`.

## [1.2.0 (56)] — 2026-04-14

### Changed
- **1.2.0 release notes restructured per user feedback**: the Settings / Developer Tools bullet moved from `What's New` to `Improvements` (it is a tidy, not a feature), and the "About page build date in English" clause was removed entirely — that fix landed on the Mac side (commit `686311b3`, task `6gJG6vpwJxG6frm2` "1.2.0 · Mac 端 Utilization CloudKit 完善 + 版本升级 + About 修复") and does not belong in iOS release notes. Final structure: 3 `What's New` items (Utilization, Multi-Mac, Push) + 1 `Improvements` item.

## [1.2.0 (55)] — 2026-04-14

### Fixed
- **1.1.0 release notes were English-only on non-English iPhones** — all 8 of the 1.1.0 `What's New` / `Improvements` / Important / summary entries were never added to `Localizable.xcstrings`, so Chinese / Japanese / Traditional-Chinese users saw the raw English `String(localized:)` keys. Added full 4-language translations for every 1.1.0 entry.
- **1.2.0 release notes had untranslated section headers** — the `"Important"` and `"Improvements"` section titles were missing from `Localizable.xcstrings` while the item bodies were localized, which made the 1.2.0 notes render as a bizarre mix of Chinese body text under English headers. Added 4-language translations for both titles.

### Changed
- **1.2.0 release notes rewritten around the four features that 1.2.0 actually ships** (Subscription Utilization visualization, multi-Mac data merge, Mac→iPhone push notifications with provider name, streamlined Settings + Developer Tools). `Improvements` section folded into the fourth "What's New" bullet. All four bullets translated to en / ja / zh-Hans / zh-Hant.
- **Important section now requires (not recommends) Mac 0.19.0 (Build 54.1.2.0) or later** — previous wording said "works best with the latest Mac app", which understated the dependency. Subscription Utilization data collection and Mac→iOS push both genuinely need that Mac version.
- **Push Setup diagnostic subscription list grouped by ID pattern** — before Build 55 the `allSubscriptions()` output listed all 47 subscriptions one per line, drowning the real signal; now grouped into `device-snapshot-changes`, `quota-*-depleted-sub`, `quota-*-restored-sub`, and a `quota-transition-*` LEGACY bucket (should always be 0 after a healthy Build 54 upgrade). Each group shows its count + a sample `alertBody`.

## [1.2.0 (54)] — 2026-04-14

### Fixed
- **Push notifications now show the provider name in the body** — e.g. "Codex 的会话额度已耗尽" on a Chinese iPhone, "Codex session quota depleted" on an English iPhone. Build 53's `UNNotificationServiceExtension` approach proved unreliable on this CloudKit container — on-device verification showed the extension didn't wake, very likely because the container silently strips the `shouldSendMutableContent` flag the same way it strips `titleLocalizationArgs`. Build 54 falls back all the way to the mechanism Build 48 / 52 proved persists reliably (a plain `CKRecordZoneSubscription` with a static `alertBody`) and scales it horizontally.

### Changed
- **One subscription per `(provider, state)` pair, ≈ 46 subscriptions total**, each with the provider's display name pre-baked into its `alertBody` via `String(format: "%@ session quota depleted", providerName)` against localized templates (`Push.QuotaDepleted.bodyWithProvider` / `Push.QuotaRestored.bodyWithProvider`, 4 languages). The iPhone's locale is resolved at subscription-setup time.
- **Mac `writeQuotaTransition` routes to a per-provider zone** named `Quota-{providerID}-{state}Zone` (e.g. `Quota-codex-depletedZone`). The shared Build 52/53 `QuotaDepletedZone` / `QuotaRestoredZone` are no longer written to — Mac simply picks the zone matching the current `(provider, state)`.
- **`QuotaProviderList` (shared)** lists the 23 providers + display names that track `UsageProvider` on Mac. New provider additions upstream require an iOS shipping update to be subscribed to.
- **Sub setup batched**: a single `modifyRecordZones(saving: [...46 zones])` + a diff-driven `modifySubscriptions(saving: [drifted subs only], deleting: [])`. Returning launches whose configs are already correct cost only one `allSubscriptions()` round-trip.
- **Legacy subs deleted on upgrade**: `quota-transition-zone-sub` (Build 42–49) + `quota-transition-depleted` / `quota-transition-restored` (Build 52/53).

### Notes
- **The `CodexBarMobilePushExtension` target is retained but dormant**: subscriptions no longer set `shouldSendMutableContent`, so iOS will never wake the extension. We keep the code around as a future-revival hook; for the foreseeable future the plain static-body mechanism is the only one that has been empirically proven on this container.
- **The body text includes the provider; the title stays as the iOS default "CodexBar"**. Title override requires the extension path, which this container does not support.

## [1.2.0 (53)] — 2026-04-14

### Added
- **Push notifications now include the provider name as the title.** Mac local notifications have always shown e.g. "Codex session depleted" — iOS push from Build 52 only showed the state ("会话额度已耗尽") without provider. Build 53 closes this gap via a new `UNNotificationServiceExtension` (`CodexBarMobilePushExtension`) target that intercepts the push, fetches the latest `QuotaTransition` record from the triggering zone, reads `providerName`, and sets it as `content.title`. The Build 52 locale-resolved body is preserved as `content.body`, so a Chinese iPhone now sees title "Codex" + body "会话额度已耗尽" instead of just "会话额度已耗尽".

### Architecture notes
- The extension target carries its own iCloud + CloudKit container entitlements (Production environment) so it can fetch records from the same private database the main app uses.
- Subscriptions now set `info.shouldSendMutableContent = true` so APNs flags pushes with `mutable-content: 1`, which is what wakes the extension. This boolean does not reference any record fields, so it does not trigger the Build 49/50 "args silently drop" failure mode (`titleLocalizationArgs` / `alertLocalizationArgs` referencing record fields). The "already correct" check on existing subscriptions is updated to require `shouldSendMutableContent`, so Build 52 subs are recreated on first launch of Build 53.
- Extension fetch path: `CKQuery(recordType: "QuotaTransition", predicate: TRUEPREDICATE)` against the state-specific zone with `desiredKeys: ["providerName", "transitionAt"]`, sorted in code by `transitionAt` (no Sortable schema requirement). If the fetch fails or times out (~30s budget), the extension delivers the unmodified push content — same UX as Build 52, no regression.
- Pure parsing helpers moved to `Shared/Notifications/QuotaZoneNotificationParser.swift` so the test target can verify them without depending on the extension target. Seven new unit tests in `CodexBarMobileTests/QuotaZoneNotificationParserTests.swift` cover zone-name acceptance, legacy-zone rejection, empty/non-CloudKit `userInfo` handling.

### Research
- 15 alternative architectures for adding provider-in-push were enumerated by parallel research agents and are documented in `Research/005-push-provider-alternatives.md`. The chosen `UNNotificationServiceExtension` design (matching alternative #14 in that doc) is fully described in `Research/006-push-provider-nse.md`.

## [1.2.0 (52)] — 2026-04-13

> **Version label note:** `xcodebuild -exportArchive` auto-bumps `CFBundleVersion` on App Store Connect collision. The commit that produced this build (`8654c6d7`) was authored with `CURRENT_PROJECT_VERSION = 51` but uploaded as 52 because 51 was already present on ASC. The `project.yml` bump 51 → 52 in the subsequent commit reconciles the label.

### Fixed
- **Push notification subscription persistence — regression from Build 51 fixed.** Build 51 (the commit that shipped as TestFlight 52 — see label note above; the preceding TestFlight 51 was labelled "Build 50" in the commit that produced it) tried to use `CKSubscription.NotificationInfo.titleLocalizationArgs = ["providerName"]` on the assumption that `providerName` (present in the Production schema since the post-Build-48 Shared changes) was safe to reference. On-device verification proved otherwise: `allSubscriptions()` returned only the legacy `device-snapshot-changes` sub after install, same failure mode as the earlier arg-stripping build (commit `65960ac8`). **Any subscription carrying args is silently dropped by CloudKit on this container, regardless of which field the args reference.**

### Changed
- **Push notification text is now localized on the iOS side via `String(localized:)`.** The `alertBody` is resolved at subscription-creation time against the iPhone's current locale (using the pre-translated `Push.QuotaDepleted.body` / `Push.QuotaRestored.body` keys in `Localizable.xcstrings`) and baked into the subscription payload as a literal string. CloudKit delivers that string verbatim at push time — no args, no server-side substitution. Each iPhone sees the push in its own language (en / ja / zh-Hans / zh-Hant); Mac-side language is irrelevant.
- If the user switches iPhone locale between sessions, the push text updates on next app launch: the `"already correct"` check compares the stored `alertBody` against a freshly-resolved `String(localized: …)`, mismatches, and recreates the subscription with the new locale's text.
- The Build 50 zone split (`QuotaDepletedZone` / `QuotaRestoredZone`) is **retained**. State differentiation still comes from the zone, which is how iOS knows at setup time which localized body to bake into which subscription.

### Notes
- Definitive takeaway recorded in `Research/004-alert-push-cloudkit.md`: subscription localization args are unusable on this CloudKit container. Pass-through-from-record designs (Plan A) are not viable. The replacement pattern is iOS-side `String(localized:)` at subscription-creation time, keyed off the zone (which is state-specific).

## [1.2.0 (51)] — 2026-04-13

> **Version label note:** This entry was committed as "(build 50)" in commit `c899e997` (`project.yml` = 50), but `xcodebuild -exportArchive` auto-bumped the upload to 51 after App Store Connect rejected 50 as a duplicate. TestFlight delivered build 51. **Build 51 turned out to have a regression (see 52 below) — iOS `allSubscriptions()` returned only the legacy `device-snapshot-changes` sub, the two new quota subs did not persist.**

### Added (attempted — regressed)
- **Locale-aware Mac→iOS push notifications.** Each iPhone was intended to render the quota push in its own locale (English / 简体中文 / 繁體中文 / 日本語) using the pre-translated `Push.QuotaDepleted.*` and `Push.QuotaRestored.*` keys in `Localizable.xcstrings`. Mac writes only the untranslated `providerName` field into the record; CloudKit was to substitute it into the title template at push time via `titleLocalizationArgs = ["providerName"]`, and iOS was to resolve the templates against its current locale.

### Changed
- **Quota transition state differentiation moved from predicate to zone.** Instead of a single zone-wide subscription with a static `alertBody = "Session quota changed"`, iOS now carries two `CKRecordZoneSubscription`s — one on the new `QuotaDepletedZone` and one on `QuotaRestoredZone` — each with its own localization key. The split lets each subscription own a static `titleLocalizationKey` / `alertLocalizationKey` while staying on the persisting subscription type (`CKRecordZoneSubscription` — `CKQuerySubscription` is still silently non-persisting on this container).
- `CloudSyncManager.writeQuotaTransition` picks the destination zone from the transition state and drops `notificationTitle` / `notificationBody` parameters (no longer needed). `recordName` is now `(providerID, hourBucket)` — state is implicit in the zone.
- The Build 42–49 legacy subscription `quota-transition-zone-sub` is explicitly deleted on upgrade. The legacy `QuotaTransitionsZone` is left in place (no harm: Mac no longer writes to it).

### Notes
- **No CloudKit Dashboard schema deploy is required for this change.** Zones are created on-demand, and the only field referenced by subscription args (`providerName`) has been in the Production schema since Build 48. This avoids the Build 49 (`65960ac8`) failure mode where args referencing undeployed fields caused subscriptions to silently not persist.
- Covers the v4 push notification iteration through Builds 43–49 (subscription type, DB, zone, localization). See `Research/004-alert-push-cloudkit.md`.

## [1.2.0 (42)] — 2026-04-08

### Added
- **Mac→iOS push notifications, v2 (CloudKit alert push design).** When a session quota becomes depleted or restored on the Mac, iPhone receives a visible push notification ("Codex" / "Session quota depleted") delivered directly by APNs without the iOS app needing to wake up. **Background App Refresh is no longer required.** See `Research/004-alert-push-cloudkit.md` for the full design rationale.
  - Mac side: when a transition is detected, write a small `QuotaTransition` record to CloudKit (provider name + state + timestamp + deviceID), debounced 5 minutes per (provider, state).
  - iOS side: two `CKQuerySubscription`s on `QuotaTransition` (one filtered by `state == "depleted"`, one by `state == "restored"`), each with a `notificationInfo.titleLocalizationKey` + `titleLocalizationArgs = ["providerName"]` that lets CloudKit fill in the provider name from the record at push time.
  - Localized in 4 languages (en / ja / zh-Hans / zh-Hant).
- **Independent Mac and iOS notification toggles.** Mac local notifications (Settings → General) and iOS push notifications (Mac Settings → Mobile → "Push notifications to iOS") are now decoupled. You can keep Mac silent and still get alerts on your iPhone, or vice versa, or both, or neither.
- **Mac DEV "iOS Push Test" buttons** (Settings → Mobile, debug build only) — writes a real `QuotaTransition` record so the full pipeline can be exercised end-to-end without waiting for an actual quota change.

### Changed
- `UsageStore.handleSessionQuotaTransition` refactored: transition computation moved before the `sessionQuotaNotificationsEnabled` gate, so the Mac local notification path and iOS push path can be controlled independently. Existing Mac local notification behaviour (gated by `sessionQuotaNotificationsEnabled`) is preserved unchanged.

### Notes
- Compared to the v1 silent-push design (rolled back in build 41): no Background App Refresh dependency, no UN authorization required for the silent-push path, no iOS app wake-up needed, no client-side baseline tracking, no diagnostic infrastructure. Net deletion of ~700 lines from build 40 → 41 → 42.

## [1.2.0 (41)] — 2026-04-08

### Removed
- **Mac→iOS push notification feature, in its entirety.** The CloudKit silent push (`shouldSendContentAvailable=true`) architecture is dropped because it requires Background App Refresh to be enabled on the device — and even then is silently throttled by iOS in many real-world conditions. The feature will return in a future release built on a different architecture (alert push triggered by a small server-decided record, no client-side wake-up needed).
- `AppDelegate.swift` (remote notification handler), `SessionQuotaMonitor.swift` (transition detection), `LocalNotificationManager.swift` (local notification posting), `PushDiagnosticStore.swift` (debug store)
- iOS Push Diagnostic developer tool and its navigation entry under Developer Tools
- iOS "Session quota notifications" toggle in Usage Setting
- iOS `aps-environment` entitlement and `UIBackgroundModes` from `Info.plist`
- Mac `MacPushDiagnostics.swift` (Mac-side debug pane) and the entire DEV "iOS Push Testing" section in `PreferencesMobilePane`
- Mac "Push notifications to iOS" toggle and `notificationPushToiOSEnabled` setting
- `SyncCoordinator.pushTestSnapshot` and the test-lock plumbing
- `CloudSyncManager.setupSubscription` and `subscriptionID` constant

### Notes
- iCloud data sync (Mac→iOS usage data display) is unaffected — that path still uses `pushSnapshot` / `fetchAllDeviceSnapshots` on the existing custom zone.
- The `DeviceSnapshotsZone` custom record zone is intentionally kept (rather than reverting to `_defaultZone`) so the future Plan B work can reuse it without another data migration.

## [1.2.0 (40)] — 2026-04-08

### Added
- **`UIBackgroundModes: fetch`** in Info.plist alongside the existing `remote-notification`. Apple's `CKQuerySubscription` documentation explicitly requires both Background Modes to be enabled for silent push notifications to wake the app. The previous build was missing `fetch`.
- **Runtime Environment** section in Push Diagnostic showing the values that actually shipped in the signed binary, not what the source files claim:
  - `aps-environment` read from `SecTaskCopyValueForEntitlement` — proves whether the device registered with Sandbox or Production APNs
  - `icloud-container-environment` — must match Mac side
  - `Background App Refresh` status — required for silent push delivery
  - `Low Power Mode` — iOS throttles silent push when on
  Mismatches are highlighted in orange so the user can spot them at a glance.

## [1.2.0 (39)] — 2026-04-08

### Fixed
- **CloudKit silent push delivery (root-cause fix)** — `DeviceSnapshot` records now live in a custom record zone (`DeviceSnapshotsZone`) instead of `_defaultZone`, and iOS subscribes via `CKRecordZoneSubscription` instead of `CKQuerySubscription`. The previous architecture was the documented dead-end for private-database silent push: query subscriptions on the default zone do not deliver pushes reliably (Apple's official `apple/sample-cloudkit-privatedb-sync` uses the same custom-zone + zone-subscription pattern). On first launch the iOS app self-heals: it queries the server for the existing subscription, deletes the legacy `CKQuerySubscription` if found, and creates a fresh `CKRecordZoneSubscription` bound to the current APNs device token.

### Changed
- `CloudSyncManager.fetchAllDeviceSnapshots()` now reads from BOTH the custom zone (where build 39+ Macs write) and the default zone (where pre-39 Macs may still be writing). Snapshots are deduped by `deviceID` keeping the most recent `syncTimestamp` per device, so the iOS app stays correct during the cross-device migration window.
- `CloudSyncManager.ensureCustomZoneExists()` and `setupSubscription(forceRecreate:)` use a fetch-first self-healing pattern: every call queries the server's actual state instead of trusting a local UserDefaults flag. This is robust to iCloud account switches, manual server-side resets, and external dashboard deletions.
- Push Diagnostic "Re-create CKSubscription" button now passes `forceRecreate: true`, bypassing the no-op fast path so the user can manually refresh the device-token binding after a TestFlight reinstall.

## [1.2.0 (38)] — 2026-04-06

Marketing version bump that rolls up all the utilization, multi-device sync, and Settings reorganization work since 1.1.0.

### Added
- **Subscription Utilization section in the Cost tab** — 30-day daily bar chart aligned with the cost chart, four period summary cards (Today / This Week / 14 Days / 30 Days) each with delta vs the previous period, and an inline Provider Share breakdown that shows each provider's proportional share of total utilization (sums to 100%).
- **Subscription Utilization History chart on each provider detail page** — scrollable per-period bars (V4 Capsule style) covering session, weekly, and opus limits.
- **Push Diagnostic developer tool** — Settings → Developer Tools → Push Diagnostic. Surfaces APNS registration, CKSubscription state, UN authorization, last silent push, fetch/transition/notification results, and a 100-entry rolling event log. Manual actions: Fetch Now, Re-create CKSubscription, Post Test Local Notification, Clear Log.
- **Multi-device utilization merge** — utilization entries from all Macs are combined and deduped by `(hourSlot, resetEpoch)` so the chart stays consistent no matter how many devices report.
- Setup Guide promoted to a top-level Settings row (above About & Sync); tapping opens the existing onboarding sheet.

### Changed
- Provider breakdown in the Cost tab now shows proportional share (summing to 100%) instead of raw average percentages, matching the visual style of the cost Provider Share section.
- Subscription Utilization section title uses `.headline` to match every other Cost-tab section header.
- Developer Tools consolidated under a single Settings entry that navigates into a dedicated container page listing Raw Sync Data and Push Diagnostic.
- About page build timestamp is forced to `en_US` locale regardless of system language (app is English).

### Removed
- "How It Works" section from Settings (previously listed 3 informational items plus a Show Setup Guide button) — redundant with the promoted Setup Guide entry.
- "How It Works" subsection inside About & Sync detail — duplicated the same info.
- Dead localization keys for the removed strings.

### Fixed
- CloudKit utilization merge now picks the entry with the freshest `capturedAt` per hour bucket instead of the one with more entries — prevents stale data from an inactive Mac from overwriting fresh data from an active one.

## [1.1.0 (37)] — 2026-04-06

### Changed
- **Promoted Setup Guide to a top-level Settings row.** It now sits at the very top of the first section (above About & Sync), opens the existing Setup Guide sheet on tap, and uses the `sparkles` icon.

### Removed
- The standalone "How It Works" section in Settings (previously listed 3 informational items plus a Show Setup Guide button). Now redundant with the promoted Setup Guide entry.
- The "How It Works" section inside About & Sync detail — duplicated the same information.
- Dead localization keys: `How It Works`, `Show Setup Guide`, `CodexBar on your Mac pushes usage data to iCloud`, `Data syncs automatically when both devices are online`, `This app reads the latest snapshot via iCloud Key-Value Store`.

## [1.1.0 (36)] — 2026-04-06

### Changed
- **Consolidated dev tools under a single "Developer Tools" entry** — Settings → Developer now shows one row that navigates into a dedicated page listing Raw Sync Data and Push Diagnostic. Future tools can be added there without cluttering the main Settings list.

## [1.1.0 (35)] — 2026-04-06

### Changed
- Renamed the Settings → Developer section to **Developer Tools**, now housing both "Raw Sync Data" and "Push Diagnostic". These screens are intentionally shipped to production builds so end users can self-diagnose sync/push issues (no sensitive data exposed).

## [1.1.0 (34)] — 2026-04-06

### Added
- **Push Diagnostic** developer view (Settings → Developer → Push Diagnostic) that surfaces every step of the Mac→iOS push notification chain in-app: APNS registration, CKSubscription status, UN authorization, last silent push received, last fetch result, last transitions, last local notification post, and a rolling event log
- `PushDiagnosticStore` — observable store tracking registration/subscription/push/fetch/transition/notification state with a 100-entry event log
- Manual diagnostic actions: "Fetch Now", "Re-create CKSubscription", "Post Test Local Notification", "Clear Event Log"
- `CloudSyncReader.setupSubscriptionWithDiagnostics()` wrapper that captures any error thrown from the shared `CloudSyncManager.setupSubscription()` instead of letting it be swallowed by `try?`
- `LocalNotificationManager.postDiagnosticTestNotification()` for verifying the UN pipeline end-to-end from the Diagnostic view

### Changed
- `AppDelegate` now reports every remote-notification lifecycle event (registration success/failure, push received, fetch result, transitions, notification post) into `PushDiagnosticStore` so the diagnostic view updates live
- `LocalNotificationManager.postSessionQuotaNotification` now returns `Bool` so the caller can record success/failure in diagnostics

## [1.1.0 (33)] — 2026-04-06

### Changed
- Subscription Utilization section title now uses `.headline` (was `.title3.bold()`), matching every other section header in the Cost tab
- Provider share rows are now merged directly into the Subscription Utilization section — the previous "Provider Share" sub-header (title + caption) is gone, and the cards sit under the daily chart as part of the same section
- Section subtitle updated to describe the whole section ("Session quota usage trend across synced providers.")

## [1.1.0 (32)] — 2026-04-06

### Removed
- Release notes items mistakenly appended to the 1.1.0 in-app catalog (`MobileReleaseNotesCatalog`) in build 31. The in-app catalog is reserved for major version updates and should not be touched on minor build bumps.

## [1.1.0 (31)] — 2026-04-06

### Changed
- **Subscription Utilization chart redesigned with daily granularity** — bars are now per-calendar-day (matching the Cost chart's 30-day window) instead of per-week
- **Four period summary cards** — Today, This Week, 14 Days, 30 Days, each with delta vs previous period (orange ↑ / green ↓)
- **Provider Share breakdown** — replaces raw average % with proportional share% (sums to 100% across providers), styled to match the Cost tab's Provider Share section
- 30-day raw average shown as subtitle context for each provider in the share breakdown

### Added
- 4-language localization for new strings: `14 Days`, `This Week`, and `30-day utilization share across synced providers.`

## [1.1.0 (25)] — 2026-04-01

### Added
- **Session quota push notifications** — iOS receives silent push from CloudKit when Mac detects quota changes, posts local notification for depleted/restored events
- `AppDelegate` with remote notification handler for CloudKit silent push processing
- `SessionQuotaMonitor` for detecting quota state transitions (depleted ≤0.01% / restored)
- `LocalNotificationManager` for posting user-visible notifications with sound
- Notification toggle in Settings → Usage → Notifications section (enabled by default)
- 4-language localization for all notification strings

### Changed
- App architecture upgraded: added `UIApplicationDelegateAdaptor` for background notification handling

## [1.0.0 (23)] — 2026-03-23

### Changed
- **iCloud sync upgraded from KVS to CloudKit** — each Mac now writes its own device record; iPhone merges all devices
- Multi-Mac support: providers from different Macs are combined on iPhone instead of last-write-wins
- Cost data from local-source providers (Claude, Codex, VertexAI) is summed across devices; account-level providers deduplicate
- Sync status now shows specific CloudKit errors (network, auth, quota) instead of generic "synced/not synced"
- Mac side generates a stable device UUID (persisted in UserDefaults) for CloudKit record identity
- KVS dual-write maintained for backward compatibility with older iOS builds

### Added
- `CloudSyncError` enum with CKError-to-user-readable mapping
- `MultiDeviceSyncResult` for multi-device CloudKit fetch results
- `SyncStatus` enum (`.synced` / `.syncing` / `.error` / `.noData` / `.incompatibleData`)
- `deviceID` field on `SyncedUsageSnapshot` for per-device CloudKit records
- CKQuerySubscription setup for silent push notifications on record changes
- Multi-device merge logic with per-provider cost aggregation strategy
- CloudKit + background remote notification entitlements (iOS + Mac)
- 13 new tests: multi-device merge (9), sync error mapping (14 total in suite)

## [1.0.0 (22)] — 2026-03-21

### Added
- App Store screenshot source assets under `AppStoreScreenshots/v0` and `AppStoreScreenshots/v1-screenshot`
- Finalized Chinese App Store screenshots under `AppStoreScreenshots/v1-styled`
- Matching English App Store screenshots under `AppStoreScreenshots/v1-styled-en`
- Reusable screenshot generation script for localized marketing images

## [1.0.0 (21)] — 2026-03-20

### Added
- Vibe (cyberpunk) share card style with arc gauges, neon glow, and "Did you vibe today?" headlines
- Style picker in share sheet: Classic / Vibe
- Dark and light theme support for both Classic and Vibe styles
- Save to Photos option in share sheet (NSPhotoLibraryAddUsageDescription)
- QR code and link updated to codexbarios.o1xhack.com

### Changed
- Share card headlines forced to single line across all 4 languages (minimumScaleFactor)
- In-app release notes now merge updates within the same marketing version
- AGENTS.md Step 5 updated with release notes merge rule

### Fixed
- Share sheet not showing "Save Image" option due to ShareLink Transferable limitation

## [1.0.0 (15)] — 2026-03-20

### Added
- One-tap share button on Cost tab to generate shareable cost report images
- Share sheet with period picker (Today / 7 Days / 30 Days) and live card preview
- Three share card styles: today (provider breakdown), 7-day and 30-day (stacked bar chart)
- Stacked bar chart colored by provider (top 3 + "Others" for 4+ providers)
- QR code footer linking to CodexBar project
- Feature research framework under Research/ with status tracking (draft → done → dropped)
- Research doc 001: Daily Utilization Chart (blocked-upstream, PR #565)
- Research doc 002: Cost Share Card (done)

### Changed
- CLAUDE.md simplified to project overview; AGENTS.md now holds complete 7-step workflow
- Share card charts follow dataviz conventions (largest segment at bottom for stable baseline)

## [1.0.0 (13)] — 2026-03-19

### Changed
- Refined in-app release note: replaced screenshot coverage note with clearer label readability improvement

## [1.0.0 (12)] — 2026-03-19

### Fixed
- In-app release notes now preserve the original 1.0.0 launch notes while prepending the latest build updates

## [1.0.0 (11)] — 2026-03-19

### Changed
- Usage percentage labels now keep a larger, fixed layout instead of scaling down under pressure
- Cost overview cards and trailing metrics in Cost lists now use adaptive fixed-width layouts for crisper numbers

### Fixed
- Blurry `% used` and `% left` labels on provider usage cards
- Soft or blurry trailing amount/share text in Provider Share and Model Mix rows

## [1.0.0 (10)] — 2026-03-18

### Changed
- Daily spend chart now scrolls horizontally, showing 30 days at a time with swipe for history
- Consolidated release notes into "What's New" and "Improvements & Fixes" sections
- Updated CLAUDE.md with jj workflow and commit automation rules
- Enriched demo data to 50 days with realistic spend curves

## [1.0.0 (9)] — 2026-03-17

Initial App Store release line, corresponding to the earlier Mobile `0.1.0` build.

### Added
- iOS companion app for CodexBar with iCloud Key-Value Store sync
- Provider list with dynamic rate limit progress bars and labels (Session, Weekly, Sonnet, etc.)
- Tappable provider cards with cost teaser line ("Today: $X.XX · 30d: $Y.YY")
- Provider detail view with interactive daily spend bar chart (SwiftUI Charts)
- Cost summary grid (session cost, 30-day cost, token counts)
- Budget progress bar with color-coded thresholds (red >90%, orange >70%)
- "Show remaining usage" toggle in Settings to display quota left instead of quota used
- iCloud sync error display (quota exceeded, account change notifications)
- iOS 26 Liquid Glass UI support (glass effect cards, soft scroll edges, tab bar minimize)
- Demo mode for previewing the app without Mac data
- About tab with sync status, developer info, and open source credits
- Display Mac app version and Sync version from iCloud payload in About tab
- Empty state views for waiting-for-sync and no-providers states
- Cost tab with provider share, model/service mix, and 30-day spend analysis
- In-app release notes page with the latest update summary and collapsible version history
- Privacy manifest, privacy policy, and dark mode app icon
- Onboarding flow, setup guide, and pull-to-refresh support
- Native localization for English, Simplified Chinese, Traditional Chinese, and Japanese

### Changed
- Usage and Cost charts support both Bar Chart and Line Chart styles
- 30-day charts support press-and-hold inspection for exact daily values
- Daily spend chart now scrolls horizontally, showing 30 days at a time with swipe to view history
- Chart Y-axis uses smart integer tick marks for cleaner readability
- Setting tab reorganized into Usage, Charts, and Privacy sections
- Mobile versioning is now aligned directly with the iOS app version number
- Dynamic version display now surfaces synced iPhone and Mac versions more clearly

### Fixed
- Pull to refresh now asks iCloud Key-Value Store to synchronize before reading the latest snapshot
- Mac sync status now reports missing iCloud entitlements or unavailable iCloud accounts instead of showing a false success state
- Fix iCloud sync entitlement check on iOS
