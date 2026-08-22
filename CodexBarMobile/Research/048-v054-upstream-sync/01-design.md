# v0.54.0 Upstream Sync 设计

Status: `done`
Date: 2026-08-21

## Merge 策略

1. provenance-preserving merge published tag `v0.54.0`，保留 upstream parent；
2. 按冲突路径逐项整合，不使用整树 ours/theirs；
3. fork-owned CI、release scripts、Production entitlements、Mobile sync、composite version、appcast 与
   parser hash policy保持不变；
4. root changelog保留 fork release段并合入 upstream 0.53/0.54，candidate阶段不改 live appcast；
5. Settings 采用 upstream retained controller + application-menu repair + placeholder guard，同时保留
   fork AppDelegate Mobile observer生命周期；
6. cost/scanner/cache采用 upstream provenance/coverage与历史定价语义，保留 fork Mobile aggregation、
   fallback pricing和published-cache迁移；触及parser文件后滚动 logic version并重生成hash；
7. locale自动合并后跑完整 lint，不以 ours/theirs 丢 key。

## iOS 设计门

先审计 upstream v0.54 数据如何进入 `UsageStore.tokenSnapshots` 与 `SyncCoordinator.makeCostSummary`：

- 已有 wire 能准确表达时，复用 generic rows，不复制 Mac-only UI/config；
- partial total、coverage、provenance、metered cost 或 token mix 若会改变用户理解，使用 additive
  optional字段并让旧 payload decode为 `nil`；
- 新字段只进入 `DeviceProviderSnapshot.payload` opaque JSON，不 bump `providerPayloadVersion=1`；
- iOS UI只在字段存在时显示“partial/estimated/source/coverage”，旧 Mac输出维持旧表现；
- 不同步project path、conversation/session identity、local file path、auth token、cookie、API key、
  plugin secret或OpenCodex raw event。

## 版本方案

| Artifact | 基线 | 目标 |
|---|---|---|
| Mac `MARKETING_VERSION` | `0.52.0.1` | `0.54.0.1` |
| Mac `BUILD_NUMBER` | `124.1` | `127.1` |
| `MOBILE_VERSION` | `1.21.0` | `1.21.0` |
| iOS `MARKETING_VERSION` | `1.21.0` | `1.21.0` |
| iOS `CURRENT_PROJECT_VERSION` | `194` | `195`，全部 targets |
| Sparkle version | `124.1.1.21.0` | `127.1.1.21.0` |
| candidate tag | `v0.52.0.1-mobile.1.21.0` | `v0.54.0.1-mobile.1.21.0` |
| upstream bookmark | `v0.52.0 / 2026-08-17` | `v0.54.0 / 2026-08-20` |

## 测试策略

- Mac最快关键路径：merge/fork policy → build/lint → Settings focused → CloudSync/sync → cost/parser/cache →
  provider focused → full grouped tests；
- Settings真实QA：menu与`Command-,`、重复复用、前台/Space、launch placeholder；
- iOS：Shared round-trip/old fixtures、cost/widget/provider display focused、Release simulator build、full tests；
- wire/display/cache变化触发16-case matrix；无四台硬件时必须逐行标`substituted`并记录风险；
- CloudKit schema diff + Production只读audit；无明确授权不deploy；
- merge、bridge、iOS三轮自查/review，阻塞问题修复并复测。

## 权限边界

本轮允许分支、本地merge、实现、测试与本地staged commits。禁止push、PR merge、published tag、
live release、appcast publication、TestFlight upload与CloudKit Production deploy。
