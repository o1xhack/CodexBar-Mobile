# Provider Overview 2.3.0 (224) 验证记录

本次仅本地开发；不上传、发布、push、merge 或修改 Mac。旧 iOS 基线为 mobile-dev build223，新为本分支224；本轮 Mac old/new 二进制相同，无 Mac 代码差异。

## 已完成证据

- A：`widget-overview-formatted.log/.xcresult`（最终格式修正后复跑），XCTest12项、Swift Testing120项通过；含 CloudKitMerge16mask、既有缓存/merge/ghost处理与 widget snapshot。
- B：WidgetProviderSelectionTests 的 legacy summary 缺少 resetsAt 解码、catalogue JSON 原子读写/去重、百分比和刷新周期一致、缺失选项不替换；最终实际View 1–4 ×4尺寸×明暗×单色/彩色，共64张附件。
- C：代码审计：Shared/CloudKit payload/schema 无变化；resetsAt 来自既有 SyncRateWindow/SyncBudget；仅 Widget 本地 Codable projection 新增 optional 字段，旧读者忽略未知JSON，新读者可读旧缺省字段。选择catalogue仅App Group本地文件。Production entitlements 未修改，结论 NO_DEPLOY。
- Release Simulator build：`widget-overview-release-build.log` BUILD SUCCEEDED；不代表 Archive/真机签名或 TestFlight。
- 四语 audit 全部 translated，366源 key 均存在；git diff --check通过。

