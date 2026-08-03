# v0.47.0 Upstream Sync 设计

Status: `ready`
Date: 2026-08-03

## 设计原则

以 published `v0.47.0` tag 做一次 provenance-preserving merge，完整保留上游 Mac
行为；仅在 fork-owned Mobile、CloudKit、CI、release、appcast 和 composite version
契约发生冲突时做定向整合。

## Merge 策略

1. 在 `upstream-sync/v0.47.0-mobile.1.20.0` 合并 annotated tag `v0.47.0`。
2. 保留 `.github/workflows/pr-fast.yml`、fork Final CI trigger、
   `Scripts/check_ci_policy.sh` 与 `docs/ci-policy.md`。
3. 保留 fork `release.sh` / `package_app.sh` / notarization / appcast / bundle ID / team /
   Sparkle / Production CloudKit 路径；逐项吸收上游 package security 改进。
4. `CHANGELOG.md` 保留 fork 当前 Mobile 段，并加入 v0.46.0 / v0.47.0 上游段。
5. Mac localizations 采用上游新 strings 与 fork Mobile strings 的 union，所有 catalog
   通过 locale audit。
6. Alibaba 冲突保留 fork 已发布的 freshness/rate-window hotfix，同时叠加上游
   Personal/Solo、安全 token、shared OneConsole 和 session hardening。
7. parser/cache/scanner 冲突合并两侧语义，bump `parserLogicVersion` 后重生成
   `CodexParserHash`。
8. published appcast 在 candidate 全部通过前保持不变。

## 双 sync 架构

```text
Mac local usage
  ├─ existing Mobile sync (iCloudSyncEnabled, default true)
  │    └─ DeviceProviderSnapshot / existing zones -> iPhone + widgets
  └─ upstream fleet sync (macFleetSyncEnabled, default false)
       └─ AccountSnapshot / Device / Preferences / ProviderIntent
          in CodexBarSync zone -> other Macs only
```

两条通道共享 Apple container `iCloud.com.o1xhack.codexbar`，但 master toggle、
UserDefaults key、record types、zone、persistence state 与消费端必须隔离。iPhone 继续只读
既有 Mobile record families；上游 `AccountSnapshot` 由 Mac fleet UI 消费，防止相同
usage 在 iOS 侧重复聚合。

upstream engine 的 container 常量必须引用 fork container。持久化文件名/namespace
必须带 fork/fleet 语义，避免读取上游 bundle 的旧 state。上游 provider secrets 只有在
`macFleetSyncEnabled && macFleetSyncIncludeSecrets` 时进入 encrypted CKRecord fields。

## Shared wire 方案

- 不 bump `providerPayloadVersion` / `encodingVersion`；
- 四个新 provider IDs 只 tail-append notification list；
- Qwen Cloud / Notion 使用现有 `SyncRateWindow`、identity、plan metadata；
- xAI 余额映射为 `SyncProviderAmount(kind: "balance")`，daily USD history 映射为
  `SyncCostSummary`；
- Claude `ProviderCostSnapshot.balance` 可与已有 spend-limit 同时存在：
  `SyncClaudeExtraUsage` 继续表示 used/limit，`SyncProviderAmount` 单独表示 prepaid
  balance；
- ZoomMate 使用新的 additive optional `SyncZoomMateCredits`，保留 cycle、credits、
  overage/unlimited 与 daily history；老 iOS 忽略，新 iOS 对老 Mac 得到 nil；
- Notion workspace display 使用新的 optional `accountOrganization`；它只参与显示，
  account merge 仍使用 authenticated identity set；
- z.ai 7d/30d 使用新的 optional daily model-usage history；hourly payload 与现有图保持
  向后兼容，daily 与 hourly 日期解析分开；
- 所有新增字段用显式 `decodeIfPresent`，old payload / new reader 与 new payload /
  old reader都不得 decode crash；
- account identity 使用上游 authenticated email/workspace ID，anonymous provider 不用
  可编辑 label 合并；
- PreviewData 按 card 数据类型补样例，不为每个 generic provider 重复造相同卡片。

## iOS 展示方案

1. Qwen Cloud：5h/weekly rate-window generic card；plan 放 identity/subtitle。
2. Notion AI：rolling/billing-period generic card；workspace/name 保持账户区分。
3. xAI：余额卡 + Cost dashboard 30-day series；与 `grok` 保持独立颜色/identity。
4. ZoomMate：credits balance/usage/overage/cycle 与 daily history；若 history 缺失，
   credits status 仍可独立显示。
5. Claude：在已有 Extra Usage card 下保留 prepaid balance，不把 balance 当 budget。
6. z.ai：在现有 hourly chart 上提供 7d/30d range，legend/colors/tooltip 与 Mac dataset
   一致。
7. 全部用户文案包含 `en`、`zh-Hans`、`zh-Hant`、`ja`，不在 UI 暴露 wire/schema/API
   等工程词。

## 版本方案

| Artifact | Target |
|---|---|
| Mac `MARKETING_VERSION` | `0.47.0.1` |
| Mac `BUILD_NUMBER` | `111.1` |
| iOS `MOBILE_VERSION` | `1.20.0` |
| iOS `CURRENT_PROJECT_VERSION` | `192`（四个 targets） |
| Sparkle / app CFBundleVersion | `111.1.1.20.0` |
| candidate tag | `v0.47.0.1-mobile.1.20.0` |
| `UPSTREAM_VERSION` / date | `v0.47.0` / `2026-08-03` |

上游变化将前三段更新到 `0.47.0`，fork 在新 upstream train 首发所以 `.1`；上游
BUILD_NUMBER `111` 加 fork patch `.1`。iOS 从当前工程 `1.19.1 (191)` 进入包含新
provider 与 sync 兼容的 feature minor `1.20.0 (192)`。

## CloudKit 方案

预期最终 audit 为 `DEPLOY_REQUIRED`：同一 fork container 新增独立 zone 和四种 fleet
record types；同时把已有 iOS writer 使用、但 Production export 缺失的
`ProviderAccountLinkage` 纳入 tracked schema。代码可以先完成并打包，但签名 candidate
只能作为 pre-deploy 验证；Production deploy 完成前不得发布 live release。schema 文件
和 deploy script 必须改为 fork container，并且只做显式目标审计，不能把 upstream team
profile 或 container 写入资产。

## 测试方案

- provenance/conflicts：tag ancestry、unmerged path、fork CI policy、release scripts、
  version/appcast/changelog；
- Mac：`swift build`、lint、full `swift test --no-parallel`、multi-account/multi-device、
  CloudSyncEngine、four-provider parsers/models/UI、Keychain no-prompt、process/security、
  widgets、Alibaba regressions；
- parser：focused scanner/cache tests、version/hash audits；
- Shared/iOS：wire round trips、old/new fixtures、four-provider mock/subscription/color/card、
  ZoomMate/xAI/Claude money、Notion workspace、z.ai hourly/daily parsing、
  identity/merge/cache/ghost/CWL/widgets；
- iOS：full unit target、Release simulator build；
- sync compatibility：`03-testing.md` 16 rows全部给出 pass/fail/substituted 证据；
- release：signed/notarized/stapled universal app/ZIP/dSYM、Production entitlement、
  Gatekeeper、version monotonicity、local candidate appcast/draft metadata；
- review：merge、Shared/iOS、release 三轮自查 + independent agent review，直到 blocker 0。
