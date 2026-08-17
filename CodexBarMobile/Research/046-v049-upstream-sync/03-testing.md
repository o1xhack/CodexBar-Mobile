# v0.49.2 Upstream Sync 测试与发布证据

Status: `done`
Date: 2026-08-11

## Gate applicability

本轮改变 Mac fleet sync、provider identity、synced snapshot generic details、Mobile bridge、
provider display/cache 与 cross-version rendering，因此
`docs/ios-sync-compatibility-testing.md` 的 2 Mac × 2 iPhone、16-case gate 全部适用。

## 验证清单

| Gate | Command / evidence | Result |
|---|---|---|
| Branch isolation | branch `upstream-sync/v0.49.2-mobile.1.21.0`; base `d874facd8`; no origin branch | PASS |
| Upstream provenance | tag object `9d4d693b…`; peel/merge parent `330ae438…`; merge `a75be5a4b` | PASS |
| Fork CI policy | final `Scripts/lint.sh lint` includes `check_ci_policy.sh` | PASS |
| Mac build | `swift build` | PASS |
| Lint/i18n/parser/release checks | `/tmp/codexbar-lint-p2-final.log`; 1897 files, 0 violations, all 302 iOS source keys present/translated, parser audit/hash current | PASS |
| Mac full tests | `/tmp/codexbar-swift-test-37d46edec.log`; 8796 tests / 851 suites / 496.079s | PASS |
| Multi-account/device | full suite: account identity, snapshot ownership/reconciliation and device merge tests | PASS |
| Provider plugins/resources | focused provider catch-up: 113 tests / 6 suites; full plugin/golden/resource suite | PASS |
| SQLite/PTY/reliability | final full suite includes cost store/cache, PTY and actor-isolation regressions | PASS |
| Shared v0.49 bridge | compatibility/details/ghost/clear/plugin/Fireworks/IBM Bob focused + full tests | PASS |
| Widget data parity | iOS full `Widget snapshot builder`, 11 cases | PASS |
| iOS full unit | `/tmp/CodexBarMobile-v049-37d46edec.xcresult`; xcresult `totalTestCount=632`, failed/skipped=0（console 594 tests / 44 suites） | PASS |
| iOS Release build | `/tmp/codexbar-ios-release-build-37d46edec.log`; generic iOS Simulator Release | PASS |
| CloudKit Production audit | tag→HEAD code audit + `/tmp/codexbar-production-schema-v049.ckdb` export | `NO_DEPLOY` |
| 16-case compatibility | `V049SyncCompatTests`, production codec/cache/merge fixtures | 16/16 SUBSTITUTED PASS |
| Signing/notarization | Developer ID `3TUERHN53E`; notary `da356aff…` Accepted; staple/distribution/direct launch pass | PASS |
| Draft release | draft `368897158`; two uploaded assets size/digest match; no tag/no push | PASS |
| Review | self diff + 3 independent agents + fixes/retest；本轮授权范围 P0/P1/P2/blocker 0 | PASS |
| Merge/CI closeout | PR #89/#90；runs `32051325391`, `32051437233`, `32054938333`, `32055053940` | PASS |
| Mac live release | tag `v0.49.2.1-mobile.1.21.0`; release/appcast readback; runs `32056443141`, `32056443142` | PASS |
| iOS archive/upload | `/tmp/CodexBarMobile-20260817-114708.xcarchive`; `EXPORT SUCCEEDED` | PASS |
| ASC processing | build `5f20e3c0-96cf-416e-ba21-8213151cdda2`; iOS `1.21.0 (193)` | `VALID` |
| iOS App icon | source 1024, archive 120, ASC CDN 152；三层尺寸与视觉 readback | PASS |

## 2 Mac × 2 iPhone compatibility matrix

