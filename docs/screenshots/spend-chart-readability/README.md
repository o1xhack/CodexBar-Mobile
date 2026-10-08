---
summary: "Synthetic production-view screenshots for the spend trend readability changes."
read_when:
  - Reviewing spend trend layout and provider icon sizing
---

# Spend trend screenshots

These images render the production SwiftUI/Charts views using deterministic synthetic histories
from `SpendTrendChartRenderTests`. All dates, account labels and monetary amounts are fixture data.
No real account history, credentials, sessions, personal identifiers or user-supplied screenshots
are included.

- `weekly-dark.png`: four-month history grouped by week, persistent amount inspection and distinct
  colors for two Codex accounts; official product marks retain their original colors.
- `hourly-light.png`: one day of recorded hourly spend with 24-hour clock ticks, a visible UTC offset,
  date navigation and per-account amounts.
- `component-icons.png`: consistent icon sizing in the chart, inspector and provider/account rows.
- `hourly-english.png`: the same clock notation with English dates and UI.
- `hourly-german-narrow.png`: German dates and UI in a narrow dark layout, including both day-boundary ticks.

Images were regenerated against the merged upstream artwork on 2026-10-07 and are unmodified output
from the offline render test. The test requires credential/session
isolation and only writes screenshots when `CODEXBAR_SPEND_TREND_PROOF_DIR` is explicitly set.
Provider icon slots are 20 points throughout Usage & Spend, with brand artwork padding compensated;
account swatches are 8 points.
