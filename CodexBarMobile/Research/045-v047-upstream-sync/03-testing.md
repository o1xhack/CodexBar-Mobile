# v0.47.0 Upstream Sync 测试证据

Status: `in-progress`
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
| Shared/four-provider wire | `SyncCoordinatorV047MapperTests`、`V047MobileEnvelopeCompatibilityTests`、mock/provider contracts | pass；5 + 2 focused tests；含 ZoomMate history 失败仍保留 structured status |
| Alibaba regression | `AlibabaTokenPlanPersonalTests` | pass；4 tests |
| iOS unit gate | `xcodebuild ... -only-testing:CodexBarMobileTests test -quiet` | pass；post-review rerun 617 tests / 639 runs / 0 failed；xcresult `14-33-51` |
| Widget data parity | `... -only-testing:CodexBarMobileTests/WidgetSnapshotBuilderTests test` | pass；11 tests；xcresult `14-15-41` |
| iOS Release build | `xcodebuild ... -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build -quiet` | pass |
| 16-case compatibility | parameterized `V047SyncCompatTests/fourDeviceCompatibilityMatrix(mask:)` | substituted pass；production codec/cache/delete/render invariants，16 dynamic runs，见 matrix |
| CloudKit audit | published `v0.45.2.2-mobile.1.19.0` → HEAD + Production export | `DEPLOY_REQUIRED`；只读 audit，未 import/deploy |
| Package credential policy | `bash -n Scripts/package_app.sh` + `test_package_signing.sh` | pass；Widget Xcode resolver 强制 `netrc`，不回退交互式 Keychain lookup |
| Signing/notarization | universal candidate app/ZIP/dSYM + draft | pending；代码 review 后执行 |
| Review | self diff + 两个独立 agent final review | pass；sync P0/P1/P2=0，release P0/P1=0，draft blocker=0 |

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

最终结论：`DEPLOY_REQUIRED`，尚未执行 Production deploy。

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
- 未执行 `import-schema`、Development schema mutation 或 Dashboard deploy；仅执行过上述
  production refusal path。Production deploy 与 deploy 后 readback 仍是 live release 前的
  独立授权门。

## Residual risk

- 16 组合是 deterministic payload/cache/merge substitution，不是 2 台真实 Mac + 2 台
  真实 iPhone；没有覆盖 silent push、foreground/background 时序、真实 iCloud 延迟、
  设备断网重连和物理设备独立持久化；old reader 证据是按 1.19.1 已发布字段冻结的最小
  decoder fixture，不是运行真实 1.19.1 二进制；
- CloudKit Production schema deploy 未授权且未执行；deploy/readback 前不能把 default-off
  fleet sync 宣称为 Production 可用，也不得发布 live release；
- live provider、browser cookie、真实账户 Keychain 读取和真实 CloudKit writes 均按
  no-prompt policy 未运行；provider parser 由 fixtures/stubs/full suites 覆盖；
- iOS Archive/TestFlight、真实 SpringBoard widget、live Mac release、appcast publish、
  merge、push 和 published tag 都不在本 Goal 当前授权内。

## Review closeout

修复前独立 review 找到 2 个 P1（矩阵没有走真实 wire/cache/delete contract、Production
helper 会调用不适用的 validation endpoint）与 2 个 P2（schema 漏掉
`ProviderAccountLinkage`、ZoomMate history 失败时丢 structured status）。修复、focused
retest、full retest 后交回同一批 reviewer：

- sync architecture final：`P0=0 / P1=0 / P2=0 / blocker=0`；逐项复核 production
  codec/envelope/zlib/recordName/cache/delete/ghost/render invariants、pre-xcrun production
  refusal、linkage schema 与 ZoomMate fallback；
- upstream/release final：`P0=0 / P1=0 / draft blocker=0`；确认版本、CHANGELOG、完整
  schema union、appcast 未改与安全 draft 路径。保留 3 个只影响 live 的 P2：真实 2 Mac ×
  2 iPhone 尚未执行、Production schema 未 deploy、draft 的 `target=mobile-dev` 在未 push/
  merge 前只是占位；因此 candidate ZIP 必须记录 embedded commit + SHA-256，live 前重新
  确认远端 target 已包含该 commit。

第一次 packaging preflight 在进入签名/公证前失败：Widget Xcode SourcePackages mirror
缺少锁定的 SweetCookieKit `v0.5.1` object；补入精确 tag 后，采样又确认 resolver 停在
`SecItemCopyMatching` 等待 Keychain authorization。两次均在签名、notarization、release
创建之前中止。修复为 Xcode 显式 `-packageAuthorizationProvider netrc`，避免公开 artifact
下载回退到交互式 Keychain；对应 shell/contract test 通过，随后交回 release reviewer。
