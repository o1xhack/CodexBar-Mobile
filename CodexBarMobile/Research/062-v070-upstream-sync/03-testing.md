# 本轮测试证据

Status: `in-progress`

当前 Mac 完整回归已通过；iOS 原始313单元与生产组件离屏渲染已通过。16组合已有冻结旧/新 wire、真实合并与独立磁盘缓存替代证据；真实 App UI、实体 CloudKit/APNs、GitHub PR/CR 与 Mac draft 仍未完成。历史段落按发生顺序保留，旧 pending 不代表当前结果。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 1 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 2 | old | old | old | new | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 2 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 3 | old | old | new | old | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 3 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 4 | old | old | new | new | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 4 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 5 | old | new | old | old | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 5 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 6 | old | new | old | new | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 6 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 7 | old | new | new | old | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 7 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 8 | old | new | new | new | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 8 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 9 | new | old | old | old | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 9 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 10 | new | old | old | new | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 10 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 11 | new | old | new | old | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 11 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 12 | new | old | new | new | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 12 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 13 | new | new | old | old | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 13 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 14 | new | new | old | new | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 14 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 15 | new | new | new | old | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 15 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |
| 16 | new | new | new | new | substituted（wire + merge + iOS disk） | frozen-consumer-matrix-r4/matrix-wire.json + frozen-ios-cache-r4/matrix-cache.json case 16 | 缺真实四设备；独立冷缓存/ghost prune通过，UI/Production/APNs未验证 |

## 当前命令证据

