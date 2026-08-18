# v0.52.0 Upstream Sync 测试证据

Status: `done`
Date: 2026-08-17

## 版本与范围

- old Mac: published fork `0.49.2.1 (116.1.1.21.0)`；
- new Mac candidate: `0.52.0.1 (124.1.1.21.0)`；
- old iPhone: iOS `1.21.0 (193)`；
- new iPhone candidate: iOS `1.21.0 (194)`；
- payload/CloudKit baseline: `providerPayloadVersion=1`、Production container。

## 计划 gates

| Gate | 结果 | Evidence / Notes |
|---|---|---|
| Merge provenance / fork conflict audit | pass | merge `25f81f26f`；upstream parent/tag peel `dc3ea3206c...`；14 conflicts逐项记录在`02-development.md` |
| Mac build + lint + full tests | pass | `swift build`；final lint：SwiftFormat 1965 files / 0 formatting、SwiftLint 1964 files / 0 violations、i18n 302 keys全覆盖；post-review CI-style grouped gate 923 selections / 77 groups全部首轮成功，0 failed / 0 retry / 0 timeout |
| Provider/cost/keychain/PTY/settings/sync focused regression | pass | pre-1.2/v0.26/v0.27/v0.29/v0.30/v0.37 wire、fleet/Mobile、多账号138 tests；architecture 38；UsageStore 34；bounded cost 10；Kiro/PTY 57，全部0 failed |
| Parser fingerprint/hash | pass | `parserLogicVersion=12`；final `CodexParserHash=a5a0cf92c6361f6e`；architecture 38 tests与lint audit通过 |
| Packaged signed/notarized candidate | pass | notary `da55b536-c3ea-4d45-a6cc-cdb7a4a71507` Accepted；stapled ZIP 66 MB，SHA-256 `15fdd2ea...0976`；dSYM 51 MB，SHA-256 `7ac90a4a...0d8d` |
| codesign / spctl / CLI / launch smoke | pass | extracted release ZIP：Developer ID、deep strict verify、Gatekeeper Notarized Developer ID、stapler validate、Production entitlement、universal main/CLI/widget、direct launch均通过；embedded commit `90c687939` |
| iOS build + full tests | pass | `xcodegen generate`；Release simulator build成功；signed iPhone 16e / iOS 26.2 Simulator完整`CodexBarMobileTests` 633 tests、0 failed |
| Widget/cost/provider display parity | pass | CloudKit merge、dual-zone、widget、device lifecycle、cache、multi-account、provider labels focused 110 tests、0 failed |
| Four-language localization | pass | `jq empty`；i18n 302 source keys present；en/zh-Hans/zh-Hant/ja均translated |
| CloudKit Production schema audit | pass — `NO_DEPLOY` | last live tag `v0.49.2.1-mobile.1.21.0`到candidate：CloudConstants零diff、UsageSnapshot public fields零diff、schema keyword零source hit；Production readback仍10 types |
| Draft release asset/readback | pass | draft ID `372056029`；[draft URL](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-9d15f5c94de6761c5243)；ZIP `69578142` bytes、dSYM `53855298` bytes均uploaded且digest匹配；remote branch/tag不存在，live appcast未改 |
| Final review blockers | pass | pricing provenance、published-tag cache迁移、same-name project identity/UI、multi-account attribution findings均修复并复审clean；architecture exact anchors由混杂261项收敛为reviewed 83项；当前blocker 0 |

首轮CI-style grouped gate执行`CODEXBAR_TEST_GROUP_SIZE=12
CODEXBAR_TEST_SUITE_TIMEOUT=240 bash Scripts/test.sh`：发现923个selection、77组，全部first-pass
成功，0 failure / 0 retry / 0 timeout，execution 739.4s / total 745.8s。唯一skip为需要显式设置
`CODEXBAR_ACCENT_SCREENSHOT_DIR`的截图渲染fixture；provider accent逻辑、配置、refresh revision
tests均实际运行通过。首轮全分支Codex review的唯一P2（routed exact pricing被误标estimated）已
修复；63个`CostUsagePricingTests`与`SyncCostIsEstimatedTests`通过，lint随之要求并完成parser
hash重生。最终post-fix grouped gate重新发现923个selection并完成77组：77 first-pass success、
0 first-pass failure、0 full-group retry、0 timeout、0 isolated retry，discovery 65.5s、execution
749.3s、total 814.8s。review提出的comment-only predecessor迁移P2修复后，失败用例隔离
`--no-parallel`通过，完整`CostUsageStoreTests` 75 tests与architecture 38 tests均通过。
最终upgrade-path审计从实际published tag读取generated parser hash
`834522608c1b0457`，发现既有0.49.x marker并非公开build marker；`34857a41c`补齐真实迁移来源，
并以tag value跑过75项serial store tests及97项pricing/store/sync联合tests。commit review确认
SQLite schema未变且adoption的hash、version、quick-check与auto-vacuum gates仍完整，0 finding。

