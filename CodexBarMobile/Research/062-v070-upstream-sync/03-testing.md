# 本轮测试证据

Status: `in-progress`

已执行初次Mac构建和定向测试；最终完整测试、iOS验证和设备矩阵尚未完成。下面pending不是pass。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 1 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 2 | old | old | old | new | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 2 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 3 | old | old | new | old | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 3 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 4 | old | old | new | new | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 4 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 5 | old | new | old | old | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 5 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 6 | old | new | old | new | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 6 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 7 | old | new | new | old | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 7 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 8 | old | new | new | new | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 8 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 9 | new | old | old | old | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 9 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 10 | new | old | old | new | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 10 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 11 | new | old | new | old | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 11 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 12 | new | old | new | new | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 12 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 13 | new | new | old | old | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 13 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 14 | new | new | old | new | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 14 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 15 | new | new | new | old | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 15 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |
| 16 | new | new | new | new | substituted（wire + merge） | frozen-consumer-matrix-r3/matrix-wire.json case 16 | 缺真实四设备；SwiftData/UI/Production/APNs 未验证 |

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
