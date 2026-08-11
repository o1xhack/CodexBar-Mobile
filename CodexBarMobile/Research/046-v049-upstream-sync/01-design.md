# v0.49.2 Upstream Sync 设计

Status: `in-progress`
Date: 2026-08-11

## 设计原则

以 published `v0.49.2` annotated tag 做一次 provenance-preserving merge，完整保留上游
Mac 行为；只在 fork-owned Mobile、CloudKit、CI、release、appcast、composite version
与跨版本 payload 契约冲突时做定向整合。Goal 已确认此方案，可直接进入实现。

## Merge 策略

1. 在 `upstream-sync/v0.49.2-mobile.1.21.0` 合并
   `refs/upstream-tags/v0.49.2`。
2. 保留 `.github/workflows/pr-fast.yml`、fork Final CI trigger、
   `Scripts/check_ci_policy.sh` 与 `docs/ci-policy.md`；吸收不改变 trigger model 的 upstream
   workflow/security 改进。
3. 保留 fork `release.sh` / `make_appcast.sh` / `sign-and-notarize.sh` / CloudKit Production /
   bundle ID / team / Sparkle/composite version 路径；逐项吸收 upstream package resource
   smoke 与 QuickJS resource hardening。
4. `CHANGELOG.md` 保留 fork Mobile release train，合入 v0.48.0–v0.49.2 upstream entries；
   candidate 期间不改 published `appcast.xml`。
5. Mac locale 采用 upstream + fork strings union，不能用批量 ours/theirs 丢掉任一侧 keys。
6. provider architecture 接受 upstream `ProviderInstanceID` 与 declarative details，同时
   port fork Mobile mappers、Mobile sync、quota warning、mock 与 provider hotfix 到新 seam。
7. deleted specialized files 仅在行为已由 generic detail model 覆盖且测试证明 parity 后删除；
   否则把 fork semantics 移植到新 owner，不能保留僵尸旧架构。
8. parser/cache/SQLite conflicts 合并两侧语义；凡 `CostUsageScanner*` / JSONL pricing logic
   变化，bump `parserLogicVersion` 并重生成 `CodexParserHash`。

## 双 sync 架构保持不变

```text
Mac local usage/config
  ├─ Mobile sync (iCloudSyncEnabled, default true)
  │    └─ DeviceProviderSnapshot / Mobile zones -> iPhone + widgets
  └─ Mac fleet sync (macFleetSyncEnabled, default false)
       └─ AccountSnapshot / Device / Preferences / ProviderIntent
          in CodexBarSync zone -> other Macs only
```

上游 v0.48–v0.49 对 fleet config/provider identity 的变化只能进入第二条通道。iPhone 继续
不读取 `AccountSnapshot` / `ProviderIntent`；plugin secrets、approval、network/cookie
capabilities 和 local file paths 永远不进入 Mobile payload。

v0.49.2 account dedupe 采用稳定 provider instance/account identity/current-device ownership；
fork Mobile reducer仍以 distinct device IDs 和 account identity set 聚合。两条通道共享 fork
Production container，但 record families、master toggle、persistence 与 consumer 隔离。

## Shared wire 方案

### 兼容层

- 保留现有 `ProviderUsageSnapshot` 及所有已发布 typed optional fields；
- 新增 optional generic declarative details，字段名与 enum 采用 forward-compatible raw string；
- 新 reader 对缺失 details 返回空集合；本轮已知 `rows` / `bars` / `line` kinds 均可读，
  detail object 内未知 optional keys 会被 decoder 忽略。新增未知 chart kind 仍需后续 additive
  iOS support，不能宣称当前 enum 可无损承载未来 kind；
- old reader 忽略新 optional key；new reader 继续渲染 old typed payload；
- provider instance raw ID 作为显示/identity hint，不替换现有 first-party `providerID`；
- `providerPayloadVersion` 维持 `1`，避免无必要的全量 rewrite/CPU/network spike。

### Provider 决策

- Fireworks：first-party ID，优先映射 generic spend limit/balance + 30-day window；如
  declarative detail 已含安全标量，iOS generic details 显示，不同步 API key/account slug。
- IBM Bob：first-party ID，使用 generic rate windows/details；未知后续 detail kind 安全降级。
- user plugin：不加入 `QuotaProviderList`（动态、不可穷举）；只在普通 usage payload 内使用
  raw instance ID + display label + declarative rows，不创建 CloudKit subscriptions。
