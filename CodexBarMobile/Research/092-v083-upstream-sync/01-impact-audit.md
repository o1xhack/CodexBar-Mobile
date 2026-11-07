# 上游逐项影响追踪

状态：done；测试结果见03。完整380文件路径与提交在evidence。此表逐项覆盖冻结release notes，并结合实际diff审计。

| 项 | 上游变化 | Mac / Shared / iOS 决策 |
|---:|---|---|
| 1 | Plugins: plugin providers now use the full menu-bar layout (inheriting your global layout, with countdowns and conditionals), can show compact multi-quota summaries and a built-in provider logo, declare an approved Usage Dashboard link, and import cookies from every supported browser including Aside. | Mac菜单完整合并。iOS以自身卡片/窗口列表展示完整额度；不复制Mac菜单布局、分隔符、紧凑图标。动态plugin logo不作为provider身份或quota所有权，保留plugin独立monogram/tint；无数据通道丢失。 |
| 2 | Codex: cost history survives Codex archiving old sessions as `.jsonl.zst` and switching between Codex homes, GPT-6.1 Sol Fast requests are priced at Fast rates, accounts can have custom names, and opt-in reminders warn before an unused weekly quota resets or reset credits expire. | Mac成本解析/缓存实现完整合并；既有costSummary/daily/provenance通道，Mac真实录入数据和iOS展示沿用；测试迁移/归档/多home/Fast。SSH CLI聚合不自动导入iPhone账本，避免重复所有权。 |
| 3 | Providers: new OpenDesign subscription quotas; Kiro works with Kiro CLI 3; Perplexity organization credits, WorkBuddy reward credits, LiteLLM team budgets, MiniMax China, Copilot monthly pace and ended subscriptions, and Brave Origin sign-in are supported. | 新增 provider：既有 rateWindows/quotaLimit/quotaUnit/accountOrganization；追加通知清单、mock与颜色。无历史接口，不伪造曲线。 |
| 4 | Menu bar and CLI: pace defaults to neutral percentages with green/red state bars, layouts gain separator glyphs, `codexbar serve` clients can request fresh measurements, and identified Codex requests can be priced across several SSH hosts. | Mac菜单pace/分隔符和CLI serve/fleet能力完整合并；iOS沿用自身pace估算、quota窗口和cost/provenance消费者。CLI SSH聚合只用于所请求命令，不自动写入iPhone账本，防止跨host重复计费。 |
| 5 | CLI: expose descriptor-based authentication inputs and existing setup hints in provider inventory JSON. (#4705) | 仅CLI inventory的认证元数据/setup hints；iOS不读取CLI inventory，也不在手机收集Mac provider凭据，无需新增Shared字段。 |
| 6 | Plugins: support an explicitly approved Usage Dashboard link from a fixed URL or a plain setting. (#4725) | plugin显式批准的Dashboard链接由Mac菜单提供；授权绑定仍在Mac，iOS不推断或自动打开未进入现有同步payload的plugin URL。额度同步不依赖该链接，无schema变化。 |
| 7 | Codex: optionally add reset-credit expiry reminders at 1 day and 1 hour, preserving the existing three-day summary and saved receipts (#4838). Thanks @PumpkinsLemon! | Mac本地账号名称/提醒完整合并；名称设置不进入fleet偏好，也不替代Shared账号身份，iOS继续独立显示/通知设置；既有resetCreditInventory语义不变。 |
| 8 | CLI: combine identified Codex requests from multiple SSH hosts, counting copies once and keeping successful sources when a host fails (#4834). Thanks @salmonumbrella! | Mac/CLI/工具实现完整合并；hooks planObservation为原始采样出处，不从显示标签推断额度，也不需要iOS hook消费者。无Shared schema变化。 |
| 9 | CLI: estimate deduplicated Codex request spend across SSH hosts with explicit unknown prices, conflict exclusions, and a coordinated schema 2 upgrade (#4833, #4836). Thanks @salmonumbrella! | Mac成本解析/缓存实现完整合并；既有costSummary/daily/provenance通道，Mac真实录入数据和iOS展示沿用；测试迁移/归档/多home/Fast。SSH CLI聚合不自动导入iPhone账本，避免重复所有权。 |
| 10 | Plugins: render global menu-bar layouts with plugin-owned windows, reset countdowns and conditionals, preserving saved plugin overrides (#4789). | Mac菜单完整合并。iOS以自身卡片/窗口列表展示完整额度；不复制Mac菜单布局、分隔符、紧凑图标。动态plugin logo不作为provider身份或quota所有权，保留plugin独立monogram/tint；无数据通道丢失。 |
| 11 | OpenDesign: track the active workspace's five-hour and weekly subscription allowance through its browser session (#4601). Thanks @vimcaw and @irfndi! | 新增 provider：既有 rateWindows/quotaLimit/quotaUnit/accountOrganization；追加通知清单、mock与颜色。无历史接口，不伪造曲线。 |
| 12 | Plugins: let each snapshot choose a built-in provider logo for its menu bar and switcher, independently of plugin identity and quota ownership (#4801). Thanks @KLIEBHAN! | Mac菜单完整合并。iOS以自身卡片/窗口列表展示完整额度；不复制Mac菜单布局、分隔符、紧凑图标。动态plugin logo不作为provider身份或quota所有权，保留plugin独立monogram/tint；无数据通道丢失。 |
| 13 | Plugins: show compact multi-quota summaries with ordered logos and quota percentages in the merged menu bar (#4802). Thanks @KLIEBHAN! | Mac菜单完整合并。iOS以自身卡片/窗口列表展示完整额度；不复制Mac菜单布局、分隔符、紧凑图标。动态plugin logo不作为provider身份或quota所有权，保留plugin独立monogram/tint；无数据通道丢失。 |
| 14 | Codex: optionally warn 24 hours and 1 hour before a weekly reset when quota remains, with account-scoped reminders that survive restarts (#4849). Thanks @hugo-alves! | Mac本地账号名称/提醒完整合并；名称设置不进入fleet偏好，也不替代Shared账号身份，iOS继续独立显示/通知设置；既有resetCreditInventory语义不变。 |
| 15 | Menu bar: add eight separator glyphs to layouts and conditional branches, with spoken accessibility names and safe downgrade projections (#4795). Thanks @urda! | Mac菜单完整合并。iOS以自身卡片/窗口列表展示完整额度；不复制Mac菜单布局、分隔符、紧凑图标。动态plugin logo不作为provider身份或quota所有权，保留plugin独立monogram/tint；无数据通道丢失。 |
| 16 | Codex: name saved accounts in Settings and account menus without changing authentication or cached usage; privacy mode hides aliases. (#4782) Thanks @shirishpothi! | Mac本地账号名称/提醒完整合并；名称设置不进入fleet偏好，也不替代Shared账号身份，iOS继续独立显示/通知设置；既有resetCreditInventory语义不变。 |
| 17 | Hooks: `usage_updated` events can carry the sampled raw Codex plan identifier, the provider surface that reported it, and the observation time, without inferring allowances from display labels. (#4775, #4800) Thanks @LeoLin990405! | Mac/CLI/工具实现完整合并；hooks planObservation为原始采样出处，不从显示标签推断额度，也不需要iOS hook消费者。无Shared schema变化。 |
| 18 | WorkBuddy: show platform reward credits separately within the total allowance, with the earliest unspent grant’s expiry and no false allowance reset when rewards expire. (#4799) Thanks @codertesla! | 既有 extraRateWindows/rewards 与 details/Reward expiry；奖励是总额子集，不累加、不当作 reset；补四语。 |
| 19 | Codex: apply GPT-6.1 Sol Fast pricing, including long-context requests, and refresh request tiers when a turn resumes. (#4814) Thanks @cassiarota! | Mac成本解析/缓存实现完整合并；既有costSummary/daily/provenance通道，Mac真实录入数据和iOS展示沿用；测试迁移/归档/多home/Fast。SSH CLI聚合不自动导入iPhone账本，避免重复所有权。 |
| 20 | LiteLLM: show member overrides or the team's default budget with matching team-scoped spend, ignoring mismatched memberships (#4842, #4843). Thanks @cnietoc! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 21 | Claude: isolate watchdog children at spawn, preserve their exit status, and clean up only session-owned processes and sleep inhibitors (#4829, #4830). Thanks @Quinnod345! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 22 | Plugins: import declared-domain cookies from the shared supported-browser catalog, including Aside, and continue through rejected sessions (#4792). | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 23 | z.ai: show prepaid CNY balances for BigModel CN personal accounts without a Coding Plan, including the shared menu-bar Balance element (#4796). Thanks @AaronJiTuo! | z.ai CN预付CNY余额由zai.js输出Quota details/Account balance，沿既有details与localizeZAIBalanceBreakdown展示人民币；不新增providerAmount，不折算USD、不推断Coding Plan。 |
| 24 | Cursor: support Brave Origin for browser login and shared cookie imports with SweetCookieKit 0.5.11 (#4837). Thanks @retX0! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 25 | AWS Bedrock: report unavailable Cost Explorer data instead of zero spend (#4846). Thanks @djbclark! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 26 | Claude: report the CLI's unavailable per-model breakdown in usage details while retaining current session and weekly quotas (#4809). Thanks @DreamyTalesPAN! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 27 | iCloud Sync: retry account snapshots after a dropped upload without allowing delayed results to confirm newer data (#4798). Thanks @audichuang! | Mac fleet CKSyncEngine重试完整合并；保留fork记录缓存/删除清理与迁移处理，旧/新Shared格式不变。 |
| 28 | DeepSeek: import Platform sessions from supported Chromium browsers using the shared browser catalog, preserving saved Chrome profile selections (#4821). Thanks @343max! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 29 | Trae CN: align Used, Total, and Remaining credits to two decimal places when any amount is fractional (#4819). Thanks @liuyuplus! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 30 | MiniMax: discover China web sessions and read the current console's quota percentages, boosted limits, and unlimited windows. (#4831, #4832) Thanks @tangwz! | 既有 rateWindows、Quota services details，Unlimited说明与无reset语义；不捏造额度上限。 |
| 31 | Localization: correctly validate reordered plural arguments after ordinary placeholders. (#4817) Thanks @xuancao1953-1! | Mac/CLI/工具实现完整合并；hooks planObservation为原始采样出处，不从显示标签推断额度，也不需要iOS hook消费者。无Shared schema变化。 |
| 32 | Codex: preserve established local cost coverage and catch-up progress when switching Codex homes (#4770, #4773). Thanks @harjothkhara! | Mac成本解析/缓存实现完整合并；既有costSummary/daily/provenance通道，Mac真实录入数据和iOS展示沿用；测试迁移/归档/多home/Fast。SSH CLI聚合不自动导入iPhone账本，避免重复所有权。 |
| 33 | Menu bar: name the Auto window once per row, so Auto % with Auto pace shows `5h 0% –` instead of `5h 0% 5h –`; separate rows, other windows, and VoiceOver keep their labels (#4820, #4822). Thanks @egigoka! | Mac菜单完整合并。iOS以自身卡片/窗口列表展示完整额度；不复制Mac菜单布局、分隔符、紧凑图标。动态plugin logo不作为provider身份或quota所有权，保留plugin独立monogram/tint；无数据通道丢失。 |
| 34 | OpenCodex: reduce temporary memory use when importing large usage logs (#4803). | Mac成本解析/缓存实现完整合并；既有costSummary/daily/provenance通道，Mac真实录入数据和iOS展示沿用；测试迁移/归档/多home/Fast。SSH CLI聚合不自动导入iPhone账本，避免重复所有权。 |
| 35 | Copilot: show calendar-month pace for Premium and chat quotas in the menu bar when a reset date is available (#4847, #4848). Thanks @chriscorbell! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 36 | Cursor: explain when the Cursor app session has expired and no browser session works, with steps to sign in again (#4804). Thanks @julianpinedayyz! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 37 | Perplexity: show organization pool credits separately and use them for automatic usage after personal credits run out (#4826, #4828). Thanks @Abelo9996! | extraRateWindows/org-credits；Mac菜单自动选择可用组织池；同步保留native槽顺序并尾部追加组织池，iOS独立显示全部额度池，避免旧客户端按index绑定通知marker时错位；真实producer桥接测试覆盖顺序/组织池可用值。 |
| 38 | Plugins: refresh the selected menu-bar percentage when its usage changes while the automatic window stays unchanged (#4787). Thanks @vincent-peng! | Mac菜单完整合并。iOS以自身卡片/窗口列表展示完整额度；不复制Mac菜单布局、分隔符、紧凑图标。动态plugin logo不作为provider身份或quota所有权，保留plugin独立monogram/tint；无数据通道丢失。 |
| 39 | Codex: retain cached cost history when previously scanned rollouts become `.jsonl.zst` archives, without duplicate counting (#4523, #4534, #4818). Thanks @BananaIIya, @kali113, @kcharlan, and @cassiarota! | Mac成本解析/缓存实现完整合并；既有costSummary/daily/provenance通道，Mac真实录入数据和iOS展示沿用；测试迁移/归档/多home/Fast。SSH CLI聚合不自动导入iPhone账本，避免重复所有权。 |
| 40 | OpenCode Go: use the active OpenCode CLI API key stored under `opencode` for server quotas instead of falling back to local estimates. (#4815) Thanks @sreejithraman! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 41 | Copilot: explain ended subscriptions instead of showing a raw decoding error. (#4851) Thanks @djbclark! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 42 | Kiro: prefer stateless usage reads to avoid probe chats when available, and use the V2 harness with older-CLI fallback when a CLI report is needed. (#4853, #4854, #4746) Thanks @jeanroloff! | 上游provider/认证/状态实现完整合并；既有quota/details/statusMessage/providerAmount通道承载结果，iOS不执行Mac浏览器/CLI认证；验证受影响provider测试。 |
| 43 | CLI: let HTTP clients request fresh usage and full dashboard measurements with `refresh=1`, coalescing concurrent requests and limiting forced measurements to one per provider every five seconds (#4785). | HTTP serve freshness请求合并与5秒限频在Mac CLI服务执行，完整保留；iPhone沿用现有CloudKit刷新路径，不成为该本地HTTP服务客户端。无Shared schema变化。 |
| 44 | CLI: malformed or ambiguous arguments now fail with an error instead of being guessed (Commander 0.3.0). | Commander参数验证只作用于CLI入口；iOS不解析CLI参数，无UI/Sync变更。 |
| 45 | Menu bar: make neutral pace percentages with font-scaled green/red state bars the default, preserving saved color choices (#4714, #4791). Thanks @arnodirlam! | Mac菜单完整合并。iOS以自身卡片/窗口列表展示完整额度；不复制Mac菜单布局、分隔符、紧凑图标。动态plugin logo不作为provider身份或quota所有权，保留plugin独立monogram/tint；无数据通道丢失。 |
| 46 | Updates: refresh Sparkle to improve update installation, download progress, and release-note handling. | Sparkle只用于Mac更新下载与安装，完整合并版本及固定依赖；iOS通过Apple分发更新，无Sparkle消费者或Shared schema影响。 |

## fork保护与README审计

merge提交逐字保持mobile-dev README。合并后单独审计并经独立审查，只适配provider数111、OpenDesign条目、WorkBuddy奖励以及已合并上游social.png的真实SHA256 cache token四处事实；guard hash随本次有意修改一起审查，不接收上游README整体、不改fork身份或下载入口。上游Mac提醒无安全/排错缺漏；social cache token从实际PNG内容计算，避免旧缓存与新图片不一致。CI策略、release脚本、签名与Production容器不变。

## Preview 与身份

OpenDesign是已有通用session/weekly卡片类型，PreviewData已有Codex/Claude通用窗口样例，故不重复添加预览；Mac mock含其两窗口。provider ID独立，不借用其他provider标识。OpenDesign工作区切换由来源快照整体替换，暂不做跨Mac工作区自动归并（identity computer为非TierA）；缺失登录不伪造身份。

## CloudKit代码审计

最新公开v0.82.0.1-mobile.3.2.0 → candidate：Shared/iCloud与Scripts/cloudkit无diff，providerPayloadVersion=1；Shared只追加OpenDesign通知注册，不改record type/field/index/predicate。Mac fleet重试只改写入确认和重试，不新增schema。结论NO_DEPLOY（代码审计），未执行Production export/deploy/业务数据库读写。最终Mac签名包和iOS本地Archive的Production entitlement均已核对，见04及evidence。

## 成本缓存与严格lint整合

fork parserLogicVersion由已发布24提升至25；最终parser hash为`c546274ea6111fa7`。CostUsageStore继续接纳已发布fork hash `2d777571778d8f12`及既有兼容前驱，保留native row/checkpoint；上游revision14的Fast pricing路径必须重新解析，旧12→13 metadata捷径不扩大到14。完整测试改为隔离的Codex store home，验证真实current contract。

严格lint的scanCodexFile复杂度通过提取原recovery可读性guard降到阈值内；helper无需恢复时直接允许，需恢复时仍先检fileId再检readability，deferred path和后续hydration时点不变。插件恢复/CLI两段测试移到同suite的独立文件，保留全部37个@Test与serialized隔离。架构gate只更新OpenDesign实际新增的精确引用指纹，未修改scanner、cluster规则或阈值。

## 旧iOS边界

旧iOS可按既有generic provider/window路径读取OpenDesign额度，但其冻结QuotaProviderList没有OpenDesign，不能自动建立新provider的通知zone订阅；该订阅能力随3.5.0客户端安装生效。本轮只完成本地3.5.0(263)Archive，未上传或交付到用户设备。Perplexity组织池作为额外窗口独立展示，原生personal槽位/旧通知index不重排；不把额外组织池伪装为已有personal通知阈值。