所有输出位于 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/`。无法进行2Mac×2iPhone实测：本轮不操作真实账户/设备的Production同步，使用合成数据与本地Simulator；可连接的两部真机均为iOS27/27.2，无iOS26.5真机。以下均为替代证据，不声称真实设备pass。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 2 | old | old | old | new | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 3 | old | old | new | old | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 4 | old | old | new | new | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 5 | old | new | old | old | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 6 | old | new | old | new | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 7 | old | new | new | old | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 8 | old | new | new | new | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 9 | new | old | old | old | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 10 | new | old | old | new | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 11 | new | old | new | old | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 12 | new | old | new | new | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 13 | new | new | old | old | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 14 | new | new | old | new | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 15 | new | new | new | old | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |
| 16 | new | new | new | new | substituted | A/B/C | 真机 Production 推送与各自缓存未实测 |

## 系统配置验证状态

原生 AppIntent 编辑器已经保存并重开 Codex/Claude 两项；默认桌面显示2项与小数倒计时已实测。iOS26.5 Simulator显式选项调用timeline仍报 `WidgetProviderEntity is not a registered AppEntity identifier`，收到count0；此项尚未通过，不将编辑器保存视为渲染通过。同一实现独立iOS27环境已验证 count0/1/2/4 与桌面对应1、2、4项，截图 `widget27-one-stable.png`、`widget27-now.png`、`widget27-four-saved.png`；resize后中尺寸4项完整显示 `widget27-medium-four.png`，时间与百分比未截断。timeline日志 `widget27-timeline.log`。26.5注册异常不视为该版本真机失败或通过，仍需真机确认。

## 剩余风险

真实Production推送/2Mac2iPhone与物理iPad超大组件未实测；超大组件已完成iPad iOS27 Simulator原生SpringBoard四项显示；物理iPad仍未覆盖。原生多选传参已在iOS27 Simulator完成；iOS26.5真机选择需后续设备验证，不能由iOS27结果推断。

## 自查 review

检查完整 diff：用户 workflow skill 未修改/暂存；Mac/version.env/Shared未变；Xcode工程由xcodegen生成；四targets build224；同2.3notes block；候选查询仅本地文件；缺失Provider保持所选身份；quota/reset同窗口。修复首轮小/超大百分比截断、未知usage被当0、候选解析与suggested来源不一致及本轮新增lint warning。最终132测试复跑0失败。View既有三条line_length与type_body_length警告基线同样存在，新增布局已移到private extension，不扩大主要struct至新增上百行。没有远程review/PR/push。

## 2026-09-30 Simulator 环境整理

用户要求旧Simulator关闭或升级27，并随后明确排除正在测试的 Memory Trail · 17e（C0E69606-65DB-4B6B-A96F-FBFDE1E2DAE1）。其余12个iOS26.5实例使用 `xcrun simctl upgrade <UDID> com.apple.CoreSimulator.SimRuntime.iOS-27-0` 原地升级成功，保留App数据；默认测试目标05045514现为iOS27。Devices symlink与realpath仍为 `/Volumes/StudioSSD/Developer/CoreSimulator/Devices`，SSD UUID校验通过。26.5 runtime因被排除实例仍需使用而保留。整理前/后清单保存在BuildScratch的 `simulator-inventory-before.json` / `simulator-inventory-after.json`；本轮相关测试在iOS27复跑 `widget-overview-ios27.log/.xcresult`。

升级实测：原先26.5异常的EA703229实例保留了3个选择，27首启迁移完成后timeline收到count3并桌面显示Codex/Claude/OpenRouter三项（`widget-upgraded27-timeline.log` / `widget-upgraded27-fixed.png`）。升级后重启该设备的sim-use daemon修复旧自动化连接；此结果早于重新安装同版本App。27复跑XCTest12+SwiftTesting120均成功。依据用户最新要求后续默认使用27；26.5环境异常不再阻塞该本地开发任务，但不推断26.5真机行为。

## 最终代码回归与补充验收（2026-09-30）

- 完整 iOS27 suite：`widget-overview-ios27-full.log/.xcresult`；52 XCTest +818 Swift Testing通过，UI16项中10通过、6按运行条件跳过（四项需预置SpringBoard模式环境、两项需tablet）。无失败。此运行在最后小尺寸3项改2×2之前启动。
- 最后改动后全部unit再跑：`widget-overview-final-units.log/.xcresult`；53 XCTest +818 Swift Testing，即871项，0失败；新增小尺寸3项两列与选择上限4测试。最后生产改动仅Overview布局，不影响完整UI suite覆盖的导航/成本功能。
- 渲染64组合均由生产SwiftUI View生成；附件目录 `widget-overview-final-64-images/`，总览 `overview-64-contact-sheet.jpg`。人工查看小3/4、中3/4、大/超大及明暗/单色彩色；百分比、短倒计时、unknown/error完整显示。不存在日期的数据不生成倒计时。
- iPad Pro13 M5 iOS27：原生gallery第8页添加CodexBarStatusWidget超大尺寸，默认四项Codex78%/3.7天、Claude42%/0.6天、Raycast30%/3.6天、OpenRouter不可用。实际截图 `widget-ipad27-overview-xl-added.png`；不是旧TokenActivityComparison。使用Simulator合成数据，不代表Production同步。
- App内Widget Setting四个checkbox实际选择成功，第五个及其余未选项disabled，已选项可取消。截图 `widget-ipad27-checkbox-four.png`。预览页英文短周期显示<0.1d、12d、4d，与中文原生桌面显示天区分。
- 最终Release Simulator构建 `widget-overview-release-final.log` BUILD SUCCEEDED；真机Debug构建 `widget-overview-device-build.log` BUILD SUCCEEDED。
- 用户指定this phone has no air（iOS27）后，本地2.3.0(224)安装成功：`widget-overview-device-install.log`；主App签名Production且get-task-allow=true。首次启动系统报告成功，但截图全黑/UI没有root，已请求解锁并保持CodexBar前台。安装成功不计作真机UI验收通过。
- 循环review：自查与widget_final_review独立agent两轮均无阻塞；最后一轮覆盖小3两列、空第四格、cap4顺序及64矩阵。CLI review因账号不支持所配置模型失败，不计作完成证据；独立agent review是本轮有效证据。
- 四语言审计及diff check通过。未上传、发布、push、merge、tag；用户workflow skill改动未触碰。

- iPad原生超大编辑器保存Codex/Claude两项后，实际桌面精确显示两列，不补其余Provider：`widget-ipad27-xl-two.png`。将同一组件resize成大尺寸后两项转为上下布局：`widget-ipad27-large-two-stable.png`。已人工查看原图/裁剪详情，中文倒计时完整。此验证覆盖系统真实AppIntent选项到WidgetKit渲染，而非直接构造intent。

- iPad原生深色大组件两项显示通过：`widget-ipad27-large-two-dark.png`，倒计时及百分比无截断。

## 真机镜像补充验收（2026-09-30 15:23–15:27 PDT）

用户指出已有iPhone镜像。使用cua_repl绑定com.apple.ScreenContinuity直接观察，镜像正常显示CodexBar；此前devicectl/sim-use全黑图只证明截图接口在该状态下未取到画面，不能判断手机需要解锁。本次无需解锁，通过镜像完成验收。

- 指定this phone has no air的App内小组件设置：中尺寸默认四项，真实本地同步缓存Codex31%/2.8天、Claude28%/4天、Antigravity未知、Grok0%/6.1天；未知usage显示横线，不伪造0%。App内勾选Codex/Claude成功。
- 在真机SpringBoard添加CodexBarStatusWidget中尺寸，加载后默认四项与App数据一致；并非gallery占位数据（gallery78%等不作为通过证据）。
- 原生编辑器候选显示Antigravity/Claude/Codex/DeepSeek/Grok，保存Codex与Claude；关闭编辑器等待实际渲染，桌面只显示两项31%/2.8天和28%/4天，布局变为双列，倒计时无截断。
- 证据为本会话cua_repl截图：查看真机Provider Overview预览、查看真机Provider候选列表、保存Codex和Claude两项、确认真机组件最终渲染。截图由镜像工具直接返回，不声称已另存设备原图。
- 真机亮屏/UI验收已完成，撤销先前待解锁事项。此为一部真机的缓存与Widget验收，16组合Production矩阵仍为substituted，未执行双Mac双iPhone交叉推送。
- 为验收在该手机桌面新增一个中尺寸Overview组件，最终保留Codex/Claude两项。未上传TestFlight或发布。
