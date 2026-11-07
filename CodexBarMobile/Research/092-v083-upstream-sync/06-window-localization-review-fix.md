# 追加远端审查：额度名称本地化分发

状态：done（修复、验证及Archive重建完成；最终远端当前head复审仍以PR实时结果为准）。

当前head 5b79c3a61的远端审查发现P2：ProviderWindowLabel.localizationKey已识别Organization/Rewards，localized后续switch没有分发这两个key，导致落入Extra usage。修复为复用现有英文catalog key分支，四语言翻译无需变更；测试直接断言两个provider最终localized输出的全部四语言，防止仅检查key映射漏检。

影响App及Widget共享展示代码；不改变数据、布局或CloudKit schema。需重跑iOS单元/相关呈现回归，重建本地Archive，更新shipping来源与hash。Mac 1835项构建输入不受影响，既有a6候选继续适用。

## 验证与替换

c5227b588实际source全量iOS单元1375 passed / 1 skipped / 0 failed；1301 Swift Testing tests / 87 suites，以及75 XCTest（含skip）。新增测试直接检查8个最终字符串，全部通过；WidgetRenderMatrix和SnapshotBuilder随全量门禁执行。SwiftFormat通过；额外直接对Mobile文件运行根目录SwiftLint配置发现的3项既有complexity/tuple告警与5b79基线完全一致、无新增，根目录常规严格lint本就只覆盖Sources/Tests。

iOS本地Archive已从c5227b588重建并替换最终路径，旧23ff候选保存在superseded-ios-23ff6887。四角色签名/版本、主App/Push/Widget Production、WidgetOptions AppGroup-only、compiled英文catalog（含release notes）与现有翻译一致、全部353个shipping输入均重新验证；新ZIP SHA256 c473659b006cd198bf880ebe1f21165d0943c4a1b008838b60346045d89e51fd。没有IPA导出或ASC上传。

此前真实Duo/SE/iPad/SpringBoard交互证据保留原source与安装hash：本次仅补齐两条catalog dispatch，不改变布局、导航、操作状态、配置交互或同步wire，依仓库规则保留仍有效的原证据，不称旧截图为新二进制实测。新全量unit/render门禁覆盖修复后的共享实现。Mac1835构建输入仍与a6ab1035b相同，不重建Mac包。
