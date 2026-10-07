# v0.71.0–v0.72.0 单版本上游同步 + iOS 2.6.0

Status: `done`
Date: 2026-10-06

## 范围与依据

- 基线：`version.env` 为 `UPSTREAM_VERSION=v0.70.0`、`UPSTREAM_SYNC_DATE=2026-09-30`，Mac `0.70.0.1 / 161.1 / Mobile 2.4.0`（最后公开 release `v0.70.0.1-mobile.2.4.0`，2026-10-03）。
- 上游事实：`gh release list --repo steipete/CodexBar` 于 2026-10-06 读取，最新正式版 v0.72.0（2026-10-04T19:33:35Z），其间 v0.71.0（10-02）、v0.71.1（10-03）。原文存 `upstream-v0710.json`、`upstream-v0711.json`、`upstream-v0720.json`；`v0.70.0..v0.72.0` 共 151 个非 merge commit，清单 `upstream-commits.txt`。
- open upstream-sync issue：[#177](https://github.com/o1xhack/CodexBar-Mobile/issues/177) v0.71.0、[#178](https://github.com/o1xhack/CodexBar-Mobile/issues/178) v0.71.1、[#179](https://github.com/o1xhack/CodexBar-Mobile/issues/179) v0.72.0。本轮一次同步到 v0.72.0，三个 issue 合并为一个用户可见版本，不拆版本。
- 历史 closed issue：#166（v0.69.0）由 Research 062 / PR #168–#170 闭环；#150/#151 由 Research 059 闭环；更早见 Research 索引。本轮不重开这些范围。#134（非 upstream-sync 标签）不在本轮范围。
- iOS 现状：mobile-dev 已是 2.5.0 (234)，App Store 2.5.0 发布说明/审核备注已写入（`AppStoreMetadata/2.5.0/`，备注写明配套 Mac 仍为 0.70.0.1 Mobile 2.4.0）。为不改动已准备送审的 2.5.0，本轮 iOS 新功能进入 **2.6.0**。

## 分支

- 从最新 `origin/mobile-dev`（`36ea0a8630347a2fd3141f5ae050a07785b5c074`）创建独立 worktree `/Volumes/StudioSSD/Projects/working/apple/CodexBar-upstream-v072`，分支 `upstream-sync/v0.72.0-mobile.2.6.0`。原 checkout 保持 mobile-dev 不动。
- StudioSSD 挂载、UUID `9D5FE511-B66C-4765-BB8F-61E5ACB3969D`、realpath、可写检查通过；构建/日志 scratch 位于 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v072`。
- 所有调研、实现、版本、测试、打包准备只在该分支进行。

## 版本号方案（docs/versioning.md）

| 字段 | 值 | 依据 |
|---|---|---|
| `MARKETING_VERSION` | `0.72.0.1` | 上游 tag v0.72.0 + fork 第 1 版 |
| `BUILD_NUMBER` | `164.1` | 上游 v0.72.0 `BUILD_NUMBER=164` + fork `.1` |
| `MOBILE_VERSION` | `2.6.0` | 本轮配套 iOS 版本（沿用 062 中 Mac Draft 配套同轮 iOS 版本的做法） |
| `UPSTREAM_VERSION` | `v0.72.0` | |
| `UPSTREAM_SYNC_DATE` | `2026-10-04` | 上游 v0.72.0 发布日期 |
| Sparkle `sparkle:version` | `164.1.2.6.0` | `BUILD_NUMBER.MOBILE_VERSION`，大于已发布 `161.1.2.4.0` |
| Tag | `v0.72.0.1-mobile.2.6.0` | |
| Zip | `CodexBar-0.72.0.1-mobile.2.6.0.zip` | |
| iOS | `2.6.0 (235)`，全部 target 同步 | 2.5.0 (234) 之后 |

若签名前用户决定 Mac 先配套已上线的 iOS 版本，只调整 `MOBILE_VERSION`/tag，不拆本轮上游内容。

## 文档

- [01-design.md](01-design.md) — 合并规则、Mac→iOS 数据通道设计、CloudKit 判断
- [02-implementation.md](02-implementation.md) — 冲突决策与实现记录
- [03-testing.md](03-testing.md) — 测试计划、命令证据、16 组合兼容矩阵
- [04-mac-release.md](04-mac-release.md) — Mac 签名、Draft、Final CI 与公开发布
- [05-ios-release.md](05-ios-release.md) — iOS 2.6.0 (235) 上传与提交审核
- [06-ios-impact-audit.md](06-ios-impact-audit.md) — 上游逐项 iOS 影响审计

## 最终交付状态（2026-10-07）

- **Mac**：`0.72.0.1 / 164.1 / Mobile 2.6.0` 已签名、公证并**公开发布**（用户在本 Goal 中明确授权 Mac 全流程发布）：https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.72.0.1-mobile.2.6.0 ，appcast 已更新（`825f68e86`）。详见 04。
- **PR**：[#180](https://github.com/o1xhack/CodexBar-Mobile/pull/180) 3 轮 Codex review 后 clean（head `000bd2570`），review gate 通过，合并为 `5948797ec`；Final CI 全绿。
- **iOS**：2.6.0 (235) 已上传（build VALID）并于 2026-10-07 提交审核，`WAITING_FOR_REVIEW` / MANUAL，详见 05；完整单测 958 Swift Testing + 58/12/9 XCTest 通过。
- **测试**：Mac 最终 head 隔离全量 1593 selections / 144 组（1 组 WebKit fixture 超时重试恢复）；lint 全绿；16 组合同步兼容 gate 全部 substituted 且通过（见 03）。
- **CloudKit**：`NO_DEPLOY`。
- **issue**：#177/#178/#179 已回复正式 release 并关闭。
- **未覆盖风险**：实体 2 Mac × 2 iPhone、Production CloudKit 收敛与 APNs 时序、新 provider 真实账户数据、人工 VoiceOver 未验证；旧 iPhone 不会订阅 museai/workbuddy 推送 zone，旧 iPhone 上 Grok/LithosAI 余额卡 period 显示英文原文。