`old` = published Mac `0.47.0.1` / iOS `1.20.0` contract；`new` = candidate
Mac `0.49.2.1` / iOS `1.21.0`。真实硬件不可用时结果只能记为 `substituted`，不能写成
physical-device pass。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted PASS | mask 0 | all-old control |
| 2 | old | old | old | new | substituted PASS | mask 1 | new reader / two legacy writers |
| 3 | old | old | new | old | substituted PASS | mask 2 | Case 2 mirror |
| 4 | old | old | new | new | substituted PASS | mask 3 | two independent new caches |
| 5 | old | new | old | old | substituted PASS | mask 4 | old readers ignore additive details |
| 6 | old | new | old | new | substituted PASS | mask 5 | mixed writer/reader |
| 7 | old | new | new | old | substituted PASS | mask 6 | Case 6 mirror |
| 8 | old | new | new | new | substituted PASS | mask 7 | new readers converge |
| 9 | new | old | old | old | substituted PASS | mask 8 | reversed writer order |
| 10 | new | old | old | new | substituted PASS | mask 9 | typed/generic details only on new reader |
| 11 | new | old | new | old | substituted PASS | mask 10 | Case 10 mirror |
| 12 | new | old | new | new | substituted PASS | mask 11 | reversed writers, new readers converge |
| 13 | new | new | old | old | substituted PASS | mask 12 | published readers ignore new keys |
| 14 | new | new | old | new | substituted PASS | mask 13 | one old reader, one new reader |
| 15 | new | new | new | old | substituted PASS | mask 14 | Case 14 mirror |
| 16 | new | new | new | new | substituted PASS | mask 15 | full candidate |

上述 16 case 由 `V049SyncCompatTests` 对 masks 0–15 参数化执行，使用两个
distinct Mac writer IDs、两个独立 reader cache、old contract fixture 与 new production codec。
每个 reader 都断言 exact provider/card identity keys；Mac B 的较新 timestamp 必须胜出，
Codex `usedPercent` 随 Mac B old/new 为 `25/30`，source device 必须为 `matrix-mac-b`。
同时单独验证：pre-v0.49 defaults、synthetic placeholder filtering、details-only plugin 不被
ghost filter 删除、同 timestamp 以 device ID 确定性合并、old empty details 不擦除 new writer、
new explicit empty 可权威清除旧 details。这里的 old iPhone 是 contract/decoder fixture，
不是在真实 published 1.20.0 binary 上运行，故所有结果严格标为 substituted。

## CloudKit Production audit

最终 verdict：`NO_DEPLOY`，没有执行 Production deploy。

1. published fork tag `v0.47.0.1-mobile.1.20.0` 到 candidate 的
   `Shared/iCloud/CloudConstants.swift` 无 schema 常量变化；
2. 没有新增 CKRecord type、field、zone、index、query predicate、schema version 或
   `providerPayloadVersion`；
3. 新 `details`、plugin branding、`usageKnown`、placeholder metadata 均位于现有
   `DeviceProviderSnapshot.payload` opaque Codable blob，使用 optional/default decode；
4. Mac package 与 iOS app entitlement 都明确为 CloudKit `Production`；
5. `xcrun cktool export-schema --team-id 3TUERHN53E --container-id
   iCloud.com.o1xhack.codexbar --environment production` 只读导出成功，文件 5829 bytes；
6. Production 仍为 10 个既有 types：`AccountSnapshot`、`Device`、
   `DeviceLifecycleEvent`、`DeviceProviderSnapshot`、`DeviceSnapshot`、`Preferences`、
   `ProviderAccountLinkage`、`ProviderIntent`、`QuotaTransition`、`Users`。

IBM Bob 通过既有 per-provider runtime 创建 quota zone/subscription；Fireworks 为 spend-only，
不创建 quota subscription。两者都不引入 CloudKit schema type/field/index/version。

## Draft release contract

- 未运行会 push tag 的 `Scripts/release.sh` phase 1；
- 已运行 `Scripts/sign-and-notarize.sh` 生成候选 ZIP/dSYM；
- 独立验证 codesign/notary/staple/Gatekeeper、Production entitlement、universal slices、
  app/dSYM UUID、bundle/composite versions、ZIP SHA-256；
- 已通过 `gh release create --draft --target mobile-dev` 创建未发布 draft并上传两资产；
- API 回读 `draft=true`、`published_at=null`、tag name、asset size/digest；
- 已确认本地/远端 candidate tag 不存在、目标分支未 push、`appcast.xml` 未改；
- final merge/publish 前必须从最终 merged commit 重新打包并替换 draft assets。

