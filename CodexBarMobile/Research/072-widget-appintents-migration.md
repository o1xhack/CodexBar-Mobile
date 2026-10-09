# 072 — iOS 27 起改用 App Intents 小组件

状态：done（实现完成；iOS 26.5 / 27.0 / 27.2 模拟器实测通过，见第 6 节；已知验证缺口：真机待验）
日期：2026-10-08（方案二：2026-10-09）
分支：`feat/ios-widget-appintents`（PR #188）
相关：Research/058（小组件重做）、062/09、065 第 8 节（SiriKit 配置结构在添加时存死）、071（额度窗口）

## 1. 背景

- **问题 1**：SiriKit `IntentConfiguration` 的小组件在添加时把配置结构存死。App 更新加的新参数（例如 238 的“额度窗口”）老小组件看不到，只能重新添加（065 第 8 节实测）。
- **问题 2**：用户真机 iOS 27.2 beta（iPhone 17 Pro Max，238）上新添加小组件，在抖动状态下配置好，点“完成”后配置全部丢失。iOS 26.5 模拟器上查到的机制是 SpringBoard 里 WidgetConfigurationExtension 连接中断与 commit 之间的竞态（日志 `is ignoring new intent`），负载高时容易出现；iOS 27 模拟器上没有复现。
- **约束**：Xcode 27 SDK 构建的 `AppIntentConfiguration` 小组件，在 iOS 26.x 上参数传不到 timeline，永远是默认值（FB23176939）；iOS 27.0 / 27.1 / 27.2 正常。

## 2. 为什么不用系统迁移

第一轮按苹果《Migrating widgets from SiriKit Intents to App Intents》做：每个 SiriKit intent 一个 `WidgetConfigurationIntent` + `CustomIntentMigratedAppIntent`（`intentClassName` = SiriKit 类名，参数名和类型逐一对应），四个小组件保持原 kind，`body` 里 iOS 27 用 `AppIntentConfiguration`、更早用 `IntentConfiguration`。实测（附录 A）：

- **iOS 27.0 / 27.2 上迁移本身可用**：238 上配置好的小组件覆盖安装后，编辑面板、timeline、渲染都保留原值；实验构建加的新参数会出现在已迁移的小组件上；抖动中配置 → 完成，都保存成功。枚举按 `INEnumValueName` 落到同名 case，对象的 `identifier` 成了 entity id。
- **iOS 26.5 上回归**：只要 App 的 App Intents 元数据里有指向 SiriKit 类名的迁移 intent，iOS 26.5 的编辑器（WorkflowUI 的 `WidgetConfigurationExtension`，`-[WFLinkActionProvider customIntentMigratedActionIdentifierWithLaunchId:className:]`）就会改用 App Intent 编辑，哪怕这个小组件在 iOS 26 上仍是 `IntentConfiguration`。三次尝试：
  1. 不加可用性限制：编辑面板变成 App Intents 样式；保存后 chronod 报 `No intent in timeline(for:with:completion:)`、`Returned view collection was either nil or empty.`，小组件变成占位骨架。
  2. 所有 App Intents 类型标 `@available(iOS 27.0, *)`：元数据里带 `LNPlatformNameIOS introducedVersion 27.0`，但 iOS 26.5 仍按类名找到它们，取默认值时报 `LNPerformActionErrorCodeActionNotFound`，服务商选择器打不开；只改颜色保存后同样 `No intent in timeline`。
  3. 实验：所有系统都用 `AppIntentConfiguration`：编辑成彩色 / Claude 后 timeline 收到 `style=mono, providerIDs=, window=default`，即 FB23176939；额度窗口的依赖也拿不到服务商。
- 结论：元数据是静态的，iOS 26 不按可用性过滤，所以“同一个 kind、iOS 27 迁移、iOS 26 保留 SiriKit”在同一个二进制里做不到。**用户决定（2026-10-09）**：iOS 27 上另做一套新 kind 的 App Intents 小组件，不走系统迁移。

## 3. 设计（方案二）

