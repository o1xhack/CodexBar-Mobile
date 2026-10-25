# 性能与回归验证

状态：done（本地测试与独立 CR 完成，远端 CR / 发布单独记录）。

- 相同197个显示点、5条额度、768pt原生Hosting布局：旧代码3.784963209秒，新代码0.213762125秒。单次同条件对比，不能解释为真机帧率；原始baseline曾因错误的provider历史条数假设失败，已保留失败证据。
- 新版2项性能测试和9项详情模型测试通过，包括20,000条真实结构样本完整保留、历史缺口、固定时间域、来源更新后的最新日期。
- 首次Duo UI测试实际运行在折叠外屏，在进入详情之前的卡片排序前置步骤失败；不计作详情验证通过。
- Air Release开发签名构建通过；PUA服务可在设备网络地址响应，但USB转发未枚举设备。工具拒绝非loopback地址，未绕过限制；使用原生Xcode UI测试作为真机验证路径。
- 全量 iOS 测试通过：xcresult 汇总 1,337 项通过、1 项 EventKit 真日历集成测试跳过、零失败（日志含 73 项 XCTest 和 1,265 项 Swift Testing）。标准 portable lint 与四语审计通过；独立本地 CR 无阻塞发现。
- 普通 iPhone 横竖屏、滑块/聚焦/非默认账户下钻 UI 测试2项通过；展开 Duo 横屏、竖屏各1项完整 App UI 测试通过（含 Summary、详情、账户下钻、Usage、Cost、Setting）。模拟器使用测试数据，Air使用真实历史；不声称已经在真实 Duo 测过性能。
- 后续：远端 CR、合并与 3.2.0 (258) TestFlight 发布证据。

证据根目录：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/QuotaDetailPerformance-3.2.0-258`。

## 真机确认

Air 显式安装新 Release 包并使用无参数 `launch()` 重启后，`air-installed-release.xcresult` 完整用例通过。开详情0.9925秒、聚焦0.4574秒、显示全部0.5316秒、打开/关闭设置1.0968/1.0499秒；这些包含XCTest传输与idle等待，并非touch-to-frame延迟。滑块、纵滚和设置原样退出通过，账户/选线未被修改。

系统滚动metric报告0 hitches、0ms hitch duration和110.59fps，但同一结果的frame count为0，故不把该FPS字段当作可靠帧率承诺；保存原始指标并以交互结果和原生布局基准共同判断。此前activate-only的14–18秒记录没有新二进制运行证明，不能归为修复版；另有一次测试measurement stop模式配置异常，两类失败原样保留。测试已修为明确安装后launch，并为LiveQA scheme配置唯一selectedTests，默认模拟器跳过，真机需显式opt-in。

本轮不改Mac、Shared payload、CloudKit schema或持久缓存。视图快照随来源/偏好/账户/时钟输入刷新；没有新的同步格式，CloudKit Production无需schema部署。

## 线宽微调验证

共享曲线默认 1.9 pt、聚焦 2.3 pt。现有生产组件渲染矩阵32种宽度/明暗/字号组合通过；实际查看普通手机深色和Duo宽度浅色渲染。两项原生性能测试通过，197点详情首次布局0.2598秒（低于1秒回归阈值）。SwiftFormat与四语审计通过。证据：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/QuotaLineWeight/render.xcresult`。用户要求本轮完整走本地CR、远端PR/CR、合并及259 TestFlight；发布回执另存 QuotaLineWeight-3.2.0-259，258发布证据不作改写。

259发布前：独立本地CR无finding；完整iOS测试结果见本轮units.xcresult（1,337通过、1条件跳过、0失败），portable lint及四语审计通过。无同步格式、缓存或CloudKit schema变更，Production无需schema部署。
