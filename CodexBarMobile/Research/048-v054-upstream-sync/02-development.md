# v0.54.0 Upstream Sync 开发记录

Status: `done`
Date: 2026-08-22

## Phase A — 分支与调研

- [x] 从最新 `mobile-dev` (`cadf27e6009c70c683122622f2ed321d2e608b17`) 建立任务分支；ASC
  状态核验后在未 push / 未建 PR 时将其改名为 `upstream-sync/v0.54.0-mobile.1.22.0`；
- [x] 读取 versioning、sync compatibility、CloudKit audit、release checklist与CI policy；
- [x] 复核 open issue #95、defect #97、历史 closed upstream-sync issues与上游 Releases；
- [x] 选择 authoritative latest release `v0.54.0`，将 v0.53.0–v0.54.0 合并成单一 train；
- [x] 记录版本方案、iOS影响门、风险与测试计划；
- [x] provenance-preserving merge peeled commit `22a2168842a9ed4fdd15dd6761cd109c56bcd3b5`；
  merge commit `0e4a7f491` 保留上游为第二 parent。

## Phase B — Mac / fork integration

- [x] 完整保留 upstream功能、修复、性能与安全变化；
- [x] 保留 fork CI/release/appcast/version/Production/Mobile sync约束；
- [x] 完成 Settings、CloudKit、cost/parser/cache与provider冲突适配；
- [x] 更新 root changelog与 `version.env`。

## Phase C — Shared / iOS

- [x] 完成 cost provenance/coverage/token mix 与provider数据投影审计；
- [x] 新增 additive optional wire与iOS显示，旧payload字段缺失保持原显示；
- [x] 新增独立的 1.22.0 notes block与四语言localization，并把已审核的 1.21.0 block恢复为前一版本内容；
- [x] 全部iOS targets build从194增至195。

## Phase D — testing/review

- [x] Mac Release build、lint、focused与9671-test serial full regression；
- [x] iOS Release build、731/731 unit tests与UI target；
- [x] CloudKit Production schema审计：`NO_DEPLOY`；
- [x] 16-case compatibility gate：全部逐行记录为`substituted`，未伪报physical pass；
- [x] merge/bridge/iOS循环review：累计94项均已修复并按影响面复测；product-source commit
  `e52a659e0`定向exact-current review为`Blockers: 0`。

## Phase E — iOS 1.22 release-state correction

- [x] ASC live readback确认已审核的`1.21.0 (194)`处于`PENDING_DEVELOPER_RELEASE` / manual release，
  不能吸收新build；用户明确批准本轮改为`1.22.0 (195)`；
- [x] 在未push、未建PR时把任务分支改名为`upstream-sync/v0.54.0-mobile.1.22.0`；
- [x] 更新`MOBILE_VERSION=1.22.0`、四个iOS targets、Sparkle复合版本、candidate tag、两份
  CHANGELOG、Research与CloudKit审计记录；
- [x] 为1.22新增独立Latest release-notes block和四语言summary；把1.21恢复为已审核内容；
- [x] `xcodegen generate`、i18n/source-key audit、fork README/CI policy/version/changelog gates与
  iOS 1.22 Release simulator build通过；未重复此前已通过的Mac/iOS full regression。

## 冲突记录

`git merge-tree` 复核正式 merge 输入得到 17 个 content conflicts：

| 分组 | Conflict paths | 决策 |
|---|---|---|
| release / version | `CHANGELOG.md`, `appcast.xml`, `version.env` | 保留 fork published history 与 draft-safe appcast；追加 0.53/0.54 notes；使用 `0.54.0.1 / 127.1 / 1.22.0` |
| app lifecycle / Settings | `CodexbarApp.swift`, `PreferencesSpendDashboardPane.swift`, `UsageStore+Refresh.swift`, `UsageStore.swift` | 采用 retained Settings controller、placeholder guard与上游refresh/spend语义，同时保留 `SyncCoordinator`、fleet/mobile observer和fork account生命周期 |
| provider / pricing | `CodexProviderDescriptor.swift`, `GrokStatusProbe.swift`, `CostUsagePricing.swift`, `CostUsageScanner+CacheHelpers.swift`, `CostUsageScanner+PricingRows.swift` | 合入PAT、Grok/xAI、historical/custom pricing、OpenCodex与新coverage；保留CLI fallback、provider-qualified pricing和fork fail-closed语义 |
| cache fingerprint | `CodexParserHash.generated.swift` | `parserLogicVersion` 12→13，最终hash由脚本生成，禁止手写 |
| regression tests | `AppDelegateTests.swift`, `CloudSyncSettingsTests.swift`, `CodexBaselineCharacterizationTests.swift`, `ProviderArchitectureGatekeeperTests.swift` | 合并上游新断言与fork Mobile/CloudKit/architecture约束，完整重跑 |

额外 fork invariant：`README.md` 保持reviewed fork版本byte-for-byte，不直接吸收上游README；上游README事实必须
另行审阅后按fork语境独立改写。本轮加入`Scripts/check_fork_readme.sh`及负向回归，防止后续upstream merge再次覆盖
branding与iOS/Mac下载入口。`appcast.xml` 与merge前fork parent byte-equivalent；CI仍只有 `PR Fast Checks` 在PR更新触发。

## 实现摘要

- `SyncCostSummary` 新增 optional `meteredCostUSD`、`costProvenance`、`coverage`、`tokenMix`、
  `historyCoverageIsEstablished`与`historyWindowIsComparable`；future provenance降级为`.unknown`，负数
  counter/token fail closed；