- **新 kind，只在 iOS 27 起提供**：`CodexBarStatusWidgetAppIntent`、`CodexBarQuotaPaceWidgetAppIntent`、`CodexBarTokenActivitySingleAppIntent`、`CodexBarTokenActivityComparisonAppIntent`（常量在 `WidgetKinds` / `WidgetActivityKind`，以后不再改）。`WidgetBundle` 里用 `if #available(iOS 27.0, *)` 加入；只用 `AppIntentConfiguration` + `AppIntentTimelineProvider`。
- **不迁移**：没有 `CustomIntentMigratedAppIntent`、没有 `intentClassName`；intent 类型名（`StatusWidgetAppIntent`、`QuotaPaceWidgetAppIntent`、`TokenActivityWidgetAppIntent`、`TokenActivityComparisonAppIntent`）都不等于任何 SiriKit 类名。构建产物的两份 `Metadata.appintents` 里查不到任何 SiriKit intent 类名，也没有 `customIntentClassName`（单测也读 App bundle 的元数据检查）。App Intents 类型仍标 `@available(iOS 27.0, *)`。
- **SiriKit 小组件原样保留**：原 kind、`IntentConfiguration`、`.intentdefinition`、`CodexBarMobileWidgetOptions` 都不变，所有系统上已放置的小组件照常工作。iOS 27 起用 `.disfavoredLocations`（主屏、锁屏、待机、Mac 上的 iPhone 小组件、CarPlay）把它们从小组件库隐藏，图库里只有新版；iOS 26 及以下位置列表为空，图库照旧。不给老小组件加“请重新添加”提示。
- **配置复用**：参数、默认值、动态选项、依赖、`ParameterSummary`、四语言都与第一轮相同（第 4 节），经 `StatusWidgetConfigurationAdapter` 转成现有渲染配置。
- **刷新**：App 写完 Token 活动投影后刷新四个 Token 活动 kind（`WidgetActivityKind.all`）。
- **代价**：iOS 27 用户想用新版要重新添加一次小组件（之后新增的选项会直接出现）；老小组件继续能用，但仍是 SiriKit，问题 1 对它们依旧存在。

主要文件：

- `CodexBarWidgetShared/WidgetConfigurationAppIntents.swift`：`WidgetKinds`、3 个 `AppEnum`、2 个 `AppEntity` + query、4 个 intent。
- `CodexBarWidgetShared/WidgetActivityProjection.swift`：新 Token 活动 kind。
- `CodexBarWidgetShared/StatusWidgetConfigurationAdapter.swift`：AppIntent 入口。
- `CodexBarMobileWidgets/CodexBarWidgets.swift`：新小组件、图库隐藏。
- `CodexBarMobileWidgets/StatusWidgetTimeline.swift`、`WidgetActivityTimeline.swift`：4 个 `AppIntentTimelineProvider`。DEBUG 日志统一为 `sirikit <小组件> timeline …` 和 `appintent <小组件> timeline …`（小组件为 status / pace / single / comparison；SiriKit 的 Token 活动另有 `sirikit single snapshot`），实测靠它区分走的是哪条路径。共用的 `Overview configuration count` 不带前缀。第 6 节引用的是统一前缀之前的日志（SiriKit 的 CodexBar 小组件当时是 `status] mode=…`、Token 活动是 `single timeline source: TokenActivitySource(rawValue: N)`）。
- `CodexBarMobile/Models/WidgetActivityPublisher.swift`：刷新新 kind。
- `CodexBarWidgetShared/WidgetConfiguration.xcstrings`：编辑面板文案，四语言措辞逐条取自 SiriKit 的 `.strings`（主 `Localizable` 表里同名 key 已被 App 用成另一套译法）。
- `CodexBarMobileTests/WidgetConfigurationAppIntentsTests.swift`。

## 4. 参数

