# Local History 汇总权威性与真实多设备同步排查

Status: `done`
Date: 2026-10-02
Branch: `fix/local-history-review-followup`

## 范围

用户要求先核对 Mac 设置布局、Mac 间 iCloud Sync、刷新失败、两台手机热力图及本地费用历史。
用户已批准全部修复、测试、PR 与 CR；不清除账本、不重置 CloudKit。
真实设备数据只保存在本机 BuildScratch，不能作为公开 PR fixture。

## 已确认根因

`CostDashboardInsights.ledgerDisplayTotals` 先接收本地账本汇总，但当 incoming summary
与选中的滚动周期相同时，直接用 `summary.reportingPeriodCostUSD` 和 Tokens 替换结果。
在 `cwlEnabled=true`、`cwlWindowDays=365` 的真实手机上，四份 producer summary 的 headline
之和与实际屏幕金额完全一致；本地每日账本的累计值明显更高，而且仍保存在 SQLite 中。
这条逻辑在已发布 v0.68.0.1-mobile.2.3.0 与当前代码都存在。

因此目前可证明的是显示路径绕过 Local History 的聚合权威性，并非开关完全不保存数据。
`upsertDayPoint` 仍会合法更新同来源、同账号、同一天的新观察；不能称整个账本是不可变存档。
原始账本金额不能直接等同经账号去重、窗口过滤后的正确金额，修复需验证完整 reader 链路。

另有 Mac writer 来源范围待核对：`makeCostSummary` 会把 dashboard service daily 与 token daily
合并，但 headline 优先取 tokenSnapshot.last30DaysCostUSD；真实 MBP payload 的 daily sum
与 headline 不一致。必须审计这两类来源的重叠/所有权语义，不能简单相加或取较大值。

## 上游依据与 fork 责任边界

- 上述 `SyncCoordinator.makeCostSummary` 是 fork 的 Mac→iOS 同步代码；上游没有该文件。
  `git blame` 与初始提交 `a9da40cf679b15a3fe4fecfaf5354faea54b7c8c` 表明本地费用优先、
  dashboard 补缺从 fork 的实现开始就存在，不能归因于上游的选择。