- Mac producer把v0.53 cost window映射到既有opaque payload，不同步路径、session identity或credential；
- iOS多Mac merge只在所有来源具备现代metadata时合并；每个token class也必须所有来源均有值，避免把
  partial已知值伪装成完整合计；old+new混合时保留旧cost显示并隐藏不完整新metadata；历史窗口缺省按
  legacy 30天归一化，但显式7天+30天来源不可认证为完整，并隐藏不可比较的metered/coverage/token mix；
- iOS provider detail显示provider-reported金额、coverage、provider-neutral incomplete-history提示、
  provenance与五类token mix；只有至少一个可见元素时才显示费用区；
- `Localizable.xcstrings` 四语言全部translated；1.22.0为最新block，已审核的1.21.0 block保持独立；build 194→195；
- root与Mobile changelog均保留历史fork release段；`README.md` fork branding未被上游覆盖；
- review发现并修复：report builder搬迁时遗漏`isEstimated`、Grok token catalog sentinel未更新、plugin
  fixture污染全局registry、per-token-class混合Mac部分合计、旧fork changelog段丢失、parser history漏记13；
- 后续consumer全链路review继续修复：widget跨provider partial subtotal、weekly share分母与provider rows不一致、
  CWL只含coverage metadata时被丢弃、Mistral稀疏history把旧bucket误标Today，以及30天分享卡把明确
  `costIsKnown=false`日的model breakdown计入Top Models。最终又移除Mistral无日期session fallback，避免
  缓存跨午夜重发时把昨天数据冒充Today；并阻止不同history window的多Mac metadata被合并为完整事实。
  最终review还发现equal-time ledger backfill只更新availability bit、可能把新状态与旧金额拼在一起；现改为
  相同时间戳下只要任一cost payload字段变化就整行原子刷新，旧时间戳仍拒绝。随后exact-current review又发现
  mixed-availability日的分享卡会丢掉已知provider贡献，以及只读cost diagnostics未传播unknown/partial状态；现由
  provider-aware reducer统一分享卡total/active-day/bar/model语义，diagnostics把不可用金额显示为`—`、partial显示
  incomplete warning且不再给出绿色pass。最新P1 review发现legacy默认30天writer与modern显式7天writer混合时，
  窗口不一致仍可能留下`nil` completeness；现不论coverage metadata是否齐全都强制标记incomplete，并把显示窗口
  归一为较宽的30天，避免将30天+7天subtotal误标为完整7天金额。最后一轮review又确认Mistral normal shared-summary
  路径仍可绕过dated-history保护，且不完整费用的dashboard/share Avg/Day仍会使用complete-only分母；现在Mistral所有
  sync发布路径均不发送无日期session fallback，coverage不完整时保留下限总额与警告但隐藏派生平均值。每项都有
  focused regression。随后数据库/分享卡专项review又发现summary-backed月图会因同日任一provider不可用而吞掉其他
  provider的已知金额，且刚seed的CWL会把“查询30天”误当成“已观察30天”；现在月图保留已知provider下限并单独标
  incomplete，CWL缺失日期只有在每个可见provider具备覆盖窗口起点的ledger或明确30天summary证据时才视为已知零。
  最新review再发现非零lower-bound日会因为`costIsKnown=false`从Active Days消失；现在以独立的本地
  `hasCostActivity`显示证据保留该日，金额仍保持不可用/不完整，且不把这个UI派生状态写入wire或CloudKit schema。
  随后的exact-current review又发现两个准确性边界：mixed provider日被折叠为已知下限后，dashboard-wide model
  fallback可能复活不可用provider的breakdown；以及明确`$0`的权威summary会因零值row被过滤而显示成未知。
  现在fallback直接检查选定周期内每个provider原始daily availability，blob与CWL路径也都会保留明确零值row；新增
  36项定向回归及149项同步/费用consumer组合回归均通过。下一轮review继续收紧月图缺口语义：legacy
  `historyCoverageIsEstablished=nil`且有逐日数据时保持旧版sparse-day兼容，只有汇总无逐日数据时不反推每日零值；
  CWL的稀疏首日row不再被当作连续覆盖证据，缺失日期只有所有producer明确认证完整30天窗口时才填权威零值。
  最终CostShare 28/28、同步/费用7-suite 150/150通过。随后full-head review又定位三个consumer边界：modern provider
  Today缺失时widget仍可能显示其他provider subtotal；分享卡的incomplete状态被选定周期外的未知日污染；负数
  `unpriced`/`unmetered` counter被clamp为0后会fail open。现在widget对modern unresolved Today保守隐藏总额，分享卡按
  Today/7天/30天实际选择窗口判定coverage，非法gap counter保留一个保守sentinel而不是归零；新增wire 19/19、
  share/widget 43/43、CWL写入/聚合/等价41/41及Mac同步75/75回归均通过。该修复后的exact-current review继续发现
  双Mac merge会把“一台有已知日、一台明确incomplete但缺该日”折叠成已知日，导致所选周期漏掉source-level缺口；
  现已在`ProviderSnapshotMerger`根层把缺失的modern incomplete contribution传播为merged day
  `costIsKnown=false`，使dashboard/share/widget/CWL共用同一lower-bound语义。双Mac集成组合105/105及
  CloudKit merge + CWL数据库组合103/103通过。下一次review进一步收紧该规则：只有扫描窗口本身
  `historyCoverageIsEstablished=false`才传播缺失日，不能把某个dated unpriced gap扩散到其他权威零日；若该Mac对
  `lastUpdated`所在本地日有已知session fallback，则把它原子并入兄弟Mac的daily点，避免daily-preferred consumer漏算；
  unfinished scan的7/30天分享卡还必须有到达周期起点的dated boundary evidence，只有近期活动行不能认证整个窗口。
  对应CloudKit merge/share/widget 108/108及CloudKit merge + CWL数据库105/105通过。
  最新exact-current review继续发现独立时间与窗口边界：provider usage refresh时间不能替代cost snapshot时间，
  catch-up期间由旧历史行合成的session `$0`不能认证Today，7天source不能把30天兄弟Mac的20天前数据标成缺失，
  pending scan也不能因旧cached boundary row而认证week/month完整。现由Mac producer在既有opaque payload内追加
  optional `sourceUpdatedAt`与`sessionCostIsKnown`，iOS仅在source day匹配且knownness为true时折入Today；缺失传播按
  每台Mac自己的`historyDays`限制，aggregate incomplete bit对week/month始终fail closed。新字段不改变
  `providerPayloadVersion`或CloudKit CKRecord schema。随后的exact-current review又发现4个同源Today freshness
  边界：明确过期source未阻断跨provider subtotal、pending scan的已定价Today row被过早认证、coverage window误用
  provider usage时间，以及不同source day的session成本被求和后挂到最新日期。现由所有Today consumer统一把
  incomplete scan、stale source与aggregate pricing gap视为不可认证；multi-Mac merge改用真实snapshot publication
  timestamp定位覆盖窗口，并只汇总最新source day的session fallback。最终exact-current review再指出两个P1：
  分享卡先按`historyCoverageIsEstablished`短路，导致“扫描已完成但source已过期”绕过Today警告；以及Mistral把UTC
  observation-end当作抓取时间，洛杉矶等UTC以西时区会把当天刷新误判为旧日。现已把Today source freshness放在
  completeness判定之前，并让Mistral使用外层`UsageSnapshot.updatedAt`真实抓取时间。随后最新review发现P4重建把
  device最新时间复制给所有provider、service-backed daily误用token source时间，以及legacy summary-only unknown
  cost未进入分享卡coverage warning。现在每个provider envelope的发布时间会贯穿CloudKit重建、incremental cache、
  设备alias collapse与最终merge；该派生metadata明确不进入wire，SwiftData冷启动则回退到已持久化的provider
  `lastUpdated`。service dashboard与token snapshot按实际贡献源取最新时间，legacy token-only unknown cost对
  Today/7天/30天均fail closed。额外自查还让乱序delta只以最新envelope更新device metadata。下一轮exact-current
  review继续发现3个时间语义缺口：dashboard refresh会给旧session重新定时、daily-only多Macmerge丢失最旧source
  freshness、以及iPhone用自身时区推断Mac producer的session day。现在opaque JSON内追加optional
  `sourceDayKey` / `sessionDayKey`，由producer固定本地日期；所有consumer分别按cost source day与session day判定，
  old payload缺字段仍保守兼容，old reader自动忽略新字段。最终Mac sync 93/93、iOS full unit 686 cases / 723 runs、
  CloudKit/cache/merge/share/widget 185/185、merge+CWL数据库113 cases / 117 runs与architecture 38/38通过。
  此后的exact-current review又发现4个同一根因边界：dashboard只刷新API时会沿用旧usage breakdown却推进整个snapshot
  时间、CWL读取已存Today row时未重新套用live summary freshness、主Cost tab未把任一provider明确stale传播到aggregate，
  以及双Mac history window不同会把“窗口不可比较”错误混入“扫描未完成”从而隐藏仍然可信的Today/7天数据。现以
  Mac本地cache-only `usageBreakdownUpdatedAt`保留breakdown真实时间；blob/CWL/share/widget统一应用live
  `costIsKnown`；新增additive optional `historyWindowIsComparable`把窗口可比性与扫描完成度拆开，Today/7天继续显示
  已知下限，30天及全局incomplete状态保持保守。字段仍位于既有opaque payload，未新增CKRecord或SwiftData schema。
  修复后Mac producer/wire/dashboard 133/133、iOS CloudKit/share/CWL/widget聚焦129/129、完整unit
  687 cases / 724 runs、CloudKit+CWL数据库114 cases / 118 runs均通过。下一轮exact-current review再发现2个
  consumer P1：CWL明确Unavailable Today仍可能被live summary的known覆盖，以及stale source只限定Today、未限定同样
  延伸到今天的7天/30天窗口。现在ledger/live任一明确false都占优，且source day过期会同时限定三个period，保留
  lower-bound金额但禁止complete-looking Avg/Day。最终定向43/43、完整unit 688 cases / 725 runs、数据库
  115 cases / 119 runs与architecture 38/38通过。最新exact-current review再抓到5个同源边界：跨日多Mac
  session fallback会把旧Mac的未知Today贡献静默丢弃、legacy summary-only 30天总额会被误当成可分配的7天事实、
  compact history会显示截至昨天的过期总额、不完整扫描窗口的起点被较新的CloudKit发布时间前移，以及CLI重建
  dashboard cache时丢失breakdown独立freshness。根因审计把时间语义统一拆成producer source day、snapshot
  publication time与scan coverage window：旧source只保留下限且使Today unknown，coverage起点锚定producer而不被
  publication重写，publication只延伸uncertainty终点；legacy无dated rows的周金额保持qualified，stale compact
  history直接隐藏，CLI显式透传`usageBreakdownUpdatedAt`。新增5个回归场景后，Mac/CLI/sync focused 112/112、
  iOS merge/share/widget 122/122、数据库116/116、完整iOS 691/691与architecture 38/38全部通过；累计review
  finding为34项。最后两项P1继续统一时间语义：Mac现在把配置的cost bucket time zone作为additive optional
  `bucketTimeZoneIdentifier`随opaque payload发布，local-cost source/session day key使用配置的producer calendar；
  iOS multi-Mac merge让daily-only旧source也参与session freshness判定，并在不同Mac bucket time zone时对daily、session、
  history以及metered/coverage/token metadata统一fail closed。旧reader忽略新字段，旧payload在新reader保持legacy fallback，
  `providerPayloadVersion`与CloudKit CKRecord schema不变。最终Mac定向63/63、iOS CloudKit/widget 93/93、数据库119/119、
  完整iOS 695/695及architecture 38/38通过；累计review finding为36项。最新exact-current review又发现3个日历/窗口
  边界：Mistral API的UTC日桶被错误标为本地cost calendar、不同history window的多Mac汇总仍可能认证7天subtotal，
  以及iPhone用自身日历的“今天零点”换算producer day时会在跨时区场景误判stale。现在Mistral日桶固定标记`UTC`；
  weekly consumer对不可比较窗口fail closed；分享卡捕获单一`now`并直接在producer calendar换算当前instant，而不是
  换算reader-local midnight。新增UTC、1天/7天混合窗口及东京iPhone/洛杉矶Mac边界回归后，Mac mapper/wire 63/63、
  iOS merge/share/widget/CWL 139/139、完整iOS 697/697与architecture 38/38通过；累计review finding为39项。
  随后的exact-current review再发现2个P1：仅携带重叠dashboard service明细也会推进token-backed总额freshness，
  以及Mistral UTC producer day仍有Cost dashboard/share consumer使用reader-local calendar。现在dashboard时间只在
  service fallback实际提供所选金额时参与source freshness；iOS捕获统一reference instant，并把producer logical day
  映射为reader相对日偏移，Today/7天/30天的总额、model mix和bar保持同一日轴。新增重叠来源与UTC producer/
  洛杉矶reader边界回归后，Mac mapper/wire 64/64、iOS merge/share/widget/CWL 140/140、完整iOS 698/698、
  architecture 38/38与full lint全部通过；累计review finding为41项。最新exact-current review又找到2个同源
  reader日轴问题：主Cost dashboard的Daily Spend仍把各producer的logical day当成reader-local日期聚合，
  而且historical coverage判定中重新读取`Date()`，可以让同一次渲染的Today与30天窗口跨日分裂。
  现在blob/CWL两条路径都先把每个provider的producer logical day转换成reader-relative day axis再跨provider
  聚合，且Today/历史/widget/share共用调用方捕获的同一`now`。新增mixed UTC/Los Angeles producer同日合并和
  widget固定reference instant回归后，iOS merge/share/widget/CWL focused 142/142、完整iOS unit 700/700、
  architecture 38/38与full lint全部通过；累计review finding为43项。
  随后exact-current review又发现一个P1：Cost页与诊断页只在iPhone本地午夜推进刷新键，UTC或其他producer
  calendar可能已经跨日但UI仍把昨日source显示为当前数据。现在刷新键同时包含reader与全部有效producer时区的
  day key，异步刷新等待其中最早的下一个午夜；CloudKit无新push时也会准时重新计算freshness与CWL窗口。
  新增东京producer/读端边界、最早午夜选择和invalid timezone过滤回归后，CostTab定向14/14、CloudKit merge +
  share + widget + CWL equivalence + CostTab组合156/156与full lint通过；累计review finding为44项。
  下一次exact-current review指出其余Usage列表/详情页也必须在producer午夜推进日期引用，且分享卡不能在已固定
  `CostDashboardInsights.referenceDate`后再读取新的系统时间，否则长时间打开页面或sheet可能把两个逻辑日混在
  同一次渲染中。现在root Usage clock、列表、详情、Cost页、诊断与分享卡都使用同一producer-aware reference；
  分享卡默认构造直接继承insights时间。新增Usage teaser和share跨日回归后，同步/费用consumer组合168/168、
  完整iOS unit 705/705与full lint通过；累计review finding为46项。最终rerun又发现一个P1：CWL先按
  iPhone本地日历裁剪rows，再在展示层映射producer logical day，会让跨时区7天/30天窗口多算或少算边界日，
  provider total、Daily Spend、model/service mix均可能偏差。现在ledger先多取两个安全边界日，再按匹配live
  原始`SyncedUsageSnapshot.deviceID`、provider identity与`bucketTimeZoneIdentifier`在形成任何rollup前逐设备执行
  producer-relative过滤；两台Mac即使固定不同时区也不会被合并后的单一calendar误裁剪。窗口边界按source预计算，
  避免对每个ledger row重复扫描provider或创建formatter；legacy/unmatched row保持reader-local兼容并显式拒绝未来日。
  新增producer领先/落后reader及双Mac异时区数据库回归后，最新review又发现3项同源准确性问题：rollup后才映射
  reader日轴会丢失producer-day identity；UTC+14与UTC-11可相差两个logical date，只多取一日仍会漏边界；以及
  refresh signature未包含per-provider publication timestamp，cost-only envelope更新可能不触发重算。现在所有原始
  row都在rollup前按其物理Mac/provider映射为reader-relative day key，安全读取扩大为两日并逐source精确裁剪；
  refresh signature同时纳入稳定排序的provider publication timestamps。新增极端Kiritimati/Pago_Pago、双Mac不同
  producer calendar、reader-relative ledger不重复映射及独立publication变化回归后，定向88/88、CloudKit+CWL数据库
  124/124、完整iOS unit 711/711与full lint通过；累计review finding为50项。最终rerun又指出3个跨日可信度
  边界：相同fresh source day会掩盖不同session day；reader-relative CWL row仍与producer Today key比较；
  非Gregorian系统日历会生成不兼容的年份键。现在session/source两个日期时钟都参与多Mac fail-closed，CWL明确按
  已归一化reader key判断Today，day-key formatter固定Gregorian但保留reader timezone。新增同source异session日、
  UTC producer/洛杉矶reader unavailable Today及Buddhist calendar回归后，定向105/105、CloudKit+CWL数据库
  126/126、完整iOS unit 713/713通过；累计review finding为53项。最新exact-current review再发现2项：通用
  Mac producer把OpenAI Admin、Mistral、xAI的原生UTC日桶错误标成Mac本地/固定时区；iOS把最长365个daily point
  投影到reader日轴时逐row创建`DateFormatter`。现在这三类provider明确发布`UTC` bucket metadata，Codex等本地
  scanner继续使用用户固定日历；reader-relative offset改为固定格式解析，dashboard projection只复用一个formatter。
  修复后Mac sync focused 97/97、architecture 38/38、Mac serial full 9650/9650、iOS同步/费用focused 166/166、
  完整iOS unit 713/713、Release build与full lint全部通过；累计review finding为55项。随后exact-current review再发现
  3项provider bucket/多Mac语义问题：OpenRouter原生UTC账单日被标成本地时区；Grok/OpenCode Go本地投影使用
  `Calendar.current`生成日桶却发布固定fallback时区；Grok本地session未列入additive多Mac来源。现已将
  OpenAI/Mistral/OpenRouter/xAI统一标UTC，Grok/OpenCode Go发布Mac当前日历时区，并将Grok与OpenCode Go都纳入
  local-cost additive merge；自查同时把Grok day key固定为Gregorian但保留时区，避免非Gregorian年份进入wire。
  最终Mac focused 39/39、CloudKit merge 79/79、iOS unit 715/715、architecture 38/38、Mac serial full
  9652/9652、Release build与full lint全部通过；累计review finding为58项，等待最终exact-current review收口。