日志目录 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070`。

- mac-build-tests.log：swift build --build-tests，exit0，326.65秒；初次merge tree构建，不覆盖之后parser18和period细化。
- mac-focused-r1.log：Scripts/test_fast.sh，41 tests / 6 suites / 0 failed。对应filter GrokTokenSnapshotProjectionTests、SyncV070PartialHistoryTests、WidgetEmptyProjectionTests、QuotaBurndownModelTests、KimiMonthlyBlockingTests、ClaudeRateLimitResetCreditsTests。
- test-fast-runner-r2.log：环境脱敏及runner黑盒10 tests，exit0。
- CI policy、CI path gate、fork README guard通过。
- lint.log：Python3.9缺waitid，失败；lint-r2.log：env fixture没有识别--skip-build，失败；lint-r3.log：social image token不一致，失败；以上没有作为最终lint通过证据。
- mac-full-r1.log：完整测试已启动，session81548，仍需查询进程终态与实际计数，不得按启动视为通过。

## 后续验证状态（2026-10-01）

- lint-r4.log：portable/JS/SwiftFormat通过，SwiftLint发现新增测试12处multiline arguments；只修正两份测试参数换行，定向SwiftFormat/SwiftLint零违规。
- lint-r5.log：此前gates再次通过；扫描期间新增Claude桥接测试，SwiftLint发现1处Data→String规则，现已改用failable initializer，新增两测试文件定向lint通过。全树最终lint仍待终态。
- mac-full-r1.log：1518 selections以group-size=1执行到约第133组；因为后续Kimi/Claude桥接实现改变了受测源码，显式SIGINT停止旧binary运行，exit130。已运行部分只能作早期回归证据，不是完整pass。最新源码需重建并用默认group-size=12重新完整跑；不把中断计为测试失败修复或通过。
- mac-bridge-r1.log：最新Mac桥接、Grok projection、parser cache定向构建/测试已启动，session32408，结果尚待查询。

- lint-r6.log：exit0，全树所有lint与安全/CI/发布脚本guards通过；SwiftLint2749 files零违规，iOS367 source keys齐全且四语言translated。随后modelsUsed的Shared/mapper/test定向SwiftLint零违规。
- mac-bridge-r1.log：Core internal makeSection从app不可访问，编译失败；改为过滤已映射的Sync detail section。
- mac-bridge-r2.log：exit0，11 tests / 4 suites；mac-bridge-r3.log：exit0，12 tests / 4 suites，包含Kimi真实pusher与native Claude wire。
- mac-bridge-r4.log：新增modelsUsed wire roundtrip及旧JSON fallback后重跑；成功后同一session46144自动执行mac-full-r2.log（repo默认12 selections/group、180s timeout）。必须读取r4与full-r2终态，不能把pipeline启动作通过。

mac-bridge-r4.log最新树构建与12 tests/4 suites通过，含modelsUsed wire roundtrip/旧JSON fallback；同pipeline已进入mac-full-r2，137 groups（12 selections/group），当前未结束。session46144维持运行。

## 冻结 Shared 序列化兼容（阶段证据，不是完整矩阵）

使用最后正式发布v0.68.0.1-mobile.2.3.0的精确Shared源码（commit616701b95122c94e106299d18ac6a83c61850d94）与当前Shared源码，分别编译Foundation-only独立reader/writer。16份Swift源文件SHA256记录在BuildScratch/upstream-v070/frozen-wire-r5/source-manifest.json；构建、module cache与TMPDIR均在SSD，未调用CloudSyncManager、Keychain或真实数据库。

可复现命令：`PATH=/opt/homebrew/bin:$PATH python3 CodexBarMobile/Research/062-v070-upstream-sync/tools/check_frozen_wire.py --old-ref v0.68.0.1-mobile.2.3.0 --scratch /Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070/frozen-wire-r5`。exit0，全部16 wire-only masks/64独立reader进程通过。旧reader读取新effective blocked百分比与monthly reset，新reader恢复raw metadata/modelsUsed；旧缺字段payload读为nil；独立deviceID、未知cost、envelope encode/decode roundtrip均断言。日志matrix-wire.log与JSON逐条readOperations记录。

该fixture是合成writer数据，不是旧Mac运行时或真实CK记录；没有测试iOS merger、SwiftData、UI、fallback/ghost清理、Production收敛、subscriptions/APNs。表中16组合保持pending，后续完整iOS替代验证与可用硬件检查完成后才逐格定最终result。初次工具preflight错误使用diskutil plist不存在的Mounted key导致早停；已改为MountPoint+os.path.ismount并验证正确UUID，再成功运行。

## 完整 Mac 回归失败与隔离修正

mac-full-r2.log终态exit1：1520 selections /137 groups，首轮52组成功、1组失败；失败组重试一次未恢复，无timeout。discovery10.3秒，execution660.5秒。唯一finding是CostUsageClaudeKimiAliasTests:151的cacheDecodes期望0实际1，其真实cost/tokens、0 transcript parse、0 cache encode、reprice count与bytes未失败。未运行剩余组，不能标为完整通过。

独立suite复测mac-alias-isolated-r1.log（7 tests）和同12-suite组mac-alias-group-r1.log（64 tests）通过，但不足以抹去完整失败。CacheIO与upstream没有差异，NSCache驻留不是保证；具体驱逐原因没有证实。既有fixture cleanup已经evict对应artifact/report memo，不能归因于未cleanup。

新增DEBUG TaskLocal自有retained ArtifactMemo，仅pricing fixture作用域保持驻留；生产仍shared NSCache countLimit4，不清全局其它测试的cache。原warm与report-memory-cold严格断言全部保留，另显式清report memory+persisted+artifact验证真正cold decode=1、parse/encode0、价格/token与bytes正确。独立只读review无阻塞。mac-alias-group-r2编译发现嵌套private initializer外层不可访问，已修正为private type内可访问init，r3重新验证。parserhash仍11b5eaedd0f337a7 current。

## 上游重型 CI provenance

v0.70.0精确tag commit `fcaffd75ace3790cca3b768ae3fd3293281692ce`的22 check runs已读取至BuildScratch/upstream-v070/upstream-v070-checks.tsv。release publish、六平台CLI build与Linux desktop build成功；该commit的lint、Mac两shards、Mac compatibility、Linux CI jobs为cancelled（musl为skipped），aggregate lint-build-test也cancelled。不能把release已发布或CLI build成功当作上游完整heavy test成功，更不能宣称满足fork upstream-heavy复用gate；以后获准push/merge时Final CI应按现有verifier决定回退本仓库完整矩阵。本Goal当前不授权remote dispatch/push。

## 修正后的最新验证

- mac-alias-group-r3.log：exit0，64 tests /12 suites，4.213秒，包含warm驻留、report-memory cold与显式artifact cold解码断言。
- lint-r7.log：exit0，全树guards、SwiftFormat、SwiftLint通过；2749 files零违规，367个iOS source keys四语言齐全且translated。
- frozen-wire-r5.log：exit0，格式化后harness再次通过16 wire-only masks/64独立reader进程，source-manifest含harness SHA256。
- mac-full-r3.log：以最新代码重新完整构建并运行137 groups，session70586；仍在执行，尚未标记为最终pass。

独立review核查冻结文件集合、SHA256与断言，无阻塞；随后按manifest paths编译以排除scratch遗留源码，新增windowID/rawResetsAt断言，输出改称JSON roundtrip，frozen-wire-r5再测exit0。

只读硬件inventory：devicectl列出一台connected实体iPhone Air，另一台实体iPhone17ProMax为unavailable。当前尚未确认第二台Mac远程可操作性，且没有安装/覆盖实体app或访问真实CloudKit。后续矩阵需先确认硬件与旧/新binary可重现范围，不把Simulator或wire fixture当作实体收敛证据。

## Mac r3 完整回归终态与安全修正

`mac-full-r3.log`终态exit1：1520 selections /137 groups，100组首轮成功、1组失败，整组重试仍失败，无timeout；discovery16.4秒、execution982.6秒、total998.9秒。此前失败的第53组已通过（64 tests /12 suites，4.776秒），确认缓存驻留修正有效；本次唯一未预期finding是`ProcessEnvironmentStorageTests`在Alibaba新增`SubscriptionSummaryContext`与`RateLimitContext`发现两个未脱敏存储的environment字典（其它14 issues为已知issue）。未运行剩余36组，不能标记全量通过。

两个context的environment改为`@ProcessEnvironment private(set) var`，与既有PersonalAPIContext一致，保留执行值并对自动Mirror/description脱敏；没有增加transient exception或放宽security测试。单文件SwiftFormat/SwiftLint零违规；`mac-env-storage-r1.log`定向安全与Alibaba构建测试、`lint-r8.log`最新全树lint执行中。成功后需对最新tree重新完整回归。

`mac-env-storage-r1.log`终态exit0，102 tests /20 suites，2.783秒（14 known issues，非新增失败）；`lint-r8.log`终态exit0，2749 Swift files零违规，安全/CI/发布脚本与本地化/parser guards通过。独立review确认两context wrapper保持memberwise init/执行字典/Sendable行为，Sources/WidgetExtension按security scanner同规则无其余未包装存储。

修正后新一轮完整`mac-full-r4.log`仍采用repo默认12 selections/group与180s timeout；等待终态，不把定向通过替代全量。

## Universal Release 无凭据构建

`mac-release-preflight-r1.log`终态exit0，692.99秒。命令`swift build -c release --arch arm64 --arch x86_64 --scratch-path /Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070/mac-release-preflight --jobs 2`，TMPDIR在本轮SSD scratch。独立构建不修改完整测试的.build；compiler module-cache-path均在此scratch的out/Intermediates.noindex/SwiftExplicitPrecompiledModules。

`mac-release-preflight-artifacts.json`记录source commit `c0343b3a2`对应完整SHA、3个product SHA256/UUID。CodexBar、CodexBarCLI、CodexBarWidget的lipo实际均为arm64+x86_64，otool两slice的LC_BUILD_VERSION实际minos均14.0，dSYM UUID与binary逐项匹配。构建日志的Xcode SDK x86_64 deprecation warning没有改变实际最低系统版本。此证据仅证明Release compiler与universal/dSYM，不是Developer ID签名、打包、公证或GitHub draft证据；未读取/使用发布凭证，也未运行binary触发真实provider或Keychain。完整mac-full-r4仍在执行。

## Mac r4 终态与 provider 架构说明

`mac-full-r4.log`终态exit1：1520 selections /137 groups，101组首轮成功、1组失败、整组重试未恢复、无timeout，discovery19.4秒、execution1263.8秒。`ProcessEnvironmentStorageTests`本轮通过，确认Alibaba存储脱敏修正；本次唯一finding为`ProviderArchitectureGatekeeperTests`在`SyncCoordinator.mapSyncedDetails`的Claude专属过滤没有紧邻construct的明确设计理由。函数doc comment已说明live-only，但gate要求精确`// Provider-specific by design: <specific reason>`格式。

