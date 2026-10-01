# 上游变化与 iOS 数据通道逐项审计

Status: `in-progress`

| 上游变更 | 已审计代码路径 | iOS 判断 / 下一步 |
|---|---|---|
| #4048 Claude saved limit resets | ClaudeRateLimitResetCreditsSnapshot.detailSections → UsageSnapshot.details → SyncCoordinator.mapDetails | 上游测试明确cached/synced不得复活库存。已在native Claude通用details发布前过滤live row，普通row/chart和plugin保留；Mac实时支持，iOS无权威refresh入口不展示库存。新iOS还需过滤旧缓存；不新增持久化观察模型 |
| #4085 quota burndown | QuotaBurndownModel → PlanUtilizationSeriesHistory；SyncCoordinator.makeUtilizationHistory → SyncUtilizationSeries | 既有 capturedAt/usedPercent/resetsAt/windowMinutes 已足够；iOS 需新增 recorded remaining-quota chart，当前尚未实现，不添加 CK字段。不能用 iPhone 当前时间伪造新 capture |
| #4091 Kimi 月池 blocking | Kimi descriptor.menuCard.blockingQuota → MenuCardView.blockingQuotaMetrics | 已实现native bridge effective窗口+optional raw blockingQuota metadata，旧iOS primary/secondary与rateWindows同源；旧版不会宣称短reset恢复。新iOS需独立blocked状态与raw消耗展示。测试和消费者/多Mac合并审计尚待完成 |
| #4084 Antigravity Starter/grouped weekly | AntigravityQuotaSummaryParser/RemoteUsageFetcher → RateWindow + extraRateWindows → syncRateWindow | 现有 period/windowMinutes/reset/usageKnown 可携带；尚待逐窗口 parser/mapper/render 回归确认，无证据前不标支持完整 |
| #4093 Grok billing outage token history | UsageStore+GrokLocalSessions → CostUsageTokenSnapshot → SyncCoordinator.makeCostSummary | 独立 review 确认 narrower projection 丢 producer calendar/metadata；已修正 Gregorian producer calendar、bucketTimeZoneIdentifier/windowEndDayKey/partial/reportingPeriod，待测试 |
| #4052/#4092 partial costs/cache reuse | CostUsageFetcher → historyCoverageIsEstablished/historyScanIsPartial → sync cost | 目前生产 partial 均 coverage=false，没有发现已可达误标完整；桥接统一 historyIsFullyScanned，旧 wire coverage=false继续限定 lower bound，无新增schema；待测试 |
| #4056 observed Grok model names | GrokLocalSessionScanner → daily.modelsUsed → cost chart | 新增optional SyncDailyPoint.modelsUsed，三个生产daily mapper均转发token-only观察模型名，reporting-period复用daily；尚待最新定向测试与iOS展示消费 |
| #4075 provider accents | ProviderDescriptor branding → Mac；iOS ProviderColorPalette builtin fallback | 新 Mac 的 plugin icon tint与内建 branding通道不同；需核对16 palette变更与iOS fallback/light-dark readable gate |
| #4072/#4076 Mistral Monthly Plan/pricing | MistralUsageSnapshot/UsageFetcher → named window/costSummary | 月窗口既有label/period可携带，event-zone-tier计价在Mac完成；需mapper/tests回归 |
| #4059/#4098 bundled migration | Notion/ZoomMate/LongCat plugin result → generic details、rateWindows、providerAmount | 既有schema支持；需补足新通用label四语言，确认over-quota/history/fuel-pack不丢失 |
| #4088 Codex plan upgrade / #4087 catch-up | UsageStore cost snapshot与quota backfill → SyncCoordinator | 上游原实现已合并，需旧功能/账户缓存/sync回归 |
| #4095 widget per-provider last-good | UsageStore+WidgetSnapshot → store + CloudSync publication | 合并同时保留fork fencing和upstream invalidation；无review直接阻塞，测试尚未完成 |
| #4097/#4106 process environment security | ProcessEnvironment storage + test_environment guard | Mac/CLI保留完整安全修正，不把env或credential传Shared；lint安全guards待最终通过 |
| AppKit菜单、Homebrew/CLI、agent sessions/process cleanup | Mac原始上游路径 | iOS无相同OS操作入口；完整Mac合并保留，iOS展示其使用数据而不同步本地权限/文件/进程 |

## 当前 CloudKit 判断

截至当前 Shared新增optional JSON blockingQuota与modelsUsed；CloudConstants与providerPayloadVersion=1未变，无新record type/field/index/query/subscription。初步 NO_DEPLOY，必须在最终iOS/bridge实现完成后对最后published tag重跑审计，当前不是最终release结论。Production实际读写、APNs、双Mac与双iPhone矩阵尚未执行。