后续数据库专项review把累计finding推进到68项，主要不是上游功能缺陷，而是fork跨设备数据契约的边界：
provider usage刷新时间不能覆盖cost自己的source freshness；provider-shared local cost在多token account间只能由一个
owner发布，owner迁移时必须用additive optional `costSummaryCleared` tombstone清除旧owner的精确ledger行；clear必须
优先于同payload内矛盾的cost，并且即使CWL显示关闭也要执行数据库清除；非本机来源选择必须按cost freshness而不是
quota freshness；seed/backfill、缺行检测、source-window选择与missing-provider fallback都必须使用
`costSummary.sourceUpdatedAt ?? provider.lastUpdated`，防止新quota envelope复活已清除的旧费用，同时允许真正较新的
cost进入ledger。`costSummaryCleared`仅位于既有opaque JSON，old reader会忽略、old payload在new reader解为`nil`，
不新增CKRecord或SwiftData schema字段。最终又将CWL seed纯逻辑夹具改为内存SwiftData且显式
`cloudKitDatabase: .none`，消除测试清理阶段的SQLite vnode噪声；产品仍由on-disk SQLite专项套件覆盖。当前
architecture gate为38/38，完整审阅集合267项、fingerprint `16870901492593307557`；Mac serial full为
9656/9656，iOS unit为725/725，Release simulator build与full lint均通过，等待最后一次exact-current review。

