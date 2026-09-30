# v0.67.0–v0.68.0 单版本上游同步

Status: `in-progress`
Date: 2026-09-28

## 基线、范围与分支

- 本轮从最新 `origin/mobile-dev` `91501264c1607f603240376208a094f94c8000ba` 创建 `upstream-sync/v0.68.0-mobile.2.3.0`。此前有一处未提交的 repo-local Git workflow skill 修改；创建分支时原样保留，不属于本轮 Research 或后续提交。
- 权威基线：`version.env` 的 `UPSTREAM_VERSION=v0.66.0`、`UPSTREAM_SYNC_DATE=2026-09-24`；Mac 现行为 `0.66.0.1 / 156.1`，该版本已正式发布为 `v0.66.0.1-mobile.2.1.0`。
- GitHub Releases 当前正式最新版本为 [v0.68.0](https://github.com/steipete/CodexBar/releases/tag/v0.68.0)，发布于 2026-09-27 UTC。Release 列表同时包含 v0.67.0 和 v0.68.0；仓库中可见的 v0.69.0 tag 不属于 Releases 正式发布，按用户指定的事实来源排除。
- 当前全部 open `upstream-sync` issues 只有 [#150](https://github.com/o1xhack/CodexBar-Mobile/issues/150)（v0.67.0）和 [#151](https://github.com/o1xhack/CodexBar-Mobile/issues/151)（v0.68.0）。本轮把两项合并为一个目标，不拆分版本；范围从上游 v0.66.0 tag 一次 merge 到 v0.68.0。
- 上游 v0.68.0 tag peeled commit 为 `7998bf66c796befcb91c38e6b1096e702e511481`；本地 tag 元数据有 SSH 签名，但本机缺少 `gpg.ssh.allowedSignersFile`，故 `git verify-tag` 无法本地验签。GitHub Release 页面显示 v0.67.0 / v0.68.0 tag commit 为 Verified。v0.68.0 上游 `version.env` 为 `MARKETING_VERSION=0.68.0`、`BUILD_NUMBER=159`。
- v0.66.0→v0.68.0 共 105 个非 merge commits、510 个变更文件（28,249 insertions / 13,786 deletions），需保留上游完整 Mac 功能、修复、性能与安全变化，同时逐项保留 fork CI、发布、CloudKit、Mobile sync、版本号和 README 约束。

## Issue 与历史闭环

| 当前 open issue | 正式 release | 结果范围 |
|---|---|---|
| #150 | [v0.67.0](https://github.com/steipete/CodexBar/releases/tag/v0.67.0)（2026-09-26 UTC） | 纳入本轮单一 v0.68.0 目标 |
| #151 | [v0.68.0](https://github.com/steipete/CodexBar/releases/tag/v0.68.0)（2026-09-27 UTC） | 纳入本轮单一 v0.68.0 目标 |

前一轮 [PR #144](https://github.com/o1xhack/CodexBar-Mobile/pull/144) 已将 v0.59.0–v0.66.0 合并为一个 train；[PR #147](https://github.com/o1xhack/CodexBar-Mobile/pull/147) 记录 Mac 0.66.0.1 正式发布和 iOS 2.1.0 review 处理。此前关闭的 issue #143 对应 v0.65.0，已由该单版本 train 覆盖。当前不是重开旧 release 范围。

最新 iOS 状态：用户于 2026-09-29 确认 iOS 2.2.0 已发布；此前 Research 058 / PR #153 中 `WAITING_FOR_REVIEW` 是旧状态，本轮没有独立查询 App Store Connect。用户确认将本轮 Mac release 的 `MOBILE_VERSION` 设为 `2.3.0`，并计划随后上传 iOS 2.3.0；候选 iOS build 为 223。此次只完成 iOS 本地构建与测试，不上传 TestFlight。

## 版本候选

按 `docs/versioning.md`，单一候选为：

| 变量 | 候选值 | 推导 |
|---|---|---|
| Mac `MARKETING_VERSION` | `0.68.0.1` | 上游版本段照抄 v0.68.0，fork release patch 为 `.1` |
| Mac `BUILD_NUMBER` | `159.1` | v0.68.0 上游整数 build 159，加本轮 fork patch |
| `MOBILE_VERSION` | `2.3.0` | 新 iOS release train；用户确认 2.2.0 已发布 |
| Sparkle `version` | `159.1.2.3.0` | `BUILD_NUMBER + "." + MOBILE_VERSION` |
| tag / zip 基名 | `v0.68.0.1-mobile.2.3.0` | 单一 Mac/iOS train |
| `UPSTREAM_SYNC_DATE` | `2026-09-27` | GitHub Release 日期，UTC |
| iOS project build | `223` | 当前工程 build 222 后递增，所有 target 一致 |

这组值属于单版本发布候选。用户已明确授权 Mac live release 及必要的 origin push、merge、tag 和 appcast 发布；仍需先通过 review/测试/公证闸门。本轮不上传 TestFlight 或提交新的 App Review。

## 上游变化初筛

- v0.67.0 增加成本报告期共享模型、可移植偏好、Stay Awake、凭证过期提示、插件持久 checkpoint、Burn Down widgets、xKiro / Raycast / Aixy provider、LiteLLM model activity、Claude Admin workspace spend 与 Grok product share；另有 browser-cookie 拒绝状态、credential 原子替换、QuickJS-NG 内存安全修复、Antigravity 部分历史下界、Mistral token coverage、Codex 成本与 reset 修正。
- v0.68.0 增加 Mistral Vibe Monthly Plan、ClinePass 复用已有 Cline session、Muse Code 可选 team quota、Homebrew cask 更新入口、plugin form POST / enrichment / 时区月份逻辑；另有 Codex daemon symlink / Dashboard 链接修复、菜单栏稳定性、Claude credential cache、Venice Clerk session、Nous 计费 activity、Cursor all-history 日期边界与 plugin worker retry 修复。
- 上游 release notes 的纯 macOS AppKit、Homebrew、CLI、Linux 和本地设置功能由 Mac 同步完整承接。iOS 只映射跨设备可见的 provider quota、balance、cost、usage details 与账户身份；不把 Mac 凭证、用户同意状态或本地设置文件同步到 iPhone。

## 关键风险与证据边界

- 上游范围跨度不大但源代码重构面很广：插件声明/运行时、provider specs、Usage & Spend、widgets 和安全文件写入都有变更；冲突解决必须对照 fork-owned seams，不可用整文件 ours/theirs 粗略覆盖。
- iOS 复用 provider 通用 ID、`rateWindows`、`providerAmount`、`costSummary` 与 generic `details` wire；xKiro、Raycast、Aixy 及 Grok/LiteLLM/Claude Admin 展示已按 Mac `SyncCoordinator` → iOS model/view/localization 审计，并由定向 iOS 测试覆盖。兼容矩阵结果及替代验证边界记录在 `03-testing.md`。
- quota warning 沿用已有 `QuotaTransition` record type、已部署字段与 subscription predicate；每用户 private-zone / zone-subscription 实例属于运行时数据，不是 Dashboard schema。本轮对照 CloudKit 代码结论为 `NO_DEPLOY`；没有读取或写入 Production。
- 双 Mac × 双 iPhone 的真实 Production 环境矩阵若无法获得设备和 owner-account 状态，16 组合必须逐行标 `substituted`，使用隔离 fixtures / Simulator / code audit，并写明真实设备与 silent push 残余风险。
- 用户已明确授权 Mac release 和对应 issue 的关闭；仍须先满足 PR 当前 head review / CI gate，之后按仓库 release checklist 合并并完成 Mac 签名、公证、draft 和 live release。TestFlight upload 与 CloudKit schema deploy 不在授权范围内。

## 文档索引

- [01-design.md](01-design.md)：合并、iOS bridge、版本、发布与验证决策。
- [03-testing.md](03-testing.md)：16 组合矩阵和最终测试证据。
- [04-upstream-release-notes.md](04-upstream-release-notes.md)：v0.67.0 / v0.68.0 发布说明人工复核。
- [05-upstream-commits.md](05-upstream-commits.md)：release tag、commit range 和重点 PR/commit。
- [06-ios-impact-audit.md](06-ios-impact-audit.md)：iOS 数据通道和 CloudKit 影响清单。
- [02-implementation.md](02-implementation.md)：待 implementation 阶段填写。
