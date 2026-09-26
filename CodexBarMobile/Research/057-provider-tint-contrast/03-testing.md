# PR #140 provider tint contrast — test evidence

Status: local validation complete; PR review pending. Date: 2026-09-25.

## Scope and results

- Mac baseline: published `0.66.0.1`, build `156.1`; Mac code, payload, CloudKit
  schema, and serialization are unchanged. In the matrix, `old` and `new` Mac
  are therefore the same published binary, not two new writer implementations.
- iPhone `old` is iOS `2.1.0 (212)` and `new` is `2.1.0 (213)` from this PR.
- Signed iOS simulator unit suite: **807 passed, 0 failed, 0 skipped** in
  `BuildScratch/CodexBar/pr140/FullUnitTests2.xcresult`.
- Signed Debug simulator build passed. Focused palette tests passed 59/59 before
  the additional older-snapshot case; the final full run includes that case.
- A real Usage card with synthetic Grok `#000000` tint was visually checked in
  dark and light appearance: `BuildScratch/CodexBar/pr140/grok-dark.png` and
  `grok-light.png`. The 22% label and progress bar remained visible in both.
- `Scripts/lint.sh audit-i18n` passed with all four translations present.
- An unsigned simulator launch failed at the app's CloudKit entitlement gate
  before tests ran; the signed rerun passed. This is not counted as a product
  test failure.

## 2 Mac × 2 iPhone old/new compatibility matrix

All rows are **substituted**, because two physical Macs and two physical
iPhones on one Production CloudKit account were not available for this PR.
The substituted path for every row is the unchanged Mac/wire/schema code audit,
synthetic old/no-tint and custom-tint snapshots in unit tests, the signed
simulator full suite, and the dark/light rendered card. `S` means this shared
substituted evidence. It checks the new renderer, but does not prove live
CloudKit delivery, two-writer convergence, per-device caches, or silent push.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | S | Prior released behavior; no four-device live replay. |
| 2 | old | old | old | new | substituted | S | New reader tested with old/no-tint snapshot. |
| 3 | old | old | new | old | substituted | S | New reader tested with old/no-tint snapshot. |
| 4 | old | old | new | new | substituted | S | Both new readers are represented by the same simulator tests. |
| 5 | old | new | old | old | substituted | S | Mac binary unchanged; two-writer delivery unmeasured. |
| 6 | old | new | old | new | substituted | S | New reader tested; two-writer delivery unmeasured. |
| 7 | old | new | new | old | substituted | S | New reader tested; two-writer delivery unmeasured. |
| 8 | old | new | new | new | substituted | S | New renderer tested; two-reader convergence unmeasured. |
| 9 | new | old | old | old | substituted | S | Mac binary unchanged; two-writer delivery unmeasured. |
| 10 | new | old | old | new | substituted | S | New reader tested; two-writer delivery unmeasured. |
| 11 | new | old | new | old | substituted | S | New reader tested; two-writer delivery unmeasured. |
| 12 | new | old | new | new | substituted | S | New renderer tested; two-reader convergence unmeasured. |
| 13 | new | new | old | old | substituted | S | Mac binary unchanged; old-reader live state unmeasured. |
| 14 | new | new | old | new | substituted | S | New reader tested; two-reader convergence unmeasured. |
| 15 | new | new | new | old | substituted | S | New reader tested; two-reader convergence unmeasured. |
| 16 | new | new | new | new | substituted | S | New renderer tested; two-reader convergence unmeasured. |

## Residual risk and gate verdict

The change is limited to tint transformation after snapshots reach iOS. It
cannot alter CloudKit records, provider values, device identity, cache keys,
or merge order. The visible risk is material-backed card contrast varying
from the tested simulator background and uncommon custom colors retaining a
less recognizable brand hue after correction. Near-black, near-white, yellow,
invalid, and absent tints are covered by tests; Grok black is rendered in both
appearances. The compatibility documentation gate is complete with 16
substituted cases; physical multi-device convergence remains unverified and
must not be described as a real-device pass.
