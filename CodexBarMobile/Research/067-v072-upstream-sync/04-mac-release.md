# Mac 0.72.0.1 签名、Draft 与发布

Status: `done`
Date: 2026-10-07

## 授权与来源

- 2026-10-07 用户在本 Goal 中明确授权“Mac 全流程发布”：push 分支 → PR → Codex Code Review → 合并 mobile-dev → 签名公证 Draft → finalize 公开发布并更新 appcast；iOS 本轮不上传 TestFlight。MOBILE_VERSION 确认保持 2.6.0。
- PR [#180](https://github.com/o1xhack/CodexBar-Mobile/pull/180)：3 轮 Codex review（P2 teaser 到期刷新、P2 项目行 ID 碰撞均修复并 resolve），最终 head `000bd2570cbd075ef93e0797f0ec59a5422d1197` 收到 “Didn't find any major issues”；`Scripts/check_pr_review_gate.sh 180` 通过（rounds=3、unresolved=0），PR Fast Checks success；`gh pr merge --merge --match-head-commit` 合并为 `5948797ec68d86aa1b8e42b787170a91febdc158`（保留上游 merge 历史）。
- 发行源码：mobile-dev `5948797ec`；包内 `CodexGitCommit=5948797ec`。

## 版本与资产

- `0.72.0.1` / `164.1` / Mobile `2.6.0`，CFBundleVersion `164.1.2.6.0`。
- Tag `v0.72.0.1-mobile.2.6.0` → `5948797ec68d86aa1b8e42b787170a91febdc158`（phase 1 推送）。
- Draft：https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-9d0fdb3f66964faa5e06（`isDraft=true`，title `CodexBar 0.72.0.1 Mobile 2.6.0`）。
- `CodexBar-0.72.0.1-mobile.2.6.0.zip`：82,066,696 bytes，SHA256 `e3d6ec687e8e02a8574ff6f4c494e79bf07eaa64982e55b00099f770e3fb3c97`。
- `CodexBar-0.72.0.1-mobile.2.6.0.dSYM.zip`：67,309,524 bytes，SHA256 `1ce5c173dc1c04b268980859ef5ff6370f4a9e643df8ac742e5ec4dd90d26d09`。
- 本地 SHA256 与 GitHub asset digest 一致。

## 实际包验证

从发行 ZIP 解包（SSD scratch `verify-zip`）：arm64 + x86_64；`codesign --verify --deep --strict` 通过；Gatekeeper `accepted / Notarized Developer ID`（Yuxiao Wang 3TUERHN53E）；`stapler validate` 成功；entitlements `com.apple.developer.icloud-container-environment = Production`、容器 `iCloud.com.o1xhack.codexbar`。发布脚本的 dSYM 配对与启动 smoke（不可读 checkout 下 2s 存活、资源探测）通过。

## 过程

- phase 1 第一次运行在签名前的 lint harness `test_keyboard_interrupt_drains_children_and_propagates` 计时等待超时失败（未签名、未推 tag）；重跑 lint 全部通过并完成构建、签名、公证、推 tag、建 Draft（`mac072-release-phase1-r2.log` exit 0）。
- 发布 staging 与 TMPDIR 均在 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v072/`。
- CloudKit：`NO_DEPLOY`（见 `docs/cloudkit-deploy-audit.md` v0.72.0.1 节）。

## Final CI 与公开发布

- 合并后 Final CI [37589616349](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/37589616349)（merge commit `5948797ec`）：changes、lint、macOS compatibility build、6 个 macOS 测试 shard、Linux CLI（x64/arm64/musl）与 aggregate `lint-build-test` 全部 success。
- Final CI 通过后在 mobile-dev（HEAD = origin = `5948797ec`，tag 包含其中）运行 `./Scripts/release.sh --finalize`：Release 公开（`isDraft=false`，2026-10-07T10:00:25Z，Latest），下载 enclosure 重新校验 Sparkle 签名与长度，appcast 提交 `825f68e86` 推送到 mobile-dev；raw appcast 回读 `sparkle:version 164.1.2.6.0` / `shortVersionString 0.72.0.1`。
- 正式 Release：https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.72.0.1-mobile.2.6.0
- issue #177、#178、#179 已逐个回复正式 release URL 与完成说明后 `Close as completed`。
- iOS 2.6.0 (235) 未上传 TestFlight/App Store（用户选择本轮只发布 Mac）。
