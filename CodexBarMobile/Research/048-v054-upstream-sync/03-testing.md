# v0.54.0 Upstream Sync 测试证据

Status: `done`
Date: 2026-08-21

## 版本与范围

- old Mac: published fork `0.52.0.1 (124.1.1.21.0)`；
- new Mac candidate: `0.54.0.1 (127.1.1.21.0)`；
- old iPhone: iOS `1.21.0 (194)`；
- new iPhone candidate: iOS `1.21.0 (195)`；
- payload/CloudKit baseline: `providerPayloadVersion=1`、Production container。

## Gates

| Gate | Result | Evidence / Notes |
|---|---|---|
| Merge provenance / conflict audit | pass | merge `0e4a7f491` parents fork research commit `c0c62d1b5` + upstream peeled tag commit `22a216884`; 17 conflict paths逐项处理 |
| Mac build + lint + full tests | pass | `swift build -c release` pass；SwiftFormat 2025 files / 0 issues、SwiftLint 2024 files / 0 violations；serial full regression 9630 tests / 918 suites / 0 failures |
| Settings / CloudKit / cost / provider focused regression | pass | sync producer/wire 44 tests；cost pricing race、29-provider token catalog、plugin isolation focused pass；architecture 38/38 pass |
| Parser fingerprint/hash | pass | `parserLogicVersion=13`；`regenerate-codex-parser-hash.sh` → `8b9bc662426a8aab`；lint audit pass |
| iOS build + full tests | pass | unit target：38 XCTest + 595 Swift Testing；UI：7 tests，4 fixture-dependent skipped，0 failures；Release simulator build pass |
| Widget/cost/provider display parity | pass | full iOS unit target覆盖widget/render；最终focused rerun为CloudKit merge 61 tests + Mobile display 13 tests，覆盖modern sum、old/new conservative merge、legacy 30天+modern 7天不一致、metadata-only与empty-section gate |
| iOS ledger/blob一致性 | pass | `CWLWriterTests` 14 tests + CloudKit merge 60 tests，同一run共74/74；equal-time nil→known与任意changed cost payload均整行刷新，older payload仍拒绝 |
| iOS cost consumer一致性 | pass | final post-review 7-suite组合150/150；mixed known/unavailable日的share total/bar/model与diagnostics availability/incomplete状态使用同一保守语义；dashboard model fallback不复活不可用provider breakdown；blob/CWL均保留权威`$0`；legacy sparse-day语义保持兼容，summary-only分布不伪造，CWL稀疏首日row不再认证连续覆盖；非零partial日保留Active Days证据但不显示为完整金额；coverage不完整时不显示派生Avg/Day |
| Four-language localization | pass | lint：all locales translated；303/303 source keys present；唯一1.21.0 notes block |
| CloudKit Production schema audit | `NO_DEPLOY` | production schema成功导出并只读核对；见下节 |
| Final review blockers | pass | exact-current `codex review --uncommitted`：`No actionable correctness issues were found`；reviewer 另行重跑 Mac sync focused 83/83 与 iOS CloudKit merge / ledger / share focused 103/103；0 blockers |

## 关键命令与结果