最后一次review新增第69项P2：Codex dashboard service日键按抓取时Mac本地calendar生成，若直接与用户pinned
token-scanner日桶合并再统一标成pinned timezone，午夜附近会把费用归到错误日期。现由Mac本地
`OpenAIDashboardSnapshot`随usage breakdown缓存其抓取时timezone；API-only refresh与CLI cache重建保留该字段，
旧缓存缺timestamp或timezone时丢弃breakdown并等待下次抓取。token与dashboard calendar相同时才合并；不同时
fail closed为保留token rows、忽略dashboard fallback；dashboard-only summary则发布其捕获calendar。该字段不进入
Shared wire或CloudKit。相关dashboard/cache/sync 82/82、architecture 38/38（267项，fingerprint
`13746141008516833249`）、Mac serial full 9658/9658、full lint全部通过，等待修复后的exact-current review。

修复后review又新增第70–71项P2，仍属于数据库/日期边界而非上游单机功能缺陷：第一，升级用户若已有一个
`lastUpdated`与authoritative blob完全相同、但金额/knownness/breakdown仍是旧内容的ledger row，原来的“是否需要
seed”快速检查只比较时间，导致aggregate不会进入已经支持等时整行修复的upsert路径；现在缺行检测会在时间相等时
比较identity与全部cost payload字段，发现漂移即在同一SwiftData事务内修复，而真正更新的ledger row仍不被旧blob
覆盖。第二，iPhone在页面保持打开时改变系统时区，旧`.task(id:)`只观察producer time zone集合，reader midnight
clock可能继续等待旧时区的边界；现在root Usage、Cost与Diagnostics的restart key都显式包含reader timezone，并监听
`UIApplication.significantTimeChangeNotification`立即刷新reference date/day key。新增equal-time stale-ledger与
reader-timezone restart回归后，数据库/时钟focused 47/47、iOS完整unit 727/727、Release simulator build、
architecture 38/38（同一267项fingerprint）与full lint均通过，等待修复后的exact-current review。

