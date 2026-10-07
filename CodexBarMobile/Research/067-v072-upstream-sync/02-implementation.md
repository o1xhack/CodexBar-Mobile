# 实现记录

Status: `done`

## 合并冲突决策（2026-10-06）

`git merge --no-ff --no-commit v0.72.0`（tag commit `6a02be2feea9cc0823395ad2f19bb71b7a7bd20f`），47 个冲突文件，逐个处理：

- `README.md`、`appcast.xml`、`version.env`：保留 fork 版本（README SHA256 与 mobile-dev 一致 `56b7ebcf…f730`）。版本号随后按 00 方案单独更新。
- `CHANGELOG.md`：fork 0.70.0.1 段在前，完整保留上游 0.72.0/0.71.1/0.71.0 段。
- 23 个 `Localizable.strings`：两侧新增键取并集；`plutil -lint` 通过；脚本核对合并未引入新的重复键（既有重复键来自双方原文件）。
- `.github/workflows/ci.yml`、`Scripts/test_swift_test_sharding.sh`：保留 fork 6 shard / 80 分钟（fork 每个 selection 独立分组，上游 3 shard 依赖批处理短套件）；上游其它 workflow 改动自动合并。
- `Scripts/ci_swift_test_by_suite.py`：保留 fork 多次一致发现（≥3 次）与 `--skip-build` 重试，接入上游 `inventory` 参数（取首个有效发现结果）供 direct workers 使用。
- `CostUsageClaudeCache.swift`：采用上游（fork 仅有 DEBUG 驻留 memo；上游以 TaskLocal 隔离 memo 解决同一并行驱逐问题）；fork `CostUsageClaudeKimiAliasTests` 改由上游 suite 级 `CostUsageClaudeCacheFixtures` 隔离，断言不变。
- `CostUsageStore.swift` 与测试：兼容前驱取并集，并登记已发布 0.70.0.1 fork hash `11b5eaedd0f337a7`。
- `CostUsagePricing.parserLogicVersion` 18→19；`CodexParserHash` 由脚本重新生成（初次 `c3e4a66c1b7f0a59`，最终以 lint `check_codex_parser_hash` 为准）。
- `GrokLocalSessionScanner`：采用上游可选 enumerator（只读 session 根 signals），保留 fork Gregorian/producer 时区；测试两侧用例都保留。
- `SpendDashboardModel`/`PreferencesSpendDashboardPane`/测试：采用上游 #4172/#4247 项目与独立 chat 分离（取代 fork 同名项目的并行修复与 `spendDashboardProjectDisambiguationPath`），保留 fork 刷新失败来源说明与 producer 时区分桶。
- `UsageStore+Refresh`：接入上游 `sessionRestoredNotificationPending`，保留 fork `finalizeProviderRefreshSuccessPublication`（含 `markProviderRefreshSuccessful`）。
- `UsageStore+SessionQuotaTransition`：采用上游 reset 通知仲裁；fork iOS QuotaTransition 推送独立成 `publishSessionQuotaTransitionToiOS`，在仲裁前写出，不受 Mac 通知开关或 reset banner 替代影响。
- `UsageStore+TokenAccounts`：保留 fork 快照发布完整性返回值，透传上游 `sleep` 注入。
- `BoundedTaskJoin`、`SubprocessRunner`：采用上游（#4217 可控计时 fixture 取代 fork 的 WallClockTimeout 方案）；`WallClockTimeout` 仍用于 OpenAI dashboard cookie deadline。
- `OpenAIDashboardBrowserCookieImporterTests`、`ProcessPipeCaptureLinuxTests`：采用上游受控 fixture 版本。
- `CloudSyncEngine.swift`：见下节。

## CloudSyncEngine

fork 版是 `actor`（含 engine lease、revision gates、deletion recovery、`record(error:scope:)` 等 fork 修复），上游 v0.70→v0.72 只有 #4147（949cac4e8）与 #4161（d066665de）改动该文件，且 #4161 把引擎改为 `@MainActor final class`。决定以 fork 版为基础移植上游语义（独立子代理执行、本人复核）：