```text
swift build -c release
  PASS，Build complete (279.26s)；只有既有deprecated API warnings

bash Scripts/lint.sh lint
  PASS，SwiftFormat 2025 files / 0 issues、SwiftLint 2024 files / 0 violations；
  4语言与303 source keys完整

swift test --filter 'Sync(CoordinatorTests|WireFormatRoundTripTests)'
  PASS，44 tests / 3 suites

swift test --filter ProviderArchitectureGatekeeperTests
  PASS，38 tests；review根因审计确认fork drift仍为已审阅265项；最终cost-availability源码位移后的
  最终fingerprint为14702636125599630567，finding仍为265项，未新增未说明的provider-specific branch

swift test --no-parallel
  PASS，9630 tests / 918 suites / 0 failures / 642.502s

xcodebuild ... test -only-testing:CodexBarMobileTests
  PASS，38 XCTest + 595 Swift Testing / 44 suites

xcodebuild ... test -only-testing:CodexBarMobileUITests
  PASS，7 tests / 4 skipped / 0 failures（重启simulator后）

xcodebuild ... -configuration Release -destination 'generic/platform=iOS Simulator' build
  PASS

xcodebuild ... test -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/MobileDisplayFormattingTests
  PASS，早期组合68 tests；最终CloudKitMerge单独复测61/61，另有Mobile display 13/13；覆盖partial metered、
  three-valued history、显式7天+30天及legacy默认30天+modern 7天均不可认证完整、metadata-only与
  Grok empty-section gate

swift test --filter 'SyncCoordinatorTests|SyncProviderMapperTests'
  PASS，56 tests / 3 suites；覆盖provider-windowed daily metadata不被Calendar.current重新裁剪，且Mistral
  shared summary正常发布路径不会把最新历史bucket重新作为Today session字段发布

swift test --filter SyncProviderMapperTests
  PASS，24 tests；覆盖Mistral dated daily rows，并确认无日期session fallback不会在跨午夜缓存重发时冒充Today

xcodebuild ... test -only-testing:CodexBarMobileTests/CostShareServiceTests
  PASS，最终28 tests；覆盖weekly denominator、summary-backed 30天Top Models排除明确不可用日、同日mixed
  provider保留已知月图金额、刚seed的30天CWL不认证缺失日期，以及partial subtotal保留Active Days证据但
  Avg/Day仍不可用；mixed provider model fallback不会复活不可用breakdown，权威`$0`保持known；legacy
  daily payload保持兼容，summary-only和CWL稀疏首日row不制造连续零值

xcodebuild ... test -only-testing:CodexBarMobileTests/CWLWriterTests \
  -only-testing:CodexBarMobileTests/CloudKitMergeTests
  PASS，74 tests / 2 suites；覆盖equal-time ledger整行原子刷新、nil→known rolling-upgrade回填与60个多Mac合并场景

xcodebuild ... test -only-testing:CodexBarMobileTests/CostShareServiceTests \
  -only-testing:CodexBarMobileTests/CostDiagnosticsReportTests ...
  PASS，最终7-suite组合150/150；review指出的mixed-availability share/bar/model fallback、权威零值、CWL实际
  覆盖证据、partial Active Days/Avg/Day与diagnostics unknown/partial传播均有回归，且同run复测CWL
  aggregate/equivalence、widget、display与CloudKit merge

codex review --uncommitted
  PASS，exact-current review返回“No actionable correctness issues were found”；reviewer独立补跑Mac同步
  focused 83/83，以及iOS CloudKitMerge + CostShare + CWLWriter 103/103；最终blocker为0
```

第一次全scheme iOS运行在UI automation session建立前因
`DebuggerVersionStore.StoreError: no debugger version` early exit；没有进入产品断言。完整unit target随后通过，
重启同一iPhone 16e simulator后UI target通过，因此记录为runner恢复，不记作产品pass前的忽略项。

最终review补跑曾以`CODE_SIGNING_ALLOWED=NO`启动focused iOS test，产品已完成编译，但test runner在
bootstrap前因缺少CloudKit entitlement退出；改用正常本地ad-hoc simulator签名和现有iPhone 16e
(`iOS 26.2`)重跑，早期focused 25/25、早期7-suite 146/146；后续准确性修复后定向36/36、7-suite
149/149，最终legacy/CWL coverage修复后CostShare 28/28、7-suite 150/150。该次失败属于harness配置，不是产品断言，且证明
CloudKit相关测试不能用去签名runner代替真实entitlement环境。

第一次默认并发Mac全套出现全局plugin fixture `acme-meter` 跨suite污染与大量deadline超时。改用Apple文档定义的
`swift test --no-parallel` 后，权威serial run仅剩3个真实suite/4 issues：pricing provenance、Grok catalog
sentinel与architecture fingerprint；均已修复并focused复测，最终serial run另行记录。

## CloudKit Production schema audit

