# 设计

Status: `done`

## 合并

- 一次 `git merge v0.73.0`（249 个提交），冲突 13 个，逐个处理：
  - **保留 fork 的版本**：CI 策略（`ci.yml`、分片策略校验脚本的 6 分片部分）、appcast、`version.env`（0.73.0.1 / 165.1 / Mobile 2.6.0）。
  - **分片校验脚本的 harness 用例**：采用上游的新循环。
  - **`applyExternalConfig`**：采用上游 `bumpConfigRevision` 的调用形式，保留 fork 给 Mac fleet sync 用的外部配置变更通知。
  - **`CodexRowCostBreakdown`**：沿用 fork 的文件布局（放在 `CostUsageScanner+PricingRows.swift`），内容更新为上游 0.73 版本（新增已定价 / 未定价请求计数），保留 fork 的 `hasEstimatedPricing`。
  - **Codex 定价**：保留 fork 对未限定 OpenAI 模型的同系列兜底（例如 gpt-6-luna），以及上游的 provider 限定定价隔离。
  - **兼容缓存列表**：去掉所有已发布 fork 版本的缓存哈希（见下）。
  - **解析器哈希**：重新生成。
- **README**：保持 fork 版本，只套用文档生成器给出的事实更新（91 个 provider、Langdock 条目、社交卡片的内容哈希），并单独提交，同时登记新的校验哈希。
  - 上游 README 的其它差异只有社交卡片和 Langdock，没有安全或排障相关的事实变化。

## Codex 成本“未知”与 token 翻倍（Mac 0.72.0.1 回归）

两个都是上游 v0.72.0 request-ledger（`token_usage_record`，Codex CLI 自 2026-09-03 起写入）的缺陷。用户本机的真实数据已复现，见 03-testing.md。

1. **成本被标成未知。** 升级迁移时，用 ledger 行自己的时间戳去查旧定价，但 ledger 记录和对应 `token_count` 的时间戳相差几毫秒到几百毫秒，查不到，于是写入 `unpricedTokens`。当天该模型的成本因此变成 nil，`SyncCoordinator` 判为 `costIsKnown=false`、金额 0。上游 #4270（94e2beb3c）修复。
2. **token 约翻倍。** 压缩或 resume 后，`token_count` 的累计值落后于线程计数，镜像对不上，legacy 行被重复计入。上游 #4290（03112809f…26ffcafa4）修复。

fork 自己的缺口：0.70.0.1 等已发布 fork 缓存被列为“兼容前代”，升级时走进了上游这条有 bug 的迁移路径。另外，上游 0.73.0 明确不修复已经被 0.72 写坏的缓存（29a8b92dc），需要用户手动执行 `codexbar cache clear --cost`。

**处理：**
- 兼容列表中去掉所有已发布 fork 缓存的哈希（0.49.2.1、v0.52 candidate、0.54.0.1、0.68.0.1、0.70.0.1；0.72.0.1 的哈希本来就不在列表里）。升级后自动从会话日志重建，坏的标记和重复行一并清除，用户无需手动操作。
- 测试固定这 6 个哈希都必须重建。
- `parserLogicVersion` 升到 20，重新生成解析器哈希。

**取舍：** 重建会丢掉本地日志已删除那些天的缓存。不过 iPhone 账本已经不再让“未知”覆盖“已知”（Research 069），这些天在 iPhone 上会保留。

**口径变化：** 0.70 在 09-03 到 09-15 少算了 resume 后计数器回退的用量。例如 09-05，0.70 算出 $101，真实值约 $542。修复后这几天会明显高于 0.70；09-16 以后只高 1–3%。

## Claude 空条目

- Studio 在后台没有可用的 Claude 数据源：OAuth 钥匙串提示模式为 never。
- 用户手动刷新时改走 CLI，但 Claude Code 2.1.28x 的 `/usage` 只输出 insights，被误判为订阅提示，于是 snapshot 和 error 都被清空。iPhone 收到的就是一个没有任何解释的空 Claude 条目。
- 这条路径 0.70 就已存在，属于上游问题。

**处理：**
- 摘取上游 36bf01ace（#4332）：只有 insights 时作为明确错误上报，在 v0.73.0 之后。
- Mac：快照为 nil、没有错误且额度已知不可用时，发布一条不算错误的说明 `Usage limits are not available for this account on this Mac.`。
- iPhone 合并器：任何来自 Mac 的数据都没有的条目，不管是否报错，都不算观测。它不会盖掉另一台 Mac 的数据，没有身份时会被吸收（成本照常合并），带说明的会在详情页列出。
  - “所有 Mac 都无法刷新”的提示要求至少一条真的报错或带说明，所以只有成本的 provider（多 Mac）不会误报。

## 推送失败重试

- Studio 负载 70–100 时，utility QoS 的 CloudKit 请求被饿到 45 秒预算超时，被报成 `networkFailure`，日志里显示为 “Network unavailable”。
- 失败后原本要等下一次 provider 刷新才再试，手机上的数据会落后几十分钟。

**处理：**
- 失败后依次在 30 秒、1 分钟、2 分钟后重试，之后每 5 分钟重试一次，直到成功。同一时间只有一个待重试任务，停止观察时取消。
- 有界推送操作改为 userInitiated QoS。

## Langdock（上游 v0.73.0 新 provider）

有 Session 和 Weekly 两个百分比窗口。处理方式：
- 品牌色 `#5A4AE7`，浅色模式下加深；
- 加入第一方 provider 列表，用于详情本地化；
- QuotaTransition 订阅追加到列表末尾（84 个 provider × 3 种状态 = 252 个 zone），保持已有订阅 ID 稳定；
- Mac 身份计算按非 Tier-A 处理，在 iOS 上是单账号卡；
- Mac 增加 debug mock（共 106 个）。

## CloudKit 审计

- 没有新的 record type、字段、索引或 subscription 类型。
- Langdock 的 QuotaTransition zone 是运行时创建的，和以往新增 provider 一样。
- Shared payload 新增的是 iPhone 本地字段（`sourceReport`，来自 2.6.0 的多 Mac 修复），Mac 不会设置，nil 时不编码。
- **结论：`NO_DEPLOY`。**
