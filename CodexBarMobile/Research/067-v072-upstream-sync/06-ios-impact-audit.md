# 上游变化与 iOS 数据通道逐项审计

Status: `done`（设计期审计；实现与测试证据见 02/03）

审计方法：上游代码用 `git show v0.72.0:<path>` / `git diff v0.70.0 v0.72.0`，fork 现状读合并工作树；数据路径按 provider fetch/plugin → `UsageSnapshot` → `SyncCoordinator` → Shared `ProviderUsageSnapshot`（CloudKit opaque JSON）→ iOS 卡片/详情/widget 追踪。两份独立只读审计（数据通道、新 provider 落点）结论已合入下表。

| 上游变更 | Mac 数据路径 | fork 同步现状 | iOS 决定 | 新 wire | CloudKit schema |
|---|---|---|---|---|---|
| WorkBuddy 新 provider（#4226/#4227） | plugin：`primary`（月度 credits %、`resetsAt`、`resetDescription` "X / Y credits left"）、`loginMethod`=plan、details "Credits"（Left/Total/Reserved）；descriptor `showsPrimaryBalanceDescription` | 通用 `buildProviderUsageSnapshot` 原样带过去；iOS 有 `resetsAt` 时不显示 `resetDescription`，丢失余额文字 | 支持：颜色 `#0DC8A6`、QuotaProviderList 尾部追加、detail 标签本地化、余额描述与 reset 同显 | 可选 `SyncRateWindow.balanceDescription` | 否（运行时 zone） |
| Muse (muse.ai) 新 provider（#4042） | plugin：`primary` 周用量 + "tokens left" 描述、`loginMethod` 档位、`subscriptionRenewsAt`、无标题 details 行（top-up，带 `progress`） | 文字带过去；行 `progress` 被丢 | 支持：颜色 `#0668E1`、QuotaProviderList、余额描述、top-up 进度条；`museai` 与已有 `muse`（Muse Code）严格区分 | 可选 detail row `progress` | 否 |
| LithosAI 新 provider（#4196）+ 菜单栏余额（#4230） | `cost{used: balance, limit: 0, period: "Prepaid credits"}`；details "Billing"（Balance / Today (UTC) / This month (UTC) / Spend） | `mapProviderAmount` default → nil，只剩 details | Mac 桥接把 `.lithosai` 并入 balance 分支，iOS 复用 `ProviderAmountCard`；"Prepaid credits" 本地化；无 rate window，不进 QuotaProviderList | 否（复用 providerAmount） | 否 |
| Grok 购买的 Extra Usage Credits（#4239/#4243） | `providerCost(used 0, limit 0, balance)` | `.grok` default → nil，到不了 iOS | Mac 桥接新增 `.grok`：`balance != nil` 时发布余额（含 0） | 否 | 否 |
| Claude 促销 cloud-session credits（#4194/#4214） | details "Cloud credits"，行 id `claude-cloud-credits`，value "$X of $Y remaining" / Expired / Unavailable，secondary "Expires <ISO>"，带 `progress`、`usageValue` | 纯文字穿过，id/progress/usageValue 丢失；iOS 原样显示英文与 ISO 时间，过期不会自动变化 | 支持：Shared 行增加可选 `id`/`progress`/`usageValue`；iOS 识别该行，本地化金额、到期时间，过期后按 Mac 观测的到期时间显示 Expired，不再显示进度 | 可选 row 字段 | 否 |
| Claude OAuth saved limit-reset credits（#4232） | OAuth 也产出 "Limit Reset Credits" 行 | `mapSyncedDetails` 对 Claude 按 label 过滤，新路径同样被过滤 | 无需改；补 OAuth 来源过滤测试 | 否 | 否 |
| Codex 周额度 reset 恢复（#4210/#4218）、resumed session（#4195）、catch-up（#3508） | rate windows、token snapshot | 现有映射自动生效 | 无需改 | 否 | 否 |
| Claude/Codex/Pi/Grok 成本扫描性能与修正 | `CostUsageScanner*`、Claude 缓存 | Claude 轴只能靠 fork `parserLogicVersion` 失效 | Mac：`parserLogicVersion` 18→19，parser hash 重新生成，0.70.0.1 hash 记为兼容前驱 | 否 | 否 |
| Usage & Spend 项目/独立 chat 分离（#4172/#4247）、Antigravity unknown 行（#4246）、额外 Gemini homes（#4177） | Mac SpendDashboard / Antigravity 本地历史 | sync cost summary 无项目维度；Antigravity daily breakdown 自动变化 | 不需 iOS 改动（iOS 无项目维度） | 否 | 否 |
| Reset 通知（#4138） | Mac 本地 session/weekly reset 通知 | 合并时保持 iOS QuotaTransition 推送在 restored 延后判定之前写出 | 本轮不新增 iOS weekly reset 推送（属于新功能，不是上游数据），记录为后续 | 否 | 否 |
| 上游 Mac fleet iCloud Sync（#4144/#4147/#4161/#4132） | 仅上游 `CloudSyncEngine`（Mac↔Mac 设置同步） | fork Mobile 同步通道独立；fork 引擎保留 `CloudSyncConstants.containerIdentifier` | 移植语义；push 注册需 `com.apple.developer.aps-environment`，fork 打包无该 entitlement → 安全跳过，保持拉取模式；不改打包脚本 | 否 | 否 |
| Widget accent（#4199）、BurnDown widget | Mac widget | iOS 色板已与菜单 accent 一致 | 只补 3 个新 provider 颜色 | 否 | 否 |
| 安全：CLI/helper 路径、Codex 发现（#4136/#4143）、cookie/SweetCookieKit 0.5.5、Keychain 重试、CPU（Surprise me） | Mac/CLI 本地 | 无 Shared 影响 | Mac 完整保留；iOS 无对应操作入口 | 否 | 否 |

