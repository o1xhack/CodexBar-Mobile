# v0.47.0 Upstream Sync + iOS 1.20.0 概览

Status: `done`
Date: 2026-08-03
Branch: `upstream-sync/v0.47.0-mobile.1.20.0`
Open issues:
- [#66](https://github.com/o1xhack/CodexBar-Mobile/issues/66) — monitor 记录的 upstream `v0.46.0`
- [#68](https://github.com/o1xhack/CodexBar-Mobile/issues/68) — monitor 记录的 upstream `v0.47.0`

## 结论

本轮以 `version.env` 的 `UPSTREAM_VERSION=v0.45.2` / `UPSTREAM_SYNC_DATE=2026-07-19`
为 fork 基线，以 `steipete/CodexBar` 的 GitHub Releases 为上游事实源。Goal 启动时
open upstream-sync issue #66 记录了 `v0.46.0`，后续 monitor issue #68 记录了
2026-08-03 发布的 `v0.47.0`。因此本轮按单版本规则一次覆盖 `v0.46.0` 和 `v0.47.0`，
不拆成两个用户可见版本。

目标版本为 Mac `0.47.0.1 (111.1)`、iOS `1.20.0 (192)`，Sparkle version
`111.1.1.20.0`，候选 tag `v0.47.0.1-mobile.1.20.0`。所有调研、merge、实现、测试、
打包和 review 都只在上述 upstream-sync 分支进行。

## 分支证据

开始时 worktree clean，`mobile-dev` 与 `origin/mobile-dev` 都是 `9d9db632`。执行：

```text
git switch mobile-dev
git pull --ff-only origin mobile-dev
git switch -c upstream-sync/v0.47.0-mobile.1.20.0
```

分支创建后才开始写 Research 和实现文件。Goal 已确认本设计，不需要再次暂停征求
实现方案确认。push、merge、published tag、live Mac release、appcast publish、
TestFlight upload 和 App Store submission 均不在授权范围。

## 权威基线

| 字段 | 基线 |
|---|---|
| Mac `MARKETING_VERSION` | `0.45.2.2` |
| Mac `BUILD_NUMBER` | `109.2` |
| `MOBILE_VERSION` | `1.19.0` |
| `UPSTREAM_VERSION` | `v0.45.2` |
| `UPSTREAM_SYNC_DATE` | `2026-07-19` |
| iOS 工程版本 | `1.19.1 (191)`，四个 targets 一致 |
| 最新 published fork release | `v0.45.2.2-mobile.1.19.0` |

## 上游范围和 provenance

| Release | Published UTC | 主要范围 |
|---|---:|---|
| `v0.46.0` (`BUILD_NUMBER=110`) | 2026-07-29 13:50 | Qwen Cloud、ZoomMate、Alibaba Personal/Solo、Claude prepaid balance / Daily Routines、Codex Workspaces foundation、fractional quota；Keychain、profile cache、large corpus、widgets、provider session 和 quota 修复 |
| `v0.47.0` (`BUILD_NUMBER=111`) | 2026-08-03 16:55 | Notion AI、opt-in Mac fleet iCloud sync、Low Power Mode、compact multi-account、monthly pace、xAI billing、z.ai 7d/30d、config file live reload；权限、session file、Keychain、menu rendering、provider windows 和 CloudKit first-contact 修复 |

`v0.47.0` 是 annotated tag，tag object `7e345e5a`，peel 后 release commit
`6a16c23313a782dee6861735116a6c06ec1338fe`。`v0.45.2` 是其祖先。范围包含 400 个
commits（288 个 non-merge commits），674 个文件，约 61,606 行新增 / 6,121 行删除。
这一规模要求 provenance-preserving merge；不能用 feature cherry-pick 替代。

merge-tree 预演给出 41 个 content conflicts，集中在 fork CI、根 CHANGELOG、
`Scripts/package_app.sh`、About/version/appcast、23 个 Mac locale、usage pace、parser
hash/cache、Alibaba hotfix 和相关 tests。冲突处理必须保留 fork 发布、CloudKit
Production、Mobile sync、版本和 CI policy。

## Mac 完整同步范围

Mac 端保留截至 `v0.47.0` 的所有上游功能、修复、性能与安全改动，包括：

- 新 provider：`qwencloud`、`zoommate`、`xai`、`notion`；
- Alibaba mainland/international Personal/Solo Token Plan variants；
- Claude prepaid balance、Daily Routines 可见性、profile-scoped credentials 与
  enterprise extra-usage/widget 修复；
- Codex giant-session resumable scanning、workspace attribution foundation、fork-parent
  discovery budget；
- Low Power Mode、compact multi-account menus、fractional quota/forecast、calendar-month
  pace、menu flicker/layout fixes；
- Keychain-disabled cold boot、in-process process inspection、0600/atomic credential files、
  config redaction 和 external config live reload；
- WidgetKit reload/background、menu rendering、provider cookie/session、reset/window 和
  optional-usage fixes；
- upstream tests、CLI 和 documentation。

## iOS / Shared 影响

| 变更 | iOS / wire 决策 |
|---|---|
| Qwen Cloud | 新 provider ID；5-hour + weekly generic windows、plan identity，可由现有通用 card 表达 |
| ZoomMate | 新 provider ID；除 generic utilization 外保留 credits status、cycle、overage 和 daily history，使用 additive optional typed payload 与专用/复用展示 |
| xAI Platform | 新 provider ID；prepaid balance 用 `SyncProviderAmount`，30-day daily spend 复用 `SyncCostSummary`，不得与既有 `grok` card 合并身份 |
| Notion AI | 新 provider ID；rolling + calendar billing-period windows 与 workspace/account identity，通用 rate-window card 可表达 |
| Claude prepaid balance | 现有 `SyncProviderAmount` 扩展读取 `ProviderCostSnapshot.balance`；同时保留已有 Extra Usage spend-limit card |
| z.ai 7d/30d | 现有 wire 只传 hourly model usage；新增 optional typed daily history 并扩展 iOS range UI，不能继续用 hourly-only mapper |
| Codex Workspaces foundation | 原始 local path、thread/session corpus 与 sidecar 只留 Mac；本轮只同步上游已经投影出的安全 aggregate，不把机器路径放入 CloudKit |
| monthly pace | iOS 当前不预测耗尽时间，只显示同步窗口与 reset；保留真实 `windowMinutes` / reset，不制造 flat-30-day 文案 |
| Alibaba variants | provider ID 不变；plan/login metadata 和窗口继续走现有 `alibabaTokenPlan` / generic wire |
| 上游 Mac fleet sync | 与 fork 既有 Mac→iOS record family 并存；iOS 不重复读取 `AccountSnapshot`，避免同一 usage 双计数 |

四个新 provider 必须 tail-append 到 `QuotaProviderList`，补齐 mock、颜色、identity、
wire round-trip、subscription count 和 card tests。现有 payload version 保持 `1`；所有
新增 Shared 字段必须 optional + `decodeIfPresent`。

Notion 的 workspace name 当前没有独立的 Shared display 字段，需增加 optional
`accountOrganization` 并在新 reader 展示；old reader 忽略它。z.ai daily history 不能复用
当前只接受 hourly `xTime` 的解析路径，必须分别覆盖 `yyyy-MM-dd HH:mm` 与
`yyyy-MM-dd` 输入。

## P0：两个 iCloud sync 的语义隔离

fork 现有 `iCloudSyncEnabled` 默认 `true`，控制 Mac→iOS usage / notification sync。
upstream v0.47 复用了同名 property 与 UserDefaults key，但含义是默认 `false` 的
Mac↔Mac provider config / preferences / encrypted secrets / fleet snapshot sync。直接
merge 会导致现有用户意外开启 secret sync，或关闭新功能时同时切断 iPhone 数据。

本轮必须：

1. 保留现有 `iCloudSyncEnabled`、默认值和 Mobile Settings 行为；
2. 将 upstream 能力隔离为 `macFleetSyncEnabled` 和独立 UserDefaults key，默认关闭；
3. upstream 的 include-secrets、snapshots、fleet-account 开关只从新的 master toggle 生效；
4. Mac UI 清楚区分“Mobile sync”和“Mac fleet sync”，不暴露工程术语；
5. hard-coded `iCloud.com.steipete.codexbar` 改为 fork 的
   `iCloud.com.o1xhack.codexbar`，但 `CodexBarSync` zone 与 upstream record types 保持
   独立；
6. 不提交/采用上游 team `Y5PE65HELJ` 的 provisioning profile，保留 fork signing 和
   Production entitlements。

## CloudKit 初步结论

`DEPLOY_REQUIRED`。upstream fleet sync 在 fork Production container 中新增：

- zone `CodexBarSync`；
- record types `AccountSnapshot`、`Device`、`Preferences`、`ProviderIntent`；
- 多个 encrypted/plain fields。

只读 Production export 还暴露出一个本轮前已存在但未部署的缺口：iOS 的账户合并功能会
读写 `ProviderAccountLinkage`，代码已在 `DeviceProvidersZone` 使用该类型，但 Production
schema 与旧 tracked schema 都没有它。本轮将它与 4 个 fleet types 一并加入完整 tracked
schema；这不是新增产品 scope，而是避免候选 schema 继续漏掉已有 writer contract。

它们不与现有 `DeviceSnapshot`、`DeviceProviderSnapshot`、`QuotaTransition`、
`DeviceLifecycleEvent` 等 record families 重名，但属于真实 CloudKit schema / zone
新增，不能按“opaque JSON optional field”归类为 `NO_DEPLOY`。实际 Dashboard deploy
必须在候选代码、schema、tests 和 Production entitlement 验证完成后单独获得用户授权。

## 风险与 release gate

- P0：两个 sync toggle/key 串线会造成意外 secret sync 或 iPhone 数据中断；
- P0：fork container 缺少 4 个 fleet record types 时启用 fleet sync 会写入失败；既有
  `ProviderAccountLinkage` 缺失时，用户确认的跨版本账户合并也无法落盘；
- P1：上游 fleet snapshots 与 fork Mobile snapshots 双写但不能双读/双计数；
- P1：old/new Mac 同时写不同 record families 时，设备/账户 identity 必须稳定；
- P1：ZoomMate/xAI/Claude monetary values不能渲染成 `$X / $0`；
- P1：四个 provider 的 notification IDs 只能 tail-append；
- P1：z.ai 7d/30d data 若继续走 hourly parser 会静默丢失或日期解析失败；
- P1：parser/cache 文件改动必须 bump `parserLogicVersion` 并重生成 hash；
- P1：上游 provisioning profile、CI/appcast/release scripts 不得覆盖 fork 资产；
- P2：真实 2 Mac × 2 iPhone / silent push / background convergence 可能只能使用
  substituted evidence，必须在 `03-testing.md` 明示剩余风险。

## Published upstream checks

上游 release provenance 可复用，但不能代替 fork-specific gates：

- v0.47 pre-release code commit 的 lint、两片 macOS Swift tests、Linux x64/arm64、
  build/deploy/report checks 均成功；
- tag/appcast commit `6a16c233` 的 Mac/Linux CLI artifact matrix 与 Homebrew update 成功；
- tag tip 的 generic heavy run 被后续工作 supersede/cancelled，所以不能声称“tag tip
  all checks green”；本 fork 仍执行完整 local build/lint/tests/release gate。

## 授权边界

Goal 启动时只允许本地分支、Research、merge、代码、测试、本地 commits、签名/公证
candidate、GitHub draft release 和本地 candidate appcast 证据。后续用户分别明确授权了
push / PR / merge、Mac live release、iOS upload / App Store submission，以及 CloudKit
Production schema deploy；因此这些步骤均在授权后执行。iOS 采用 manual release，Apple
审核通过后的 App Store 公开发布不在本轮自动执行范围。

## 候选阶段完成状态（2026-08-03）

- semantic merge、fork integration、Shared/iOS bridge、版本与四语言 release notes 均已
  在目标分支完成；最终文档提交前 candidate source commit 为
  `151a17ae43c3e1be9070d852efca2749e49ca719`；
- Mac full suite、iOS full unit、Release simulator build、lint、schema validation 与
  16-case substituted compatibility matrix 全部通过；最终独立 review 为
  `P0=0 / P1=0 / P2=0 / blocker=0`；
- Mac candidate 已完成 Developer ID 签名、Apple notarization、staple、Gatekeeper 和
  独立 ZIP 解包验收；GitHub draft release 已创建：
  <https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-fce8f8f3bb37740266ba>；
- draft 资产的远端 size / SHA-256 与本地完全一致，candidate tag 在本地与 origin 都不
  存在，目标分支没有 push，`appcast.xml` 没有改动；
- `DEPLOY_REQUIRED` 是 live release 前的明确授权门；Production schema deploy、push、
  merge、published tag、live release、appcast publish 与 TestFlight 均未执行。

## 最终发布闭环（2026-08-08）

- PR [#71](https://github.com/o1xhack/CodexBar-Mobile/pull/71) 的持续 review 循环已完成；
  exact-SHA review 无 major issue、unresolved threads `0`，最终修复 SHA `638c01cf3`；
  merge commit `98f5e55688cd65edd6e4c8841c1c631e54c16b36`；
- Final CI run
  [31241006284](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/31241006284)
  全绿，覆盖 Linux x64/arm64 与 macOS 6/6 shards；
- 从最终 merge commit 重新生成的 Mac 包通过 Developer ID 签名、公证、staple、
  Gatekeeper、Production entitlement、universal binary 与 dSYM UUID 核验；notarization
  submission `d6ce3a05-f19e-4f39-bc44-c1675adc7ab5`；
- Mac release
  [`v0.47.0.1-mobile.1.20.0`](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.47.0.1-mobile.1.20.0)
  已于 `2026-08-08T17:06:59Z` 发布；ZIP SHA-256
  `614299556551f1e9e72156ba965df1fdea767bbad1f615b0779f05e828a1249d`，dSYM SHA-256
  `c73456b7042d3752909b10a206549476f18e1a358115a79ce87e4ddfa054bfd6`；
- 签名 appcast 已通过下载长度与 EdDSA signature 独立校验，并由 commit `958a184e0`
  推送到 `mobile-dev`；Sparkle short version `0.47.0.1`、version
  `111.1.1.20.0`；
- CloudKit Console promotion 明确列出 5 个新增 record types、1 个 index 与 3 个 security
  role updates；部署成功后 `cktool export-schema --environment production` 回读确认完整
  10-type union，包含 `AccountSnapshot`、`Device`、`Preferences`、
  `ProviderAccountLinkage`、`ProviderIntent`；
- iOS `1.20.0 (192)` 已 archive / upload，build ID
  `715a8ec4-8ede-4621-a8d2-1ddd90f48e09` 为 `VALID`；四语言 metadata 与 release notes
  已配置，review submission `a3a56d2c-5a9c-411f-8e9d-ac5b72cffb99` 于
  `2026-08-08T17:07:40.9Z` 提交，API 回读 submission 与 version 均为
  `WAITING_FOR_REVIEW`。
