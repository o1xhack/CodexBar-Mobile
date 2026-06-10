---
summary: "Canonical test gate for Mac-to-iOS iCloud sync compatibility across old/new app versions and multiple devices."
read_when:
  - Planning or testing a release that changes Mac-to-iOS sync
  - Updating Shared payloads, CloudKit schema, provider display data, cache behavior, or cross-version rendering
  - Filling out a release Research/03-testing.md matrix
---

# iOS Sync Compatibility Testing

This is the canonical compatibility gate for CodexBar's Mac-to-iOS iCloud sync.
Per-release `CodexBarMobile/Research/NNN-*/03-testing.md` files record the
actual evidence for one release; this document defines the reusable rule and
matrix.

## When This Gate Applies

Run this gate for any release that changes any of the following:

- Mac -> CloudKit -> iOS sync behavior
- Shared payload shape, encoding, decoding, or fallback behavior
- CloudKit schema, record types, zones, subscriptions, or query predicates
- provider display data that is synced from Mac and rendered on iOS
- local cache behavior on Mac or iOS
- cross-version rendering or migration behavior

If a release does not touch any of these areas, state why this gate is not
applicable in the release testing notes.

## Minimum Real-device Matrix

The minimum real-device environment is:

- 2 Macs
- 2 iPhones
- each device independently on old or new version

That yields `2^4 = 16` old/new combinations. Do not collapse this to a simple
Mac-version x iOS-version table when the change can depend on device identity,
per-device CloudKit records, merge order, local cache, silent push delivery, or
fallback state.

| Case | Mac A | Mac B | iPhone A | iPhone B |
|---:|---|---|---|---|
| 1 | old | old | old | old |
| 2 | old | old | old | new |
| 3 | old | old | new | old |
| 4 | old | old | new | new |
| 5 | old | new | old | old |
| 6 | old | new | old | new |
| 7 | old | new | new | old |
| 8 | old | new | new | new |
| 9 | new | old | old | old |
| 10 | new | old | old | new |
| 11 | new | old | new | old |
| 12 | new | old | new | new |
| 13 | new | new | old | old |
| 14 | new | new | old | new |
| 15 | new | new | new | old |
| 16 | new | new | new | new |

Mac A and Mac B are distinct writers with distinct device IDs. iPhone A and
iPhone B are distinct readers with independent local caches, subscription
delivery, and foreground/background state.

## What Each Combination Must Verify

For each applicable combination, verify:

- old and new Macs can write without corrupting each other's CloudKit records
- old and new iPhones can read, merge, fallback, cache, and render without
  crashes or data loss
- new Mac payloads and optional fields do not break old iOS clients
- new iOS clients can gracefully read old Mac payloads
- multi-Mac merge rules remain correct with both writers present
- both iPhones converge to the same visible state after CloudKit fetch or silent
  push
- stale or ghost records do not reappear after mixed-version writes
- user-visible provider cards do not show impossible values, duplicated rows, or
  missing account/device identity

## Evidence Format

Each release's `CodexBarMobile/Research/NNN-*/03-testing.md` should include a
matrix table with one row per case:

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | pass / fail / substituted / not applicable | command, screenshot, log, or manual QA note | risk or follow-up |

Use `substituted` only when real hardware is unavailable or the combination is
not practically reproducible. In that case, document:

- why real-device coverage was unavailable
- the substituted validation path, such as unit tests, mock CloudKit records,
  simulator runs, or code audit
- remaining user-visible risk

## Release Gate

This gate is complete only when:

- all 16 combinations are listed in the release testing document
- every applicable combination has a pass/fail/substituted result
- failures are fixed and rerun, or explicitly called out as release blockers
- substituted combinations include clear residual risk
- the final release summary states whether this gate passed
