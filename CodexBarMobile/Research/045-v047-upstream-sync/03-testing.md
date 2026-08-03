# v0.47.0 Upstream Sync 测试证据

Status: `ready`
Date: 2026-08-03

## 环境定义

- Old Mac: published fork `0.45.2.2 (109.2.1.19.0)`
- New Mac: candidate `0.47.0.1 (111.1.1.20.0)`
- Old iPhone: current `1.19.1 (191)`
- New iPhone: candidate `1.20.0 (192)`
- Branch base: `9d9db632`
- Upstream target: annotated tag `v0.47.0`, peeled commit `6a16c233`

会触发 Keychain prompt、读取真实 browser session、访问 live provider 或写 CloudKit
Production 的命令不在未单独授权的自动测试中运行。

## Command evidence

| Gate | Command / evidence | Result |
|---|---|---|
| Branch preflight | `git status` / HEAD 与 `origin/mobile-dev` 比较 | pass；clean base `9d9db632` |
| Upstream provenance | tag type/object/peeled commit、ancestry、commit/file counts | pass；待 merge 后记录 second parent |
| Merge build | `swift build` | pending |
| Portable/release lint | `bash Scripts/lint.sh lint` | pending |
| CI policy | `bash Scripts/check_ci_policy.sh` | pending |
| Mac full tests | `swift test --no-parallel` | pending |
| Multi-account/device | filtered Swift tests | pending |
| Fleet CloudSync | engine/models/settings/persistence tests | pending |
| Shared/four-provider wire | focused mapper + round-trip tests | pending |
| iOS unit gate | `xcodebuild ... -only-testing:CodexBarMobileTests test` | pending |
| Widget data parity | `WidgetSnapshotBuilderTests` | pending |
| iOS Release build | generic simulator Release, no signing | pending |
| Signing/notarization | candidate app/ZIP/dSYM | pending |
| CloudKit audit | last published tag → HEAD schema diff | preliminary `DEPLOY_REQUIRED`; final pending |
| Review | merge / Shared+iOS / release rounds | pending |

## 2 Mac × 2 iPhone compatibility matrix

本轮同时改变 Mac→CloudKit→iOS provider data、Shared payload、cache/render 与新增 Mac
fleet CloudKit record family，所以 16 组合全部适用。真实硬件不可用时只能标记
`substituted`，不能写成 physical-device pass。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | pending | — | all-old control |
| 2 | old | old | old | new | pending | — | new reader, legacy writers |
| 3 | old | old | new | old | pending | — | independent new-reader cache |
| 4 | old | old | new | new | pending | — | both new readers, legacy writers |
| 5 | old | new | old | old | pending | — | new provider writer to old readers |
| 6 | old | new | old | new | pending | — | mixed writers/readers |
| 7 | old | new | new | old | pending | — | mirrored reader order |
| 8 | old | new | new | new | pending | — | mixed writers, new readers |
| 9 | new | old | old | old | pending | — | reversed writer order |
| 10 | new | old | old | new | pending | — | reversed mixed order |
| 11 | new | old | new | old | pending | — | independent caches |
| 12 | new | old | new | new | pending | — | reversed writers, new readers |
| 13 | new | new | old | old | pending | — | all new writers to old readers |
| 14 | new | new | old | new | pending | — | one old reader |
| 15 | new | new | new | old | pending | — | mirrored one-old-reader case |
| 16 | new | new | new | new | pending | — | full candidate environment |

每行必须验证：两个 writer 的 device/account identity 不互相覆盖；old/new payload decode
不 crash；新 reader 保留四个新 provider、Claude balance、ZoomMate/xAI money/history、
Notion workspace 与 z.ai hourly/7d/30d；
旧 reader 忽略新 optional 字段但继续显示 generic lanes；两台 iPhone cache/merge 不产生
duplicate、ghost、impossible values；upstream fleet `AccountSnapshot` 不进入 iOS 聚合；
silent push/background/physical-device 缺口必须写出 residual risk。

## CloudKit Production audit

初步：`DEPLOY_REQUIRED`，尚未执行 Production deploy。

- 既有 Mobile record families/zone 不重命名；
- Shared provider additions仍是 existing compressed JSON payload 内的 optional keys；
- 但 upstream fleet sync 明确新增 `CodexBarSync` zone、`AccountSnapshot`、`Device`、
  `Preferences`、`ProviderIntent` 及其 fields；
- package 与 iOS entitlements 仍必须指向 `iCloud.com.o1xhack.codexbar` / `Production`；
- 最终 schema diff、candidate entitlement、deploy 前后 readback 需要在实现后补录。

## 当前 residual risk

- 尚未执行 merge/build/tests；
- 尚未验证真实两 Mac × 两 iPhone；
- CloudKit Production schema deploy 未授权且未执行；
- Production deploy 完成前 fleet sync 即使默认关闭也不能作为可发布能力验收；
- live provider、browser cookie、Keychain prompt 和真实 CloudKit writes 均未运行。