| App Intent（SiriKit 对应） | 参数 | 类型 | 默认 |
|---|---|---|---|
| `StatusWidgetAppIntent`（`SelectStatusWidget`） | `mode` | `StatusWidgetModeAppEnum`（overview / providerFocus / todayCost / syncHealth） | `overview` |
| | `colorStyle` | `StatusWidgetColorStyleAppEnum`（mono / colorful） | `mono` |
| | `provider1`…`provider4` | `StatusWidgetProviderAppEntity?`，只在概览显示 | 未选择 |
| `QuotaPaceWidgetAppIntent`（`SelectQuotaPaceWidget`） | `colorStyle` | `StatusWidgetColorStyleAppEnum` | `mono` |
| | `provider` | `StatusWidgetProviderAppEntity?` | 未选择 |
| | `quotaWindow` | `QuotaPaceWindowOptionAppEntity?`，有服务商时显示 | 默认（每周） |
| `TokenActivityWidgetAppIntent`（`SelectTokenActivity`） | `source` | `TokenActivitySourceAppEnum`（all / claude / codex） | `all` |
| `TokenActivityComparisonAppIntent`（`CompareTokenActivity`） | `firstSource` / `secondSource` | `TokenActivitySourceAppEnum` | `all` / `claude` |

- 服务商 query：第一项“未选择”（保留 id `codexbar-widget-choice:none`），后面是 App Group catalogue；`defaultResult()` 是“未选择”；catalogue 里没有的 id 仍保留，标题用 id（与 SiriKit 不同：SiriKit 存着当时的显示名，App Intents 只存 id，所以已下线的服务商会显示成 id，渲染仍按 id 取数据）。选项由 `StatusWidgetProviderChoice.choices` 生成，两代小组件共用。
- 额度窗口 query：`@IntentParameterDependency<QuotaPaceWidgetAppIntent>(\.$provider)` 读当前编辑的服务商，选项与 071 的 `QuotaPaceWindowChoice.options` 完全相同；`defaultResult()` 是“默认（每周）”；`entities(for:)` 先按 id 里的服务商前缀在该服务商的选项里找；选项里没有时（例如只剩一个窗口、它就是默认窗口，选项只给“默认（每周）”），再到 catalogue 的 `record.windows` 里按窗口 id 找，用 `title(preferredLocalizations:)` 作标题；都找不到才用窗口 id。
- 参数名和 SiriKit 一致（单测核对），只是为了两代小组件配置方式相同，不再用于迁移。
- **隐藏参数会保留值**：App Intents 版在父参数切走后（例如 CodexBar 从概览切到服务商详情）仍保留服务商 1–4 的值，切回概览时原来的选择还在；SiriKit 版不保存被隐藏的参数（附录 A.1）。渲染不受影响：只有概览和额度消耗趋势读配置的服务商，服务商详情、今日费用、同步状态不读。
- **catalogue 读不出来时**：新版服务商选项回落为只有“未选择”，额度窗口回落为只有“默认（每周）”。SiriKit 的 `IntentHandler.provideOptions` 原来出错时把错误交给系统（选择器打不开），这次改为同样回落到“未选择”（共用 `StatusWidgetProviderChoice.choices`，单测覆盖的是这个共用函数；`IntentHandler` 只编进 Options 扩展，没有测试 target 能直接调用它）。

## 5. 单测与 lint

- `WidgetConfigurationAppIntentsTests`（Swift Testing）：
  - 读 App bundle 里的两份 `.intentdefinition`，核对四个 App Intent 的参数名、类型、枚举 case 与 SiriKit 一致；枚举参数的默认值直接拿 `.intentdefinition` 的 `INIntentParameterMetadataDefaultValue` 和 App Intent `init()` 后的 rawValue 比，不在测试里写死；
  - **不映射到 SiriKit**：四个类型都不遵循 `CustomIntentMigratedAppIntent`、类型名不等于 SiriKit 类名（iOS 27 起才跑）；另一项不带 `@available`、所有系统都跑：读 App 的 `Metadata.appintents/extract.actionsdata` 和 `PlugIns/CodexBarMobileWidgets.appex/Metadata.appintents/extract.actionsdata`，整份文件里不能出现四个 SiriKit 类名（用 `NSStringFromClass` 取）和 `customIntentClassName`，文件不存在就失败；
  - kind：新旧 8 个 kind 互不相同，SiriKit 的 4 个 kind 保持原值，`WidgetActivityKind.all` 含四个 Token 活动 kind；
  - 对象参数初始为空、经 query 的 `defaultResult()` 取默认值；AppIntent 与 SiriKit 同样输入经 adapter 的结果一致（四种模式 × 两种颜色、去重、空名回落 id、“未选择”、窗口 id）；Token 来源 id；
  - 两个 query 的选项、默认值、按 id 解析（含“不再提供的单一默认窗口仍有标题”）、catalogue 读不出来时的兜底；共用的服务商选项函数。
  - **依赖接线没有单测**：额度窗口选项随服务商变化，单测是用测试注入的服务商 id（`providerIDOverride`）验证选项计算；`@IntentParameterDependency` 本身由系统在编辑面板里注入，只有 SpringBoard 实测证据（第 6 节动态选项）。
  - `@Suite` 不能加 `@available`，所以可用性标在各个 `@Test` 上。
