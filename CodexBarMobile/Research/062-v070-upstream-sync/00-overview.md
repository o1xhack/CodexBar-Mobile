# v0.69.0–v0.70.0 单版本上游同步

Status: `in-progress`
Date: 2026-10-01

## 权威范围与分支

基线为最新 origin/mobile-dev `322865d30b7f9611effe08648c76e461446c63e4`，version.env 为 v0.68.0 / 2026-09-27。2026-10-01 GitHub Releases 核对：v0.69.0（2026-09-28）和 v0.70.0（2026-09-30）均已正式发布。全部 open upstream-sync issue 只有 [#166](https://github.com/o1xhack/CodexBar-Mobile/issues/166)，自动化仅列 v0.69.0；本轮涵盖其全部范围并一次同步到正式最新 v0.70.0，不拆版本。

从最新 origin/mobile-dev 创建独立 worktree `/Volumes/StudioSSD/Projects/working/apple/CodexBar-upstream-v070`，分支 `upstream-sync/v0.70.0-mobile.2.4.0`。原 checkout 的 release/ios-230-build226-evidence 分支和未提交的 Git workflow skill 修改原样保留。挂载、UUID 9D5FE511-B66C-4765-BB8F-61E5ACB3969D、realpath 和可写检查通过。后续实现、Research、版本及发布准备只在此任务分支。

历史 #150 / #151 已由 Research 059、PR #155–#162 的 v0.68.0 单版本同步闭环覆盖；不重开这些范围。历史陈述以本轮查询到的 closed issues 和现有 Research 为依据，不替代本轮测试。

## 重点变化

v0.69.0：插件 top-level 默认 tab、Notion/ZoomMate/LongCat 转 bundled plugin；host-owned cookies、缓存迁移、安全环境脱敏；Codex 凭证 publication race 和 plan transition；Claude OAuth cache recovery、limit resets；Claude/Vertex cache CPU/IO 优化和稀疏日期扫描；Grok billing fallback 与本地 token/model history；Kimi monthly blocking、Antigravity grouped/Starter weekly quota；widgets last-good per-provider preservation。

v0.70.0：Codex/Claude quota burndown、16 个品牌 accents；Mistral event/zone/tier pricing 与 Monthly Plan metric；模型 alias 和历史 Sol/Cyber rates；全量 stored process environment redaction 及 guard；大进程表 cancellation cleanup 和 dashboard layout。

全部原文见 upstream-v069.json、upstream-v070.json。完整非 merge commit 清单见 upstream-commits.txt；重点 PR #4048/#4059/#4098/#4091/#4084/#4085/#4075/#4106/#4076/#4094/#4108 必须逐项检查源代码与 iOS 数据路径。

## 版本方案

上游 v0.70.0 version.env 为 0.70.0 / 161。本轮 Mac 0.70.0.1 / 161.1；iOS 候选 2.4.0 (227)，四个 target 一起更新。docs/versioning.md 顶部四段规则优先于下方仍残留的旧决策树。Mac MOBILE_VERSION 暂保留最新已发布 Mac 配套 2.3.0，Sparkle 为 161.1.2.3.0，候选 draft tag 名 v0.70.0.1-mobile.2.3.0；分支 mobile.2.4.0 表示本轮 iOS 开发目标，不声明它已经 ship。若用户后续确认本轮 Mac 也配套 2.4.0，再在签名前统一最终值，不另拆本轮上游版本。

## 授权与未完成项

Goal 已确认本方案的调研、实现、本地测试、review 和 Mac draft 准备。禁止 origin push、merge、tag publish、live release、TestFlight upload。实际凭证使用与 schema deploy 按 Goal 暂停确认。GitHub draft 不能让 CLI 隐式创建远程 tag；先核对可用无 tag-publish 路径再创建。仅本地打包不等同 GitHub draft 完成。

当前生产源码 checkpoint 为 `9974283e2`。Mac 完整回归 mac-full-r5 exit0（1520 selections /137组、0 retries/timeouts），双架构 unsigned Release compiler 预检通过。iOS 2.4.0 (227) 已实现数据持久化、实际采样 quota pace、monthly blocking、模型名、provider 呈现及四语言说明；原始 Swift Testing 在 iOS26.5 Simulator 313项/15 suites 通过，完整旧 schema migration 在其中。生产图表离屏渲染为四语言×两外观×两宽度，并补跨午夜24h fixture，共32 PNG。16 old/new组合以冻结 wire、真实 merger 和独立 iOS 磁盘缓存替代验证；32缓存、96独立进程全部通过。以上替代证据不证明 VoiceOver、Production CloudKit/APNs 或实体四设备；另有四语言真实 App quota 导航通过证据。

验收发现 ProviderColorPalette 同时被 WidgetActivityView 与 CodexBarWidgetView 使用，因此触发 Widget render matrix 和真实 SpringBoard gate；313项中的 WidgetSnapshotBuilder 不能代替渲染测试。现已补原始矩阵5/6方法通过，以及仅适配附件持久化后的6/6方法、220次离屏渲染与12张视觉图；标准XCTest附件现已生成，真实SpringBoard gate仍未完成，详见03。最终axis输入在iOS27复验313项/15 suites exit0；标准Widget原六方法全部通过，真实App四语言quota UI在修复辅助功能容器后exit0；人工VoiceOver未完成；实际SpringBoard配置已验证持久化，但主Widget timeline占位/XPC错误仍待查。最新本地 review clean 不等同 GitHub PR/CR。PR、merge、签名公证和 Mac draft 均未执行，Goal 保持 in-progress。逐项验收见07-acceptance-audit.md。

## 用户调整执行顺序

用户明确要求先完成 iOS 实现、本地测试、兼容验证与 review，再考虑 Mac draft；此前凭据确认不再阻断 iOS 阶段。GitHub PR + CR 的 push 授权正在确认，未得到明确回复前不 push、不开 PR；merge、发布凭据与正式发布仍分别等待授权。原 Goal 全部交付范围保留。
