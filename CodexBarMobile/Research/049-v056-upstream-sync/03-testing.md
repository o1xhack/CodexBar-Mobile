# v0.56.0 / iOS 1.23.0 测试与发布证据

Status: `in-progress`
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
| local/agent review blocker count | in progress | Shared delete terminal-error P1 已修并复核；最终 release evidence review待完成 |
| signed/notarized draft | pending | ZIP/dSYM + draft URL |
| no push/merge/live/TestFlight/deploy boundary | pass-so-far | 未 push/merge/publish/TestFlight/deploy；draft 后再回读 remote branch/tag/live feed |

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
旧 binary 运行仍为 release residual risk；公开 release 前若要把这些风险降为实测 pass，必须另行
安排四机矩阵。

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
- Mac full exact-product-tree rerun 已通过；signed/notarized draft 与最终 review evidence
  仍是本文件进入 `done` 前的剩余 gate。

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