紧邻Claude guard补充明确理由：native Claude reset-credit inventory仅可实时使用，不能持久存入iOS。没有改动过滤行为、新增例外或放宽架构检测；定向架构与两桥接suite(`mac-architecture-r1.log`)及最新全树lint(`lint-r9.log`)验证中。r4未完成其余35组，不能称全量通过。

候选tag `v0.70.0.1-mobile.2.3.0`只读查询返回release not found（BuildScratch/draft-candidate-readback.stderr），尚未创建草稿。正式创建前再次回读防止并发重复。

`mac-architecture-r1.log`终态exit0，53 tests /3 suites，6.643秒；包含全架构gate与Claude库存/Kimi阻塞桥接，单文件SwiftFormat/SwiftLint零违规。`lint-r9.log`仍执行中；下一轮完整`mac-full-r5.log`继续原默认137组，不用定向测试替代全量。

`lint-r9.log`终态exit0：2749 Swift files零违规，367 source keys四语言齐全，安全/脚本/CI/parser guards全部通过。mac-full-r5保持原进程运行中。

## iOS consumer 基线构建

为提前验证Mac→iOS Shared改动，使用XcodeBuildMCP build_sim compile-only：source `bc26b3512`、xcodegen按现有project.yml生成；Debug/iOS27 Simulator，独立DerivedData `BuildScratch/upstream-v070/ios-baseline`，CODE_SIGNING_ALLOWED=NO、jobs2，未安装/启动App。Build succeeded，51.3秒；日志已复制至`ios-baseline-build.log`。产物Info.plist确认为现有2.3.0 (226)，未提前变更2.4.0版本/说明。App、Shared framework、push/widget extensions编译通过；两处CloudSyncManager save unused warning是现有代码诊断，没有编译错误。

该证据仅为现有consumer编译兼容；不是新iOS功能完成、单元测试通过、四语言UI渲染、真实CloudKit同步或16组合矩阵证据。新iOS实施仍按05设计继续，最终新版本须重新build/test。

## iOS Shared consumer 定向基线测试

XcodeBuildMCP test_sim选择SyncModelTests、AccountIdentityMergeTests、CloudKitMergeTests、WidgetSnapshotBuilderTests；原工程2.3.0(226)、source `62afccdd2`、iOS27 booted Simulator、CODE_SIGNING_ALLOWED=NO、parallel-testing=NO。unit host经源码确认使用PreviewData，跳过同步观察/通知注册；测试使用合成payload，未访问实体iPhone或真实CloudKit。结果SUCCEEDED，61.877秒，153 passed /0 failed /0 skipped。包含未知未来字段/legacy JSON、账号隔离、多Mac费用合并、KVS fallback、widget Today totals与Cost dashboard parity及既有Today cost old/new合成矩阵。

证据：`ios-baseline-tests-r1.log`、`ios-baseline-tests-r1-summary.json`、`ios-baseline/tests-r1.xcresult`。工具默认生成的本次自有prepared test bundle已移至`ios-baseline/baseline-r1.xctestproducts`，后续可显式引用SSD路径；不更改其它tool-managed产物。该结果仅覆盖既有consumer基线与此四suite，不等于新2.4.0功能、完整iOS测试、真实sync或本轮16组合矩阵完成。

## 最终完整 Mac 回归通过

`mac-full-r5.log`已终态exit0：1520 discovered/selected selections、137 selected groups、137 first-pass successful groups、0 failed、0 retries、0 timeouts。discovery9.7秒、execution1308.6秒、total1318.3秒。运行源码checkpoint `bc26b3512`；其后仅Research变化，当前Sources/Tests/Shared/Package/WidgetExtension/version.env inputs diff为空。缓存定价组、ProcessEnvironmentStorageTests、ProviderArchitectureGatekeeperTests在同一完整运行中通过；没有删除失败测试、放宽断言或使用定向pass替代完整gate。

完整runner包括安全test_environment、Mac/Core/CLI/Plugin回归；native proof与live-provider opt-in fixture的既有skip/known-issue策略保持，不能据此宣称真实账号/实体设备QA完成。结合lint-r9、universal Release compiler预检及独立checkpoint review clean，Mac源码准备gate通过。签名/公证/生产entitlements资产验收和GitHub草稿尚无证据；iOS新功能与16矩阵仍pending。

## iOS consumer 复测记录（2026-10-01）

日志与 xcresult 均位于本页上述 BuildScratch 目录。

