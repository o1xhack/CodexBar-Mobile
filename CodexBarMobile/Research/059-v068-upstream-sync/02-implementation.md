# v0.67.0–v0.68.0 单版本实现记录

Status: `in-progress`
Date: 2026-09-28

## 上游 Mac 同步

- 从上一个正式同步点 `v0.66.0` 一次合并上游 `v0.68.0`，因此 issues #150 / #151 进入同一个 release train。保留上游 provider、plugin runtime、UI、cost history、CLI、安全、性能及平台改动；fork CI、版本和发布流程、CloudKit Production entitlement、iOS targets 与 fork-owned README 继续由 fork 控制。
- README 单独审计：`v0.67.0` / `v0.68.0` 的 README 将总数从 84 更新为 87，并增加 Aixy、Raycast、xKiro。当前 Mac provider 清单包含这三项，因此将总数改为 87、social 图片 cache token 同步到当前图像，并把旧的 provider 名称摘要替换成指向本页 provider 清单的链接；fork 的安装、下载和其余产品说明保留。`Scripts/check_fork_readme.sh` 的哈希随这项有意审阅的 fork README 更新一起改动。
- Mac `SyncCoordinator` 用已有 `ProviderUsageSnapshot` 通路输出 provider quota、amount、details、cost 和 identity；这轮新增了 Aixy 的 key-scoped opaque identity，并将 cost reporting period 映射到既有 cost summary。没有同步凭证、登录 session secret、API key secret、路径或用户设置。
- Raycast 插件给 credits meter 写入 `monthly` period，使 Mac 阈值 lane 与 iOS 通知使用周/月控制和 Monthly 文案；xKiro daily 通知不发送“Daily free tokens”自定义标题，避免和本地化 Daily 重复。
- 上游 `.github/pr-proof/muse-web-team-quota.log` 是真实账户用量记录，不属于产品功能；已从候选分支移除。Muse team quota 的产品代码保留，本轮没有执行真实账户/provider QA。

## Mac→iOS wire 与兼容性

- `SyncCostSummary.reportingPeriod` 是 optional JSON payload key，供 all-time / month-to-date / rolling 等窗口区分聚合口径；旧 payload 解码为 `nil`。wire version 仍是 1。iOS 在周期不一致时不把不同区间的费用硬合并，并保留 all-time history 的有效覆盖边界。
- 新 provider quota 和 details 继续使用 `providerID`、`rateWindows`、`providerAmount`、`costSummary`、account identity 与 generic detail section。rate-window id / label / period 都是 optional payload keys，旧 payload 可解码；新增的 provider tint、通知资格和卡片/详情表现只复用现有模型。
- Aixy identity 由 Mac 上游返回的 key ID 映射为 `aixy:key:<opaque ID>`；按 API key 归并、大小写敏感；没有 key ID 时不伪造 identity，旧 iOS 使用既有 per-device fallback。
- `CodexBarMobileTests/CloudKitMergeTests.swift` 枚举两台 Mac writer 与两台 iPhone reader 的 16 种旧/新布置；这验证 JSON payload 编解码与 reader 兼容，不模拟 CloudKit、设备缓存或通知投递。实际矩阵证据和残余风险见 `03-testing.md`。

## iOS 用户体验与发布记录

- PreviewData 已按卡片类型复核：现有 Claude quota、多 rate windows、Kiro generic details 与 Antigravity 多账户样例覆盖本轮沿用的通用表现；本轮新 provider 未新增卡片布局，不为每个 provider 重复添加同类 preview。Provider-specific identities/labels/colors 与 payload 数据仍由专项测试和 mock injector 覆盖。
- iOS provider 列表、颜色、detail subtitle、mock provider 和 quota notification list 已覆盖本轮新增的 xKiro、Raycast、Aixy，以及 upstream provider display 的新增数据。Grok / LiteLLM / Claude / Mistral / Muse 等内容走 generic snapshot/details 与既有 provider data model；不可从 Mac payload 得出的数据维持 unavailable。
- `ContentView.swift` 的 release notes 新增 2.3.0 并包含 en、zh-Hans、zh-Hant、ja 翻译；`Localizable.xcstrings` 的本轮新增文案经 i18n audit 确认为四语 translated。iOS 技术 changelog 更新为 2.3.0 (223)。
- iOS `project.yml` 中所有 targets 使用 `MARKETING_VERSION=2.3.0`、`CURRENT_PROJECT_VERSION=223`；已运行 `xcodegen generate` 生成 `CodexBarMobile.xcodeproj`。

## CloudKit schema 判断

