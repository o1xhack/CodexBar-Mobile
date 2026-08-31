# v0.56.0 / iOS 1.23.0 测试与发布证据

Status: `done`
Date: 2026-08-28

## 兼容基线

| Role | Old | New candidate |
|---|---|---|
| Mac | `0.54.0.1 (127.1.1.22.0)` | `0.56.0.1 (131.1.1.23.0)` |
| iPhone | `1.22.0 (195)` | `1.23.0 (196)` |
| upstream | `v0.54.0` | `v0.56.0` |
| Mobile payload | `providerPayloadVersion=1` | 保持 `1`，现有 opaque optional JSON |
| Production schema | last published release baseline | `NO_DEPLOY`；Production 仍为既有 10 types |

## 总 gate

| Gate | Result | Evidence / notes |
|---|---|---|
| upstream provenance + second parent | pass | merge `a7ab9f708` 的第二 parent 为 `fc1bd0d797e235fee17cee1fe5920dcdd4dd4303`（`v0.56.0^{}`） |
| fork README / CI / release policy | pass | CI/path/reuse/sharding/release guards通过；README 经单独事实适配并更新 reviewed hash |
| Mac Release build + lint | pass | `swift build -c release`；`./Scripts/lint.sh lint`，2093 Swift files / 0 violations |
| Mac focused tests | pass | CloudSync migration 59+3、provider architecture 39、provider/cost 160+12；最终 OAuth/sync/producer set 57 tests / 7 suites |
| Mac full tests | pass | 修复 Codex OAuth priority 后干净 `swift test --no-parallel`：10254 tests / 964 suites / 0 failures / 630.228s |
| iOS xcodegen + Release build | pass | 4 targets 均为 `1.23.0 (196)`；最终 generic iOS Release compile `BUILD SUCCEEDED` |
| iOS focused/full tests | pass | v0.49 matrix + v0.56 semantics focused通过；full Simulator suite 738/738通过 |
| CloudKit Production audit | pass | static diff + `cktool export-schema`；结论 `NO_DEPLOY` |
| 16-case compatibility gate | substituted-complete | 16 行全部列出；无 2 Mac + 2 iPhone 实机，使用 S1-S5 替代证据 |
| local/agent review blocker count | pass | 三路 exact-head review 最终 blocker=0；CloudKit/iOS focused 复测通过；draft body finding 已修并 API 复核 |
| signed/notarized live Mac release | pass | 从 merge commit `9f3b28746` 重建；notary `Accepted`；staple/Gatekeeper/launch通过；ZIP/dSYM、live appcast与GitHub release全部回读验证 |
| iOS App Store Connect handoff | pass | Archive/upload `1.23.0 (196)`；`VALID` / `APP_STORE_ELIGIBLE`；四语言 `What's New`；build双向绑定回读通过；App Review为`WAITING_FOR_REVIEW` |
| final authorization boundary | pass | CloudKit `NO_DEPLOY`未deploy；App Review已按追加授权提交；`MANUAL` public iOS release未执行 |

## 已执行的关键命令

```bash
bash Scripts/check_ci_policy.sh
bash Scripts/check_fork_readme.sh
bash Scripts/lint.sh lint
swift build -c release
swift test --no-parallel

cd CodexBarMobile
xcodegen generate
xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile \
  -destination 'generic/platform=iOS' -configuration Release CODE_SIGNING_ALLOWED=NO build
xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

live provider probes、browser cookie imports、真实 Keychain reads不在默认回归中执行；使用 parser fixtures、
stub stores与 `KeychainNoUIQuery` seam。

## CloudKit audit（2026-08-28）

- baseline tag：`v0.54.0.1-mobile.1.22.0`；
- `git diff "$LAST_TAG"..HEAD -- Shared/iCloud/CloudConstants.swift`：零 diff；
- `git diff "$LAST_TAG"..HEAD -- Shared/Models/UsageSnapshot.swift | grep ...public let`：零输出；
- schema keyword grep只有 Research 文档命中，没有生产代码命中；
- `providerPayloadVersion` 在 root/Mobile 两处均保持 `1`；`diff -qr Shared CodexBarMobile/Shared`
  零输出，Mobile Shared 与 root 物理同源；
- Claude slot migration复用现有 `AccountSnapshot`；Mobile payload仍为既有
  `DeviceProviderSnapshot.payload` opaque Data；
- Production只读回看命令：

```bash
xcrun cktool export-schema --team-id 3TUERHN53E \
  --container-id iCloud.com.o1xhack.codexbar --environment production
