# 测试、CloudKit 与发布证据

Status: `in-progress`
Date: 2026-09-25

## 已取得的证据

- 分支：`upstream-sync/v0.66.0-mobile.2.1.0`，起点 `origin/mobile-dev` `d0d4fe55a8d648e34221c97c2636a34e509b4311`；上游 tag `v0.66.0` peeled commit `a6f2b8725934dfefa80ee3295504ec1a53fc4677`。
- Mac 隔离构建：`swift build --scratch-path /Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-swift --jobs 4` 通过。定向 `QuotaProviderListTests|SyncCodexMultiAccountIntegrationTests|MockProviderInjectorIntegrationTests|PerplexityUsageFetcherTests|LLMProxyUsageFetcherTests` 共 96 tests / 5 suites 通过，含 iCloud 开启时无菜单切换也同步其他 Codex 账号的新增回归。
- `AccountIdentity|MultiAccount|DualZoneReader|CloudSyncDeviceRemoval` Mac 定向回归共 133 tests / 13 suites 通过；新增测试以真实 `Observation` 触发 Codex inactive-only 账号更新，确认无需菜单切换或手动 push。
- 全套测试首轮在 Alibaba Personal CLI 命令旧断言失败：上游 Personal 地区已改为 `console call` API。更新旧断言后 `AlibabaTokenPlanCLIUsageTests` 7 tests / 1 suite 通过；全套从头重新执行。
- iOS：`xcodegen generate` 后，Simulator `xcodebuild` `BUILD SUCCEEDED`。
- iOS 签名 Simulator focused test：`QuotaProviderListTests`、`ProviderColorPaletteTests`、`WidgetSnapshotBuilderTests` 共 113 tests / 3 suites 通过，结果包 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-ios-focused-signed.xcresult`。其中 Today 费用的 2 Mac × 2 iPhone 参数化模拟测试 16 例通过；这只覆盖 widget 费用聚合，不能当作完整实时 CloudKit 矩阵。
- 兼容性 Simulator focused test：`CloudKitMergeTests`、`DeviceLifecycleEventTests`、`V047SyncCompatTests`、`V049SyncCompatTests`、`V058SyncSemanticsTests` 共 121 tests / 5 suites 通过，结果包 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v066-ios-compat.xcresult`；其中旧新版本双 Mac/双 iPhone 16 例矩阵各自覆盖 v0.47、v0.49 通用详情与 v0.58 独立 writer/cache，共 48 参数化组合。
- `bash Scripts/lint.sh audit-i18n`：359 个 source key 均存在，四语言均已翻译。`bash Scripts/regenerate-plugin-js.sh --check`：19 个 TypeScript 插件的 JS 是当前版本；`tsc --project tsconfig.plugins.json` 通过。
- `PATH=/opt/homebrew/bin:$PATH bash Scripts/lint.sh lint` 全部通过：SwiftLint 2683 files 零违规、SwiftFormat 零需格式化、Shell 73 files、站点 23 locales / 84 provider cards、iOS 359 字符串和 fork CI guard。合并尚未提交时 parser-version 审计只见 `HEAD` 的旧 diff；提交后须再跑以确认本轮 15→16 bump。
- 文档链接检查通过：264 条本地链接。上游删去的 `docs/crof.md` 被 fork `README.md` 继续引用，故恢复该 fork 文档；README 内容保持字节不变。
- Review 发现并修复：Codex 非当前账号的 co-resident 结果需被 `SyncCoordinator` 观察以触发自动 push；无 push draft 不能把 GitHub 尚不存在的本地 commit 作为 `--target`；app/dSYM 校验的二进制解压目录必须位于 StudioSSD BuildScratch。Mac 定向回归和相关脚本校验已通过。
- 修复后独立复审确认上述三个阻塞项已解除，当前 draft-only 范围未发现新增阻塞项。将来 live finalize 必须在合并推送后核对 draft target 与最终 reviewed commit，本 Goal 不执行。
- 上游社交卡检查会尝试修改 fork-owned `README.md` 并强制其中 provider 数量跟随上游。本轮保持 README 字节不变，仅对 `docs/index.html` 执行图片 cache token 校验；`Scripts/check_fork_readme.sh` 独立保证 README 身份，`check-site-locales` 与 social-card 25 个测试通过。
- `PreviewData.swift` 已按卡片类型复核：现有 Bedrock、Z.ai 等 generic detail 样例覆盖本轮新增 provider 的通用详情呈现；新 ID 由 Mac mock/provider 配额样例和同步 fixture 覆盖，故不逐 provider 添加相同预览卡。Plugin 化后的 Perplexity、ElevenLabs、LLMProxy 专属 typed 卡在 iOS 侧改由通用详情显示；余额、额度、字符/语音槽与代理费用等字段已映射进 `details`，视觉样式与旧专属卡不同。

## CloudKit Production schema 审计

- 对比最后 published fork tag `v0.58.0.1-mobile.1.23.0` 到本候选：`Shared/iCloud/CloudConstants.swift` 零差异；`providerPayloadVersion` 保持 `1`；`Shared/Models/UsageSnapshot.swift` 未增删 `public let`，没有新增必填 wire 字段。
- 源码差异未新增 `CKRecord` 类型、字段、索引、zone 或 query predicate。新配额服务仅在既有 `Quota-{providerID}-{state}Zone` 命名规则下追加订阅；Mac fleet 的删除使用已部署的 `CodexBarSync` zone 与原有记录类型。
- 结论：按 `docs/cloudkit-deploy-audit.md` 属于 **NO_DEPLOY**，不需 Production schema deploy；本轮不调用 Dashboard deploy。源码审计不替代 Production 跨设备验证。

## 2 Mac × 2 iPhone 新旧版本矩阵

本轮涉及 provider 显示、Mac fleet 删除、缓存与配额订阅，适用 `docs/ios-sync-compatibility-testing.md`。现场只有一台 Mac，`system_profiler SPUSBDataType` 未发现已连接 iPhone；iOS 27 Simulator 可用。以下 16 个组合无法在独立真实硬件与同一 Production container 上运行，均以本地 fixture、模拟器和代码审计替代。共同剩余风险：真实 silent push、两 Mac 同时写入、旧 iPhone 缓存与版本、Production 网络和用户账户权限尚未在物理设备复核。

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

- Mac 全套单元测试、旧功能回归、最终 diff review。
- Mac 签名、公证与 GitHub draft 使用发布凭证，需按 Goal 门槛征求授权；`Scripts/release.sh` phase1 会 `git push -f origin <tag>` 并删除旧 draft，与本 Goal 禁止 push/tag publish 冲突。须走仅签名公证和 `gh release create --draft --target <head>` 的无 tag push 路径；不执行 live finalize、appcast push 或 TestFlight。
