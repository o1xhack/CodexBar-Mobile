# 本轮测试证据

Status: `in-progress`

当前 Mac 完整回归已通过；iOS r7标准完整单元916 tests/1012 runs及r16相关回归51 tests/66 runs已通过。16组合已有冻结旧/新 wire、真实合并与独立磁盘缓存替代证据；真实 App 四语言 quota UI、标准Widget渲染及分范围生产SpringBoard配置/timeline/Home验收已通过，r17六组受控路径通过但保留r15/r16偶发无法载入未知原因风险。人工 VoiceOver、实体 CloudKit/APNs、GitHub PR/CR 与 Mac draft 仍未完成。历史段落按发生顺序保留，旧 pending 不代表当前结果。

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


## 用户处理密码提示后的运行终态（2026-10-01）

用户报告已输入密码。此前iOS27独立Swift Testing runner PID99312已不存在，run-ios27.log实际终态为313 tests/15 suites passed after1887.226s，运行OS27.0(24A434)。ios27-terminal-evidence.json保存log SHA和证据边界；原launch记录指向frozen-r2，不能当作后来axis-final输入在iOS27通过。历史shell session已不可读取，未虚构shell exit0。此前三个xcodebuild PID也均已不存在，但r6 xcresult缺Info.plist，仍无标准XCTest pass证据；sample PID已消失且未生成堆栈文件。没有据进程消失重启任务。

DevToolsSecurity仍报告disabled。本机manpage说明：普通系统在一个login session首次使用Apple debugger/performance analysis工具检查用户进程时会请求管理员授权；enable改变的是免额外密码策略。disabled并不证明刚输入的单次授权失败，也不能单独确定本轮UI阻塞根因。Simulator ui复检terminal exit1，再次返回No translation object returned for simulator，无成功screen证据；不宣称真实App/SpringBoard恢复。用户无需向agent提供密码，未改变全局授权策略。


## 最终 axis 输入 iOS27 复验

历史313项通过后，旧进程确实退出且用户已处理密码提示；启动独立ios27-axis-final-r1，链接frozen-axis-final所有生产/原测试对象，逐个SHA匹配。仅Runner的event输出路径与bundle ID改变，clone当前真实app资源，没有替换原Swift Testing断言。保存compile-command/object/source/binary/artifact manifests。iOS27.0(24A434)运行terminal exit0，313 tests/15 suites passed after2.851s。当前最终图表输入在iOS26.5和iOS27均有原始单元通过证据；仍不证明真实App或系统Widget行为。

旧标准XCTest三PID已缺失且无完整result，因环境变化后重新从ios-display-final启动Widget六方法+四语言quota UI test，session26117/PID17111，result ios-widget-ui-after-auth-r1.xcresult。本次没有重启live run；当前仍live且没有测试终态，不称pass。未进行sim-use坐标操作；SpringBoard配置gate继续未完成。


## 标准XCTest恢复：Widget完成、真实UI定位失败

ios-widget-ui-after-auth-r1终态exit65，真实xcresult summary为6 passed /1 failed /0 skipped。CodexBarWidgetRenderMatrixTests原始六方法全部通过（含此前activities异常的附件方法），导出12张标准XCTest PNG；因此Widget离屏矩阵和标准附件gate现已完成，不再仅依赖适配runner。实际SpringBoard配置仍未验收。

唯一失败为四语言quota UI test的英文首轮：App启动成功，provider-group-claude可点击、Claude navigation/title可见，图表exists断言失败。失败录像15s截图显示quota卡片在viewport底部，标题可点击而图表仍被tab栏遮住。这证明Simulator/XCTest启动和导航可用，不支持“Simulator整体故障”的判断；sim-use入口错误是独立channel，不能拿来推断XCTest失败根因。

修正测试：先滚动直到chart.exists且isHittable，再waitForExistence与原有hittability/height/label/value断言；未删减图表内容断言或改productionview。原失败保留。ios-quota-ui-scroll-r2以当前源码构建并运行，session8077/PID20535，结果未终态。测试SwiftFormat lint 0/1 files需改，diff check通过。


## 图表辅助功能容器修复与四语言真实 App UI 通过

scroll-only r2终态exit65，仍不能定位lane ID，因此viewport不是完整根因。外层VStack的section identifier传播到子节点（初次log标题被解析为quota-burndown-section）；显式accessibilityElement(children:.contain)建立section container，保留Chart各自ID/label/value与子元素，不使用combine/ignore吞并图表。r3按当前修改源码编译，终态exit0 / TEST SUCCEEDED；xcresult1 passed/0 failed/0 skipped，四语言循环全部完成：preview模式真实App启动、Claude导航、滚动、lane0 exists/hittable/frame>0/localized label/87%value。四张标准App screenshot已export并逐张查看；source/summary/log/attachment SHA见ios-quota-ui-contain-r3-evidence.json。截图显示真实生产图表，非ImageRenderer；仍是虚构preview数据，不证明live账户/CloudKit或人工VoiceOver。

