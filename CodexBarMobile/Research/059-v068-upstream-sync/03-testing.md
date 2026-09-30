# 测试、CloudKit 与 16 组合兼容证据

Status: `in-progress`
Date: 2026-09-29

## 环境与目标版本

- 分支：`upstream-sync/v0.68.0-mobile.2.3.0`，base `origin/mobile-dev` `91501264c1607f603240376208a094f94c8000ba`。
- Old Mac：`v0.66.0.1`。用户于 2026-09-29 确认 iOS `2.2.0 (222)` 已发布；此状态未独立从 App Store Connect 验证。New candidate：Mac `0.68.0.1 (159.1)` / iOS `2.3.0 (223)`。
- 2026-09-29 在唯一实体 Mac 与 iPhone 17 Simulator 上复跑 iOS 全量测试；没有使用实体双 Mac/iPhone fleet 或 CloudKit Production 账号。新结果 bundle：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-r5-full.xcresult`。

## 最终验证结果

- Mac Release：合并前已有 `swift build -c release --scratch-path /Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929/mac-arm64 --triple arm64-apple-macosx14.0` 与 `.../mac-x86_64 --triple x86_64-apple-macosx14.0` 通过；耗时 327.25 秒与 328.67 秒。日志分别为 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-mac-release-arm64.log`、`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-mac-release-x86_64.log`。Swift 6.2 SDK 报 9 处 Swift warning，集中在 CloudKit save 返回值、既有/上游 `var` 与 `unsafeBitCast`、CString 和 macOS API 弃用；vendored QuickJS C 文件另有编译告警；两架构均无 build error。最终签名/公证打包会在精确 review 通过后从本轮候选再次构建。
- Mac 完整测试：最终修复后运行 `swift test --no-parallel`，5 个 SwiftPM test run 合计 13,412 tests / 1,371 suites，全通过（12,617 + 282 + 435 + 74 + 4），零失败；日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-mac-full-tests-final-r18.log`。没有执行 live provider、browser-cookie import、`codexbar usage` 真实账号探测或 CloudKit Production 操作；凭证相关回归用测试 fixture/override 和 prompt-safety guards。此前一次跑测因 token-account fanout 误用通用 test seam 卡在 Copilot fixture；改成独立 token-account seam 后，完整跑测及 `CopilotStackedAllowanceTests` 都通过。
- Mac lint：最新源代码 `bash Scripts/lint.sh lint` 通过，2,724 个文件 0 个 SwiftLint violation；portable checks、CLI/release/CI/README guards 都通过，iOS catalog 362 个 source keys 全部存在且四种语言均 translated；parser-version audit 通过，日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-mac-lint-review-findings.log`。
- iOS 全量测试：最新候选源代码在 iPhone 17 / iOS 26.5 Simulator 串行运行通过，866 passed、6 skipped、0 failed（872 total；16 UI tests 中 6 skipped、0 failed）；`xcresulttool get test-results summary` 的 result 为 `Passed`。结果包 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-r21-ios265-full-review-fixes.xcresult`，日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-ios-full-r21-review-fixes.log`。首轮全量测试曾有 4 个 locale-sensitive 英文断言在中文 Simulator locale 下失败；已改为读取本地化文案/语义数字后通过。较早 iOS 27 widget pixel run 遇到 IOSurface image provider timeout，iOS 26.5 上同一渲染矩阵通过，因此最终采用 26.5 结果。
- iOS 定向复测：最终 review 修复后，`WidgetSnapshotBuilderTests` 与 `CWLEquivalenceTests` 共 43 tests、0 failures；覆盖 all/MTD 不能冒充 30-day widget total，以及完成的 wider scan 对 7-day sparse active rows 推导零日。结果包 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-r20-review-findings.xcresult`，日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-ios-focused-r20-review-findings.log`。此前 Cost share、quota warning parser、ShareCard render 等 68 tests 全通过（r17），以及 16-mask、iOS 2.2 frozen projection、旧版安全 JSON 编码、All/MTD local model round-trip 的 110 tests（r11）；候选 build 为 `2.3.0 (223)`。
- iOS Release Simulator build：最新 review 修复后的候选源代码于 2026-09-29 通过；日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-ios-release-build-r22-review-fixes.log`（`** BUILD SUCCEEDED **`）。
- CloudKit：从 `v0.66.0.1-mobile.2.1.0` 的 schema 到最终代码逐项对照 `docs/cloudkit-deploy-audit.md`；无新增 record type、query/sort field、index、subscription predicate 或 schema field。结论 `NO_DEPLOY`；未读取或写入 Production。
- 版本：`version.env` 为 Mac `0.68.0.1` / build `159.1`、Mobile `2.3.0`、upstream `v0.68.0` / `2026-09-27`；Sparkle `159.1.2.3.0`；候选 tag/zip basename `v0.68.0.1-mobile.2.3.0`。已更新 Mac/iOS changelog、4-language in-app release notes、project build metadata，并生成 changelog HTML；Mac draft/live release 等 PR review gate 和合并到 `mobile-dev` 后执行，用户已授权。

## 2 Mac × 2 iPhone × old/new 16 组合

结果必须每格为 `pass`、`fail` 或 `substituted`。真实 Production 双 Mac、双 iPhone 若不可得，依规范标注 `substituted` 并列证据路径与剩余风险。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 0 | Synthetic v0.66 writer DTO + legacy reader projection; no physical fleet or live CloudKit. |
| 2 | old | old | old | new | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 1 | Same fixture matrix; iPhone B uses current reader path. |
| 3 | old | old | new | old | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 2 | Same fixture matrix; iPhone A uses current reader path. |
| 4 | old | old | new | new | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 3 | Both iPhone readers use current reader path. |
| 5 | old | new | old | old | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 4 | Mac B uses v0.68 fixture writer; both iPhones use legacy projection. |
| 6 | old | new | old | new | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 5 | Mac B uses v0.68 fixture writer; iPhone B uses current reader path. |
| 7 | old | new | new | old | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 6 | Mac B uses v0.68 fixture writer; iPhone A uses current reader path. |
| 8 | old | new | new | new | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 7 | Mac B and both iPhones use v0.68/current fixture paths. |
| 9 | new | old | old | old | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 8 | Mac A uses v0.68 fixture writer; both iPhones use legacy projection. |
| 10 | new | old | old | new | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 9 | Mac A uses v0.68 fixture writer; iPhone B uses current reader path. |
| 11 | new | old | new | old | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 10 | Mac A uses v0.68 fixture writer; iPhone A uses current reader path. |
| 12 | new | old | new | new | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 11 | Mac A uses v0.68 fixture writer; both iPhones use current reader path. |
| 13 | new | new | old | old | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 12 | Both Macs use v0.68 fixture writers; both iPhones use legacy projection. |
| 14 | new | new | old | new | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 13 | Both Macs use v0.68 fixture writers; iPhone B uses current reader path. |
| 15 | new | new | new | old | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 14 | Both Macs use v0.68 fixture writers; iPhone A uses current reader path. |
| 16 | new | new | new | new | substituted | `UpstreamSync068Review20260929-ios-focused-r11.log`, mask 15 | All four devices use v0.68/current fixture paths. |

Parameterized case `CloudKitMergeTests.v0.66 and v0.68 reporting periods survive the 2 Mac x 2 iPhone matrix` passed all 16 masks in the latest full iOS run `UpstreamSync068Review20260929-r21-ios265-full-review-fixes.xcresult`; focused source matrix evidence is in `UpstreamSync068Review20260929-r11-focused.xcresult`. Bit mapping: Mac A = bit 3, Mac B = bit 2, iPhone A = bit 1, iPhone B = bit 0. It serializes current snapshots, supplies synthetic v0.66 writer values, projects old readers through `LegacyMatrixSnapshot`, then checks merge, rendering and cost-window results. It does not run old app binaries, independent device caches, CloudKit subscriptions/APNs or Production records. These are substituted results, not a physical 16-combination pass.

### Quota warning notification compatibility

Review found that the first v0.68 record-name layout put named-window identity tokens after the hour bucket. The iOS 2.2 notification service reads the final `window-t<threshold>-<hourBucket>` components, so that layout could fall back to an empty window and `0%`. The Mac writer now emits `providerID[-w<hash>[-l<label>]]-window-t<threshold>-<hourBucket>` through `QuotaZoneNotificationParser.warningRecordName`; current readers still accept records already written with the earlier post-hour suffix. This adds no CloudKit field or schema requirement.

`QuotaZoneNotificationParserTests` passed 20 tests (`ios-parser-compat-final.log`, result bundle `ios-parser-compat-final.xcresult`). The named-window case feeds the Mac writer's shared record-name formatter into a test copy of the v0.66/iOS 2.2 suffix parser and verifies the old reader still obtains the window and threshold; that old NSE path uses those values and the `providerName` record field. The invariant covers the 9 matrix masks where at least one new Mac and at least one old iPhone are present: 4, 5, 6, 8, 9, 10, 12, 13, and 14. This remains source-level compatibility evidence; no old binary, APNs delivery or Production record was exercised.

## Final verdict

Review on head `8e0d478` found two P2 issues: the iOS widget could label All/MTD as 30-day spend, and sparse zero-cost days could make a covered shorter CWL window appear unknown. Both are fixed locally with regression coverage. The focused 43-test run, full iOS suite (866 passed / 6 skipped), Release Simulator build and lint all pass on the fixes; those code changes and their evidence need a new exact-head review and resolved-thread gate. All 16 matrix cells have evidence-backed `substituted` results. Physical device convergence, real v0.66/v0.68 binary interoperability, CloudKit Production and APNs delivery remain unverified. Mac signed/notarized draft, live release, issue #150/#151 closure, Final CI and Todoist closeout remain in progress; record their evidence here before marking this Research item `done`.
