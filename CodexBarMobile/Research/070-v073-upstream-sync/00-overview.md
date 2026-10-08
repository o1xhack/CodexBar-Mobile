# v0.73.0 上游同步 + Mac 0.72.0.1 成本回归修复

Status: `done`
Date: 2026-10-08
Versions: Mac 0.73.0.1（BUILD_NUMBER 165.1，Sparkle 165.1.2.6.0，已公开发布），iOS 2.6.0 (237；238 另含小组件窗口选择，均在 TestFlight)
Branch: `upstream-sync/v0.73.0-mobile.2.6.0`

## 背景

2026-10-07 发布的 Mac 0.72.0.1 带入了上游 v0.72.0 的 Codex request-ledger 缺陷。用户升级后：
- iPhone 成本页“本地历史”从约 $15.5k 降到 $9.4k，今天没有数据；
- Studio 的 Claude 一度变成空卡；
- Studio 的 iCloud 推送大量失败。

已采取的处置：
- appcast 回退到 0.70.0.1（提交 87a650953）；
- iOS 2.6.0 撤回审核；
- 用户决定直接同步上游 v0.73.0，Mac 修复版直接发布，iOS 上 TestFlight。

iPhone 账本的保护单独在 PR #184 修复，见 Research 069。

## 文档
- [01-design.md](01-design.md)：合并规则、Codex 成本根因与缓存重建、Claude 空条目、推送重试、Langdock、README 与 CloudKit 审计
- [03-testing.md](03-testing.md)：测试与兼容矩阵证据
- [04-mac-release.md](04-mac-release.md)：Mac 0.73.0.1 签名、公证、公开发布与 appcast 恢复
- [05-ios-testflight.md](05-ios-testflight.md)：iOS 2.6.0 (237/238) TestFlight、图标验收与送审前待办