最新exact-current review新增第72项P1与第73项P2：Bedrock Cost Explorer使用UTC生成billing day，却被通用
producer标成固定本地cost calendar；Cursor按抓取时`Calendar.current`生成日桶，却同样被标成另一套pinned
calendar。现由Mac内部`CostUsageTokenSnapshot`携带实际生成日桶的IANA timezone；Bedrock的查询窗口、Today选择和
metadata统一固定Gregorian UTC，Cursor在同一次抓取中锁定当前calendar并随snapshot保存，SyncCoordinator优先使用
该source metadata，不会在Mac旅行或设置变化后重解释旧day key。该字段只存在Mac进程内，不进入Shared wire、
CloudKit或iOS数据库schema。Bedrock/Cursor/token/sync focused 96/96通过；architecture完整审计更新为269项、
fingerprint `14207327058727828035`，38/38通过；Mac serial full 9660/9660与iOS full 727/727通过。

随后review新增第74项P1与第75项P1：custom provider plugin虽已把`costUsage`映射进Mac快照，却没有桥接到
`ProviderUsageSnapshot.costSummary`，iOS会完全看不到custom plugin费用；Grok local scanner则在扫描后重新读取
`TimeZone.current`投影既有日桶，Mac旅行或时区变化后会把旧日键标成错误calendar。现统一复用
`SyncCostSummary` additive wire桥接plugin daily/provenance/coverage/token mix，并把plugin日桶明确定义为UTC；
Grok summary保存扫描时IANA timezone，投影只使用该捕获calendar。两项都只改变既有opaque payload内容或Mac
进程内metadata，不新增CKRecord/SwiftData schema。修复后plugin/Grok/sync focused 81/81、architecture 38/38
（269项，fingerprint `967595160927161226`）、Mac serial full 9662/9662、iOS unit 727/727、Mac/iOS Release build、
full lint、README guards与Production entitlement审计全部通过，等待最终exact-current review。

