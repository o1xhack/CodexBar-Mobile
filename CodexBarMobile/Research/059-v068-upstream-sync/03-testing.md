# 测试、CloudKit 与 16 组合兼容证据

Status: `in-progress`
Date: 2026-09-29

## 环境与目标版本

- 分支：`upstream-sync/v0.68.0-mobile.2.3.0`，base `origin/mobile-dev` `91501264c1607f603240376208a094f94c8000ba`。
- Old Mac：`v0.66.0.1`。用户于 2026-09-29 确认 iOS `2.2.0 (222)` 已发布；此状态未独立从 App Store Connect 验证。New candidate：Mac `0.68.0.1 (159.1)` / iOS `2.3.0 (223)`。
- 2026-09-29 在唯一实体 Mac 与 iPhone 17 Simulator 上复跑 iOS 全量测试；没有使用实体双 Mac/iPhone fleet 或 CloudKit Production 账号。新结果 bundle：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-r5-full.xcresult`。

## 历史阶段验证（当前候选证据见末尾）

- Mac Release：合并前已有 `swift build -c release --scratch-path /Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929/mac-arm64 --triple arm64-apple-macosx14.0` 与 `.../mac-x86_64 --triple x86_64-apple-macosx14.0` 通过；耗时 327.25 秒与 328.67 秒。日志分别为 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-mac-release-arm64.log`、`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-mac-release-x86_64.log`。Swift 6.2 SDK 报 9 处 Swift warning，集中在 CloudKit save 返回值、既有/上游 `var` 与 `unsafeBitCast`、CString 和 macOS API 弃用；vendored QuickJS C 文件另有编译告警；两架构均无 build error。签名/公证打包从同步分支候选再次构建；tag、merge 与 live release 必须等精确 head 的 review gate 通过。隔离工作区在 `ade035e52` 上的 arm64 Release 预构建已通过（390.85 秒；`.../UpstreamSync068Review20260929-r27-release-arm64.log`），后续 Shared/发布脚本修复需在签名流水线中重新构建。
- Mac 完整测试：最终修复后运行 `swift test --no-parallel`，5 个 SwiftPM test run 合计 13,412 tests / 1,371 suites，全通过（12,617 + 282 + 435 + 74 + 4），零失败；日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-mac-full-tests-final-r18.log`。没有执行 live provider、browser-cookie import、`codexbar usage` 真实账号探测或 CloudKit Production 操作；凭证相关回归用测试 fixture/override 和 prompt-safety guards。此前一次跑测因 token-account fanout 误用通用 test seam 卡在 Copilot fixture；改成独立 token-account seam 后，完整跑测及 `CopilotStackedAllowanceTests` 都通过。
- Mac lint：最新源代码 `bash Scripts/lint.sh lint` 通过，2,724 个文件 0 个 SwiftLint violation；portable checks、CLI/release/CI/README guards 都通过，iOS catalog 362 个 source keys 全部存在且四种语言均 translated；parser-version audit 通过，日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-r57-mistral-lint.log`。
- iOS 全量测试：MTD 修复后的候选源代码（warning title 之后另有 r28 定向复测）在 iPhone 17 / iOS 26.5 Simulator 串行运行通过，867 passed、6 skipped、0 failed（873 total；16 UI tests 中 6 skipped、0 failed）；`xcresulttool get test-results summary` 的 result 为 `Passed`。结果包 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-r25-ios-full-mtd-calendar.xcresult`，日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-r25-ios-full-mtd-calendar.log`。首轮全量测试曾有 4 个 locale-sensitive 英文断言在中文 Simulator locale 下失败；已改为读取本地化文案/语义数字后通过。较早 iOS 27 widget pixel run 遇到 IOSurface image provider timeout，iOS 26.5 上同一渲染矩阵通过，因此最终采用 26.5 结果。
- iOS 定向复测：最终 review 修复后，`WidgetSnapshotBuilderTests` 与 `CWLEquivalenceTests` 共 43 tests、0 failures；覆盖 all/MTD 不能冒充 30-day widget total，以及完成的 wider scan 对 7-day sparse active rows 推导零日。结果包 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-r20-review-findings.xcresult`，日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-ios-focused-r20-review-findings.log`。此前 Cost share、quota warning parser、ShareCard render 等 68 tests 全通过（r17），以及 16-mask、iOS 2.2 frozen projection、旧版安全 JSON 编码、All/MTD local model round-trip 的 110 tests（r11）；候选 build 为 `2.3.0 (223)`。
- iOS Release Simulator build：最新 review 修复后的候选源代码于 2026-09-29 通过；日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-r49-ios-release-aixy.log`（`** BUILD SUCCEEDED **`）。
- CloudKit：从 `v0.66.0.1-mobile.2.1.0` 的 schema 到最终代码逐项对照 `docs/cloudkit-deploy-audit.md`；无新增 record type、query/sort field、index、subscription predicate 或 schema field。结论 `NO_DEPLOY`；未读取或写入 Production。
- 版本：`version.env` 为 Mac `0.68.0.1` / build `159.1`、Mobile `2.3.0`、upstream `v0.68.0` / `2026-09-27`；Sparkle `159.1.2.3.0`；候选 tag/zip basename `v0.68.0.1-mobile.2.3.0`。已更新 Mac/iOS changelog、4-language in-app release notes、project build metadata，并生成 changelog HTML；Mac tagless draft 在本分支生成；live release 等 PR review gate 和合并到 `mobile-dev` 后执行，用户已授权。

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

Parameterized case `CloudKitMergeTests.v0.66 and v0.68 reporting periods survive the 2 Mac x 2 iPhone matrix` passed all 16 masks in the latest full iOS run `UpstreamSync068Review20260929-r25-ios-full-mtd-calendar.xcresult`; focused source matrix evidence is in `UpstreamSync068Review20260929-r11-focused.xcresult`. Bit mapping: Mac A = bit 3, Mac B = bit 2, iPhone A = bit 1, iPhone B = bit 0. It serializes current snapshots, supplies synthetic v0.66 writer values, projects old readers through `LegacyMatrixSnapshot`, then checks merge, rendering and cost-window results. It does not run old app binaries, independent device caches, CloudKit subscriptions/APNs or Production records. These are substituted results, not a physical 16-combination pass.

### Quota warning notification compatibility

Review found that the first v0.68 record-name layout put named-window identity tokens after the hour bucket. The iOS 2.2 notification service reads the final `window-t<threshold>-<hourBucket>` components, so that layout could fall back to an empty window and `0%`. The Mac writer now emits `providerID[-w<hash>[-l<label>]]-window-t<threshold>-<hourBucket>` through `QuotaZoneNotificationParser.warningRecordName`; current readers still accept records already written with the earlier post-hour suffix. This adds no CloudKit field or schema requirement.

`QuotaZoneNotificationParserTests` passed 20 tests (`ios-parser-compat-final.log`, result bundle `ios-parser-compat-final.xcresult`). The named-window case feeds the Mac writer's shared record-name formatter into a test copy of the v0.66/iOS 2.2 suffix parser and verifies the old reader still obtains the window and threshold; that old NSE path uses those values and the `providerName` record field. The invariant covers the 9 matrix masks where at least one new Mac and at least one old iPhone are present: 4, 5, 6, 8, 9, 10, 12, 13, and 14. This remains source-level compatibility evidence; no old binary, APNs delivery or Production record was exercised.

## 历史阶段结论（不代表当前发布 gate）

Review on head `8e0d478` found two P2 issues: the iOS widget could label All/MTD as 30-day spend, and sparse zero-cost days could make a covered shorter CWL window appear unknown. These are fixed with regression coverage. Round 5 on `f9224f0` found a further P2: the share-card MTD boundary used the reader calendar's day-of-month. The revised implementation uses producer `reportingPeriodHistoryDays`, or the Gregorian producer source day key when the count is absent. Both payload cases pass under an Islamic reader calendar. The required pre-sixth design audit is recorded at https://github.com/o1xhack/CodexBar-Mobile/pull/155#issuecomment-5901675948.

Round 6 on `ade035e52` found a P2 in warning notification titles: an ambiguous push retained the arbitrarily selected record's account. The shared parser now returns an account only when every contemporaneous (or unknown-time) candidate agrees after whitespace normalization; otherwise the title stays provider-only. Same-account warnings preserve their account label, historical records outside the ambiguity interval do not interfere, and missing/blank/conflicting accounts suppress it. The focused current-source run passes 114 tests across `QuotaZoneNotificationParserTests` and `CloudKitMergeTests`, including all 16 masks; result `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/UpstreamSync068Review20260929-r28-quota-account-compat.xcresult`, log `.../UpstreamSync068Review20260929-r28-quota-account-compat.log`. No wire or CloudKit schema changes are introduced by this pure title-resolution helper.

The last full iOS run before the warning-title fix passes 867 tests with 6 skips and zero failures, including the 16 matrix masks; Release Simulator build and lint also pass. The earlier r23 focused run passed all 46 CostShareService tests. The r24 full run was interrupted and has no completion result; it is not counted as passing evidence. The revised head still requires a clean Codex review and resolved-thread gate. All 16 matrix cells remain evidence-backed `substituted` results. Physical device convergence, real v0.66/v0.68 binary interoperability, CloudKit Production and APNs delivery remain unverified. Mac signed/notarized draft, live release, issue #150/#151 closure, Final CI and Todoist closeout remain in progress; record their evidence here before marking this Research item `done`.

## 发布启动检查隔离审计

预检发现仅设置 `CFFIXED_USER_HOME` 并不能证明系统偏好 daemon 已被隔离，因此不能把隔离目录当作用户状态隔离的证据。`verify_packaged_app_launch.sh` 现在显式禁用 production Keychain access，并在沙箱中禁止用户目录读取/写入、偏好 daemon 与 CloudKit daemon 的 mach lookup 和网络访问；仍执行真实 AppKit startup 和资源探测，不替换成只加载资源的较窄启动模式。`sign-and-notarize.sh` 的公证后检查复用这条隔离路径，并强制 2 秒存活；无 Aqua 时也不能用 inconclusive early exit 放行。

`test_packaged_app_launch.py` 用无害子进程验证环境/沙箱隔离、清理及无 Aqua 时提前退出必须失败；回归通过。实际 `sandbox-exec` 已验证新增 profile 的语法。发布 artifact 输入清单包含该 launch verifier，避免签名后流程变更被 provenance 检查忽略。新发布运行的 TMPDIR/staging/evidence 全部指定到 BuildScratch。实际签名包的 AppKit/AMFI 启动结果将在 draft 生成后补充。

## 第七轮 review 复测

Round 7 (`8759c12e3`) 发现 NSE 先 `compactMap` 掉无 `transitionAt` 的记录，使账户一致性 helper 未被调用。现在 ambiguity gate 保留 `[Date?]`，未知时间的记录与账户 helper 一样视作可能触发来源；多个全无时间的记录也使用 generic body，单一记录仍保留既有详情。混合时间戳、全无时间戳、空列表和单一记录的回归已补齐。r34 定向 iOS run 的 parser/merge 114 tests 通过（`.../UpstreamSync068Review20260929-r34-quota-undated.xcresult`）；r35 完整 lint 与 r36 Release Simulator build 用于最终候选验证。r32 draft 预检被 Xcode Python 3.9 缺少 waitid 阻止，改用已安装的 Homebrew Python 3.14；r33 进入 arm64 构建后因新 review Shared 修复停止，不计作最终 artifact，下一次从修复后的同步分支重打。

## 第八轮 review 复测

Round 8 (`9dcfda9fb`) 发现 Overview 仅比较 reportingPeriod 字符串，会在 UTC/local 月份错位时把两个月的 MTD 总额相加。多 summary 的 MTD 现在要求 producer source day key（缺少时使用 sourceUpdatedAt）和有效 bucket time zone 计算的 Gregorian 月起点一致；边界未知或不一致即显示已有四语 `Mixed cost windows`，不发布合并的 cost/token/provider totals。单一 summary 和 CWL 已重窗路径维持原本语义。同月 UTC/GMT 别名、跨月份、同月不同时区起点、缺失/非法 metadata 的回归已补齐。r38 首次测试因新 fixture initializer 参数顺序编译失败，修正后 r40 的 CWL、merge、CostTabInsightsResolver 三套共 130 tests 通过（`.../UpstreamSync068Review20260929-r40-mtd-overview.xcresult`）；r39 完整 lint、r41 Release Simulator build 验证最终 iOS 候选。该修复不改变 Mac artifact inputs，Mac r37 draft 流程可继续使用 `9dcfda9fb`，finalize 会核对 artifact 输入一致性。

## 第九轮 review 与月份边界规则集中

Round 9 (`a52e29bd4`) 指出多 Mac local-cost merge 会先把不同月份但同 ordinal day 的 MTD 合成一个 summary。已将 producer 月份边界检查集中到 `ProviderSnapshotMerger.monthToDateWindowsAreComparable`，Overview 和 device merge 共用该纯方法；缺失或不同边界使 `historyWindowIsComparable=false`，后续 UI/分享沿用 incomplete 语义。回归覆盖 August 15/September 15、同月同日与未知边界。审计其余 consumer：Widget 固定 30-day 字段只接受 rolling totals；CWL 重新按 reader window 聚合；share 按 producer coverage 判断选定日期，不能把不同 source 月份的 summary 当作完整合计。r43 四套（CWL、merge、resolver、WidgetSnapshotBuilder）156 tests 全通过；r44 完整 lint、r45 Release Simulator build 验证最终候选。

r42 最新全量 iOS 测试在上述 device-merge 修复前通过：869 passed、6 skipped、0 failed，xcresult summary 为 `Passed`（`.../UpstreamSync068Review20260929-r42-ios-full.xcresult`）；后续差异由 r43 的 156 项定向回归覆盖。

## 第十轮 review：Aixy 四语预算标签

Round 10 (`0d0191580`) 发现 Aixy composite budget 的 Monitor 虽在 catalog 中有四语，semantic allowlist 却缺少它。对上游完整 label vocabulary 审计同时找到 Monthly 缺口；两项均已加入。回归遍历 scope × period × shared/personal × hard/monitor 共 80 种组合 × en/zh-Hans/zh-Hant/ja 四语，以 catalog 翻译逐段验证，而非只测示例 Hard label。r47 presentation suite 9 tests 全通过（`.../UpstreamSync068Review20260929-r47-aixy-localization.xcresult`），r48 lint / r49 Release Simulator build 验证最终源。

Mac r37 已完成通用 app/widget 编译，但 package guard 正确阻止缺少本地 gitignored Provisioning profile 的 worktree。复制主仓库现有 profile 后，r46 继续完整 pipeline；未跳过 AMFI/profile 检查，r37 不作为发布 artifact 证据。

## 第十一轮 review：Mistral 生产端统计范围

Round 11 (`140345e2c`) 发现 Mistral 默认 30-day projection 在 31 日会漏掉 day 1，却被无条件标 MTD。现在按 UTC producer day 取至少 30、最多当前 month day 的窗口，31 日覆盖完整月；只有 `historyLabel == This month` 的 validated projection 且投影月份与 provider fetch 月份一致才输出 MTD。没有完整月份证据的稀疏/ended-range projection 保留 nil period 的 legacy history 语义。

扩大测试发现既有 `sourceUpdatedAt/sourceDayKey` 表示 provider fetch freshness；首次尝试改为 observation end 违反既有断言，已恢复原契约，并将 coverage 资格与 freshness 分离：ended range 不能声称覆盖 fetch day 的零日。新测试覆盖 31 日全月、稀疏无范围、ended range、次月 fetch republish；原 source-freshness 回归保持通过。r50 新用例单独通过；r51 首次 lint 有 8 个新 fixture 参数换行问题、已修正；r52 大套因上述 freshness 契约有 2 断言失败、已修复；r56 Mac 最终定向 161 + 6 = 167 tests / 26 suites 全通过，r57 完整 lint/i18n/parser guards 通过。日志 `.../UpstreamSync068Review20260929-r56-mistral-sync.log`、`.../UpstreamSync068Review20260929-r57-mistral-lint.log`。没有执行真实 provider/Keychain/CloudKit 访问。

Mac r46 因此次 Mac 发布输入修复主动停止，未产出 draft；后续签名、公证包必须从修复后的精确候选重新构建。CloudKit 仍为 NO_DEPLOY，没有新 wire/schema 字段，已记录的 16-mask 兼容替代验证继续适用。

## 第十二轮 review：原币种不能进入 USD 统计

Round 12 (`f4199f79f`) 指出 Mistral EUR API cost 会被 iOS 美元总额使用。修复将 currency acceptance 集中到 ProviderSnapshotMerger；blob/CWL/old ledger model mix/share/widget 均过滤显式非 USD，provider details 保留原币种；多 Mac 同账户若币种不同，保留无金额的 unavailable envelope。Mac 对原币种 rolling history 使用既有 modern period envelope；Shared encoder 对 old-reader 隐藏 legacy historical USD fields，Mistral Today/session 保持 nil。四语统计范围提示与同一 2.3.0 notes block 已更新。无新增 schema，结论仍 NO_DEPLOY。

- r60 正确隔离环境的 Mac 全量测试通过：12,618 + 282 + 435 + 74 + 4 = 13,413 tests / 1,371 suites，0 failures；日志 `.../UpstreamSync068Review20260929-r60-mac-full.log`。该完整 run 在 round 12 Shared/Mac 改动前构建；新增 wire 修复再跑定向测试。此前 r58 将 release smoke 的显式禁用 Keychain 环境误用于策略单元测试，17 个环境语义断言失败；不计通过。r60 保留 SWIFT_TESTING / CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS，使真实 SecItem 访问仍 fail closed，移除显式 disable 和文件隔离覆盖。
- r71 iOS 四套定向：185 passed、0 failed、0 skipped（xcresult summary Passed），覆盖 CWL、分享、Widget、merge/current-native/frozen-old reader，包含全部 16 masks。结果 `.../UpstreamSync068Review20260929-r71-currency.xcresult`；日志 `.../UpstreamSync068Review20260929-r71-currency.log`。
- r74 完整 lint、portable guards、四语审计与 parser audit 通过：2,724 Swift 文件 0 violations；363 source keys 全部存在且 translated（`.../UpstreamSync068Review20260929-r74-currency-lint.log`）。
- r73 Mac SyncCoordinator 定向测试通过：38 tests / 2 suites，覆盖 native EUR publication、MTD/freshness 与旧 session 契约（`.../UpstreamSync068Review20260929-r73-currency-mac.log`）。
- r72 Release Simulator build 通过（`.../UpstreamSync068Review20260929-r72-ios-release-currency.log`）。
- 未计通过的初次尝试：r61 optional snapshot compile、r62 SharePeriod enum fixture typo、r65 in-memory SwiftData 默认 CloudKit 配置、r68 缺少 nil initializer 参数，均已修复并由 r71 复测。r70/r69 被会话中断，进程已不存在且日志无 terminal pass；不重用为成功证据，改由 r73/r74 重跑。

所有金额 fixture 均为合成数据；没有真实 provider/Keychain/Production CloudKit 操作。旧 Mac 的已存在 legacy EUR payload 不能由新 Mac retroactively 改写，本轮仅证明新 writer 不产生误标的 Mistral legacy history，以及新 reader 不把显式非 USD 计入美元总额；16 组合仍为 substituted，不是实体设备 pass。

## 第十三轮 review：将原币种兼容保护集中到 Shared serializer

Round 13 (`a5c30c84f`) 指出 plugin rolling cost 的独立 mapper 没有 modern history envelope。已补齐 plugin 映射，并将保障集中在 SyncCostSummary.encode：显式非 USD 即使 producer 未填 modern envelope，也自动保留 modern 历史并隐藏 legacy historical USD fields。附加审计发现原币种 session fallback 同样可能被旧 reader 当 USD；新增 optional opaque JSON `nativeCurrencySession`，保存原始 session amount/known status，新 reader 恢复，旧 reader 获得 nil USD amount / false known status。USD 与缺省币种旧契约保持原状。该改动不新增 CKRecord field/type/index/query/subscription，仍 NO_DEPLOY；新增的是 payload 内的 optional JSON key，需要 source-level old/new 兼容 gate。

- r76 在该 serializer 改动前的最终 a5c30c84f iOS 全量通过：873 passed、6 skipped、0 failed（879 total）；`.../UpstreamSync068Review20260929-r76-ios-full-currency.xcresult`。
- r81 serializer 变更后四套定向通过：186 passed、0 failed、0 skipped；新增 USD/EUR/CNY × nil/true/false session-known 9 组合和 writer 未填 envelope 的 frozen legacy/current round-trip；原 16 old/new masks、CWL、share、Widget 同时覆盖。`.../UpstreamSync068Review20260929-r81-native-envelope.xcresult`。
- r77 完整 Mac test run 在 a5c30c84f（round 13 serializer fix 前）通过：12,619 + 282 + 435 + 74 + 4 = 13,414 tests / 1,371 suites，0 failures；日志 `.../UpstreamSync068Review20260929-r77-mac-full-currency.log`。r79 从最终 Shared/plugin 源代码重建并定向覆盖 mapper/SyncCoordinator：66 tests / 3 suites 全通过，包含 USD/EUR/CNY plugin rolling history 与新旧编码断言（`.../UpstreamSync068Review20260929-r79-plugin-currency.log`）。
- r84 完整 lint/portable guards/四语/parser audit 通过，2,724 files 0 violations、363 source keys；`.../UpstreamSync068Review20260929-r84-native-lint.log`。初次单文件手工 lint 将 repo canonical exclusion 外的旧 iOS fixtures 也纳入产生无关告警，新 Shared 参数换行已修正，最终采用 canonical lint。
- r83 Release Simulator build 通过（`.../UpstreamSync068Review20260929-r83-native-ios-release.log`）。
- r75 a5c30c84f Mac arm64 Release 预构建通过，125.65 秒；r78 draft 在 lint 阶段收到新 Shared/Mac finding 后停止，未创建 artifact/release。不存在的进程已核实；下一次从修复后 head 重打。

追加 architecture audit 已在 PR 记录，根因是每个 producer 自行维护 consumer compatibility；Shared serializer 现在强制保护 native history/session 边界。所有新 wire 值仍为 synthetic fixture，本轮没有 Production/APNs/实体双 Mac/iPhone 证据。#154 收到用户新回复：要求独立账户卡片；两个账户的三个 Personal/Business plans 目前仅显示两个。该 issue 保持 open，未把上游同步当成该问题已修复。

## 第十四轮 review：保留未定型 USD Mistral 历史

Round 14 (`97231d6b7`) 发现 Mistral USD 的 sparse/missing/ended range 在 MTD 校验失败后仍无条件创建 modern envelope；nil reportingPeriod 被 Shared encoder 视为非 rolling，导致 old reader 丢失历史。现已把 validated period 与 envelope 资格绑定：明确 MTD 或非 USD 才需要 modern envelope；未定型 USD 保留 legacy historical fields 及原 coverage/freshness metadata，不将不确定窗口冒充 rolling/MTD。回归扩大到实际 serialized wire 和 frozen legacy reader，检查 complete month、missing range、ended range、next-month cached republish。原 native currency 保护不受影响。

r85 在 97231d6b7 的 iOS 全量通过：874 passed、6 skipped、0 failed（880 total），结果 `.../UpstreamSync068Review20260929-r85-ios-full-native.xcresult`。此次后续修复只涉及 Mac mapper 与 Mac 测试，iOS/Shared 输入不变。r86 draft 在 arm64 构建阶段收到 Mac finding 后停止；没有签名 artifacts、draft、tag 或 live release。修复后候选通过 clean review 再重启签名流水线，避免反复构建已被 review 阻止的 Mac inputs。

第十四轮复测：r90 Mistral + mapper + SyncCoordinator 共 182 + 6 = 188 tests / 26 suites 全通过；r89 完整 lint/i18n/parser audit 通过。r87 最新 Shared serializer 后的完整 Mac run 有 1 个既有 EUR round-trip 断言失败：V030SnapshotsCodableTests 仍读取 legacy last30DaysRequests，而非现代 reportingPeriodRequests。已按新的兼容契约验证现代 requests/cost/tokens/session 不丢失、legacy historical requests 不泄漏；r91 整套 V030 7 tests 通过，r92 新断言文件 lint 通过。r87 其余四个 run（282 + 435 + 74 + 4）通过，但完整 run 不计全绿，最终候选需再跑完整验证。证据 `.../UpstreamSync068Review20260929-r90-mistral-legacy.log`、`.../UpstreamSync068Review20260929-r89-mistral-wire-lint.log`、`.../UpstreamSync068Review20260929-r91-native-v030.log`、`.../UpstreamSync068Review20260929-r92-v030-lint.log`。

## Final CI 编译器兼容修复（PR #155 合并后）

PR #155 已于 2026-09-30T03:33:36Z 合并，merge commit `54aaddff5c6f494a6efa468050dfe6c9d02bfb41`；round 15 在 `067bf3aca` clean、所有 threads resolved。最终本机 Mac 全量 r93 为 13,414 tests / 1,371 suites、0 failures；iOS r85 为 874 passed / 6 skipped / 0 failed。

Final CI run `36664952941` 未复用上游检查（上游 checks 未全部成功），按保守策略执行完整矩阵。Mac Xcode 26.3/26.2 与 Linux musl Swift 6.2.1 编译失败：provider `.init(red: 226 / 255, ...)` 在旧编译器中推断整数除法后不能传给 `Double`，本机 Swift 6.4 没有暴露该差异。修复只把隐式 color initializer 的 RGB denominator 写成 `255.0`，保留原 RGB；新增所有受影响 provider 与 widget RGB 的回归断言。发布 r94 进程已停止，不作为最终 artifact 证据；需新 head review、Final CI 和重打包完成后发布。

修复本机验证：`swift test --filter ProviderAccentColorTests` 14 tests / 1 suite passed，完整 targets 编译通过；changed-file SwiftLint、SwiftFormat lint 与 `git diff --check` 通过。日志 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-ci-color-fix-test.log`。较旧 Swift 的完整编译以修复合并后的 Final CI 为准。

