# v0.52.0 Upstream Sync 测试证据

Status: `in-progress`
Date: 2026-08-17

## 版本与范围

- old Mac: published fork `0.49.2.1 (116.1.1.21.0)`；
- new Mac candidate: `0.52.0.1 (124.1.1.21.0)`；
- old iPhone: iOS `1.21.0 (193)`；
- new iPhone candidate: iOS `1.21.0 (194)`；
- payload/CloudKit baseline: `providerPayloadVersion=1`、Production container。

## 计划 gates

| Gate | 结果 | Evidence / Notes |
|---|---|---|
| Merge provenance / fork conflict audit | pending | `v0.52.0` merge parent、14 conflict paths/types |
| Mac build + lint + full tests | pending | — |
| Provider/cost/keychain/PTY/settings/sync focused regression | pending | — |
| Parser fingerprint/hash | pending | — |
| Packaged signed/notarized candidate | pending | — |
| codesign / spctl / CLI / launch smoke | pending | — |
| iOS build + full tests | pending | — |
| Widget/cost/provider display parity | pending | — |
| Four-language localization | pending | — |
| CloudKit Production schema audit | pending | expected `NO_DEPLOY` |
| Draft release asset/readback | pending | no live publish/tag/appcast |
| Final review blockers | pending | target 0 |

## 2 Mac × 2 iPhone old/new compatibility matrix

本轮 provider display data、Mac fleet sync optional fields、widget/cache projection与跨版本
rendering有变化，因此 gate适用。每一行后续必须填 pass/fail/substituted及实际 evidence。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | pending | — | published baseline control |
| 2 | old | old | old | new | pending | — | new reader / old writers |
| 3 | old | old | new | old | pending | — | independent iPhone caches |
| 4 | old | old | new | new | pending | — | new readers / old writers |
| 5 | old | new | old | old | pending | — | mixed writers / old readers |
| 6 | old | new | old | new | pending | — | mixed all roles |
| 7 | old | new | new | old | pending | — | mixed all roles reversed readers |
| 8 | old | new | new | new | pending | — | mixed writers / new readers |
| 9 | new | old | old | old | pending | — | writer order reversed |
| 10 | new | old | old | new | pending | — | writer/reader asymmetry |
| 11 | new | old | new | old | pending | — | writer/reader asymmetry reversed |
| 12 | new | old | new | new | pending | — | mixed writers / new readers |
| 13 | new | new | old | old | pending | — | new payload / old readers |
| 14 | new | new | old | new | pending | — | independent reader versions |
| 15 | new | new | new | old | pending | — | independent reader versions reversed |
| 16 | new | new | new | new | pending | — | all-new convergence |

## 每个 case 的验收语义

- old/new writers不破坏 device + provider + account identity与delete/ghost规则；
- old iPhone忽略新 optional内容且不crash，新 iPhone安全读取old payload；
- Claude scoped rows、Cursor/Vertex/OpenCode/Grok/Antigravity semantics不重复、不误标、不丢卡；
- 两个 iPhone在fetch/silent push/cache fallback后收敛；
- accent color/workday tick只留在Mac fleet sync，不进入Mobile payload；
- project path、conversation/session identity、credential/plugin secret不进入CloudKit Mobile records。

## substituted evidence 要求

若本机没有2 Mac + 2 iPhone可反复安装old/new binaries，不能把矩阵写成实机pass。必须记录：

1. 缺少的真实硬件/old binary组合；
2. 对应 old/new Codable fixture、dual-writer reducer、cache/delete/ghost、CloudKit mock、
   simulator或代码审计路径；
3. silent push、真实Production传播、background delivery与旧binary行为的剩余用户风险。