Draft URL：
[`untagged-d5c3a3e0664b621f548b`](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-d5c3a3e0664b621f548b)。

| Asset | Bytes | SHA-256 / GitHub digest |
|---|---:|---|
| `CodexBar-0.49.2.1-mobile.1.21.0.zip` | 67,721,716 | `31662c86f8249a8ed124332c549252b84a0a1ae5d52d4e53a77234e114f23c24` |
| `CodexBar-0.49.2.1-mobile.1.21.0.dSYM.zip` | 52,743,104 | `8636f0390db23fc140a349e79a705b5a0ad3ee3638ed1d88c4c6bb00120cda63` |

ZIP 解压复核：Mac short/build version `0.49.2.1 / 116.1.1.21.0`，CloudKit Production，
Developer ID authority/team 正确；app、CLI、widget 都含 `x86_64 arm64`；app/dSYM 两组 UUID
`A4292182…` / `527B7EE6…` 一致；无 AppleDouble entries。

## Live release 与 TestFlight closeout（2026-08-17）

用户在初始 Goal 后另行明确授权 live Mac release 与 iOS TestFlight upload。最终发布没有复用
上面的 pre-merge draft artifact，而是从 merged `mobile-dev` commit `a88b71b27` 重新构建。

| Item | Evidence | Result |
|---|---|---|
| Mac version/tag | `0.49.2.1`; Sparkle `116.1.1.21.0`; tag peel `a88b71b27` | PASS |
| Notarization | submission `fe3ad18e-2178-46dd-ab27-4d89a8e867a5` `Accepted`; ZIP ticket validates | PASS |
| Live app asset | 67,721,761 bytes; SHA-256 `a5b9cddf151f87f0c209e9d15a008ad8a51504be1c716aa1c384b124aa30efd0` | PASS |
| Live dSYM asset | 52,743,103 bytes; SHA-256 `e8795a4af3e8acc88aef112a48b37e7aaf4c58c5f1d0dde08c7fe2d5b987eb07` | PASS |
| Release | <https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.49.2.1-mobile.1.21.0>; published `2026-08-17T18:44:38Z` | LIVE |
| Appcast | commit `f6772526b`; remote top entry/signature/length/URL match live asset | PASS |
| Remote release QA | Mac Release Verify `32056443141`: Gatekeeper, stapler, 5-second launch | PASS |
| CLI release assets | Release CLI `32056443142`; 6 jobs + tarball/checksum readback; 14 total assets | PASS |
| iOS archive | main + two extensions `1.21.0 (193)`; CloudKit Production; compiled icon readable | PASS |
| ASC/TestFlight | build `5f20e3c0-96cf-416e-ba21-8213151cdda2`; uploaded `2026-08-17T11:51:01-07:00`; `VALID` | PASS |

ASC build attributes：minimum OS `17.0`、`expired=false`、
`usesNonExemptEncryption=false`、`iconAssetToken` present；prerelease version
`e685d3b3-440d-4425-8cc0-4a6772ab39a6` 为 iOS `1.21.0`。本次仅上传到
App Store Connect/TestFlight，没有提交 App Store review 或公开 App Store release。

## Residual risk

本轮没有 2 台真实 Mac + 2 台真实 iPhone，因此以下风险不冒充已验证：真实 CloudKit
propagation/silent push、foreground/background/cold-launch timing、断网重连、两个物理
iPhone 独立持久化，以及 published iOS 1.20.0 binary 对新 payload 的真实行为。old contract
fixture、production codec、cache/reducer 与 16 masks 已覆盖确定性兼容逻辑，但不能替代上述
系统级链路。live provider/Keychain/browser cookie 测试也未获授权、未运行。

既存 `.mac-release.env` 仍指向 upstream repo/Peter signing manifest。本轮 direct fork
`Scripts/release.sh` / `Scripts/sign-and-notarize.sh` 不读取它，且未运行
`Scripts/mac-release`；实际 live ZIP 的 signer、feed、public key 与 fork bundle readback 均正确。
未来若启用 `Scripts/mac-release` wrapper，应先增加 fork guard 或修正 manifest。该前置条件
不改变本轮 `P0/P1/P2/blocker=0` 的 review 结论。
