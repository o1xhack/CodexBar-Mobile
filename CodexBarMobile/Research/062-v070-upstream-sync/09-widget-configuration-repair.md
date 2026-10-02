# 主 Widget 配置参数恢复修复

状态：in-progress（生产 SiriKit 接入已编译并通过 focused tests；实际编辑、迁移与四语言验收进行中）

## 问题与证据

真实 SpringBoard 保存非默认 mode，但 AppIntentTimelineProvider 收到 overview/mono/空 providers。标准 Xcode Simulator 权限已恢复 timeline；纯 enum whole-bundle 原型仍失败。显式 CaseIterable、固定 allCases/supportedValues 均不能恢复用户选择。详情及 source/artifact/evidence manifests 见 03-testing.md。不能用编译通过、离屏 ImageRenderer 或系统编辑值替代实际 timeline/Home 验收。

Research/058-ios-220-widget-redesign.md 的实际历史记录表明 Token Activity 曾有相同保存/接收不一致，SiriKit IntentConfiguration 路径能完成实际 source 切换，但沿用旧 kind 时序列化不兼容。因此不能直接将主 Widget 的配置类型换掉而保持原 kind，也不能仅复制固定三项 source 的实现。

## 选择的验证方向

先在独立无账号诊断项目验证 SiriKit 全配置原型，再接入生产；目标是恢复全部现有能力，不改变 CloudKit wire/schema、选择含义或数据来源。Apple 的[可配置 Widget 指南](https://developer-rno.apple.com/cn/documentation/widgetkit/making-a-configurable-widget/)定义了 IntentTimelineProvider 与为动态选项提供数据的 Intents extension；原型必须实证这条路径可用，文档说明不能替代验收。

| 现有能力 | 迁移必须保留 |
| --- | --- |
| mode | overview、providerFocus、todayCost、syncHealth 四项，unknown 映射 overview |
| colorStyle | mono、colorful，unknown 映射 mono |
| providers | 0–4 个动态 provider，空选择维持自动选择；每项稳定 provider ID 与展示名称；保留选择顺序与去重；已删除 ID 保持 unavailable |
| 数据 | 继续现有 WidgetProviderCatalogue 与 snapshot builder，禁止账号探测/云端读取充当模拟证据 |
| 尺寸 | small、medium、large、extraLarge，保持当前布局与选择行为 |
| 多实例 | 两个并置 Widget 可独立选择 mode/style/providers，禁止全局 defaults 替代每实例配置 |
| 本地化 | App、Widget、动态选项 extension 的 intent resources 四语言完整 |

## 拟定接入边界

新增 SiriKit status intent 定义与独立动态选项 extension，通过 INObject 的 identifier/display 承载 catalogue 数据；handler 仅读 App Group catalogue，不引入网络或共享 SwiftData migration。IntentDefinition 在包含 App、Widget 和 options extension 三 target 注册，使用 project.yml/xcodegen 生成项目。App Group 与签名配置只增加必要新 target，全部仍使用 Production CloudKit；没有原因添加 Development 环境。

把 framework intent 转换为现有 mode/style/provider 配置模型，再使用原 snapshot/render/selection；若需要拆出纯 value 配置，必须更新原单元/离屏测试而不是复制生产逻辑。并发接口与异步 timeline 的生命周期需要 review，不能启动脱离 completion 的无约束工作。

选择新的 status widget kind，保留旧 kind 的迁移策略需在原型结果后具体确定；不改 Token Activity V2 kinds。旧配置不能无证据静默迁移或表示已恢复；四语言 release notes 合并到现有 2.4.0 entry，说明经实际验证的重新添加步骤。旧包摆放→新包覆盖→编辑→移除/重新添加→新实例配置全过程需保留截图与日志，移除只针对诊断自有 fixture，不能删除其他设备数据。

## 必须完成的验证

1. 原型实际 SpringBoard 四模式、两样式、动态选项 0/1/4 项，实际 provider 参数和 Home 同时正确；不能只看 serializedParameters。
2. 两个并置实例配置不同，切换其中一个不得污染另一个。
3. provider 顺序、重复/超过四项边界、未知/已删除 ID 和空 catalogue 的单元测试；使用临时可注入文件与虚构数据。
4. 新旧 kind 升级行为、四语言实际编辑面板、四尺寸外观与现有 quota/UI/原 Widget tests 回归。
5. 新 target 本地构建与 signing/Production/App Group 审计；来源源码、实际 artifact hash 和测试证据保持一致。
6. 完成后 exact-current-head 本地 review；push/PR、GitHub CR、merge 和 Mac draft 继续遵循现有授权与发布顺序，不能用原型通过宣告 release 完成。

## 当前验收状态（2026-10-02更新）

生产四槽迁移已实现；不以早期原型替代生产结果。

| 必须完成项 | 当前证据与边界 |
| --- | --- |
| 四模式 × 两配色 | medium实际编辑→timeline→Home见r8–r11；跨r6/r10产物，r10仅两项中文翻译变更 |
| 0–4、顺序、重复、清空 | r7/r8实际生产配置，8个adapter tests；未知ID/空catalogue是单元证据 |
| 两个独立实例 | r8双向编辑与桌面核对，r12冷加载保留 |
| 四个尺寸 | r12 small/large、r13 iPad extraLarge、此前medium；小/大/超大仅overview/mono实际布局，完整渲染分支由既有render matrix tests覆盖 |
| 四语言配置 | r12简中、r15日文/英文/繁体字段与picker实际显示；繁体一次同ID空选退出失败，可靠性复测待r16 |
| 旧新kind升级 | 生产SiriKit接入初期有旧包摆放→升级→legacy提示→仅自有fixture移除/重加证据；之后r10/r12实例保留，旧kind不静默转换 |
| 编译、单元、lint | r7完整916 tests/1012 runs零失败；r10翻译后构建、r15 audit-i18n及r16 root lint通过；handler默认值补全的新r16 build已通过，focused test与实际复验进行中 |
| review与handoff | 迁移及翻译本地review clean；默认值新增差异review clean。尚未最终commit exact-head确认，不是remote PR CR gate |

当前待闭环：繁体同ID空选/退出可靠性、新产物默认值日志、focused test终态、最终来源提交与review；PR+CR、merge、Mac draft保持用户指定顺序和授权边界。

## 生产接入与 r3 review 修复（2026-10-01）

- 新 `CodexBarStatusWidgetV2` 使用 SiriKit IntentTimelineProvider；旧 `CodexBarStatusWidget` 保留原 AppIntent 类型并明确显示重新添加提示，不能推断旧配置自动迁移。
- 动态 options extension 只读取原 App Group v1 catalogue，纯 `WidgetProviderRecord(id,name)` 保持 JSON 格式；转换层复用原渲染配置、timeline、selection 和 snapshot，不改变数据来源。
- r2 production build terminal exit 0；r1 曾因回调缺 `@Sendable` 编译失败，已按 SDK 协议修正。r2 artifact 65 文件 hash 独立保存；不能引用 r1 作为通过证据。
- review 发现多选无上限和非 overview 字段误导。补固定四槽元数据及 `mode == overview` parent relationship，`intentbuilderc compile` 的规范化输出保留对应 keys。编译层确认不等于真实 picker 的 0–4 行为通过。
- r3 focused test terminal exit 0：结果总计 49 个测试、64 次运行（包含 16 组参数化运行），0 failure / skip；涵盖 6 adapter tests、既有 provider/catalogue、snapshot 与 activity projection。结果为 `ios-status-sirikit-focused-r3.xcresult`，源码冻结 `status-sirikit-r3-inputs.json` 191 项；尚非完整新 binary 回归。
- 原已安装旧包先记录 artifact hashes 与 Home，再覆盖生产包：旧实例实际编辑面板显示 legacy 名称、保留旧 syncHealth 值；关闭后 Home 明确显示重新添加提示。只移除自有 fixture 实例，再从图库第 5 页添加新的 medium status widget；其他设备和 App 数据未删除。
- r3 实际新实例默认 timeline 收到 overview/mono/空 provider；编辑器呈现空固定槽。但参数文字仍英文。安装包检查发现 options extension 未打入四语言 WidgetStatus.strings；这是 xcodegen sources 归属错误，正在以共享资源目录（排除 Swift）修复并重建 r4，不能报告四语言验收通过。

当前主要证据均位于 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070/`：`status-upgrade-before-r3.png`、`status-upgrade-before-artifacts-r3.json`、`status-upgrade-old-edit-r3.png`、`status-upgrade-old-home-r3.png`、`status-new-default-edit-r3.png`、`status-picker-catalogue-fixture-r3.json`。picker 数据是六个明确虚构项，备份原 catalogue 后写入自有 iOS26 Simulator，不能作为真实账号/CloudKit 证据。

剩余：r4 安装包资源审计与实际四语言、真实四模式/两样式/0–4 项/第五项边界、切换模式隐藏与恢复选择、多实例、全回归、本地 exact-head review、获准的 PR+CR/merge 后 Mac draft。Goal 继续 active。

### r4 生产实际验证补充（2026-10-01）

`project.yml` 已将 options extension 的共享资源目录纳入，排除 Swift 文件后单独加入 catalogue。r4 build terminal exit 0，191 项冻结 source hashes 与当前源码一致；安装前 App/Widgets/Options 三 bundle 的 en/zh-Hans/zh-Hant/ja `WidgetStatus.strings` 均实际解码正确。r3 focused 49 tests / 64 runs / 0 failure / 0 skip 验证 adapter、provider/catalogue、snapshot、activity，r4 只改变资源归属，不能把 r3 测试扩大成所有 r4 runtime gate。

同一已升级自有 iOS26.5 的新 status 实例实际选择 syncHealth：timeline 日志收到 `mode=syncHealth, style=mono, providerIDs=`，稳定 Home 显示同步健康“正常”。旧实例编辑及重新添加迁移全过程已有截图。仍不意味着所有四模式/配色/providers/多实例通过。

r4 覆盖安装后编辑面板仍使用旧英文标签，parent hiding 未体现。仅对本任务自有 `7216E120-B46B-43D5-A78C-93A096A3D5A3` shutdown/boot 保留数据，bootstatus terminal exit 0；未停止/重启其他项目 Simulator 或全局服务。因有意重启而消失的旧 App PID 已重设 sim-use baseline，没有据此声明 App 崩溃。冷加载后编辑面板实际出现“小组件类型/概览/颜色样式/单色/服务商”，说明原英文显示与缓存有关；不应改正确的 enum predicate 名为数字。

随后冷编辑面板控件未响应，最终显示“无法载入”。暂无 App crash banner、诊断报告或确定原因；不得将这个局部配置面板失败泛化为 Simulator 整体故障。真实 parent hiding、0–4 槽位删除/顺序/第五项边界及后续模式组合仍未通过，下一步需做新 namespace/class/kind 的独立配置模型对照或按运行日志定位冷加载失败，不以重复操作替代排查。

`status-sirikit-integration-evidence-r4.json` 保存上述独立证据 hashes 与严格 pass/pending 范围。全部文件位于 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070/`。预览 App 曾以明确 `UI_TEST_PREVIEW_DATA` 启动，将自有 Simulator catalogue 更新为合成 preview 数据；初始六项虚构 fixture 仅用于后续边界测试，不能将该列表误称为真实账号数据。Goal 保持 active，未 push/PR/merge/tag/release/TestFlight。

### fresh 配置模型对照与操作证据修正（2026-10-01）

独立 `local.codexbar.sirikitcoldprobe` 使用全新 namespace、intent class、widget kind 和纯虚构 A–F 选项，四语言资源实际存在；已放置并实际编辑。中文“概览”值按钮范围 x297–331，先前 x295 的点击落在按钮之外；改为 x314 后正常打开四模式菜单。这部分未响应不能作为配置控件故障证据，先前“无法载入”的单次面板现象根因仍未确定。

fresh 模型实际选择 syncHealth 时仍显示 providers，随后恢复 overview、打开六项动态列表、选中 B 均成功。因此“旧注册缓存”不能单独解释 parent 隐藏失败；不能声称 Simulator 整体异常。选中 B 后重选 B 不清空，左滑其行打开列表，未看到删除入口；初始空槽不等于已验证可恢复自动选择。截图与 hashes 保存于 `widget-sirikit-cold-probe-r2/runtime-evidence-r2.json`。

下一轮独立 `widget-sirikit-relationship-probe-r3` 对照将同一个 overview 条件施加于普通 scalar colorStyle 与非 fixed-size 的多值 providers，区别关系配置整体失效和固定数组行为；动态列表加入诊断 Automatic 项用于后续清空交互方案试验。该项目前只存在于 scratch prototype，不是生产变更，也未宣称可发布或通过实际验收。原 full-size production 功能与全部四模式、两样式、0–4 provider 要求保持不变。

### 条件隐藏对照结果（r3，2026-10-01）

r3 独立原型 terminal build exit 0，13 个来源 hashes 与实际构建保持一致。实际 SpringBoard 将 overview 切为 syncHealth 后，scalar colorStyle 与非固定数组 providers 同时隐藏（截图 `widget-sirikit-relationship-probe-r3/sync-edit.png`）。此定义仍无 managed/unmanaged combinations，所以不能把缺组合当成根因。对比 r2 同条件固定数组仍显示 providers，证据指向固定数组 UI 的条件隐藏差异，尚需单一标量槽方案完整交互验证。

正在 scratch r4 验证四个独立 optional provider 槽，各自保留 overview parent 条件、稳定 ID 和四槽顺序；选项中的 Automatic 使用保留 ID，并从实际 renderer 输入排除，不写入 v1 catalogue。该方案旨在保持 0–4 容量、自动选择、动态 catalogue、两种配色、四模式和多实例，不以移除功能换通过。生产代码尚未改为该方案。

r4 四个独立槽 prototype build terminal exit 0，source-inputs hashes 与当前文件一致，artifact-inputs hashes 已冻结；安装至同一自有 Simulator 并启动。尚未摆放/编辑四槽新实例，不能声明0–4或隐藏通过。只读 review 未发现方案丢失原能力，要求补真实清零、顺序交换、重复、未知ID和多实例验证。

### r4 独立四槽实际验证与生产接入（2026-10-01）

实际 SpringBoard syncHealth 时全部四槽隐藏，style仍可选；Overview slot1选B再选Automatic后，timeline收到空IDs，Home显示空IDs；按槽选择B/A/C/D，timeline与Home均收到B,A,C,D，次序未按名称排序。证据保存 `widget-sirikit-slots-probe-r4/runtime-evidence-r4.json`。上述均为虚构独立原型，尚不代表生产验收或多实例通过。

生产定义现已改为四个独立optional object槽，均保留overview条件；选择列表提供四语言“Not selected”，用保留ID `codexbar-widget-choice:none` 表达空槽，不写入既有v1 catalogue。Adapter先过滤nil/空ID/保留ID，再按槽序first-wins去重，unknown IDs保持原行为。新增/更新测试涵盖4槽、空槽混合、清零、顺序、重复和独立配置。尚需生成项目、生产构建/测试、实际生产SpringBoard全验收与最终review；Goal仍active。

r5 production focused test terminal exit 0：51 tests / 66 runs，0 failures/skips/runtime warnings，包含8个adapter测试及现有catalogue/selection/snapshot/activity。191输入hashes在测试结束后复核一致，结果为 `ios-status-slots-focused-r5.xcresult`。strict lint随后发现handler NSLocalizedString参数布局2项；现已改为String(localized:)和options target独立Localizable.xcstrings四语言translated文案，去除WidgetStatus.strings重复文案。四个改动Swift文件strict lint terminal exit0。r6只改变handler文案API/资源归属，adapter/tests保持已测内容；生产重建仍待终结，不能将r5扩大为r6全回归。

### r6 生产构建及 iOS27 实际配置验收（2026-10-01）

r6 production build terminal exit0，192项输入hashes与当前源码一致；App/Widget/Options三bundle的四语言Provider1–4资源均实际解码完整，options独立Localizable.strings的“Not selected”四语言值正确。四个changed Swift文件strict lint通过。r5相关51tests/66runs/0failures/0skips已验证adapter/catalogue/selection/snapshot/activity；r6 handler文案API及resource变更不扩展该测试范围。

在自有iOS27 D86C3D2C-7A29-43C6-9B22-5B61902B794B覆盖安装r6，再以UI_TEST_PREVIEW_DATA启动发布合成catalogue；没有真实账号或CloudKit探测。从系统图库第5页添加medium新status，中文Overview四槽实际出现；实际切syncHealth后全部四槽隐藏，style仍可选。再选colorful，timeline收到mode=syncHealth/style=colorful/providerIDs=空，稳定Home呈绿色“正常”。已证明修复接入生产并能消费非默认配置，不能据此宣称完整验收。独立证据manifest为 `status-slots-production-evidence-r6.json`。

剩余生产实际dynamic picker/清空/0–4/顺序与重复边界、两实例、其余模式配色组合、其余三语言实际配置、四尺寸、iOS26最终版本复测、完整iOS回归与exact-source review。旧kind迁移已有此前独立证据，最终package影响仍要核对；PR+CR/merge/Mac draft按用户顺序和授权边界，未执行remote handoff。Goal继续active。

### r7 完整单元回归与生产选择/清空验收（2026-10-01）

`ios-status-slots-full-r7.xcresult` 实际 summary 为916 tests / 1,012 runs，0 failures / skips / runtime warnings；终态 TEST SUCCEEDED。192项r6输入hashes在本轮再次核对一致。完整单元回归运行于自有iOS26.5；不把单元测试扩大为SpringBoard全配置验收。

自有iOS27仍使用已冻结的r6生产安装包和合成preview catalogue：实际选择Codex单项，timeline收到codex；再按槽选择Codex/Claude/OpenRouter/AWS Bedrock，timeline收到codex,claude,openrouter,bedrock，Home顺序一致。后两项缺少合成配额数据，实际保留“不可用”，未替换为其他项。逐槽选择“未选择”清空四项后，timeline收到空IDs，Home恢复自动Codex/Claude/Raycast/OpenRouter。日志和实际Home截图hash记录于 `status-slots-production-evidence-r7.json`，运行产物引用r6冻结manifest，独立记录r7测试结果。

此对照将失败范围缩小到本项目固定长度数组的配置路径；改为四个独立optional选项后，模式条件隐藏与选择/清空路径实际生效。没有证据支持Simulator整体故障，也未核验其他项目。仍待两/三项与重复边界、实际两实例、其余模式配色/语言/尺寸、iOS26最终运行验收与最终review。Goal保持active；PR+CR、merge、Mac draft按用户要求顺序，未执行remote handoff。

### r8 生产两实例与两/三项、重复边界（2026-10-01）

同一自有iOS27桌面添加第二个medium新status，未修改其他项目设备。上方新实例设syncHealth/mono，下方原实例保留overview/colorful。下方实际按槽选择Claude/Codex，两项timeline和Home顺序一致；添加OpenRouter为第三项，timeline收到claude,codex,openrouter，Home三列对应一致。第四槽再次选择Claude，编辑截图证明四槽内容为Claude/Codex/OpenRouter/Claude，timeline仍为前三个不同ID，Home没有重复列。滚动到底实际表单终止于服务商4，无第五槽。

全过程上方保持单色同步状态；反向编辑上方切彩色，Home实际变为绿色“正常”，下方继续保留彩色三项概览。已有截图证明两个放置实例在两个编辑方向独立；本轮未捕获反向彩色health的新timeline事件，因此该动作只声明实际编辑/Home证据，不能补造日志。初始health mono及下方2/3/去重日志真实存在。所有证据hash保存 `status-slots-production-evidence-r8.json`，仍引用已冻结r6生产产物，192输入hash再次一致。

与r7一起已覆盖实际0/1/2/3/4项及清空、槽序和重复、多实例；仅为中文medium/合成preview/iOS27范围。其余模式配色组合、另外三语言配置、其他尺寸、iOS26最终运行验收及源码最终review仍待完成。没有新代码修改、remote handoff、merge或Mac draft；Goal继续active。

### r9 服务商详情实际切换及翻译修复（2026-10-01）

同一iOS27生产r6上方实例从syncHealth/colorful实际切providerFocus/colorful：配置表单只保留模式/样式，Home显示Codex“已用78%”蓝色详情，下方三项彩色overview保持。日志随后实际捕获syncHealth/colorful空IDs（补足r8当时尚未出现的事件）及providerFocus/colorful空IDs，见 `status-slots-focus-timeline-r9.log`；r8原冻结日志不修改。截图及日志hash存 `status-slots-production-evidence-r9.json`。

实际详情底部出现英文“Provider”，代码使用String(localized:)但主catalogue的zh-Hans/zh-Hant值本身都是英文。已只将这两值修为“服务商”/“服務商”，英文及日文保留；四语言仍translated。r6/r7/r8/r9冻结来源均为修复前，不能据此宣称最终文案通过。新的192输入manifest `status-slots-r10-inputs.json`冻结修复后资源，生产构建session74542正在运行，结果待核对。

review agent已对HEAD45a6a42666bd2378e4a355d07694732a25a567b2加未提交四槽迁移diff完成clean源码审查，零代码阻塞；本次两行翻译资源后另请复核。仍未提交最终来源，也不是remote PR exact-head CR gate。完整UI矩阵未完成，Goal继续active。

### r10 翻译修复后构建与保留实例升级（2026-10-01）

生产build session74542终态exit0/BUILD SUCCEEDED，结果 `ios-status-slots-build-r10.xcresult`。192输入hashes再次一致；App及Widgets最终Localizable.strings实际解码Provider为en Provider、zh-Hans服务商、zh-Hant服務商、jaプロバイダー。构建产物全文件hash冻结 `status-slots-r10-artifacts.json`，不覆盖r6来源。

仅覆盖安装到自有iOS27并以UI_TEST_PREVIEW_DATA启动；有意安装/启动后重置sim-use进程baseline，未把预期进程替换记作未知崩溃。已放置两实例保留：上方仍providerFocus/colorful，Home底部实际显示“服务商”；下方仍overview/colorful，保持Claude/Codex/OpenRouter三项和次序。实际截图hash保存 `status-slots-production-evidence-r10.json`。纯文案修复没有改逻辑；r7全单元结果覆盖修复前逻辑，r10不另伪称完整单元重跑。

review agent对唯一新增的两行翻译复核clean。剩余实际模式/配色、另外三语言、其他尺寸、iOS26最终运行验收仍待完成；当前只有providerFocus/colorful、syncHealth两样式、overview/colorful有明确实际证据。最终commit/remote PR CR、merge、Mac draft尚未进行，不能声明iOS或Goal整体done。

### r11 四模式两配色实际桌面补齐（2026-10-01）

已安装r10、自有iOS27/合成preview/medium新status：实际选providerFocus/mono，Home已用78%黑色；todayCost/mono实际$19.42、822.0 K tokens黑色；todayCost/colorful同值橙色；overview/mono自动四项单色（error图标仍红色，属于错误语义）。每次实际编辑→timeline接收mode/style→稳定Home核对，日志 `status-slots-modes-timeline-r11.log` 和截图hash冻结 `status-slots-production-evidence-r11.json`。另一实例仍保持三项彩色overview。192项r10源hash复核一致。

加此前r8/r9 syncHealth两样式、r10 providerFocus/colorful及overview/colorful，四模式×两样式的medium实际接收与显示已覆盖；health证据是r6二进制，r10仅两行翻译变动，不能称r10同一产物全部八组重新运行。

覆盖安装r10后系统编辑面板mode/style/provider字段显示英文，而heading/description与Home保持中文。App/Widget/Options实际WidgetStatus.strings四语言完整，设备AppleLanguages=zh-Hans-US,en-US；尚不能据文件或既往r6中文UI宣称本次编辑界面中文通过。已保存实际英文编辑截图，只对自有iOS27保留数据shutdown/boot做冷加载对照，session51287进行中；其他项目设备不操作。其余语言、尺寸及iOS26最终runtime仍pending。

### r12 冷加载中文配置与small/large实际布局（2026-10-01）

自有iOS27 bootstatus session51287终态exit0，数据保留；因有意重启而消失的旧进程重置baseline，未据此声明App崩溃。冷打开新status编辑先见短暂spinner，settled实际显示“小组件类型/概览/颜色样式/单色/服务商1–3”；此前覆盖安装后英文字段在未改源码/资源情况下恢复中文，支持系统配置缓存解释（推断），不是Simulator整体故障证明。返回Home上方overview/mono自动四项、下方overview/colorful原Claude/Codex/OpenRouter三项仍保留。

从系统尺寸菜单实际将上方改small：settled框168×191，显示自动Codex78%和Claude42%两行，姓名/百分比/进度均无裁切；最初 `status-slots-small-home-r12.png` 是过渡中的旧medium，不作为small通过证据，最终只用 `status-slots-small-home-settled-r12.png`。再改large，实际框354×392，四项2×2顺序正确，无裁切；下方原实例被系统挪到下一页，未移除。

r10产物冻结保持，全部图片hash记录 `status-slots-production-evidence-r12.json`。medium已有八组合，小/大目前只覆盖overview/mono，不扩大为所有尺寸全模式矩阵。第四尺寸为systemExtraLarge（iPad），本iPhone菜单disabled，需另做iPad真实放置或明确替代验证；另外三语言配置与iOS26最终runtime仍待。Goal active，未远程handoff/merge/Mac draft。

### r13 iPad systemExtraLarge实际放置（2026-10-01）

确认CoreSimulator Devices入口realpath为SSD且可写后，新建本任务独立 `CodexBar v070 iPad XL QA`，UDID1111ADF4-3166-42D2-B868-10D8A18FEF97、iPad Pro13 M5、iOS27.0；身份记录 `status-slots-ipad-device-r13.json`。bootstatus session84729终态exit0。安装同一r10已冻结生产包、以UI_TEST_PREVIEW_DATA启动；初次读取进程列表短暂失败，等待原session93245终态exit0并重新读取baseline成功，无重装/全局重启或未知crash证据。

实际SpringBoard从CodexBar图库第8/12页选择新status超大尺寸并添加，完成编辑后Home框752×377，overview/mono四列Codex78%、Claude42%、Raycast30%、OpenRouter不可用顺序正确，名字/数值/进度/副标题无裁切。不是仅图库预览通过。图片与timeline日志hash冻结 `status-slots-production-evidence-r13.json`；均为合成数据，不是物理iPad/真实CloudKit。

至此四family都有实际放置布局证据：small/large/extraLarge目前只overview/mono，medium有四模式×两样式；不扩大成全family×mode矩阵通过。另外三语言的配置界面、iOS26最终runtime及最终提交/远程review仍待完成。Goal active，未push/merge/tag/TestFlight/Mac draft。

### r14 iOS26最终产物实际配置运行（2026-10-01）

在自有iOS26.5设备7216E120-B46B-43D5-A78C-93A096A3D5A3安装已冻结r10产物。实际medium配置选择Codex和彩色，桌面显示单项78%；切到syncHealth/colorful后服务商字段隐藏，桌面显示绿色“正常”。timeline-r14.log依次收到overview/mono空IDs、overview/colorful codex、syncHealth/colorful codex；模式切换保留选项且同步状态渲染忽略provider选择。截图/日志hash保存status-slots-production-evidence-r14.json。

这是当前产物在iOS26的实际配置→timeline→桌面证据，不扩大为iOS26全部模式/配色矩阵。覆盖安装后配置字段曾显示英文，冷加载的四语言配置验证仍待；无Simulator整体故障结论。Goal active，未remote handoff/merge/Mac draft。

### r15 其余三语言实际配置与完整lint（2026-10-02）

同一r10生产产物、自有iOS26.5设备依次设ja-JP/ja_JP、en-US/en_US、zh-Hant-US/zh-Hant_US并保留数据冷启动，bootstatus sessions36946/67588/64138均exit0；仅有意重启后重置baseline。日文实际显示模式/配色/四槽标签、picker未選択，选择Codex后Home单项78%且timeline codex；英文实际显示四槽与Not selected，清空后timeline空IDs、Home自动四项；繁体实际四槽/未選擇picker、选择Codex后timeline codex、Home已用78%。图片与日志hash冻结status-slots-production-evidence-r15.json，192项r10源码hash仍全一致。

繁体切语言后原已保存空对象display保留英文Not selected；同ID重选界面暂改未選擇，滚动/退出时出现無法載入，必须保留失败证据。SpringBoard日志记录系统WidgetConfigurationExtension连接中断；RunningBoard同PID30442随后仍running-suspended，无对应crash报告或sim-use未知进程消失banner。用Home退出再编辑可打开，随后不同ID Codex选择正常退出并被timeline消费。根因/是否需default handler修复交review，不据成功重试抹去可靠性问题。此时不宣称iOS整体done。

Scripts/lint.sh audit-i18n exit0，所有catalogue四语言translated、382源keys齐全。完整root lint首轮r15 exit2因Xcode Python3.9缺waitid；改用已有Homebrew Python3.14置PATH前，r16 terminal exit0：2749文件零SwiftLint违规、资源/解析版本及相关policy guards通过。不是整个iOS目录SwiftLint零违规声明；新生产Swift文件另有此前strict lint证据。未安装工具或改源码以绕过检查。正在恢复该专用设备原zh-Hans-US/en-US、zh-Hans_US设置，待boot核对。Goal active，未push/PR/merge/tag/TestFlight/Mac draft。

### r16 默认值补全与失败复验（2026-10-02）

review确认generated协议defaultProvider1–4为optional，缺实现不能直接叫timeout根因。为消除实际default lookup1003，handler新增四个同步默认方法，共用当前语言的emptyChoice；不读catalogue、不保存全局选择。新增差异review clean。192源码hash冻结status-slots-r16-inputs.json，构建session30317 terminalexit0/BUILD SUCCEEDED，安装前产物全文件hash冻结status-slots-r16-artifacts.json。handler strict lint exit0。focused test session75873 terminalexit0/TEST SUCCEEDED，51 tests/66 runs，0失败/跳过/runtime warnings，自有iOS27。

覆盖安装自有iOS26后再冷切繁体，bootstatus session29508 exit0。实际选择未選擇，再重选同一空ID、滚动四槽并outside(15,630)退出，仍出现無法載入；new errors日志未见default lookup1003，但系统WidgetConfigurationExtension连接再次中断。因此默认值补全只消除一项观察错误，不是失败根因的充分修复。保留failed-exit-r16.png、errors/termination/timeline日志，不宣称繁体可靠性通过。

独立探索对照：退出失败面板后重新编辑，选择不同ID Claude，停留并截图后通过Home按钮退出。timeline实际收到claude，settled Home显示Claude42%及繁体已用；最初Home截图仍为旧Codex过渡，不能当失败或最终通过，只用settled截图。这证明这种正常退出路径能保存并被生产消费，但未完成固定时长/滚动的同不同ID×Home/outside四对照，不能排除配置会话问题。

证据hash冻结status-slots-production-evidence-r16.json。专用iOS26仍保持zh-Hant，供下一步受控诊断，原设置文件保留；未操作其他项目设备/全局服务。Goal active，iOS可靠性gate及最终来源review仍待；未push/PR/merge/tag/TestFlight/Mac draft。

### r17 受控退出对照与配置读回（2026-10-02）

生产源码/产物仍为冻结r16，未为取得通过修改实现。脚本status-slots-controlled-r17.py逐步observe→act→verify，遇未知UI或PROCESS DISAPPEARED立即停止；固定滚动后等待45s，实际滚动验证到退出46.26–47.91s。每组退出后重新编辑并截图读回，再回桌面检查。早期人工a组实际57.82s，作为探索证据，不冒称固定30s对照。

| 组 | 前值→重选 | 退出 | 结果 |
| --- | --- | --- | --- |
| a-repeat | Claude→Claude | Home | 正常退出，读回Claude |
| b | Claude→Claude | outside15,630 | 正常退出，读回Claude |
| c | Claude→未選擇 | Home | 正常退出，读回空槽；timeline空IDs，桌面自动四项 |
| d | 未選擇→未選擇 | Home | 正常退出，读回空槽；桌面自动四项 |
| e | 未選擇→未選擇 | outside15,630 | 正常退出，读回空槽；桌面自动四项 |
| f | 未選擇→Codex | outside15,630 | 正常退出，读回Codex；桌面78% |

六组终态exit0，无实际無法載入、未知crash banner或数据清除。每组action JSON包含原始UI/命令/timestamp，result记录实际停留，图片已检查。完整系统日志status-slots-controlled-lifecycle-r17.log及-f.log在终态后停止保存；正常退出a/b也出现system extension connection interrupted和Invalidation requested，所以单条该日志不能替代实际面板结果。不能据本轮无复现宣称旧失败根因已修复，旧r15/r16失败证据和系统会话风险保留，请review比较。

所有截图/脚本/逐动作/日志hash冻结status-slots-production-evidence-r17.json。当前控制流程已通过，其余本地scope仍依据此前分来源证据；最终验收判断与来源提交review进行中。已恢复专用iOS26原简中设置zh-Hans-US,en-US / zh-Hans_US，重启终态exit0；sim-use基线重置及SpringBoard简中读回正常。未remote handoff/merge/Mac draft，Goal active。

只读review复核：没有新的可证实源码阻塞。r17正常a退出先完成request、teardown、取消XPC再产生interrupted/Invalidation；r16同样先teardown再interrupted。因此日志不能单独定位业务callback超时或保存/dismiss竞态。旧失败仍为未知原因风险；停止无新增信息的同操作重试。各语言、模式、样式与尺寸适用证据已有此前逐轮记录，不能扩展为r17全矩阵复跑。
