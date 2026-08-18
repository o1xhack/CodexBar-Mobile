# v0.52.0 Upstream Sync 开发记录

Status: `in-progress`
Date: 2026-08-17

本文件只记录可复核的实现与冲突决策；不把命令流水账当作完成证据。

## Phase A — 分支与调研

- [x] 从最新 `mobile-dev` (`32283fd0c...`) 建立
  `upstream-sync/v0.52.0-mobile.1.21.0`；
- [x] 读取 `AGENTS.md`、`version.env`、versioning、sync compatibility、CloudKit audit、
  release checklist/flow与CI policy；
- [x] 复核 open issues #82–#88、历史 closed issues #77–#81、上游 Releases与相关 PR/commits；
- [x] 选择 authoritative latest release `v0.52.0` 作为单一 train终点；
- [x] merge-tree预演并识别 fork冲突面；
- [ ] merge `v0.52.0` 并逐项记录冲突解决。

## Phase B — Mac / fork integration

- [ ] 完整保留上游功能、修复、性能与安全变化；
- [ ] 保留 fork CI/release/appcast/composite version/CloudKit Production约束；
- [ ] 合并 provider accent/workday tick/scoped quota/project cost语义；
- [ ] 滚动 parser logic fingerprint并重生成 hash（若审计确认需要）；
- [ ] 更新 root changelog与 `version.env`。

## Phase C — Shared / iOS

- [ ] 审计 Mobile wire能否承载所有 iOS-relevant output；
- [ ] 只添加确有必要的 additive optional字段与兼容 tests；
- [ ] 合并更新 1.21.0 notes，不创建 1.22.0 block；
- [ ] 将 iOS全部 targets build从 193增至194；
- [ ] 完成四语言 localization、technical changelog与 provider/widget/display tests。

## Phase D — release candidate

- [ ] Mac build/lint/test/regression；
- [ ] CloudKit Production `NO_DEPLOY`/`DEPLOY_REQUIRED`审计；
- [ ] signed + notarized candidate、codesign/spctl/CLI/launch verification；
- [ ] 创建 GitHub draft release并上传 ZIP/dSYM，不发布 live、不推 tag/appcast；
- [ ] iOS build/tests与16-case compatibility gate；
- [ ] 循环 review至 blocker 0并回写全部 evidence。

## 冲突记录

待正式 merge 后填写每个 conflict 的 ours/upstream/integration决策、验证与 commit。