第二个 Final CI run `36666013312` 的较旧 Mac compiler 已通过 provider color 编译，随后在上游 `TestsLinux/CostUsageQuotaWeekLinuxTests.swift` 的两条 `#expect` 报 type-check timeout（245、288 行）。将两个 optional cost 求和先绑定显式 `Double` 变量再比较，保留 expected 6 与原测试语义。此变更只涉及测试/文档，不改变 `Scripts/release.sh` ARTIFACT_INPUTS；r96 包可按输入相同的 provenance 规则继续使用。PR #156 merge commit `c42f504af219d292f921e8ac78ca5f9ca12df87c`，clean review https://github.com/o1xhack/CodexBar-Mobile/pull/156#issuecomment-5903641539。

完整核对第二轮 Final CI 日志发现 Linux x64 另有一项 fixture failure：`OpenRouter optional key timeout is an observable degradation`（QuickJS / delaysTaskStart=false）抛出 credits request timed out。该测试把 credits 和 key 都设为 1 秒预算；满负载下 credits 也超时，失去“credits 成功、key 超时”的目标前提。调整测试预算为 5 秒，key transport / before-attempt delay 为 7.5 秒，仍验证实际超时、task admission 延迟与完整降级详情，不改 production budget，不删/弱化断言。此测试变化不影响 artifact inputs。此前独立的 quota expression 修复 `a0d537f88019fd9c9f15fbafc7c2a01ee3d84f06` 由 PR #157 clean-reviewed 并合并到 `5fdd4670410f0ef062722d89fd692a4677f12b5f`；该 merge 不包含本段 OpenRouter timeout fixture 修复。本段修复由 PR #158 的 `3e3bc0f49f6fe3ffb86f2bdfbea0a77bc8db4104` 引入，目前等待自身的 clean review 和 merge，不能复用 PR #157 的 review。manual full run `36667161490` 只验证 timeout 修复前的 `5fdd46704`；timeout 修复合并后仍须跑包含该修复的当前 head full gate。