- 新增字段只存在于既有 `DeviceProviderSnapshot.payload` JSON 内容，不是 CloudKit 可查询字段；没有新增 CKRecord type、schema field、索引或 query/subscription predicate。新增 provider 可以创建自己的 private-zone / zone-subscription 实例；这些是运行时数据，并非新的 Dashboard schema。
- `QuotaTransition` 仍复用现有 record type 与 private database zone/subscription 路径；provider list 追加新 provider 的 transition event 写入/订阅资格，保留所有已有 provider 的 zone/subscription 身份与字段契约。
- 按 `docs/cloudkit-deploy-audit.md` 的 Production schema 规则结论为 `NO_DEPLOY`。本轮不读取或写入 Production CloudKit。

## 发布候选与验证状态

- Mac：`0.68.0.1` / `159.1`；Mobile：`2.3.0`；Sparkle version：`159.1.2.3.0`；候选 tag / zip 基名：`v0.68.0.1-mobile.2.3.0`。
- Mac 完整串行测试通过：13,415 tests / 1,371 suites（r95），日志 `UpstreamSync068Review20260929-r95-mac-full-color-fix.log`。此前一次完整跑测曾在 Copilot stacked allowance fixture 卡住；根因为通用 provider test override 被接入 token-account fanout。现已使用独立 token-account override，定向 Copilot 测试也通过。该失败跑测已中断，不作为最终结果。
- Mac 完整 lint 通过：2,724 个文件 0 个 SwiftLint 违规；iOS `Localizable.xcstrings` 363 个 source keys 全部存在，四种语言均为 translated；parserLogicVersion 已从 16 bump 到 17，CodexParserHash 已重生成至 `6fbe90ca603fb1e4`；parser-version/hash guards 通过。日志 `mac-lint-final-pass.log`。
- iOS Release Simulator build 通过；6 个定向测试套件共 151 项通过，包含 16 组合 payload/merge 矩阵；20 项 quota notification parser 测试通过并覆盖 iOS 2.2 后缀规则。日志 `ios-release-build-final.log`、`ios-focused-final-resolved.log`、`ios-parser-compat-final.log`。
- 16 种设备新旧组合都已逐格记录为 `substituted`；没有真实设备 fleet、CloudKit Production、APNs 或旧版二进制验证。CloudKit Production schema 审计为 `NO_DEPLOY`，没有 Production read/write。
- Independent review 曾发现旧 NSE 对 named-window warning record name 的 P2；已调整尾部格式、增加旧解析器回归验证并复审。后续 review 发现的 cost-window coverage 与 reader/producer calendar 边界问题已修复并复测；PR #155、#156、#157、#158、#159 和 #160 的各自最终 head 已通过 clean review / resolved-thread gate；host-timezone fixture 修复后的最终 full Final CI 仍待完成。
- 最新候选全量 iOS 测试通过：874 passed、6 skipped、0 failed（r85）；Release Simulator build 与全量 lint 通过。完整日志、result bundles、review 修复与未覆盖风险见 `03-testing.md`。
- 用户已授权 Mac live release、合并 PR #155 和关闭 #150/#151；不包含 TestFlight 上传或 CloudKit deploy。已从同步分支源代码创建签名、公证的 tagless draft；PR #155–#160 已按各自 clean review / Fast Checks 合并；host-calendar fixture 与 Linux deadline suite 调度修复均已合并。当前 merge commit `1b1067b9fe1ab06b4e665a1e69b776d014cd3318` 的 full Final CI `36673362217` 正在运行。此前失败/取消的矩阵不计全绿。通过后再执行 tag 和 finalize。#154 保持 open。

Research 保持 `in-progress`，直到 Mac release、对应 issue 与证据收尾完成。

## 打包与 review 证据

Mac r96 phase1 签名、公证（Accepted `2847b559-aac2-426f-a015-220d9530cb29`）、6 秒 packaging AppKit smoke 与公证后 2 秒 strict smoke、codesign/spctl/stapler 验证通过。Draft https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-a69da92a14bc37c77721 ，实际包版本 `0.68.0.1` / `159.1.2.3.0`，Production，arm64/x86_64 最低 macOS 14.0。artifact source `45c2828ba`；后续修复仅测试/Research/CI 调度，artifact inputs 相同。

- PR #155 merge `54aaddff5`：单版本同步 + iOS bridge，round 15 clean。
- PR #156 merge `c42f504af`：较旧 Swift 的 RGB type inference 修复，clean。
- PR #157 merge `5fdd46704`：较旧 Swift 的 quota cost assertion type-check 修复，28 定向 tests passed、clean。
- PR #158 merge `debeca9dc`：OpenRouter optional timeout fixture 调度余量，17 定向 tests（四 engine/scheduling 组合）passed；文档 provenance finding 修复，最终 `522e929b5` clean、0 unresolved。两次 review container setup failure 没有被记作 clean，之后重试成功。

最终 remote full CI、live/tag/appcast、#150/#151 完成与 Research 收尾仍待完成；完整证据以 `03-testing.md` 为准。
