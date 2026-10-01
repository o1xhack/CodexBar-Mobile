# Review、合并与 2.3.0 (226) 上传

Status: `in-progress`

用户授权推送PR、循环review、合并后上传TestFlight；仍不提交App Review。
此前upstream-sync PR已合并，widget与旧Mac修复尚未推送，因此创建完整2.3.0后续PR。
版本保留2.3.0，全部target构建号226。225已经在TestFlight，不能重复上传。
本次PR包含widget多选/布局/刷新倒计时、旧Mac日期费用小计、四语言资源及测试。
已完成的878单测、3UI、实机和16-mask替代证据见03-testing.md。
226将在当前head review gate通过并合并后由merge commit打包，记录来源与产物。