这里的75项是多轮review累计发现并逐项修复的fork集成/跨版本边界，不代表上游v0.53/v0.54本身包含75个发布缺陷。
主要复杂度来自将Mac单机功能接入本fork的多Mac→CloudKit→iOS链路，并同时证明old/new payload、producer/reader
时区、稀疏历史、partial cost、publication freshness与本地CWL数据库语义一致；上游自己的功能与测试只是输入基线。

最终exact-current review新增第76–78项：OpenRouter并发抓取history与date-specific Today时，活跃消费会令同一Today
row计数不同，旧实现把正常竞态误判为duplicate corruption并丢弃整段cost；provider-level Management Activity又被
绑定到当前普通API-key owner，切换key或不同Mac使用不同token UUID时会迁移、tombstone或重复账号级费用；plugin
mapper还把logical `windowEnd` noon sentinel当作抓取freshness，UTC中午前会发布未来时间并可能绕过iOS clear-history
tombstone。现由date-specific响应确定性替换history中的Today，其他日期继续严格duplicate校验；OpenRouter费用独立
发布到跨Mac稳定的`management-activity` pseudo-account，普通token envelope统一发clear tombstone，iOS Cost继续读取
该owner而Usage列表隐藏cost-only伪账号；plugin实际fetch `now`只负责freshness，`windowEnd`只负责calendar window。
全部变化仍位于既有opaque payload与既有provider record模型，不新增CloudKit/SwiftData schema。修复后Mac focused
76/76、iOS focused 14/14通过，完整回归与最终exact-current review待执行。

这里的78项仍是同一累计口径；新增3项均是fork多账号/CloudKit/CWL接入边界，不是上游release在Mac单机环境中已知
包含78个缺陷。

下一轮exact-current review新增第79项P1与第80项P2：稳定的OpenRouter Management Activity envelope虽然已经从
Usage列表隐藏，但现有`SnapshotCache.dropOrphansAndStale`仍会把其nil-email身份当作同provider真实账号旁的orphan，
使Activity cost在进入Cost/CWL前被丢弃；widget也仍会把该pseudo-account计入provider row/count，单API-key场景还会
生成重复`openrouter|_` identity。现有wire或schema无需改变：iOS cache明确保留
`isProviderLevelCostEnvelope`的稳定系统记录，cost freshness继续由source metadata独立判定；widget总额继续消费该
envelope，但provider count、top rows、usage/error只投影普通账号。新增SnapshotCache与widget回归后，iOS完整unit为
730/730，Mac serial full为9665/9665，full lint通过；等待修复后的exact-current review。

这里的80项仍是累计fork集成review findings，不是上游两个版本发布前遗留了80个Mac缺陷；最后两项只存在于
fork的Mac→CloudKit→iOS cost envelope consumer边界。