```

- 输出 5,830 bytes，SHA-256
  `50cac5c334e301856adcd7506ffa793b90c7edc8ca8ab4264ba62502b1acc6f0`；
- 仍为 10 types：`AccountSnapshot`、`Device`、`DeviceLifecycleEvent`、
  `DeviceProviderSnapshot`、`DeviceSnapshot`、`Preferences`、
  `ProviderAccountLinkage`、`ProviderIntent`、`QuotaTransition`、`Users`；
- 没有新 type、field、index、zone、query 或 subscription。

最终 verdict：`NO_DEPLOY`。本轮不得且未执行 CloudKit schema deploy。

## Compatibility evidence keys

| Key | Scope | Result |
|---|---|---|
| S1 | old/new wire fixtures + Mac producer | pass：`SyncCoordinatorMobileBridgeTests`实际执行`pushCurrentSnapshot`的dynamic windows与Fireworks spend，`SyncCoordinatorV047MapperTests`覆盖generic details，`SyncCoordinatorTests`覆盖token-only/partial cost producer；再由`V056SyncSemanticsTests` 4项与`SyncWireFormatRoundTripTests`验证old payload、Kiro/Cursor/Fireworks/Antigravity round-trip与unknown cost，focused 57 tests / 7 suites通过 |
| S2 | iOS merge/cache/widget readers | pass：`V049SyncCompatTests` 16参数组合覆盖两 writer与 full-fetch/delta 两 reader；full iOS suite 738/738 |
| S3 | simulator build/tests | pass：正常 Simulator signing focused tests + full tests；generic iOS Release compile exit 0 |
| S4 | fleet/Mobile lifecycle、privacy、schema code audit | pass：Claude replacement save-confirmed-delete、terminal delete error保留 ownership、root/Mobile Shared parity、无 credential/raw local history上 wire |
| S5 | Production schema readback | pass：`cktool export-schema` 5,830 bytes / SHA-256 `50cac5c3...6f0` / 10 existing types / `NO_DEPLOY` |

## 2 Mac x 2 iPhone old/new matrix

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | S1+S2 baseline fixture | 未启动4台旧版实机；真实silent push未覆盖 |
| 2 | old | old | old | new | substituted | S1+S2 old writers / delta new reader | iPhone B真实独立cache与background delivery未覆盖 |
| 3 | old | old | new | old | substituted | S1+S2 old writers / full-fetch new reader | iPhone A真实独立cache与background delivery未覆盖 |
| 4 | old | old | new | new | substituted | S1+S2两条 reader path读取old payload | 两台iPhone真实CloudKit收敛未覆盖 |
| 5 | old | new | old | old | substituted | S1+S2+S4 mixed writers / legacy readers | 旧binary与Claude predecessor真实写入顺序未覆盖 |
| 6 | old | new | old | new | substituted | S1-S4 mixed writers/full+delta readers | 真实silent push、merge order与ghost reappearance未覆盖 |
| 7 | old | new | new | old | substituted | S1-S4 reader identity reversal | 真实silent push、merge order与ghost reappearance未覆盖 |
| 8 | old | new | new | new | substituted | S1-S4 mixed writers / new readers | Claude slot migration的Production传播时序未实测 |
| 9 | new | old | old | old | substituted | S1-S4 writer identity reversal / legacy readers | 旧binary与Claude predecessor真实写入顺序未覆盖 |
| 10 | new | old | old | new | substituted | S1-S4 mixed writers/full+delta readers | 真实silent push、merge order与ghost reappearance未覆盖 |
| 11 | new | old | new | old | substituted | S1-S4 mixed writers/reader reversal | 真实silent push、merge order与ghost reappearance未覆盖 |
| 12 | new | old | new | new | substituted | S1-S4 mixed writers / new readers | Claude slot migration的Production传播时序未实测 |
| 13 | new | new | old | old | substituted | S1+S2 new additive payload / legacy reader fixture | 两台旧iPhone binary未实跑，unknown fields由fixture证明忽略 |
| 14 | new | new | old | new | substituted | S1-S3 new writers / old+delta new reader | 两台iPhone真实cache与silent push未覆盖 |
| 15 | new | new | new | old | substituted | S1-S3 new writers / full new+old reader | 两台iPhone真实cache与silent push未覆盖 |
| 16 | new | new | new | new | substituted | S1-S5 all-new producer/merge/render/schema | 四台实机Production端到端收敛未覆盖 |

本轮没有可用的 2 Mac + 2 iPhone old/new 四机环境，因此 16 行均如实标记为
`substituted`，没有把 simulator/unit/code-audit 证据冒充真实设备 `pass`。替代 gate 完整，
但真实 Production propagation、silent push/background delivery、不同设备本地 cache 时序和
旧 binary 运行仍为 release residual risk；后续若要把这些风险降为实测 pass，必须另行安排四机矩阵。

## 必查行为

- replacement save成功前绝不删除 Claude email-key predecessor；
- old/new Mac并存不造成永久 duplicate、误删或 ghost reappearance；
- old/new iOS均能 decode dynamic fourth window、generic details与 optional cost fields；
- estimated/unpriced/unknown不会显示为确定 `$0`；
- 两台 iPhone merge/fallback/cache后可收敛到同一可见 provider state；
- provider/account/device identity不重复、不串账号；
- silent push/background delivery与真实 Production propagation若未实测，明确记录残余风险。

## 当前结论

- iOS兼容、wire、merge/cache、cost honesty、四语言与 Release build均通过；
- 16-case canonical gate以 `substituted-complete` 闭环，0 个已知 functional failure；
- CloudKit verdict为 `NO_DEPLOY`，Production只读回看完成；
- Mac full exact-product-tree rerun、signed/notarized draft 与最终 review evidence 全部完成；
- 三路最终 review 合计 blocker=0：CloudKit/Shared 额外复跑 migration 15/15 与
  v0.56 semantics 4/4，iOS/cost 额外复跑 18 focused tests，CI/release 发现的
  draft body 缺失已修复并回读通过；
- PR #105首轮exact-head review在`62abb00ef`发现2项Kiro一致性/本地化finding；修复后
  `KiroUsageLimitsAPITests` 20/20、iOS `V056SyncSemanticsTests` 4/4、full lint通过，
  第二轮在`64c7669c4`继续发现enabled/cap错误耦合；修复后组织账号fixture在无CLI
  overage文本且无API cap时仍显示authoritative API usage/charges，Kiro 20/20通过，
  第三轮在`84d51b643`发现bonus expiry后缀仍为英文；已复用既有4语言Kiro expiry
  key并覆盖19/1/0天，iOS `V056SyncSemanticsTests` 4/4通过，第四轮review待修复
  push后执行；第四轮无finding，PR转ready后第五轮在`6b8e9f768`发现Kiro overage
  window及Antigravity offline count两个同根本地化缺口；已按workflow写入architecture
  audit，统一改造provider-aware window展示边界并保留unknown/custom label原样，第六轮
  review前iOS `V045ProviderPresentationTests` + `V056SyncSemanticsTests` 8/8、full
  lint（SwiftLint 2093 files/0 violations、4语言catalog/source audit）通过；第六轮在
  `78568bf34`发现无email Claude Swap旧`Account N` CloudKit predecessor未进入
  save-confirmed delete保护；已从slot重建旧key并覆盖reconciliation、save未确认/确认路径，
  `swift test --filter 'SyncModelTests|CloudSyncSnapshotMigrationSaveThenDeleteTests'`
  33/33通过；full lint（SwiftLint 2093 files/0 violations、4语言catalog/source audit）
  再次通过；第七轮在`f189e2247`完成且无新finding，但unresolved-thread audit发现
  第五轮另有OpenRouter `API key limit`固定状态与z.ai `Account balance` breakdown两条
  P2未被纳入前次修复/resolve；已扩展provider-aware detail边界，覆盖OpenRouter固定
  降级状态、HTTP/rate格式及z.ai余额片段，dynamic/custom值保持原样；iOS
  `V056SyncSemanticsTests` 5/5与full lint（SwiftLint 2093 files/0 violations、4语言
  catalog/source audit）通过；第八轮在`4e7af68e0`发现无rate window时首页detail teaser
  仍直接渲染raw value；已让teaser调用同一provider-aware formatter并覆盖OpenRouter
  简中与custom provider fallback，iOS `V056SyncSemanticsTests` 5/5和full lint（SwiftLint
  2093 files/0 violations、4语言catalog/source audit）再次通过；第九轮在`1801b4db6`
  完成且无新finding、10条thread unresolved=0，但review gate错误要求pre-sixth audit的
  `Head`等于重构后的第六个distinct reviewed commit，和skill的“先按当时head audit、再
  重构”顺序矛盾；已改为匹配audit时点最近一次已review head、仍强制早于第六轮和完整
  四字段，新增合法checkpoint pass及stale checkpoint fail fixture；gate tests与PR #105
  live gate（rounds=8、unresolved=0）通过，full lint再次通过；第十轮在`caa1f6dd3`
  发现shared predecessor的Claude Swap sibling中一个confirmed、另一个terminal skip时，
  下一次refresh可能由confirmed sibling提前删除仍需保护的旧record；已在处理任何confirmed
  migration前统一stage全部sibling mapping，并让terminal skip保留durable predecessor
  protection，覆盖旧错误持久化状态的自动修复与confirmed/skip顺序，focused sync migration
  33/33、full lint 2093 files/0 violations通过；第十一轮在`014c1b31d`发现terminal-failed
  slot被authoritative refresh移除后仍会留下guard并永久阻止旧record清理；已让reconciliation
  先stage当前siblings、再按`recordNamesToDelete`剪除removed replacement guard，无其他引用时
  立即释放predecessor，有current sibling时继续等待confirmed save；focused sync migration
  34/34、full lint 2093 files/0 violations通过；第十二轮在`98c4da26b`发现Linux
  delayed-readiness cleanup fixture把1秒ready delay、process startup/observation handshake与
  0.5秒poll压进2秒总deadline，Ubuntu调度下可能误报124；已把该case deadline放宽到4秒，
  并patch parent runner sleep、断言任何单次sleep不超过0.5秒，以确定性保留旧1.2秒
  ancestry sleep回归；focused case通过（本机实际2.387秒），full sharding gate与62项cleanup
  tests通过，full lint 2093 files/0 violations通过；第十三轮在`f313b17af`发现removed
  Swap guard释放的email-keyed predecessor可能已经重新成为live普通Claude snapshot，若直接并入
  delete set会短暂删除当前账号record；已让`releasePredecessors`显式排除`liveNames`并覆盖
  关闭Swap回到普通账号的回归场景，focused sync migration 35/35、full lint 2093 files/0
  violations通过；第十四轮在`e9c5c2337`发现Kiro budget卡仍直接显示raw `Overage`
  period。因累计14轮仍出现同类finding，暂停逐条review并执行第二次整体architecture audit：
  所有生产Mac→iOS semantic sink加入provider-aware源码守卫，Raw Sync Data显式保留canonical
  wire text；同时把CloudKit live-predecessor保护下沉到confirmed-save产生delete set的最终
  destructive boundary，以latest accepted per-provider topology消除callback晚于账号拓扑变化的
  race。四态migration matrix连同既有suite为36/36，iOS `V056SyncSemanticsTests`扩至6/6；
  62项process cleanup tests、CI policy/final-path/review-gate和full lint（SwiftLint 2093/0、
  iOS 303 source keys四语完整）全部通过；整体修复提交为`e4a0bb2d3`，第十五轮
  exact-head review结论为`Didn't find any major issues`，0个新thread；
