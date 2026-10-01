# Review、合并与 2.3.0 (226) 上传

Status: `done`

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

## 最终 review、合并与上传

- 第三轮current head `2150544273bda3904468aa76548859c09e130c75`收到Codex clean review；merge gate输出 rounds=3、unresolved=0。
- PR #164合并为 `405a2054e87f6bb7437d23c0860e6e59997fa421`；review head与merge的产品输入diff为空。
- [Final CI 36821527937](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/36821527937)成功；iOS-only路径按policy跳过Mac/Linux重矩阵。
- 合并源Release Archive、实际上传IPA均为2.3.0 (226)，主App/两个extension均Production。
- 本地最终Release Simulator、完整881单测、lint通过；Cost/share UI3/3，widget布局render矩阵在完整单测中通过。
- CloudKit NO_DEPLOY，Shared wire/schema未改变。
- Build/delivery ID `a1391f7b-5853-4d7d-9d13-cea3ed1e6f5e`：VALID、IN_BETA_TESTING，原内测组包含226。
- App Store2.3.0草稿已绑定226，仍PREPARE_FOR_SUBMISSION；四语言测试说明及What’s New回读一致。
- 未提交App Review/外测审核；225和224保持，未发布live release。

- Source tree: `a117e86a33ec95f79883392a26864225dde21221`
- Archive contents SHA256: `4848f526f4c0d7b309eb08c6ce742a75203cf53301b1e72baa69ea3fef697708`
- Uploaded IPA SHA256: `f7db00d5604599acb4426d2dd3264e5ec1da2ba5dc5e1f109b104f2a667022a1`

证据目录 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-2.3.0-226/` 保存archive、上传IPA、provenance、ASC readback、日志；所有新Apple打包TMPDIR也位于该目录下。
图标源文件与已检查225源相同；226编译图和Apple处理后的CDN图另行人工查看。

## 验证边界

Air实机证据为225、两个旧Mac0.58.0.1；226含review修复，物理手机/widget editor由用户TestFlight验收。
16兼容组合仍是03-testing.md定义的替代模型证据，不能声称完整真实四设备或后台push已实测。
Todoist保留QA等待用户验收，上传与public App Store release不等同。
后续提交审核时以本文件记录的reviewed merge source及产物provenance核对；纯文档closeout不改变226产品输入。