- #4147：`CloudSyncLifecycle.isCurrentEngine` 取代 `shouldResumeDelayedRetry`；`CloudSyncEntitlementGate.prepareForSync` 仅在同时具备 CloudKit 与 `com.apple.developer.aps-environment` 时注册远程通知，fork 以 `macFleetSyncEnabled`（不是 Mobile 通道开关 `iCloudSyncEnabled`）作为 fleet 引擎开关；去掉 `automaticallySync = true`；`fetchChanges(scopedToSyncZone:)` 合并 `fetchAllChanges`；`processEvent` 最先做当前引擎守卫（fork 错误恢复也在守卫后）；`handleSaveFailure(_:error:syncEngine:)` 新签名与 `.unknownItem` 删除记录恢复；`scheduleRetry(deleting:)` 合并删除重试并对保存重试也校验发起引擎；`localWinsConflict` 复用。
- #4161：转 `@MainActor final class`，静态常量/纯函数 `nonisolated`，去除全部 `MainActor.run` 跳转；`applyGeneration`、`beforeApply` 注入与 `applyIfCurrent` 原子边界；`stopEngine` 先 bump generation、作废 lease、置空 engine，最后 `cancelOperations`；fetched changes apply 后再校验引擎与取消。
- 保留：容器 `CloudSyncConstants.containerIdentifier`；engine lease 与 `CloudSyncDeviceRemoval`；`delegateEventQueue` 串行事件；provider intent 写设置与 fork 的 `externalConfigurationDidChange` 在同一同步边界提交（相关三个函数改为同步）；fork 终态跳过不释放前置映射；删除缓存的完整清理。类体超长，`scheduleRetry` 移入同文件 extension。
- 测试：上游三份新测试与 SyncModelTests 未改；fork 的两份 CloudSyncSettings 测试只去掉多余 `await`/`async`，断言不变。CloudSync|SyncModelTests|SnapshotMigration 113 项通过（8 suites）。
- 残余：若干调用点出现 “no async operations in await” 警告（与上游合并后一致，非错误）；签名发布不含 aps-environment，push 注册不会触发，fleet 维持拉取模式。

## 编译修复与语义对齐（合并后）

- `PiSessionCostScanner`：上游把日报聚合移到 `PiSessionCostScanner+Aggregation.swift`（逐消息定价、"never reprice an aggregate request"、request 计数），自动合并保留了 fork 旧版私有聚合/重新定价函数（已无调用者，且缺 1h cache write 参数）。删除遗留代码，采用上游聚合；修正 fork 非可选 `catalog` 上的可选链。
- `SpendDashboardModelTests`：去掉 fork 辅助函数重复的 `path` 参数，与上游签名一致。
- `SpendDashboardModel`：项目行 `providerName` 恢复 fork 的 `input.displayName`（账号区分），上游 `modelProviderName` 仍用于模型行。
- `CostUsageModels.swift`：fork 字段 + 上游新增使文件超过 1500 行，按仓库先例加 `swiftlint:disable file_length`。

## Mac→iOS 桥接（commit 48a81235a）

- `SyncCoordinator.withBalanceDescription` 在 primary/secondary 构建后按 descriptor 的 `showsPrimary/SecondaryBalanceDescription` 事后标注（避免改变 gatekeeper 记录的 provider 簇偏移），同步更新 alibabatokenplan 的 semantic legacy 窗口；`projectingBlockingQuota` 与 iOS Kimi 有效窗口重建保留该字段。
- `mapProviderAmount`：`.lithosai` 并入预付余额分支；新增 `.grok`（`balance != nil` 时发布，0 也发布）。
- `mapDetails`：转发 `id`/`progress`/`usageValue`。
- `QuotaProviderList` 尾部追加 museai、workbuddy；`AccountIdentityComputer` 三个新 provider 保持 per-device；Mac mock 105 个快照（LithosAI mock 带预付余额与 Billing 详情）；Mac mock 说明计数修正为 105/95（22 语言，含波斯数字）。
- gatekeeper：更新 providerAmount 与 AccountIdentity、mock 数组簇指纹；新 mock 簇与 LithosAI 扩展加 `Provider-specific by design` 说明。

## README

合并 commit 中 README 与 mobile-dev 字节一致（SHA256 `56b7ebcf…f730`）。之后单独提交 2fafec411，只移植 v0.70.0..v0.72.0 上游 README 的四处事实变化（social 图 token 与 90 providers、Muse (muse.ai) 条目、LithosAI/WorkBuddy 生成区块、codexbar-kde），guard hash 更新为 `35e4e3b0fc78e243c69056ab37edd17d34104c7c7534e6cab25d63d351c6efd7`。

## iOS 2.6.0 (235)（commit bef187ba0）

见 06 清单；新增 `ProviderDetailRowPresentation`（详情行本地化、进度条、Claude 云额度到期），`UsageCardView` 余额描述，`ProviderDetailLocalization` 新标签/值（LithosAI 用专用键避免与通用 "Added" 冲突），三色板，QuotaProviderList 83/249，24 条四语言字符串，CHANGELOG、in-app notes（2.6.0 Latest，2.5.0 降级）、AppStoreMetadata/2.6.0。

## 提交

| Commit | 内容 |
|---|---|
| e0a729b49 | merge v0.72.0 + 冲突解决 + 编译修复 |
| 48a81235a | Mac→iOS 桥接、Shared optional 字段、新 provider mock/推送列表 |
| 2fafec411 | README 事实适配 + guard hash |
| 7b3975a35 | lint 修正 |
| bef187ba0 | iOS 2.6.0 (235) |
| 9b15925e7 | version.env / 根 CHANGELOG |