- 最后published fork tag：`v0.52.0.1-mobile.1.21.0`；candidate：本分支未tag的
  `v0.54.0.1-mobile.1.21.0`；
- schema keyword grep无新增record type/field/index/query/zone/subscription；
- `Shared/iCloud/CloudConstants.swift` 相对published baseline无schema diff；
- `providerPayloadVersion` 保持`1`；本轮字段只位于既有`DeviceProviderSnapshot.payload` opaque JSON；
- `xcrun cktool export-schema ... --environment production` 成功，readback含既有10类：
  `AccountSnapshot`、`Device`、`DeviceLifecycleEvent`、`DeviceProviderSnapshot`、`DeviceSnapshot`、
  `Preferences`、`ProviderAccountLinkage`、`ProviderIntent`、`QuotaTransition`、`Users`；
- verdict：`NO_DEPLOY`。未执行CloudKit deploy。

## Compatibility evidence keys

- S1: old/new Shared wire fixtures + Mac producers；
- S2: independent iOS merge/cache/widget readers；
- S3: all-new iOS full simulator tests；
- S4: lifecycle/producer/schema code audit；
- S5: Production schema readback。

## 2 Mac × 2 iPhone old/new compatibility matrix

本轮 cost/provider display、Mac sync behavior与cross-version rendering均可能变化，因此gate适用。
测试完成前不得把任何行标成pass。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | S4+S5 | published baseline/code audit；未重跑4台旧binary |
| 2 | old | old | old | new | substituted | S1+S2+S5 | new reader解pre-0.53 payload；old iPhone为code audit |
| 3 | old | old | new | old | substituted | S1+S2+S5 | case 2对称 |
| 4 | old | old | new | new | substituted | S1+S2+S3+S5 | 两个new reader以unit/simulator替代 |
| 5 | old | new | old | old | substituted | S1+S4+S5 | old readers忽略additive unknown fields；无旧binary实测 |
| 6 | old | new | old | new | substituted | S1+S2+S4+S5 | mixed Mac conservative metadata + one new reader |
| 7 | old | new | new | old | substituted | S1+S2+S4+S5 | case 6对称 |
| 8 | old | new | new | new | substituted | S1+S2+S3+S5 | mixed Mac测试确认不泄漏partial modern metadata |
| 9 | new | old | old | old | substituted | S1+S4+S5 | case 5 Mac顺序对称 |
| 10 | new | old | old | new | substituted | S1+S2+S4+S5 | case 6 Mac顺序对称 |
| 11 | new | old | new | old | substituted | S1+S2+S4+S5 | case 7 Mac顺序对称 |
| 12 | new | old | new | new | substituted | S1+S2+S3+S5 | case 8 Mac顺序对称 |
| 13 | new | new | old | old | substituted | S1+S4+S5 | old decoder unknown-field compatibility仅code/fixture证明 |
| 14 | new | new | old | new | substituted | S1+S2+S3+S4+S5 | modern producer/new reader实测，old reader替代 |
| 15 | new | new | new | old | substituted | S1+S2+S3+S4+S5 | case 14对称 |
| 16 | new | new | new | new | substituted | S1+S2+S3+S5 | producer、merge、full unit/UI、Release simulator与Production schema readback |

## 替代证据与剩余风险

- S1：Mac producer + Shared round-trip + pre-0.53/future-field decode tests；
- S2：iOS `CloudKitMergeTests`、cache/widget reader与完整unit target；
- S3：iPhone 16e simulator UI target和Release build；
- S4：Codable unknown-field、old reader与producer lifecycle代码审计；
- S5：CloudKit Production schema只读export/readback。

本轮没有2 Mac + 2 iPhone old/new实体fleet，因此16行全部如实标`substituted`，不是physical pass。剩余风险：
真实Production record传播、silent push/background delivery、旧`1.21.0 (194)` binary运行行为、四设备并发写入与真实
账号数据未实测；本轮无schema deploy且additive字段在opaque payload内，风险受old/new fixtures、不同history window
fail-incomplete与conservative merge约束。
