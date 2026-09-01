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
- 完整 `CodexBarMobileTests`：749 tests passed，0 failed；其中新增参数化 matrix 的
  16/16 dynamic cases全部通过；
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

## 2 Mac × 2 iPhone old/new 兼容性 gate

本 hotfix 改变跨版本 Today-cost 展示与 `CodexBarWidgetSnapshot` 的 additive optional 字段，
因此 `docs/ios-sync-compatibility-testing.md` 的 16-case gate 适用。这里的 `old Mac` 是已发布
`mobile-dev` producer，`new Mac` 是本分支 candidate；本分支没有修改 Mac source、wire model 或
CloudKit schema，所以二者都使用 `0.56.0.1` production payload contract。`old iPhone` 是
`1.23.0 (196)` 展示 contract，`new iPhone` 是 `1.23.0 (197)` candidate。

当前运行环境只有一台开发 Mac 和一台已连接 iPhone，无法反复安装并同时保留 2 Mac × 2 iPhone
的 old/new binaries，因此以下结果严格标记为 `substituted PASS`，不是实机 PASS。替代证据为
`WidgetSnapshotBuilderTests.2 Mac x 2 iPhone Today cost old-new matrix`：参数化执行 masks 0–15，
使用两个 distinct Mac writer ID，经 production `CloudSyncConstants` codec round-trip 后，由两个
独立 reader 路径执行 merge、App Today、share card 与 widget presentation。old reader contract
保持 `—`，new reader 显示 `≥$200.95`；两者都保留 raw `$200.95`、唯一 provider identity 与两个
device records，同版本 readers 必须收敛。另有双向 additive Codable 证据：new reader 解码缺少
lower-bound keys 的 legacy snapshot；published model 解码 candidate snapshot 时忽略新 key 且不崩溃。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted PASS | mask 0 | all-published control；两 reader 均为 `—` |
| 2 | old | old | old | new | substituted PASS | mask 1 | new reader 解 published writers，显示 `≥$200.95` |
| 3 | old | old | new | old | substituted PASS | mask 2 | case 2 reader role mirror |
| 4 | old | old | new | new | substituted PASS | mask 3 | 两个 new readers 独立构建 widget snapshot 并收敛 |
| 5 | old | new | old | old | substituted PASS | mask 4 | unchanged mixed writer contract；old readers fail closed |
| 6 | old | new | old | new | substituted PASS | mask 5 | mixed writers/readers；raw total 与 qualified display 分离 |
| 7 | old | new | new | old | substituted PASS | mask 6 | case 6 reader role mirror |
| 8 | old | new | new | new | substituted PASS | mask 7 | mixed writers；new App/share/widget 均收敛 |
| 9 | new | old | old | old | substituted PASS | mask 8 | writer role reverse；old readers fail closed |
| 10 | new | old | old | new | substituted PASS | mask 9 | writer/reader 双重非对称 |
| 11 | new | old | new | old | substituted PASS | mask 10 | case 10 reader role mirror |
| 12 | new | old | new | new | substituted PASS | mask 11 | reversed writers；new readers 收敛 |
| 13 | new | new | old | old | substituted PASS | mask 12 | candidate writers 保持 published wire；old readers 不崩溃 |
| 14 | new | new | old | new | substituted PASS | mask 13 | candidate payload 同时供 old/new reader 读取 |
| 15 | new | new | new | old | substituted PASS | mask 14 | case 14 reader role mirror |
| 16 | new | new | new | new | substituted PASS | mask 15 | all-candidate App/share/widget convergence |

### 剩余风险与 gate verdict

- 未覆盖四台真实设备上的 Production CloudKit propagation、silent push 时序、foreground/background
  切换与两个独立 WidgetKit host cache；这些仍是 release 前真实硬件 QA 风险。
- published iOS binary 不理解 additive lower-bound key。candidate snapshot 可被它安全解码，但若用户
  降级并由系统恢复 candidate 的 archived widget timeline，旧 UI 无法显示 `≥`；下一次旧版 timeline
  refresh 会按 published fail-closed 逻辑重新隐藏 Today。正常升级方向由 legacy decode test 覆盖。
- 16/16 substituted cases 通过后，本 PR 的 canonical compatibility gate 结论为
  **SUBSTITUTED PASS**；不得对外表述为 2 Mac × 2 iPhone physical-device PASS。
- PR #110 第三轮 exact-head review 指出最初证据没有列全 16 cases；本节与参数化测试补齐该 gate。
- PR #110 第四轮 exact-head review 发现 lower-bound 不应由其他日期的 window-level gap 永久
  触发，且 provider subtitle 与 diagnostics summary 尚未传播 qualifier；修复后只有
  `historyCoverageIsEstablished == false` 才标记 `≥`，历史 gap warning 继续保留，两个展示面也与
  Overview/share/widget 一致。定向 117 tests 与当轮完整 748 tests 均通过；第五轮修复后完整
  suite 更新为 749 tests passed。
- PR #110 第五轮 exact-head review 发现 Widget aggregate 会把有效的 `≥$0.00` lower bound 当成
  普通零值隐藏；修复后仅在 lower-bound 成立时保留零值，普通 exact `$0.00` 的既有隐藏策略不变，
  并新增 Widget aggregate/provider 回归测试。

实现与本地验证完成。PR exact-current-head Code Review作为 GitHub handoff gate执行；未授权且
不执行 merge、TestFlight上传或 public release。