最新review新增第81–82项，属于同一个CLI日历一致性根因：dashboard和`/cost`虽然已按用户固定的cost bucket
calendar抓取usage，却在形成payload/coverage时重新使用`Calendar.current`；`costTotals`也会用当前系统日历
二次计算窗口边界，旅行或午夜附近可能让CLI的Today/coverage与Mac app及同步payload分叉。现在CLI从同一份
app defaults生成固定calendar，并把该实例同时传给fetcher、totals与dashboard/serve payload；新增一个刻意选择
与`Calendar.current`日期不同的时区边界回归。`CLICostTests`最终28/28、architecture 38/38、Mac serial full
9666/9666、Release build与full lint全部通过；等待修复后的最终exact-current review。

这里的82项是多轮独立review累计修复的fork集成边界，不是上游v0.53/v0.54本身带有82个产品缺陷。

修复后的full-head review新增第83–85项，均位于fork的Mac→CloudKit→iOS费用桥接边界：第一，单一费用
owner切换时旧owner tombstone会删除其全部CWL历史，而新Mac payload只携带当前扫描窗口，导致窗口外的历史永久
丢失；现在删除前先把旧owner ledger重键到唯一新owner，碰撞时保留较新的payload，并保留仅存在于ledger的旧日。
第二，custom plugin把抓取完成时间写入`updatedAt`后，声明的`windowEnd`丢失，延迟窗口可能被错误显示为当前完整
窗口；现在Mac本地token snapshot单独保留`windowEndDayKey`，同步映射以它作为`sourceDayKey`，fetch instant仍用于
freshness。第三，plugin允许366日而iOS投影只保留365日；producer上限已统一为365，避免第366日被静默裁掉。
新增owner迁移、窗口结束日与365日上限回归后，Mac focused 44/44、iOS `SwiftDataBridgeTests` 18/18、
architecture 38/38、iOS完整unit 730/730（767 expanded runs）、Mac serial full 9667/9667及两端Release build
全部通过；等待最终exact-current review。

这里的85项仍是多轮独立review累计发现并修复的fork集成/跨版本边界，不代表上游v0.53/v0.54发布前遗留了
85个Mac产品缺陷。

最终full-head review新增第86–89项，仍集中在fork费用同步的跨账号和跨时区消费边界：OpenRouter旧API-key
account的费用summary可能比新的`management-activity` owner tombstone更早，却仍被独立挑中并重复计入；现在
非本机summary与clear tombstone使用同一source/publication排序原子选胜，较新的clear不会再留下旧summary，且
本地合并结果不会同时发布summary和clear。其余三项来自同一个日桶metadata没有贯穿所有Mac consumer的根因：
Spend dashboard、CLI JSON coverage/totals与Mac cost chart过去会重新使用display/pinned calendar，而忽略snapshot
已声明的`bucketTimeZoneIdentifier`。现在三个consumer都优先用producer snapshot calendar，旧payload才保留
Mistral/OpenRouter/xAI的legacy UTC fallback；xAI producer也显式发布UTC元数据。新增OpenRouter tombstone、东京/洛杉矶
边界、CLI pinned-calendar覆盖与generic provider UTC chart回归后，Mac focused 124/124、iOS CloudKit merge
83/83、architecture 38/38、Mac serial full 9670/9670、iOS完整unit 731/731（768 expanded runs）、full lint与
两端Release build全部通过；等待最终exact-current review。

这里的89项是整条fork Mac→CloudKit→iOS费用闭环经过多轮独立review的累计发现，不是上游v0.53/v0.54自身包含
89个Mac单机缺陷。

最新exact-current review新增第90项P1：Mistral多账号费用历史来自各自cookie/account snapshot，并不是可在账号间
移动的provider-level共享ledger。旧实现会把非owner账号缺失的summary解释成clear tombstone，瞬时抓取失败时可能
删除该账号已经同步到iOS的原生费用历史。现在Mistral逐账号从各自`MistralUsageSnapshot`映射费用；抓取失败只省略
本次summary，不发共享owner tombstone。新增Alice有账单、Bob临时失败的回归后，Mistral multi-account suite
13/13、architecture 38/38、Mac serial full 9671/9671、iOS CloudKit merge + SwiftData bridge 101/101与full lint
全部通过；等待修复后的最终exact-current review。

这里的第90项仍是fork把Mac多账号payload投影到CloudKit/iOS时的归属缺陷，不是上游v0.53/v0.54的单机功能缺陷。

## Review 循环与第 6 轮前根因审计

前5轮独立review依次发现并修复：多Mac partial metered subtotal、`false`被legacy `nil`掩盖、custom
pricing文案误称public API prices、metadata-only summary不可达、provider-specific history文案、
`Calendar.current`重切provider窗口、Grok zero-information空标题，以及line-sensitive architecture sentinel漂移。
每轮修复后均重跑对应Mac/iOS focused tests与lint；第5轮P1触发进入第6轮前的强制根因审计：

- **Head:** `upstream-sync/v0.54.0-mobile.1.22.0` working tree，基于merge commit `0e4a7f491`；
- **Repeated finding pattern:** 新cost metadata在producer、multi-Mac merge与iOS可见性之间缺少统一的
  completeness/source/calendar不变量，并反复混用source day、publication time与coverage window；architecture
  gate另受源码行号影响；
- **Root design/requirements problem:** 初版bridge复用了旧total-first UI gate与`summary(forLastDays:)`，但没有先定义
  “provider已裁窗口不可重切、partial不得汇总、unknown不得压过false、UI只渲染可见事实”的共同契约；
