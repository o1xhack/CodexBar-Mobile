# 3.2.0 (257) 验证与发布记录

状态：in-progress；尚未上传或声明完成。

## 输入与范围

- 基线：92742802c1097e9abae59f4699a16822c114da9f（256 已发布）。
- 分支：feature/summary-quota-detail；全部五个 target 为 3.2.0 (257)。
- 只改 iOS 展示、导航、交互与对应测试。共享 payload、持久历史、CloudKit schema、Mac 实现未改。
- 当前工具链：Xcode 27.1 (27A9275)；最低 iOS 17 保持不变。
- 本轮独立证据目录：/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/SummaryQuotaDetail-3.2.0-257。

## 已完成

- `units.xcresult`：全量 iOS 测试通过，71 项 XCTest、1261 项 Swift Testing；包括新历史检查模型、缺口/真实时间/无效状态/最近重置排序以及现有账户和同步兼容回归。
- `lint.log`：仓库 portable lint 通过。
- `i18n.log`：四语本地化审核通过。
- 独立静态 CR：无阻塞的数据模型或账户导航发现；补回图例辅助功能值，测试先断言非空再验证返回/旋转保持，避免 nil==nil 假通过。
- 源 AppIcon 浅色/深色均本轮目视检查并核对 1024×1024、不透明、SHA-256；记录 source-icon-check.json。

## 运行时问题与修复

首轮普通 iPhone 详情测试发现图表辅助功能边界右侧超出可视区 8pt。失败截图确认实际图表未溢出；AX dump 显示 Swift Charts 为图表生成两个同标识节点，外层虚拟区域比真实 plot 水平多 80pt、垂直多 100pt。给真实布局容器独立标识，保留图表原生无障碍功能，用容器几何执行严格边界验收；不裁剪数据或放宽可视区。

首屏历史读数修正：初始状态分别呈现每条曲线最近真实记录及各自时间；只有用户主动拖动后才按共同选中时间查询，保留缺口和时间来源。

真实 Air 257 已安装、Production entitlement 和 build 已核实。真实账户的 Claude/Codex 历史可见，点击整卡进入详情；发现图表 chartXSelection 接管纵向滑动，页面未滚动而改变了查询时间，与普通 iPhone 横屏测试中连续拖动仍无法显示图例一致。保留 air-vertical-pan-intercept-before-fix.jpg，必须修正手势分工并在真实设备重验，不能把测试拖动移到图表之外规避。

UIKit 方向感知 pan 修复后，真实 Air 已验证：从图表内纵向拖动，容器 Y 从 186pt 移至 -68pt，历史时间保持 12:18；回到顶部横向拖动，容器 Y 保持 186pt，查询变为 10 月 20 日 23:22，Claude 返回真实 95% 与其 22:57 观测时间，其他没有对应记录的曲线不补值。再次纵向拖动仍滚动且保留所选时间。证据：air-gesture-proof.json、air-real-history-inspection.jpg。这里的通过结论来自操作前后 AX 位置/读数对照与人工目视回读；PUA 动作回包的 verified=false / verification_deferred=true 本身不代表自动验证通过。滚到底部说明完整可见：air-real-current-footer.jpg。SwiftUI simultaneousGesture 候选曾失败，未作为完成证据。

`ios26-accessibility-final.xcresult` 虽命令返回成功，但实际 0 tests，不能计入通过。核实 runner 哈希、方法符号和测试过滤后，将三个同步 UI 用例显式声明为 throws；重跑实际执行三项：日文 XXXL 和隐私通过，辅助大字用例暴露排序测试前置查找方向错误。模块向上排序后被 List 虚拟化，脚本仍向下查找；修正查找方向并保留首项与重开排序页持久化断言，随后单独复验。没有因此放宽产品断言。

- `detail-model-final.xcresult`：更新初始历史读数后的 6 项模型用例通过。
- `phone-uikit-final.xcresult`：2 项交互用例通过，包括图表内纵向滚动、横向查值、旋转后状态、非默认账户准确跳转与返回。
- `phone-light-portrait-final.xcresult`：1 项完整 App 验证通过，已导出七张完整页面截图，底部说明完全位于 Tab Bar 上方。
- `duo-portrait-dark-uikit.xcresult`：1 项完整展开竖屏验证通过，图表与底部说明目视通过。
- `duo-portrait-light-uikit.xcresult`：因模拟器启动白屏取消，明确记为失败；设备重启时 bootstatus 报 Data Migration Failed，不能按命令 exit 0 当成恢复成功。随后 CUA 实际展开内屏并恢复 App 测试；恢复验证使用新结果目录，不覆盖失败证据。

## 独立视觉复核补充（2026-10-24）

