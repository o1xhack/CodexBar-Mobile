# Mac 0.73.0.1 签名、Draft 与发布

Status: `done`
Date: 2026-10-08

## 授权与来源

- 2026-10-08 用户选择“Mac 直接发布，iOS 上 TestFlight”：本地 review、PR review 与全量测试通过后签名公证 Mac 0.73.0.1，恢复更新源；iOS 只上传 TestFlight，用户真机验证后再送审。
- PR [#186](https://github.com/o1xhack/CodexBar-Mobile/pull/186)：3 轮 Codex review，`Scripts/check_pr_review_gate.sh 186` 通过（rounds=3、unresolved=0），head `b04e495cc74e778797f737a6e17fefa6543526b2`，`--match-head-commit` 合并为 `273b2334487abf339c421c4141f99ef0267edc20`。
- 发行源码：mobile-dev `273b23344`（tag 指向此提交）。

## 版本与资产

- `0.73.0.1` / `165.1` / Mobile `2.6.0`，CFBundleVersion `165.1.2.6.0`。
- Tag `v0.73.0.1-mobile.2.6.0` → `273b2334487abf339c421c4141f99ef0267edc20`（phase 1 推送）。
- Draft：`untagged-18533afc18440aff5c54`，title `CodexBar 0.73.0.1 Mobile 2.6.0`。
- `CodexBar-0.73.0.1-mobile.2.6.0.zip`：83,672,569 bytes，SHA256 `3d29233bffc58b0b1c7243be0edd0fca1e15603e0897ea17868b06c2a0042d00`。
- `CodexBar-0.73.0.1-mobile.2.6.0.dSYM.zip`：68,336,797 bytes，SHA256 `889d07c7ee00cd9f19b378cf1170ddf957d40c739ffe327f8f326368baa3d669`。
- 本地文件与 GitHub asset digest 一致（finalize 的 `require_remote_asset_matches_local` 复核）。
- 发布 staging 与 TMPDIR 均在 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v073-release/`。
- CloudKit：`NO_DEPLOY`（见 `docs/cloudkit-deploy-audit.md` v0.73.0.1 节）。

## Final CI 与公开发布

- #186 合并提交自身的 Final CI（37838259940）因 macOS runner 排队，公开发布时仍未开始。
- PR #187 合并后的 Final CI [37842301090](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/37842301090) 已 success。它的 head `2962fabcc` 包含 `b04e495cc` 和 `273b23344`。
- `git diff 273b23344 ff49aec70` 只改了 `CodexBarMobile/`、`Research/` 和 `docs/`，Mac 构建输入完全相同，所以这次 Final CI 也覆盖了发行源码。
- finalize 再次确认 zip 与 mobile-dev 当前的 Mac 输入匹配（`artifact_matches_current_inputs`）。
- finalize 在 mobile-dev 运行，HEAD 与 origin 相同（`ff49aec70`），tag 是它的祖先。
- Release 于 2026-10-08T21:10:38Z 公开，`isDraft=false`、`isPrerelease=false`，`releases/latest` 指向 `v0.73.0.1-mobile.2.6.0`。
- 下载 enclosure 后 Sparkle 签名和长度复核通过。appcast 提交 `73c8d560b` 已推送到 mobile-dev。
- raw appcast 读回结果：最上面一项是 `0.73.0.1`，`sparkle:version 165.1.2.6.0`。appcast 已从回退的 0.70.0.1 恢复为最新版。
- 正式 Release：https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.73.0.1-mobile.2.6.0

## 实际包验证

从线上 release 下载 ZIP，在 SSD scratch `v073-release/verify` 解包后检查：
- `codesign --verify --deep --strict` 通过；
- Gatekeeper `accepted / Notarized Developer ID`（Yuxiao Wang 3TUERHN53E）；
- `stapler validate` 成功；
- entitlements 为 `com.apple.developer.icloud-container-environment = Production`，容器 `iCloud.com.o1xhack.codexbar`；
- Info.plist `0.73.0.1` / `165.1.2.6.0`。
