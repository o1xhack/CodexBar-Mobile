# v0.47.0 Upstream Sync 测试证据

Status: `done`
Date: 2026-08-03

## 环境定义

- Old Mac: published fork `0.45.2.2 (109.2.1.19.0)`
- New Mac: candidate `0.47.0.1 (111.1.1.20.0)`
- Old iPhone: current `1.19.1 (191)`
- New iPhone: candidate `1.20.0 (192)`
- Branch base: `9d9db632`
- Upstream target: annotated tag `v0.47.0`, peeled commit `6a16c233`

会触发 Keychain prompt、读取真实 browser session、访问 live provider 或写 CloudKit
Production 的命令不在未单独授权的自动测试中运行。

## Command evidence

| Gate | Command / evidence | Result |
|---|---|---|
| Branch preflight | `git status` / HEAD 与 `origin/mobile-dev` 比较 | pass；clean base `9d9db632` |
| Upstream provenance | tag type/object/peeled commit、ancestry、merge parents | pass；merge `78aa2f067` 的 second parent 为 `6a16c233` |
| Merge build | `swift build` | pass |
| Portable/release lint | `bash Scripts/lint.sh lint` | pass；0 SwiftFormat / SwiftLint violation；i18n/parser/package/release checks 全过 |
| CI policy | `bash Scripts/check_ci_policy.sh`（也包含在 lint） | pass；PR update 仍只有 Fast Checks |
| Mac full tests | `swift test --no-parallel` | pass；post-review rerun 8340 tests / 812 suites / 0 issue / 363.739s；log `/tmp/codexbar-v047-full-test-postreview.log` |
| Multi-account/device | `swift test --skip-build --filter 'AccountIdentity\|MultiAccount\|DualZoneReader'` | pass；106 tests / 12 suites；截图生成器因未设输出目录 skip 1 |
| Fleet CloudSync | `CloudSyncSettingsTests`、engine/model/persistence tests（full suite） | pass；toggle/key、first-contact、dirty set、secret gate 均覆盖 |
| Fleet snapshot deletion review fix | `swift test --filter CloudSyncSettingsTests` + `swift test --no-parallel` | pass；在当前 release code SHA `15a77b70f` 重跑 36/36 focused；local full 8363 tests / 812 suites / 0 failure / 336.143s，logs `/tmp/codexbar-pr71-15a77b70f-focused.log`、`/tmp/codexbar-pr71-15a77b70f-full.log`；覆盖 record-scoped removal/provenance/revision/generation、external config / CloudKit intent removal、offline startup repair、invalid/stale-disk authority refusal、overtaken local dirty/cancellation ordering、跨启动 durable delete cancellation |
| Linux Final CI | x64/arm64 Linux build + tests + CLI smoke | pass；修正后的 x64/arm64 均通过；x64 首轮只在 `ProcessPipeCaptureLinuxTests` 的 raw-FD assertion 假失败，因为已关闭 FD number 被并发 suite 复用；`71772e15e` 改用 `/proc/self/fd` target identity 验证旧 pipe alias 已关闭 |
| macOS Final CI discovery | 6-shard `Scripts/test.sh` | pass；最终 `15a77b70f` 固定执行 4 次 discovery，最多容忍 1 次 malformed，但任何有效 selection set 不一致立即 hard fail，至少 3 次有效结果才执行分片；malformed-once 与稳定截断回归均通过；manual Final CI run [`31239327715`](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/31239327715) 的 6/6 shards 全绿 |
| Shared/four-provider wire | `SyncCoordinatorV047MapperTests`、`V047MobileEnvelopeCompatibilityTests`、mock/provider contracts | pass；5 + 2 focused tests；含 ZoomMate history 失败仍保留 structured status |
| Alibaba regression | `AlibabaTokenPlanPersonalTests` | pass；4 tests |
| iOS unit gate | `xcodebuild ... -only-testing:CodexBarMobileTests test -quiet` | pass；post-review rerun 617 tests / 639 runs / 0 failed；xcresult `14-33-51` |
| Widget data parity | `... -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests test` | pass；11 tests；xcresult `14-15-41` |
| iOS Release build | `xcodebuild ... -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build -quiet` | pass |
| 16-case compatibility | parameterized `V047SyncCompatTests/fourDeviceCompatibilityMatrix(mask:)` | substituted pass；production codec/cache/delete/render invariants，16 dynamic runs，见 matrix |
| CloudKit audit/deploy | published `v0.45.2.2-mobile.1.19.0` → HEAD + Development import + Console promotion + Production export | pass；Console 部署 5 types / 1 index / 3 role updates，Production 回读为完整 10-type union |
| Package credential policy | `bash -n Scripts/package_app.sh` + `test_package_signing.sh` | pass；Widget Xcode resolver 强制 `netrc`，不回退交互式 Keychain lookup |
| Signing/notarization | `Scripts/sign-and-notarize.sh` + 独立 ZIP 解包验收 | pass；Developer ID、notarization Accepted、staple、Gatekeeper、universal binaries、Production entitlement、dSYM UUID 全部通过 |
| GitHub draft | draft create + API readback + local/remote tag/branch audit | pass；draft ID `364520043`，两资产 size/digest 一致；未创建 tag、未 push |
| Review | self diff + GitHub Codex iterative review | pass；截至 PR head `a17ed979f` 的 findings 已逐条修复、回复、resolve；exact-SHA Codex review 明确返回 “Didn't find any major issues”，unresolved threads `0`，`P0=0 / P1=0 / P2=0 / blocker=0` |