- 本文件状态为 `done`；PR #105、merge-only Final CI、Mac live release/appcast 与 iOS
  Archive/upload/build binding均已获用户追加授权并执行。2026-08-30 用户进一步授权 App Review，
  submission与version已回读为`WAITING_FOR_REVIEW`。CloudKit verdict为 `NO_DEPLOY`；
  public iOS release未执行。

## Published release / ASC closeout evidence

- PR #105 final reviewed head：`b5e8631edb265cfa60aebd86348e084e94fc946b`；merge commit：
  `9f3b28746ca74222e08bd8a2703d96c305546a26`；Final CI
  [33343515532](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/33343515532) 12 jobs success；
- live Mac artifact重新从merge后源码构建，`CodexGitCommit=9f3b28746`；notary submission
  `f19497f4-fc65-4295-af1d-2e54ef67480f` `Accepted`；codesign、stapler、Gatekeeper与本机重启通过；
- live release：
  `https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.56.0.1-mobile.1.23.0`；
  ZIP `74,884,775` bytes / SHA-256 `9ac9007b0a05530eccaff54b2a9b154fd61b1bd43cf9212535e057b8b1104d30`；
  dSYM `57,062,195` bytes / SHA-256 `6382c774b1a08af41ab55f788f54fb07a829660917a5e56eb842685b3c93ec40`；
