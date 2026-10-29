# v0.80.0–v0.82.0 单版本上游同步

状态：`done`。2026-10-29 已按授权合并 PR #225（及必要修复 #227/#228）、公开 Mac 0.82.0.1，并提交 iOS 3.3.0 (261) App Review（WAITING_FOR_REVIEW / AFTER_APPROVAL）。最新实际版本、产物 hash、CI 和状态见 [08-public-release.md](08-public-release.md)。下文保留 2026-10-28 候选阶段历史；其中未发布/未上传/placeholder/旧产物表述不代表当前状态。

## 冻结范围

- 分支：`upstream-sync/v0.82.0-mobile.3.3.0`，从最新 `origin/mobile-dev` `bdfb510853270c1ebf6b9d6f5ccbb289a2634db1` 创建。原有未跟踪 error.log / work/ 不属于本轮。
- version.env 基线：v0.79.0 / 2026-10-21；Mac 0.79.0.1 / 172.1 / Mobile 3.1.0。iOS 项目为 3.2.0 (260)。
- 起始 open upstream-sync：[221](https://github.com/o1xhack/CodexBar-Mobile/issues/221)、[222](https://github.com/o1xhack/CodexBar-Mobile/issues/222)。
- 官方 Releases 确认 v0.80.0、v0.81.0、v0.82.0；最新稳定 v0.82.0 发布于 2026-10-26T23:41:31Z，目标 commit `7749f7b94ae8f1b84b9ffb2046643cec810f4078`，远端 peeled tag 已核对。本轮不追逐随后新增 release。
- 只合并最终 v0.82.0，累计 697 文件（含大量 rename）、24202 additions / 4554 deletions；不拆用户版本。
- 历史 closed #196/#193 与 Research079：单 train 包含未有提醒的 release；只有 Mac public release 后才回帖完成并关闭 Issue。本轮 PR 仅关联，不用 closing keywords。
- 全量 release notes、提交/文件清单存 evidence/，后续 06-ios-impact-audit.md 逐项归类与验收。

## 版本方案（候选阶段历史）

| 项目 | 候选值 | 依据 |
| --- | --- | --- |
| Mac MARKETING_VERSION | 0.82.0.1 | 上游三段 + 首个 fork 补丁；文档首部明确规则优先于遗留决策树 |
| BUILD_NUMBER | 175.1 | 上游 v0.82.0 整数 175，不擅自提升整数 |
| Mac MOBILE_VERSION | 3.2.0 | ASC 实时读取确认 3.2.0 READY_FOR_DISTRIBUTION / READY_FOR_SALE；不把未上传 3.3 当已交付 |
| Sparkle / CFBundleVersion | 175.1.3.2.0 | 大于最近 published 172.1.3.1.0 |
| draft 逻辑 tag | v0.82.0.1-mobile.3.2.0 | 不创建/推送真实 tag；source commit 与 draft 占位 target 分开记录 |
| iOS | 3.3.0 (261) | 3.2.0 (260) 已发布，最新上传260 VALID；本轮增加 provider/数据展示能力，全部 targets 一致 |

若后续用户授权先交付 iOS3.3再正式发布 Mac，正式发布前重新核实 companion 并更新候选包；不在本 Goal 未上传时声称3.3已配套交付。本轮只准备一个 Mac 候选版本。

## 环境与边界（候选阶段历史）

StudioSSD UUID、working symbolic link、项目 realpath 与 BuildScratch 可写检查已通过。Xcode27.1 / 27A9275，iOS SDK27.1、macOS SDK27.0；iOS26.5/27.0/27.1 runtime 可用；最低 iOS17 保持不变。大型构建、Archive、结果和临时模型仅写 BuildScratch。

用户授权本轮本地构建/签名公证、无 tag draft及附件、任务分支push/PR与两轮review；未授权 merge/tag/live release/appcast/TestFlight/App Review/CloudKit deploy/Issue关闭。签名使用已授权凭证；不运行会触发 Keychain UI 的真实 provider/cookie 探测。上游 fetch 曾拒绝覆盖若干历史同名 tag，未 force；本轮 v0.80/81/82 已成功获取且目标hash与远端匹配。



## 最终候选验收（2026-10-28）

当前产品源码：`18ebb97272a68853473b3c3c565fc56f719901e2`，后续仅补文档/证据。Mac Group/CLI 修复后重新构建、公证与校验；旧草稿包已hold，最终附件替换结果见04。iOS原353项Archive输入重新逐项SHA256核对不变（evidence/ios-archive-final-input-equivalence.json），保留a36来源Archive。

- 最终Mac受影响128 selections/43组全部首遍PASS，0fail/timeout/retry；与成本修复97项及原完整gate1620项去重，覆盖1845 selections/16194 method identifiers。123个条件XCTest skip及Swift Testing opt-in early-return限制保留；不是单一最终binary全量body通过。见evidence/mac-appgroup-final-coverage-review.md与proof。
- `mac-appgroup-full-lint.log`完整lint与`mac-appgroup-final-build.log`的swift build --jobs4通过；SwiftLint 3211文件0违规，4语言533keys、parser24/hash、CI/fork guards通过。16个打包合同及timestamp retry stub通过。
- 真实Developer ID签名QA正负控：独立nonce group的声明成员可open，无成员EPERM；containerURL非nil不能证明授权。未操作用户业务容器，任务QA容器已清理。最终App/CLI runtime group均与Widget签名Group一致，生产包本身单独验证。
- Mac最终双架构App/CLI/Watchdog/Widget均Developer ID、hardened runtime、minOS14.0；App与dSYM双架构UUID一致。公证`343e9fc0-4ac2-4f2e-9300-c0492953d430` Accepted，stapler、distribution policy、隔离启动通过。
- Sparkle175.1.3.2.0单调递增；最终ZIP长度92810809、Ed25519以及实际App内SUPublicEDKey客户端校验均通过。仅scratch候选appcast，仓库feed无修改。
- iOS全量1278 Swift Testing/85 suites +75 XCTest及后续150 tests/6 suites通过；普通iPhone/iPad、Duo实际内外屏横竖、partial和跨折叠操作、严格SpringBoard Widget及四语原生渲染证据继续有效。
- 16组合全部为 **substituted**（64 reads/32真实冻结consumer merges），没有实体双Mac/双iPhone CloudKit/APNs/缓存收敛实测。CloudKit结论 **NO_DEPLOY**；本轮Group仅Mac本地共享容器，iOS/Shared wire不变。
- GitHub已对7f6bdc416返回clean，Fast Checks通过；最终收尾文档仍需current-head复核，动态结果以PR225为准。未merge/tag/live/feed发布或iOS上传。Final CI在授权合并后执行。

## PR对应关系

已合并PR [#225](https://github.com/o1xhack/CodexBar-Mobile/pull/225) → 已关闭 upstream-sync #221/#222，累计v0.80–v0.82一个版本。已合并代码 PR #225/#227/#228 的各自候选 head 审查与门禁已完成；本收尾文档分支的门禁及正式交付按08。