- 全量 iOS 单测（`-only-testing:CodexBarMobileTests`，iOS 27.0 模拟器，区域 en_US）：Swift Testing 1046 项（64 个 suite）+ XCTest 60 项全部通过（`logs/v2-full.log`、`xcresult/v2-full.xcresult`；开跑时 load average 约 153）。
- 构建产物检查：App 和小组件扩展的 `Metadata.appintents` 里搜不到四个 SiriKit 类名和 `customIntentClassName`。
- `Scripts/lint.sh audit-i18n` 通过（三份 xcstrings 全部翻译，406 个源 key 都在目录）。
- 改动的 Swift 文件用仓库的 swiftformat 0.63.0 / swiftlint 0.65.1 检查：新增和改动的代码无告警；剩下的告警都在原有行上（`WidgetActivityTimeline.swift` 的 SiriKit provider 6 处超长行、`WidgetActivityProjection.swift` 预览数据里的 7 处，`origin/mobile-dev` 上相同）。

## 6. 模拟器实测（方案二）

环境：Xcode 27.0（27A266a），Debug 构建，模拟器本地签名；iPhone 17 Pro，系统语言简体中文；每台设备先抹掉，再装 238、用 `UI_TEST_PREVIEW_DATA` 写 catalogue，并换成合成 catalogue（Claude：当前周期 / 每周 / 仅 Fable；Codex：每周）和合成 Token 活动投影。证据目录 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/widget-appintents/runs/`。

### 6.1 iOS 26.5（23F77）回归：通过（`v2-ios265/`）

| 项 | 结果 | 证据 |
|---|---|---|
| 238 上放好 4 种老小组件并配置 | 额度（彩色 / Claude / 每周）、CodexBar（概览 / 彩色 / Claude / Codex）、Token 活动（Codex）、对比（Claude Code / Codex） | `238-*`、`log-238-setup.txt` |
| 覆盖安装新构建后照常显示 | timeline 全走 SiriKit：`sirikit pace ... colorful, providerIDs=claude, window=claude\|secondary`、`status mode=overview, style=colorful, providerIDs=claude,codex`、`single source: 3`、`sirikit comparison sources: 2,3` | `log-v2-install.txt`、`v2-page*-after-install.png` |
| 编辑面板能打开、服务商选择器能用、改值生效 | 额度改成 Codex / 单色 → `sirikit pace timeline style=mono, providerIDs=codex`；对比第一个改成全部 → `sources: 1,3`；CodexBar 改成今日费用 → `mode=todayCost`；Token 活动改成 Claude Code → `source: 2`；主屏渲染都跟着变 | `v2-*-set.png`、`v2-page*-after-edits.png`、`stream-v2.log` |
| 不能出现的错误 | 安装后整段日志：`No intent in timeline` 0 次、`LNPerformActionErrorCodeActionNotFound` 0 次、`view collection was either nil` 0 次，没有占位骨架 | `stream-v2.log` |
| `customIntentMigratedActionIdentifier` 查找 | 编辑器每次打开都会查（5 次），但没有命中我们的 App Intent：没有 `WFLinkAction ... identifier: com.o1xhack.codexbar.mobile.*`；唯一一条 `LNAction creation context` 是原有的旧版隐藏小组件 `CodexBarWidgetConfigurationIntent`。编辑走 SiriKit（`INCExtensionConnection` 28 次）。第一轮同类日志有 59 条命中 | `stream-v2.log`、`ios26-regression/stream.log` |
| 图库 | 9 页：Token 活动 小 / 中、对比 大、CodexBar 小 / 中 / 大、额度 小 / 中 / 大，与 238 相同，没有新 kind；新加一个额度小组件仍是 SiriKit（`sirikit pace` 日志） | `gallery/`、`v2-newadd-page.png` |

- 有一次编辑出现 `is ignoring new intent`（覆盖安装后、load 约 95），就是 iOS 26.5 已知的 SiriKit 竞态，重启后同样操作 commit 正常；238 上同样存在，不是本次引入。
- 覆盖安装后，编辑面板的参数名会暂时显示英文，重启后恢复中文（065 第 8 节记录过的系统缓存），27.0 / 27.2 上也一样。

### 6.2 iOS 27.0（24A434）与 27.2（24B5089g）

| 项 | 27.0 | 27.2 | 证据 |
|---|---|---|---|
| 238 上放好的老小组件，覆盖安装后照常显示 | 通过（值同 26.5，全走 `sirikit` 日志） | 通过 | `v2-ios270/`、`v2-ios272/` 的 `log-v2-install.txt` |
| 老小组件能编辑 | 通过：额度改 Codex / 单色、对比改全部、CodexBar 改今日费用、Token 改 Claude Code，都 commit 并进 timeline | 通过（同上） | `editold*.out`、`v2-*-set.png` |
| 图库只有新的 4 个 | 9 页，名称、尺寸与 SiriKit 版相同；从图库添加的都是新 kind（日志只有 `CodexBarQuotaPaceWidgetAppIntent` / `CodexBarStatusWidgetAppIntent`，没有 `CodexBarQuotaPaceWidget:` / `CodexBarStatusWidgetV2:`；timeline 是 `appintent` 日志） | 同 27.0 | `gallery/`、`v2-ios27*-new/stream.log` |
| 新小组件抖动中配置 → 完成 → 读回 | 额度 5/5（Q1–Q4、Q7）、CodexBar 2/2（S2、S3） | 额度 5/5（Q2–Q6）、CodexBar 2/2（S1、S2） | `v2-ios27*-new/trial-*.json`、`shots/*-readback.png` |
| 动态选项与依赖 | 通过 | 未单独测（与 27.0 同一实现） | `v2-ios270-new/dyn/` |
| 新参数出现在已放置的新小组件上 | 通过 | — | `v2-ios270-new/exp/` |

- **抖动中配置**：每次都是新添加（图库）→ 不退出抖动直接点小组件 → 设彩色 / Claude / 仅 Fable（CodexBar：彩色 / Claude / Codex）→ 点面板外关闭 → 点“完成” → 长按“编辑小组件”读回 → 删除。SpringBoard 顺序全部是先 `is committing new intent`，约 1 秒后 `Disconnecting remote view controller`；额度读回都是彩色 / Claude / 仅 Fable，timeline 有记录的几次是 `appintent pace timeline style=colorful, providerIDs=claude, window=claude|claude-weekly-scoped-fable`。CodexBar 两组读回 Claude / Codex，颜色停在单色：这是脚本按标签点“彩色”没点上（关闭前的截图就是单色），读回与关闭前一致。关闭前 load average：27.0 为 251.7 / 43.6 / 9.5 / 7.4 / 15.9（额度）、5.9 / 52.3（CodexBar）；27.2 为 17.3 / 12.0 / 7.0 / 19.9 / 5.7、17.0 / 11.4。
- 不计入的几次（脚本问题，都发生在配置之前）：系统通知授权弹窗挡住；点小组件时打开了 App（抖动状态已退出或点到了别处）；27.2 的软键盘不接受 HID 输入，改成逐键点按后正常。打开 App 会用演示数据重写 catalogue，每次都恢复了合成数据。
- **动态选项**：服务商菜单第一项“未选择”；额度窗口 Claude 为 默认（每周）/ 当前周期 · 5小时 / 每周 · 7天 / 仅 Fable · 7天，Codex 只有默认（每周），切换服务商后窗口回到默认；CodexBar 改成服务商详情后面板只剩类型和颜色两行，timeline `mode=providerFocus, providerIDs=`；额度选“未选择”后 timeline `providerIDs=, window=default`（自动选择）。
- **新参数**：scratch 实验构建（`src-exp2/`，build 240，不提交）给 `QuotaPaceWidgetAppIntent` 加 `experimentNote: String = "probe"`。覆盖安装后，已放置的新额度小组件（彩色 / Claude / 仅 Fable）编辑面板多出 “Experiment Note: probe”，原配置都在，timeline 带 `experimentNote=probe`；装回正式构建后配置仍在（`log-back.txt`）。

## 7. 局限

- iOS 27 上已放置的老小组件不会自动换成新版，用户要从小组件库重新添加一次；老小组件继续能用、能编辑，但仍受问题 1 限制。
- 问题 2 在模拟器上（iOS 27.0 / 27.2，SiriKit 与 App Intents）都没有复现，用户真机上丢配置的原因仍未定位；新版小组件是否解决需要真机验证。小组件库里不能预先配置（附录 A），所以不是那条路径。
- iOS 26.5 的 SiriKit 竞态（关闭面板时连接中断早于 commit，`is ignoring new intent`）是系统问题，本次不处理。
- 真机未验证。

## 附录 A. 第一轮：系统迁移方案的实测（已放弃）

环境：Xcode 27.0（27A266a），Debug 构建，模拟器本地签名；设备 iPhone 17 Pro，系统语言简体中文；`UI_TEST_PREVIEW_DATA` 启动 App 写 catalogue 后，按小组件模拟数据把 Claude 改成当前周期 / 每周 / 仅 Fable、Codex 只留每周（`catalogue-synthetic.json`），另写一份合成 Token 活动投影。证据目录 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/widget-appintents/`。

### A.1 iOS 27.0（24A434）

1. **迁移保留配置：通过。** 238 上添加 6 个小组件并配置：CodexBar 中（服务商详情 + 彩色）、CodexBar 小（概览，服务商 1 Claude、2 Codex）、额度消耗趋势中（彩色 + Claude + 每周）、Token 活动小（Codex）、Token 活动中（保持默认“全部”作对照）、Token 活动对比大（Claude Code / Codex）。238 的 timeline 日志和主屏渲染都对。覆盖安装新构建后：
   - timeline 全部走 App Intents（`appintent` 日志），值与 238 一致：`mode=providerFocus, style=colorful`；`mode=overview, style=mono, providerIDs=claude,codex`；`pace style=colorful, providerIDs=claude, window=claude|secondary`；`single source: codex` / `all`；`comparison sources: claude,codex`；
   - 编辑面板读回一致（概览 / 单色 / 服务商 1 Claude / 服务商 2 Codex；服务商详情 / 彩色且不显示服务商槽；彩色 / Claude / 每周；Codex；Claude Code / Codex）；
   - 主屏渲染与 238 相同（小组件里 Claude、Codex 的顺序也跟着配置，而不是自动选择的 Codex、Claude）。
   - 附带发现：238 上先在概览选好服务商、再切到服务商详情，SiriKit 不保存被隐藏的服务商（238 日志 `providerIDs=` 为空），迁移后同样为空。这是 SiriKit 原有行为。
   - 证据：`runs/ios27-migration/`（`log-238-config.txt`、`log-238-status2.txt`、`log-239-install.txt`、`08-*`、`11-*`、`12-*`）。
2. **问题 1 已解决：通过。** 实验构建（只在 scratch，`src-exp/`，build 240）给 `SelectQuotaPaceWidgetAppIntent` 加了一个 `experimentNote: String = "probe"` 参数。覆盖安装后，第 1 步迁移来的老额度小组件编辑面板多出“Experiment Note: probe”，原来的彩色 / Claude / 每周都在，timeline 带 `experimentNote=probe`。装回正式构建后配置仍在。证据 `runs/ios27-experiment/`。
3. **问题 2：** 新添加额度消耗趋势，在抖动状态下改颜色 + 服务商 + 窗口（彩色 / Claude / 仅 Fable）→ 点面板外关闭 → 点“完成” → 读回，以及 CodexBar 小组件（彩色 / Claude / Codex）。结果见下表；SpringBoard 日志顺序为先 `is committing new intent`，再 `Disconnecting remote view controller`，读回时没有改动的那次是 `is ignoring new intent`（没有改动时系统也打印 ignoring，不代表丢失）。证据 `runs/ios27-race/`（`trial-*.json`、`shots/`、`stream.log`）。

   | 系统 | 次数 | 构建 | 关闭前 load avg | SpringBoard 顺序（关闭面板后） | 读回 | 结论 |
   |---|---|---|---|---|---|---|
   | 27.0 | Q1–Q4 额度 | 239-a（未加 `@available`） | 86.7 / 64.6 / 74.0 / 18.5 | 均为 `committing new intent` → `Disconnecting` | 彩色 / Claude / 仅 Fable（截图 Q1–Q3，Q1、Q4 有 timeline 日志） | 4/4 保存 |
   | 27.0 | Q5 额度 | 239-b（最终代码） | 13.4 | commit → disconnect | 彩色 / Claude / 仅 Fable，timeline 一致 | 1/1 保存 |
   | 27.0 | S1–S2 CodexBar | 239-b | 4.0 / 6.9 | commit → disconnect | Claude / Codex 保存；颜色停在单色（见下） | 2/2 保存 |
   | 27.2 | Q1–Q5 额度 | 239-b | 5.2 / 7.5 / 5.1 / 约 7 / 11.1 | 均为 commit → disconnect（Q4 的 JSON 因删除步骤失败没写出，按 `stream.log` 21:24:15 commit） | 彩色 / Claude / 仅 Fable（Q1、Q3、Q4、Q5 截图核对，Q2 有 commit） | 5/5 保存 |
   | 27.2 | S1–S2 CodexBar | 239-b | 5.1 / 5.6 | commit → disconnect | Claude / Codex 保存；颜色停在单色 | 2/2 保存 |

   说明：
   - CodexBar 小组件那两组，“颜色样式”是第二行，弹出菜单的无障碍树时有时无，脚本按标签点“彩色”没点上（`configured` 截图里关闭前就是单色），读回与关闭前一致，不算丢失。
   - 另有几次是脚本问题中途停止，不计入：负载高时 SpringBoard 在加完小组件后自己退出抖动，脚本再点小组件就打开了 App；还有一次删除小组件时长按没出菜单。打开 App 会用演示数据重写 catalogue，每次都恢复了合成数据。
   - 抖动状态有时会自己退出，这本身值得在真机上留意，但本次没有证据表明它和配置丢失有关。

4. **动态选项与依赖：通过。**
   - 额度窗口：Claude 为 默认（每周）/ 当前周期 · 5小时 / 每周 · 7天 / 仅 Fable · 7天；Codex 只有默认（每周）。改服务商后窗口自动回到“默认（每周）”（SiriKit 会留着旧选择，071 第 2.3 节；渲染时本来就按默认处理）。
   - 新添加的 App Intents 小组件，服务商和窗口直接显示“未选择”“默认（每周）”（SiriKit 显示“选取”）。
   - CodexBar 小组件在服务商详情模式下不显示服务商 1–4。
   - 选“未选择”回到自动选择：额度小组件 `providerIDs=` 为空、窗口 `default`；CodexBar 小组件两个槽都改回“未选择”后 `providerIDs=` 为空，渲染回到自动的 Codex、Claude。
   - 编辑面板的选择器从 SiriKit 的整页列表变成弹出菜单（系统 UI）。
   - 证据 `runs/ios27-dynamic/`。
5. **图库里预先配置（主会话追加）：图库不支持。** iOS 27.0 小组件图库的详情页只有预览、页码和“添加小组件”，轻点或长按预览都不会出现配置项（长按只是拿起拖动）。238（SiriKit）和新构建（App Intents）一样。证据 `runs/ios27-gallery/`。

### A.2 iOS 27.2（24B5089g）

- **迁移保留配置：通过。** iPhone 17 Pro 模拟器（用户真机是 17 Pro Max，为复用脚本坐标用了 Pro）。238 上配置：CodexBar 中（概览 / 彩色 / Claude / Codex）、额度消耗趋势中（彩色 / Claude / 仅 Fable）、Token 活动对比大（Claude Code / Codex）；238 日志 `mode=overview, style=colorful, providerIDs=claude,codex`。覆盖安装新构建（`builds/239-b.app`，即最终代码）后 timeline 全走 App Intents，值一致（`pace ... providerIDs=claude, window=claude|claude-weekly-scoped-fable`、`status ... style=colorful, providerIDs=claude,codex`、`comparison sources: claude,codex`），编辑面板读回一致。证据 `runs/ios272/`（`log-238-config.txt`、`log-239-install.txt`、`07-*`、`08-*`、`09-*`）。
- **问题 2：** 结果见 A.1 第 3 项的表。

### A.3 iOS 26.5（23F77）回归：**失败**

- 新构建（未加 `@available` 的版本，`builds/239-a.app`）：添加额度消耗趋势和 CodexBar 小组件后，默认配置渲染正常。用“编辑小组件”改额度小组件（彩色 / Claude）时，编辑面板已经是 App Intents 的样式（弹出菜单，窗口默认显示“默认（每周）”，且 Claude 只给“默认（每周）”一项）。关闭后小组件变成占位骨架，chronod 日志：`No intent in timeline(for:with:completion:)`、`Returned view collection was either nil or empty.`。证据 `runs/ios26-regression/04-*`、`05-home-after-pace.png`、`stream.log`。
- 原因（日志）：iOS 26.5 的 `WidgetConfigurationExtension`（WorkflowUI）打开 SiriKit 小组件的编辑面板时，会调 `-[WFLinkActionProvider customIntentMigratedActionIdentifierWithLaunchId:className:]`，在 App 的 App Intents 元数据里找 `customIntentClassName` 等于这个 SiriKit 类名的 action。238 上找不到，于是走 SiriKit；新构建里找到了，就改用 App Intent（`WFLinkAction ... SelectQuotaPaceWidgetIntent`）来编辑和保存。保存的是 App Intent，而 iOS 26 上这个 kind 是 `IntentConfiguration`，timeline provider 拿不到 `INIntent`。
- 加 `@available(iOS 27.0, *)` 后（`builds/239-b.app`）：元数据里这些 action 带 `LNPlatformNameIOS introducedVersion 27.0`，但 iOS 26.5 仍按类名找到了它们，再向扩展取默认值时报 `LNPerformActionErrorCodeActionNotFound`，服务商选择器点不开。证据同目录 `08-239b-*`、`09-*`。
- 再试一个只用于实验的变体（`src-all/`，build 241，不提交）：所有系统都用 `AppIntentConfiguration`。iOS 26.5 上新添加额度小组件，编辑为彩色 / Claude 后，timeline 收到的是 `style=mono, providerIDs=, window=default`，即 FB23176939；而且额度窗口在 iOS 26.5 上只给“默认（每周）”（`@IntentParameterDependency` 没有拿到服务商）。证据 `runs/ios26-allappintents/`。
- 加 `@available` 的构建上只改颜色也一样：保存后 `No intent in timeline(for:with:completion:)`（`10-239b-*`、`11-239b-*`）。
- 结论：**只要扩展里有 `CustomIntentMigratedAppIntent` 指向这些 SiriKit 类，iOS 26.5 的编辑就会改走 App Intents**，而 iOS 26 上 App Intents 小组件又受 FB23176939 影响。“iOS 26 保留 SiriKit、行为完全不变”在同一个二进制里做不到（元数据是静态的，iOS 26 不按可用性过滤）。真机 iOS 26 未验证。

## TestFlight（2026-10-09）

- PR #188 两轮 Codex review：第一轮 1 条 P2（本文状态）已修；第二轮 “Didn't find any major issues”。门禁 rounds=2、unresolved=0，`--match-head-commit` 合并为 `f74ecaf0d`。
- 合并前在最终 head `a53416edb` 上跑完整 iOS 单测：Swift Testing 1,049 项、XCTest 60 项全部通过。合并后源码（detached worktree `ios239-src`）完整 lint 和 i18n 审计通过。
- iOS 2.6.0 (239) 已上传，ASC build id `b93da15e-3106-4d45-a0c4-1c8f3684488e`，状态 `VALID`，内测 `IN_BETA_TESTING`。
- 图标验收：
  - 归档里的 `AppIcon60x60@2x.png` 与 238 逐字节相同；
  - Apple CDN 图标为 152×152，目视正确。
- 仍待用户在 iOS 27.2 真机上验证：从小组件库添加新版小组件，在抖动状态下配置后点“完成”，确认配置保留。
