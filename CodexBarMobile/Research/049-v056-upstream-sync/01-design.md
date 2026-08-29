# v0.56.0 Upstream Sync 设计

Status: `ready`
Date: 2026-08-28

## Merge 策略

1. provenance-preserving merge published tag `v0.56.0`，保留 upstream second parent；
2. 按冲突路径逐项整合，不使用整树 ours/theirs；
3. `README.md` 保持 fork byte-owned 内容，并运行 `Scripts/check_fork_readme.sh`；
4. `.github/workflows/ci.yml` 保留 fork 的 PR Fast Checks / post-merge Final CI invariant，
   同时吸收上游 Linux musl/aggregate gate 与 test-runner hardening；
5. release scripts、appcast、Production entitlements、Mobile sync、composite version 与
   parser fingerprint 规则保持 fork 语义；
6. `CloudSyncEngine` 合入上游 Claude slot-key migration，但保留 fork pending-delete
   cancellation、ownership 与 reconciliation；必须保证 replacement save 成功后才删 predecessor；
7. cost/scanner/cache 冲突同时保留 fork coverage/provenance/cache safety 与上游 fair scheduling、
   partial-history completion、read-view、estimated-cost changes；
8. localization 自动合并后跑完整 lint，不以 ours/theirs 丢 key。

merge-tree 预演得到 20 个冲突文件、112 个 hunks；`appcast.xml` 单列为禁止改动的 live feed 后，
其余 19 个代码/策略冲突主要位于 CI/test scripts、CHANGELOG/version、CloudSync、cost store、
Alibaba/OpenRouter、parser hash 与相应 tests。

## Fleet sync 与 Mobile sync 边界

- upstream `CodexBarSync` 的 Claude slot-key migration 只服务 Mac fleet `AccountSnapshot`；
- fork Mobile sync 继续写 `DeviceProviderSnapshot.payload` opaque JSON，record type 与 zone 不变；
- 两条通道共享 `UsageStore` 输入但不得共享 record deletion ownership；
- old Mac 可能重写 email-key predecessor，因此 16-case audit 必须验证 mixed writer 收敛；
- Mobile payload 不包含 fleet predecessor key、本地 pending-delete、project/session path、raw scanner
  state、credential、cookie、token 或 browser metadata。

## iOS wire / UI 设计

不新增 dedicated struct 或 CloudKit schema，复用下列稳定 seam：

1. `SyncCoordinator` 将所有 primary/secondary/tertiary/extra windows 映射为动态 `rateWindows`；
2. `ProviderDetailSection` 映射为 bounded generic `details`；
3. cost history 继续使用 `SyncCostSummary` 的 known/estimated/coverage/provenance/token mix；
4. `ProviderUsageSnapshot.init(from:)` 对 optional/additive fields 使用 `decodeIfPresent`；
5. `providerPayloadVersion` 保持 `1`，不触发全量 rewrite。

需要实现的 iOS slice：

- 为 Kiro `Overage` 与新增 detail labels补 semantic localization 和四语言 translations；
- 新增 v0.56 producer/round-trip/reader fixtures：Cursor fourth window + estimated coverage、
  Antigravity token-only unknown cost、Fireworks provider spend、Kiro overage/details、old payload；
- 确认 `Grok Bot` 品牌名保持原文且不会被 generic label 错译；
- 更新 PreviewData 与 release notes，但仅新增能提高回归覆盖的代表样例，不复制 Mac-only UI。

## 版本方案

| Artifact | 基线 | 目标 |
|---|---|---|
| Mac `MARKETING_VERSION` | `0.54.0.1` | `0.56.0.1` |
| Mac `BUILD_NUMBER` | `127.1` | `131.1` |
| `MOBILE_VERSION` | `1.22.0` | `1.23.0` |
| iOS `MARKETING_VERSION` | `1.22.0` | `1.23.0` |
| iOS `CURRENT_PROJECT_VERSION` | `195` | `196`，全部 4 targets |
| Sparkle version | `127.1.1.22.0` | `131.1.1.23.0` |
| candidate tag | `v0.54.0.1-mobile.1.22.0` | `v0.56.0.1-mobile.1.23.0` |
| upstream bookmark | `v0.54.0 / 2026-08-20` | `v0.56.0 / 2026-08-28` |

Mac 上游段变化后 fork patch 从 `.1` 起；`BUILD_NUMBER` 采用上游整数 `131` + fork `.1`；
iOS 本轮包含用户可见 provider/cost/localization compatibility，使用新的 `1.23.0 (196)`。
`docs/versioning.md` 后半段旧三段示例与顶部四段核心规则冲突，本轮以顶部规则和最近 047/048
release train 为准。

## 测试策略

- merge/fork policy：CI policy、README hash、release scripts、version/changelog extraction；
- Mac：Release build、lint、full `swift test --no-parallel`、focused fleet/Mobile sync、Claude migration、
  cost/parser/cache、Codex/Alibaba/Grok/Cursor/Antigravity/Fireworks/OpenRouter/OpenCode、CLI security；
- iOS：`xcodegen generate`、四 target version audit、Release simulator build、full tests、focused
  wire/mapper/cache/widget/localization；
- compatibility：因 fleet record migration、provider display、cost cache/history 与 cross-version rendering
  变化，执行 16-case gate；无四台硬件时每行如实写 `substituted`；
- CloudKit：最后 published fork tag到 candidate的 schema diff + Production schema只读回看；
- review：merge、bridge/iOS、release evidence 分轮自查与独立 agent review，finding 修复并复测。

## Draft 与权限边界

默认 `Scripts/release.sh` phase 1 会 `git push -f origin "$TAG"`，不符合本 Goal 的 no-push
边界，因此不直接运行。候选闭环使用：

1. `Scripts/sign-and-notarize.sh` 生成签名、公证 ZIP/dSYM；
2. 验证 UUID、SHA-256、codesign、stapler、Gatekeeper、Production entitlement；
3. 通过 GitHub draft API 创建未发布 tag 的 draft并上传资产；因任务分支不得 push，
   `target_commitish` 暂指向 `mobile-dev`，draft notes明确记录本地产物源 SHA；公开前必须在 exact
   commit 合入 `mobile-dev` 后重新校验 target/资产，draft本身不会创建远端 tag ref；
4. candidate appcast 只在临时 worktree/临时文件中生成并验签，不修改 live `appcast.xml`；
5. 回读 `draft=true`、remote task branch/tag 不存在、live feed 未改变。

push、PR/GitHub current-head review gate、merge、tag publish、live release/appcast、TestFlight 与
CloudKit deploy仍需后续明确授权。公开 release 前必须从最终 clean `mobile-dev` 重新核对或重建资产。