最终全分支review发现same-name project在相同source下按名称合并的P2。`dddcd4fa3`将canonical
path纳入aggregation与collision-safe ID，且只在同名冲突时显示path。后续两轮精确review继续
发现视觉不可区分与HOME-dependent test expectation，均修复后普通HOME和
`CFFIXED_USER_HOME=/Users/example`各40项测试通过，commit review clean。后续whole-branch review
又发现同repo跨两个Codex账号时row仍显示generic provider name的P2；`1ae439e46`改用account-aware
display name，40项focused tests与commit review clean。

最终完整gate在第56/77组失败并稳定重现。审计确认大量allowlist/suppression anchor在上游合并后
仍是旧行号，并被混入原261项drift hash；本轮逐项重定位全部unique/duplicate anchor，拆分实际
cluster并复核变化后的fingerprint，而不是直接放宽总hash。`90c687939`将真实fork-only drift收敛
到83项；architecture 38 tests通过，随后从头运行同一命令，923 selections / 77 groups全部
first-pass成功，0 failed / 0 retry / 0 timeout / 0 isolated retry，discovery 6.2s、execution
753.1s、total 759.3s。最终lint同时通过22 catalogs / 1486 English keys、SwiftFormat 1965 files、
SwiftLint 1964 files与iOS 302 source keys四语言检查。

首次iOS focused test曾用`CODE_SIGNING_ALLOWED=NO`，runner在bootstrap前因CloudKit/KVS
entitlement缺失退出，0个断言执行；这不是产品失败。改用正常Simulator签名后focused与full tests
均通过。Release simulator build可在无签名模式产出，但所有运行型sync测试使用正常签名产物。

## CloudKit Production schema审计

基线由GitHub published release只读查询确定为`v0.49.2.1-mobile.1.21.0`。执行文档定义的三组
diff audit后，排除Research文案的source结果均为空：

- `Shared/iCloud/CloudConstants.swift`：零diff；
- `Shared/Models/UsageSnapshot.swift`：无新增/删除`public let`；
- 无新增record type、field、index、zone、subscription、query、encoding version或
  `providerPayloadVersion` bump；
- Mac package与iOS entitlement均明确
  `com.apple.developer.icloud-container-environment = Production`。

只读执行`xcrun cktool export-schema --team-id 3TUERHN53E --container-id
iCloud.com.o1xhack.codexbar --environment production`成功，回读5829 bytes，仍为既有10 types：
`AccountSnapshot`、`Device`、`DeviceLifecycleEvent`、`DeviceProviderSnapshot`、
`DeviceSnapshot`、`Preferences`、`ProviderAccountLinkage`、`ProviderIntent`、
`QuotaTransition`、`Users`。因此结论是`NO_DEPLOY`，未执行任何CloudKit deploy。

## 签名、公证、draft与Sparkle证据

- `./Scripts/sign-and-notarize.sh`完成双架构production build、widget extension、deep signing、
  offline resource/launch smoke、Apple notarization与stapling；submission
  `da55b536-c3ea-4d45-a6cc-cdb7a4a71507`为`Accepted`；
- 从最终release ZIP重新解压验证，`xcrun stapler validate`、`spctl --assess`、
  `codesign --verify --deep --strict`全部成功；Info.plist为`0.52.0.1 / 124.1.1.21.0`、
  embedded commit `90c687939`，CloudKit environment仍为Production；
- app/dSYM UUID逐一相同：x86_64 `31392159-0BB9-379E-8035-037FB7F7981C`、arm64
  `353F365B-21A7-32AE-90FA-B80802CE8529`；asset SHA-256与GitHub draft readback size记录在
  `02-development.md`；
- GitHub draft保持`draft=true`、`prerelease=false`，tag name为
  `v0.52.0.1-mobile.1.21.0`但remote Git ref不存在；没有live publication；
- candidate appcast只在detached临时worktree生成并在验证后移除，enclosure URL使用完整
  candidate tag，length `69578142`、Sparkle version `124.1.1.21.0`、`sign_update`重算的EdDSA
  signature均验证成功；repo live
  `appcast.xml` hash保持不变。

## compatibility substitution evidence

本机无法提供2台Mac与2台iPhone、并对4台设备反复安装old/new binaries；16行不能标成实机
pass。以下替代证据组合用于每行：

