# v0.49.2 Upstream Sync 开发记录

Status: `done`
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

- [x] merge annotated tag；
- [x] 解决 fork infrastructure/version/localization conflicts；
- [x] 解决 provider/details/CloudSync/parser/cache/tests conflicts；
- [x] 确认 unmerged paths = 0，merge parent 指向 tag peel commit；
- [x] merge build/lint/focused tests；
- [x] 独立 merge review 到 clean。

### Phase 2 — Shared / Sync bridge

- [x] 保留 published Mobile typed wire；
- [x] generic declarative detail additive optional codec + redaction；
- [x] `ProviderInstanceID` first-party/plugin boundary；
- [x] Mobile/fleet record family 与 reducer隔离；
- [x] v0.49.2 account dedupe/ownership tests；
- [x] Fireworks/IBM Bob mappers、wire round-trip、unknown instance tests。

### Phase 3 — iOS product

- [x] first-party provider list tail entries；
- [x] mock profiles/count contracts；
- [x] color/identity/card/generic detail UI；
- [x] PreviewData card-type decision；
- [x] widgets/Cost dashboard dedupe and parity；
- [x] 4-language user-facing strings。

### Phase 4 — Version / docs / CloudKit

- [x] `version.env` → `0.49.2.1 / 116.1 / 1.21.0 / v0.49.2 / 2026-08-11`；
- [x] `project.yml` 全 targets → `1.21.0 (193)` + `xcodegen generate`；
- [x] root/iOS CHANGELOG；
- [x] `MobileReleaseNotesCatalog` 1.21.0 + four locales；
- [x] parser version/hash audit；
- [x] CloudKit Production schema audit verdict：`NO_DEPLOY`。

### Phase 5 — Verification / draft / review

- [x] Mac build/lint/full/focused regressions；
- [x] iOS focused/full/Release build；
- [x] 16-case compatibility matrix（fixture/simulator substituted）；
- [x] signed/notarized/stapled candidate；
- [x] draft release + asset digest readback；
- [x] final iterative review/retest；
- [x] Research status/evidence closeout。

## 实现日志

### 2026-08-11 checkpoint

- Research commit `c246b1ca4`；provenance-preserving merge commit `a75be5a4b`，第二 parent
  为 tag peel `330ae4384b182e531c483fa9d132ea85a74c204b`；50 个冲突全部解决。
- 保留 fork `AGENTS.md`、CI trigger、Production entitlements、composite version、appcast 与
  no-push release 边界；22 个 Mac locale 做 key union。既存 `.mac-release.env` 仍含 upstream
  repo/Peter signing manifest，但本轮权威 `sign-and-notarize.sh` 完全不读取它，且未运行
  `Scripts/mac-release`；它是未来启用 wrapper/live finalize 前的前置条件，不属于本轮 direct
  draft finding。
- CloudSync 的 dirty state、authority/revision/generation/reconciliation 统一迁到
  `ProviderInstanceID`；custom plugin refresh 能产生 publication authority，同时继续隔离
  Mac fleet 与 Mobile record family。
- Mac `UsageSnapshot.details` 投影为 Shared optional generic details；旧 typed Mobile keys 保留。
  `usageKnown`、synthetic-placeholder filter、plugin branding/device-scoped identity 与
  deterministic `(lastUpdated, deviceID)` merge 均有 compatibility tests。
- iOS generic rows/bar/line chart、explicit-clear semantics、unknown plugin generic card、
  Fireworks spend-only 与 IBM Bob Bobcoin quota 已落地；Quota provider tail 仅 append，现为
  70 providers / 210 subscriptions。
- parser logic `10 → 11`，generated hash `834522608c1b0457`，commit `42d6dc331`。
- 全量回归首次发现 provider architecture drift fingerprint 已因 Fireworks/IBM Bob catalog
  seams 改变；审计完整 254 findings 后确认新增 ID 仅在 mock/pricing/sync/identity 边界，
  最终以 `18225140329188946977` 精确 pin，单项 gate 与最终全量均通过。
- 三路 review 发现的 Fireworks/plugin cost-only ghost、identity、typed/details 双渲染、IBM Bob
  unknown quota、generic decoder bounds、动态 label 误本地化和 matrix 断言不足均已修复；代码
  commits `b594ffa38`、`37d46edec`，final P0/P1/P2/blocker 为 0。
- 首次签名在 widget Xcode DerivedData 的 SweetCookieKit repository cache 缺失锁定 tree
  `d5ea6d9…` 处停止，尚未进入 codesign。只对该生成 cache fetch 已锁定 revision，独立 widget
  Release build 通过后重跑；notary submission `da356aff-452e-4d07-93df-514514c68ac6`
  `Accepted`，staple/distribution/direct-launch/dSYM gate 全过。
- 创建 GitHub untagged draft `368897158`，上传 app ZIP 与 dSYM；API digest 与本地 SHA-256
  逐字一致。没有创建/推送 tag、branch，也没有修改 appcast 或发布 live release。

### 2026-08-17 release closeout

- 用户明确追加授权 Mac live release 与 iOS 打包上传；同步分支通过 PR
  [#89](https://github.com/o1xhack/CodexBar-Mobile/pull/89) 合入 `mobile-dev`，merge commit
  `c1f448339`。PR Fast Checks `32051325391` 与 conservative full Final CI `32051437233`
  均通过。
- 首次从 merged `mobile-dev` 运行 `Scripts/release.sh` 时，lint child shell 因继承
  `CODEXBAR_SPARKLE_HELPERS_LOADED=1`、但未继承 shell function，出现
  `check_assets: command not found`。修复为 sentinel 只有在 `declare -F check_assets`
  存在时才生效，且不再 export；回归测试显式覆盖 stale inherited sentinel。修复经 PR
  [#90](https://github.com/o1xhack/CodexBar-Mobile/pull/90) 合入，merge commit
  `a88b71b27`；PR Fast Checks `32054938333` 与 path-selected Final CI `32055053940` 通过。
- 从最终 merge commit 强制重建 Mac universal app；notary submission
  `fe3ad18e-2178-46dd-ab27-4d89a8e867a5` 为 `Accepted`，staple、Gatekeeper、direct launch、
  Production CloudKit 与 ZIP readback 均通过。phase 1 创建正式 annotated tag 和新 draft，
  phase 2 发布 live release、验证 Sparkle signature/length，并以 commit `f6772526b` 推送
  `appcast.xml`。
- Mac release：
  <https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.49.2.1-mobile.1.21.0>；
  Mac Release Verify run `32056443141` 通过 Gatekeeper、stapler 与 release-asset launch。
  Release CLI run `32056443142` 的 6 个 macOS/Linux glibc/musl jobs 全部通过 build、smoke、
  package 和 upload；release 最终包含 app/dSYM 与 6 个 CLI tarball/checksum，共 14 个 assets。
- `xcodegen generate` 后运行 `Scripts/upload_ios_testflight.sh`；1897 Swift files 0 lint
  violations、四语 audit 通过，archive/export/upload 均成功。archive：
  `/tmp/CodexBarMobile-20260817-114708.xcarchive`；主 App、Push Extension、Widget Extension
  均为 `1.21.0 (193)`，CloudKit Production。
- App Store Connect build `5f20e3c0-96cf-416e-ba21-8213151cdda2` 已绑定 iOS `1.21.0`，
  processing state `VALID`，`expired=false`，`usesNonExemptEncryption=false`；source、archive
  compiled 和 ASC CDN 三层 App icon 均完成尺寸/内容回读。未提交 App Store review。

禁止把 credential、token、cookie、真实账号标识或未脱敏日志写入本文。
