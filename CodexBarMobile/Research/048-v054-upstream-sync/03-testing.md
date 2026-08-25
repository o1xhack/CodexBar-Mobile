# v0.54.0 Upstream Sync 测试证据

Status: `done`
Date: 2026-08-23

## 版本与范围

- old Mac: published fork `0.52.0.1 (124.1.1.21.0)`；
- new Mac candidate: `0.54.0.1 (127.1.1.22.0)`；
- old iPhone: iOS `1.21.0 (194)`；
- new iPhone candidate: iOS `1.22.0 (195)`；
- payload/CloudKit baseline: `providerPayloadVersion=1`、Production container。

## Gates

| Gate | Result | Evidence / Notes |
|---|---|---|
| Merge provenance / conflict audit | pass | merge `0e4a7f491` parents fork research commit `c0c62d1b5` + upstream peeled tag commit `22a216884`; 17 conflict paths逐项处理 |
| Mac build + lint + full tests | pass | exact-current `swift build -c release` pass（265.87s）；SwiftFormat 2026 files / 0 issues、SwiftLint 2025 files / 0 violations；serial full regression 9671 tests / 919 suites / 0 failures；末轮仅按影响面复测，没有重复整套full suite |
| Settings / CloudKit / cost / provider focused regression | pass | final custom-plugin cost bridge + Grok captured-calendar + sync focused 81/81；此前Bedrock/Cursor bucket-calendar 96/96、Grok/calendar 39/39、sync producer/mapper/wire/UTC freshness 97/97与dashboard freshness组合135/135；cost pricing race、29-provider token catalog、plugin isolation focused pass；architecture 38/38 pass |
| Parser fingerprint/hash | pass | `parserLogicVersion=13`；`regenerate-codex-parser-hash.sh` → `8b9bc662426a8aab`；lint audit pass |
| iOS build + full tests | pass | product-source unit target：731/731，0 failures / 0 skipped（device/config展开768 passed runs）；完整scheme另含UI 7 tests，3 pass / 4 fixture-dependent skipped，0 failures；版本修正后的1.22 Release simulator build再次`BUILD SUCCEEDED` |
| Widget/cost/provider display parity | pass | full iOS unit target覆盖widget/render；最终CloudKit merge + share + widget + CWL等价 + CostTab刷新时钟聚焦156/156；此前CloudKit重建 + incremental cache + merge + share + widget组合185/185 test cases（189 runs）；覆盖独立provider envelope发布时间、乱序delta metadata、modern sum、old/new conservative merge、history window comparability、producer bucket time zone、stale daily-only writer、source-window限制、producer-day scan anchor、publication uncertainty extension、跨日session隔离、Today session fallback并入daily、跨producer calendar的reader-relative day聚合、固定reference instant、producer最早午夜主动刷新、metadata-only与empty-section gate |
| iOS ledger/blob一致性 | pass | final数据库/时钟专项47/47；此前CloudKit merge + `CWLWriterTests` + `CWLAggregateTests` + `CWLEquivalenceTests`为126/126；覆盖写入去重、equal-time原子刷新、equal-timestamp旧ledger内容会由authoritative blob修复、older payload拒绝、跨设备聚合、producer day/time-zone/source freshness、stored-row/live-summary freshness与显式false优先、producer领先/落后reader、UTC+14/UTC-11极端边界，以及双Mac异时区时按原始device/provider在rollup前映射reader-relative day并精确裁剪；owner tombstone精确删除旧ledger row且clear优先；seed/backfill按cost source time与payload内容判定，不会由新quota envelope复活旧cost，也不会漏掉真正较新的或等时漂移的cost；blob/CWL等价且不会重复映射已归一化ledger日轴；reader day key固定Gregorian并保留timezone |
| iOS cost consumer一致性 | pass | full unit 731/731；mixed known/unavailable日的share total/bar/model与diagnostics availability/incomplete状态使用同一保守语义；modern unresolved、stale source、unfinished scan、legacy summary-only unknown cost与aggregate pricing gap均不泄漏Today subtotal；任一明确false会传播到主Cost aggregate，stale source同时限定Today/7天/30天并隐藏compact history；legacy无dated rows的30天汇总不会认证7天分配；不同Mac cost bucket time zone会fail closed并隐藏不可比较的metered/coverage/token mix；窗口不可比较会保守限定7天/30天派生值但不污染可信Today；dashboard model fallback不复活不可用provider breakdown；blob/CWL均保留权威`$0`；legacy sparse-day语义保持兼容；非零partial日保留Active Days证据但不显示为完整金额或Avg/Day；跨时区freshness比较使用producer calendar中的当前instant，并把producer logical day映射为reader相对日轴再跨provider聚合；CWL也按每个原始device/provider在provider/model/service rollup前使用各自producer窗口；历史完整性与Today使用同一固定reference instant，不使用reader-local midnight重切来源窗口；per-provider publication timestamp变化会进入refresh signature并触发重算；reader timezone变化会重启root/Cost/Diagnostics日期时钟；同source day下的旧session day仍会使多Mac Today fail closed，CWL explicit-false按reader-normalized Today key优先于live fallback；missing-provider fallback按cost source timestamp遵守本地clear boundary；OpenRouter provider-level cost envelope在cache中保留、在widget金额汇总中消费，但不生成额外provider row/count或重复identity；较新的provider-level clear tombstone与旧account summary原子选胜，不重复计费 |
| ASC version-state / TestFlight | pass | `1.21.0 (194)`仍为`PENDING_DEVELOPER_RELEASE` / `MANUAL`；独立train `1.22.0 (195)`已Archive并上传，ASC build `f2597f02-7056-4e70-b740-6e8b1eda6ffd`=`VALID`、`expired=false`、min iOS 17.0；未创建或提交1.22 App Store version |
| Four-language localization | pass | 1.22.0独立Latest notes block；1.21.0恢复已审核内容；新增summary含en / zh-Hans / zh-Hant / ja |
| iOS 1.22 relabel gate | pass | `xcodegen generate`；4个targets均为`MARKETING_VERSION=1.22.0` / build`195`；i18n source-key、README、CI policy、parser-version与changelog extraction通过；版本/说明diff后未重复full test suites |
| CloudKit Production schema audit | `NO_DEPLOY` | production schema成功导出并只读核对；见下节 |
| Local review blockers | pass | 累计94项产品finding均已修复；product-source commit `e52a659e0`定向review为`Blockers: 0`；随后1.22版本/说明diff本地自查为0 blocker，full lint与Release build通过 |
| GitHub PR / exact-current review | pass | PR [#99](https://github.com/o1xhack/CodexBar-Mobile/pull/99) head `4535e55bf47c291f22cc9f883fa2f2b6ffb17272` 收到 exact-current `Didn't find any major issues`；review threads `0`；`Scripts/check_pr_review_gate.sh 99`通过；merge commit `d7eddbc70d133f34e52d903dbdb4e2e9a1af7581` |
| Merge-triggered Final CI | pass | run [32614686853](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/32614686853) `completed/success`：6/6 macOS shards、2/2 Linux CLI build/test/smoke、lint与provenance/path gate全绿；未重复触发第二次full run |
| Mac signed/notarized public release | pass | phase 1 notarization submission `d9e78000-ad1b-4133-bb57-7e47d53b42a8`=`Accepted`；最终ZIP stapled/Gatekeeper/Developer ID/launch通过；`--finalize`公开[release](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.54.0.1-mobile.1.22.0)，appcast commit `f7b86b7ab`，公网ZIP `302 -> 200`，Mac Release Verify [32661301239](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/32661301239)成功 |
| Release CLI assets | pass | release-triggered run [32661301225](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/32661301225) `completed/success`；6/6平台build/smoke/package/upload成功，release共14个assets；fork按workflow契约跳过upstream-only Homebrew dispatch |
| Release issue closeout | pass | #95与#97均在public release后回复正式release/测试证据，并手动`Close as completed`；draft阶段未提前关闭 |
| issue #97 packaged Settings QA | substituted | notarized draft在本机macOS 26.5.2实际验证`Command-,`与状态栏`设置…`均打开同一个retained Settings window，重复打开稳定态仍为1个，目标runtime fault日志为0；报告环境macOS 27 beta与active Space/Stage Manager仍未直接实测 |

## 关键命令与结果

```text
xcodegen generate
  PASS，四个iOS targets生成`MARKETING_VERSION=1.22.0` / `CURRENT_PROJECT_VERSION=195`

xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile -configuration Release
  -destination 'generic/platform=iOS Simulator' ... CODE_SIGNING_ALLOWED=NO build
  PASS，iOS 1.22 Release simulator `BUILD SUCCEEDED`

bash Scripts/lint.sh audit-i18n
  PASS，全部locale为translated，全部303个source keys存在

bash Scripts/changelog-to-html.sh 0.54.0.1
  PASS，标题为`CodexBar 0.54.0.1-Mobile 1.22.0`，Sparkle version为`127.1.1.22.0`

swift build -c release
  PASS，最终exact-current Build complete (265.87s)；只有既有deprecated API warnings

swift test --filter CostProvenanceTests
  PASS，最终11 tests / 2 suites；覆盖nil cost请求归入unpriced、nil request的Int.max gap counters，
  以及多entry coverage merge/total饱和而不溢出

bash Scripts/lint.sh lint
  PASS，SwiftFormat 2026 files / 0 issues、SwiftLint 2025 files / 0 violations；
  4语言与303 source keys完整

swift test --filter 'Sync(CoordinatorTests|WireFormatRoundTripTests)'
  PASS，44 tests / 3 suites

swift test --filter 'Sync(CoordinatorTests|ProviderMapperTests|WireFormatRoundTripTests|CostIsEstimatedTests)'
  PASS，最终93 tests / 5 suites；含独立cost source timestamp、service-backed daily source timestamp、
  per-provider publication metadata不进入wire、session knownness、synthesized zero fail-closed、
  负数coverage counter、legacy/future wire、Mistral真实抓取时间/日期边界、provider mapper、重叠push与per-provider zone行为

swift test --filter 'OpenAIDashboardFetcherCreditsWaitTests|Sync(CoordinatorTests|ProviderMapperTests|WireFormatRoundTripTests|CostIsEstimatedTests)'
  PASS，最终135 tests / 6 suites；额外覆盖API-only/empty-scrape保留旧usage breakdown真实时间，而不把新API刷新时间
  误当成旧费用明细时间

swift test --filter ProviderArchitectureGatekeeperTests
  PASS，38 tests；最终scanner实际审阅集合为95项，fingerprint `469636138625236751`；
  242个allowed constructs中79个、153个suppression中28个仅按当前源码重定位exact line anchor，
  没有放宽scanner、删除旧allowlist或加入产品注释规避gate

swift test --filter CLICostTests
  PASS，28 tests；新增与`Calendar.current`日期不同的pinned-zone边界，确认CLI fetcher、totals、dashboard与
  `/cost` payload复用同一cost bucket calendar

swift test --filter 'SpendDashboardModelTests|CLICostTests|CLICostCalendarTests|CostHistoryChartMenuViewTests|XAICostUsageMappingTests'
  PASS，124 tests / 5 suites；覆盖snapshot bucket timezone优先于display/pinned calendar，以及xAI显式UTC元数据

xcodebuild ... test -only-testing:CodexBarMobileTests/CloudKitMergeTests
  PASS，83/83；覆盖较新的OpenRouter tombstone清除旧account summary，同时保留唯一
  `management-activity` provider-level费用；xcresult：
  Test-CodexBarMobile-2026.08.22_16-16-50--0700.xcresult

swift test --filter 'SyncProviderMapperTests|GrokLocalSessionScannerTests|ProviderPluginParityTests|ProviderPluginRuntimeTests'
  PASS，81 tests / 4 suites；覆盖custom plugin cost-only snapshot进入iOS additive wire、UTC day metadata、
  Grok扫描时calendar在后续投影中保持不变，以及plugin registry/parity回归

swift test --filter 'UserProviderPluginTests|SyncProviderMapperTests'
  PASS，44 tests；覆盖plugin声明window end独立于fetch instant进入sync source day，以及history上限365日、
  366日fail-closed

swift test --filter 'SyncCoordinatorTests|CostUsageTokenSnapshotDaySelectionTests|BedrockUsageStatsTests|CursorUsageEventsFetcherTests'
  PASS，96 tests / 5 suites；覆盖Bedrock Gregorian UTC查询/日桶元数据、Cursor抓取时calendar、
  token snapshot source timezone保留及SyncCoordinator优先使用source metadata而非当前/pinned timezone

swift test --no-parallel
  PASS，修复后exact-current 9671 tests / 919 suites / 0 failures / 636.083s

swift test --filter SyncMultiAccountEdgeCasesTests
  PASS，13/13；新增Mistral账号原生费用回归：Alice账单保留，Bob临时抓取失败不发共享owner clear tombstone

xcodebuild ... test -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/SwiftDataBridgeTests
  PASS，101/101；修复后按影响面复测旧新payload merge、cost owner tombstone与SwiftData持久化；xcresult：
  Test-CodexBarMobile-2026.08.22_17-24-18--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests
  PASS，修复后exact-current 731/731、0 failures / 0 skipped；device/config参数化展开为768 passed runs；xcresult：
  Test-CodexBarMobile-2026.08.22_16-27-32--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/SwiftDataBridgeTests
  PASS，最终exact-current 21/21；覆盖单一cost owner切换时把旧owner的窗口内和ledger-only旧日历史迁移到
  新owner、临时nil cost blob后仍从CWL识别旧owner，以及Mistral account-native历史不跨账号迁移；xcresult：
  Test-CodexBarMobile-2026.08.22_18-12-37--0700.xcresult

codex exec --ephemeral -s read-only <targeted exact-current review of e52a659e0>
  PASS，限定最后6个cost/SwiftData文件且不运行测试、build或network；结果`Blockers: 0`

xcodebuild ... test -only-testing:CodexBarMobileTests/CWLSeedTests \
  -only-testing:CodexBarMobileTests/CWLWriterTests \
  -only-testing:CodexBarMobileTests/CostTabInsightsResolverTests
  PASS，exact-current 47/47；覆盖equal-timestamp stale ledger payload修复与reader timezone变化使日期时钟
  restart key变化；xcresult：
  Test-CodexBarMobile-2026.08.22_10-25-21--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/CWLSeedTests \
  -only-testing:CodexBarMobileTests/SwiftDataBridgeTests
  PASS，exact-current 30/30；覆盖owner tombstone、clear优先、CWL关闭时仍删除、旧cost/新quota不复活、
  新cost/旧quota可导入。纯逻辑seed夹具使用内存SwiftData与`cloudKitDatabase: .none`；xcresult：
  Test-CodexBarMobile-2026.08.22_09-13-07--0700.xcresult

xcodebuild ... -configuration Release -destination 'generic/platform=iOS Simulator' build
  PASS，exact-current `** BUILD SUCCEEDED **`，约47.45s

xcodebuild ... test -only-testing:CodexBarMobileTests/CloudKitMergeTests
  PASS，exact-current 79/79；新增Grok local session token与OpenCode Go local cost的双Macadditive merge，
  同时保持unknown cost fail-closed；xcresult：
  Test-CodexBarMobile-2026.08.22_07-24-23--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/CostShareServiceTests \
  -only-testing:CodexBarMobileTests/CostTabInsightsResolverTests \
  -only-testing:CodexBarMobileTests/CWLAggregateTests \
  -only-testing:CodexBarMobileTests/CWLEquivalenceTests \
  -only-testing:CodexBarMobileTests/CWLPerformanceTests
  PASS，166/166 / 6 suites；最终复测UTC provider bucket、reader-relative Gregorian day、跨设备merge、
  CloudKit lower-bound、CWL数据库聚合/等价、share与365日projection性能；xcresult：
  Test-CodexBarMobile-2026.08.22_06-18-51--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/CWLAggregateTests \
  -only-testing:CodexBarMobileTests/CWLPerformanceTests
  PASS，23/23 / 2 suites；新增UTC producer领先洛杉矶reader、洛杉矶producer落后东京reader、UTC/洛杉矶双Mac
  同provider及Kiritimati/Pago_Pago极端边界回归，确认安全多取的两日只用于逐source过滤，窗口外/未来row不会进入provider total、daily、
  model mix或service mix；14.6k-row producer-calendar生产路径通过2秒内部性能断言；xcresult：
  Test-CodexBarMobile-2026.08.22_05-44-07--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/CostShareServiceTests \
  -only-testing:CodexBarMobileTests/CostTabInsightsResolverTests \
  -only-testing:CodexBarMobileTests/CWLAggregateTests \
  -only-testing:CodexBarMobileTests/CWLEquivalenceTests \
  -only-testing:CodexBarMobileTests/CWLPerformanceTests
  PASS，88/88 / 5 suites；覆盖reader-relative ledger不会再按producer calendar二次映射、极端双日边界和
  per-provider publication timestamp独立变化触发refresh；xcresult：
  Test-CodexBarMobile-2026.08.22_05-40-44--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/CWLEquivalenceTests \
  -only-testing:CodexBarMobileTests/CostTabInsightsResolverTests
  PASS，105/105 / 3 suites；覆盖相同source day但不同session day、UTC producer/洛杉矶reader明确不可用Today、
  Buddhist reader calendar仍生成Gregorian day key；xcresult：
  Test-CodexBarMobile-2026.08.22_05-56-07--0700.xcresult

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
  PASS，25 tests；覆盖Mistral dated daily rows、真实provider抓取时间，并确认无日期session fallback不会在跨午夜缓存重发时冒充Today

xcodebuild ... test -only-testing:CodexBarMobileTests/CostShareServiceTests
  PASS，最终33 tests；覆盖weekly denominator、不同Mac history window不可认证完整7天subtotal、跨时区producer
  freshness使用当前instant、summary-backed 30天Top Models排除明确不可用日、同日mixed
  provider保留已知月图金额、刚seed的30天CWL不认证缺失日期，以及partial subtotal保留Active Days证据但
  Avg/Day仍不可用；mixed provider model fallback不会复活不可用breakdown，权威`$0`保持known；legacy
  daily payload保持兼容，summary-only和CWL稀疏首日row不制造连续零值

xcodebuild ... test -only-testing:CodexBarMobileTests/CWLWriterTests \
  -only-testing:CodexBarMobileTests/CloudKitMergeTests
  PASS，74 tests / 2 suites；覆盖equal-time ledger整行原子刷新、nil→known rolling-upgrade回填与60个多Mac合并场景

xcodebuild ... test -only-testing:CodexBarMobileTests/CWLWriterTests \
  -only-testing:CodexBarMobileTests/CWLAggregateTests \
  -only-testing:CodexBarMobileTests/CWLEquivalenceTests
  PASS，最终41 tests / 3 suites；数据库写入去重、跨设备aggregate、window filter、clear tombstone及blob/CWL等价

xcodebuild ... test -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/CWLWriterTests \
  -only-testing:CodexBarMobileTests/CWLAggregateTests \
  -only-testing:CodexBarMobileTests/CWLEquivalenceTests
  PASS，最终126/126 / 4 suites；双Mac incomplete source缺少兄弟Mac已知日时，merged day保持lower-bound；
  stale cost timestamp不冒充Today、catch-up synthesized zero不认证Today、7天source不污染20天前兄弟数据；
  producer `sourceDayKey` / `sessionDayKey` / `bucketTimeZoneIdentifier`避免reader时区重切，daily-only merge保留最旧source freshness；
  不同Mac cost bucket time zone会把daily/session/history与metered/coverage/token metadata全部标成不可比较；
  stored CWL Today row还必须通过live summary freshness；窗口不可比较不会伪装成scan incomplete；
  producer领先/落后reader、双Mac各自固定不同时区时，CWL按原始device/provider在rollup前独立精确裁剪；
  同时复测CWL写入、聚合、窗口及blob等价；xcresult：
  Test-CodexBarMobile-2026.08.22_05-56-47--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/CostShareServiceTests \
  -only-testing:CodexBarMobileTests/CostDiagnosticsReportTests ...
  PASS，最终7-suite组合150/150；review指出的mixed-availability share/bar/model fallback、权威零值、CWL实际
  覆盖证据、partial Active Days/Avg/Day与diagnostics unknown/partial传播均有回归，且同run复测CWL
  aggregate/equivalence、widget、display与CloudKit merge

xcodebuild ... test -only-testing:CodexBarMobileTests/CostShareServiceTests \
  -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests
  PASS，最终43/43；选定周期外未知日不污染Today/7天卡片，30天仍标incomplete，modern unresolved Today
  widget总额fail closed

xcodebuild ... test -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/CostShareServiceTests \
  -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests
  PASS，最终122/122；真实双Mac回归确认source-level incomplete不会被兄弟Mac已知日掩盖、
  dated gap不跨日污染、stale/synthesized session不会冒充Today、known Today fallback不丢失；unfinished scan、
  stale source与aggregate pricing gap在没有date-scoped completion evidence时始终保守标记Today/week/month incomplete；
  complete-but-stale provider只保留当前来源lower-bound并明确显示incomplete；跨日session fallback不会隐藏旧Mac的
  未知Today贡献，scan起点保持producer day、publication只延伸uncertainty终点；xcresult：
  Test-CodexBarMobile-2026.08.22_02-30-01--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/CostShareServiceTests \
  -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests \
  -only-testing:CodexBarMobileTests/CWLEquivalenceTests
  PASS，最终142/142；额外覆盖Mistral UTC日桶元数据、不同history window不可认证完整weekly subtotal、
  东京reader/洛杉矶producer跨时区时以同一current instant判断source freshness，以及UTC producer day在
  洛杉矶reader仍映射到Today/7天/30天的相对日轴，mixed UTC/Los Angeles producer在blob/CWL主图也合并到
  同reader-relative day，且widget历史判定复用同一reference instant；xcresult：
  Test-CodexBarMobile-2026.08.22_03-59-23--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/CostShareServiceTests \
  -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests \
  -only-testing:CodexBarMobileTests/CWLEquivalenceTests \
  -only-testing:CodexBarMobileTests/CostTabInsightsResolverTests
  PASS，最终156/156 / 5 suites；新增producer午夜刷新键、最早日界线等待与invalid timezone过滤，确认CloudKit
  merge、blob/CWL、share和widget语义不分叉；xcresult：
  Test-CodexBarMobile-2026.08.22_04-35-49--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/ProviderUsageViewSubtitleTests \
  -only-testing:CodexBarMobileTests/CostShareServiceTests \
  -only-testing:CodexBarMobileTests/CostTabInsightsResolverTests \
  -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests \
  -only-testing:CodexBarMobileTests/CWLEquivalenceTests
  PASS，最终168/168 / 6 suites；Usage列表/详情、Cost页、诊断、widget与share全部复用producer-aware reference
  instant；分享卡默认继承insights reference，避免sheet跨午夜把两个逻辑日混在同一投影。第一次新增UI helper
  测试因Swift Testing后台executor调用MainActor金额格式化触发queue assertion；将测试明确标为`@MainActor`后同一
  产品代码与组合门禁通过，非产品或数据库断言失败。xcresult：
  Test-CodexBarMobile-2026.08.22_04-50-48--0700.xcresult

xcodebuild ... test -only-testing:CodexBarMobileTests/DualZoneReaderTests \
  -only-testing:CodexBarMobileTests/SnapshotCacheTests \
  -only-testing:CodexBarMobileTests/CloudKitMergeTests \
  -only-testing:CodexBarMobileTests/CostShareServiceTests \
  -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests
  PASS，最终185 test cases / 189 runs；同一device的每个provider保留各自CloudKit envelope发布时间，
  newer sibling delta不会刷新unchanged provider；乱序delta也保留最新device metadata，legacy summary-only
  token usage在Today/7天/30天lower-bound分享中均显示incomplete

swift test --filter SyncWireFormatRoundTripTests
  PASS，最终20/20；负数`unpriced`/`unmetered`不会归零并伪造complete cost；per-provider publication
  metadata不进入wire，旧payload/SwiftData hydration保守回退provider `lastUpdated`

codex review --base origin/mobile-dev
  后续full-head review发现3个P2：widget modern nil-Today subtotal、share period scope、negative gap counter
  fail-open；第一次exact-current rerun再发现双Mac merge丢失incomplete-source信号的P2；第二次rerun发现dated gap
  过度传播、Today session fallback丢失及7天窗口缺少boundary proof三个P2。最新rerun再发现2个P1与2个P2：
  provider refresh时间误代cost source时间、catch-up synthesized zero认证Today、短historyDays source污染宽窗口、
  pending scan被旧cached boundary row错误认证。随后一轮又发现3个P1与1个P2：明确stale Today source仍可泄漏
  其他provider subtotal、pending scan的priced Today row被过早认证、coverage window误用usage refresh时间、跨日
  session总额被挂到最新日期。最终rerun另发现2个P1：complete-but-stale source绕过Today分享卡警告，以及
  Mistral UTC observation-end误作本地刷新时间。随后一轮再发现3项：P4 per-provider envelope发布时间被device-level
  最新时间覆盖、service-backed daily误用token source时间、legacy summary-only unknown provider未触发share coverage warning。
  最新一轮继续发现3项：dashboard refresh重定时旧session、daily-only merge丢失最旧source freshness、reader时区
  误代producer session day。随后exact-current rerun再发现4项：API-only dashboard refresh沿用旧breakdown时误推进其时间、
  CWL stored Today row绕过live summary freshness、主Cost aggregate未传播明确stale provider、双Mac不同history window误把
  comparability混入scan completion。下一轮又发现2个P1：CWL explicit-false Today被live summary known覆盖，以及
  stale source只限定Today而未限定延伸到今天的7天/30天。最新一轮再发现5项：跨日session fallback遗漏旧source
  uncertainty、legacy summary-only 30天总额误认证weekly分配、stale compact history仍显示、coverage起点被publication
  前移、CLI cache重建丢失独立breakdown freshness。随后又发现2个P1：Mac固定的cost bucket time zone未进入
  producer source/session day key，以及daily-only旧Mac未参与session freshness认证。最新一轮再发现3项：Mistral
  UTC日桶被标为本地cost calendar、不同history window仍可认证weekly subtotal、reader-local midnight会误判
  producer freshness；已改为Mistral UTC元数据、weekly不可比较即fail closed及当前instant直接换算producer day。
  最后一次rerun再发现2个P1：重叠但未被选中的dashboard service明细错误推进token-backed freshness，以及
  Mistral UTC logical Today仍被Cost/share路径按reader calendar筛选。现改为只有实际fallback来源参与freshness，
  consumer按producer day offset选择并映射reader日轴。最新两项继续统一该不变量：Daily Spend的blob/CWL聚合必须先将
  每个provider logical day换算为reader-relative day，Today和historical coverage必须共用单一reference instant。
  随后又发现producer/reader跨时区时UI仍只在reader本地午夜刷新；现将全部有效producer calendar纳入刷新键并等待
  最早日界线，即使没有新的CloudKit push也会重新判断freshness。最新两项补齐Usage列表/详情的producer午夜刷新，
  并让share projection继承insights reference date。最终P1要求CWL不能先用reader-local cutoff形成rollup，再把结果
  映射为producer day；现已在聚合前按原始device ID、live provider identity和每台Mac各自producer calendar过滤，
  并对legacy保持原兼容路径；source窗口只预计算一次，避免大ledger逐行构建formatter或扫描provider。
  最近3项继续收紧同一不变量：每个source row必须在rollup前保留producer calendar身份并映射reader-relative
  day，安全读取必须覆盖全球时区的两个logical-date差，per-provider publication必须进入refresh signature。
  最新3项补齐session day独立于source day、reader-relative Today和Gregorian wire-style key三个边界。
  最新2项修复provider-native UTC bucket metadata与reader projection formatter churn。随后3项修复OpenRouter
  UTC bucket、Grok/OpenCode Go实际本地calendar metadata及Grok local session additive merge；自查另补OpenCode Go
  additive merge与Grok Gregorian day key。后续review再将provider usage与cost freshness拆开，固定provider-shared
  local cost的单一owner与owner迁移clear tombstone，保证clear优先并精确删除旧ledger行；最终seed/backfill、缺行检测、
  source-window与missing-provider fallback统一使用cost自己的source timestamp，累计68项均已按
  producer calendar / source selection / source day / publication / coverage window / boundary invalidation /
  render reference / pre-rollup windowing / clear ownership / database seeding分层语义修复；
  下一次review新增第69项P2：dashboard service rows的Mac-local calendar不可被直接标成不同的pinned token
  calendar。现在缓存记录抓取时timezone；calendar相同才合并，不同则保留token rows并fail-closed省略dashboard
  fallback，dashboard-only summary按捕获calendar发布。相关82/82与Mac full 9658/9658通过。修复后review又新增
  第70–71项P2：equal-time旧ledger内容可能绕过seed修复，以及iPhone运行期间改变reader timezone不重启日期时钟。
  现在seed缺行检查在等时比较完整payload，root/Cost/Diagnostics restart key纳入reader timezone并监听系统显著
  时间变化；数据库/时钟47/47、iOS full 727/727、Release build、architecture与full lint通过。最新review再发现
  第72项P1与第73项P2：Bedrock UTC billing day被标为pinned local calendar，Cursor抓取时current-calendar日桶也被
  标成另一套pinned calendar。现由Mac token snapshot携带真实source timezone，Bedrock查询与投影固定UTC，Cursor
  单次抓取锁定并保存实际calendar；focused 96/96、architecture 38/38（269项，fingerprint
  `14207327058727828035`）、Mac serial full 9660/9660、iOS full 727/727、Release build与full lint通过。随后
  第74–75项P1补齐custom plugin cost-only snapshot到iOS的wire桥接，并让Grok local日桶保留扫描时timezone；
  focused 81/81、architecture 38/38（269项，fingerprint `967595160927161226`）、Mac serial full
  9662/9662、iOS full 727/727、Mac/iOS Release build与full lint通过，final exact-current review待执行。
  final exact-current review随后新增第76–78项：OpenRouter Today并发响应竞态、Management Activity错误绑定所选
  API-key owner，以及plugin logical window date被误用为freshness。现由date-specific Today确定性替换history Today，
  provider-level费用发布到跨Mac稳定的`management-activity` owner且普通account发精确clear tombstone，iOS Usage隐藏
  cost-only伪账号但Cost/CWL继续消费；plugin fetch instant与window boundary彻底分离。修复后Mac focused 76/76、
  iOS focused 14/14通过；完整回归与下一轮exact-current review待执行。
```

第一次全scheme iOS运行在UI automation session建立前因
`DebuggerVersionStore.StoreError: no debugger version` early exit；没有进入产品断言。完整unit target随后通过，
重启同一iPhone 16e simulator后UI target通过，因此记录为runner恢复，不记作产品pass前的忽略项。

最终review补跑曾以`CODE_SIGNING_ALLOWED=NO`启动focused iOS test，产品已完成编译，但test runner在
bootstrap前因缺少CloudKit entitlement退出；改用正常本地ad-hoc simulator签名和现有iPhone 16e
(`iOS 26.2`)重跑，早期focused 25/25、早期7-suite 146/146；后续准确性修复后定向36/36、7-suite
149/149，最终legacy/CWL coverage修复后CostShare 28/28、7-suite 150/150。该次失败属于harness配置，不是产品断言，且证明
CloudKit相关测试不能用去签名runner代替真实entitlement环境。

数据库专项早期运行出现的`vnode unlinked while in use`来自Swift Testing纯逻辑seed夹具删除临时SQLite时局部
`ModelContext`尚未析构；路径位于simulator app的`tmp/CodexBarTests-*`，不是app-group或用户Production store。
最终将该纯逻辑夹具改为内存SwiftData并显式`cloudKitDatabase: .none`，30/30复测不再出现该清理噪声；产品的
on-disk WAL、busy timeout、foreign keys、incremental vacuum、锁竞争、级联删除与幂等写入仍由Mac/iOS数据库专项和
9658项Mac full regression覆盖。以上都不能代替真实Production多设备同步验证。

第一次默认并发Mac全套出现全局plugin fixture `acme-meter` 跨suite污染与大量deadline超时。改用Apple文档定义的
`swift test --no-parallel` 后，权威serial run仅剩3个真实suite/4 issues：pricing provenance、Grok catalog
sentinel与architecture fingerprint；均已修复并focused复测，最终serial run另行记录。

## GitHub handoff、public release、TestFlight 与 issue closeout

- product PR：[#99](https://github.com/o1xhack/CodexBar-Mobile/pull/99)，base `mobile-dev`，head
  `4535e55bf47c291f22cc9f883fa2f2b6ffb17272`；PR Fast Checks通过，exact-current Codex review明确返回
  `Didn't find any major issues`，GraphQL `reviewThreads.totalCount=0`，merge前review gate通过；
- merge：2026-08-22合入`mobile-dev`，merge commit
  `d7eddbc70d133f34e52d903dbdb4e2e9a1af7581`；合并后的Final CI
  [32614686853](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/32614686853)最终
  `completed/success`，6个macOS shard、2个Linux CLI job、lint与变更审计全部通过；
- phase 1：在clean且与`origin/mobile-dev`一致的merge commit上运行`./Scripts/release.sh`；本地Swift测试按脚本
  CI-authoritative策略未重复执行，phase 1自身的full lint、release guards与production universal build通过；
- notarization：submission `d9e78000-ad1b-4133-bb57-7e47d53b42a8`返回`Accepted`；staple/validate、
  pre-distribution checks、stapled bundle direct-launch verification均通过；
- tag：`v0.54.0.1-mobile.1.22.0` peel到上述product merge commit；2026-08-23运行
  `./Scripts/release.sh --finalize`，公开
  [release](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.54.0.1-mobile.1.22.0)，
  `draft=false`、`prerelease=false`、published at `2026-08-23T19:27:35Z`；
- appcast：commit `f7b86b7ab5a743b657d34e0a298f3f0e070b2385`已push到`mobile-dev`；remote feed
  回读title/short version `0.54.0.1`、Sparkle version `127.1.1.22.0`、length `71,847,424`，
  EdDSA signature存在且phase 2已验证；ZIP公网链路为`302 -> 200`；
- ZIP：`CodexBar-0.54.0.1-mobile.1.22.0.zip`，71,847,424 bytes，SHA-256
  `2fe6db8643dc012e090d1b4355986924f603c533eaf8fa936e4cda2e678e6113`；
- dSYM：`CodexBar-0.54.0.1-mobile.1.22.0.dSYM.zip`，55,609,020 bytes，SHA-256
  `20832e39ee6ae2e0054b4e7fc4db0c20ee7e691f2eca914d54488073d104d040`；GitHub asset digest/size
  与本地逐项一致；
- authoritative ZIP解包回读：`CFBundleShortVersionString=0.54.0.1`、
  `CFBundleVersion=127.1.1.22.0`、`CodexGitCommit=d7eddbc70`、arm64+x86_64；Developer ID
  `Yuxiao Wang (3TUERHN53E)`、Gatekeeper `source=Notarized Developer ID`、stapler validate通过；
  主app entitlement回读`com.apple.developer.icloud-container-environment=Production`。仓库根目录
  `CodexBar.app`是staple前中间产物，不能替代最终ZIP验收；
- issue #97 packaged QA：机器为macOS 26.5.2。先按exact executable path/PID隔离draft，避免同bundle ID的
  `/Applications/CodexBar.app`污染证据；draft PID启动前0 window，`Command-,`后1个前台standard Settings
  window；重复快捷键与重复状态栏`设置…`在稳定态均保持同一title/position/size与1 window；状态栏入口从0
  window重新打开也为1 window；`log show`未出现`SettingsLink`、`runtime-issues`、`showSettingsWindow`或
  `showPreferencesWindow`fault。截图：`/tmp/codexbar-v054-draft-settings-reuse.png`；
- 限制：本机不是macOS 27 beta，且未做active Space / Stage Manager跨stage直接验证，因此issue #97的
  macOS 27环境证据仍标`substituted`，不能写成macOS 27 physical pass；
- iOS archive：`/tmp/CodexBarMobile-20260823-123024.xcarchive`，回读
  `CFBundleShortVersionString=1.22.0`、`CFBundleVersion=195`、bundle ID
  `com.o1xhack.codexbar.mobile`；app entitlement为CloudKit `Production`；
- iOS upload：`xcodebuild -exportArchive`返回`Upload succeeded` / `EXPORT SUCCEEDED`；ASC build
  `f2597f02-7056-4e70-b740-6e8b1eda6ffd`于`2026-08-23T19:35:00Z`回读为`VALID`、
  `expired=false`、min iOS 17.0、pre-release train `1.22.0`；
- App icon三层验收：1024x1024源图无alpha且视觉正确；archive内`AppIcon60x60@2x.png`为120x120、
  无alpha且视觉正确；ASC `iconAssetToken`存在，Apple CDN返回152x152正确图标；
- issue [#95](https://github.com/o1xhack/CodexBar-Mobile/issues/95)与
  [#97](https://github.com/o1xhack/CodexBar-Mobile/issues/97)在draft阶段均保持`OPEN`；public release后分别
  [回复#95 release证据](https://github.com/o1xhack/CodexBar-Mobile/issues/95#issuecomment-5388042853)与
  [回复#97修复/限制证据](https://github.com/o1xhack/CodexBar-Mobile/issues/97#issuecomment-5388042982)，
  并手动`Close as completed`。

## CloudKit Production schema audit

- 审计基线published fork tag：`v0.52.0.1-mobile.1.21.0`；candidate tag：
  `v0.54.0.1-mobile.1.22.0`（审计后已公开）；
- schema keyword grep无新增record type/field/index/query/zone/subscription；
- `Shared/iCloud/CloudConstants.swift` 相对published baseline无schema diff；
- `providerPayloadVersion` 保持`1`；包括最终新增的optional `sourceUpdatedAt` / `sessionCostIsKnown` /
  `sourceDayKey` / `sessionDayKey` / `bucketTimeZoneIdentifier` / `historyWindowIsComparable`在内，
  本轮字段都只位于既有`DeviceProviderSnapshot.payload` opaque JSON，不新增CKRecord field/index/type；
- optional `costSummaryCleared`同样只在上述opaque JSON内表达provider/account owner迁移的clear tombstone；旧reader
  忽略未知字段，旧payload在new reader解码为`nil`，不新增CKRecord或SwiftData schema字段；
- `usageBreakdownUpdatedAt`只存在于Mac本地Codable dashboard cache，用于避免API-only刷新给旧费用明细重新定时；
  不进入Shared wire、CloudKit record或iOS SwiftData模型；
- `usageBreakdownTimeZoneIdentifier`同样只存在于Mac本地dashboard cache，用于保留usage breakdown抓取时calendar；
  不进入Shared wire、CloudKit record或iOS SwiftData模型；
- `CostUsageTokenSnapshot.bucketTimeZoneIdentifier`只存在于Mac进程内token snapshot，用于把Bedrock/Cursor等来源的
  已生成day key与其真实calendar一起交给SyncCoordinator；最终仍只映射到既有opaque payload内已审计的
  `SyncCostSummary.bucketTimeZoneIdentifier`，不新增CKRecord或SwiftData schema字段；
- custom provider plugin的`costUsage`现复用同一个`SyncCostSummary` opaque payload bridge，plugin日桶固定UTC；
  Grok的扫描时IANA timezone也只作为该opaque payload中既有optional calendar metadata发布；两者均不新增
  CKRecord field/type/index或iOS SwiftData字段；
- OpenRouter `management-activity`只复用既有`accountRecordKey`、`accountIdentities`、`costSummary`与
  `costSummaryCleared` opaque payload字段，未新增record type/field/index或SwiftData属性；
- `providerPublicationTimestamps`只由既有`ProviderUsageEnvelope.syncTimestamp`在iOS内存重建，明确不编码到wire；
  冷启动SwiftData hydration使用已持久化的provider `lastUpdated`保守回退，不新增SwiftData/CloudKit schema字段；
- 2026-08-22再次执行`xcrun cktool export-schema ... --environment production`成功，readback含既有10类：
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
账号数据未实测；issue #97的macOS 27 beta、active Space与Stage Manager也没有目标环境physical pass。本轮无schema
deploy且additive字段在opaque payload内，风险受old/new fixtures、不同history window fail-incomplete与conservative
merge约束；Settings风险由retained controller/placeholder guard单元测试与macOS 26.5.2 notarized draft UI替代验证约束。
