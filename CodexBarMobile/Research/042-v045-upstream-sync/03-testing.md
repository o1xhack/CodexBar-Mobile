# v0.45.2 Upstream Sync Test Evidence

Status: `in-progress`
Date: 2026-07-19

## Environment

- Old Mac: published fork `0.41.0.1 (100.1.1.18.0)`
- New Mac: candidate `0.45.2.1 (109.1.1.19.0)`
- Old iPhone: iOS `1.18.0 (187)`
- New iPhone: candidate iOS `1.19.0 (188)`
- Branch base: `6e4d605f`
- Upstream target: `v0.45.2`, peeled commit `91560ca9`

## Command Evidence

Results are added as each gate runs. Commands that can prompt for Keychain or
touch real provider sessions are excluded unless separately authorized.

## 2 Mac x 2 iPhone Compatibility Matrix

Every row is required because provider identity, display data, rate windows,
multi-account merge, caches and legacy-provider behavior change. `pending`
must be replaced by pass/fail/substituted before closeout.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | pending | — | Baseline control |
| 2 | old | old | old | new | pending | — | New reader, legacy writers |
| 3 | old | old | new | old | pending | — | Independent new-reader cache |
| 4 | old | old | new | new | pending | — | Both new readers, legacy writers |
| 5 | old | new | old | old | pending | — | New provider writer with old readers |
| 6 | old | new | old | new | pending | — | Mixed writer and reader versions |
| 7 | old | new | new | old | pending | — | Mirrored mixed reader order |
| 8 | old | new | new | new | pending | — | Mixed writers, both new readers |
| 9 | new | old | old | old | pending | — | Writer identity order reversed |
| 10 | new | old | old | new | pending | — | Reversed mixed writer/reader order |
| 11 | new | old | new | old | pending | — | Reversed independent reader cache |
| 12 | new | old | new | new | pending | — | Reversed writers, both new readers |
| 13 | new | new | old | old | pending | — | Old readers tolerate new payloads |
| 14 | new | new | old | new | pending | — | Mixed reader convergence |
| 15 | new | new | new | old | pending | — | Mixed reader convergence reversed |
| 16 | new | new | new | new | pending | — | Full candidate environment |

Required observations per row: both writers retain distinct device/account
ownership; old/new readers decode without crash or loss; provider rows and
quota lanes do not duplicate or disappear; both phones converge; retired
provider records remain readable during rollout; stale/ghost records do not
reappear; and balances/costs do not become impossible values.

## CloudKit Production Audit

Pending post-implementation diff audit. Preliminary verdict: no deploy
expected because upstream changes no fork `Shared/` schema and planned provider
coverage stays inside existing opaque payload fields.

## Residual Risk

Pending real-device availability and completed matrix evidence.
