# Usage & Spend: native settings interaction proof

All account names, dates, monetary amounts and token counts in this folder are deterministic **synthetic fixtures**. No real account, credential, session, project, home path or spending history is published. Original captures and the complete accessibility transcript are retained locally. This public derivative omits unrelated accessibility rows; the screenshots retain the original captured bytes.

## Built application and production route

The freshly built CodexBar executable opens the production `SettingsWindowController`, including the complete `PreferencesView` sidebar. Native clicks enter **Usage & Spend** and exercise `SpendDashboardPane` → `UsageStore.sharedSpendDashboardController()` → `SpendDashboardTrendPanel`.

The docs-only launcher injects a synthetic shared controller through the existing storage seam. A temporary DEBUG entry guard bypasses ordinary menu-bar/provider startup. Settings use dictionary-backed defaults and a contained config; credential/session isolation and disabled discovery prevent real account access. Normal provider fetching and menu-bar initialization are outside this proof. This is not the earlier standalone chart wrapper.

[Build receipt](build-receipt.json) records the executable, fixture and production-source hashes. [Verification](verification.json) checks those source hashes, the observed transitions and screenshot byte identity. The receipt's base commit precedes the fix/evidence commit; its source hashes identify the compiled working-tree changes precisely.

## Observed native interactions

The [runtime transcript](interaction-transcript.json) contains actual accessibility observations after each native interaction, with the corresponding screenshots.

| Action | Observed result | Capture |
| --- | --- | --- |
| Open settings | General pane and complete sidebar | [01](screenshots/01-settings-entry.jpg) |
| Click Usage & Spend | Production pane and 90-day selection | [02](screenshots/02-usage-spend-entry.jpg) |
| Scroll to chart | Weekly overview and persistent amount inspector | [03](screenshots/03-weekly-overview.jpg) |
| Click Demo Codex A | Selected legend; only that account remains in the chart | [04](screenshots/04-account-isolated.jpg) |
| Click the selected account again | Four sources and original recorded amounts restored | [05](screenshots/05-filter-reset.jpg) |
| Show weekly details | Sep 27–Oct 3 scope and seven daily bars | [06](screenshots/06-week-to-days.jpg) |
| Open the selected day's hours | Sep 30, five recorded hours, two account amounts | [07](screenshots/07-day-to-hours.jpg) |
| Previous day | Sep 29 and its different recorded hourly amounts | [08](screenshots/08-previous-day.jpg) |
| Next day | Sep 30 and its original amounts restored | [09](screenshots/09-next-day.jpg) |
| Select Oct 5 from the date menu | Latest recorded day; Next day is disabled | [10](screenshots/10-date-menu-selected.jpg) |
| Open/dismiss hourly inspection menu | Focused date and exact amounts persist | Transcript step 11 |

Hour ticks use `00:00` through `24:00` in every language. The hourly view shows its reporting UTC offset, and the amount inspector includes the offset for each hour so repeated daylight-saving hours remain distinct. Dates and surrounding UI retain their selected-language formatting. Provider icons share a 20-point slot, with transparent brand artwork padding compensated; different Codex accounts retain distinct source colors.

## Reproduce

From a macOS checkout with its normal build dependencies:

```sh
python3 docs/proof/spend-chart-readability/build-app-proof.py .
.build/spend-dashboard-app-proof/SpendDashboardAppProof.app/Contents/MacOS/SpendDashboardAppProof --spend-dashboard-app-proof
```

The build script restores `CodexbarApp.swift` and removes the temporary helper in `finally`. The launcher belongs only to this documentation directory and is not compiled into normal app builds. Use the sidebar and controls in the table to reproduce the transitions.

Published JPEG metadata contains only image dimensions/color-space data; no location, device identity, author or free-text metadata is present. The machine paths from build logs and capture locations are withheld.
