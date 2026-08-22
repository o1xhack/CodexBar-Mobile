# v0.54.0 Upstream Sync + iOS 1.21.0 概览

Status: `done`
Date: 2026-08-21
Branch: `upstream-sync/v0.54.0-mobile.1.21.0`

## 结论

本轮以 `version.env` 的 `UPSTREAM_VERSION=v0.52.0`、
`UPSTREAM_SYNC_DATE=2026-08-17` 为 fork 基线，以
[`steipete/CodexBar` Releases](https://github.com/steipete/CodexBar/releases) 为上游事实源。
open upstream-sync issue [#95](https://github.com/o1xhack/CodexBar-Mobile/issues/95) 记录
`v0.53.0`，而 Goal 启动时上游最新正式 release 已是
[`v0.54.0`](https://github.com/steipete/CodexBar/releases/tag/v0.54.0)。因此本轮把
`v0.53.0` 与 `v0.54.0` 合并成一个用户可见 train，不单独发布 `v0.53.0`。

目标版本为 Mac `0.54.0.1 (127.1)`、iOS `1.21.0 (195)`、Sparkle version
`127.1.1.21.0`，candidate tag `v0.54.0.1-mobile.1.21.0`。iOS 继续复用尚未完成 public
release 的 `1.21.0` marketing version；所有新增说明合并进唯一的 1.21.0 notes block。

## 分支证据

开始时从最新 `origin/mobile-dev=cadf27e6009c70c683122622f2ed321d2e608b17` fast-forward，
再创建 `upstream-sync/v0.54.0-mobile.1.21.0`。分支初始 HEAD 与 `origin/mobile-dev` 相同，
worktree clean。后续 Research、merge、实现、版本和测试只在该分支进行。

本轮未授权 push、PR merge、published tag、live Mac release、appcast publication、
TestFlight upload 或 CloudKit Production deploy。

## Issue 范围

| Issue | Release / defect | 本轮处置 |
|---|---|---|
| [#95](https://github.com/o1xhack/CodexBar-Mobile/issues/95) | upstream `v0.53.0` | 纳入 v0.54.0 train；PR 只关联，不提前关闭；Mac public release 公开后回复 release 链接并手动 `Close as completed` |
| [#97](https://github.com/o1xhack/CodexBar-Mobile/issues/97) | macOS 27 Settings 无法打开 | 由 upstream #3029 修复，并纳入完整 sync 与 Settings 回归 |
| monitor 尚未生成 | upstream `v0.54.0` | Releases 权威事实补入同一 train |

历史 closed issues #82–#88 与 Research 047 证明前一 train 已发布至 `v0.52.0`，本轮不重复
处理 `v0.49.3`–`v0.52.0`。

## 上游 provenance

| Release | Published UTC | 主要范围 |
|---|---:|---|
| `v0.53.0` | 2026-08-18 10:29 | Usage & Spend provenance/coverage/token mix/All-time/OpenCodex；Settings retained controller；CloudKit delegate reentrancy；Grok source；CLI TOON；provider reliability |
| `v0.54.0` | 2026-08-20 13:51 | blank Settings window；RPC pipe crash；conditional menu tokens；Grok/xAI spend；historical pricing；OpenRouter/OpenCode/Codex sources；localization |

`v0.52.0` tag commit 为 `5a1e104e31e7a5783a2cfadef34ed06001aa39a3`；`v0.54.0` 的
annotated tag object 为 `1181138acf3ebcfc40c827ecd89d2002a6c5b03a`，peeled commit 为
`22a2168842a9ed4fdd15dd6761cd109c56bcd3b5`。区间包含 131 个 non-merge commits、354 个
changed files、28,134 insertions 与 2,233 deletions。上游 `v0.54.0/version.env` 为
`MARKETING_VERSION=0.54.0`、`BUILD_NUMBER=127`。

## Mac 同步范围

- 保留完整 upstream Settings、Usage & Spend、provider、menu layout、CLI、Linux、reliability、
  performance、安全与 localization 改动；
- issue #97 的 #3029 retained Settings controller 与 v0.54 #3056 placeholder-window guard 必须一起
  保留，并验证 menu、`Command-,`、重复打开、active Space 与 launch 不出现空白窗口；
- CloudKit #3030 只改变 CKSyncEngine delegate event 调度，预期无 wire/schema 变化，但必须验证 fork
  Mobile sync 与 Mac fleet sync 均不退化；
- 冲突时保留 fork release/appcast/composite version、CI trigger policy、Production entitlements、
  Mobile sync、parser fingerprint 与 iOS bridge，并逐项吸收上游语义。

merge-tree 预演 v0.53.0 已出现 13 个冲突；v0.54.0 范围更大，不能整批采用 ours/theirs。

## iOS / Shared 初步影响

完整 v0.54.0 不是 iOS `NO_IMPACT`：

- upstream cost models 新增 provenance、coverage、partial totals、metered cost、token mix 与 reasoning
  tokens；当前 Mobile `SyncCostSummary` 尚不能完整表达这些语义；
- Grok/xAI、OpenRouter、OpenCode Go 与 OpenCodex 会改变新 Mac 产生的 provider/cost 数据，需确认
  既有 generic details / rate windows / cost summary 能否安全投影；
- conditional menu tokens、Settings 与 Mac-only dashboard UI 不进入 iPhone；project/session/path、
  auth source、credential 与 raw OpenCodex local metadata不得进入 CloudKit；
- 若现有 wire 会把 partial/estimated 数据误呈现为完整金额，则新增 additive optional payload 字段，
  old reader 通过 `decodeIfPresent` 保持兼容，并执行 16-case compatibility gate。

## CloudKit 初步结论

预期 `NO_DEPLOY`：已观察到的 CKSyncEngine 改动没有新增 record type、field、zone、index、query 或
subscription；cost/provider扩展预计只位于既有 opaque payload。实现完成后仍须从最后 published
fork tag到 candidate执行完整 schema diff与 Production只读回看。任何 schema变化均升级为
`DEPLOY_REQUIRED` 并停在单独授权门。

## 主要风险

- P0：大范围 merge 覆盖 fork CI/release/CloudKit/Mobile sync/versioning；
- P0：iOS 把 partial cost 或未知 provenance 显示成完整、确定账单；
- P1：Settings controller 与 placeholder guard 只合入一半，造成无法打开或启动空白窗口；
- P1：parser/cost cache逻辑变化后 fingerprint/version未滚动；
- P1：Grok/xAI/OpenRouter/OpenCode新数据重复计费、错归账号或丢失；
- P1：Mac fleet CKSyncEngine fix干扰既有Mobile writer生命周期；
- P2：无四台真实设备时兼容矩阵只能 substituted，silent push、真实Production传播与旧binary仍有残余风险。
