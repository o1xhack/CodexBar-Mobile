# 测试、CloudKit 与发布证据

Status: `in-progress`
Date: 2026-09-25

## 已取得的证据

- 分支：`upstream-sync/v0.66.0-mobile.2.1.0`，起点 `origin/mobile-dev` `d0d4fe55a8d648e34221c97c2636a34e509b4311`；上游 `v0.66.0` 签名 tag object `a6f2b8725934dfefa80ee3295504ec1a53fc4677`，peeled commit `e665cbf64976839dc947e70a942ba8226388d4c9`。
- Mac 隔离构建：`swift build --scratch-path /Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-swift --jobs 4` 通过。定向 `QuotaProviderListTests|SyncCodexMultiAccountIntegrationTests|MockProviderInjectorIntegrationTests|PerplexityUsageFetcherTests|LLMProxyUsageFetcherTests` 共 96 tests / 5 suites 通过，含 iCloud 开启时无菜单切换也同步其他 Codex 账号的新增回归。
- `AccountIdentity|MultiAccount|DualZoneReader|CloudSyncDeviceRemoval` Mac 定向回归共 133 tests / 13 suites 通过；新增测试以真实 `Observation` 触发 Codex inactive-only 账号更新，确认无需菜单切换或手动 push。
- 全套测试首轮在 Alibaba Personal CLI 命令旧断言失败：上游 Personal 地区已改为 `console call` API。更新旧断言后 `AlibabaTokenPlanCLIUsageTests` 7 tests / 1 suite 通过；全套从头重新执行。
- 后续全套还暴露两条旧测试假设：Codex 分段菜单在 iCloud 开启时也必须抓取 sibling 工作区；Copilot allowance 缓存测试若要覆盖选中账号路径，必须显式关闭 iCloud/widget fanout。两处只调整测试条件/断言，并给 Copilot 等待加入上限。`CodexAccountScopedRefreshTests` 及 `CopilotAllowanceCacheTests` 5 tests 均定向复测通过。
- 全套继续暴露两条上游旧测试预期：保留的费用快照现在带有日桶时区标识；费用面板把 `Est.` 展开为 `Estimated:`。只修正预期而不改产品逻辑，`CostUsageStoreReadWorkTests` 与 `InlineCostHistoryDashboardLabelTests` 定向复测 99 tests / 2 suites 通过；随后两片全套从头重跑。
- 后续全套在 mock 目录发现上游 provider 扩充后的旧覆盖数（79）及费用允许清单已失效：本轮真实 provider ID 样例为 94 条，新增额度/积分/详情类 provider 不虚构 USD 费用。修订样例约束和文档后，`MockProviderAdvancedScenariosTests|MockProviderInjectorTests` 定向 29 tests / 2 suites 通过。
- 全套随后发现 OpenRouter 诊断 fixture 将异常历史行放在最新完成日，而新 plugin 会先以日期专属响应替换该日历史行；测试因此没有覆盖预期的异常路径。将异常历史行移到前一日，并同步 `QuotaWindowPresentationTests` 对上游 `Estimated:` 文案的断言。两组 11 tests / 2 suites 定向复测通过，最终完整回归通过。
- 最后几组又发现 7 个上游新 token-account provider 已进入共享 catalog，fork 的显式回归集合仍为 29 个；更新为 36 个并保留与 `SyncCoordinator` 全量相等断言。Widget 隐私测试默认开启 iCloud 时会按 fork 规则主动抓取多个账号，现显式关闭 iCloud 来验证仅关闭 widget 的本机路径。更重要的是，上游 Alibaba/Qwen 共用 parser 已能解析月度窗口，但 fork 的 `AlibabaTokenPlanUsageSnapshot.toUsageSnapshot()` 漏掉 `monthlyWindow`，且订阅摘要合并会丢失它；修复这条真实功能回归，令月度独占时成为主窗口、与其他窗口/订阅 credits 共存时成为具名额外窗口。独立复审发现仅月度 rate window 与订阅 credits 共存的可达边界，已追加 Mac→iOS `rateWindows` 测试；相关 18 tests / 4 suites 定向通过，最终完整回归通过。
- 末尾 Widget token owner 测试只配置一个账号，无法进入新多账号 fanout 路径，故错误地要求 `accountSnapshots` 非空。为此用例补第二个隔离账号后，仍核验标签编辑后暂时性失败保留旧快照、未授权失败清除快照；`WidgetTokenOwnerTests` 12 tests / 1 suite 定向通过。Mac 全套第 1 片 730 selections / 65 groups 全绿退出（`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-full-mac-pass5-shard0.log`）；第 2 片 698 selections / 64 groups 全绿退出（`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-full-mac-pass6-shard1.log`）。两片合计发现的 1428 selections 均已运行，没有失败、重试或超时。
- 上游及 fork 合并令 `ProviderArchitectureGatekeeperTests` 中 108 个源码精确锚点错位，连带报告大量未证明分支。按当前源码逐一重定位 106 个仍存在的锚点，审阅另 2 个定价回退语义变化；修正 9 处聚类拆分/指纹变化，总计新增 94 条带精确行、原文、引用次数、逐次指纹和具体理由的守卫条目。扫描算法、锚点容忍度与全量 Sources 覆盖没有放宽；定向守卫 41 tests / 1 suite 与最终完整回归均通过。
- iOS：`xcodegen generate` 后，Simulator `xcodebuild` `BUILD SUCCEEDED`。
- iOS 签名 Simulator focused test：`QuotaProviderListTests`、`ProviderColorPaletteTests`、`WidgetSnapshotBuilderTests` 共 113 tests / 3 suites 通过，结果包 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-ios-focused-signed.xcresult`。其中 Today 费用的 2 Mac × 2 iPhone 参数化模拟测试 16 例通过；这只覆盖 widget 费用聚合，不能当作完整实时 CloudKit 矩阵。
- 兼容性 Simulator focused test：`CloudKitMergeTests`、`DeviceLifecycleEventTests`、`V047SyncCompatTests`、`V049SyncCompatTests`、`V058SyncSemanticsTests` 共 121 tests / 5 suites 通过，结果包 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-ios-compat.xcresult`；其中旧新版本双 Mac/双 iPhone 16 例矩阵各自覆盖 v0.47、v0.49 通用详情与 v0.58 独立 writer/cache，共 48 参数化组合。
- `bash Scripts/lint.sh audit-i18n`：359 个 source key 均存在，四语言均已翻译。`bash Scripts/regenerate-plugin-js.sh --check`：19 个 TypeScript 插件的 JS 是当前版本；`tsc --project tsconfig.plugins.json` 通过。
- `PATH=/opt/homebrew/bin:$PATH bash Scripts/lint.sh lint` 在 Widget fixture 修正后最终重跑通过（`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-lint-final3.log`）：SwiftLint 2683 files 零违规、SwiftFormat 零需格式化、Shell 73 files、站点 23 locales / 84 provider cards、iOS 359 字符串和 fork CI guard；parser-version 审计明确得到 `parser code changed AND parserLogicVersion bumped — OK`。
- `bash Scripts/changelog-to-html.sh 0.66.0.1` 成功提取 fork 的单版本 Mac 发行说明，标题为 `CodexBar 0.66.0.1-Mobile 2.1.0`，并包含新增、变更、修复段；提取结果保存在 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-changelog-extract.html`。
- merge 提交时 README 与 fork `mobile-dev` 逐字节相同；随后独立审阅并更新 fork README 中的 84 provider、23 语言和新增功能事实，移除失效 Crof 链接，恢复上游 social-card cache token 检查，并有意更新 `Scripts/check_fork_readme.sh` 哈希。当前文档链接检查通过 284 条本地链接。
- Review 发现并修复：Codex 非当前账号的 co-resident 结果需被 `SyncCoordinator` 观察以触发自动 push；无 push draft 不能把 GitHub 尚不存在的本地 commit 作为 `--target`；app/dSYM 校验的二进制解压目录必须位于 StudioSSD BuildScratch。Mac 定向回归和相关脚本校验已通过。
- 修复后独立复审确认上述三个阻塞项已解除，当前 draft-only 范围未发现新增阻塞项。将来 live finalize 必须在合并推送后核对 draft target 与最终 reviewed commit，本 Goal 不执行。
- README 独立适配与 Alibaba/Codex/Copilot 旧测试修正再次经过只读复审，未发现新阻塞；fork 下载入口、README 哈希、上游 Personal API 区分、CloudKit fanout 测试范围和有界等待均已核查。
- 经独立 README 审阅后，恢复上游对 `README.md` 与 `docs/index.html` 双路径的 social-card cache token 校验；`Scripts/check_fork_readme.sh` 继续验证 fork 身份，`check-site-locales` 与 social-card 26 个测试通过。
- 最后一轮只读复审覆盖费用快照时区、`Estimated:` 面板文案、Codex sync 注释及发布关键 diff，未发现新增阻塞；`git diff HEAD --check` 通过。独立复审结论仅覆盖代码，完整 Mac suite 须以实际跑完为准。
- 最新只读复审再次核对 OpenRouter 日期替换语义、额度窗口文案、99 组 mock 构成和架构守卫格式化后的精确指纹；未发现弱化断言或阻塞缺陷。最终完整 Mac suite 与 lint 单独记录其运行结果。
- `PreviewData.swift` 已按卡片类型复核：现有 Bedrock、Z.ai 等 generic detail 样例覆盖本轮新增 provider 的通用详情呈现；新 ID 由 Mac mock/provider 配额样例和同步 fixture 覆盖，故不逐 provider 添加相同预览卡。Plugin 化后的 Perplexity、ElevenLabs、LLMProxy 专属 typed 卡在 iOS 侧改由通用详情显示；余额、额度、字符/语音槽与代理费用等字段已映射进 `details`，视觉样式与旧专属卡不同。
- 用户询问多 Mac 与 UI 后再审计，发现本轮内置 plugin 的固定详情标签缺少 iOS 本地化白名单；已补四语言目录与动态标签保护。循环复审又发现 Muse 登录/Weekly/动态 Plan、v0 额度文案与动态 Scope、Bifrost 周期和合成 `Other models`、新服务多账号 tab 的边界，均已修复并加入测试；最终只读复审未发现阻塞。iOS 27 iPhone 18 Pro Simulator 签名定向 `V066ProviderPresentationTests` 4 tests / 1 suite 全部通过，结果包 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-ui-localization-final5.xcresult`；`audit-i18n`、三文件 SwiftLint/SwiftFormat、`git diff --check` 均通过。首轮禁用签名的模拟器测试在 CloudKit container 初始化前崩溃，0 项测试执行，已改用签名构建复测；失败结果不计入产品测试结论。实际运行的演示数据确认 Usage→详情导航与现有卡片布局，但演示数据没有本轮新 provider，故未获得其真实内容的视觉截图；真实双 Mac/双 iPhone 仍为下表替代验证。

