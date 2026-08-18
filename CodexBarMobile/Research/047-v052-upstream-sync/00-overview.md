# v0.52.0 Upstream Sync + iOS 1.21.0 概览

Status: `done`
Date: 2026-08-17
Branch: `upstream-sync/v0.52.0-mobile.1.21.0`

## 结论

本轮以 `version.env` 的 `UPSTREAM_VERSION=v0.49.2`、
`UPSTREAM_SYNC_DATE=2026-08-11` 为真实 fork 基线，以
[`steipete/CodexBar` GitHub Releases](https://github.com/steipete/CodexBar/releases)
为上游事实源。open upstream-sync issues #82–#88 覆盖 `v0.49.3`–`v0.51.0`；
Goal 启动时上游已正式发布尚无 monitor issue 的
[`v0.52.0`](https://github.com/steipete/CodexBar/releases/tag/v0.52.0)。因此本轮一次性
同步 `v0.49.3`、`v0.49.4`、`v0.49.5`、`v0.49.6`、`v0.50.0`、`v0.50.1`、
`v0.51.0`、`v0.52.0`，不拆成多个用户可见版本。

目标版本为 Mac `0.52.0.1 (124.1)`、iOS `1.21.0 (194)`、Sparkle version
`124.1.1.21.0`，candidate tag `v0.52.0.1-mobile.1.21.0`。iOS `MARKETING_VERSION`
继续使用尚未完成 public release 的 `1.21.0`；本轮新增内容合并进既有 1.21.0 release
notes block，只增加 `CURRENT_PROJECT_VERSION`，不创建 1.22.0。

本轮已在目标分支完成 merge、Mac/Shared/iOS integration、Mac 与 iOS 测试、CloudKit
Production schema 审计、16-case substituted compatibility gate、循环 review、Developer ID
签名与 Apple notarization，并创建仅 draft 的 GitHub release：
[`CodexBar 0.52.0.1-Mobile 1.21.0`](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-9d15f5c94de6761c5243)。
没有 push branch、merge、创建/推送 tag、发布 live release、更新 live appcast、上传 TestFlight
或执行 CloudKit deploy；issues #82–#88 留待最终 merge/publication 后再关闭。

## 分支证据

开始时 worktree clean，`mobile-dev`、`origin/mobile-dev` 均为
`32283fd0cbeb5958eb23f091ce9622c8fe12861d`。执行：

```text
git fetch origin --prune
git switch mobile-dev
git pull --ff-only origin mobile-dev
git switch -c upstream-sync/v0.52.0-mobile.1.21.0
```

分支建立后的 merge-base、`mobile-dev` 和 branch HEAD 均为 `32283fd0c...`。后续 Research、
merge、实现、测试、版本号与 draft release 准备只在该分支进行。Goal 已确认单版本设计；
禁止 push、merge、published tag、live release、appcast publication、TestFlight upload 与
CloudKit Production deploy。

## issue 范围

| Issue | Release | 状态与本轮处置 |
|---|---|---|
| [#82](https://github.com/o1xhack/CodexBar-Mobile/issues/82) | `v0.49.3` | 纳入 `v0.52.0` train |
| [#83](https://github.com/o1xhack/CodexBar-Mobile/issues/83) | `v0.49.4` | 纳入 `v0.52.0` train |
| [#84](https://github.com/o1xhack/CodexBar-Mobile/issues/84) | `v0.49.5` | 纳入 `v0.52.0` train |
| [#85](https://github.com/o1xhack/CodexBar-Mobile/issues/85) | `v0.49.6` | 纳入 `v0.52.0` train |
| [#86](https://github.com/o1xhack/CodexBar-Mobile/issues/86) | `v0.50.0` | 纳入 `v0.52.0` train |
| [#87](https://github.com/o1xhack/CodexBar-Mobile/issues/87) | `v0.50.1` | 纳入 `v0.52.0` train |
| [#88](https://github.com/o1xhack/CodexBar-Mobile/issues/88) | `v0.51.0` | 纳入 `v0.52.0` train |
| monitor 尚未生成 | `v0.52.0` | Releases 权威事实补入同一 train |

Issues 中写的“当前基线 v0.47.0”已经过时；仓库权威字段显示本轮实际起点为
`v0.49.2`。历史 closed upstream-sync issues #77–#81 与 Research 046 证明前一 train 已同步并
发布至 `v0.49.2`，本轮不重复评估 `v0.48.0`–`v0.49.2`。

## 上游 provenance

| Release | Published UTC | 主要范围 |
|---|---:|---|
| `v0.49.3` | 2026-08-12 18:12 | symlink CLI resource、layout drag、history no-op writes、OpenRouter/Codex cost/store 修复 |
| `v0.49.4` | 2026-08-13 16:47 | Ghostty、CZK、Codex reset、Ollama/Claude recovery、cost/history、PTY teardown |
| `v0.49.5` | 2026-08-14 01:49 | OpenCode/Grok、Settings Space、Codex indexing、EDU limit、menu/cost、Claude authority |
| `v0.49.6` | 2026-08-14 09:28 | Antigravity idle lanes、pace、Amp/Ollama、history retention、Claude CLI cache、Linux stability |
| `v0.50.0` | 2026-08-15 07:40 | Cursor local session、Tokens/Cost chart、run-out token、widgets、status/error fixes |
| `v0.50.1` | 2026-08-16 18:11 | Kiro re-auth、provider accent sync、workday ticks、Claude scoped quota、13 provider/cost/privacy fixes |
| `v0.51.0` | 2026-08-16 20:36 | session cost breakdown、Keychain no-UI hardening、OpenCode Go estimated labels |
| `v0.52.0` | 2026-08-17 11:24 | project/session cost breakdown、Projects panel、Mission Control、chart localization、Grok tier |

`v0.49.2` peel 为 `330ae4384b182e531c483fa9d132ea85a74c204b`；`v0.52.0` peel 为
`dc3ea3206c705b8b2ee19f3e2759d43c944a602a`。区间包含 294 个 non-merge commits。
`v0.52.0` 上游 `version.env` 为 `MARKETING_VERSION=0.52.0`、`BUILD_NUMBER=124`。

已核相关 upstream PR/commit 包括：provider accent colors
[#2972](https://github.com/steipete/CodexBar/pull/2972) (`20aee7c...`)、project spend model
[#2984](https://github.com/steipete/CodexBar/pull/2984) (`dbd54a8...`)、Projects pane
[#2985](https://github.com/steipete/CodexBar/pull/2985) (`03047cd...`)、chart localization
[#2983](https://github.com/steipete/CodexBar/pull/2983) (`45ca0b4...`) 和 Grok plan
[#2991](https://github.com/steipete/CodexBar/pull/2991) (`f3f3cce...`)。其余 release-note PR
按各 release 的 GitHub body 与 `v0.49.2..v0.52.0` commit history 追踪。

## Mac 完整同步范围

- 保留全部 provider、cost/history、widgets、settings、Keychain、PTY、CLI、packaging、Linux
  与 localization 变更，而不是 cherry-pick 少量用户可见功能；
- 重点验收 provider accent colors 与三态跨 Mac intent、workday tick preferences、Claude
  model-scoped weekly widget rows、Cursor/Vertex/OpenCode/Grok semantic fixes；
- 重点验收 Codex project/session cost attribution、cache fingerprint、dashboard/menu parity；
- 重点验收 Keychain background no-UI、Settings/Mission Control 生命周期、CLI symlink resources、
  release checksum 与 packaged launch smoke；
- 冲突时保留 fork 的 Mobile sync、CloudKit Production、composite version、release/appcast、CI
  trigger policy、parser hash policy和 iOS bridge，再将上游新语义移植进 fork owner。

merge-tree 预演显示 14 个冲突路径/类型：`AGENTS.md`、root `CHANGELOG.md`、`CLAUDE.md`
文件类型、`README.md`、两项 fork CI scripts、`CodexbarApp.swift`、`UsageStore+Refresh.swift`、
parser hash、Codex descriptor、cost pricing、Linux pipe test、`appcast.xml`、`version.env`。
正式 merge 必须逐项解释，不能整批 ours/theirs。

## iOS / Shared 初步结论

上游没有新增 first-party provider ID，也没有直接修改 fork-owned
`Shared/iCloud/CloudConstants.swift` 或 Mobile `ProviderUsageSnapshot` wire。上游新
`ProviderIntentPayload.accentColor`、`SyncedPreferences.workdayTickAppearance` 属于默认关闭的
Mac fleet `CodexBarSync` 通道，不进入 iPhone 的 `DeviceProviderSnapshot.payload`；其字段都是
optional/三态兼容，旧 Mac 不会清除新 Mac 设置。

iOS 本轮仍需支持从新 Mac 投影出的用户可见语义：Claude model-scoped weekly
`extraRateWindows`、Cursor included-usage 新标签、Vertex 无 `limit_name` 的恢复数据、
OpenCode Go estimated/local-only 标记、Grok plan/display label、Antigravity idle row filtering。
优先复用已发布的 generic windows/details wire；只有审计证明现有 payload 无法表达且新增
字段不会泄露凭据时才加 additive optional。Codex Projects/Conversations 是 Mac local
cost-history breakdown，当前 Mobile ledger 只有按日/provider/model 的安全 aggregates；不把
项目路径、conversation/session identity 或本地文件元数据同步进 CloudKit。

## CloudKit 初步结论

预期 `NO_DEPLOY`：上游改动只给现有 Mac fleet Codable blob 增加 optional preferences/intent
字段，并调整现有 Mobile payload 的 producer semantics；CloudKit 不解析 blob 内部 JSON。
实现后仍必须从最后 published fork tag `v0.49.2.1-mobile.1.21.0` 到 candidate 运行完整 diff
审计并只读回看 Production schema。如发现新 record type、field、index、zone、subscription、
predicate 或 `providerPayloadVersion` bump，结论升级为 `DEPLOY_REQUIRED` 并停在授权门。

## 主要风险

- P0：merge 覆盖 fork release/CI/CloudKit Production/composite version 约束；
- P0：provider accent/workday preferences 串进 Mobile sync，或旧 Mac 抹掉新值；
- P0：Codex project/session identity、路径或 plugin secrets 被误放进 iPhone payload；
- P1：parser/project attribution 改变却未滚动 fork parser fingerprint；
- P1：新 Mac scoped/estimated/display semantics 在 iOS 被重复、误标或隐藏；
- P1：Mission Control/Keychain/PTY 修复在 fork 冲突解决中退化；
- P1：same-version iOS notes 被错误拆成 1.22.0 或重复 1.21.0 block；
- P2：16-case matrix 若只能 substituted，真实 silent push、CloudKit propagation、background
  convergence 与旧 binary 行为仍有硬件残余风险。
