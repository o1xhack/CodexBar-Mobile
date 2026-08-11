# v0.49.2 Upstream Sync 测试与发布证据

Status: `planned`
Date: 2026-08-11

## Gate applicability

本轮改变 Mac fleet sync、provider identity、synced snapshot generic details、Mobile bridge、
provider display/cache 与 cross-version rendering，因此
`docs/ios-sync-compatibility-testing.md` 的 2 Mac × 2 iPhone、16-case gate 全部适用。

## 验证清单

| Gate | Command / evidence | Result |
|---|---|---|
| Branch isolation | `git status --short --branch` / merge-base | pending |
| Upstream provenance | annotated tag object/peel/ancestry/merge parent | pending |
| Fork CI policy | `bash Scripts/check_ci_policy.sh` | pending |
| Mac build | `swift build` | pending |
| Lint/i18n/parser/release checks | `bash Scripts/lint.sh lint` | pending |
| Mac full tests | `swift test --no-parallel` | pending |
| Multi-account/device | `swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'` | pending |
| Provider plugins/resources | focused engine/golden/resource/package launch tests | pending |
| SQLite/PTY/reliability | focused cost store / PTY / actor isolation tests | pending |
| Shared v0.49 bridge | wire/old-new/generic details/Fireworks/IBM Bob tests | pending |
| Widget data parity | `CodexBarMobileTests/WidgetSnapshotBuilderTests` | pending |
| iOS full unit | `xcodebuild ... -only-testing:CodexBarMobileTests test` | pending |
| iOS Release build | generic iOS Simulator Release build, no signing | pending |
| CloudKit Production audit | published tag→HEAD grep + tracked schema/export | pending |
| 16-case compatibility | parameterized production codec/cache/merge tests | pending |
| Signing/notarization | Developer ID + Accepted + staple + Gatekeeper | pending |
| Draft release | API readback, two asset size/digest, no tag/no push | pending |
| Review | self diff + independent agents, blockers 0 | pending |

## 2 Mac × 2 iPhone compatibility matrix

`old` = published Mac `0.47.0.1` / iOS `1.20.0` contract；`new` = candidate
Mac `0.49.2.1` / iOS `1.21.0`。真实硬件不可用时结果只能记为 `substituted`，不能写成
physical-device pass。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | pending | mask 0 | all-old control |
| 2 | old | old | old | new | pending | mask 1 | new reader / two legacy writers |
| 3 | old | old | new | old | pending | mask 2 | Case 2 mirror |
| 4 | old | old | new | new | pending | mask 3 | two independent new caches |
| 5 | old | new | old | old | pending | mask 4 | old readers ignore additive details |
| 6 | old | new | old | new | pending | mask 5 | mixed writer/reader |
| 7 | old | new | new | old | pending | mask 6 | Case 6 mirror |
| 8 | old | new | new | new | pending | mask 7 | new readers converge |
| 9 | new | old | old | old | pending | mask 8 | reversed writer order |
| 10 | new | old | old | new | pending | mask 9 | typed/generic details only on new reader |
| 11 | new | old | new | old | pending | mask 10 | Case 10 mirror |
| 12 | new | old | new | new | pending | mask 11 | reversed writers, new readers converge |
| 13 | new | new | old | old | pending | mask 12 | published readers ignore new keys |
| 14 | new | new | old | new | pending | mask 13 | one old reader, one new reader |
| 15 | new | new | new | old | pending | mask 14 | Case 14 mirror |
| 16 | new | new | new | new | pending | mask 15 | full candidate |

每个 case 必须验证：两台 Mac 使用不同 device IDs；old/new payload 同时存在不破坏 records；
old iOS 不 crash；new iOS 能读 old typed payload 与 new generic details；同 provider/account
跨 Mac 去重但 distinct accounts 不合并；两个 iPhone 独立 cache 最终收敛；delete/ghost/stale
record 不复活；fleet records 不进入 Mobile reducer；未知 plugin instance 不泄露 secret、
不重复 first-party card。

## CloudKit Production audit

计划按 `docs/cloudkit-deploy-audit.md` 执行：

1. 找最新 published fork tag；
2. tag→HEAD grep `recordType` / zone / index / subscriptions / payload version；
3. diff `Shared/iCloud/CloudConstants.swift`；
4. 审计 `Shared/Models/UsageSnapshot.swift` 新字段是否全部 optional `decodeIfPresent`；
5. 只读 export Production schema，核对上轮已部署 types；
6. 记录 `NO_DEPLOY` 或 `DEPLOY_REQUIRED`。后者必须停在用户授权门。

## Draft release contract

- 不运行会 push tag 的 `Scripts/release.sh` phase 1；
- 运行 `Scripts/sign-and-notarize.sh` 生成候选 ZIP/dSYM；
- 独立验证 codesign/notary/staple/Gatekeeper、Production entitlement、universal slices、
  app/dSYM UUID、bundle/composite versions、ZIP SHA-256；
- 通过 `gh release create --draft --target mobile-dev` 创建未发布 draft并上传两资产；
- API 回读 `isDraft=true`、tag name、asset size/digest；
- 确认本地/远端 candidate tag 不存在、目标分支未 push、`appcast.xml` 未改；
- final merge/publish 前必须从最终 merged commit 重新打包并替换 draft assets。

## Residual risk

待执行后填写。若 16-case 使用 simulator/fixture substitution，至少保留：silent push、真实
CloudKit propagation、foreground/background timing、断网重连、两个物理设备独立持久化、
published iOS binary 真实 decoder 仍未实测。live provider/Keychain/browser cookie 测试不会
在未获明确授权时运行。
