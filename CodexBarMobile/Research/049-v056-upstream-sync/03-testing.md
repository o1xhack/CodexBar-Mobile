# v0.56.0 / iOS 1.23.0 测试与发布证据

Status: `ready`
Date: 2026-08-28

## 兼容基线

| Role | Old | New candidate |
|---|---|---|
| Mac | `0.54.0.1 (127.1.1.22.0)` | `0.56.0.1 (131.1.1.23.0)` |
| iPhone | `1.22.0 (195)` | `1.23.0 (196)` |
| upstream | `v0.54.0` | `v0.56.0` |
| Mobile payload | `providerPayloadVersion=1` | 保持 `1`，现有 opaque optional JSON |
| Production schema | last published release baseline | final diff / readback pending |

## 总 gate

| Gate | Result | Evidence / notes |
|---|---|---|
| upstream provenance + second parent | pending | target `fc1bd0d797` |
| fork README / CI / release policy | pending | policy scripts |
| Mac Release build + lint | pending | commands below |
| Mac focused tests | pending | sync/cost/provider/CLI |
| Mac full tests | pending | `swift test --no-parallel` |
| iOS xcodegen + Release build | pending | 4 targets `1.23.0 (196)` |
| iOS focused/full tests | pending | wire/cache/widget/localization |
| CloudKit Production audit | pending | expected `NO_DEPLOY` |
| 16-case compatibility gate | pending | rows below |
| local/agent review blocker count | pending | exact-head evidence |
| signed/notarized draft | pending | ZIP/dSYM + draft URL |
| no push/merge/live/TestFlight/deploy boundary | pending | remote/readback proof |

## 计划命令

```bash
bash Scripts/check_ci_policy.sh
bash Scripts/check_fork_readme.sh
bash Scripts/lint.sh lint
swift build -c release
swift test --no-parallel

cd CodexBarMobile
xcodegen generate
xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Release build
xcodebuild -project CodexBarMobile.xcodeproj -scheme CodexBarMobile \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

live provider probes、browser cookie imports、真实 Keychain reads不在默认回归中执行；使用 parser fixtures、
stub stores与 `KeychainNoUIQuery` seam。

## CloudKit audit

- baseline tag：`v0.54.0.1-mobile.1.22.0`；
- 检查 schema keywords、`CloudConstants.swift`、`UsageSnapshot.swift`、zones/subscriptions/indexes、
  `providerPayloadVersion`；
- Claude slot migration复用现有 `AccountSnapshot`；Mobile payload仍为既有
  `DeviceProviderSnapshot.payload` opaque Data；
- Production schema使用 `cktool export-schema` 只读回看；若最终发现任何新 record type/field/index/
  zone/subscription，则结论升级为 `DEPLOY_REQUIRED` 并停在单独授权门。

最终 verdict：pending。

## Compatibility evidence keys

| Key | Scope | Result |
|---|---|---|
| S1 | old/new wire fixtures + Mac producer | pending |
| S2 | iOS merge/cache/widget readers | pending |
| S3 | signed simulator build/tests | pending |
| S4 | fleet/Mobile lifecycle、privacy、schema code audit | pending |
| S5 | Production schema readback | pending |

## 2 Mac x 2 iPhone old/new matrix

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | pending | pending | baseline |
| 2 | old | old | old | new | pending | pending | new reader / old writers |
| 3 | old | old | new | old | pending | pending | independent reader caches |
| 4 | old | old | new | new | pending | pending | old writers / new readers |
| 5 | old | new | old | old | pending | pending | mixed writers / old readers |
| 6 | old | new | old | new | pending | pending | mixed fleet |
| 7 | old | new | new | old | pending | pending | mixed fleet |
| 8 | old | new | new | new | pending | pending | slot migration + new readers |
| 9 | new | old | old | old | pending | pending | writer identity reversal |
| 10 | new | old | old | new | pending | pending | mixed fleet |
| 11 | new | old | new | old | pending | pending | mixed fleet |
| 12 | new | old | new | new | pending | pending | slot migration + new readers |
| 13 | new | new | old | old | pending | pending | new writers / old readers |
| 14 | new | new | old | new | pending | pending | independent reader caches |
| 15 | new | new | new | old | pending | pending | independent reader caches |
| 16 | new | new | new | new | pending | pending | all-new convergence |

若 2 Mac + 2 iPhone 实机不可用，所有组合必须逐行标为 `substituted`，并引用 S1-S5 中的
unit fixtures、mock CloudKit records、simulator runs与 code audit；不得把替代验证写成真实设备 `pass`。

## 必查行为

- replacement save成功前绝不删除 Claude email-key predecessor；
- old/new Mac并存不造成永久 duplicate、误删或 ghost reappearance；
- old/new iOS均能 decode dynamic fourth window、generic details与 optional cost fields；
- estimated/unpriced/unknown不会显示为确定 `$0`；
- 两台 iPhone merge/fallback/cache后可收敛到同一可见 provider state；
- provider/account/device identity不重复、不串账号；
- silent push/background delivery与真实 Production propagation若未实测，明确记录残余风险。
