# v0.49.2 Upstream Sync 开发记录

Status: `not-started`
Date: 2026-08-11

## 目标

在 `upstream-sync/v0.49.2-mobile.1.21.0` 完成一个 release train：

1. provenance-preserving merge upstream `v0.49.2`；
2. 保留 fork CI/release/CloudKit Production/Mobile sync/versioning；
3. 适配 upstream `ProviderInstanceID`、declarative details 与 fleet sync dedupe；
4. 完成 Fireworks、IBM Bob 与安全 generic details 的 iOS bridge；
5. 更新版本、CHANGELOG、4-language in-app notes；
6. build/test/audit/sign/notarize/draft/review 证据收口。

## 阶段记录

### Phase 0 — Research / branch

- [x] 从 clean/latest `origin/mobile-dev` `d874facd8` 创建目标分支；
- [x] 核验 open issues #77–#80 与历史 closed upstream-sync issues；
- [x] 核验 GitHub Releases 权威目标为 `v0.49.2`；
- [x] 获取 collision-safe upstream tags 并验证 `v0.47.0` ancestry；
- [x] 预演 merge：187 commits、954 files、50 conflicts；
- [x] 写 `00-overview.md`、`01-design.md`、`02-development.md`、`03-testing.md`。

### Phase 1 — Upstream merge

- [ ] merge annotated tag；
- [ ] 解决 fork infrastructure/version/localization conflicts；
- [ ] 解决 provider/details/CloudSync/parser/cache/tests conflicts；
- [ ] 确认 unmerged paths = 0，merge parent 指向 tag peel commit；
- [ ] merge build/lint/focused tests；
- [ ] 独立 merge review 到 clean。

### Phase 2 — Shared / Sync bridge

- [ ] 保留 published Mobile typed wire；
- [ ] generic declarative detail additive optional codec + redaction；
- [ ] `ProviderInstanceID` first-party/plugin boundary；
- [ ] Mobile/fleet record family 与 reducer隔离；
- [ ] v0.49.2 account dedupe/ownership tests；
- [ ] Fireworks/IBM Bob mappers、wire round-trip、unknown instance tests。

### Phase 3 — iOS product

- [ ] first-party provider list tail entries；
- [ ] mock profiles/count contracts；
- [ ] color/identity/card/generic detail UI；
- [ ] PreviewData card-type decision；
- [ ] widgets/Cost dashboard dedupe and parity；
- [ ] 4-language user-facing strings。

### Phase 4 — Version / docs / CloudKit

- [ ] `version.env` → `0.49.2.1 / 116.1 / 1.21.0 / v0.49.2 / 2026-08-11`；
- [ ] `project.yml` 全 targets → `1.21.0 (193)` + `xcodegen generate`；
- [ ] root/iOS CHANGELOG；
- [ ] `MobileReleaseNotesCatalog` 1.21.0 + four locales；
- [ ] parser version/hash audit；
- [ ] CloudKit Production schema audit verdict。

### Phase 5 — Verification / draft / review

- [ ] Mac build/lint/full/focused regressions；
- [ ] iOS focused/full/Release build；
- [ ] 16-case compatibility matrix；
- [ ] signed/notarized/stapled candidate；
- [ ] draft release + asset digest readback；
- [ ] final iterative review/retest；
- [ ] Research status/evidence closeout。

## 实现日志

后续每个 checkpoint 追加：commit SHA、关键文件、冲突取舍、命令与结果。禁止把 credential、
token、cookie、真实账号标识或未脱敏日志写入本文。
