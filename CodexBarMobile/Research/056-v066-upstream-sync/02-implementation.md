# 实现与数据通道审计

Status: `done`
Date: 2026-09-25

## 上游合并与 fork 边界

- 在 `upstream-sync/v0.66.0-mobile.2.1.0` 对官方 `v0.66.0` tag 做本地双 parent merge，包含 v0.59.0–v0.66.0 的 Mac provider、plugin、菜单、费用、性能、安全、CLI、Linux 与站点变更。46 处冲突逐项解决，保留 fork 的发布、签名、公证、CloudKit/iOS 同步、CI 触发与版本规则。
- `README.md` 在 merge 提交 `bf896f1c4` 阶段严格保留 fork 内容。随后单独审阅上游事实，更新 fork README 的 84 provider、23 语言、新 provider、Linux/Omarchy 与 Mac Usage & Spend 说明，并更新 fork README 哈希守卫。已删除的 Crof provider 从 README 移除，恢复过渡时所需的 `docs/crof.md` 随之删除；fork 的 `CLAUDE.md` 入口保留。
- 原 fork Mac 发布脚本继续负责签名、公证、双资产和 Sparkle；新增无 push 的 draft 模式，供发布授权前准备使用。用户后来明确授权正式发布；经 PR #144、#145、#146 审阅与合并，实际从 `mobile-dev` 生成并公证安装包、推送 tag、发布 GitHub release 与 Sparkle appcast。Widget Xcode DerivedData 改为使用 StudioSSD BuildScratch；发布环境中的路径测试已隔离外部变量。具体证据见 `03-testing.md`。
- `.github/workflows/omarchy.yml` 的上游 PR 触发改为手动 dispatch，以保持 fork 的 PR Fast Checks / merge 后 Final CI 规则。`Scripts/check_ci_policy.sh` 与 fork README guard 均通过。

## Mac → Shared → iOS 审计

- 新的 provider ID 使用既有 `UsageProvider` / plugin result → `UsageStore` → `SyncCoordinator` → `DeviceProviderSnapshot`/`ProviderUsageSnapshot` 路径。服务详情使用已有 optional `details`、额度使用已有 `rateWindows`，颜色使用已有 `providerIconTintHex` 与 iOS ID 回退调色板；未增加 `providerPayloadVersion`、Shared `UsageSnapshot` 必填字段或 CloudKit record 字段。
- `Shared/Notifications/QuotaProviderList.swift` 为 bifrost、helmcode、nous、muse、huggingface、v0、gitkraken、devpass 追加配额通知订阅；只有余额、费用或记忆而无额度事件的 provider 不进入配额订阅。Mac/iOS 配额测试均覆盖 78 个 quota provider 的三个状态。
- `MockProviderInjector` 添加 16 个上游新 ID 和 16 组真实 ID 样例，并给 CodeRabbit、Hyper、Atlas Cloud、LLMMan 补详情样例；Crof 仅保留历史 mock 兼容。iOS 通用详情卡沿用已有渲染，新增 ID 有调色板回退。
- 上游迁入 plugin 的 Perplexity、ElevenLabs、LLMProxy 原 typed snapshot 不再由 native fetcher 生成。本轮在 plugin 输出中保留可显示的余额、促销额度、字符、语音槽、overage、请求、tokens、key 状态与 provider 费用详情；iOS 通过现有通用详情卡展示。原专属卡布局未沿用，数据仍可读。旧模型类型仅作为 fork 编译和旧 payload 解码兼容，不恢复旧 native 网络 fetcher。
- UI 复核发现新内置 plugin 的固定详情字段原样透传时会在中文、日文界面显示英文；已将本轮 bundled provider ID、固定标题/行标签、有限的固定值纳入四语言白名单，动态服务名、模型名、自定义 plugin 字段继续保留原文。多账号标签缺少身份时的 Account N 回退也使用已有四语言格式。iOS 仍沿用 Usage 列表、详情卡与 Cost 布局，没有新增导航层级。
- 上游 Codex 可同时取多个可见账户。fork 同步将非当前账户的 co-resident `codexAccountSnapshots` 转成独立 CloudKit account record，观察其变化并触发自动 push；当前账户仍负责 provider 级费用/历史，避免重复累加。另恢复 Mac fleet 删除缓存同步入口，旧设备删除只落在既有 `CodexBarSync` zone。
- 上游 Codex/Claude 费用 parser 语义变化将 `parserLogicVersion` 从 15 升至 16，更新生成哈希，旧缓存会重算。

## 版本与发布输入

`version.env`：Mac `0.66.0.1 (156.1)`、`MOBILE_VERSION=2.1.0`、`UPSTREAM_VERSION=v0.66.0`、`UPSTREAM_SYNC_DATE=2026-09-24`。iOS `project.yml`：`2.1.0 (212)`；Sparkle `156.1.2.1.0`；候选 tag 名 `v0.66.0.1-mobile.2.1.0`。只生成一个版本。Mac/iOS CHANGELOG、四语言 in-app release notes 与本轮 Research 索引均已更新；测试与 draft 证据见 `03-testing.md`。