- appcast live回读为 `0.56.0.1` / `131.1.1.23.0`，enclosure length `74,884,775`，
  EdDSA signature验证通过；commit `d3b30a48a`；
- App Store Connect version `1.23.0` 创建为 `MANUAL`，en-US、ja、zh-Hans、zh-Hant
  四语言 `What's New` API回读一致；
- `/tmp/CodexBarMobile-20260830-181907.xcarchive` 为 bundle `1.23.0 (196)`，主 app、Widget、
  Push Extension archive成功；主 app entitlement包含
  `com.apple.developer.icloud-container-environment=Production`；
- delivery `00812071-873e-42b7-94ab-dce1c6f12693` 为 `VALID` / `APP_STORE_ELIGIBLE` /
  non-expired / min iOS 17.0；App Store version→build与build→version双向关系均回读一致；
- icon gate：1024 source无alpha且视觉完整；Archive 120 CgBI icon无alpha且视觉完整；Apple CDN
  152 iconAssetToken视觉完整；
- pre-submission snapshot：PR #106 merge commit `0a7e5adac` 于
  `2026-08-31T03:04:28Z` 固化初始 closeout 状态；version 为
  `PREPARE_FOR_SUBMISSION` / `MANUAL`，没有 review submission；
- post-submission snapshot：review submission `3d68c4ed-ad43-4ec1-b066-d945e01d019e`
  关联唯一的 iOS `1.23.0`
  item，并于 `2026-08-31T03:19:07.901Z` 提交；submission与version均为
  `WAITING_FOR_REVIEW`，build `196`仍为`VALID`且未过期，四语言`What's New`逐项回读非空；
  releaseType保持`MANUAL`，没有公开iOS；
