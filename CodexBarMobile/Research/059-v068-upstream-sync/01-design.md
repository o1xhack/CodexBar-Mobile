# v0.67.0–v0.68.0 单版本设计

Status: `ready`
Date: 2026-09-28

## 合并策略

1. 仅在 `upstream-sync/v0.68.0-mobile.2.3.0` 上工作；起点为最新 `origin/mobile-dev` `91501264c1607f603240376208a094f94c8000ba`。
2. 从 `v0.66.0` 直接 merge `v0.68.0` 一次，保留 release 范围中的完整上游历史，不逐个 release 创建用户可见版本。
3. 冲突逐文件/逐 hunk 检查。保留 fork `README.md` 字节内容、`docs/ci-policy.md` 的 PR Fast Checks / merge Final CI 策略、CloudKit Production entitlement 与 schema 边界、`Shared/` Mobile wire contract、version/release scripts、GitHub fork 目标和 iOS 工程。Mac 上游插件/provider、安全及性能实现尽可能原样保留。
4. merge 后单独审阅上游 README 对安全、安装、provider 覆盖和故障排除的事实变化，只主动适配经证实适用于 fork 的内容；不直接接受 upstream README。审计确认上游将 provider 总数从 84 更新到 87，并新增 Aixy、Raycast、xKiro；本轮只更新 fork README 的总数、social image cache token 和总览链接，保留 fork 安装/下载入口与其他本地叙述，并同步更新 `Scripts/check_fork_readme.sh` 的 reviewed hash。appcast 发布 feed 不在 draft 阶段更新。
5. 按 `docs/versioning.md` 写入 0.68.0.1 / 159.1 / Mobile 2.3.0 / Sparkle 159.1.2.3.0；同一版本只做这一组变量，不另拆 0.67.0 用户 release。

## Mac→iOS 数据通道

在 merge 后逐项追踪：provider fetch / plugin model → Mac `SyncCoordinator` → `ProviderUsageSnapshot` → 现有 `DeviceProviderSnapshot.payload` → iOS `SyncedUsageData` → provider/account group、cards、details、Cost 与 widgets。

当前已确认的复用边界：

- `ProviderUsageSnapshot.providerID` 是字符串，不靠 iOS 编译期 provider enum 过滤所有新 provider；`ProviderAccountGroup` 也按 ID 动态分组。
- `SyncRateWindow` 可承载 named quota windows；`providerAmount` / `budget` / `costSummary` 已覆盖金额、预算和 daily cost 数据。
- `SyncProviderDetailSection` 可承载 provider 自定义 section、row、secondary value、chart；Mac `SyncCoordinator.mapDetails` 转换 generic details，iOS `ProviderDetailsView` 显示这些数据。
- 本轮只在以上已有类型不足时添加字段。任何 wire 新字段必须 optional、decode-if-present、旧 Mac/iOS fixture 全覆盖，`providerPayloadVersion` 保持 1；不得同步 cookie、token、session ID、私有路径或未经确认的设备设置。
- xKiro、Raycast、Aixy 的 quota push 是否纳入 `QuotaProviderList`，要结合上游 transition eligibility、现有 zone 命名和 CloudKit audit 最终确认；不能为了显示 quota 而改 zone ID 或记录类型。

## iOS 功能与发布 notes

- 对上游真实可同步的数据补齐 iOS 2.3.0 展示：新增 quota providers、余额/预算、具名 windows、Grok usage share、LiteLLM model usage、Claude Admin workspace details、Antigravity window/reset/partial history、Mistral Monthly Plan、Muse team quota（仅当 Mac payload 实际提供且不泄露凭证）。
- 保留未支持的计算或 provider 数据为缺省 / unavailable；不将 unknown 当作 0，不猜测模型、成本、账号或订阅状态。
- 为固定的新增用户文案更新 `Localizable.xcstrings`：en、zh-Hans、zh-Hant、ja 全部有 `translated` 状态。动态 provider 名、scope、账号标签和模型名只在符合既有语义时原样显示。
- iOS `project.yml` 所有 app / extension / sync targets 统一为 `MARKETING_VERSION=2.3.0`、`CURRENT_PROJECT_VERSION=223`，重新生成 `.xcodeproj`；在 `CodexBarMobile/CHANGELOG.md` 加 2.3.0 (223) 技术条目，并在 `MobileReleaseNotesCatalog` 添加一个 2.3.0 block。不要改写已提交审核的 2.2.0 (222) 内容。

## 版本与 CloudKit

- 候选版本：Mac `0.68.0.1` / `159.1`，Mobile `2.3.0`，Sparkle `159.1.2.3.0`，tag 基名 `v0.68.0.1-mobile.2.3.0`。
- CloudKit audit 比较最后 published tag `v0.66.0.1-mobile.2.1.0` 到最终 branch diff，检查 `CloudConstants.swift`、zone/type/field/index/subscription、payload version 和 `UsageSnapshot` 中新增的 non-optional field。
- 只新增既有 `DeviceProviderSnapshot.payload` 的 optional JSON key、沿用已部署的 type/field/index 和 subscription predicate 时结论为 `NO_DEPLOY`。新 record type、被查询/排序的新 field 或新 index、以及依赖这些新 schema 项的 subscription 才进入 Production deploy gate。private-database zone 与 subscription 实例本身是运行时数据，不是 Dashboard schema；本轮无 schema deploy。

## 测试与 review 计划

- Mac：隔离 scratch `swift build`、完整 `swift test`（遵守 KeychainNoUI 规则）、仓库 lint、插件 JS/TS 检查、`Scripts/check_ci_policy.sh`、provider/parser/cost/history/Codex account/credential safety/CloudKit sync 回归。
- iOS：StudioSSD BuildScratch 下 `xcodegen generate` 和 Simulator build/test；重点覆盖新 provider generic payload、详情 localization、color、quota warning/push gate、2.2 旧 payload decode、all-history/partial/unknown cost。
- i18n：`bash Scripts/lint.sh audit-i18n`，逐项检查新 source keys 的四种语言。
- Sync compatibility：按 `docs/ios-sync-compatibility-testing.md` 列 2 Mac × 2 iPhone 的全部 16 组合；真实 Production 设备不可得时用隔离 test stores / fixtures / Simulator / code audit 替代并保留风险。
- 自查每阶段 diff；实施后调用可用 review/agent 能力做独立 review，修复阻塞项并复测。Review 必须覆盖 Mac merge、sync bridge、iOS/UI-localization、release/version 变更。
- 本地候选完成后不 push、merge、publish tag、TestFlight upload、CloudKit Production deploy 或 live release。签名/公证/GitHub draft 若需要 release credentials，先完成全部可独立验证的本地工作，再按用户指示停在凭证边界。
