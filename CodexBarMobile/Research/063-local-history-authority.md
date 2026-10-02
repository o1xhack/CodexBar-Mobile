# Local History 汇总权威性与真实多设备同步排查

Status: `in-progress`
Date: 2026-10-02
Branch: `fix/local-history-sync-authority`

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
  按同一1520 selection/137 group manifest继续102–137组，不将初次失败隐藏为一次全绿。
  所有测试环境禁用真实 Keychain。
- 纳入 PR168 已推送的 writer provenance 修复后，r39 iOS：936 tests pass、0 skip/failed，
  r40 generic Release BUILD SUCCEEDED。PR169 第一轮远端 CR 又确认 SnapshotCache 重建
  丢失 per-provider metadata 的 P1；正在修补实际 full/delta/replay/filter 链，最终 head 需重新验证。
- 公开 GitHub CR 已恢复；本修复 PR169 已创建并通过首次 PR Fast Checks。
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
