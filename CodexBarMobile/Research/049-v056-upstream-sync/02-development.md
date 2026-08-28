# v0.56.0 Upstream Sync 开发记录

Status: `ready`
Date: 2026-08-28

## Phase A — 调研与分支

- [x] 从最新 `origin/mobile-dev=c7f61ae60` 创建
  `upstream-sync/v0.56.0-mobile.1.23.0`；
- [x] 读取 `AGENTS.md`、versioning、compatibility、CloudKit 与 release docs；
- [x] 核对 open issues #102-#104、历史 closed issue #95 与上游四个 Releases；
- [x] 拉取 collision-safe upstream refs并核对 tag/version/build provenance；
- [x] 完成 merge-tree conflict、Shared/wire/schema 与 release-boundary审计；
- [x] 写入 Research 049 概览、设计、开发与测试计划。

## Phase B — Mac merge / integration

- [ ] merge `v0.56.0`，保留 upstream second parent；
- [ ] 逐一解决 20 个 conflict files / 112 hunks；
- [ ] 语义合并 Claude slot-key migration 与 fork pending-delete ownership；
- [ ] 保留 fork README、CI、release/appcast、Production entitlements 与 composite version；
- [ ] 吸收 cost scanner/cache、provider、CLI security 与 localization；
- [ ] 更新 parser logic version/hash predecessors（若生成器判定需要）；
- [ ] 完成 Mac focused + full build/lint/test。

## Phase C — Shared / iOS

- [ ] 最终审计 root `Shared/` 与 `CodexBarMobile/Shared` wire diff；
- [ ] 证明现有 generic lanes覆盖 Cursor/Kiro/Alibaba/Fireworks/Antigravity/z.ai/OpenCode；
- [ ] 补 Kiro semantic labels 与四语言 localization；
- [ ] 补 v0.56 producer/round-trip/reader fixtures与代表 PreviewData；
- [ ] 更新 `version.env`、`project.yml`、root/iOS CHANGELOG、MobileReleaseNotesCatalog；
- [ ] `xcodegen generate` 并完成 iOS build/tests。

## Phase D — Compatibility / release candidate / review

- [ ] 正式 CloudKit schema audit与 Production只读回看；
- [ ] 逐行填写 16-case matrix；
- [ ] merge、bridge/iOS、release evidence 三轮 self-review + agent review；
- [ ] 生成并验证 signed/notarized ZIP+dSYM；
- [ ] 创建 no-ref GitHub draft并回读 assets/digest；
- [ ] 临时 candidate appcast 生成、签名与单调性验证；
- [ ] Research 状态与证据收口，blocker=0。

## Conflict 决策记录

| Path / area | Upstream intent | Fork invariant | Resolution | Verification |
|---|---|---|---|---|
| `.github/workflows/ci.yml` | 新测试平台与 runner hardening | PR Fast Checks + merge-only heavy CI | pending | CI policy tests |
| `CHANGELOG.md` / `version.env` | upstream 0.56 / build 131 | fork mobile-first changelog + composite version | pending | version/changelog gates |
| `appcast.xml` | upstream public feed | fork live feed不可在 candidate改写 | pending | byte/hash check |
| `CloudSyncEngine.swift` | Claude slot replacement/delete | fork pending delete ownership/retry | pending | migration + mixed writer tests |
| cost scanner/store/hash | read-view/fair scheduling/estimated cost | coverage/provenance/cache compatibility | pending | focused/full tests |
| Alibaba/OpenRouter | CLI-first/parser/plugin fixes | fork bridge/parser hash | pending | provider tests |
| CI/test scripts | upstream shards/aggregates | fork path gate/policy | pending | script regression tests |

## Review 记录

| Round | Exact head | Scope | Findings | Fix / retest | Result |
|---:|---|---|---|---|---|
| 1 | pending | merge + fork seams | pending | pending | pending |
| 2 | pending | Shared/iOS + localization | pending | pending | pending |
| 3 | pending | release diff + evidence | pending | pending | pending |

## Draft artifact 记录

| Evidence | Value |
|---|---|
| candidate tag name | `v0.56.0.1-mobile.1.23.0` |
| ZIP | `CodexBar-0.56.0.1-mobile.1.23.0.zip` |
| dSYM | `CodexBar-0.56.0.1-mobile.1.23.0.dSYM.zip` |
| app UUID / dSYM UUID | pending |
| ZIP / dSYM SHA-256 | pending |
| notary / stapler / Gatekeeper | pending |
| Production entitlement | pending |
| GitHub draft URL / `draft=true` | pending |
| remote task branch / tag absent | pending |
| live appcast unchanged | pending |