超时 fixture 最终定向验证：`ProviderPluginDetailsParityTests` 17 tests passed，目标用例覆盖 QuickJS / JavaScriptCore × queued/unqueued 四组合，全部仍检查真实 key 超时与完整降级 details。fixture overall runtime budget 60 秒，独立于 5 秒 request deadline，防止更长 admission 模型碰到 unrelated outer deadline；production default 不变。日志 `upstream-ci-openrouter-timeout-fix-final.log`，elapsed 20.932 秒；lint 与 diff check 通过。

## 当前发布候选闸门（2026-09-30 UTC，未完成）

- Runtime/artifact source `45c2828ba3df0df223d39fd02cd184d10bc6922b` 已由 PR #156 clean-reviewed 并合并。r95 相同 runtime inputs 的 Mac full 13,415 tests / 1,371 suites、0 failures；quota expression delta 单独 28 tests passed；OpenRouter timeout delta 单独 17 tests passed、四参数组合 passed。iOS/Shared inputs 最后全量 r85 为 874 passed / 6 skipped / 0 failed；之后 delta 仅 Mac colors 与测试/文档，没有改变 iOS inputs。
- r96 Mac phase1 完成。Apple notarization submission `2847b559-aac2-426f-a015-220d9530cb29` Accepted；AppKit packaging smoke 存活 6 秒、公证后 strict smoke 2 秒通过；codesign deep/strict、spctl accepted Notarized Developer ID、stapler validate 通过。Production entitlement 已从实际 ZIP 解包的签名 bundle 读取，两架构 minos 14.0。
- Draft https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-a69da92a14bc37c77721 。包版本 `0.68.0.1` / `159.1.2.3.0`，embedded commit `45c2828ba`。ZIP 80,524,313 bytes，SHA256 `0b5a5e5b18e67daf282fbcfaded3e5aed0cb2f4f754ef4ed31f368b61a5ed1bb`；dSYM ZIP 66,277,400 bytes，SHA256 `6a6ce5fadf5ba90c285894509ec9a54d2a5ff7ed0b68a0953745360d8c70edcc`；与 GitHub draft asset digests 一致。
- 后续 quota / timeout fixes 只改测试与 Research，ARTIFACT_INPUTS 未变；finalize 前仍要对当时 HEAD 审计 ancestry 和输入相同。PR #158 当前 head 未获得 clean review；full Final CI、tag、live/appcast、#150/#151 关闭和最终 Research closeout 都未完成。Draft 或旧 head review 不能替代这些 gate。#154 保持 open；无 TestFlight 上传、CloudKit deploy 或 Production probes。