- **Revised approach:** producer直接聚合provider已裁好的daily窗口，并显式携带producer day/freshness；wire保持
  additive optional；multi-Mac以producer day确定scan起点、以publication只延伸uncertainty终点并按字段完整性
  conservative merge；UI使用显式visibility helper与source-neutral文案；新增UTC边界、legacy/new、partial subtotal、
  metadata-only与Grok empty-section回归。为避免无语义fingerprint漂移，`syncWindowSummary`放到文件末尾并保持
  原调用处行数不变；后续新增`SyncDailyPoint.costIsKnown`与source-alignment逻辑属于必要源码位移，复核count仍为
  265、前12项逐条一致后，没有新增provider-specific branch。最终Mistral stale-session guard及上游v0.54
  `MenuCardView+ModelHelpers`的pace/localization变更移动已审阅anchor；在当前格式化源码上重新审计的sentinel为
  `2384312504282601872`；provider-specific finding仍为265项，未新增未说明的特例。最终为原生UTC billing API
  新增有理由标记的provider-specific bucket选择后，重新审计完整265项，当前sentinel为
  `12183018372452420532`。新增Mac本地
  `usageBreakdownUpdatedAt`只移动`OpenAIDashboardModels`中既有provider default的精确行锚，已单独重锚并保持
  同一265项完整指纹，不放宽scanner。

最终数据库/owner tombstone实现移动了既有源码锚点并增加两项有明确设计标记的provider分支；重新审计完整集合为
267项；加入Mac本地dashboard calendar字段后的当前fingerprint为`13746141008516833249`，38项architecture gate全部
通过，没有放宽scanner或删除旧allowlist。

Bedrock/Cursor真实bucket calendar加入既有provider-specific selector后新增两项已说明的审阅记录；当前完整集合为
269项。custom plugin cost bridge与Grok扫描时calendar修复移动既有审阅锚点，但不增加新的provider-specific
branch；当前fingerprint为`967595160927161226`，38项architecture gate全部通过，仍未放宽scanner或删除旧allowlist。

OpenRouter provider-level cost owner采用既有`ProviderUsageSnapshot.accountRecordKey`与`accountIdentities`表达稳定
pseudo-account，不增加provider-specific architecture branch或wire字段；普通account envelope的
`costSummaryCleared`继续复用已审计的additive tombstone语义。iOS cache/widget修复也只消费既有
`isProviderLevelCostEnvelope`分类，不增加provider-specific architecture branch。

最终架构scanner升级后，原先依赖源码行号的allowlist/suppression锚点按当前源码逐条机械重定位；没有加入产品
注释、放宽scanner或删除旧约束。242个allowed constructs中79个仅行号移动，153个suppression中28个仅行号移动，
全部exact anchor可解析且无重复。owner迁移与plugin window metadata修复只移动既有审阅锚点；当前scanner实际
审阅集合仍为95项。Mistral account-native费用分支使用紧邻、具体原因的设计标记，不扩大fork drift；新增源码行使
location fingerprint更新为`469636138625236751`，focused与full-run内的38/38 architecture gate均通过。

PR #99的GitHub Codex review在第一轮即返回exact-current clean结果，且没有finding thread，因此没有进入第6轮
GitHub review，也无需额外发布architecture audit comment；上述四字段继续作为本地累计review的根因记录。

最后两轮把同一cost准确性根因收口到四个边界：费用来源owner从增量快照完全消失时仍须迁移CWL长历史；一次
临时无费用blob不能抹掉该历史所有权；Mistral账号原生费用不得跨账号迁移；损坏或极大的coverage counter不得
整数溢出。对应SwiftData 21/21与CostProvenance 11/11通过，最终Mac Release build在当前HEAD以265.87秒完成。
这部分没有新增CloudKit record/schema字段，`providerPayloadVersion`保持1。

## GitHub 合入与 Mac draft（2026-08-22）

- upstream-sync分支推送后创建PR [#99](https://github.com/o1xhack/CodexBar-Mobile/pull/99)；
  `PR Fast Checks`通过，exact-current head `4535e55bf47c291f22cc9f883fa2f2b6ffb17272`的Codex review
  返回`Didn't find any major issues`，review threads为0，`Scripts/check_pr_review_gate.sh 99`通过；
- PR #99合入`mobile-dev`，merge commit为
  `d7eddbc70d133f34e52d903dbdb4e2e9a1af7581`；merge-triggered Final CI
  [32614686853](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/32614686853)全部通过；
- 从clean且与`origin/mobile-dev`一致的merge commit运行`./Scripts/release.sh` phase 1；Apple notarization
  `d9e78000-ad1b-4133-bb57-7e47d53b42a8`=`Accepted`，签名、staple、Gatekeeper与launch checks通过；
- tag `v0.54.0.1-mobile.1.22.0`指向merge commit；GitHub
  [draft release](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-b32586f17d599231dee5)
  已创建并含ZIP/dSYM，远端digest与本地SHA-256一致；未运行`--finalize`，未发布appcast/live release；
- notarized draft在macOS 26.5.2用exact PID验证issue #97：`Command-,`与状态栏`设置…`均打开同一个
  retained Settings window，重复打开稳定态仍为1，目标runtime fault日志为0。macOS 27 beta及
  active Space/Stage Manager仍为substituted，未伪报physical pass；
- #95/#97均保持open，等待Mac public release公开后逐项回复正式URL并手动`Close as completed`；
- draft后的证据只在`release/v0.54.0.1-draft-evidence` docs-only分支回写，没有直接修改`mobile-dev`产品代码。