代码静态review clean；两Swift文件format lint 0/2需改。新改动只是section辅助功能分组和严格测试定位顺序；模型/缓存/merger源码未改。Widget原六方法标准XCTest已在after-auth-r1全部通过并生成12附件。真实SpringBoard编辑配置/切换mode、实体Production/APNs以及GitHubPR/CR、merge和Macdraft仍未完成。sim-use入口此前错误不等同Simulator整体故障，标准XCTest已实际证明正常启动/导航/图表访问。

## 实际 SpringBoard 配置与 timeline 鉴别（2026-10-01）

sim-use 当前已恢复，可读取与操作自有 iOS26.5 Simulator 7216E120。通过真实 Gallery 添加 medium 主 Widget，打开编辑面板查看 Overview / Provider Focus / Today Cost / Sync Health 四选项，切换为 Sync Health 后关闭再重开，值仍为同步健康。Token Activity 的实际 source picker 也从全部切换 Codex。截图及日志 SHA 见 springboard-evidence-r1.json。此处证明配置入口与持久化通过，不代表 timeline/主 Widget 展示通过。

主 Widget 在 Home 仍显示 overview placeholder；同 extension 的 Token Activity 则返回 noData。系统日志明确主 Widget INAppIntent linkAction XPC4097、Unable to get LNAction、No AppIntent in timeline(for:with:)、CHSError1101。未观察到预期即时返回 simulatorMock 的 timeline 成功记录。当前 UITest artifact 使用 CODE_SIGNING_ALLOWED=NO，appex 无签名 entitlements，Token App Group lookup 也报告 client is not entitled；这只是下一项签名/运行环境鉴别线索，尚未证明根因，不能认定 Simulator 整体故障或生产代码缺陷。未重启全局 Simulator、未删除数据、未触碰实体设备或发布凭证。SpringBoard gate 继续未完成。

## Xcode 模拟器权限与 mode 恢复对照（2026-10-01）

手工签名实验 ios-simulator-adhoc-r1 保留相同源码/资源/metadata，仅将展开的设备 entitlements 写入 ad-hoc 签名；codesign 静态验证通过但系统启动拒绝，launchd 日志为 restricted entitlements / OS_REASON_CODESIGNING。此实验在 extension 启动前失败，不能解释原 LNAction 故障。

随后使用独立 ios-widget-signed-build-r1 DerivedData、标准 xcodebuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- -packageAuthorizationProvider netrc 构建，session99962终态exit0 / BUILD SUCCEEDED。实际身份 Sign to Run Locally，无真实证书/Keychain/发布凭证。Xcode 将 Production CloudKit/app-group 等模拟权限放入 Simulated.xcent 与 Mach-O __TEXT 区段，普通签名 xcent 为空；不能仅凭 codesign -d 为空认定这种产物缺模拟权限。安装后主Widget已到达 provider 的 Overview configuration 日志、timeline成功并显示 simulatorMock，原 XPC 空timeline阻塞已越过。未进行 Production 网络验证。

实际选 Sync Health 后 Home 仍显示 overview；为鉴别参数恢复与缓存，仅临时扩展 DEBUG notice 记录 mode/colorStyle/providerCount，其他代码不改，诊断源码保存 widget-timeline-diagnostic.swift。诊断 build session82932 exit0；系统 serializedParameters 为 syncHealth 和后续 todayCost，实际 timeline 入口却均 mode=overview/colorStyle=mono/providerCount=0。模式显示 gate 仍失败，不把 timeline success 当作配置已生效。source/二进制/metadata/截图/log SHA 见 widget-mode-diagnostic-evidence-r1.json。

