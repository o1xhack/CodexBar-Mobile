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
`131.1.1.23.0`，candidate tag `v0.56.0.1-mobile.1.23.0`。初始 Goal 允许本地 commits、
签名/公证产物与 GitHub draft；2026-08-30 用户追加授权 push task branch、创建 PR 并完成
Code Review 循环；随后又明确授权 merge、Mac live release 与 iOS App Store Connect
version/build handoff。PR #105 已合并，Mac release 与 appcast 已公开，iOS `1.23.0 (196)`
已上传、处理为 `VALID` 并绑定到四语言 App Store version。CloudKit 审计为 `NO_DEPLOY`，
因此未执行 schema deploy。2026-08-30 用户进一步授权 App Review submission；Apple 已接收
submission，version 与 submission 均为 `WAITING_FOR_REVIEW`。发布方式仍为 `MANUAL`，
iOS public release 未执行。

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
| [#102](https://github.com/o1xhack/CodexBar-Mobile/issues/102) | `v0.54.1` | 纳入 v0.56.0 单一 train；live release 后附证据并 close as completed |
| [#103](https://github.com/o1xhack/CodexBar-Mobile/issues/103) | `v0.55.0` | 纳入 v0.56.0 单一 train；live release 后附证据并 close as completed |
| [#104](https://github.com/o1xhack/CodexBar-Mobile/issues/104) | `v0.55.1` | 纳入 v0.56.0 单一 train；live release 后附证据并 close as completed |
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

## 发布闭环（2026-08-30）

- PR [#105](https://github.com/o1xhack/CodexBar-Mobile/pull/105) 在 exact-current
  Code Review gate（15 rounds、0 unresolved、最终 `Didn't find any major issues`）通过后合并；
  merge commit `9f3b28746ca74222e08bd8a2703d96c305546a26`；
- merge-only [Final CI 33343515532](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/33343515532)
  全绿：lint、Linux x64/arm64/musl、6/6 macOS Swift Test 与 aggregate gate 全部 success；
- 从最终 `mobile-dev` 重建而非复用旧 draft：Apple notary submission
  `f19497f4-fc65-4295-af1d-2e54ef67480f` 为 `Accepted`，stapler、Gatekeeper、direct launch
  smoke 全部通过，artifact 内嵌 `CodexGitCommit=9f3b28746`；
- Mac [live release](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.56.0.1-mobile.1.23.0)
  已公开，zip/dSYM 的远端 digest/size 与本地一致；live appcast 经 enclosure 回下载、EdDSA 与
  length 验证后，以 `d3b30a48a` 提交到 `mobile-dev`；
- App Store Connect 已创建 iOS `1.23.0`（`MANUAL`），保存 en-US、ja、zh-Hans、zh-Hant
  四语言 `What's New`；Archive `1.23.0 (196)` 上传后为 `VALID` / `APP_STORE_ELIGIBLE`，
  并双向回读确认绑定到该 version；
- source 1024 icon、Archive 120 icon 与 Apple CDN 152 icon 三层视觉/尺寸验证通过；Archive
  entitlement 回读为 CloudKit `Production`；
- #102-#104 均附 release/ASC/CloudKit 证据并 close，当前 open `upstream-sync` issue 为 0；
  原 task branch 在合并、发布和证据回读后从 local/origin 清理；
- 初始 closeout snapshot 由 PR #106 merge commit `0a7e5adac` 在
  `2026-08-31T03:04:28Z` 固化：version 为 `PREPARE_FOR_SUBMISSION` / `MANUAL`，
  尚无 review submission；
- 后续 App Review submission `3d68c4ed-ad43-4ec1-b066-d945e01d019e` 于
  `2026-08-31T03:19:07.901Z` 提交；submission 与 version 均回读为 `WAITING_FOR_REVIEW`；
  `MANUAL` release 保持不变，未公开 iOS。
