# 上游同步 Goal 模板

以下正文用于启动一次上游同步；通用开发与审查规范由 `AGENTS.md` 路由。

```text
将当前所有 open upstream-sync issue 涵盖的上游更新合并为一个候选版本交付。
遵循 AGENTS.md 及其引用规范，本 Goal 已确认先调研、再实现的单版本方案。

以 version.env 的 UPSTREAM_VERSION / UPSTREAM_SYNC_DATE 为同步基线，以
steipete/CodexBar GitHub Releases 为事实。启动时确认最新稳定 release，补齐
尚无提醒 issue 的版本，记录并冻结本轮范围；执行期间的新 release 留待下轮。

完成必要只读预检与版本判断后，从最新 mobile-dev 创建
upstream-sync/<target-upstream>-mobile.<target-mobile> 分支。
本轮 Research、实现、测试、版本更新和打包准备均在该分支进行。

先在 CodexBarMobile/Research/NNN-*/ 记录范围、方案、版本计划和风险，再实现：
1. 完整同步目标上游的 Mac 功能、修复、性能和安全改动，并保留 fork 约束。
2. 逐项追踪上游变化到 Mac、Shared/Sync 和 iOS；补齐必要的数据通道、兼容、
   展示和操作。不适用或不能支持的项目说明原因，不遗漏数据层影响。
3. 保护现有产品能力，尤其 Duo 各页面布局与跨姿态交互；按仓库规范回归。
4. 独立核对 Mac 配套 MOBILE_VERSION、iOS project.yml 与已交付版本，形成
   一个版本计划；完成适用的本地化、release notes、CloudKit 审计和同步矩阵。
5. 完成 Mac 签名公证与不推送 tag 的 draft release，以及 iOS 本地 Archive
   和签名检查。记录真实 source commit、hash 和 draft 占位 target；review
   修复影响二进制后重建对应产物，保证最终候选与 reviewed source 一致。

本 Goal 额外授权本轮 Mac draft 创建/更新、其附件上传，以及上述本地打包与
现有已授权签名凭证的使用。push/PR 和两轮 review 按仓库默认开发交付流程执行。

完成标准：上游范围完整落地、iOS 影响逐项有结论，适用测试与回归通过，最终
本地和 PR review 无未解决问题；Research 记录矩阵、替代验证和风险、CloudKit
结论、候选产物、draft、PR 与 issues 对应关系。

达到仓库规定的决策交接点后，询问是否合并 PR，以及是否执行 Mac 正式发布和
iOS 的具体交付阶段。未经另行授权不 merge/auto-merge、不推送 tag、不发布
live release/appcast、不上传 TestFlight/提交 App Review、不 deploy CloudKit
schema，也不关闭 upstream-sync issues。阻塞只暂停依赖该决策的部分。
```
