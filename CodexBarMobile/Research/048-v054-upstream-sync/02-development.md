# v0.54.0 Upstream Sync 开发记录

Status: `done`
Date: 2026-08-21

## Phase A — 分支与调研

- [x] 从最新 `mobile-dev` (`cadf27e6009c70c683122622f2ed321d2e608b17`) 建立
  `upstream-sync/v0.54.0-mobile.1.21.0`；
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
- [x] 合并更新唯一的 1.21.0 notes block与四语言localization；
- [x] 全部iOS targets build从194增至195。

## Phase D — testing/review

- [x] Mac Release build、lint、focused与9630-test serial full regression；
- [x] iOS Release build、595 Swift Testing + 38 XCTest unit与UI target；
- [x] CloudKit Production schema审计：`NO_DEPLOY`；
- [x] 16-case compatibility gate：全部逐行记录为`substituted`，未伪报physical pass；
- [x] merge/bridge/iOS循环review至blocker 0；最终 exact-current review 明确返回无可执行正确性问题。

## 冲突记录

`git merge-tree` 复核正式 merge 输入得到 17 个 content conflicts：

| 分组 | Conflict paths | 决策 |
|---|---|---|
| release / version | `CHANGELOG.md`, `appcast.xml`, `version.env` | 保留 fork published history 与 draft-safe appcast；追加 0.53/0.54 notes；使用 `0.54.0.1 / 127.1 / 1.21.0` |
| app lifecycle / Settings | `CodexbarApp.swift`, `PreferencesSpendDashboardPane.swift`, `UsageStore+Refresh.swift`, `UsageStore.swift` | 采用 retained Settings controller、placeholder guard与上游refresh/spend语义，同时保留 `SyncCoordinator`、fleet/mobile observer和fork account生命周期 |
| provider / pricing | `CodexProviderDescriptor.swift`, `GrokStatusProbe.swift`, `CostUsagePricing.swift`, `CostUsageScanner+CacheHelpers.swift`, `CostUsageScanner+PricingRows.swift` | 合入PAT、Grok/xAI、historical/custom pricing、OpenCodex与新coverage；保留CLI fallback、provider-qualified pricing和fork fail-closed语义 |
| cache fingerprint | `CodexParserHash.generated.swift` | `parserLogicVersion` 12→13，最终hash由脚本生成，禁止手写 |
| regression tests | `AppDelegateTests.swift`, `CloudSyncSettingsTests.swift`, `CodexBaselineCharacterizationTests.swift`, `ProviderArchitectureGatekeeperTests.swift` | 合并上游新断言与fork Mobile/CloudKit/architecture约束，完整重跑 |

额外 fork invariant：`README.md` 没有 wholesale采用上游版本；branding、iOS/Mac下载入口保持fork内容，
只人工吸收已审阅的 OpenCode Go usage API 描述和 Stream Deck integration。`appcast.xml` 与merge前
fork parent byte-equivalent；CI仍只有 `PR Fast Checks` 在PR更新触发。

## 实现摘要

- `SyncCostSummary` 新增 optional `meteredCostUSD`、`costProvenance`、`coverage`、`tokenMix`、
  `historyCoverageIsEstablished`；future provenance降级为`.unknown`，负数counter/token fail closed；
- Mac producer把v0.53 cost window映射到既有opaque payload，不同步路径、session identity或credential；
- iOS多Mac merge只在所有来源具备现代metadata时合并；每个token class也必须所有来源均有值，避免把
  partial已知值伪装成完整合计；old+new混合时保留旧cost显示并隐藏不完整新metadata；历史窗口缺省按
  legacy 30天归一化，但显式7天+30天来源不可认证为完整，并隐藏不可比较的metered/coverage/token mix；
- iOS provider detail显示provider-reported金额、coverage、provider-neutral incomplete-history提示、
  provenance与五类token mix；只有至少一个可见元素时才显示费用区；
- `Localizable.xcstrings` 四语言全部translated，1.21.0 release notes只有一个block；build 194→195；
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
  最终CostShare 28/28、同步/费用7-suite 150/150通过。

## Review 循环与第 6 轮前根因审计

前5轮独立review依次发现并修复：多Mac partial metered subtotal、`false`被legacy `nil`掩盖、custom
pricing文案误称public API prices、metadata-only summary不可达、provider-specific history文案、
`Calendar.current`重切provider窗口、Grok zero-information空标题，以及line-sensitive architecture sentinel漂移。
每轮修复后均重跑对应Mac/iOS focused tests与lint；第5轮P1触发进入第6轮前的强制根因审计：

- **Head:** `upstream-sync/v0.54.0-mobile.1.21.0` working tree，基于merge commit `0e4a7f491`；
- **Repeated finding pattern:** 新cost metadata在producer、multi-Mac merge与iOS可见性之间缺少统一的
  completeness/source/calendar不变量，早期修复逐个暴露边界；architecture gate另受源码行号影响；
- **Root design/requirements problem:** 初版bridge复用了旧total-first UI gate与`summary(forLastDays:)`，但没有先定义
  “provider已裁窗口不可重切、partial不得汇总、unknown不得压过false、UI只渲染可见事实”的共同契约；
- **Revised approach:** producer直接聚合provider已裁好的daily窗口；wire保持additive optional；multi-Mac按字段完整性
  conservative merge；UI使用显式visibility helper与source-neutral文案；新增UTC边界、legacy/new、partial subtotal、
  metadata-only与Grok empty-section回归。为避免无语义fingerprint漂移，`syncWindowSummary`放到文件末尾并保持
  原调用处行数不变；后续新增`SyncDailyPoint.costIsKnown`与source-alignment逻辑属于必要源码位移，复核count仍为
  265、前12项逐条一致后，没有新增provider-specific branch。最终Mistral stale-session guard只移动
  `SyncCoordinator`后续行锚点，最终共享summary路径的Mistral Today保护加入后，重新审计的sentinel为
  `14702636125599630567`；provider-specific finding仍为265项，未新增未说明的特例。

当前尚无PR，因此无法发布规定格式的PR comment；创建PR后若review流程继续超过5轮，必须把以上4个非空字段原样
写入PR再请求下一轮。