## Mac 端必须补齐

1. `SyncCoordinator.mapProviderAmount`：`.lithosai` 并入 balance 分支；新增 `.grok`。
2. `mapDetails`：转发 row `id`/`progress`/`usageValue`（Shared 增加可选字段，nil 不编码，旧 payload hash 不变）。
3. 每个 rate window 发布 `balanceDescription`（descriptor 的 `showsPrimaryBalanceDescription` / `showsSecondaryBalanceDescription` 为真且描述非空时）。
4. 新 provider 全套：`AccountIdentityComputer` switch、`MockProviderInjector`（real borrowed IDs + simple profiles）、gatekeeper/计数测试、Mac `mobile_toggle_mock_subtitle` 计数。

## iOS 实现清单

- `ProviderColorPalette`：museai `#0668E1`、lithosai `#6B7280`、workbuddy `#0DC8A6`（精确 ID + 显示名归一化）。
- `QuotaProviderList` 尾部追加 museai、workbuddy（LithosAI 只有余额，不加）；计数 81→83、243→249。
- `ProviderDetailLocalization`：firstParty IDs + 新标签（Total、Payment card、Account status、Today (UTC)、This month (UTC)、Spend、Additional tokens、Cloud credits 等）四语言。
- `UsageCardView`：显示 `balanceDescription`。
- `ProviderAmountCard` period 本地化 "Prepaid credits"。
- 详情行进度条与 Claude cloud credits 专门呈现。
- 版本 2.6.0 (235)、CHANGELOG、MobileReleaseNotesCatalog 四语言。

## 风险

- `parserLogicVersion` 19 会让 Claude/Codex 本地历史一次性重扫，CPU 峰值属预期。
- 新增 `balanceDescription` 会改变约 20 个使用余额描述的 provider 的 payload hash，升级后一次性重新上传。
- 新 provider 的实时账户数据无法在本机验证（无对应账户），以 parser/mapper fixture 与 mock 注入替代。