## 2 Mac × 2 iPhone compatibility matrix

本轮同时改变 Mac→CloudKit→iOS provider data、Shared payload、cache/render 与新增 Mac
fleet CloudKit record family，所以 16 组合全部适用。真实硬件不可用时只能标记
`substituted`，不能写成 physical-device pass。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | matrix mask 0 | all-old control；legacy decoder，两个 device IDs |
| 2 | old | old | old | new | substituted | matrix mask 1 | new reader 从两份 legacy payload 建独立 cache |
| 3 | old | old | new | old | substituted | matrix mask 2 | 与 Case 2 镜像；reader state 不共享 |
| 4 | old | old | new | new | substituted | matrix mask 3 | 两个 new reader 对 legacy writers 收敛 |
| 5 | old | new | old | old | substituted | matrix mask 4 | old readers 忽略新 typed keys，保留 generic lanes |
| 6 | old | new | old | new | substituted | matrix mask 5 | mixed writers/readers；new reader 保留 v0.47 fields |
| 7 | old | new | new | old | substituted | matrix mask 6 | Case 6 镜像；独立 cache 收敛 |
| 8 | old | new | new | new | substituted | matrix mask 7 | 两个 new readers 合并 old/new writers |
| 9 | new | old | old | old | substituted | matrix mask 8 | reversed writer order；old readers 不 crash |
| 10 | new | old | old | new | substituted | matrix mask 9 | reversed mixed order；typed fields 只在 new reader |
| 11 | new | old | new | old | substituted | matrix mask 10 | Case 10 镜像；两个 cache 独立 |
| 12 | new | old | new | new | substituted | matrix mask 11 | reversed writers，两个 new readers 收敛 |
| 13 | new | new | old | old | substituted | matrix mask 12 | 两个新 writers，published reader 忽略 additive keys |
| 14 | new | new | old | new | substituted | matrix mask 13 | one old reader；new reader 保留全部 typed data |
| 15 | new | new | new | old | substituted | matrix mask 14 | Case 14 镜像 |
| 16 | new | new | new | new | substituted | matrix mask 15 | full candidate model，两个 readers 可重复收敛 |

替代证据来自 iOS 26.5 Simulator 的 parameterized test，bit 3/2/1/0 分别表示 Mac A、
Mac B、iPhone A、iPhone B。专用 xcresult：
`Test-CodexBarMobile-2026.08.03_14-29-07--0700.xcresult`，5 tests / 20 runs / 0 failed，
其中 matrix 为 16 dynamic runs。最终 post-review full unit xcresult：
`Test-CodexBarMobile-2026.08.03_14-33-51--0700.xcresult`，617 tests / 639 runs / 0 failed。

每个 mask 都创建两个稳定且不同的 writer device IDs。old writer 走 legacy monolithic
payload；new writer 走生产用 `CloudSyncConstants` ISO8601 codec、逐 provider
`ProviderUsageEnvelope`、zlib `PayloadCompression` 与
`CloudSyncManager.perProviderRecordName`。两台 new phone 各自从 legacy full-fetch fallback
建立独立 `SnapshotCache`，再独立回放 per-provider upsert/delete delta。断言覆盖：legacy
decoder 忽略 additive keys；recordName 与 cache composite inverse 一致且无碰撞；ghost
upsert 被丢弃、retired record delete 后不重现；新 reader 读取四个 provider + z.ai；Notion
workspace、ZoomMate status/history、z.ai daily typed fields；卡片 identity 唯一；百分比与
credits 有限、非负且总量一致；同版本 readers 收敛。代码审计另确认 fleet
`AccountSnapshot` 只由 Mac fleet consumer 读取，不进入 iOS `CloudSyncReader`。

