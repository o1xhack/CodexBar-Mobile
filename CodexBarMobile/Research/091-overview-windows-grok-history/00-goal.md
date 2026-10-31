# Overview widget 每槽额度窗口（#223）与 Grok 额度历史

状态：done（实现与本地验证完成；远端审查、合并与 TestFlight 以 PR 和发布记录为准）。用户 2026-10-30 确认两项都进入 iOS 3.5.0（跳过 3.4，按用户版本号偏好）。

## 1. Grok 在 Summary 额度图只有一个点

根因：Mac 通过浏览器 Cookie 读取 Grok 时快照不带 email、organization、accountIdentities 或 accountRecordKey（本机同步状态实测 `identity` 只有 `providerID`，`accountKey` 为 `default`）。iOS 的 `UsageAccountIdentity.tokens` 只能得到 `grok:card:grok|`，`hasUnambiguousHistorySource` 要求稳定身份，于是本地观测与同步历史全部不记录，只剩当前读数。Mac `usage-history.jsonl` 也没有 Grok 记录，widget Quota Pace 曲线同样为空（Mac 侧不在本仓库 iOS 范围）。

方案：新增 `UsageQuotaHistoryOwner`。稳定身份照旧；另外接受“匿名单例”——该服务唯一账号、身份只有 card key、无任何涉及该服务的 linkage、锚点从未学到稳定身份——以 card key 作为 owner（`UsageQuotaHistory.anonymousSingletonToken`，与 `stableAccountTokens` 互斥）。出现第二个账号或 linkage 时立即删除该流且不再恢复；之后学到稳定身份时按原规则清空。record slot（可复用凭证槽）仍不记录，原有测试保持。

已知边界：同一浏览器换成另一个 Grok 账号时 card key 不变；`record` 的重置时间/用量回落规则会切断大多数情况，残余风险接受。

## 2. Overview widget 每槽选择窗口（issue #223）

- SiriKit `SelectStatusWidget` 新增 `quotaDisplay`（Used/Remaining，父参数 mode=overview）与 `window1…4`（`QuotaPaceWindowOption`，父参数 providerN HasAnyValue），选项处理复用 Quota pace 的 `QuotaPaceWindowChoice.options`。
- iOS 27 `StatusWidgetAppIntent` 同名参数；窗口用 `OverviewWindowNOptions`（`DynamicOptionsProvider` + `@IntentParameterDependency` 对应槽位），存储值仍由 `QuotaPaceWindowOptionAppEntityQuery` 解析。参数一致性测试已覆盖。
- 配置不进旧 App Intent schema：`CodexBarWidgetEntry.overviewQuota`。槽位窗口只在其 id 指向该槽当前服务商时生效。
- `overviewFigures(windowID:)` 用 `quotaPace.windows` 中该窗口的用量与重置；窗口已在同步后重置则不显示旧用量；窗口消失回退每周。返回 `windowTitle`，瓦片说明行显示“窗口 · 已用/剩余”，紧凑瓦片把窗口名放在服务商名旁。
- “按每周重置”模式无槽位，窗口参数不适用，但显示方式适用。

## 验证

- `UsageQuotaOverviewTests` 44 项通过（新增匿名单例记录/持久化、第二账号与 linkage 撤销）。
- `OverviewQuotaWindowTests`、`WidgetConfigurationAppIntentsTests`、`SoonestWeeklyResetTests` 通过；渲染导出小/中/大 × 浅/深 × 已用/剩余并人工查看。
- 证据目录：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/GrokHistory`。
- 不改同步格式与 CloudKit schema，Production 无需部署。
