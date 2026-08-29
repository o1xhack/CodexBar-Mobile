# v0.56.0 Upstream Sync + iOS 1.23.0 概览

Status: `done`
Date: 2026-08-28
Branch: `upstream-sync/v0.56.0-mobile.1.23.0`

## 结论

本轮以 `version.env` 的 `UPSTREAM_VERSION=v0.54.0`、
`UPSTREAM_SYNC_DATE=2026-08-20` 为 fork 基线，以
[`steipete/CodexBar` Releases](https://github.com/steipete/CodexBar/releases) 为上游事实源。
open upstream-sync issues #102、#103、#104 分别记录 `v0.54.1`、`v0.55.0`、`v0.55.1`；
Goal 启动时上游最新正式 release 已是
[`v0.56.0`](https://github.com/steipete/CodexBar/releases/tag/v0.56.0)。因此本轮把
`v0.54.1`、`v0.55.0`、`v0.55.1`、`v0.56.0` 合并成一个用户可见 release train，
不拆分中间版本。

目标候选为 Mac `0.56.0.1 (131.1)`、iOS `1.23.0 (196)`、Sparkle version
`131.1.1.23.0`，candidate tag `v0.56.0.1-mobile.1.23.0`。本轮允许本地 commits、
签名/公证产物与 GitHub draft；不允许 push branch、merge、tag publish、live release、
appcast publish、TestFlight upload 或 CloudKit Production deploy。

## 分支证据

- `git fetch origin --prune && git switch mobile-dev && git pull --ff-only origin mobile-dev`
  后，`mobile-dev == origin/mobile-dev == c7f61ae60d87ca7011a3b76e4a2cf15220174e37`；
- worktree clean 后创建 `upstream-sync/v0.56.0-mobile.1.23.0`；
- 分支初始 HEAD 为同一 `c7f61ae60`，Research、merge、实现、测试与 release preparation
  全部只在该分支进行；
- `git merge-base HEAD v0.56.0` 为已同步的 upstream `v0.54.0` commit
  `22a2168842a9ed4fdd15dd6761cd109c56bcd3b5`。

## Issue 范围

| Issue | Release | 本轮处置 |
|---|---|---|
| [#102](https://github.com/o1xhack/CodexBar-Mobile/issues/102) | `v0.54.1` | 纳入 v0.56.0 单一 train；draft 阶段保持 open |
| [#103](https://github.com/o1xhack/CodexBar-Mobile/issues/103) | `v0.55.0` | 纳入 v0.56.0 单一 train；draft 阶段保持 open |
| [#104](https://github.com/o1xhack/CodexBar-Mobile/issues/104) | `v0.55.1` | 纳入 v0.56.0 单一 train；draft 阶段保持 open |
| monitor 尚未生成 | `v0.56.0` | 以 GitHub Release 权威事实补入同一 train |

closed issue [#95](https://github.com/o1xhack/CodexBar-Mobile/issues/95) 与 Research 048
证明前一 train 已公开发布至 `v0.54.0`，本轮不重复处理 `v0.53.0-v0.54.0`。

## 上游 provenance

| Release | Published UTC | annotated tag | peeled commit | version / build |
|---|---:|---|---|---|
| `v0.54.1` | 2026-08-23 10:45 | `0ffdf3ee76` | `d6d281e898` | `0.54.1 / 128` |
| `v0.55.0` | 2026-08-24 08:14 | `d86652fd8c` | `061593ca15` | `0.55.0 / 129` |
| `v0.55.1` | 2026-08-26 06:12 | `f1c2e443de` | `10587234b5` | `0.55.1 / 130` |
| `v0.56.0` | 2026-08-28 16:28 | `277ccd49a5` | `fc1bd0d797` | `0.56.0 / 131` |

`v0.54.0..v0.56.0` 共 124 commits，其中 114 个 non-merge commits、432 个 changed
files、37,021 insertions 与 3,762 deletions。发布范围中的关键实现映射包括：

- Claude Swap slot-key CloudKit migration：#3111 / `416ef870aa`；
- Claude slot identity/display separation：#3082 / `63bf039cc0`；
- Codex CLI 0.149 approval compatibility：#3118 / `4394708cc5`；
- Spend parallel load：#3105 / `1cf98b330a`；
- persistent priority cursor：#3130 / `df18670d61`；
- Cursor/Antigravity local history readers：#3113 / `7427660af2`；
- OpenCodex pricing/incremental performance：#3136 / `d8d03a1221`、#3140 / `17ade2b11a`；
- Codex early reset recovery：#3177 / `0a1aa53598`；
- Antigravity SQLite history：#3212 / `d94c71acfc`；
- Cursor estimated cost/coverage：#3129 / `5b8602981b`；
- CLI installer shell isolation：#3217 / `0b54a928ff`；
- Codex JWT expiry：#3222 / `53be40244`；
- WebView ownership/cleanup：#3252 / `6907103580`。

## Mac 同步范围

### `v0.54.1`

- Codex CLI 0.149 read-only approval compatibility、profile/account isolation；
- layout editor drag/drop、agent session width、简中窗口文案；
- Alibaba `SEC_TOKEN` 与 retry、Cursor Grok Bot、Codex monthly credits；
- Claude Swap slot migration、Kiro overage、z.ai balance；
- Codex priority cursor 与 Spend dashboard parallel load。

### `v0.55.0`

- ChatGPT.app 内置 Codex adaptive refresh；
- Antigravity `agy` CLI/offline fallback、Gemini migration guidance；
- Codex tokscale parity、Warp/single-quota icon、Grok/OpenRouter fixes；
- Cursor/Antigravity local cost readers、timezone-aware spend、CHF；
- OpenCodex pricing performance 与 CLI install robustness。

### `v0.55.1`

- Codex early-reset、cross-relaunch confirmation、spend catch-up；
- Alibaba Bailian CLI-first、Grok account binding/performance、Fireworks spend；
- OpenRouter/Amp/OpenCode Go fixes、OpenCodex append-only scan、AED；
- Claude Swap probe 与 selected-language shortcut recorder。

### `v0.56.0`

- Antigravity SQLite token history 与 unknown/zero distinction；
- Cursor estimated/unpriced/metered cost separation；
- Codex expiry/error/cache/history freshness、Grok account consistency；
- OpenCode Go scale、Claude Extra Usage、OpenRouter cap、menu layout override；
- cached-cost performance、WebView lifecycle 与 CLI installer security hardening。

Mac 端须尽可能完整保留上述功能、修复、性能与安全语义。冲突时保留 fork 的 README、
PR Fast Checks / merge-only heavy CI、release/appcast/composite version、Production entitlements、
Mobile sync 与 parser hash 约束，并逐项吸收上游行为。

## Shared / iOS 影响

本轮不是 `NO_IMPACT`，但不需要新增 provider ID、专用 CloudKit field 或新的 dedicated wire：

- 上游范围未修改 root `Shared/` 或 `CodexBarMobile/`，`UsageProvider` 也没有新增/改名；
- 现有 Mobile envelope 已有动态 `rateWindows`、generic `details`、`costSummary`、
  coverage/provenance/token mix、`providerAmount` 与 `decodeIfPresent` fallback；
- Cursor Grok Bot、Kiro overage/cap/charges、Alibaba Bailian、Fireworks spend、Antigravity/Cursor
  history、z.ai balance可经现有 opaque payload 表达；
- iOS 需要补 v0.56 compatibility fixtures，验证 estimated/unpriced 不显示为确定 `$0`、
  dynamic fourth window、provider-reported spend、Kiro details 与 old payload fallback；
- iOS 需要补 Kiro `Overage`/detail labels 的 4-language localization；`Grok Bot` 保留品牌名并测试；
- project/session/path、raw local history、auth token、cookie、API key、CLI credential、
  Claude predecessor record key 等不得进入 Mobile payload。

## CloudKit 初步结论

预期 `NO_DEPLOY`：Claude Swap migration 在 upstream Mac fleet sync 中复用既有
`AccountSnapshot` record，先保存 slot-key replacement、再删除 email-key predecessor，并把
pending delete/retry 状态持久化在本地；没有新增 CK record type、field、zone、index、query、
subscription 或 `providerPayloadVersion` bump。实现完成后仍须从最后 published fork tag
`v0.54.0.1-mobile.1.22.0` 到 candidate 重跑正式 schema audit 和 Production 只读回看。

## 主要风险

- P0：19 个代码/策略冲突与 `appcast.xml` 单列冲突覆盖 fork CI/release/sync/versioning；
- P0：Claude predecessor 删除顺序错误导致重复卡片、误删或旧 Mac 回写 ghost record；
- P0：estimated/unpriced/unknown cost 在 iOS 被错误显示为确定 `$0` 或完整账单；
- P1：成本 scanner/cache 合并丢失 fair scheduling、coverage、parser hash predecessor；
- P1：CLI installer security 修复被 fork packaging 路径抵消；
- P1：Kiro/新增 detail labels 在中日文 UI 中泄漏英文；
- P2：无 2 Mac + 2 iPhone 实机时 16-case matrix 只能 `substituted`，真实 Production
  propagation、silent push/background convergence 与旧 binary reader 仍有残余风险。