- built-in JS conversions：provider ID 保持已发布 raw value；新/旧 engine 输出必须在
  Mobile mapper 层归一，不让 iOS 因 engine 变化产生重复卡片。

### Generic detail 最小模型

建议只同步 render-safe aggregate：section title、row label、value、optional percentage、
optional reset/date、chart points、unit/currency、semantic kind。明确排除 credential、cookie、
URL override、local path、raw response、plugin script/manifest permissions 与 secret map。

## iOS 展示方案

1. Fireworks 与 IBM Bob 加入 first-party provider metadata、color、mock/subscription
   contracts；能用现有 rate/balance/card 就不造重复专用 view。
2. 新 generic details section 放在既有 primary/secondary window 和 typed cards之后；同语义
   row 去重，typed contract 优先，避免 old+new 两套数据重复显示。
3. unknown provider instance 使用稳定 raw ID + sanitized display name 的 generic card；不允许
   冒充现有 first-party provider，也不参与 quota notification whitelist。
4. widget/Cost dashboard 继续只消费已验证 aggregate；plugin declarative rows 不自动计入
   Today cost/token totals，除非有明确 numeric semantic 与去重 identity。
5. user-facing 文案仅描述“更多 provider 与更完整详情”，不暴露 plugin runtime、wire、
   CloudKit schema、JSON key 等工程术语。

## 版本方案

| Artifact | Target |
|---|---|
| Mac `MARKETING_VERSION` | `0.49.2.1` |
| Mac `BUILD_NUMBER` | `116.1` |
| iOS `MOBILE_VERSION` | `1.21.0` |
| iOS `CURRENT_PROJECT_VERSION` | `193`（全部 targets） |
| Sparkle / app `CFBundleVersion` | `116.1.1.21.0` |
| candidate tag name | `v0.49.2.1-mobile.1.21.0` |
| assets | `CodexBar-0.49.2.1-mobile.1.21.0.zip` + `.dSYM.zip` |
| upstream bookmark | `v0.49.2` / `2026-08-11` |

上游变化将前三段更新到 `0.49.2`；fork 保留 Mobile/CloudKit/release bridge，因此新 upstream
train 首发为 `.1`。上游 build `116` 加 fork patch `.1`。iOS 有新 provider/generic detail
与兼容逻辑，走 feature minor `1.21.0`，build 从 `192` 单调递增为 `193`。

## CloudKit 方案

初始 verdict 为 `NO_DEPLOY_EXPECTED`。实现后必须按 published fork tag→HEAD 运行文档中的
四步 diff audit，并只读 export Production schema：

- 若只有 `DeviceProviderSnapshot.payload` 内 optional JSON keys、更多 existing records 或
  render 变化，正式结论 `NO_DEPLOY`；
- 若发现新 record type/field/index/zone/subscription/predicate，正式结论
  `DEPLOY_REQUIRED`，只完成 schema candidate/Development validation，Production deploy
  停在显式授权门。

## 测试方案

- provenance/conflicts：tag ancestry/merge parent、50 conflicts、fork CI/release/appcast/
  CloudKit entitlements/version contracts；
- Mac：`swift build`、`bash Scripts/lint.sh lint`、`swift test --no-parallel`、provider plugin
  engines/goldens/resources、SQLite store、PTY/actor isolation、Fireworks/IBM Bob、fleet sync
  dedupe、existing Alibaba/Claude/Codex/Notion regressions；
- fork gates：`check_ci_policy.sh`、parser version/hash、package resource launch smoke、
  multi-account/device filter、Widget snapshot parity；
- Shared/iOS：old/new wire fixtures、generic detail safe decode/redaction/dedupe、Fireworks/IBM
  Bob provider contracts、unknown plugin generic card、identity/cache/delete/ghost behavior；
- iOS：focused tests、full `CodexBarMobileTests`、Release simulator build、4-language audit；
- 16-case compatibility：每个 mask 使用两个 distinct Mac writer IDs、两份独立 iPhone cache，
  覆盖 old/new typed/generic payload、provider instance IDs、dedupe 与 convergence；
- release：signed/notarized/stapled app、Gatekeeper、universal binaries、Production entitlement、
  ZIP/dSYM UUID/hash、GitHub draft asset digest；确认无 local/remote tag 和 branch push。

## Review 方案

merge 轮、Shared/iOS 轮、release 轮分别执行 self diff + 独立 agent review；每个 P0/P1/P2
finding 都修复、focused retest，再回交 reviewer。最终只有 `P0=0 / P1=0 / P2=0 /
blocker=0` 才能把 Research 状态改为 `done`。
