# v0.83.0 单版本上游同步候选

状态：done（研究、实现、本地门禁与候选产物完成；PR审查/合并/正式发布以04及PR当前状态为准）。启动日期：2026-11-06。

## 冻结范围与版本计划

从最新 origin/mobile-dev `0d3099448c73f0e7274b487be2d0775ab56a90be` 创建 `upstream-sync/v0.83.0-mobile.3.3.0`。
基线 version.env v0.82.0 / 2026-10-28；GitHub Releases 最新稳定版 v0.83.0（2026-10-31T10:12:05Z）。本轮仅合并该 tag，后续 release 留待下轮。open upstream-sync 只有 [#231](https://github.com/o1xhack/CodexBar-Mobile/issues/231)，无缺失提醒版本。

Mac 计划 0.83.0.1 / BUILD_NUMBER 176.1；ASC 实时确认 3.3.0 READY_FOR_DISTRIBUTION，故 MOBILE_VERSION=3.3.0，Sparkle176.1.3.3.0。iOS 项目已有待交付3.5.0(262)，保留营销版本，本轮统一增加为3.5.0(263)；候选不声称已交付。

## 方案

完整 merge 上游v0.83.0，逐块保留fork身份、README、CI触发策略、签名/Production环境和iOS数据通道。上游380文件变化逐项清单保存在evidence；release notes逐项追踪Mac、Shared/Sync、iOS，重点审计OpenDesign、新余额/奖励额度/无限窗口、账号别名、plugin展示、成本归档与fleet重试。

先完成模型/通道，再适配展示与测试；原有Duo页面布局、选择和操作语义保持。研究、实现、版本与打包均在任务分支。Mac签名公证使用no-tag draft模式；iOS仅本地Archive与签名验证。完整候选本地独立审查通过后push/PR，并完成GitHub当前head审查。

## 环境与风险

StudioSSD已挂载且UUID匹配9D5FE511-B66C-4765-BB8F-61E5ACB3969D，working入口为预期symlink，repo realpath位于SSD并可写。Xcode27.2(27B52)、iOS/macOS SDK27.2。构建/Archive/大型证据使用BuildScratch。原有未跟踪error.log/work不属于本轮。

上游fetch拒绝覆盖历史同名tag；未force，本轮v0.83.0远端peeled commit已冻结为 `348e2fa8d36ae8e452739ca07a79e83ab9d25e98`。不得运行真实provider/Keychain读取探测。兼容矩阵、CloudKit审计和Duo实际验证分别记录，替代验证不得冒充实体收敛。

授权：本地打包/签名公证、Mac draft和附件、任务push/PR及审查。未授权merge/auto-merge、tag push、live release/appcast、TestFlight/App Review、CloudKit deploy、关闭issue。最终按真实结果交接。
