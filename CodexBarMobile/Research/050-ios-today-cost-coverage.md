# iOS Today Cost Coverage Hotfix

Status: `done`
Date: 2026-09-01
Branch: `fix/ios-today-cost-coverage`

## 结论

截图中的 Raw Sync Data 已包含两台 Mac 当日 Codex 金额 `$7.37` 与 `$193.58`，但 Cost
Overview 把 Today 显示为 `—`。这不是 CloudKit 缺数，也不是 v0.56 新产生的数据错误；直接
回归来自 v0.53/v0.54 cost coverage 同步在 fork commit `cf9f37726`（PR #99、iOS 1.22.0）
中的 iOS 展示适配。该适配把面向整个历史扫描窗口的
`historyCoverageIsEstablished`、`coverage.unpriced` 与 `coverage.unmetered` 错当成 Today
日期点的已知性，只要更早历史仍在 catch-up，就会隐藏已经独立标记为 known 的今日金额。
v0.56 / iOS 1.23.0 只是继续携带这一逻辑。

## 设计

- Today 只根据当前日期点，或带明确当日 provenance 的 session 自身 `costIsKnown`、producer
  day freshness 和 bucket time-zone 合法性决定是否展示；无日期 legacy fallback 继续使用历史
  coverage guard；历史扫描未完成时把可见金额标为 `≥` lower bound，不声称它已经是最终总额；
- 历史覆盖状态继续控制 30/365 日总额与 `Historical cost coverage is incomplete` 告警；
- 缺失/unknown 的 Today point、跨日陈旧来源和非法 producer calendar 仍然 fail closed；
- App、分享卡与 Widget 共用相同语义，避免 Overview、diagnostics、share card 与 widget 再次分叉；
- 不修改 wire model、CloudKit schema 或 Mac producer。

## 影响文件

- `Models/SyncCostSummary+Today.swift`：修正 App Today resolver；
- `CodexBarWidgetSnapshot.swift`：修正 Widget duplicated resolver；
- `CloudKitMergeTests.swift`、`CostDiagnosticsReportTests.swift`、
  `WidgetSnapshotBuilderTests.swift`：覆盖 dated point、session fallback、双 Mac 合并和历史告警并存。

## 验证计划

- 定向运行 merge、diagnostics、dashboard/share/widget cost tests；
- 运行 iOS unit test target 与 Release simulator build；
- 用 synthetic 双 Mac fixture 复现截图金额，期望 Today `$200.95` 且历史 incomplete 仍为 true；
- 校验四 target build number、四语言 release notes 与 localization lint；
- PR exact-current-head Code Review 必须无 finding、无 unresolved thread；本 hotfix 不包含 merge、
  TestFlight 上传或 public release。

## 验证结果

- 定向成本与展示链路：196 tests passed；首轮发现并保留 3 个既有 fail-closed 场景后复测全绿；
- Widget 旧缓存兼容：缺少新增 lower-bound 字段的旧 JSON 仍可解码，字段按 `nil` 处理；
- 完整 `CodexBarMobileTests`：745 tests passed，0 failed；
- iPhone 17 Pro / iOS 26.5：Release simulator build、install、launch 与 Cost tab navigation通过；
- repository lint：SwiftFormat 0/2094、SwiftLint 0 violations / 2093 files、四语言
  localization source/catalog audit、CI policy与release guards全部通过；
- synthetic 双 Mac fixture：`$7.37 + $193.58 = $200.95`，Today known 为 true，同时历史
  incomplete 保持 true、Today lower-bound 标记为 true、30-day widget total 保持 unavailable；
- build number：四个 iOS targets均为 `1.23.0 (197)`；同一 marketing version 的发布说明已
  合并到现有 1.23.0 block。
- PR #110 首轮 exact-head review 指出 `historyCoverageIsEstablished=false` 也可能包含会影响
  Today 的尚未扫描 session；修复后不再把可见金额称作最终值，App 与 Widget 均显式传播
  lower-bound 状态并显示 `≥`，同时补 snapshot propagation 与 teaser 测试。
- PR #110 第二轮 exact-head review 发现分享卡未传播 lower-bound qualifier，以及 `≥…*` 组合
  状态会丢失 Estimated 的 VoiceOver 提示；两处均已修复并补四语言组合提示。

实现与本地验证完成。PR exact-current-head Code Review作为 GitHub handoff gate执行；未授权且
不执行 merge、TestFlight上传或 public release。