- **S1 — old/new wire + writers（138 tests）**：`SyncWireFormatRoundTripTests`、v0.26/
  v0.27/v0.29/v0.30/v0.37 old fixtures、`CloudSyncSettingsTests`、
  `SyncCoordinatorMobileBridgeTests`、`SyncCoordinatorMultiAccountTests`、
  `SyncMultiAccountEdgeCasesTests`、`AccountIdentityComputerTests`；serial，0 failed。
- **S2 — independent readers/merge/cache（110 tests）**：iOS `CloudKitMergeTests`、
  `DualZoneReaderTests`、`DeviceLifecycleEventTests`、`WidgetSnapshotBuilderTests`、
  `ViewCacheIdentityTests`、`MultiAccountForEachIdentityTests`、provider label tests；0 failed。
- **S3 — all-new consumer regression（633 tests）**：完整iOS test target在signed iPhone 16e /
  iOS 26.2 Simulator运行，0 failed。
- **S4 — lifecycle/producer audit**：AppDelegate start/stop test、Mobile bridge tests、
  `providerPayloadVersion=1`、Shared/CloudConstants零diff、project/session path不在Mobile producer。
- **S5 — server contract**：Production schema只读回读10 types，candidate无schema diff，
  `NO_DEPLOY`。

## 2 Mac × 2 iPhone old/new compatibility matrix

本轮 provider display data、Mac fleet sync optional fields、widget/cache projection与跨版本
rendering有变化，因此 gate适用。每一行后续必须填 pass/fail/substituted及实际 evidence。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | S1 old fixtures + S5 | published-format control；无四实机重放 |
| 2 | old | old | old | new | substituted | S1 + S2 + S3 | new reader解old payload；silent push未实测 |
| 3 | old | old | new | old | substituted | S1 + S2 | 两reader cache路径分离；第二iPhone未实测 |
| 4 | old | old | new | new | substituted | S1 + S2 + S3 | new readers merge old writers；真实传播未实测 |
| 5 | old | new | old | old | substituted | S1 + S4 + S5 | mixed writer/delete/identity；old binary硬件未实测 |
| 6 | old | new | old | new | substituted | S1 + S2 + S4 | 全角色混合；background delivery未实测 |
| 7 | old | new | new | old | substituted | S1 + S2 + S4 | reader顺序反转由deterministic merge覆盖 |
| 8 | old | new | new | new | substituted | S1 + S2 + S3 + S4 | mixed writer/new readers；真实push未实测 |
| 9 | new | old | old | old | substituted | S1 + S4 + S5 | writer顺序反转由device-ID/timestamp tests覆盖 |
| 10 | new | old | old | new | substituted | S1 + S2 + S4 | 非对称reader；第二实机未实测 |
| 11 | new | old | new | old | substituted | S1 + S2 + S4 | 非对称reader反转；第二实机未实测 |
| 12 | new | old | new | new | substituted | S1 + S2 + S3 + S4 | mixed writers/new readers；真实传播未实测 |
| 13 | new | new | old | old | substituted | S1 + S4 + S5 | new producer复用旧wire；old iOS binary未实测 |
| 14 | new | new | old | new | substituted | S1 + S2 + S3 + S4 | reader版本独立；silent push未实测 |
| 15 | new | new | new | old | substituted | S1 + S2 + S3 + S4 | reader版本反转；silent push未实测 |
| 16 | new | new | new | new | substituted | S1 + S2 + S3 + S4 + S5 | all-new simulator/fixture convergence；四实机未实测 |

## 每个 case 的验收语义

- old/new writers不破坏 device + provider + account identity与delete/ghost规则；
- old iPhone忽略新 optional内容且不crash，新 iPhone安全读取old payload；
- Claude scoped rows、Cursor/Vertex/OpenCode/Grok/Antigravity semantics不重复、不误标、不丢卡；
- 两个 iPhone在fetch/silent push/cache fallback后收敛；
- accent color/workday tick只留在Mac fleet sync，不进入Mobile payload；
- project path、conversation/session identity、credential/plugin secret不进入CloudKit Mobile records。

## substituted evidence 要求

若本机没有2 Mac + 2 iPhone可反复安装old/new binaries，不能把矩阵写成实机pass。必须记录：

1. 缺少的真实硬件/old binary组合；
2. 对应 old/new Codable fixture、dual-writer reducer、cache/delete/ghost、CloudKit mock、
   simulator或代码审计路径；
3. silent push、真实Production传播、background delivery与旧binary行为的剩余用户风险。

本轮16行全部完成substitution，未发现功能/serialization/schema blocker。gate结论为
**substituted pass**，不是real-device pass。剩余风险集中在真实Production CloudKit传播延迟、
silent push与background delivery、两个独立iPhone cache最终收敛，以及old iOS 193 binary读取
new Mac producer的真实设备行为；这些风险在live/TestFlight授权前无法消除，不被伪装成已实测。