- #102-#104已附闭环证据并 close；open `upstream-sync` issue回读为空；合并后的 task branch已清理。

## Historical signed draft evidence

- artifact source commit：`0d7db66a68ce341ddf5fc404048407500bddd944`；
- Apple notarization submission `2e926c37-a720-4c37-b6e0-a83d12b80e24`：`Accepted`；
- 解包后 `codesign --verify --deep --strict`、`spctl --assess`、`stapler validate`、
  `syspolicy_check distribution` 全部通过，CloudKit entitlement 为 `Production`；
- ZIP：74,879,194 bytes，SHA-256
  `1764e11669bab7439c3d283ca60279a189bb1711a5f4a75e3a07f728c24bd5ed`；
- dSYM：57,059,595 bytes，SHA-256
  `ebf84fd9281cfb13ac9983a858689686c30c0ecaf3f73a235d0701891d248e6a`；
- app/dSYM UUID一致：x86_64 `BDD23A54-0136-3971-BF58-4FF48A85F382`，arm64
  `6AE7CA97-6A0B-31C0-AA9D-EE26B35F6FDF`；
- candidate appcast 只在 detached `/tmp/codexbar-v056-appcast-0d7db66a` 生成；
  XML valid，`sparkle:version=131.1.1.23.0`，完整 tag URL，enclosure length
  74,879,194，EdDSA signature 验证通过；
- GitHub draft：`https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-f119f55a105dc5efcac0`，
  database ID `378828305`，`draft=true`，`target_commitish=mobile-dev`；资产均
  `uploaded`，远端 digest/size 与本地完全一致；
- draft body 已从 root CHANGELOG 回写并 API 回读 `Added`、`Changed`、`Fixed`、
  `Upstream release range`，同时保留 exact source SHA 与 no-publish gate；
- draft 创建完成时 remote task branch/tag 均为 0 lines；2026-08-30用户追加授权后仅push
  task branch并创建PR #105，candidate tag仍不存在；live `appcast.xml` 与
  `origin/mobile-dev` SHA-256 均为
  `7a0078d8ab90af5be5d19e343c3054e2df45d9d94d584950491a77907eb03267`。

GitHub draft 因 no-push 边界暂指向 remote `mobile-dev`；notes 已锁定本地 artifact
source commit。公开前必须在该 exact commit 合入 `mobile-dev` 后重验 target、assets、
candidate appcast、review gate 与 release checklist。

## Mac full-test failure / fix log

1. `swift test --no-parallel` 首轮完成 10,254 tests / 964 suites，1 issue；第二次带完整
   `/tmp` log复现为 `CodexOAuthExpiryPipelineTests.future expiry keeps OAuth model windows...`：
   CLI `.auto` 在有效 native OAuth之前尝试fork web dashboard；
2. 调整CLI auto顺序为 `PAT -> OAuth -> web dashboard -> CLI`：保留fork dashboard fallback，
   同时让有效OAuth优先提供model-scoped windows与正确account identity；managed workspace仍只走
   `PAT -> OAuth`；
3. 更新fork characterization，并运行OAuth expiry、baseline、CloudKit delete、Mobile producer、
   generic details和SyncCoordinator focused regex：57 tests / 7 suites全部通过；
4. final `swift test --no-parallel` 在该修复后的 exact product tree 完成：
   `Test run with 10254 tests in 964 suites passed after 630.228 seconds`，exit 0；
5. 随后最终 `./Scripts/lint.sh lint` 通过：SwiftFormat 0 files、SwiftLint
   2093 files / 0 violations、iOS 303 source keys四语全部 translated；最终 generic
   iOS Release build 为 `BUILD SUCCEEDED`。
