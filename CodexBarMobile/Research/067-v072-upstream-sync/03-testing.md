# 本轮测试证据

Status: `in-progress`

日志目录：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v072`（StudioSSD UUID 已校验）。所有测试不触发 Keychain 弹窗，不访问真实 provider 账户或真实 CloudKit。

## 测试计划

| 层 | 命令 / 范围 | 目的 |
|---|---|---|
| Mac build | `swift build --build-tests` | 合并树与 fork 桥接可编译 |
| Mac lint | `bash Scripts/lint.sh lint` | swiftformat/swiftlint strict、Mac locale、parser version/hash、CI policy、fork README guard |
| Mac 定向 | CloudSync*/SyncModelTests、SyncV072BridgeTests、新 provider plugin、gatekeeper、MockProviderInjector*、QuotaProviderList、AccountIdentity、CostUsage*/Grok/SpendDashboard | 冲突与新增桥接 |
| Mac 多账号/多设备 | `--filter 'AccountIdentity|MultiAccount|DualZoneReader'` | release checklist 必跑 |
| Mac 全量 | `Scripts/test.sh`（隔离分组） | 老功能回归 |
| iOS | `xcodegen generate` + Simulator build + 完整单元测试（含 V072ProviderPresentationTests、QuotaProviderListTests、ProviderColorPaletteTests、WidgetSnapshotBuilderTests） | iOS 功能与回归 |
| i18n | `bash Scripts/lint.sh audit-i18n` | 四语言齐全 |
| 兼容 | 冻结旧/新 Shared wire + 真实 merger（`tools/check_frozen_wire.py`），iOS 磁盘重开测试 | 16 组合替代验证 |

## 同步兼容 gate

本轮修改 Shared payload（`SyncRateWindow.balanceDescription`、`SyncProviderDetailSection.Row.id/progress/usageValue`）、provider 显示数据（LithosAI/Grok `providerAmount`、新 provider）与 QuotaTransition 订阅列表 → 触发 `docs/ios-sync-compatibility-testing.md` gate。

### 实体硬件与替代原因

只读 `xcrun devicectl list devices`：实体 iPhone 17 Pro Max（paired/available）与 iPhone Air（connected）两台；本机一台 Mac（Studio），没有可远程操作的第二台 Mac，也没有为本轮准备的旧/新签名 Mac 二进制组合。实体手机上是用户日常使用的 App Store/TestFlight 安装与真实 iCloud 数据，Goal 未授权覆盖安装、TestFlight 上传或写入 Production CloudKit，因此 16 组合全部用以下可复现路径替代，并保留残余风险：

1. **冻结 wire + 真实 consumer merger**（`tools/check_frozen_wire.py --old-ref v0.70.0.1-mobile.2.4.0`）：分别用最后公开 tag `v0.70.0.1-mobile.2.4.0`（commit `81e3862f04cc3bd52b5f3d2bf91885bb2e235c68`）与当前树的 Shared 源码 + `ProviderSnapshotMerger` 编译独立 reader/writer 进程；mac-a/mac-b 两个 writer 各写 old/new payload，phone-a/phone-b 两个 reader 按 16 个 old/new mask 读两台 Mac 的 payload 并做双 writer 合并（正反两种输入顺序）+ 移除 writer。断言：旧 reader 读新 payload 不崩溃、用量/重置/余额文本/details/providerAmount 一致；新 reader 读旧 payload 新字段为 nil；新 writer 的 balanceDescription 与 detail progress/id/usageValue 往返一致；合并后窗口与 details 来自同一 writer 的完整观测（不混拼新旧字段）；独立 deviceID；JSON roundtrip。
2. **iOS 磁盘缓存**：`V072ProviderPresentationTests` “v0.72 optional metadata survives disk reopening and multi Mac merge” 在 iOS Simulator 用 SSD 上真实 SwiftData store 写入旧/新两台 Mac 快照、重开容器读回并双向合并，新字段持久化、旧 writer 字段为 nil、较新观测胜出。
3. **iOS 完整单元测试** 957 Swift Testing + 58 XCTest 全过（含 WidgetSnapshotBuilder、渲染矩阵 XCTest、QuotaProviderList 83/249）。
4. **Mac 桥接**：`SyncV072BridgeTests`（nil 字段不编码、非法 metadata 丢弃不丢行、Claude 云额度经 mobile 过滤后保留、Grok 0 余额发布）。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | frozen-wire-r1/matrix-wire.json case 1；iOS 磁盘重开测试 | 缺实体四设备；Production CloudKit/APNs 时序未验证 |
| 2 | old | old | old | new | substituted | frozen-wire-r1 case 2 | 同上 |
| 3 | old | old | new | old | substituted | frozen-wire-r1 case 3 | 同上 |
| 4 | old | old | new | new | substituted | frozen-wire-r1 case 4 | 同上 |
| 5 | old | new | old | old | substituted | frozen-wire-r1 case 5 | 旧 iPhone 读新 Mac：忽略新字段，余额文本仍走既有 resetDescription |
| 6 | old | new | old | new | substituted | frozen-wire-r1 case 6 | 同上；新 iPhone 合并保持单一 writer 完整观测 |
| 7 | old | new | new | old | substituted | frozen-wire-r1 case 7 | 同上 |
| 8 | old | new | new | new | substituted | frozen-wire-r1 case 8 | 同上 |
| 9 | new | old | old | old | substituted | frozen-wire-r1 case 9 | 同上 |
| 10 | new | old | old | new | substituted | frozen-wire-r1 case 10 | 同上 |
| 11 | new | old | new | old | substituted | frozen-wire-r1 case 11 | 同上 |
| 12 | new | old | new | new | substituted | frozen-wire-r1 case 12 | 同上 |
| 13 | new | new | old | old | substituted | frozen-wire-r1 case 13 | 旧 iPhone 可见新 LithosAI/Grok 余额卡（既有 providerAmount 卡片） |
| 14 | new | new | old | new | substituted | frozen-wire-r1 case 14 | 同上 |
| 15 | new | new | new | old | substituted | frozen-wire-r1 case 15 | 同上 |
| 16 | new | new | new | new | substituted | frozen-wire-r1 case 16 + iOS 磁盘重开 | 同上 |

**Gate 结论**：16 组合全部列出，均为 substituted 且全部通过，无失败；残余风险为实体 2 Mac × 2 iPhone 下的 Production CloudKit 收敛、silent push/APNs 时序、两台手机前后台缓存与 UI 实际呈现未实测。新 museai/workbuddy 推送 zone/subscription 只在新 iPhone 上创建，旧 iPhone 不会收到这两个 provider 的额度推送（与既有“新增 provider 尾部追加”行为一致）。

## 命令证据

| 日志 | 命令 | 结果 |
|---|---|---|
| merge.log | `git merge --no-ff --no-commit v0.72.0` | 47 冲突文件，逐个解决（见 02） |
| cloudsync-build-scratch.log / cloudsync-tests.log | 子代理在 SSD 副本 `swift build --build-tests`；`swift test --filter 'CloudSync|SyncModelTests|CloudSyncSnapshotMigration'` | build 成功；113 tests / 8 suites 通过 |
| mac-build-r1.log | `swift build --build-tests` | exit 0（427.8 s） |
| mac-focused-r1.log | 1266 项 Mac 定向（同步/CloudSync/mock/gatekeeper/Spend/Grok/CostUsage/Pi/新 provider 等）未隔离并发运行 | 10 个问题：gatekeeper 簇指纹 1、mock 写路径计数 104≠105 1、并发超时 8（SpendDashboardSourceConcurrency 6、OpenAIDashboardBrowserCookieImporter 2） |
| mac-focused-r3.log | 修正后 `--filter 'ProviderArchitectureGatekeeper|MockProviderInjector|SyncV072Bridge|QuotaProviderList'` | 136 tests / 6 suites 通过 |
| mac-spendconc-r1.log / mac-cookie-r1.log | 超时两组单独运行 | 20/20、17/17 通过（判定为无隔离并发负载导致，正式门以隔离分组全量为准） |
| lint-r1..r4.log | `PATH=/opt/homebrew/bin:$PATH bash Scripts/lint.sh lint` | r1 README 生成区块缺失 → README 适配；r2 新测试格式 → swiftformat；r3 CostUsageModels file_length → 按先例 disable；r4 exit 0（SwiftFormat 0/2840、SwiftLint 0 violations、i18n 404 keys 四语言、parser version/hash、CI policy、fork README guard、Package.resolved、provider docs 均通过） |
| ios-build-r1.log | `xcodebuild … build-for-testing`（iOS 27 Simulator，DerivedData/xcresult 在 SSD） | TEST BUILD SUCCEEDED |
| ios-focused-r2.log | V072/QuotaProviderList/ProviderColorPalette/Contrast/V056 | 116 tests / 5 suites 通过 |
| ios-unit-r1.log | 完整 `CodexBarMobileTests` | 957 Swift Testing / 59 suites + 58 XCTest 全部通过 |
| frozen-wire-r1.log | `check_frozen_wire.py --old-ref v0.70.0.1-mobile.2.4.0` | PASS: 16 masks, 64 wire reads, 32 real old/new merge processes |
| ios-focused-r3.log | 审查修复后 V072/Palette/Contrast/V056 | 80 tests / 4 suites 通过 |