[Apple Developer Forums thread834793](https://developer.apple.com/forums/thread/834793) 有 SDK27 构建后配置保持默认的相似开发者报告，Apple 工程师回复此行为非预期并请提交反馈；该报告是鉴别线索，不能单独证明本轮相同根因。两 target metadata 的四 mode 定义完整且一致。当前另一套已安装 Xcode27.2beta2 仅通过单命令 DEVELOPER_DIR、独立 ios-widget-xcode272-r1 做同输入对照；不切换全局工具链、不下载工具、不据尚未完成构建称通过。

### Xcode27.2 对照终态

同临时 DEBUG trace 输入的 Xcode27.2beta2 构建 session64022终态exit0 / BUILD SUCCEEDED，安装到同一自有iOS26.5 Simulator。真实编辑面板保留旧 todayCost 选择，实际切换 syncHealth 后系统日志 serialized mode=syncHealth；timeline入口仍 overview/mono/0，并重复to-0.0 AppEnum runtime warning。Home实际截图仍overview四provider。widget-xcode272-evidence-r1.json记录工具链、输入、产物和截图/log SHA。该版本对照未修复参数恢复；不把beta构建当发布工具链，也不据两工具链同样失败断言系统根因。

临时 DEBUG trace 已精确恢复为原源码；两个诊断产物和trace副本保留在scratch，不混称其为正式发布二进制。下一项安全鉴别为独立最小项目的纯enum与同enum+optional AppEntity array对照，保留生产providers完整范围，禁止通过删除参数/改旧raw IDs/全局defaults绕过per-widget配置。

## 独立最小项目排除业务与枚举列表因素（2026-10-01）

证据目录：BuildScratch/CodexBar/upstream-v070/widget-parameter-probe-r1。诊断 App 不含 CloudKit、账号、App Group 或生产业务，只显示 timeline 实际接收的参数。所有实验只安装到自有 7216E120 iOS26.5，使用 Xcode27.0 的本地 ad-hoc Simulator 签名。

| 实验 | 构建终态 | 系统保存值 | 实际 timeline 值 | 证据 |
| --- | --- | --- | --- | --- |
| mixed-r3，Plain intent 无 entity，但 bundle 另含 Entity intent | exit0 | syncHealth | overview | frozen-mixed-r3/manifest.json，plain-log.txt、plain-sync-home.png |
| plain-only-r4，整个 bundle 删除全部 entity/query/entity intent/widget | exit0，session24447 | todayCost | overview | frozen-plain-only-r4/manifest.json |
| caseiterable-r5，仅显式 CaseIterable conformance | exit0，session78850 | syncHealth | overview | frozen-caseiterable-r5/manifest.json |
| explicit-values-r6，固定四项 allCases 和 supportedValues，打印 runtime allCases | exit0，session71284 | providerFocus | overview | frozen-explicit-values-r6/manifest.json |

r6 实际 allCases=overview,providerFocus,todayCost,syncHealth，仍出现 to-0.0 warning 与默认参数。此证据排除“必须存在 AppEntity 才失败”和“实际枚举列表缺少选项”这两条窄假设；不证明 Simulator 整体故障，也不能将 warning 的内部来源归因于业务 enum。r4/r5/r6 均保存构建输入、实际 artifact SHA、截图和系统/provider 日志；r3 保存源代码及实际 UI/log，未在其二进制被覆盖后伪造 artifact provenance。

r4 覆盖安装时 sim-use 检测旧诊断 app PID42215 消失，立即停止下一步界面操作并核对日志。plain-only-install-process.log 记录 installcoordinationd 主动请求终止该 PID、terminate_with_reason success 与随后安装完成；属于安装替换终止，未当作 App 崩溃或系统故障。工具 baseline 在确认安装终止后重置。

生产 Widget 源码未因这些实验改变；所有模式、颜色及 provider 选择能力保留。下一步采用 09-widget-configuration-repair.md 中的完整迁移原型验证，不继续堆叠已被否定的 enum 列举补丁。真实 SpringBoard 主 Widget 参数生效 gate 仍失败，iOS/PR/CR/Mac draft 不称完成。

### SiriKit 全配置原型首次实际生效

独立 widget-sirikit-full-probe-r1 已创建 App/Widget/动态选项 extension 三 target，intent 类型包含四模式、两样式和 INObject provider 数组。xcodegen + Xcode27.0 标准本地签名构建 session2967 终态exit0 / BUILD SUCCEEDED；无 CloudKit、真实账号或 App Group，动态 catalogue 只有虚构 A/B/C/D。

安装到同一自有 iOS26.5，在实际 SpringBoard 添加 medium Widget，打开配置菜单：动态列表 A/B/C/D 可见，选择 B、syncHealth、colorful。options extension 日志证明被系统调用，timeline-r1.log 最终 mode=4,color=2,ids=B；对应生成 enum 4=syncHealth、2=colorful。final-config-B-r1.png 与已等待稳定的 home-health-color-B-settled-r1.png 实际一致；较早 home-health-color-B-r1.png 截到关闭编辑动画中的旧图，保留且不作为最终通过证据。初始默认 mode1/color1/空列表也有实际 Home/log。evidence-r1.json 保存三 target 输入、build log、全部截图/log 与实际 artifact SHA。

这证明此 Simulator 中 SiriKit 的动态 provider+mode/style 参数恢复路径可用；不是生产主 Widget 修复，也不是全部配置/多实例/迁移矩阵通过。尚需剩余模式、四 provider、独立实例、生产接入、本地化、旧新 kind 升级与回归。

### r4 生产实际验证补充（2026-10-01）

`project.yml` 已将 options extension 的共享资源目录纳入，排除 Swift 文件后单独加入 catalogue。r4 build terminal exit 0，191 项冻结 source hashes 与当前源码一致；安装前 App/Widgets/Options 三 bundle 的 en/zh-Hans/zh-Hant/ja `WidgetStatus.strings` 均实际解码正确。r3 focused 49 tests / 64 runs / 0 failure / 0 skip 验证 adapter、provider/catalogue、snapshot、activity，r4 只改变资源归属，不能把 r3 测试扩大成所有 r4 runtime gate。

同一已升级自有 iOS26.5 的新 status 实例实际选择 syncHealth：timeline 日志收到 `mode=syncHealth, style=mono, providerIDs=`，稳定 Home 显示同步健康“正常”。旧实例编辑及重新添加迁移全过程已有截图。仍不意味着所有四模式/配色/providers/多实例通过。

r4 覆盖安装后编辑面板仍使用旧英文标签，parent hiding 未体现。仅对本任务自有 `7216E120-B46B-43D5-A78C-93A096A3D5A3` shutdown/boot 保留数据，bootstatus terminal exit 0；未停止/重启其他项目 Simulator 或全局服务。因有意重启而消失的旧 App PID 已重设 sim-use baseline，没有据此声明 App 崩溃。冷加载后编辑面板实际出现“小组件类型/概览/颜色样式/单色/服务商”，说明原英文显示与缓存有关；不应改正确的 enum predicate 名为数字。

随后冷编辑面板控件未响应，最终显示“无法载入”。暂无 App crash banner、诊断报告或确定原因；不得将这个局部配置面板失败泛化为 Simulator 整体故障。真实 parent hiding、0–4 槽位删除/顺序/第五项边界及后续模式组合仍未通过，下一步需做新 namespace/class/kind 的独立配置模型对照或按运行日志定位冷加载失败，不以重复操作替代排查。

`status-sirikit-integration-evidence-r4.json` 保存上述独立证据 hashes 与严格 pass/pending 范围。全部文件位于 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070/`。预览 App 曾以明确 `UI_TEST_PREVIEW_DATA` 启动，将自有 Simulator catalogue 更新为合成 preview 数据；初始六项虚构 fixture 仅用于后续边界测试，不能将该列表误称为真实账号数据。Goal 保持 active，未 push/PR/merge/tag/release/TestFlight。

### r6 生产构建及 iOS27 实际配置验收（2026-10-01）

r6 production build terminal exit0，192项输入hashes与当前源码一致；App/Widget/Options三bundle的四语言Provider1–4资源均实际解码完整，options独立Localizable.strings的“Not selected”四语言值正确。四个changed Swift文件strict lint通过。r5相关51tests/66runs/0failures/0skips已验证adapter/catalogue/selection/snapshot/activity；r6 handler文案API及resource变更不扩展该测试范围。

在自有iOS27 D86C3D2C-7A29-43C6-9B22-5B61902B794B覆盖安装r6，再以UI_TEST_PREVIEW_DATA启动发布合成catalogue；没有真实账号或CloudKit探测。从系统图库第5页添加medium新status，中文Overview四槽实际出现；实际切syncHealth后全部四槽隐藏，style仍可选。再选colorful，timeline收到mode=syncHealth/style=colorful/providerIDs=空，稳定Home呈绿色“正常”。已证明修复接入生产并能消费非默认配置，不能据此宣称完整验收。独立证据manifest为 `status-slots-production-evidence-r6.json`。

剩余生产实际dynamic picker/清空/0–4/顺序与重复边界、两实例、其余模式配色组合、其余三语言实际配置、四尺寸、iOS26最终版本复测、完整iOS回归与exact-source review。旧kind迁移已有此前独立证据，最终package影响仍要核对；PR+CR/merge/Mac draft按用户顺序和授权边界，未执行remote handoff。Goal继续active。

### r7 完整单元回归与生产选择/清空验收（2026-10-01）

`ios-status-slots-full-r7.xcresult` 实际 summary 为916 tests / 1,012 runs，0 failures / skips / runtime warnings；终态 TEST SUCCEEDED。192项r6输入hashes在本轮再次核对一致。完整单元回归运行于自有iOS26.5；不把单元测试扩大为SpringBoard全配置验收。

自有iOS27仍使用已冻结的r6生产安装包和合成preview catalogue：实际选择Codex单项，timeline收到codex；再按槽选择Codex/Claude/OpenRouter/AWS Bedrock，timeline收到codex,claude,openrouter,bedrock，Home顺序一致。后两项缺少合成配额数据，实际保留“不可用”，未替换为其他项。逐槽选择“未选择”清空四项后，timeline收到空IDs，Home恢复自动Codex/Claude/Raycast/OpenRouter。日志和实际Home截图hash记录于 `status-slots-production-evidence-r7.json`，运行产物引用r6冻结manifest，独立记录r7测试结果。

此对照将失败范围缩小到本项目固定长度数组的配置路径；改为四个独立optional选项后，模式条件隐藏与选择/清空路径实际生效。没有证据支持Simulator整体故障，也未核验其他项目。仍待两/三项与重复边界、实际两实例、其余模式配色/语言/尺寸、iOS26最终运行验收与最终review。Goal保持active；PR+CR、merge、Mac draft按用户要求顺序，未执行remote handoff。

### r8 生产两实例与两/三项、重复边界（2026-10-01）

同一自有iOS27桌面添加第二个medium新status，未修改其他项目设备。上方新实例设syncHealth/mono，下方原实例保留overview/colorful。下方实际按槽选择Claude/Codex，两项timeline和Home顺序一致；添加OpenRouter为第三项，timeline收到claude,codex,openrouter，Home三列对应一致。第四槽再次选择Claude，编辑截图证明四槽内容为Claude/Codex/OpenRouter/Claude，timeline仍为前三个不同ID，Home没有重复列。滚动到底实际表单终止于服务商4，无第五槽。

全过程上方保持单色同步状态；反向编辑上方切彩色，Home实际变为绿色“正常”，下方继续保留彩色三项概览。已有截图证明两个放置实例在两个编辑方向独立；本轮未捕获反向彩色health的新timeline事件，因此该动作只声明实际编辑/Home证据，不能补造日志。初始health mono及下方2/3/去重日志真实存在。所有证据hash保存 `status-slots-production-evidence-r8.json`，仍引用已冻结r6生产产物，192输入hash再次一致。

与r7一起已覆盖实际0/1/2/3/4项及清空、槽序和重复、多实例；仅为中文medium/合成preview/iOS27范围。其余模式配色组合、另外三语言配置、其他尺寸、iOS26最终运行验收及源码最终review仍待完成。没有新代码修改、remote handoff、merge或Mac draft；Goal继续active。

### r9 服务商详情实际切换及翻译修复（2026-10-01）

同一iOS27生产r6上方实例从syncHealth/colorful实际切providerFocus/colorful：配置表单只保留模式/样式，Home显示Codex“已用78%”蓝色详情，下方三项彩色overview保持。日志随后实际捕获syncHealth/colorful空IDs（补足r8当时尚未出现的事件）及providerFocus/colorful空IDs，见 `status-slots-focus-timeline-r9.log`；r8原冻结日志不修改。截图及日志hash存 `status-slots-production-evidence-r9.json`。

实际详情底部出现英文“Provider”，代码使用String(localized:)但主catalogue的zh-Hans/zh-Hant值本身都是英文。已只将这两值修为“服务商”/“服務商”，英文及日文保留；四语言仍translated。r6/r7/r8/r9冻结来源均为修复前，不能据此宣称最终文案通过。新的192输入manifest `status-slots-r10-inputs.json`冻结修复后资源，生产构建session74542正在运行，结果待核对。

review agent已对HEAD45a6a42666bd2378e4a355d07694732a25a567b2加未提交四槽迁移diff完成clean源码审查，零代码阻塞；本次两行翻译资源后另请复核。仍未提交最终来源，也不是remote PR exact-head CR gate。完整UI矩阵未完成，Goal继续active。

### r10 翻译修复后构建与保留实例升级（2026-10-01）

生产build session74542终态exit0/BUILD SUCCEEDED，结果 `ios-status-slots-build-r10.xcresult`。192输入hashes再次一致；App及Widgets最终Localizable.strings实际解码Provider为en Provider、zh-Hans服务商、zh-Hant服務商、jaプロバイダー。构建产物全文件hash冻结 `status-slots-r10-artifacts.json`，不覆盖r6来源。

仅覆盖安装到自有iOS27并以UI_TEST_PREVIEW_DATA启动；有意安装/启动后重置sim-use进程baseline，未把预期进程替换记作未知崩溃。已放置两实例保留：上方仍providerFocus/colorful，Home底部实际显示“服务商”；下方仍overview/colorful，保持Claude/Codex/OpenRouter三项和次序。实际截图hash保存 `status-slots-production-evidence-r10.json`。纯文案修复没有改逻辑；r7全单元结果覆盖修复前逻辑，r10不另伪称完整单元重跑。

review agent对唯一新增的两行翻译复核clean。剩余实际模式/配色、另外三语言、其他尺寸、iOS26最终运行验收仍待完成；当前只有providerFocus/colorful、syncHealth两样式、overview/colorful有明确实际证据。最终commit/remote PR CR、merge、Mac draft尚未进行，不能声明iOS或Goal整体done。

### r11 四模式两配色实际桌面补齐（2026-10-01）

已安装r10、自有iOS27/合成preview/medium新status：实际选providerFocus/mono，Home已用78%黑色；todayCost/mono实际$19.42、822.0 K tokens黑色；todayCost/colorful同值橙色；overview/mono自动四项单色（error图标仍红色，属于错误语义）。每次实际编辑→timeline接收mode/style→稳定Home核对，日志 `status-slots-modes-timeline-r11.log` 和截图hash冻结 `status-slots-production-evidence-r11.json`。另一实例仍保持三项彩色overview。192项r10源hash复核一致。

加此前r8/r9 syncHealth两样式、r10 providerFocus/colorful及overview/colorful，四模式×两样式的medium实际接收与显示已覆盖；health证据是r6二进制，r10仅两行翻译变动，不能称r10同一产物全部八组重新运行。

覆盖安装r10后系统编辑面板mode/style/provider字段显示英文，而heading/description与Home保持中文。App/Widget/Options实际WidgetStatus.strings四语言完整，设备AppleLanguages=zh-Hans-US,en-US；尚不能据文件或既往r6中文UI宣称本次编辑界面中文通过。已保存实际英文编辑截图，只对自有iOS27保留数据shutdown/boot做冷加载对照，session51287进行中；其他项目设备不操作。其余语言、尺寸及iOS26最终runtime仍pending。

### r12 冷加载中文配置与small/large实际布局（2026-10-01）

自有iOS27 bootstatus session51287终态exit0，数据保留；因有意重启而消失的旧进程重置baseline，未据此声明App崩溃。冷打开新status编辑先见短暂spinner，settled实际显示“小组件类型/概览/颜色样式/单色/服务商1–3”；此前覆盖安装后英文字段在未改源码/资源情况下恢复中文，支持系统配置缓存解释（推断），不是Simulator整体故障证明。返回Home上方overview/mono自动四项、下方overview/colorful原Claude/Codex/OpenRouter三项仍保留。

从系统尺寸菜单实际将上方改small：settled框168×191，显示自动Codex78%和Claude42%两行，姓名/百分比/进度均无裁切；最初 `status-slots-small-home-r12.png` 是过渡中的旧medium，不作为small通过证据，最终只用 `status-slots-small-home-settled-r12.png`。再改large，实际框354×392，四项2×2顺序正确，无裁切；下方原实例被系统挪到下一页，未移除。

r10产物冻结保持，全部图片hash记录 `status-slots-production-evidence-r12.json`。medium已有八组合，小/大目前只覆盖overview/mono，不扩大为所有尺寸全模式矩阵。第四尺寸为systemExtraLarge（iPad），本iPhone菜单disabled，需另做iPad真实放置或明确替代验证；另外三语言配置与iOS26最终runtime仍待。Goal active，未远程handoff/merge/Mac draft。

### r13 iPad systemExtraLarge实际放置（2026-10-01）

确认CoreSimulator Devices入口realpath为SSD且可写后，新建本任务独立 `CodexBar v070 iPad XL QA`，UDID1111ADF4-3166-42D2-B868-10D8A18FEF97、iPad Pro13 M5、iOS27.0；身份记录 `status-slots-ipad-device-r13.json`。bootstatus session84729终态exit0。安装同一r10已冻结生产包、以UI_TEST_PREVIEW_DATA启动；初次读取进程列表短暂失败，等待原session93245终态exit0并重新读取baseline成功，无重装/全局重启或未知crash证据。

实际SpringBoard从CodexBar图库第8/12页选择新status超大尺寸并添加，完成编辑后Home框752×377，overview/mono四列Codex78%、Claude42%、Raycast30%、OpenRouter不可用顺序正确，名字/数值/进度/副标题无裁切。不是仅图库预览通过。图片与timeline日志hash冻结 `status-slots-production-evidence-r13.json`；均为合成数据，不是物理iPad/真实CloudKit。

至此四family都有实际放置布局证据：small/large/extraLarge目前只overview/mono，medium有四模式×两样式；不扩大成全family×mode矩阵通过。另外三语言的配置界面、iOS26最终runtime及最终提交/远程review仍待完成。Goal active，未push/merge/tag/TestFlight/Mac draft。

### r14 iOS26最终产物实际配置运行（2026-10-01）

在自有iOS26.5设备7216E120-B46B-43D5-A78C-93A096A3D5A3安装已冻结r10产物。实际medium配置选择Codex和彩色，桌面显示单项78%；切到syncHealth/colorful后服务商字段隐藏，桌面显示绿色“正常”。timeline-r14.log依次收到overview/mono空IDs、overview/colorful codex、syncHealth/colorful codex；模式切换保留选项且同步状态渲染忽略provider选择。截图/日志hash保存status-slots-production-evidence-r14.json。

这是当前产物在iOS26的实际配置→timeline→桌面证据，不扩大为iOS26全部模式/配色矩阵。覆盖安装后配置字段曾显示英文，冷加载的四语言配置验证仍待；无Simulator整体故障结论。Goal active，未remote handoff/merge/Mac draft。

### r15 其余三语言实际配置与完整lint（2026-10-02）

同一r10生产产物、自有iOS26.5设备依次设ja-JP/ja_JP、en-US/en_US、zh-Hant-US/zh-Hant_US并保留数据冷启动，bootstatus sessions36946/67588/64138均exit0；仅有意重启后重置baseline。日文实际显示模式/配色/四槽标签、picker未選択，选择Codex后Home单项78%且timeline codex；英文实际显示四槽与Not selected，清空后timeline空IDs、Home自动四项；繁体实际四槽/未選擇picker、选择Codex后timeline codex、Home已用78%。图片与日志hash冻结status-slots-production-evidence-r15.json，192项r10源码hash仍全一致。

繁体切语言后原已保存空对象display保留英文Not selected；同ID重选界面暂改未選擇，滚动/退出时出现無法載入，必须保留失败证据。SpringBoard日志记录系统WidgetConfigurationExtension连接中断；RunningBoard同PID30442随后仍running-suspended，无对应crash报告或sim-use未知进程消失banner。用Home退出再编辑可打开，随后不同ID Codex选择正常退出并被timeline消费。根因/是否需default handler修复交review，不据成功重试抹去可靠性问题。此时不宣称iOS整体done。

Scripts/lint.sh audit-i18n exit0，所有catalogue四语言translated、382源keys齐全。完整root lint首轮r15 exit2因Xcode Python3.9缺waitid；改用已有Homebrew Python3.14置PATH前，r16 terminal exit0：2749文件零SwiftLint违规、资源/解析版本及相关policy guards通过。不是整个iOS目录SwiftLint零违规声明；新生产Swift文件另有此前strict lint证据。未安装工具或改源码以绕过检查。正在恢复该专用设备原zh-Hans-US/en-US、zh-Hans_US设置，待boot核对。Goal active，未push/PR/merge/tag/TestFlight/Mac draft。

### r16 默认值补全与失败复验（2026-10-02）

review确认generated协议defaultProvider1–4为optional，缺实现不能直接叫timeout根因。为消除实际default lookup1003，handler新增四个同步默认方法，共用当前语言的emptyChoice；不读catalogue、不保存全局选择。新增差异review clean。192源码hash冻结status-slots-r16-inputs.json，构建session30317 terminalexit0/BUILD SUCCEEDED，安装前产物全文件hash冻结status-slots-r16-artifacts.json。handler strict lint exit0。focused test session75873 terminalexit0/TEST SUCCEEDED，51 tests/66 runs，0失败/跳过/runtime warnings，自有iOS27。

覆盖安装自有iOS26后再冷切繁体，bootstatus session29508 exit0。实际选择未選擇，再重选同一空ID、滚动四槽并outside(15,630)退出，仍出现無法載入；new errors日志未见default lookup1003，但系统WidgetConfigurationExtension连接再次中断。因此默认值补全只消除一项观察错误，不是失败根因的充分修复。保留failed-exit-r16.png、errors/termination/timeline日志，不宣称繁体可靠性通过。

独立探索对照：退出失败面板后重新编辑，选择不同ID Claude，停留并截图后通过Home按钮退出。timeline实际收到claude，settled Home显示Claude42%及繁体已用；最初Home截图仍为旧Codex过渡，不能当失败或最终通过，只用settled截图。这证明这种正常退出路径能保存并被生产消费，但未完成固定时长/滚动的同不同ID×Home/outside四对照，不能排除配置会话问题。

证据hash冻结status-slots-production-evidence-r16.json。专用iOS26仍保持zh-Hant，供下一步受控诊断，原设置文件保留；未操作其他项目设备/全局服务。Goal active，iOS可靠性gate及最终来源review仍待；未push/PR/merge/tag/TestFlight/Mac draft。

### r17 受控退出对照与配置读回（2026-10-02）

生产源码/产物仍为冻结r16，未为取得通过修改实现。脚本status-slots-controlled-r17.py逐步observe→act→verify，遇未知UI或PROCESS DISAPPEARED立即停止；固定滚动后等待45s，实际滚动验证到退出46.26–47.91s。每组退出后重新编辑并截图读回，再回桌面检查。早期人工a组实际57.82s，作为探索证据，不冒称固定30s对照。

| 组 | 前值→重选 | 退出 | 结果 |
| --- | --- | --- | --- |
| a-repeat | Claude→Claude | Home | 正常退出，读回Claude |
| b | Claude→Claude | outside15,630 | 正常退出，读回Claude |
| c | Claude→未選擇 | Home | 正常退出，读回空槽；timeline空IDs，桌面自动四项 |
| d | 未選擇→未選擇 | Home | 正常退出，读回空槽；桌面自动四项 |
| e | 未選擇→未選擇 | outside15,630 | 正常退出，读回空槽；桌面自动四项 |
| f | 未選擇→Codex | outside15,630 | 正常退出，读回Codex；桌面78% |

六组终态exit0，无实际無法載入、未知crash banner或数据清除。每组action JSON包含原始UI/命令/timestamp，result记录实际停留，图片已检查。完整系统日志status-slots-controlled-lifecycle-r17.log及-f.log在终态后停止保存；正常退出a/b也出现system extension connection interrupted和Invalidation requested，所以单条该日志不能替代实际面板结果。不能据本轮无复现宣称旧失败根因已修复，旧r15/r16失败证据和系统会话风险保留，请review比较。

所有截图/脚本/逐动作/日志hash冻结status-slots-production-evidence-r17.json。当前控制流程已通过，其余本地scope仍依据此前分来源证据；最终验收判断与来源提交review进行中。正在恢复专用iOS26原简中设置。未remote handoff/merge/Mac draft，Goal active。

## r18发布前专项覆盖与当前来源复核（2026-10-02）

产品检查点55fdc080dc5b228d811e34a3969ed49b5a6fec95、文档检查点7661b9ed25ff6ccc0ea21612df80004fee1bd180均已完成exact-head本地review，未发现新增阻塞；工作树clean。192/192产品输入与r16冻结SHA一致；Mac Sources/Tests/Shared/Package/version.env相对完整回归bc26b3512 diff为空。

发布清单的多账号专项命令通过安全test_environment执行：明确unset live Keychain opt-in，TMPDIR指向SSD，`swift test --skip-build --filter 'AccountIdentity|MultiAccount|DualZoneReader'`终态exit0，128 tests/12 suites通过；mac-account-gate-r18.log保留完整结果。DualZoneReader位于iOS target，不能把这个Mac过滤器当该suite证据。另从r7标准xcresult测试树逐项读回7个AccountIdentity/MultiAccount/DualZoneReader suites，共65 test-case节点均Passed，其中DualZoneReader10项；ios-account-gate-readback-r18.json记录节点与结果。这是旧r7证据覆盖复核，不宣称在r18重跑iOS全量测试。

当前CI policy与fork README guards exit0；changelog-to-html 0.70.0.1实际提取fork Highlights/Changed/Fixed和Mobile2.3.0标题，非上游技术段。MOBILE_VERSION保持已发配套2.3.0，未上传的iOS2.4.0不作为已发版本。GitHub只读回读：唯一open upstream-sync仍为#166，最新published稳定release仍为v0.70.0，前两版v0.69.0/v0.68.0；本分支PR列表为空。未push/PR/merge/tag/签名公证/Mac draft/TestFlight。

## r19 iPhoneOS Release 编译及实际产物预检（2026-10-02）

新options target此前只有Debug/Simulator证据，本轮补完整generic iOS Release编译。源commit30a41cf87c949a18984d6c357ed1df553da692bd、192输入与r16冻结SHA一致；SSD挂载UUID与可写/realpath预检通过。`xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj -scheme CodexBarMobile -configuration Release -destination 'generic/platform=iOS' -derivedDataPath <scratch>/ios-release-preflight-r19 -resultBundlePath <scratch>/ios-release-preflight-r19.xcresult -packageAuthorizationProvider netrc CODE_SIGNING_ALLOWED=NO -jobs 2 build`终态exit0 / BUILD SUCCEEDED。session88649正常结束，没有重启或取消。

实际App内嵌Push/Widgets/WidgetOptions三extension及CodexBarSync.framework；五bundle均2.4.0(227)、arm64，五binary UUID与各自Release dSYM逐项一致。App/Widgets/Options×四语言共12份编译WidgetStatus.strings解码后与当前源逐键逐值一致，每份20键；Options四语言Not selected也与xcstrings源值一致。App包60文件SHA与bundle/binary/dSYM/version/resource核对记录于ios-release-preflight-r19-artifacts.json，192输入及源码commit另存-inputs.json。首次核对误把22行源文件当22键导致检查失败；改为源strings解码比对后通过，未改任何产品资源。

构建零error diagnostics、有5个warning diagnostics（7条匹配日志行，其中2条为重复插图），主要为Shared CloudSyncManager既有未使用save返回值和无AppIntents依赖target的metadata extraction skipped，完整行保留manifest/log；不称零warning构建。本轮只证明Release编译与上述静态实际产物条件，签名关闭，不是archive、export、上传、可安装发行物、真实CloudKit/APNs或Release runtime验收。未读发布凭证、未操作实体设备、未push/PR/merge/tag/Mac draft/TestFlight。下一步remote handoff仍等待Goal要求的用户明确授权。

## PR169 本地历史与同步恢复补充回归（2026-10-02）

本轮保留iOS 2.4.0，统一build229。详见[063本地历史排查](../063-local-history-authority.md)，
包括16组合的substituted证据与残余风险；原上游同步证据不代表这次修复已经在实体机部署。
新Shared类型仅为reader/cache来源信息，未新增Mac CloudKit field/type/index，代码审计NO_DEPLOY。

r50标准xcodebuild：941 tests pass、0 failed/skip，含四语言UI、1/7/30/90/365 Today补缺、
legacy session日期校验、旧/新producer metadata × 保存/实时history状态矩阵。
Mac最终同步/协调器/费用过滤200 tests / 19 suites pass，设置/错误恢复专项57 tests pass；
此前全量1520 selections / 137 groups按记录完成，旧架构标记与dashboard混用断言的初次失败
已经复测并完成剩余manifest，不冒称单次全绿。所有测试禁用真实Keychain。
全量lint r8与独立子线程审查通过；generic iOS Release r51 BUILD SUCCEEDED。
新fixture的r48/r49编译参数顺序失败已修复并完整重跑r50。

两台手机只读SQLite+WAL备份在独立模拟器按生产reader完整365天账本验收，金额、Tokens、
active days各自稳定；实际金额与截图仅保留私有SSD scratch，不上传公开fixture。
实体Mac设置渲染/卡顿检查因CUA持续timeoutReached未完成；两Mac两iPhone仍为旧版，
16组合以fixture、reader/cache流水线、旧数据库副本代替，真实生产CloudKit时序尚未验证。
PR168已在exact-head clean/gate/Fast Checks通过后合并；PR169需要本次最新修复的新head
再完成远端CR。整体Goal仍in-progress，未因源码通过宣称Mac draft或TestFlight已完成。

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
