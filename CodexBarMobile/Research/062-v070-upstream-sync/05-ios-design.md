# iOS 2.4.0 实施设计

Status: `ready`

Goal已确认单版本方案；本文件细化下一阶段，不声明已实现。iOS目标2.4.0 (227)，所有target同步；只有一个MobileReleaseNotesCatalog版本块，四语言同时补齐。

## Kimi 与实时库存

UsageCardView是详情/总览/账户多个入口共享的窗口卡。effective字段继续驱动可用性、warning和widget，blockingQuota存在时增加明确月池阻塞状态和原始窗口消耗说明，避免将有效100%误读为实际消耗100%。不展示短reset会恢复访问或短regen；过reset的缓存只能说明上次观察，不自行改成可用。旧Mac的缺metadata payload保持既有fallback；多Mac merger不得从较旧记录追加矛盾的可用窗口覆盖最新阻塞状态。

ProviderDetailsView对native Claude旧缓存同名Limit Reset Credits row过滤，保留其它rows/chart，插件同名row不受影响。Mac实时库存继续可用；iOS不做持久化库存观察或虚构可兑换入口。

## Quota burndown

新增可独立测试的纯model与Swift Charts view，使用SyncUtilizationSeries.entries的真实capturedAt/usedPercent/resetsAt及SyncRateWindow。当前值的采样时间为provider.lastUpdated，不是iPhone当前时间。按reset同一周期（上游2分钟容差）选取，百分比下降后只保留最新segment，保留理想剩余额度线、calendar起止和capture age；future/nonfinite/unknown/synthetic无效数据不伪造曲线。先显示Codex/Claude可验证窗口，再接既有utilization history。无需新增wire。

## 观察模型与本地存储

modelsUsed与有价格modelBreakdowns分开显示，不为token-only观察名创建假成本。除SwiftData整provider JSON外，要更新所有生产daily重建路径：ProviderSnapshotMerger的daily accumulator/build、CostLedgerService、TokenActivity。不能只在原始detail页显示而在跨Mac合并/本地ledger丢失。新增local storage字段若需要使用optional默认值并覆盖旧库读取；不改CloudKit schema。

## Provider变化

核对16个上游brand颜色与iOS builtin fallback，保留light/dark contrast和synced tint策略。Antigravity grouped weekly/Starter、Mistral Monthly Plan、Notion/ZoomMate/LongCat通过existing rateWindows/budget/providerAmount/details传输；补新增固定label的四语言，保留provider账号/模型等verbatim文本。各自parser→bridge→consumer fixtures验证，不能只靠schema能装载。

## 验证

xcodegen后build/test，独立widget snapshot totals gate，模型/mapper/ledger/merger/usage-card policy测试；新增burndown做Simulator渲染与四语言可读性核对。16组合依canonical sync文档逐格记录，实测或明确替代验证并保留Production/APNs未证风险。最终全diff独立review、修复、复测，任何阻塞不留待以后。