## CloudKit Production audit

最终结论：`DEPLOY_REQUIRED` 已在用户明确授权后完成部署，并通过独立 Production export
回读。

- 既有 Mobile record families/zone 不重命名；
- Shared provider additions仍是 existing compressed JSON payload 内的 optional keys；
- 但 upstream fleet sync 明确新增 `CodexBarSync` zone、`AccountSnapshot`、`Device`、
  `Preferences`、`ProviderIntent` 及其 fields；
- package 与 iOS entitlements 仍必须指向 `iCloud.com.o1xhack.codexbar` / `Production`；
- 最新 published fork tag 为 `v0.45.2.2-mobile.1.19.0`；对该 tag→HEAD 的 schema
  keyword diff 命中新 zone/record 写入，Shared 新字段均是 `decodeIfPresent`；
- `xcrun cktool export-schema ... --environment production` 只读成功，Production 当前
  有 `DeviceSnapshot`、`DeviceProviderSnapshot`、`QuotaTransition`、
  `DeviceLifecycleEvent`、`Users`，没有 4 个 fleet record types，也没有已有 iOS linkage
  writer 所需的 `ProviderAccountLinkage`；
- tracked schema 已改为上述 Production types + 4 个 fleet types +
  `ProviderAccountLinkage` 的完整 union；
  `validate-schema --environment development` 返回 `Schema is valid`；该 endpoint 不支持
  Production validation，Production 以只读 export + diff 为准；
- `bash -n Scripts/cloudkit/deploy_schema.sh` 通过；production dry invocation 在任何
  cktool/import 动作前以 exit 2 拒绝，并要求另行授权后走 CloudKit Console + readback；
- Mac package 和 iOS entitlements 均为 `iCloud.com.o1xhack.codexbar` / `Production`；
- 首次打开 Console 时待部署清单为 0，确认 tracked schema 尚未导入 Development；执行
  `./Scripts/cloudkit/deploy_schema.sh development` 后 validation / import 均成功；
- Console `Deploy Schema Changes` 明确列出新增 `AccountSnapshot`、`Device`、
  `Preferences`、`ProviderAccountLinkage`、`ProviderIntent`，以及 1 个 linkage index、
  3 个 security role updates；确认页返回 `The schema is deployed to Production.`；
- deploy 后运行 Production `cktool export-schema`（team `3TUERHN53E`、container
  `iCloud.com.o1xhack.codexbar`），回读确认上述 5 types 与原有 5 types 共 10 个均存在；
  runtime-created `CodexBarSync` zone 不由 schema export 证明，仍由 production container
  entitlement、zone constant 与 engine tests 覆盖。

## Residual risk

- 16 组合是 deterministic payload/cache/merge substitution，不是 2 台真实 Mac + 2 台
  真实 iPhone；没有覆盖 silent push、foreground/background 时序、真实 iCloud 延迟、
  设备断网重连和物理设备独立持久化；old reader 证据是按 1.19.1 已发布字段冻结的最小
  decoder fixture，不是运行真实 1.19.1 二进制；
- live provider、browser cookie、真实账户 Keychain 读取和真实 CloudKit writes 均按
  no-prompt policy 未运行；provider parser 由 fixtures/stubs/full suites 覆盖；
- App Store 采用 manual release；当前已提交审核但不会在 Apple 审核通过后自动公开，公开
  发布仍需后续单独执行。

## Review closeout

PR #69 merge 后的异步自动 review 新增 1 个 P1：本机消失的 fleet account snapshots 没有
CloudKit deletion lifecycle。该 finding 不按“已 merge”忽略；在独立 review-fix branch 修复、
新增 current-device ownership/empty-set/foreign-device preservation tests，并重新进入
GitHub review → resolve → re-review 循环。

PR #71 第一轮在 commit `4e3784078c` 新增 P1/P2：非权威的空 snapshot publication 可能
误删 last-good data，且恢复的 snapshot 没有取消 pending delete。现已引入
enabled/authoritative provider contract，并在 hash guard 前取消当前 record 的 pending
delete。后续 review 又指出 provider-wide last-token tombstone 会误删同 provider 的 fallback
账号；第五轮已改为持久化 local record ownership 并只 tombstone 明确移除账号的 record，
不新增 wire/schema。第六轮继续纳入 throttle queue，并为旧 persistence 在删除前回填唯一
ownership。随后三条 provenance/ordering review finding 也已通过 actual-success receipt、
fetch-start config revision 与 per-provider publication generation 修复；`6cf207c404` 的
29/29 focused、8356-test full suite 均通过；这只是继续 review 前的 checkpoint。

