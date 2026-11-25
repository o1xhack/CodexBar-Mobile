# CodexBar v0.84.0 和 v0.85.0 上游同步候选

状态：done（实现与本地验收完成，发布交接见 PR）

冻结日期：2026-11-24

跟踪：[v0.84.0 #235](https://github.com/o1xhack/CodexBar-Mobile/issues/235)、[v0.85.0 #236](https://github.com/o1xhack/CodexBar-Mobile/issues/236)

| 项目 | 冻结值 |
|---|---|
| Fork 起点 | mobile-dev `b78652c6d4abe0c0d2cf3e2de7cb6069d1abcb3b` |
| 既有上游基线 | v0.83.0 `348e2fa8d36ae8e452739ca07a79e83ab9d25e98`，2026-11-06 |
| 中间正式版本 | v0.84.0 `5bebf9a05e68059eae11d5031c7239f1aa1d49ef` |
| 本轮目标 | v0.85.0 `5dd48cab770a326691b25a124d37ffee12c5f7ac` |
| 上游改动规模 | 173 commits，708 个文件 |
| Mac 候选 | 0.85.0.1 / 178.1 / Sparkle 178.1.3.5.0 |
| 已交付 iOS | 3.5.0，App Store Connect 显示 READY_FOR_DISTRIBUTION |
| iOS 候选计划 | 3.6.0 (264)，ASC 最新上传构建为 3.5.0 (263) |

## 方案和风险

- 在最新 mobile-dev 创建独立 worktree，并直接合入已发布的 v0.85.0 标签，承接 v0.84.0 的历史。保留 fork README、CI、签名脚本和 Appcast。单独审查上游 README 事实变更。
- 逐项追踪 Provider 注册、额度和余额语义、成本价格与归属、Claude 账号展示以及 Widget 改动。沿 Mac 生产、Shared 编码、CloudKit、iOS merge/cache、卡片及 Widget 检查需要移植的字段和回退。
- Deferred Mac UI、浏览器导入、CLI 与 Linux 变化按平台验证。严查账户身份、金额单位、旧版 Codable 和多设备去重。CloudKit Production 先审计，部署另行授权。
- 测试记录覆盖 Mac 本地发布测试、iOS 测试、四语言、普通屏幕及 Duo、16 组合兼容证据。签名 Mac ZIP 和 dSYM、iOS Archive 绑定实际源码与哈希。独立本地审查及 PR 审查通过后交接。
- 本轮授权涵盖 Mac 草稿及附件、iOS 本地 Archive。正式合并、标签、发布、TestFlight 与 CloudKit 部署留待决策。
