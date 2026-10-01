# 旧 Mac 历史费用在 iOS 2.3.0 被隐藏

Status: `done`
Date: 2026-09-30
Branch: `fix/ios-230-legacy-mac-compatibility`

## 实际证据与根因

用户截图和 Air 镜像确认 iOS 2.3.0 (224)、两台 Mac 0.58.0.1。
Raw Sync Data 有两台 Mac 的 Claude/Codex 历史及 Today 费用；365 Days
Overview 金额及 Top Driver 为「—」，费用诊断全部显示 No cost total。
因此不能归因为 CloudKit 未同步或要求用户升级 Mac。

`CostDashboardInsights.fromLedger` 在账本中保留已定价日的金额，但
`dailyPointsCoverSelectedWindow` 要求完整覆盖选中范围；50/200 天 producer
与 365 天 reader 不满足该条件。Overview 直接把完整覆盖判定作为金额显示
条件，Provider Share/Top Driver 还会滤掉这些已有金额的行。
回归引入于 `f2404073f`：之前 ledgerCostIsKnown 判断是否存在可计价点；
2.3.0 改为要求覆盖每一天，却未另设小计显示状态。旧 Mac 缺省 additive
字段能解码，问题位于 reader 的费用展示策略。

Air 的实际设置还暴露 CWL 关闭路径：两台 Mac 同账户的 50/200 天扫描
被 Merger 写入 historyWindowIsComparable=false，旧 Overview 也因此
隐藏金额。该标志限制扫描总额，而不撤销仍标为 known 的每日费用。
同样的短历史场景在新 Mac 上也可能发生，不应仅按 appVersion 特判。

## 修复设计

保留现有完整覆盖判定；另行区分「已有已定价贡献」与「完整总额」。
存在有效已定价历史贡献时显示已知小计并标 ≥，保留历史不完整提示，
排行及占比仅依据已知费用。无定价数据仍显示「—」，不把未知费用算成零。
不复活明确清除、非 USD 或 costIsKnown=false 的费用。周期总额不可比较时，
只按 reader 日期范围计算逐日已知费用，标题改为 Known history；绝不相加
不同周期的原始总额。现代/旧格式都使用这条日期小计规则。
同步 payload、CloudKit schema、Mac writer 不变，无需 schema deploy。

## 验证计划

使用旧 Mac 缺省字段/稀疏历史，在真实 fromLedger→Overview/diagnostics
链路复现 365 天 reader；覆盖已知/未知混合、零数据、不可比较窗口、
新旧 writer 混合、30/90/365 天。新增 focused regression，并执行构建、
成本测试与界面验证。实机替代与真实 Production 证据分别记录；不声称
上一轮 16 个替代组合已证明所有真实旧 Mac 场景通过。

修复构建 2.3.0 (225) 已本地安装 Air，已上传并进入内测 TestFlight；App Store 草稿绑定225，未提交审核。用户个人
workflow skill 修改不在本次 diff。详见 03-testing.md。