继续循环后又发现并修复 6 类实际问题：external CloudKit intent/config-file reload 绕过
account-removal reconciliation；fallback/default startup config 误获 destructive authority；
较新 external revision 吞掉尚未处理的本地 dirty delta；350ms debounce 中 stale-but-valid
disk config 误获 authority；overtaken local restoration 的 cancellation 被第二个 plan 丢弃；
以及 tombstone 已清除但 CKSyncEngine 尚未收到 cancellation 时的崩溃/提前返回窗口。最终实现
要求 startup disk/current config encode-identical，只对 token-account 真正变化的 provider
授予删除权；external transition 先保存 overtaken local dirty/cancellation；delete cancellation
作为 local-only 状态先持久化、engine 初始化后立即重放，新的权威删除再覆盖。对应 commits：
`a948cb99e`、`a98cac24f`、`57351687a`、`c2622aafd`。最终 36/36 focused、8363-test
full suite、lint 均通过；`c2622aafd9` exact-SHA Codex review 当时明确无 major issue，所有
thread 已 resolve。后续 CI 基础设施 review 又修复 raw-FD reuse 假失败、malformed discovery
与 syntactically-valid truncation 漏测：`71772e15e`、`50277b4d9`、`29f2da8fb`、
`15a77b70f`。其中最后一个 release code SHA 再次通过 36/36 focused、8363 tests /
812 suites / 0 failure（336.143s），因此 sync compatibility gate 不再引用旧生产代码 SHA。

修复前独立 review 找到 2 个 P1（矩阵没有走真实 wire/cache/delete contract、Production
helper 会调用不适用的 validation endpoint）与 2 个 P2（schema 漏掉
`ProviderAccountLinkage`、ZoomMate history 失败时丢 structured status）。修复、focused
retest、full retest 后交回同一批 reviewer：

- sync architecture final：`P0=0 / P1=0 / P2=0 / blocker=0`；逐项复核 production
  codec/envelope/zlib/recordName/cache/delete/ghost/render invariants、pre-xcrun production
  refusal、linkage schema 与 ZoomMate fallback；
- upstream/release final：确认版本、CHANGELOG、完整 schema union、appcast 未改与安全
  draft 路径；packaging credential 修复后再次 review，最终
  `P0=0 / P1=0 / P2=0 / blocker=0`。真实 2 Mac × 2 iPhone、Production schema deploy 与
  远端 target provenance 仍是 live gate，而不是 draft blocker；candidate ZIP 因此记录
  embedded commit + SHA-256，live 前必须重新确认远端 target 已包含该 commit。

第一次 packaging preflight 在进入签名/公证前失败：Widget Xcode SourcePackages mirror
缺少锁定的 SweetCookieKit `v0.5.1` object；补入精确 tag 后，采样又确认 resolver 停在
`SecItemCopyMatching` 等待 Keychain authorization。两次均在签名、notarization、release
创建之前中止。修复为 Xcode 显式 `-packageAuthorizationProvider netrc`，避免公开 artifact
下载回退到交互式 Keychain；对应 shell/contract test 通过，随后交回 release reviewer。

## Signed candidate / draft release evidence

下列是 Round 7 review fixes 之前的 draft candidate evidence，仅证明当时的打包链路；
不能直接用于 live release。Candidate source commit：
`151a17ae43c3e1be9070d852efca2749e49ca719`；ZIP 内
`CodexGitCommit=151a17ae4`。执行 `Scripts/sign-and-notarize.sh` 的最终结果：

- Developer ID：`Developer ID Application: Yuxiao Wang (3TUERHN53E)`；
- Apple notarization submission：`ad29f441-b170-422c-8cef-a440724156d2`，status
  `Accepted`；staple validate、`syspolicy_check distribution` 与 direct-launch smoke pass；
- app：`CFBundleShortVersionString=0.47.0.1`，
  `CFBundleVersion=111.1.1.20.0`；
- 主程序、`CodexBarCLI`、`CodexBarClaudeWatchdog`、`CodexBarWidget` 均为
  `x86_64 arm64`；
- 主程序 / dSYM UUID 完全一致：x86_64
  `11566CA4-B239-38CF-B3F9-D8395F9F326E`，arm64
  `D9DE5E06-E147-3DC7-8875-23FF85B6E8A3`；