## CloudKit Production schema 审计

- 对比最后 published fork tag `v0.58.0.1-mobile.1.23.0` 到本候选：`Shared/iCloud/CloudConstants.swift` 零差异；`providerPayloadVersion` 保持 `1`；`Shared/Models/UsageSnapshot.swift` 未增删 `public let`，没有新增必填 wire 字段。
- 复核命令 `git diff --exit-code v0.58.0.1-mobile.1.23.0 HEAD -- Shared/iCloud/CloudConstants.swift` 再次返回 0；`CodexBarMobile/CodexBarMobile/CodexBarMobile.entitlements` 与 `Scripts/package_app.sh` 均声明 CloudKit `Production`。
- 源码差异未新增 `CKRecord` 类型、字段、索引、zone 或 query predicate。新配额服务仅在既有 `Quota-{providerID}-{state}Zone` 命名规则下追加订阅；Mac fleet 的删除使用已部署的 `CodexBarSync` zone 与原有记录类型。
- 结论：按 `docs/cloudkit-deploy-audit.md` 属于 **NO_DEPLOY**，不需 Production schema deploy；本轮不调用 Dashboard deploy。源码审计不替代 Production 跨设备验证。

## 2 Mac × 2 iPhone 新旧版本矩阵

本轮涉及 provider 显示、Mac fleet 删除、缓存与配额订阅，适用 `docs/ios-sync-compatibility-testing.md`。`old` 表示 `origin/mobile-dev` 基线源码（Mac `version.env` 为 `0.58.0.1`，iOS 工程为 `2.0.0 (211)`），`new` 表示本轮候选（Mac `0.66.0.1`，iOS `2.1.0 (212)`）；这不是对现场已安装版本的断言。最后已发布 Mac tag 是 `v0.58.0.1-mobile.1.23.0`。现场只有一台 Mac，`system_profiler SPUSBDataType` 未发现已连接 iPhone；iOS 27 Simulator 可用。以下 16 个组合无法在独立真实硬件与同一 Production container 上运行，均以本地 fixture、模拟器和代码审计替代。共同剩余风险：真实 silent push、两 Mac 同时写入、旧 iPhone 缓存与版本、Production 网络和用户账户权限尚未在物理设备复核。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 1 | 真实双 Mac/双 iPhone、silent push 未测 |
| 2 | old | old | old | new | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 2 | 真实双 Mac/双 iPhone、silent push 未测 |
| 3 | old | old | new | old | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 3 | 真实双 Mac/双 iPhone、silent push 未测 |
| 4 | old | old | new | new | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 4 | 真实双 Mac/双 iPhone、silent push 未测 |
| 5 | old | new | old | old | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 5 | 真实双 Mac/双 iPhone、silent push 未测 |
| 6 | old | new | old | new | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 6 | 真实双 Mac/双 iPhone、silent push 未测 |
| 7 | old | new | new | old | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 7 | 真实双 Mac/双 iPhone、silent push 未测 |
| 8 | old | new | new | new | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 8 | 真实双 Mac/双 iPhone、silent push 未测 |
| 9 | new | old | old | old | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 9 | 真实双 Mac/双 iPhone、silent push 未测 |
| 10 | new | old | old | new | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 10 | 真实双 Mac/双 iPhone、silent push 未测 |
| 11 | new | old | new | old | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 11 | 真实双 Mac/双 iPhone、silent push 未测 |
| 12 | new | old | new | new | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 12 | 真实双 Mac/双 iPhone、silent push 未测 |
| 13 | new | new | old | old | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 13 | 真实双 Mac/双 iPhone、silent push 未测 |
| 14 | new | new | old | new | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 14 | 真实双 Mac/双 iPhone、silent push 未测 |
| 15 | new | new | new | old | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 15 | 真实双 Mac/双 iPhone、silent push 未测 |
| 16 | new | new | new | new | substituted | V047/V049/V058 sync fixtures + WidgetSnapshotBuilderTests case 16 | 真实双 Mac/双 iPhone、silent push 未测 |

## 待完成与发布边界

- Mac 全套单元测试、旧功能回归、最终 lint、CloudKit schema 审计和独立 diff review 已完成，未发现剩余阻塞项。真实双 Mac × 双 iPhone Production 组合只有替代验证，风险见上表。
- Mac 签名、公证与 GitHub draft 使用发布凭证，需按 Goal 门槛征求授权。使用已审阅的 `Scripts/release.sh --draft-no-tag-push`：构建、签名、公证并创建 draft；GitHub draft 暂指向远端已有的 `mobile-dev`，notes 明确记录真正构建的本地 commit。此模式不推送 tag、不清理旧 draft；live 发布前须在另一次获准流程中把 draft target 调整到最终 reviewed commit。本 Goal 不执行 live finalize、appcast push 或 TestFlight。
