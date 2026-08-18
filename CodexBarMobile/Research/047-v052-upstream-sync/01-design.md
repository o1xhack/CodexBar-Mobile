# v0.52.0 Upstream Sync 设计

Status: `done`
Date: 2026-08-17

## 设计决策

Goal 已确认单版本方案。以 published `v0.52.0` tag 做 provenance-preserving merge，完整保留
Mac 上游内容；只在 fork-owned Mobile、CloudKit、CI、release、appcast、composite version
与跨版本 payload 契约冲突时定向整合。

## Merge 策略

1. 在 `upstream-sync/v0.52.0-mobile.1.21.0` 合并 tag `v0.52.0`，保留 merge parent。
2. `AGENTS.md`、CI scripts/workflows 保持 fork policy，同时吸收不改变 trigger model 的上游
   lint/path-gate 改进。
3. root `CHANGELOG.md` 保留 fork release train并合入 `0.49.3`–`0.52.0` upstream sections；
   candidate 阶段不覆盖已发布 `appcast.xml`。
4. 保留 fork `release.sh`、`make_appcast.sh`、`sign-and-notarize.sh`、bundle/team/Production
   entitlements 与 composite build；吸收 checksum、resource、launch-smoke 加固。
5. `CodexbarApp.swift` 保留 Mobile sync/fleet initialization 与 fork lifecycle，再移除上游已废弃
   keepalive window/keychain migration，采用新 Settings opener。
6. `UsageStore+Refresh`、Codex descriptor、cost pricing 与 parser hash 合并两边语义；project
   attribution、pricing、scanner 变化后滚动 fork fingerprint并重生成 hash。
7. locale 自动 merge 后运行完整 localization gate；不得用 ours/theirs 丢 key。
8. Linux test 冲突保留上游 process teardown 覆盖与 fork determinism/CI constraints。

## 双 sync 通道边界

```text
Mac usage/provider snapshots
  ├─ Mobile sync (default on)
  │    └─ DeviceProviderSnapshot payload -> iPhone / iOS widgets
  └─ Mac fleet sync (default off)
       └─ ProviderIntent / Preferences / AccountSnapshot -> other Macs
```

`ProviderIntentPayload.accentColor` 与 `SyncedPreferences.workdayTickAppearance` 只属于第二条
通道。Mobile payload 不复制 provider customization settings。iPhone只读取 render-safe
usage aggregates；credential、cookie、local path、project path、conversation/session identity、
raw API response、plugin permission 和 secret map 永不进入 Mobile payload。

## iOS 适配策略

- Claude scoped weekly quotas：复用 `extraRateWindows` 与 stable ID prefix；iOS详情页、generic
  card 与 widget reducer以 existing unknown-window behavior安全展示，避免专用 wire；
- Cursor：把 Mac 输出的新 Cursor/Third Party 文案作为 generic detail label，旧 Mac labels继续可读；
- Vertex：这是 producer fetch 修复，新 Mac会恢复既有 generic quota window，不增 wire；
- OpenCode Go：若 upstream existing generic details 已携带 estimated/local-only 文案，iOS直接展示；
  若只是 Mac-only decoration且 wire无 semantic，不伪造“confirmed”；
- Grok：现有 rate-window ID、provider details 与 plan tier优先；仅做 normalization/test，避免
  再加 Grok 专用字段；
- Antigravity：沿用 generic extra windows，审计 idle model families在 iOS是否也需要过滤；
- project/session cost：不扩展 CloudKit。iOS保留当前按 provider/model/day aggregate；本轮文案
  不宣称 iPhone支持 Mac Projects/Conversations panel。

只有发现现有 wire确实缺口时才加 optional + `decodeIfPresent` 字段；不得删除或重命名已发布
keys，不 bump `providerPayloadVersion=1`。

## 版本方案

| Artifact | 基线 | 目标 |
|---|---|---|
| Mac `MARKETING_VERSION` | `0.49.2.1` | `0.52.0.1` |
| Mac `BUILD_NUMBER` | `116.1` | `124.1` |
| `MOBILE_VERSION` | `1.21.0` | `1.21.0` |
| iOS `MARKETING_VERSION` | `1.21.0` | `1.21.0` |
| iOS `CURRENT_PROJECT_VERSION` | `193` | `194`，全部 targets |
| Sparkle version | `116.1.1.21.0` | `124.1.1.21.0` |
| candidate tag | `v0.49.2.1-mobile.1.21.0` | `v0.52.0.1-mobile.1.21.0` |
| upstream bookmark | `v0.49.2 / 2026-08-11` | `v0.52.0 / 2026-08-17` |

上游前三段与 integer build采用 tag `v0.52.0` 的 `0.52.0 / 124`；fork仍包含 Mobile bridge、
CloudKit与release pipeline，因此 train首发为 `.1`。iOS按用户要求不升 marketing version，
只把 build `193` 增至 `194`，并合并改写唯一的 1.21.0 in-app notes block。

## 发布与权限边界

- 允许本地 commits、Mac signed/notarized candidate 与 GitHub draft release；
- draft必须明确未发布，不能生成/推送 Git tag，不能更新 live appcast；
- `Scripts/release.sh` phase 1可能 push/force-push tag，不直接使用；候选使用
  `Scripts/sign-and-notarize.sh` 与 draft API上传资产；
- 不 push branch、不 merge、不 publish tag/live release、不上传 TestFlight、不执行 CloudKit
  Production deploy。

## 测试与 review

- merge provenance、conflict audit、fork CI/release/CloudKit/version contracts；
- Mac `swift build`、lint、full unit tests、focused provider/cost/keychain/PTY/settings/sync tests；
- package/sign/notary、codesign、spctl、CLI version/config、launch smoke；不运行会触发真实
  Keychain/browser prompt的 live provider usage；
- Shared/iOS mixed-version fixtures、provider display tests、widget/cost parity、full iOS build/tests；
- 16-case matrix全部列出；硬件不可得时必须用 old/new fixture、dual-writer reducer、cache/delete/
  ghost、simulator与代码审计 substitution，并写剩余风险；
- 每个 merge/bridge/iOS/release阶段自查 diff与独立 code review能力，修复后复测直至 blocker 0。