- ios-consumer-build-r1：exit65，新测试缺必填 reset 参数；修正后 build-r2 exit0，TEST BUILD SUCCEEDED。
- ios-consumer-tests-r1：exit65，174 tests / 7 suites，15 issues；历史 fixture 使用未来 capture 却较旧 publication，另有旧 window-duration union 预期。实现分离 history publication 与 cost 时间语义，修正 fixture 的真实 observation/publication 时间关系。
- ios-consumer-tests-r2：exit65，240 tests / 9 suites，6 issues；颜色旧 golden 两项、hyphen alias 四项。数据与新增展示测试通过不代表整轮通过。
- ios-consumer-tests-r3：exit65，242 tests / 9 suites，1 issue；Venice golden 未反映新增白底 luminance ceiling，已用独立 WCAG 算法更新预期。
- ios-consumer-tests-r4：运行中，尚无终态；不得作为通过证据。开始后新增真正旧 schema migration 与 publication cold-start 修复，r4 即使通过也不覆盖这些后续输入。
- lint-r10：exit0；随后增加 publication/migration 修复，最终树仍须重跑 lint。

上述都是 Simulator / synthetic fixture 验证，不证明 Production CloudKit、APNs 或完整四设备收敛。现有 frozen-wire 16 组合是编解码阶段替代证据，仍需 consumer merger/cache/render 的逐格补充，不能替换全部 canonical gate。

- lint-r11：exit1，102 process-cleanup tests / 1 failure / 1 skip；失败是 success fixture 在 drain 时尚未退出，断言 None != 0。单独重跑同一 test：lint-r11-process-focused.log exit0，fixture child terminated/sentinel alive，未修改 runner 或缩弱断言；全 lint-r12 已启动，终态待查，不能以 focused pass 替代全 lint。
- ios-consumer-tests-r5：使用专用 Simulator `D86C3D2C-7A29-43C6-9B22-5B61902B794B` 与隔离 ios-consumer-final DerivedData 验证新增 publication 与 old-ledger migration。r4 原 Simulator 同时被另一项目使用，进程仍 live，未因观察等待而重启或终止。r5 是新增源码验证，非重复 r4 结果。

## 数据层本地提交前状态

- lint-r12 exit0：2749 文件零违规，381 literal source keys 全部匹配 catalog、全语言 translated；后续完整旧 schema fixture 与 UI visibility/preview 历史扩展不在该开始时输入内，另外新增文件定向 lint-r4 exit0 / 4 文件零违规。
- 数据层六个生产文件在 ios-consumer-tests-r5 已经过 SwiftCompile、link 与 app Validate，未见编译错误；xcodebuild 仍在 test launch 阶段，尚无 tests terminal。不能把编译阶段当 test pass。
- 新完整旧 schema fixture、UI 测试和 synthetic demo history 尚需下一轮实际 build/test；UI 数据为 synthetic，不访问用户 provider/CloudKit。
- r4/session11533、r5/session17532 均 live；专用 Simulator app-container 查询也未返回，诊断句柄97447与进程 sample 19272 仍待查询。未因 observation timeout 取消或重启任何 live run，也未重启全局 CoreSimulator。

本地保存 consumer 数据层 checkpoint；包含 actual-observation history merge、token-only 模型名流转与 publication 持久化，尚未完成 migration/runtime release gate，不执行 push/PR/merge/draft。

## 16 组合 wire + consumer merge 替代证据

`frozen-consumer-matrix-r3.log` exit0；真实旧发行 tag `v0.68.0.1-mobile.2.3.0` 的 Shared model 和 ProviderSnapshotMerger、当前树对应源码分别编译为两个独立 reader executable。每组两 reader 各运行两 writer envelope decode/roundtrip、一次双 writer merge，共 64 read + 32 merge process，全部通过。每次 merge 同时验证正/反输入顺序、Kimi legacy/effective availability 与 reset、account-native summary、两个虚构本地 Codex token contribution 的 24-token 汇总和 cost unavailable；新 reader 检查 optional blocking metadata/model-name union；删除 writer 后只剩 12-token contribution。旧 reader 使用真实旧 merger，未模拟旧策略。fixture Codex token contribution 从虚构 envelope summary 构造，没有真实账户读写。

真实硬件不足且当前 Simulator test launch 未取得结果；因此表格仅把 wire+merge 阶段标 substituted，不能推断完整 matrix gate 已通过。SwiftData cache、UI render、Production records/APNs 与两手机实际收敛仍未证明。每个旧/新源码 SHA 与 harness SHA、oldCommit/newCommit 见 `frozen-consumer-matrix-r3/source-manifest.json`；编译仅移除同 module 自引用 import，不改算法。首轮 r1 在 mask0 的 retained.deviceID 断言失败：production merged snapshot 正常为 nil，测试错误要求 mac-a；改为检查保留 deviceName 与 12 token，r2 全部通过。未修改生产代码迎合 harness。

2026-10-01 再次 devicectl read-only inventory：physical iPhone Air connected；physical iPhone 17 Pro Max unavailable。其余可用 iPhone/iPad 均 simulated，不能算第二台真实 iPhone。未连接或安装任何设备。本轮 Simulator install/query/sample 仍 live，不能据此声称启动成功；另外启动 ios-ui-build-final（generic Simulator build-for-testing，无启动/安装）以验证完整旧 schema fixture 和四语言 UI 当前最终输入的编译，日志待终态。

独立 matrix review 核对所有 17 个源码 hashes 对应各自真实 old/new source，只删 module self-import，无旧新算法混用；建议补 account-native summary 直接断言，现已增加 Kimi 12 tokens / unavailable，而不是只验证 quota。r3 exit0，再次完整 16 masks / 64 reads / 32 merge processes。移除 writer 仅验证无状态 reduction，尚不证明 SwiftData tombstone 或 CloudKit 删除收敛。