- 签名 entitlement：container `iCloud.com.o1xhack.codexbar`、environment
  `Production`、team `3TUERHN53E`。

| Asset | Bytes | SHA-256 |
|---|---:|---|
| `CodexBar-0.47.0.1-mobile.1.20.0.zip` | 62,218,691 | `6c5568282d518cd7d805378ae26d0bdc8b713a520adc5cb7249d5bc6a4b00d86` |
| `CodexBar-0.47.0.1-mobile.1.20.0.dSYM.zip` | 46,990,922 | `983bf918b9fa142bae38d3d0268b255af0719cc7f80b28fd3be78bd4818cd579` |

GitHub draft readback：

- URL：<https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-fce8f8f3bb37740266ba>；
- release ID `364520043`，title `CodexBar 0.47.0.1 Mobile 1.20.0`，
  `tag_name=v0.47.0.1-mobile.1.20.0`，`isDraft=true`，`prerelease=false`；
- `target_commitish=mobile-dev` 只是未 push 阶段的占位；draft 不发布 Git tag；
- GitHub API 返回的两个 asset `state=uploaded`、size 与 `sha256:` digest 和上表完全一致；
- `git tag -l`、`git ls-remote --tags origin`、目标分支的
  `git ls-remote --heads origin` 均为空；未 push、未 merge、未发布 tag、未改 appcast、
  未 live release。

发布前必须从最终 merged commit 重新签名、公证、生成 appcast 与 ZIP/dSYM，替换上述 draft
assets，并重新核对 embedded commit、digest、entitlements、notarization 与远端 target。

## Final merged release / App Store evidence

- merged source：`98f5e55688cd65edd6e4c8841c1c631e54c16b36`；tag
  `v0.47.0.1-mobile.1.20.0` peel 到该 commit；Final CI
  [31241006284](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/31241006284)
  全绿；
- notarization submission：`d6ce3a05-f19e-4f39-bc44-c1675adc7ab5`，`Accepted`；ZIP 内
  `CodexGitCommit=98f5e5568`，app UUID 为 x86_64
  `DD6D576C-69D8-39C1-A1E5-A362C4A067C3`、arm64
  `21442943-0B73-357C-A2EE-A335C12A5089`，与 dSYM 一致；
- live release：<https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.47.0.1-mobile.1.20.0>，
  published at `2026-08-08T17:06:59Z`；
- final ZIP：62,358,278 bytes，SHA-256
  `614299556551f1e9e72156ba965df1fdea767bbad1f615b0779f05e828a1249d`；final dSYM：
  47,225,725 bytes，SHA-256
  `c73456b7042d3752909b10a206549476f18e1a358115a79ce87e4ddfa054bfd6`；
- appcast commit `958a184e0`；enclosure download、length 与 Sparkle signature 校验通过，
  short version `0.47.0.1`、Sparkle version `111.1.1.20.0`；
- Release CLI run
  [31268623891](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/31268623891)
  6/6 matrix jobs 全绿；GitHub release 最终有 14 个 assets：Mac app ZIP + dSYM，以及
  macOS arm64/x86_64、Linux glibc arm64/x86_64、Linux musl arm64/x86_64 共 6 份 CLI
  tarball 与 6 份 checksum；各 checksum 内容与 GitHub SHA-256 digest 一致；
- 发布后必跑 checker 首次暴露 fork asset prefix / remote pin 不兼容；PR
  [#72](https://github.com/o1xhack/CodexBar-Mobile/pull/72) 修复后，Codex review 继续找到并
  修复 dSYM 误充 app ZIP（P1）与 regex 近似文件名误通过（P2）。最终 exact-basename
  checker、complete / dSYM-only / app-only / similar-name 回归、full lint、Fast Checks 均
  通过；exact-SHA review 无 major issue、unresolved threads `0`，merge commit
  `f70d5fb3c20d91748690a048f645e9b203504219`；
- iOS archive `/tmp/CodexBarMobile-20260807-222242.xcarchive` 的 app 与两个 extensions
  均为 `1.20.0 (192)`、CloudKit Production；ASC version ID
  `f0cada21-9f94-42e3-a34b-bfd744e9d4f3`，build ID
  `715a8ec4-8ede-4621-a8d2-1ddd90f48e09`，build `VALID`；
- 四语言 metadata / release notes 与 screenshots inheritance 已回读；review submission
  `a3a56d2c-5a9c-411f-8e9d-ac5b72cffb99` 含 1 个 version item，于
  `2026-08-08T17:07:40.9Z` 提交，submission 与 version 均回读为
  `WAITING_FOR_REVIEW`。
