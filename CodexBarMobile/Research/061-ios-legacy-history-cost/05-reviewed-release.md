# Review、合并与 2.3.0 (226) 上传

Status: `in-progress`

用户授权推送PR、循环review、合并后上传TestFlight；仍不提交App Review。
此前upstream-sync PR已合并，widget与旧Mac修复尚未推送，因此创建完整2.3.0后续PR。
版本保留2.3.0，全部target构建号226。225已经在TestFlight，不能重复上传。
本次PR包含widget多选/布局/刷新倒计时、旧Mac日期费用小计、四语言资源及测试。
已完成的878单测、3UI、实机和16-mask替代证据见03-testing.md。
226将在当前head review gate通过并合并后由merge commit打包，记录来源与产物。

## PR #164 第一轮

Head 425d2edbb 返回4个P2：catalogue包含管理cost envelope、消失选择未标Unavailable、诊断混入未知费用、测试硬编码SSD目录。
统一picker/builder的envelope过滤，显式Unavailable，抽取producer/reader-calendar内已知日期小计供Overview/diagnostics共用，测试使用隔离临时目录并清理。
新增catalogue/builder一致性及unknown/future/expired/nonfinite金额回归，完整单测54 XCTest+826 Swift Testing共880项通过。
初次226完整单测878项、Release Simulator、lint通过；每次push后重新请求当前head review。

## PR #164 第二轮

Head 2dace41f8 返回2个P2：权威空sync未清catalogue，非Overview模式暴露无效provider selector。
把catalogue更新移到统一状态决策：nil+.noData/.synced清空，nil+syncing/error/incompatible保留。新增隔离磁盘清理/保留测试。
配置使用系统When/parameterSummary，仅Overview包含providers，其余模式保留mode/colorStyle。
参考：[Apple WidgetConfigurationIntent](https://developer.apple.com/documentation/appintents/widgetconfigurationintent)，核对本机SDK接口；生成metadata保留mode/colorStyle/providers及WidgetConfiguration protocol。条件展示仍需用户在真实widget editor验收，编译/渲染矩阵不等同系统editor实测。
完整单测55 XCTest+826 Swift Testing，共881项，0失败（legacy-history-226-review2-unit.log）。