`ios-ui-build-final.log` exit0，TEST BUILD SUCCEEDED；generic Simulator arm64/x86_64 当前主应用、extensions、全部 unit/UI tests 编译完成。之后调整的是行换行与既有字符串同内容格式；不更改运行逻辑。`ios-final-tests-r6` 使用该构建在新专用 iOS26.5 Simulator 7216E120-B46B-43D5-A78C-93A096A3D5A3 运行最新完整 migration/UI 与既有 consumer/CWL/presentation/widget totals gate，尚待终态；并未取消 r4/r5 或把等待等同失败。


## iOS 显示边界与测试启动诊断更新

- `MobileDisplayPreferences` 对真实超额用量仍显示 140%，remaining 为 0%；仅进度条限制到 0...1。`Int(exactly:)` 避免极大 finite 值转换 trap，NaN/±Infinity 的完整 label 为既有四语言 `Usage unavailable`，不会拼接 used/left。UsageCard 同步 finite guard，新增双模式回归断言。
- `overage-pure/build-r2.log` / `run-r2.log` 均 exit0：将当前真实 formatter 源码与 Shared models 编译并实际运行，覆盖 0 / 0.5 / 78 / 100 / 140 / 1e30 / NaN / ±Infinity。只移除同 module 的 import；这是 macOS pure formatter 验证，不代替 iOS runtime。`ios-overage-typecheck-r3.log` exit0，使用当前真实 CodexBarSync framework、iOS 17 deployment target 和 Simulator SDK。r2 typecheck 因误用 -I 而找不到 framework module 失败；改为 -F 后通过，没有修改实现。
- 定向 `ios-changed-all-lint-r4.json` 覆盖 26 个本轮 Swift 文件：SwiftLint exit2，824 个报告全部落在 1d7ff545c 对照的未修改行，新增行零报告。分类详见 `ios-changed-lint-classification-r4.json`；不能称整个 iOS 目录 lint 零违规。修复新增 multiline arguments，并缩短五条英文 release note key；全部四语言 translated，`ios-localized-final-r2.log` 的 381 source keys 全匹配。最新独立 reviewer 对 formatter/card finite guard、边界测试与 release note 四语言映射审查 clean，仅源码/JSON 审查。
- `frozen-consumer-matrix-r4.log` exit0：最终 merger 换行后重新编译真实旧/新源，16 masks、64 wire reads、32 consumer merges 全通过；r4 source-manifest 对应本轮最终 merger 字节。仍只证明 wire+merge 阶段，不证明缓存、UI、Production/APNs 或真实四设备收敛。
- 最新 r6 的实际 Session log 显示：testmanagerd 控制连接成功；20:23:12 开始安装，20:23:31 安装完成并发出 launch request，随后尚无测试 App PID / stdout / terminal。launchctl 只见 testmanagerd，未见主应用进程；这只能定位到 launch 阶段，不确认原因。r4/r5/r6 的 xcodebuild PID 64477 / 70255 / 84611 均 live，未因 observation timeout 终止或重启。
- sim-use 0.14.0 read-only inventory 确认专用 iOS26.5 Simulator booted；ui 预检返回 `No translation object returned for simulator`。这不是系统 permission dialog 的已验证证据；未进行坐标操作、未操作真实手机。专用 UI、host CoreSimulator 与 runningboardd 限定日志未取得可解释的错误。没有关闭其他项目 Simulator 或重启全局服务。
- 后续新增 formatter 与 note key 输入通过独立 `ios-display-final` DerivedData 重新 build-for-testing，session5065 / `ios-display-build-final.log` 尚待终态；不覆盖或修改当前 r6 的旧构建目录。r6 不包含后加入的 formatter 测试，因此即使其通过，仍需最终当前输入测试。


`ios-display-build-final.log` exit0、TEST BUILD SUCCEEDED；主应用、extensions 和所有测试目标编译通过。因为本次英文 key 收尾发生在该 build 开始之后，另在停止修改源码后执行同 DerivedData 的 incremental `ios-display-build-stable.log`，用于固定最终输入，现已 exit0 / TEST BUILD SUCCEEDED；不在 r6 运行目录写入。

系统调试授权调查仅取得间接证据：`DevToolsSecurity -status` 为 disabled，SecurityAgent PID60124 live；CUA 的 Xcode 只读界面未显示调试弹窗，而读取 SecurityAgent 被工具安全策略明确禁止。未启用 Developer Tools、未操作系统授权窗口或获取密码。这不是已确认的根因；已请用户在本机检查是否有 Developer Tools Access 授权提示，等待其观察/处理反馈。源码与构建工作继续，不把此状态当作 iOS tests failure 或 pass。


## 磁盘迁移与 publication 重启的独立运行证据

`consumer-mac-runtime-r1/build-r3.log` / `run-r3.log` 均 exit0：完整五实体 legacy migration 和 opposing device clocks 的 publication disk reopening 两项测试的全部断言实际通过。独立 reviewer 核对 25 个当前 production 副本 hashes、完整 LegacyV230Ledger 与两原方法一致；17+5 个 expect 与 3+2 个 require 全部保留。断言只转换为 precondition 与 throwing require，未替换生产存储、factory、merger 算法。

可重复入口：`tools/check_consumer_disk.py --scratch /Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070/<fresh-run>`。`consumer-mac-runtime-repro.log` / `consumer-mac-runtime-repro/{build.log,run.log}` 全部 exit0。入口重新从当前原测试提取两方法和旧 schema、冻结当前真实 production 文件，并记录 test/harness/source SHA 与 compile-command。仅移除同 module import，SwiftData 操作使用 SSD 自有 UUID fixture 路径、cloudKitDatabase.none 和显式 factory URL；没有读取真实 iOS app store 或 Keychain、没有 CloudKit 网络调用。publication upsert 的 cost hook 会读取命令行进程 UserDefaults.standard 的 cwlEnabled 开关，不能声称完全没有 defaults 读取；不调用 app-group migration 或共享 store singleton。

