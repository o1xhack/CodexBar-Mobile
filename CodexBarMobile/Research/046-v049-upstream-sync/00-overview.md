# v0.49.2 Upstream Sync + iOS 1.21.0 概览

Status: `done`
Date: 2026-08-11
Branch: `upstream-sync/v0.49.2-mobile.1.21.0`
Open issues:
- [#77](https://github.com/o1xhack/CodexBar-Mobile/issues/77) — upstream `v0.48.0`
- [#78](https://github.com/o1xhack/CodexBar-Mobile/issues/78) — upstream `v0.48.1`
- [#79](https://github.com/o1xhack/CodexBar-Mobile/issues/79) — upstream `v0.49.0`
- [#80](https://github.com/o1xhack/CodexBar-Mobile/issues/80) — upstream `v0.49.1`

## 结论

本轮以 `version.env` 的 `UPSTREAM_VERSION=v0.47.0` /
`UPSTREAM_SYNC_DATE=2026-08-03` 为 fork 基线，以
[`steipete/CodexBar` GitHub Releases](https://github.com/steipete/CodexBar/releases)
为上游事实源。open issues #77–#80 覆盖 `v0.48.0`–`v0.49.1`；Goal 启动时上游已经发布
[`v0.49.2`](https://github.com/steipete/CodexBar/releases/tag/v0.49.2)，monitor 尚未来得及
生成 issue。按“所有 open upstream-sync scope 合并为一个用户可见版本”的约束，本轮一次
同步 `v0.48.0`、`v0.48.1`、`v0.49.0`、`v0.49.1` 和 `v0.49.2`，不拆版本。

目标版本为 Mac `0.49.2.1 (116.1)`、iOS `1.21.0 (193)`、Sparkle version
`116.1.1.21.0`，candidate tag `v0.49.2.1-mobile.1.21.0`。所有调研、merge、实现、测试、
签名公证、draft release 与 review 都只在上述 upstream-sync 分支进行。

## 分支证据

开始时 worktree clean，`mobile-dev`、`origin/mobile-dev` 均为 `d874facd8`。执行：

```text
git fetch origin --prune
git switch mobile-dev
git merge --ff-only origin/mobile-dev
git switch -c upstream-sync/v0.49.2-mobile.1.21.0
```

分支建立后才写 Research 与实现文件。Goal 已明确确认按单版本同步方案执行。push、merge、
published tag、live Mac release、appcast publish、TestFlight upload、App Store submission
和 CloudKit Production deploy 均不在授权范围。

## 权威基线与目标

| 字段 | 基线 | 目标 |
|---|---|---|
| Mac `MARKETING_VERSION` | `0.47.0.1` | `0.49.2.1` |
| Mac `BUILD_NUMBER` | `111.1` | `116.1` |
| `MOBILE_VERSION` | `1.20.0` | `1.21.0` |
| `UPSTREAM_VERSION` | `v0.47.0` | `v0.49.2` |
| `UPSTREAM_SYNC_DATE` | `2026-08-03` | `2026-08-11` |
| iOS 工程版本 | `1.20.0 (192)` | `1.21.0 (193)`，全部 targets 一致 |
| Sparkle version | `111.1.1.20.0` | `116.1.1.21.0` |

## 上游范围与 provenance

| Release | Published UTC | 主要范围 |
|---|---:|---|
| `v0.48.0` (`BUILD_NUMBER=112`) | 2026-08-07 07:34 | provider plugin/QuickJS 基础、declarative details、serve dashboard、usage heatmap、Kimi/GLM routing、CLI/config→fleet sync、cost/cache/widget/security 修复 |
| `v0.48.1` (`BUILD_NUMBER=113`) | 2026-08-08 00:14 | 修复 packaged-app resource bundle 启动崩溃；dashboard progressive cache |
| `v0.49.0` (`BUILD_NUMBER=114`) | 2026-08-09 15:55 | Fireworks、IBM Bob、Linux QuickJS、Codex SQLite cost store、Claude credential consent/fallback、PTY/actor isolation/transaction/performance/security 修复 |
| `v0.49.1` (`BUILD_NUMBER=115`) | 2026-08-10 05:57 | DeepInfra/z.ai/Codex/DeepSeek fixes、Dock/update 可见性、Claude CLI fallback、SSH settings |
| `v0.49.2` (`BUILD_NUMBER=116`) | 2026-08-11 03:32 | multi-Mac account dedupe、quota lane correctness、localized menu layout、plugin fill direction、Sub2API summary、cost/agent-session idle CPU reductions |

`v0.49.2` 是 annotated tag；本地 collision-safe ref 为
`refs/upstream-tags/v0.49.2`，tag object `9d4d693b...`，peel 后 release/appcast commit
`330ae4384b182e531c483fa9d132ea85a74c204b`。`v0.47.0` 是其祖先。区间包含 187 个
non-merge commits、954 个文件，约 144,444 行新增 / 21,873 行删除。大头是 vendored
QuickJS 与 provider plugin runtime，必须用 provenance-preserving merge，不能用少量
cherry-pick 冒充完整同步。

上游 tag 历史有一个已核验的非线性例外：`v0.48.1` peel `226085b80f24…` 不是最终
`v0.49.2` HEAD 的祖先；最终 release line 使用 replay commit `44a6c69726…`，两者的 appcast
patch-id 均为 `4699dfda…`。因此内容没有缺失，但不能声称五个 release tag commits 全部
线性可达。`v0.48.0`、`v0.49.0`、`v0.49.1`、`v0.49.2` peel 均为 candidate HEAD 祖先。

`git merge-tree --write-tree HEAD refs/upstream-tags/v0.49.2` 预演得到 50 个 conflicts：
fork `AGENTS.md` / CI / lint / release / changelog / appcast / version、23 个 Mac locale、
CloudSync、provider declarative details、parser/cache/SQLite、widget bridge 及相关 tests。

## Mac 完整同步范围

Mac 必须保留整个 upstream tag 的功能、修复、性能与安全变更，重点包括：

- provider plugins：manifest-driven JS/TS provider、QuickJS/JSC engine、network/cookie
  permission、generic detail rows/charts、packaged resources 与 Linux parity；
- provider/model：Fireworks 与 IBM Bob；Kimi/GLM region and pool、Command Code、Codex
  quota/reset/cost、Claude OAuth/CLI、OpenRouter、Sub2API、z.ai、DeepInfra 等修复；
- data contract：CLI/serve/synced snapshot 从 provider-specific keys 迁向 generic
  `usage.details`，provider config 从 first-party enum 扩展为 `ProviderInstanceID`；
- cost/history：Codex SQLite store、transaction/corruption/retention/append-linear catch-up、
  activity heatmap 与 bounded cache；
- reliability/security：PTY bounded process-group kill 与 drain、serve header limits、resource
  bundle safe lookup、QuickJS stack/actor isolation、widget I/O timeout、dormant scheduler/CPU
  reduction；
- multi-Mac sync：CLI/config file edits push、provider instance identity、同账户跨 Mac 去重；
- upstream tests、CLI、packaging smoke、documentation 与 localization。

fork 冲突必须继续保留：Mobile sync、CloudKit Production/container、Mac fleet sync 与
Mobile sync 的语义隔离、composite version/appcast、Developer ID release pipeline、fork CI
trigger policy、iOS bridge、已发布 provider hotfix 与 parser hash policy。

## iOS / Shared 初步影响

本轮必然触发 `docs/ios-sync-compatibility-testing.md`：上游直接改变 provider identity、
synced snapshot details、Mac fleet CloudSync 与同账户多 Mac dedupe；fork 还需要把这些数据
安全投影到现有 Mac→CloudKit→iOS payload。

| 变更 | iOS / wire 决策 |
|---|---|
| Fireworks | 新 first-party provider ID；增加 notification tail entry、mock、color、identity 和 balance/spend card 映射 |
| IBM Bob | 新 first-party provider ID；generic rate windows/details，补 provider contracts |
| provider plugins | plugin IDs 为动态 `ProviderInstanceID`，不能扩成 iOS 编译期 enum；以 optional generic detail payload + stable raw ID 降级展示 |
| breaking `usage.details` | fork Mobile payload 不能删除旧 typed fields；新增 generic details 为 additive optional，保持 old iOS 可读 generic windows/旧字段 |
| ProviderInstanceID | Mac fleet 可同步 plugin/extension instances；Mobile notification whitelist 仍只 tail-append first-party providers，未知 instance 走 safe generic card，不改订阅 ID |
| v0.49.2 multi-Mac dedupe | fork Mobile writer/reader 必须继续按 device + provider + account identity 稳定聚合，不能让 fleet AccountSnapshot 和 Mobile snapshot 双计数 |
| SQLite cost store / heatmap | Mac local storage 不直接同步；现有 Cost Summary/ledger 只消费安全 aggregate，不把 SQLite rows、local paths 或 plugin secrets 进 CloudKit |
| plugin config/secrets | 仅 Mac fleet contract；iOS 不读取 ProviderIntent/pluginSecrets，未知 extension values 必须 ignored/redacted |

所有新字段必须 optional 且显式 `decodeIfPresent`；不删除或重命名已发布 Mobile wire keys，
不 bump `providerPayloadVersion`，除非实现审计证明现有 decoder 无法安全承载。旧 Mac/新
iPhone、新 Mac/旧 iPhone 和两台不同 writer 的组合均要进入 16-case gate。

## CloudKit 初步结论

预期 `NO_DEPLOY`，但必须以 tag→candidate diff 和 Production export 回读核验：

- `v0.47.0` release 已部署 `CodexBarSync` zone 所需的 `AccountSnapshot`、`Device`、
  `Preferences`、`ProviderIntent` 与 Mobile `ProviderAccountLinkage`；
- 本轮 upstream changes 主要改变这些 records 内部的 Codable payload / provider raw ID，
  以及现有 record 的写入/去重逻辑；
- fork 新 iOS bridge 计划只在现有 `DeviceProviderSnapshot.payload` opaque zlib JSON 中加
  optional keys；CloudKit 不解析这些 bytes；
- 若 merge 后出现新 CKRecord type、field、zone、index、subscription 或 predicate field，
  结论立即升级为 `DEPLOY_REQUIRED` 并停在授权门，不执行 Production deploy。

## 主要风险

- P0：upstream plugin/provider-instance migration 删除或改写 fork Mobile 已发布 typed wire；
- P0：Mac fleet `AccountSnapshot` 与 fork Mobile snapshots 串线或双计数；
- P0：fork CI/release/CloudKit Production assets 被 upstream workflow/profile/appcast 覆盖；
- P1：provider config migration 丢失 fork existing provider settings/hotfix；
- P1：plugin secrets/extension values 意外进入 Mobile payload；
- P1：v0.49.2 dedupe 只按 provider/raw email，误合并 distinct account/device；
- P1：Fireworks/IBM Bob 没进入 iOS tail whitelist/mock/color/card contracts；
- P1：parser/cache/SQLite migration 未同步 bump parser logic/hash；
- P1：packaged QuickJS/Core resources 或 release zip 启动失败；
- P2：16 组合若只能 substituted，silent push、真实 CloudKit propagation、background
  convergence 与旧 iOS binary 行为仍未实测。

## 授权边界

本 Goal 授权本地分支、Research、merge、代码、测试、本地 commits、签名/公证 candidate、
GitHub draft release 与资产上传。禁止 push、merge、published tag、live release、appcast
publish、TestFlight/App Store upload 和 CloudKit Production deploy。

`Scripts/release.sh` phase 1 会创建并 force-push tag，不适用于本轮 no-push 边界；候选应
运行 `Scripts/sign-and-notarize.sh`，再用 GitHub draft API 创建 untagged draft、上传 ZIP
和 dSYM。`target_commitish=mobile-dev` 只是 draft 占位，最终 publish 前必须从真实 merged
commit 重打包并替换资产。绝不运行 `release.sh --finalize`。

## 完成结论

本轮已在目标分支完成单 train 同步、Shared/iOS bridge、版本与 4 语言文案、全量回归、
Production CloudKit `NO_DEPLOY` 审计、签名公证和 GitHub draft。代码候选 HEAD 为
`37d46edec`；Mac `8796` tests / `851` suites、iOS xcresult `632` tests 均为 0 failure。
GitHub draft 为
[`untagged-d5c3a3e0664b621f548b`](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-d5c3a3e0664b621f548b)，
保持 `draft=true` / `published_at=null`。本地/远端 candidate tag、远端同步分支、appcast
变更、live release、TestFlight 与 CloudKit deploy 均为 0；没有 merge 到 `mobile-dev`，也
没有 push branch/tag。本轮唯一 merge 是任务分支内的 provenance merge `a75be5a4b`。
