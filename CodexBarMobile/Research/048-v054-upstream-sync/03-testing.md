# v0.54.0 Upstream Sync 测试证据

Status: `in-progress`
Date: 2026-08-21

## 版本与范围

- old Mac: published fork `0.52.0.1 (124.1.1.21.0)`；
- new Mac candidate: `0.54.0.1 (127.1.1.21.0)`；
- old iPhone: iOS `1.21.0 (194)`；
- new iPhone candidate: iOS `1.21.0 (195)`；
- payload/CloudKit baseline: `providerPayloadVersion=1`、Production container。

## Gates

| Gate | Result | Evidence / Notes |
|---|---|---|
| Merge provenance / conflict audit | pending | |
| Mac build + lint + full tests | pending | |
| Settings / CloudKit / cost / provider focused regression | pending | |
| Parser fingerprint/hash | pending | |
| iOS build + full tests | pending | |
| Widget/cost/provider display parity | pending | |
| Four-language localization | pending | |
| CloudKit Production schema audit | pending | expected `NO_DEPLOY`, must prove |
| Final review blockers | pending | target 0 blockers |

## Compatibility evidence keys

- S1: old/new Shared wire fixtures + Mac producers；
- S2: independent iOS merge/cache/widget readers；
- S3: all-new iOS full simulator tests；
- S4: lifecycle/producer/schema code audit；
- S5: Production schema readback。

## 2 Mac × 2 iPhone old/new compatibility matrix

本轮 cost/provider display、Mac sync behavior与cross-version rendering均可能变化，因此gate适用。
测试完成前不得把任何行标成pass。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | pending | | |
| 2 | old | old | old | new | pending | | |
| 3 | old | old | new | old | pending | | |
| 4 | old | old | new | new | pending | | |
| 5 | old | new | old | old | pending | | |
| 6 | old | new | old | new | pending | | |
| 7 | old | new | new | old | pending | | |
| 8 | old | new | new | new | pending | | |
| 9 | new | old | old | old | pending | | |
| 10 | new | old | old | new | pending | | |
| 11 | new | old | new | old | pending | | |
| 12 | new | old | new | new | pending | | |
| 13 | new | new | old | old | pending | | |
| 14 | new | new | old | new | pending | | |
| 15 | new | new | new | old | pending | | |
| 16 | new | new | new | new | pending | | |

无法提供2 Mac + 2 iPhone old/new实体组合时，必须记录substitution路径与silent push、真实Production
传播、background delivery、旧binary行为等剩余风险，不能伪装成real-device pass。