此结果是 **macOS SwiftData 运行证据**，补强旧 schema 数据保留与新 publication 字段的实际磁盘读写，不证明 iOS 版本的 SwiftData runtime、UI 或 16 组设备/cache/APNs gate 已通过。首轮 harness compile 使用不存在的 CocoaError code 失败；改为自身 synthetic NSError 后编译运行通过，未修改任何生产文件或削弱断言。

截至本 checkpoint：iOS 2.4.0 (227) feature/presentation/localization/source 已实现，最终 generic Simulator 编译通过；本地保存代码供后续运行验证与 review，不将 checkpoint 当 release 或 Code Complete。r4/r5/r6 仍 live，UI/完整 iOS runtime/实际多设备收敛待证据；不 push、不开 PR、不 merge、不签名公证或创建 Mac draft。


## 完整 review 发现的 quota 历史同源问题

独立 reviewer 在确切 3cff48ff9 找到功能阻塞：按任意 id/label 的 weekly/opus 子串或 period 映射，会将 Claude `claude-weekly-scoped-<model>` 专属额度接到账户级 weekly/opus 历史；同 reset/duration 下仍是不同额度。生产 `UsageStore+PlanUtilization` 只记录三个 native roles，不记录 scoped extras。

已取消子串/period 作为同源证明：Claude 仅 native primary/secondary/tertiary 对应 session/weekly/opus；legacy nil ID 使用原始 slot，unknown extras 不画借来的历史。Codex 的两个 native slots 按 `CodexConsumerProjection.classifyRateWindow` 相同的 300/10080/43200 分钟规则匹配 session/weekly/monthly，其它时长按 native slot fallback。模型专属用量仍由既有 quota cards 展示；没有独立生产 history 的 extras 不创建趋势。旧 primary 缺失时保留 secondary index1，避免 compact 后错误接到 session。

新增四项独立 pure 回归方法覆盖真实 scoped Sonnet/Opus extras、weekly/opus label、tertiary Weekly label 与 weekly period、Codex swapped/native durations 和 legacy secondary。`quota-lane-pure/{build-r2.log,run-r2.log}` exit0，提取原测试全部断言并调用真实当前模型，不模拟算法；source/tests/harness SHA 见 source-manifest-r2.json。三文件 `ios-lane-fix-lint-r2.log` 零违规；`ios-lane-fix-build-r2.log` exit0 / TEST BUILD SUCCEEDED。首个新增测试 build 因 initializer argument 顺序写错失败，已修正并重新构建，不修改实际 API 或减弱断言。此处纯回归运行于 macOS，iOS编译证据不代替iOS runtime。

修复后独立 review 待结果。此前 r4/r5/r6 仍 live，但不含本次 mapper 修复或最终全部输入，不能作为最终测试 pass。尚无授权进行 push/PR/merge/发布凭据或 Mac draft。


修复复查又发现两个相关 Codex 边界：原始 Session label 与已分类 weekly/monthly 历史不一致，以及两 native slots 同 role 时重复画图。现统一为纯 `MobileQuotaBurndown.nativeLanes(for:)` projection，绑定真实 window、seriesName、标题与稳定 native slot ID；Codex 同 role secondary 优先，正反输入完整 projection 相等，按 role 标题 Session/Weekly/Monthly；Claude 保留 native 源 label。Section 仅消费该 projection，不另算分类、winner 或标题。scoped extras 没有独立生产 history，因此排除趋势，原 quota cards 仍展示其当前数据。

新增第五项回归检查 canonical 标题、window 数、secondary 30% winner 与完整数组正反一致。最终 `quota-lane-pure/{build-r4.log,run-r4.log}` exit0，五原方法所有断言真实运行通过；最终 model/test/harness hashes 见 source-manifest-r4.json。`ios-lane-fix-build-r3.log` exit0 / TEST BUILD SUCCEEDED；`ios-lane-fix-lint-r4.log` 三文件零违规。独立复查该模型、view 与 fixtures clean，没有剩余功能阻塞；仍需修复 commit 后 exact-head 确认。这个 pure 结果是 macOS，未将仍 live 的 Simulator r4/r5/r6 算作最终 runtime 通过。


## 实际 iOS 单元运行（642748a79，2026-10-01）

标准 XCTest r4/r5/r6 仍为 live launch wait，未算通过、未因等待取消重启。使用 Testing.framework 原生 `__swiftPMEntryPoint` 直接链接最终 ios-display-final 的原始 arm64 生产/测试对象，在自有 Simulator 7216E120-B46B-43D5-A78C-93A096A3D5A3 通过 simctl spawn 启动。进程报告 iOS Version 26.5 (Build 23F77)，vtool 确认 IOSSIMULATOR / minos17 / sdk27。没有修改原测试或断言，没有更改 debugger 权限或操作 SecurityAgent。

证据位于 BuildScratch/CodexBar/upstream-v070/ios-testing-standalone：build_runner.py、compile-command.json、object-manifest.json、runtime-evidence.json 保存命令、对象 hashes、当前 source/resources hashes、HEAD 和 runner hash。runner 克隆真实 built app 的资源并使用自身 local.codexbar.v070.unitrunner bundle ID；排除 CodexBarMobileApp.o 避免真实 app 启动逻辑，原样提取该文件 Notification.Name extension 并在 CodexBarMobile module 中重编以满足 SyncedUsageData 符号。TMPDIR 为自有 SSD BuildScratch 目录。没有替换存储、merger、presentation 或测试实现。