- 已逐张目视 `phone-light-portrait-final-{summary,detail-chart,detail-current,detail-account,usage,cost,settings}.png`，均为原生完整 App 截图；Simulator 数据为 fixture，不作为真实账户历史或 provider 健康证据。
- 普通手机浅色竖屏的 Summary 图表跨两列、占两行标准卡片高度，标题、日期、坐标、曲线及紧凑图例清晰；Usage、Summary、Cost、Settings 均保持白色页面与浅灰卡片，导航和四个 Tab 完整。
- `detail-current` 的当前额度、原始观测时间和两行历史空缺说明完整可读；说明与浮动 Tab Bar 之间留有空白，没有此前的 home indicator 覆盖。`detail-chart` 的坐标、五条最近读数和滑块可读；底部拖动说明在该首屏落于 Tab Bar 后方，应作为可滚动内容看待，不声称单张首屏显示完整整卡。
- 账户详情截图的整页外框仍圆角内缩，右上按钮虚化且左缘出现底层内容，疑似导航转场尚未稳定；当前没有据此判定产品缺陷，最终展示证据应在导航稳定后重截。其可见账户用量、费用与主题配色清晰。
- 已目视的 Air 真实历史选点保留选择时间与原始观测时间，缺记录的四条曲线显示明确空缺；Air 底部两段说明无遮挡。Duo 深色竖屏 UIKit 三张截图也已通过，footer 位于 Tab Bar 上方、home indicator 位于 Tab 下方。尚未查看的矩阵状态仍单独待验，不能由其他姿态结果替代。
- 已逐张目视 `duo-landscape-light-recovered-{summary,detail-chart,detail-current,detail-account,usage,cost,settings}.png`：展开横屏浅色视觉通过。Summary 图表真实占 2×2 四格，与右侧四张 metric 卡片的上下边缘对齐；详情图表、坐标与横向图例清晰，右侧返回、筛选和四 Tab rail 完整且不侵入内容。滚到底部的 `detail-current` 显示完整最后一张卡片和一行历史说明，说明下方留白充分，原 footer/home indicator 覆盖在此横屏状态已消除。
- Duo 浅色横屏 Usage、Cost、Settings 与 Summary 同为白底、浅灰卡片；Usage sidebar 与主区背景一致。该组账户详情截图已是平直稳定页面，没有普通手机先前截图的圆角收缩、按钮虚化或底层残影，可作为稳定导航视觉证据；Settings 的 No Data 仅记录 fixture 同步状态，不作为真实同步健康判断。

- 最终正常字号补审三组各七张原生截图：`duo-landscape-dark-stable-*`、`duo-portrait-light-final-*`、`phone-dark-landscape-final-*`（Summary、图表详情、当前额度、账户详情、Usage、Cost、Settings）。前两组逐张目视，普通手机组由另一独立只读视觉审阅逐张检查；均无新增视觉阻断。
- Duo 深色横屏：Summary 的 2×2 四格与右侧四张 metric 上下对齐；详情 plot、坐标和横向图例清晰，当前额度末卡与整句 footer 完整，说明下方留白充分，先前 home indicator 覆盖已消除。Usage sidebar 与主区均为黑底，卡片维持炭灰色，没有旧的大块灰底分区；账户页稳定，右侧导航和四 Tab rail 完整。
- Duo 浅色竖屏：Summary 保持三列，2×2 图表与右侧两张卡片对齐；详情五条最近读数、滑块及说明可读，滚到底部的五张当前额度卡与 footer 完整，footer 在 Tab Bar 上方。各 Tab 白底/浅灰卡片一致，账户页无转场残影。截图方向 metadata 的上下倒置不计为产品布局错误。
- 普通手机深色横屏：Summary 四格模块的边界、标题、坐标及紧凑图例完整；`detail-current` 最后一张当前额度卡及 footer 完整，与 Tab Bar 留有明显间距；账户页稳定无残影，各 Tab 黑底/炭灰卡一致，导航与四 Tab 完整。`detail-chart` 首屏部分图例位于浮动 Tab Bar 后，只能证明该滚动视口状态，不能声称单张展示完整详情整卡，也不能仅凭截图判定内容不可达。真实手势可达性以独立 UI 测试和实机回读证据为准。

## 辅助字号生产布局修正

`ios26-accessibility-order-fixed` 已通过排序前置，但实际进入详情后失败。AX 证据显示：历史读数高 1340pt，首条当前额度卡高 1610.7pt，而可用 viewport 仅 660pt；固定横向布局让大字号百分比挤压账户与时间，是真实产品适配缺陷。历史有值/无值读数及当前卡片在 accessibility size 改为纵向布局，正常字号保持原横向布局。纵排后首卡为 803.3pt，所有文本已获得完整 330pt 内容宽；最大辅助字号下自然内容超过 660pt viewport，不能要求整卡同时塞进一屏。独立截图和 AX 明确区分这与原先 1610.7pt 的窄列挤压缺陷。最大 AX 改为逐个历史与当前字段完整滚到无遮挡 viewport，检查水平包含、垂直不重叠，并实际点击当前字段验证精确账户跳转；普通字号仍保留整卡完整可见断言。详情滚动查找使用不超过 viewport 45% 的步长，Summary 四格仍保留原 72pt 上限。七个日期坐标视觉字号上限为常规 xxxLarge，完整日期朗读保留，其他正文不缩字号。

最终普通字号矩阵八组均为实际 1/1 PASS、零失败、零跳过：普通 iPhone 的浅/深竖屏与浅/深横屏，展开 Duo 的浅/深竖屏与浅/深横屏。结果来自每个 xcresult 的真实测试数量，汇总见 eight-pose-matrix.json。最大辅助字号的逐字段复验单独记录，不能由普通字号结果替代。

真实 Air 最终源版本截图为 air-real-detail-axis-final.jpg（2026-10-24 20:05 UTC）。七个日期刻度完整，真实 Claude Weekly 54%、Codex Weekly 35%，最新观测时间 13:04，证明当前页随真实同步更新；模拟器 fixture 与真实账户证据分开保存。

`ios26-accessibility-fields-final.xcresult`：实际执行 1 项，0 失败，耗时 667.942 秒。全部历史读数字段、五张当前账户卡字段、精确账户跳转及返回和底部说明均通过；与已通过的日文 XXXL、隐私测试一起完成大字/本地化验证。

## 待验收


- 当前 head 远端 CR、所有 threads、CI 和合并 gate。
- 已审查源码归档、Production entitlement、IPA 与图标证据、ASC VALID、四语 What to Test 与 Internal 访问回读。