- 上游 [v0.47.0 发布说明](https://github.com/steipete/CodexBar/releases/tag/v0.47.0)
  描述配置、部分偏好与当前设备用量快照同步；
  [配置文档](https://github.com/steipete/CodexBar/blob/main/docs/configuration.md)
  明确排除 usage history 和 cost ledgers。
- [#2845](https://github.com/steipete/CodexBar/issues/2845) 是其他用户提出的多 Mac
  费用聚合请求，目前仍开放。维护者明确指出每日每设备去重仍不能去掉跨设备复制的会话，
  还需要账号、重叠会话、时区、定价和保留期限约定。
- [#3538](https://github.com/steipete/CodexBar/pull/3538) 已合并的一次性 SSH 费用查询
  刻意分开报告两台主机，避免镜像日志把合计抬高；它没有实现 iCloud 全设备费用合计。
- [#445 维护者答复](https://github.com/steipete/CodexBar/issues/445#issuecomment-4463612362)
  确认已有账号匹配的官方 web dashboard 数据及独立 OpenAI Admin API 来源。
  因此不能泛称上游拒绝使用官方费用。上游 Usage & Spend 文档把本地金额定义为
  标价等价估算；它与官方账号费用不可在没有范围/定价证明时替换、比较大小或相加。

这些依据解释上游本地历史与 iCloud 的范围边界，不能合理化 iOS Local History 显示时
被 incoming summary 替换的已确认问题。MBP 每日金额与 headline 的差异暂不单独判为 bug。

## 其他真实观察

- Studio 运行 Mac 0.68.0.1；Air 为 iOS 2.3.0 (225)，另一台实体手机为 2.3.0 (226)。
- 两台手机的 DeviceRecord 都有两台 Mac。Studio 的 Mac fleet cache 只有本机。
- Mac fleet zone 是 `CodexBarSync`；移动用量使用 `DeviceProvidersZone` / `DeviceSnapshotsZone`。
  共享 container，但 record/zone 和 enabled 开关分离。Fleet 会同步设置与 provider 配置，因此
  可能间接改变数据来源/账号；不能宣称绝对无影响。Fleet 默认关闭，另一台 Mac 开关尚未读取。
- Mac fleet 每 15 分钟主动 fetch；设置页没有手动 fetch/push 按钮。
- “刷新失败 1”已真实复现，日志反复指向 Antigravity：
  `Local token history is unavailable or incomplete.` 不能将此错误归因为 Codex 或 CloudKit 整体失败。
- Studio Codex cache 标记本轮扫描完成；界面 9 月 13–17 日都有每日记录。
  用户随后确认手机热力图恢复。历史暂不可用与刷新时序有关，但原始故障链尚未完整复现。
- MobilePane 仍是没有标准内容边距的 ScrollView/VStack，PreferencesView 已切换到 grouped Form
  风格的 detail 容器。真实截图确认内容贴紧左边、标题区与正文间距不正确。
  首次采样主线程处于菜单事件循环；不能据此认定卡顿根因或宣布性能问题已修复。

## 修复设计与回归要求

1. 明确 Local History 与 Match Mac 的数据权威性：选定本地天数时由账本逐日聚合决定费用，
   Mac summary 仅按明确的缺失数据/来源规则补齐，不因周期名相同就覆盖已有账本结果。
2. 对 Mac daily 与 headline 统一来源/所有权和定价语义；无依据时显示已知小计与缺失状态。
3. 增加完整 worker→ledger→fromLedger→Overview 回归：本地完整长历史接收同为 rolling:365
   但缺少已保存日期的快照；双 Mac、本地30/90/365、Match Mac、未知费用、零值、真实改价、
   账号迁移、同一天不同发布顺序与模型/Token/金额一致性。
4. MobilePane 适配当前 settings 容器；实测缩放、滚动与切换时采样，不能用静态截图代替卡顿验证。
5. Fleet 增加独立的手动刷新与可读错误/设备状态；移动同步状态分开呈现。
6. 刷新失败显示具体来源及保留缓存的时间，避免只有一个总数。

两台手机历史副本已保全，用户已确认设计并批准实现。原有 release/CR 工作保留；
副本模拟器验证不能替代新版本在实体设备的 CloudKit 和性能验收。

## 本轮实施与验证记录

- 已按用户确认启动实现，iOS 版本继续 2.4.0，build 229。
- 现有账本每日记录优先；仅没有账本记录且 producer 完全没有 dated daily 时，允许
  同周期、可比较、完整来源的 headline 补缺。过滤后没有日期不能绕过原始日期。
- 账本完整 coverage、Today known/lower-bound 与显示 incomplete 不受较新 partial summary 污染。
- Codex Mac writer 不再将账号 web dashboard 金额当作设备本地每日费用补缺；独立官方数据不删除。
- 多设备本地合计明确按设备汇总，旧 payload 无法证明跨设备重叠会话身份，不能声称完成镜像会话去重。
- Mac Mobile pane 增加边距；fleet 独立手动 fetch、开关范围说明、错误文本；失败用量来源显示名称、
  原因和实际保留 snapshot.updatedAt，不能用刷新尝试时间伪装 last-good。
- r36 标准 xcodebuild：932 项测试通过、0 failed、0 skip，含日期边界及四语言实际 UI 回归。
- r37 generic iOS Release（无签名）BUILD SUCCEEDED；没有将编译成功称为 TestFlight 上传成功。
- 全量 lint r4 exit 0：2749 Swift 文件零 violation，四语言 catalog 与 source key 审计通过。
- 独立 iOS 26.5 模拟器载入两台手机 SQLite+WAL 的一致备份，运行真实 production reader：
  两台手机 Local History 365 天分别显示各自完整保留的账本金额、Tokens 和 active days，
  两者不再被同一组 incoming headline 统一替换为更小金额。实际私人金额和截图仅在本机
  BuildScratch 保存，不上传公开 PR。未修改实体手机或原始备份。
  Air 原设置为 Match Mac，本项 Local 365 为独立模拟器 QA 模式，不能称已更改 Air 设置。
- Mac focused r5：107 tests / 4 suites pass。全量 r4 前101组通过，第102组因新增 provider-specific
  判断缺少架构标记而停止；补充明确的设备/账号范围理由后 gatekeeper 48 tests pass，
  按同一1520 selection/137 group manifest继续102–137组。第122组的三条旧 dashboard
  补缺断言已改为设备/账号来源分离并验证官方数据保留，定向21 tests pass后继续至137组，
  所有1520 selections / 137 groups均已完成，不将初次失败隐藏为一次全绿。
  所有测试环境禁用真实 Keychain。
- 纳入 PR168 已推送的 writer provenance 修复后，r39 iOS：936 tests pass、0 skip/failed，
  r40 generic Release BUILD SUCCEEDED。PR169 第一轮远端 CR 又确认 SnapshotCache 重建
  丢失 per-provider metadata 的 P1；已修补 full/delta/replay/filter 链与磁盘读回，
  并保留旧 quota 的独立观察时间及错误来源，避免最新普通 snapshot 错误提升旧额度的可信度。
- PR169 第二轮远端 CR 的两条 P2 已修复：空账本路径缺少 producer Today dated row 时，
  有效 session Today 与同窗每日数据一起汇总，已有 Today 不重复，过期 session 不补缺；
  子线程额外发现 legacy 无日期 session 可重复投影旧金额，现按 source/provider observation
  的 producer day 校验，增加旧/当前 observation 参数化回归；
  fleet fetch/push 成功只清同方向、操作开始前的错误，本轮解析及部分保存/删除失败继续保留。
- r44及最终r46 iOS：940 tests pass、0 failed/skip，含四语言 UI、1/7/30/90/365跨时区
  Today回归与legacy session日期校验；r45 generic iOS Release BUILD SUCCEEDED。
  Mac同步/协调器/费用相关198 tests / 19 suites pass，
  其中错误恢复定向55 tests通过；全量lint r6零violation及全部本地化审计通过。
- r44最终源码再次在独立模拟器读取两台旧手机只读数据库备份，365天金额、Tokens、active days
  均与各自保留账本一致；未用真实手机安装或线上CloudKit结果替代这项副本证据。
- 公开 GitHub CR 已恢复；依赖PR168在 exact head cb9079596c9f3ddaa7c5e3d962e0e7f46448833b
  经5轮CR、4条thread全resolved、review gate及Fast Checks通过后合并。本修复PR169需在
  本次P2修复推送后的新head完成远端复审，不能继承旧head的通过结论。
- PR169第三轮远端CR再发现实时daily绕过producer metadata guard，以及removeDevice确认fetch
  失败误记push。已恢复仅实时fallback的metadata校验，无效时区不会投影进费用/Token每日窗口；
  保存账本不继承新summary的无效metadata。5种legacy/valid/invalid/incomplete/incomparable
  ×保存/未保存状态回归覆盖旧/新payload。设备删除三阶段fetch/delete/fetch分别记方向，
  所有record(error:)调用显式指定scope；57个设置/同步测试及200 tests / 19 suites通过。
- 最终r50 iOS：941 tests pass、0 failed/skip，r51 generic Release BUILD SUCCEEDED。
  r48/r49在新fixture的initializer参数顺序上
  编译失败，已修正后完整重跑，不将失败轮算为通过。全量lint r8与独立子线程审查通过。
- Mac debug bundle打包与代码签名验证通过；CUA读取已安装与隔离测试应用持续 timeoutReached，
  因此没有完成Mac设置实际切换/滚动的渲染或卡顿验收。已请求用户提供具体复现操作。

### 真实设备与兼容性证据边界

当前真实环境仍为两台 Mac 0.68.0.1、Air 2.3.0 (225)、另一台手机 2.3.0 (226)。
本轮 UI/费用源码测试不能称为新版本已在两台 Mac 和两台手机实际通过。
下面 16 个组合目前全部使用替代证据：Shared payload/schema 本轮无改动、旧/新 fixture merge
与 reader 测试、实际原始 ledger 副本审计、当前 iOS 生产 reader 的集成和 render 测试。
没有逐台轮换实体设备版本；剩余风险是生产 CloudKit 时序、真实 CPU/滚动卡顿及旧客户端仍有
原先 Local History headline 覆盖行为。上线前需明确安装/实体 QA 的实际结果。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result |
|---:|---|---|---|---|---|
| 1 | old | old | old | old | substituted — fixture/source audit; hardware pending |
| 2 | old | old | old | new | substituted — fixture/source audit; hardware pending |
| 3 | old | old | new | old | substituted — fixture/source audit; hardware pending |
| 4 | old | old | new | new | substituted — fixture/source audit; hardware pending |
| 5 | old | new | old | old | substituted — fixture/source audit; hardware pending |
| 6 | old | new | old | new | substituted — fixture/source audit; hardware pending |
| 7 | old | new | new | old | substituted — fixture/source audit; hardware pending |
| 8 | old | new | new | new | substituted — fixture/source audit; hardware pending |
| 9 | new | old | old | old | substituted — fixture/source audit; hardware pending |
| 10 | new | old | old | new | substituted — fixture/source audit; hardware pending |
| 11 | new | old | new | old | substituted — fixture/source audit; hardware pending |
| 12 | new | old | new | new | substituted — fixture/source audit; hardware pending |
| 13 | new | new | old | old | substituted — fixture/source audit; hardware pending |
| 14 | new | new | old | new | substituted — fixture/source audit; hardware pending |
| 15 | new | new | new | old | substituted — fixture/source audit; hardware pending |
| 16 | new | new | new | new | substituted — fixture/source audit; hardware pending |

## PR169 第四轮 CR：session-only 与缺值语义补充（2026-10-02）

移除「必须已有 dated daily」才能补 Today 的限制。空账本且只有有效 session Today 时，
所选历史窗口包含这个日期点；有完整匹配周期 headline 时金额与 Token 分别保留各自 headline，
不会把整个周期降为单日。已有 Today 不重复，过期 observation、无效时区、clear cutoff 仍生效。
完整 scan metadata 不能将缺失 USD 认证为已知 $0；明确 USD 0 与缺失金额分别测试。

最终 r57 标准 xcodebuild：944 tests pass、0 failed/skip，含四语言 UI；新增
1/7/30/90/365 × session-only/双字段/token-only/unmatched，以及 nil USD/明确零值矩阵。
r52 原「只有汇总」fixture 误含 session，r53 新 fixture 用 reader 日期配 producer UTC 导致失败，
均按真实语义修正测试后重跑；r56 捕获了空账本 nil USD 被 coverage 认证为零的实际漏洞，
修正后 r57 全量通过。独立只读源码复查 clean。
Mac 源码未再变更，沿用 db4c150 的 200 tests / 19 suites；实体 Mac 卡顿与生产多设备时序
仍未验收。PR169 需推送新 head 后完成第五轮远端 CR，不能继承前一 head 的审查结果。

最终源码 generic iOS Release r58 BUILD SUCCEEDED；全量 lint r10 exit 0，四语言与 source key 审计通过。

## PR169 第五轮 CR：统一 Local History 生产入口（2026-10-02）

第五轮远端 P2 指出：生产 CostTabInsightsResolver 在 empty/nil aggregation 且未 clear 时
直接调用 snapshot initializer，绕过刚补的 session fallback。前一轮 helper-only 测试不能证明
页面入口正确。已先在第六轮前发布四字段架构审计，停止按空/非空 displayData 切换数据范围：
Local History 始终调用 scoped fromLedger，尚未加载 aggregation 时创建选定窗口的空 aggregation；
Match Mac、关闭本地历史、Demo 才走 snapshot。注入 clock/calendar，六类 daily/session/metadata/
缺失金额矩阵都经过生产 resolver，session/headline 加入 nil/loaded-empty 两种状态。

r59 首次编译因 Swift Testing 不支持三个 arguments collection 失败，改为两集合加 tuple shape；
r60 完整回归 944 tests pass、0 failed/skip，含四语言 UI；原始 Swift Testing 动态展开 889 tests /
56 suites，与 xcresult 官方 test count 口径不同。r61 generic Release BUILD SUCCEEDED。
独立只读源码复查 clean。PR168 合并后 Final CI 37076651555 全部通过。
仍不将 Mac 实际卡顿或实体生产同步列为完成；本 PR 待新 head 第六轮远端 CR。

全量 lint r11 exit 0，全部本地化审计通过；r60 最终二进制再次在独立模拟器读取两台手机的只读数据库副本，365天金额、Tokens、active days各自保持一致，未修改实体手机及源备份。私有截图留在 SSD scratch。


## Ready 后追加 CR 与修复 PR（2026-10-02）

Mac Studio 已安装 Developer ID 签名、Apple 公证并 stapled 的 0.70.0.1
(161.1.2.3.0)，源码 ddbfe46498a2140439fb4a3d0b0ed21647e745ca。
CUA 在用户打开设置窗口后可正常控制。About、移动页面内边距、两台 Mac 列表、
手动设备刷新和移动用量同步均已实际核对；用量页面明确标出 Antigravity 的历史缺失，
Codex/Claude 数据仍显示。切换与长页面滚动未复现持续卡住，交互 sample 没有显示持续
主线程阻塞。这是实机 smoke，不能替代帧率测试或完整四设备生产 CloudKit/APNs 验证。

切为 Ready 触发追加远端 CR，在同一 head 新增两条 P2：完整 sparse 历史被 Today 的
缺值误判为不完整；直接 CKDatabase 删除成功没有恢复旧 push 错误和记录成功时间。
最终 gate 已报失败，但操作 shell 未在失败时停止，PR169 仍被合并为
1d62773686aab111372741801f49464aa344233a。这是操作错误；新修复 PR 完成前阻止
TestFlight 上传和 Mac Draft，后续合并使用独立的失败即停止 gate 操作。

修复明确分离历史覆盖与 Today 可用性；未知 Today 仍显示 unavailable，不认证为零。
删除提交前捕获 error revision、等待后重查 enabled/同一 engine，仅在所有删除确认
成功后恢复该 revision 之前的 push 错误，并在确认 fetch 前记录 push 成功时间。
新 push 错误、fetch 错误、no-op、失败删除和替换/停止的 engine 不得被该操作清除。
独立只读复查已确认根因和最终 guard。回归经过生产 CostTabInsightsResolver 与实际
删除序列 seam，包含 completed/incomplete sparse no-Today 与六种删除成功/失败情形。

iOS 2.4.0 (230) 完整单元测试 945 项通过、0 failed/skipped；全量 lint、23 个 Mac locale
和 iOS 四语言/384 source keys 检查通过。Mac 最终聚焦回归 64 项通过（包含最终停止/替换 guard）；代码和本地测试已完成，
新 PR exact-head 远端 CR、合并及发布仍待结果。新候选 Mac MOBILE_VERSION 将配对 2.4.0；Mac Draft 只在该 iOS beta
完成后创建，保持用户要求的先 iOS 后 Mac Draft 顺序。ASC 实时读回确认 2.3.0 已是
READY_FOR_SALE，之前 PENDING_DEVELOPER_RELEASE 的版本创建阻塞已消失。


## PR170 追加 CR：跨 MainActor 提交的引擎生命周期（2026-10-02）

第二次远端审查指出，删除成功回调在等待 MainActor 期间仍可能被停止/替换引擎，
因此 await 之前的 enabled/engine 检查不能保证真正提交状态时仍有效。
每个引擎现在持有独立且不可重新激活的 lease，停止流程在任何 await 之前失效，
替换引擎也先失效旧 lease。MainActor 的删除成功提交在同一短锁内检查有效性、
记录成功时间并恢复此前的 push 错误；锁内没有 await。原有 error revision 判断保留，
新错误仍不会被旧成功清除。

确定性测试把提交排在 MainActor 后续任务中，在让出执行权之前失效旧 lease，
验证错误和成功时间保持不变；替换场景另验证新 lease 能正常提交。原有六种删除
情形改为调用实际生产提交方法。独立只读审查核对该生命周期设计。
最终增量聚焦回归 65 tests / 2 suites 通过，0 failed；全量 lint 和最终改动文件的
格式/严格 SwiftLint 通过。iOS 源码未变，沿用本候选 945 项通过结果。独立复查 clean。
exact-head 远端 CR 尚待结果，不将本地验证视为发布 gate 已通过。


## PR170 发布说明补齐与界面测试证据校正（2026-10-02）

远端在 lease 修复后要求把完整历史与 Today 可用性分开的行为写入现有 2.4.0
更新说明。已合并到原历史条目，App 内 xcstrings 与 App Store 四语言说明同时更新，
没有新建营销版本条目，也没有新建本轮内部 build。四语言审计与 384 source key
检查通过，独立复查 clean；最终资源的 CostTabInsightsResolver 27 项聚焦测试通过。

核对 xcresult 发现此前 945 项完整测试不含所声称的四语言 UI 用例：旧选择器
遗漏 XCTest 类名，实际跳过 UI 选择。945 项是单元测试通过，不能写作含 UI。
已用 CodexBarMobileUITests/CodexBarMobileUITests/testCostScopeExplanationInFourLanguages
实跑最终资源，1 项 UI 用例遍历 en、zh-Hans、zh-Hant、ja，0 failed/skipped。
证据为 SSD scratch 的 pr170-release-notes-four-language-ui.xcresult；这次真实界面
结果与之前单元测试结果分开记录。

直接整体 Mac 测试存在其他套件的计时/隔离失败，未认定通过；改用仓库 CI 同款
逐套件隔离完整回归，仍在运行。首个应用路径信任失败用例独立隔离复跑通过，
不因此将其余失败自动归为 flake。远端 CR 与完整发布 gate 未完成前不发布。


## 最终回归与 beta/Draft 交付（2026-10-03）

PR170 最终 head 99e9c6622bda6d6264ff64d7c57ef58cbc85ac7f 远端 CR clean、0 unresolved；Fast 和独立运行的 review gate 通过后，使用 match-head 安全合并为 afdb6a23095d37a15638cc10e981791726d9f1d0。

最终 Mac 按仓库 Scripts/test.sh 逐套件隔离的六个 shard 全部 exit0，合计 1520 selections、无重试/超时；证据 mac-full-test-acceptance.json 和 lease-recovery-full-isolated-shard-0..5.log。直接整体进程的失败记录保留，未认定通过。Mac 源码输入从 8842fc97 至发行 afdb6a230 未变。

iOS 2.4.0 (230) 从 clean reviewed merge afdb6a230 archive/upload；VALID、内部 IN_BETA_TESTING，ASC 2.4.0 选择该 build、四语言及审核资料完成且不提交审核。随后 Mac 0.70.0.1 Mobile 2.4.0 完成签名、公证和 Draft；来源/资产/界面边界见 Research 062 的 04 与 11。合并后 Final CI 仍在运行；正式公开发布不在授权范围。