首轮因 notification 符号缺失链接失败；补入真实 extension 后 build exit0。clang incompatible-sysroot warning 仍存在，已以产物平台与实际运行 OS 核对，不隐去 warning。run.log exit0 / 296 tests in 12 suites passed；最终 run-r2.log exit0 / **313 tests in 15 suites passed**。包含 V070ConsumerData、V070Presentation、MobileDisplayFormatting、CloudKitMerge、TokenActivity、CWLWriter/Aggregate/Seed/Migration、ProviderColorPalette、WidgetSnapshotBuilder、V045/V066 presentation ，其中 palette 文件同时包含 ProviderColorContrastTests，V045 文件同时包含 V049ProviderDetailPresentationTests。TestFixtures 只提供原始 fixture。全部原始 Swift Testing 断言实际执行。

此前 consumer-ios-spawn/{build.log,run.log} 与 quota-lane-ios-spawn/{build.log,run.log} 均 exit0：真实完整旧 schema migration/publication disk reopen 和五个 canonical lane 原方法；这些 runner 使用已记录的断言转换。最终原始 Swift Testing 对象运行提供更强的 iOS runtime 证据。

此结果证明本轮相关 iOS 单元运行通过，覆盖 SwiftData 实际磁盘迁移、UIColor、四语言固定文案与 provider/Widget 数据模型；不证明四语言真实 App 导航、图表可见/可交互、VoiceOver、完整 light/dark 布局或 16 组实体设备 CloudKit/APNs 收敛。四语言 UI test 尚未成功启动，多设备缺项仍按前述矩阵记录替代验证和风险。独立 reviewer 正在核对 runner 来源与证据边界，不据此宣称整个 Goal 完成。


standalone 证据独立审计完成：当前 compile-command 的 106 个链接对象与 object-manifest 集合及 hashes 全匹配，14 个 test/support 对象全部存在，没有漏加载或断言改写。reviewer 接受其作为实际 iOS Simulator 单元证据，明确不替代 App 生命周期/UI/实体设备 gate。按审计建议将 r2 命令、对象/source/resource manifests、Runner/Notification 源、build/run log 与真实可执行产物冻结于 ios-testing-standalone/frozen-r2，freeze-manifest 逐文件 SHA；built app 与 clone 本地化/asset 资源 hashes 相同。r1 的 manifest 已被 r2 覆盖，不把 r2 manifest 倒推绑定 r1。prototype 的缺失 test object 静默跳过已改为明确失败，当前所有所选对象齐全。源文件 mtime 均不晚于其匹配的编译对象；当前 source hashes 记录于 provenance。


## 实际 SwiftUI 组件渲染与刻度修复（2026-10-01）

sim-use UI preflight 再次 exit1：`No translation object returned for simulator ... likely ... fullscreen dialog`。此错误仅证明 UI channel 不可读，不能证明具体系统授权弹窗；不绕过 SecurityAgent、不执行 tap/swipe，不把预检失败算 UI pass。先前请求用户检查调试授权仍未回复。

使用真实 Xcode production objects 与 `@testable import CodexBarMobile`，在自有 iOS26.5 Simulator 通过 ImageRenderer 渲染 **真实 QuotaBurndownSection**，使用原 PreviewData.claudeProvider 与真实 ProviderColorPalette。4语言 × light/dark ×320/393pt，共16原始PNG，逐语言查看 contact sheet 并检查窄屏原图。这是离屏组件布局证据，不是独立仿制视图；未启动真实 AppDelegate、CloudKit 或 app store。源/对象/产物/图片 hashes 与命令/run exit 见 ios-render-standalone/{compile-command,render-results,render-provenance,image-manifest}.json。原图已保存 before-axis-fix，存在默认日期长文本截断，且 hierarchical .secondary 被 Chart series 渲染为蓝色，与灰色图例不一致。

修复只涉及 production chart：周期内20/50/80%三个参考刻度、显式 top anchor 居中标签；<=12h 显示 locale 时间，<=48h 显示两行数字月/日和时间，较长周期显示数字月/日。保留完整真实 start...reset domain、理想线端点和所有实际采样；参考刻度不声称周期起止。使用显式 Color.secondary 使灰色 guide 与 legend 一致。没有新用户文案；原2.4.0四语言额度图表说明覆盖此细节，技术 CHANGELOG 补充修复。

首轮紧凑格式仍在末端 truncate，进一步使用内部三刻度与 top anchor 后，四语言窄屏标签完整。ios-axis-build-r3.log exit0 / TEST BUILD SUCCEEDED；该 view SwiftFormat lint 和 SwiftLint 均 exit0。四语言生产渲染各 exit0，灰色 guide/实际品牌色、实际采样、刻度和图例可见，明暗及两宽度无发现截断。compile 有已记录 incompatible-sysroot warning，部分 render log 有 IOSurfaceClientSetSurfaceNotify warning；实际PNG已读取，不把仅输出路径当渲染通过。

另在 ios-render-24h 渲染明确虚构24小时原生primary fixture，UTC captured 2026-10-01T22、reset2026-10-02T12，跨本地午夜；四语言×明暗×两宽度共16PNG、四个进程exit0，窄屏四语言原图均看到完整两行日期/时间。补覆盖12–48h显示分支；不将虚构周期当真实provider能力。来源与证据同样保存 render-provenance.json。

最终 view 编译后原始 Swift Testing 重链接运行 run-axis-final.log exit0 / **313 tests in15 suites passed**；freeze于 ios-testing-standalone/frozen-axis-final，包含原对象/source SHA、命令、runner、events和产物。独立源码review clean，reviewer实际检查日语窄屏图，并建议的24h fixture已补。iOS27复验仍是live进程，停在颜色测试，未见终态且未取消重启；不据此认定真实App bug或系统版本兼容pass。真实App四语言导航/可交互/VoiceOver与多设备CloudKit/APNs gate仍未闭环，PR/CR/merge/Mac draft未执行。


## 冻结真实旧/新 iOS 磁盘缓存16组合（2026-10-01）

