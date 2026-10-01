# 合并与数据通道设计

Status: `ready`

## 合并规则

一次 merge v0.70.0，完整保留 v0.68.0..v0.70.0 上游历史、Mac provider/plugin、安全与性能变更。逐 hunk 解决冲突，保留 fork CloudKit Production、Shared wire、iOS 工程、发布版本体系、GitHub fork target 和 CI 双层 trigger。README 保持 mobile-dev 字节内容；随后单独审计上游 README factual diff。appcast 保持现有公开 feed，候选 XML 放 BuildScratch。

## 数据通道与协议

审计 fetch/plugin → UsageStore → SyncCoordinator → ProviderUsageSnapshot → CloudKit opaque payload → SyncedUsageData → cards/details/history/widgets。先定义 Shared 接口再实现 mapper/render。现有 rateWindows、details、amount、costSummary、utilizationHistory 能准确承载时复用；缺少语义时增加 bounded optional 字段，decodeIfPresent、未知字段向后兼容，不提升 payload version，不同步 credential/session/path/env。

Claude saved limit resets 需核对 generic details 是否包含 count/expiry；Kimi shorter-window blocked monthly semantics 需核对 serializer 与 iOS pace；Antigravity grouped/week-only cadence 需保留窗口标签/period/reset。Grok observed models 与 incomplete priced costs 需审计 cost projection。Quota burndown 必须区分真实 recorded remaining quota 与估计线，保留 capture age、calendar endpoints 和 account/device identity。品牌颜色需同步 iOS catalog 并保留可读性；Mistral Monthly Plan 已有通用 named window，验证无需新增 top-level CK field。

## 测试和完成门

Mac build、lint、完整 no-UI test suite 和 plugin suites；重点 PR 原有测试及 fork Sync mapper/roundtrip/account/cache/credential-isolation 回归。iOS xcodegen、Simulator build/tests、四语言 audit 与 rendered validation；BuildScratch 位于 StudioSSD。CloudKit audit 对最后已发布 v0.68.0.1-mobile.2.3.0 和最终 diff，区分 payload JSON 与 type/field/index/query/subscription。

03-testing.md 列 16 组合。真实 2 Mac × 2 iPhone old/new 无可用硬件/旧 binary/owner-account 证据时只能逐行 substituted，以实际跑过的隔离 fixtures 和 Simulator 替代并写明 APNs、Production convergence 风险。失败不能以 substituted 掩盖。

循环 diff review 覆盖冲突、wire backward compatibility、payload bounds、account attribution、窗口语义、localization、版本、签名/发布来源。阻塞项修复复测至 0；当前未授权 push/PR，因此不声称远程 current-head clean review。Goal 明确允许 review/agent 能力，必要时可委托独立 review，但执行期本地工作串行。
