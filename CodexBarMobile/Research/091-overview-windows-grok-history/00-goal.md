# Overview widget 每槽额度窗口（#223）与 Grok 额度历史

状态：done（实现与本地验证完成；远端审查、合并与 TestFlight 以 PR 和发布记录为准）。用户 2026-10-30 确认两项都进入 iOS 3.5.0（跳过 3.4，按用户版本号偏好）。

## 1. Grok 在 Summary 额度图只有一个点

根因：Mac 通过浏览器 Cookie 读取 Grok 时快照不带 email、organization、accountIdentities 或 accountRecordKey（本机同步状态实测 `identity` 只有 `providerID`，`accountKey` 为 `default`）。iOS 的 `UsageAccountIdentity.tokens` 只能得到 `grok:card:grok|`，`hasUnambiguousHistorySource` 要求稳定身份，于是本地观测与同步历史全部不记录，只剩当前读数。Mac `usage-history.jsonl` 也没有 Grok 记录，widget Quota Pace 曲线原本同样为空。

方案：新增 `UsageQuotaHistoryOwner`。稳定身份照旧；另外接受“匿名单例”——该服务唯一账号、身份只有 card key、无任何涉及该服务的 linkage、锚点从未学到稳定身份——以 card key 作为 owner（`UsageQuotaHistory.anonymousSingletonToken`，与 `stableAccountTokens` 互斥）。出现第二个账号或 linkage 时立即删除该流且不再恢复；之后学到稳定身份时按原规则清空。record slot（可复用凭证槽）仍不记录，原有测试保持。

已知边界：同一浏览器换成另一个 Grok 账号时 card key 不变；`record` 的重置时间/用量回落规则会切断大多数情况，残余风险接受。

### 1b. Quota pace widget 曲线（不依赖 Mac）

widget 快照由 widget 进程从 CloudKit 自建，Mac lane 只覆盖 Codex/Claude。改为由 iPhone 自己的历史补上：

- App：`UsageQuotaOverviewStore.reconcile` 结束后经 `UsageQuotaWidgetHistorySink` 导出 `WidgetLocalQuotaHistory`（App Group 文件 `widget-local-quota-history-v1.json`）。只导出“匿名单例”owner（该服务唯一账号、无身份、无 linkage，且 `historyMatchesAnchor` + `history(_:isOwnedBy:)` 仍成立）的流，每个窗口只取最新重置周期。有稳定身份的账号不导出：widget 只能确认“该服务只有一个账号”，无法确认是哪一个，换号后可能把旧账号读数画给新账号。仅 `live()` 接线，demo/测试 store 不写；账号列表为空（快照未加载）时不覆盖；内容变化才写并刷新 Quota pace 两种 kind。
- widget：`CodexBarWidgetSnapshotBuilder` 读取该文件。widget 不经 App 独立刷新，所以自己重新检查匿名单例条件（GitHub Codex 审查 P2）：合并快照中该服务恰好一个账号、该账号仍无身份也无凭证槽（`WidgetLocalQuotaHistory.isIdentityLess`）、没有生效的 linkage（`UsageCardLinkages` 移到共享层）。满足时，`CodexBarWidgetPaceSummary` 对没有 Mac lane 的服务按窗口 id 生成 `local:<windowID>` lane（`MobileQuotaBurndown` 新增按周期长度构造入口，沿用重置 ±120 秒、用量回落即重来、只取 capturedAt 之前），App 可能用来源时间记下当前读数，若最后一条与当前用量相同则去掉，避免同一读数算两点；去掉后仍要有一个真实的较早读数才画。本地 lane 不参与自动选择（`isAutomaticCandidate`）和排序（`paceRank` 用 `hasPublishedChart`），不会挤掉 Codex/Claude。未选窗口时默认窗口原先只认 weekly/session lane，现在再回退到本地 lane，Grok 不再显示“还没有配速数据”。
- 周期长度：Grok 无 `windowMinutes`，距重置不足约 3.5 天时 `QuotaPace.duration` 推不出周长，原先会因 duration 变 nil 清空整段历史。现在同一重置时间内沿用已观测到的周期长度（记录与 Summary 显示两处都用 `UsageQuotaProjection.inheritedDuration`）。

限制：曲线点来自 App 运行时的观测（打开 App/前台刷新时记录），widget 自身刷新不新增点。

## 2. Overview widget 每槽选择窗口（issue #223）

- SiriKit `SelectStatusWidget` 新增 `quotaDisplay`（Used/Remaining，父参数 mode=overview）与 `window1…4`（`QuotaPaceWindowOption`，父参数 providerN HasAnyValue），选项处理复用 Quota pace 的 `QuotaPaceWindowChoice.options`。
- iOS 27 `StatusWidgetAppIntent` 同名参数；窗口用 `OverviewWindowNOptions`（`DynamicOptionsProvider` + `@IntentParameterDependency` 对应槽位），存储值仍由 `QuotaPaceWindowOptionAppEntityQuery` 解析。参数一致性测试已覆盖。
- 配置不进旧 App Intent schema：`CodexBarWidgetEntry.overviewQuota`。槽位窗口只在其 id 指向该槽当前服务商时生效。
- `overviewFigures(windowID:)` 用 `quotaPace.windows` 中该窗口的用量与重置；窗口已在同步后重置则不显示旧用量；窗口消失回退每周。返回 `windowTitle`，瓦片说明行显示“窗口 · 已用/剩余”，紧凑瓦片把窗口名放在服务商名旁。
- “按每周重置”模式无槽位，窗口参数不适用，但显示方式适用。

## 验证

- `UsageQuotaOverviewTests` 44 项通过（新增匿名单例记录/持久化、第二账号与 linkage 撤销）。
- `OverviewQuotaWindowTests`、`WidgetConfigurationAppIntentsTests`、`SoonestWeeklyResetTests` 通过；渲染导出小/中/大 × 浅/深 × 已用/剩余并人工查看。
- `WidgetLocalQuotaHistoryTests`（本地 lane 生成、多账号/旧周期/用量回落/错窗口拒绝、文件 schema、Quota pace 小/中/大 × 浅/深渲染）与 store 导出、周期长度沿用测试通过；渲染人工查看。
- 证据目录：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/GrokHistory`。
- 不改同步格式与 CloudKit schema，Production 无需部署。
