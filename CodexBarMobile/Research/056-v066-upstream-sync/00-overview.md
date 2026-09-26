# v0.59.0–v0.66.0 一次性上游同步

Status: `done`
Date: 2026-09-25

## 基线、目标与分支

- 本轮从最新 `origin/mobile-dev` `d0d4fe55a8d648e34221c97c2636a34e509b4311` 创建 `upstream-sync/v0.66.0-mobile.2.1.0`，所有写入仅在该分支。
- 基线以 `version.env` 为准：`UPSTREAM_VERSION=v0.58.0`、`UPSTREAM_SYNC_DATE=2026-09-10`；当前 Mac `0.58.0.1 (141.1)`，iOS 工程 `2.0.0 (211)`。
- `steipete/CodexBar` GitHub Releases 的最新正式版本是 [v0.66.0](https://github.com/steipete/CodexBar/releases/tag/v0.66.0)，2026-09-24 18:15:52 UTC 发布；签名 tag object 为 `a6f2b8725934dfefa80ee3295504ec1a53fc4677`，peeled commit 为 `e665cbf64976839dc947e70a942ba8226388d4c9`。v0.66.0 虽尚无监控 issue，已纳入同一版本以覆盖当前正式上游。
- 目标是一次 Git merge 和一个用户可见 Mac/iOS 版本。上游 v0.58.0→v0.66.0 约 382 个非 merge 提交，预合并 46 处冲突。`v0.58.0` 是双方共同祖先。

## Open issue 对应关系

| Issue | Release | Issue | Release |
|---|---|---|---|
| [#125](https://github.com/o1xhack/CodexBar-Mobile/issues/125) | [v0.59.0](https://github.com/steipete/CodexBar/releases/tag/v0.59.0) | [#126](https://github.com/o1xhack/CodexBar-Mobile/issues/126) | [v0.60.0](https://github.com/steipete/CodexBar/releases/tag/v0.60.0) |
| [#127](https://github.com/o1xhack/CodexBar-Mobile/issues/127) | [v0.60.1](https://github.com/steipete/CodexBar/releases/tag/v0.60.1) | [#128](https://github.com/o1xhack/CodexBar-Mobile/issues/128) | [v0.60.2](https://github.com/steipete/CodexBar/releases/tag/v0.60.2) |
| [#132](https://github.com/o1xhack/CodexBar-Mobile/issues/132) | [v0.60.3](https://github.com/steipete/CodexBar/releases/tag/v0.60.3) | [#133](https://github.com/o1xhack/CodexBar-Mobile/issues/133) | [v0.60.4](https://github.com/steipete/CodexBar/releases/tag/v0.60.4) |
| [#135](https://github.com/o1xhack/CodexBar-Mobile/issues/135) | [v0.60.5](https://github.com/steipete/CodexBar/releases/tag/v0.60.5) | [#136](https://github.com/o1xhack/CodexBar-Mobile/issues/136) | [v0.61.0](https://github.com/steipete/CodexBar/releases/tag/v0.61.0) |
| [#137](https://github.com/o1xhack/CodexBar-Mobile/issues/137) | [v0.62.0](https://github.com/steipete/CodexBar/releases/tag/v0.62.0) | [#138](https://github.com/o1xhack/CodexBar-Mobile/issues/138) | [v0.63.0](https://github.com/steipete/CodexBar/releases/tag/v0.63.0) |
| [#141](https://github.com/o1xhack/CodexBar-Mobile/issues/141) | [v0.64.0](https://github.com/steipete/CodexBar/releases/tag/v0.64.0) | [#142](https://github.com/o1xhack/CodexBar-Mobile/issues/142) | [v0.64.1](https://github.com/steipete/CodexBar/releases/tag/v0.64.1) |
| [#143](https://github.com/o1xhack/CodexBar-Mobile/issues/143) | [v0.65.0](https://github.com/steipete/CodexBar/releases/tag/v0.65.0) | — | [v0.66.0](https://github.com/steipete/CodexBar/releases/tag/v0.66.0) |

已关闭 #117/#118 等先前 issue 与 v0.58.0 轮次相符；本轮 13 个 issue 在 Mac 0.66.0.1 正式发布后逐一附上 release 链接并关闭。监控 issue 的 iOS 初筛只是提示，采用 release notes、代码与真实 payload 审计作为结论依据。

## 上游变化概览

| 范围 | Mac 变化 | iOS 数据影响初判 |
|---|---|---|
| v0.59.0–v0.60.5 | plugin tabs、Linux app、Codex/Claude/Cursor/Antigravity 费用与 quota 修复、凭证安全、缓存和菜单可靠性 | quota、cost、账户身份、观测时间和未知值必须审计；纯 AppKit/Linux UI 不移植 |
| v0.61.0–v0.63.0 | 新 provider、周费用历史、Pi/OMP local history、widget 与多账号支持 | provider 卡片、费用周期、tokens、未知/partial 历史与去重需要验证 |
| v0.64.0–v0.65.0 | Helmcode/v0/TypeSafe、Charm Hyper/GitKraken/Bifrost、新账户和 Kimi region、provider plugin 引擎修复 | 新 provider、region、预算/余额/rate windows、账户隔离；CLI/菜单专属能力不移植 |
| v0.66.0 | 84 provider，14 个新增或迁入 plugin；Mac iCloud 旧设备删除；配置保存和费用缓存修复 | provider display、plugin typed usage、跨版本旧设备读取/删除需审计 |

主要来源：各 [GitHub Releases](https://github.com/steipete/CodexBar/releases)、上游 tag/commits；上游具体 PR 包括 [#3933](https://github.com/steipete/CodexBar/pull/3933)、[#3934](https://github.com/steipete/CodexBar/pull/3934)、[#3944](https://github.com/steipete/CodexBar/pull/3944)，另 [#3234](https://github.com/steipete/CodexBar/issues/3234) 是 iCloud 删除 issue。

## 风险

- 46 处合并冲突，包括 fork CI/release 和 Mac Sync；已逐项保留 fork 特有行为，同时引入上游修复。
- 上游 provider 扩充和 plugin 化可能改变 `UsageProvider`、`UsageSnapshot`、typed details 的 iOS 映射；不能只靠 Mac 编译证明兼容。
- CloudSync 旧设备删除是跨设备写操作，必须审计与 Mobile 独立的 zone、record type 与旧客户端容错。
- Mac 签名/公证及 GitHub draft 使用发布凭证；用户在后续回合明确授权 PR 合并、Mac 正式发布、iOS 上传和送审。实际发布与送审证据见 `03-testing.md`。

详细方案与证据：[01-design.md](01-design.md)、[02-implementation.md](02-implementation.md)、[03-testing.md](03-testing.md)。
