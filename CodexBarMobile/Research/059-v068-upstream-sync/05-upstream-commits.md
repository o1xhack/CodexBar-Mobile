# v0.66.0→v0.68.0 上游提交与 PR 线索

Status: `done`

## Release anchors

| Tag | GitHub Release 日期 | peeled commit | 上游 build |
|---|---|---|---|
| v0.66.0 (baseline) | 2026-09-24 | `e665cbf64976839dc947e70a942ba8226388d4c9` | 156 |
| v0.67.0 | 2026-09-26 | `e0286a895055e60ddaefa6a5f176f246aa2f05e4` | 158 |
| v0.68.0 (target) | 2026-09-27 | `7998bf66c796befcb91c38e6b1096e702e511481` | 159 |

本地观察到 v0.68.0 tag object `69e3e7f4edbc4fbc3668b77c5e638098a3dfb463`、v0.67.0 tag object `bcf13df472cbd419c16d892ebdbbdb5aa9583e54`。本地验签因缺少 SSH allowed-signers 配置而未完成；GitHub 正式 Release 页面将其发布 tag commit 标记为 Verified。

范围统计：`git rev-list --count --no-merges v0.66.0..v0.68.0` = 105；`git diff --shortstat` = 510 files changed, 28,249 insertions(+), 13,786 deletions(-)。上游 release 说明显示 v0.68.0 的直接前序正式版本是 v0.67.0。

## 重点改动线索

| 主题 | commit / PR | 影响与同步审查重点 |
|---|---|---|
| 新 provider：Aixy / xKiro / Raycast | `f2bb629ce`、`9090006d3`、`9344b7d92`；上游 PR #3958 / #3729 / #3960 | ID、余额/额度、reset、通用 details 和 iOS 可见色彩；quota notifications eligibility 需独立核实 |
| 成本报告期 | `9f76e1194`；PR #3981、#2087/#2859/#1708 | Mac 统一 period selection；审查同步 cost window 与 iOS 现有 Cost Window Ledger 的日界线，不移植 Mac preference file |
| 安全与 QuickJS | `d8c2af958`（PR #3996）、`1d28f0d7b`（PR #3987） | 保留 cookie denial 及 credential atomic staging；保留供应链版本和 fork package guard |
| history / Antigravity / Mistral | `125d7327a`（PR #3963）、`79b38f346`（PR #3974）及 Mistral usage commits | 保留 lower-bound/unknown 语义、multi-window quota、token 不等同于 billed cost |
| Muse team quota | `fe80c80d8`（PR #4011） | 只传所选 team 的安全展示值，不把 cookie 或选择状态写入 Shared |
| Nous / Codex / Cursor cost fixes | `43843393a`（PR #4015）、`d834114ce`（PR #3524）、`a7ad58d61`（all-history） | 验证 provider attribution、fork 累计值与 API 日期边界在 iOS ledger 的表达 |
| ClinePass / Venice / Mistral Monthly Plan | `0ab15e453`、`363e3beaa`、`cff36599f`；PR #4026/#4019/#4025/#4038 | ClinePass 不刷新 credential；Venice cookies 属 Mac auth；Monthly Plan 要进既有 rate-window wire |
| plugin runtime/refactor | `f79561136`（PR #4047）、`c0ded67cd`、`394ed2570` | 保留上游 host form / optional POST / calendar-month / bundle provider spec，检查 merge 未丢 fork SyncCoordinator |
| status item 与取消 worker | `c1f50ac13`、`c72a0e57f`（PR #4032/#4033） | macOS 生命周期安全与 worker 取消是本轮 Mac 回归重点 |

PR 编号取自对应 GitHub Release notes；上表只列影响本 fork 冲突或 iOS 数据面最强的线索，并不替代 merge `v0.66.0..v0.68.0` 完整历史。