`tools/check_frozen_cache.py` 与 `FrozenCacheHarness.swift` 将已发布旧commit `616701b95122c94e106299d18ac6a83c61850d94` 和当前真实25个源码文件分别编译为 arm64 iOS Simulator cache runner。包含完整5实体schema、ModelContainerFactory、SwiftDataBridge、CostLedgerService、TokenActivity与实际旧/新ProviderSnapshotMerger；仅移除同module import，不重写缓存算法或schema。工具使用已通过冻结wire测试的四个旧/新writer JSON，并在开始时核对17个旧/新wire源SHA，防止源漂移。source-manifest、旧/新compile-command与artifact-manifest记录冻结来源/输入/二进制 hashes。

运行 `check_frozen_cache.py --scratch .../frozen-ios-cache-r4 --wire-root .../frozen-consumer-matrix-r4 --simulator 7216E120-B46B-43D5-A78C-93A096A3D5A3`，终态 exit0。16 masks、32独立phone缓存、96次分别启动的iOS进程全部通过。每phone依次：write原per-device snapshots→新进程read-prune先冷读完整两writer再移除B→第三进程read-retained验证没有B复活。不是同一进程的内存读取，也没有复用phone A/B store。每次明确断言 opened.isPersistent，不能以memory fallback替代。

冷读逐device断言独立ID/name、两个provider、primary/rateWindows、capture和完整costSummary与当前reader的原输入一致；按正反cache顺序调用真实merger，完整provider projection与live合并相等。删B后实际DeviceRecord=1、ProviderSnapshotModel=2，第三进程重开仍仅A。旧reader按真实旧类型忽略新optional metadata/model names，同时effective blocked百分比/monthly reset与未知金额/token值保留；新reader保存其能够解析的新字段。不把旧客户端恢复不存在字段作为成功条件。

两个runner经vtool确认IOSSIMULATOR/minos17/sdk27，执行设备为自有iOS26.5 Simulator。CloudKitDatabase.none +显式SSD SQLite URL；仅使用合成writer数据，不读真实store/Keychain/CloudKit。传入-cwlEnabled YES作为命令行测试配置，不写真实app设置；未独立断言ledger hook/rows或aggregate，不把provider缓存pass扩展为ledger聚合pass。SQLite及临时路径全部在BuildScratch。未验证增量CK变更token/subscription/APNs、真实fallback优先级、跨phone网络收敛或UI；删除断言针对Device/provider cache，不声称历史ledger被删除。旧cache→新schema upgrade由前述完整冻结schema单元测试覆盖，当前矩阵每phone固定reader版本，并不冒充16组合都执行了upgrade。

r1 harness把throwing fetch放进precondition autoclosure导致compile失败；改为先fetch再断言，r2旧/新compile均exit0，未修改生产或减弱谓词。顶表16行已补强为wire+merge+iOS disk substituted；本轮未获得可用2Mac×2iPhone实体环境，因此继续明确UI/Production/APNs残余风险，不将模拟器缓存视为实体全链路pass。UI预检与iOS27旧job仍未终态。


最终 r4（包含新增独立语义断言与格式清理）终态exit0，16cases/96进程全通过；每个进程log明确 `OS: Version 26.5 (Build 23F77)`。两个版本各25源SHA、缓存harness SHA、冻结四wire副本SHA全部重新核对一致；artifact-manifest保存二进制、脚本、source/matrix与96份日志SHA。SwiftFormat lint与该harness SwiftLint均exit0/无warning。r2为较弱的初次冷/live一致性证据，r3/r4进一步独立断言Codex24→12 tokens、Kimi12 tokens、unknown cost、有效100%/25%及20天/1天reset；new-reader额外断言raw blocker与Fictitious model名单。旧reader不能访问新字段的断言仅在NEW_CACHE编译条件内，这是原legacy数据模型边界，不是生产算法替换。各reader都用相同当前toolchain重编旧/新源码；不是运行已发布旧app二进制，仍有旧二进制/历史升级路径差异的残余风险。


## Widget 原始矩阵与截图适配（2026-10-01）

本轮 ProviderColorPalette 被 Widget 实际使用，适用 RELEASE-CHECKLIST:26。`ios-widget-tests-r1`链接原始 CodexBarWidgetRenderMatrixTests.o 与当前生产对象，在自有iOS26.5 Simulator运行 XCTestSuite；原始6方法中5通过，视觉附件方法因独立runner禁用activities抛NSInternalInconsistencyException，terminal exit1。保留完整失败，不称标准XCTest全部通过。平台vtool为IOSSIMULATOR/min17/sdk27，运行OS26.5(23F77)。

`ios-widget-tests-r2`仅将原测试的XCTAttachment/add四行替换为同一UIImage的PNG持久化；不改循环、fixture、production view或断言，额外断言PNG编码/写入成功。#sourceLocation保留真实原路径供footer源断言。adapter-manifest记录精确before/after、原始与适配源码SHA；所有原始production/test对象SHA核对仍匹配，编译命令和artifact-manifest保留。编译首次缺Swift XCTest overlay的-I路径，补platform Developer/usr/lib后链接通过；warning记录原样保留。

r2 terminal exit0，6方法/0 failures：主Widget128 mode×family×style×scheme×rendering组合、error/noData/syncing12组合、activity4states×4families×2schemes×2rendering64组合、loaded视觉12张、removed/duplicate4组合，共220次离屏渲染；footer居中源断言也通过。12原始PNG已保存并查看contact sheet，各family的Light/Dark/tinted可见对比与内容。此为原始断言+附件存储适配的替代证据，不是标准Xcode XCTest活动系统通过，不是SpringBoard截图。真实Home Screen编辑面板/配置选项/切换mode、真实App导航/可交互/VoiceOver仍未完成。
