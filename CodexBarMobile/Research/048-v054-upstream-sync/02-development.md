# v0.54.0 Upstream Sync 开发记录

Status: `in-progress`
Date: 2026-08-21

## Phase A — 分支与调研

- [x] 从最新 `mobile-dev` (`cadf27e6009c70c683122622f2ed321d2e608b17`) 建立
  `upstream-sync/v0.54.0-mobile.1.21.0`；
- [x] 读取 versioning、sync compatibility、CloudKit audit、release checklist与CI policy；
- [x] 复核 open issue #95、defect #97、历史 closed upstream-sync issues与上游 Releases；
- [x] 选择 authoritative latest release `v0.54.0`，将 v0.53.0–v0.54.0 合并成单一 train；
- [x] 记录版本方案、iOS影响门、风险与测试计划；
- [ ] provenance-preserving merge `v0.54.0` 并记录全部冲突决策。

## Phase B — Mac / fork integration

- [ ] 完整保留 upstream功能、修复、性能与安全变化；
- [ ] 保留 fork CI/release/appcast/version/Production/Mobile sync约束；
- [ ] 完成 Settings、CloudKit、cost/parser/cache与provider冲突适配；
- [ ] 更新 root changelog与 `version.env`。

## Phase C — Shared / iOS

- [ ] 完成 cost provenance/coverage/token mix 与provider数据投影审计；
- [ ] 必要时新增 additive optional wire与iOS显示；
- [ ] 合并更新唯一的 1.21.0 notes block与四语言localization；
- [ ] 全部iOS targets build从194增至195。

## Phase D — testing/review

- [ ] Mac build/lint/focused/full regression；
- [ ] iOS build/focused/full tests；
- [ ] CloudKit Production schema审计；
- [ ] 16-case compatibility gate；
- [ ] merge/bridge/iOS循环review至blocker 0。

## 冲突记录

正式 merge 后填写每个 conflict path、决策与验证证据。
