# 测试、CloudKit 与 16 组合兼容证据

Status: `in-progress`
Date: 2026-09-28

## 环境与目标版本

- 分支：`upstream-sync/v0.68.0-mobile.2.3.0`，base `origin/mobile-dev` `91501264c1607f603240376208a094f94c8000ba`。
- Old Mac / iOS：已发布 Mac `v0.66.0.1`；现有 iOS 2.2.0 (222) 已送 App Review。New candidate：Mac `0.68.0.1 (159.1)` / iOS `2.3.0 (223)`。
- Mac 与 iOS build/test 于 2026-09-28 执行；证据日志在 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/20260928-upstream-sync/`。没有使用实体 Mac/iPhone fleet 或 CloudKit Production 账号。

## 最终验证结果

- Mac Release：`swift build -c release --scratch-path .../mac-arm64 --triple arm64-apple-macosx14.0` 与 `.../mac-x86_64 --triple x86_64-apple-macosx14.0` 均通过，日志 `mac-build-arm64-final.log`、`mac-build-x86_64-final.log`。Swift 6.2 SDK 有 5 项上游/既有非阻塞 warning：`CursorLocalCSVReader` 的未变 `var`、Claude JSON 的两项 `unsafeBitCast` 建议、`CLIIO` 的 CString 解码 deprecation、macOS 14 的 `CGWindowListCreateImage` deprecation；无 build error。
- Mac 完整测试：`swift test --scratch-path .../mac-tests-review --no-parallel` 通过 13,412 tests / 1,371 suites，日志 `mac-tests-final-resolved.log`。没有执行 live provider、browser-cookie import、`codexbar usage` 真实账号探测或 CloudKit Production 操作；凭证相关回归用测试 fixture/override 和 prompt-safety guards。此前一次跑测因 token-account fanout 误用通用 test seam 卡在 Copilot fixture；改成独立 token-account seam 后，完整跑测及 `CopilotStackedAllowanceTests` 都通过。
- Mac lint：`bash Scripts/lint.sh lint` 通过，2,724 个文件 0 个 SwiftLint violation；脚本内 portable checks、CLI/release/CI/README guards 都通过，iOS catalog 362 个 source keys 全部存在且四种语言均 translated；parser-version audit 通过，日志 `mac-lint-final-pass.log`。
- iOS：`xcodegen generate` 后 Release Simulator build 成功，日志 `ios-release-build-final.log`。6 个定向 suites 共 151 tests 通过（含 16-mask CloudKit merge case），日志 `ios-focused-final-resolved.log`；quota warning parser 20 tests 通过，日志 `ios-parser-compat-final.log`。候选 build 为 `2.3.0 (223)`。
- CloudKit：从 `v0.66.0.1-mobile.2.1.0` 的 schema 到最终代码逐项对照 `docs/cloudkit-deploy-audit.md`；无新增 record type、query/sort field、index、subscription predicate 或 schema field。结论 `NO_DEPLOY`；未读取或写入 Production。
- 版本：`version.env` 为 Mac `0.68.0.1` / build `159.1`、Mobile `2.3.0`、upstream `v0.68.0` / `2026-09-27`；Sparkle `159.1.2.3.0`；候选 tag/zip basename `v0.68.0.1-mobile.2.3.0`。已更新 Mac/iOS changelog、4-language in-app release notes、project build metadata，并生成 changelog HTML；tagless GitHub draft 尚无链接，等待 release credential authorization。

## 2 Mac × 2 iPhone × old/new 16 组合

结果必须每格为 `pass`、`fail` 或 `substituted`。真实 Production 双 Mac、双 iPhone 若不可得，依规范标注 `substituted` 并列证据路径与剩余风险。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | `ios-focused-final-resolved.log`, mask 0 | Synthetic v0.66 writer DTO + legacy reader projection; no physical fleet or live CloudKit. |
| 2 | old | old | old | new | substituted | `ios-focused-final-resolved.log`, mask 1 | Same fixture matrix; iPhone B uses current reader path. |
| 3 | old | old | new | old | substituted | `ios-focused-final-resolved.log`, mask 2 | Same fixture matrix; iPhone A uses current reader path. |
| 4 | old | old | new | new | substituted | `ios-focused-final-resolved.log`, mask 3 | Both iPhone readers use current reader path. |
| 5 | old | new | old | old | substituted | `ios-focused-final-resolved.log`, mask 4 | Mac B uses v0.68 fixture writer; both iPhones use legacy projection. |
| 6 | old | new | old | new | substituted | `ios-focused-final-resolved.log`, mask 5 | Mac B uses v0.68 fixture writer; iPhone B uses current reader path. |
| 7 | old | new | new | old | substituted | `ios-focused-final-resolved.log`, mask 6 | Mac B uses v0.68 fixture writer; iPhone A uses current reader path. |
| 8 | old | new | new | new | substituted | `ios-focused-final-resolved.log`, mask 7 | Mac B and both iPhones use v0.68/current fixture paths. |
| 9 | new | old | old | old | substituted | `ios-focused-final-resolved.log`, mask 8 | Mac A uses v0.68 fixture writer; both iPhones use legacy projection. |
| 10 | new | old | old | new | substituted | `ios-focused-final-resolved.log`, mask 9 | Mac A uses v0.68 fixture writer; iPhone B uses current reader path. |
| 11 | new | old | new | old | substituted | `ios-focused-final-resolved.log`, mask 10 | Mac A uses v0.68 fixture writer; iPhone A uses current reader path. |
| 12 | new | old | new | new | substituted | `ios-focused-final-resolved.log`, mask 11 | Mac A uses v0.68 fixture writer; both iPhones use current reader path. |
| 13 | new | new | old | old | substituted | `ios-focused-final-resolved.log`, mask 12 | Both Macs use v0.68 fixture writers; both iPhones use legacy projection. |
| 14 | new | new | old | new | substituted | `ios-focused-final-resolved.log`, mask 13 | Both Macs use v0.68 fixture writers; iPhone B uses current reader path. |
| 15 | new | new | new | old | substituted | `ios-focused-final-resolved.log`, mask 14 | Both Macs use v0.68 fixture writers; iPhone A uses current reader path. |
| 16 | new | new | new | new | substituted | `ios-focused-final-resolved.log`, mask 15 | All four devices use v0.68/current fixture paths. |

Parameterized case `CloudKitMergeTests.v0.66 and v0.68 reporting periods survive the 2 Mac x 2 iPhone matrix` passed all 16 masks (current log `ios-focused-final-resolved.log`; result bundle `ios-focused-final-resolved.xcresult`). Bit mapping: Mac A = bit 3, Mac B = bit 2, iPhone A = bit 1, iPhone B = bit 0. It serializes current snapshots, supplies synthetic v0.66 writer values, projects old readers through `LegacyMatrixSnapshot`, then checks merge, rendering and cost-window results. It does not run old app binaries, independent device caches, CloudKit subscriptions/APNs or Production records. These are substituted results, not a physical 16-combination pass.

### Quota warning notification compatibility

Review found that the first v0.68 record-name layout put named-window identity tokens after the hour bucket. The iOS 2.2 notification service reads the final `window-t<threshold>-<hourBucket>` components, so that layout could fall back to an empty window and `0%`. The Mac writer now emits `providerID[-w<hash>[-l<label>]]-window-t<threshold>-<hourBucket>` through `QuotaZoneNotificationParser.warningRecordName`; current readers still accept records already written with the earlier post-hour suffix. This adds no CloudKit field or schema requirement.

`QuotaZoneNotificationParserTests` passed 20 tests (`ios-parser-compat-final.log`, result bundle `ios-parser-compat-final.xcresult`). The named-window case feeds the Mac writer's shared record-name formatter into a test copy of the v0.66/iOS 2.2 suffix parser and verifies the old reader still obtains the window and threshold; that old NSE path uses those values and the `providerName` record field. The invariant covers the 9 matrix masks where at least one new Mac and at least one old iPhone are present: 4, 5, 6, 8, 9, 10, 12, 13, and 14. This remains source-level compatibility evidence; no old binary, APNs delivery or Production record was exercised.

## Final verdict

All local Mac/iOS build, full Mac test, focused iOS test, lint, localization, schema audit and independent review gates pass. All 16 cells have evidence-backed substituted results. The source-level payload/merge/render matrix passes; physical device convergence, real v0.66/v0.68 binary interoperability, CloudKit Production and APNs delivery remain unverified. Do not describe those real-device behaviors as passed. Mac tagless draft packaging/upload is the only remaining task and awaits explicit authorization to use Developer ID/notarization, Sparkle and GitHub release credentials; no live release, pushed tag, TestFlight upload, CloudKit deploy, PR merge or push was performed.
