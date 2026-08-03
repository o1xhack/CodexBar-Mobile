# v0.47.0 Upstream Sync 开发证据

Status: `ready`
Date: 2026-08-03
Branch: `upstream-sync/v0.47.0-mobile.1.20.0`

## Round 0 — Preflight / research

- clean `mobile-dev` at `9d9db632`，与 `origin/mobile-dev` 一致；
- 在任何 Research / implementation 写入前创建目标 upstream-sync branch；
- 已读 AGENTS、versioning、sync compatibility、CloudKit audit、release checklist 与必需
  Git/release/QA skills；
- 权威 release 范围冻结为 `v0.45.2..v0.47.0`，覆盖 issue #66 与尚未被 monitor
  建 issue 的当天正式版 v0.47.0；
- annotated tag `v0.47.0` peel 到 `6a16c233`，v0.45.2 ancestry 通过；
- merge-tree 预演：41 个 content conflicts；
- P0 架构审计确认 fork Mobile sync 与 upstream fleet sync 同名 property/key 冲突；
- CloudKit 初判 `DEPLOY_REQUIRED`，实际 deploy 延后到独立授权门。

## 后续 evidence ledger

实现开始后按轮次追加：

1. provenance-preserving merge 与 conflict ledger；
2. fleet/Mobile sync 隔离、container/schema、package/signing；
3. Shared wire 与 iOS provider bridge；
4. localization/version/release notes；
5. Mac/iOS tests 与 16-case compatibility；
6. independent review findings/fixes；
7. signed/notarized draft candidate 与 CloudKit final audit。
