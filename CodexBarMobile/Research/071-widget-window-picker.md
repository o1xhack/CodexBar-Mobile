# 071 — 额度消耗趋势小组件：按服务商选择额度窗口

状态：done（已实现；全量单测、渲染矩阵、i18n 审计通过，模拟器 SpringBoard 上验证了新添加小组件的配置流程；分支 `feat/ios-widget-window-picker`，未推送、未开 PR；见第 6 节）
日期：2026-10-08
相关：Research/065（Quota pace 数据来源与小组件、SiriKit 配置结构在添加时存死）、Research/060（小组件服务商 catalogue）

## 1. 需求

编辑小组件时，选好服务商后，下面可以选这个服务商的额度窗口：

- Claude：当前周期（Session）、每周（Weekly）、仅 Fable（`claude-weekly-scoped-fable`）三选一。
- Codex、muse.ai：只有每周，不需要选。
- Antigravity：窗口有 1 到 10 个甚至更多，要能选。
- 默认每家都选每周，用户可以改。

## 2. 调研结论

### 2.1 是哪个小组件

**是“额度消耗趋势”（Quota pace，kind `CodexBarQuotaPaceWidget`，意图 `SelectQuotaPaceWidget`）。**

| 小组件 | 有没有服务商参数 | 和额度窗口的关系 | 结论 |
| --- | --- | --- | --- |
| 额度消耗趋势 | 有，单选 `provider` | 主数字、配速、预估、曲线、重置时间都描述“某一个窗口” | 本次改这个 |
| CodexBar 小组件（`CodexBarStatusWidgetV2`）概览模式 | 有，`provider1`–`provider4` | 每个服务商只显示一个“用得最多的窗口”的百分比，不涉及配速 | 不改，见 2.5 |
| CodexBar 小组件其它模式（服务商详情、今日费用、同步状态） | 没有 | — | 不涉及 |
| Token 活动 / Token 活动对比 | 有“来源”参数（全部、Claude Code、Codex） | 统计的是 token，没有额度窗口 | 不涉及 |
| 旧版 CodexBar 小组件（App Intent，已从小组件库隐藏） | — | 只显示“请重新添加” | 不涉及 |

### 2.2 小组件能不能拿到窗口数据

- **小组件本身**：`CodexBarWidgetProvider.makeTimeline` 每次刷新直接从 CloudKit 读各台 Mac 的快照，用和 App 同一个 `ProviderSnapshotMerger` 合并。合并结果里有完整的 `ProviderUsageSnapshot.rateWindows`（含 `id`、`label`、`windowMinutes`、`period`、`usedPercent`、`resetsAt`）和 `utilizationHistory`。所以小组件侧窗口数据本来就有，不需要扩展同步格式（`Shared/` 不动）。App Group 里**没有**合并快照，只有两份文件：服务商 catalogue（`widget-provider-catalogue-v1.json`）和 Token 活动投影。
- **配置选项**：编辑面板的选项由 `CodexBarMobileWidgetOptions`（Intents 扩展）的 `IntentHandler` 提供，它只读 App Group 里的 catalogue。原来的 catalogue 只有 `id` 和 `name`，所以要扩展：每个服务商加一个可选的 `windows` 数组（窗口 id、原始 label、时长、四种语言的标题）。旧文件没有这个字段，照样能解码，只是这个服务商只给“默认（每周）”一个选项。catalogue 由 App 在每次同步刷新后写（`WidgetActivityPublisher`）。

### 2.3 SiriKit 能做到哪一步

**已添加的小组件能不能看到新参数：不能。** Research/065 第 8 节在模拟器上实测过：`IntentConfiguration` 的小组件在添加时把当时的配置结构（参数和枚举值）存进小组件，之后不随 App 更新；给 `SelectStatusWidget` 加的枚举值和参数，老小组件的编辑面板里都看不到，只有新添加的才有。这次给 `SelectQuotaPaceWidget` 加参数属于同一种改动，结论相同（本次没有在 SpringBoard 上重复实测，见第 7 节）。所以：

- 已经放在主屏上的额度消耗趋势小组件，`quotaWindow` 永远是空的，走“默认（每周）”。对 Codex、Claude 来说和以前完全一样（以前描述的就是原生每周窗口）。
- 想用新选项，需要移除后重新添加。App 内更新说明和 App Store 说明都写了这一句。

**父子联动（parentParameter）**：

- `.intentdefinition` 的参数关系（`INIntentParameterRelationship`）里，父参数是对象类型时，Xcode 只支持两种条件：`HasAnyValue` 和 `ObjectIdentifierValueContains`（从 Xcode 26 的 `IDEIntentBuilderCore` 里查到的全部谓词；枚举父参数才有 `EnumHasExactValue`，数字和布尔另有几种）。没有任何条件能根据**动态数据**（这个服务商有几个窗口）来显示或隐藏子参数。
- 所以“只有一个窗口的服务商隐藏这个参数”做不到。采用的方案：`quotaWindow` 设父参数 `provider`、条件 `HasAnyValue`（服务商有值时显示）。服务商的默认值是“未选择”这个对象，本身也算有值，所以参数一直显示。只有一个窗口的服务商（Codex、muse.ai）和“未选择”时，选项只有“默认（每周）”一项，等于不用选。
- `ObjectIdentifierValueContains` 理论上可以按服务商 id 的子串来显示，但服务商 id 是已存进各小组件里的稳定值，不能为了这个改 id，所以没用。
- `relevantParameters` / `@IntentParameterDependency` 是 App Intents（`WidgetConfigurationIntent`）的能力。改用 App Intents 意味着换一个新的小组件 kind，所有已添加的小组件配置都会丢，不值得。

**选项随服务商变化**：每次打开窗口选择列表，系统都会调用 `provideQuotaWindowOptionsCollection(for:with:)`，传入的 intent 带着当前选中的服务商。所以先改服务商、再点窗口，列表就是新服务商的窗口。

**改了服务商以后，原来选的窗口会怎样**：没有文档说明；模拟器实测（第 6 节）**系统不会清空子参数**：Claude 选了“仅 Fable”后把服务商改成 Codex，“额度窗口”仍显示“仅 Fable”。为了不依赖系统行为，窗口选项的 identifier 写成 `<服务商 id>|<窗口 id>`（例如 `claude|claude-weekly-scoped-fable`）。渲染时如果 identifier 里的服务商和当前服务商不一致，就当作没选，走默认（每周）。窗口从数据里消失时也一样。

`defaultQuotaWindow(for:)` 返回“默认（每周）”（identifier `codexbar-widget-window:default`）。实测新添加的小组件里这一行显示的是系统的“选取”（值为空），说明系统没有对这个子参数调用默认值；空值和“默认（每周）”在渲染时等价，都走每周。

### 2.4 选项内容

- **来源**：所选服务商最近一次同步的窗口里，用量已知的窗口（`usageKnown`），按卡片顺序（原生槽位在前，附加窗口在后）。没有 id 的旧 Mac 数据按位置叫 `primary` / `secondary` / `tertiary`。同一服务商多个账号的窗口取并集。
- **标题**：和 App 的服务商卡片同一套 `ProviderWindowLabel`（从 App target 挪到 `CodexBarWidgetShared`，App 和小组件共用），普通槽位名（Session、Weekly）再走一次和小组件曲线标签相同的 `ProviderDetailLocalization`。没有 label 的窗口先按时长命名（7 天叫“每周”），再按槽位。四种语言的标题由 App 写进 catalogue，Intents 扩展按自己的首选语言取。
- **时长**：每个选项的副标题是窗口时长（例如“7 天”“5 小时”），用系统的 `DateComponentsFormatter` 本地化。两个选项标题相同时，标题后面再加时长区分。
- 例子：
  - Claude：默认（每周）、当前周期、每周、仅 Fable。
  - Codex（只有每周）、muse.ai：只有默认（每周）。
  - Antigravity：默认（每周）、Gemini · 每周、Gemini · 5 小时、Claude/GPT · 每周……（每个已知用量的窗口一项）。

### 2.5 CodexBar 小组件概览模式要不要同步

概览模式每个服务商只显示一个数字（用得最多的窗口），最多四个服务商。要按服务商选窗口，需要再加四个参数，而且已添加的小组件同样看不到。用户说这次只改一个小组件，所以**不改**，以后有需要再单独评估。

## 3. 设计

### 3.1 默认窗口

`QuotaPaceWindowSelection.defaultWindowID(for:now:)`，只考虑用量已知、还没重置的窗口：

1. 原来的配速窗口（`QuotaPace.window(for:)`，原生 secondary → tertiary → primary）是每周的，就用它。Codex、Claude 都在这一步。
2. 否则找每周窗口（`windowMinutes == 10080`，或没有时长但 `period == .weekly`）：先原生槽位，再附加窗口。Antigravity 没有原生槽位，用第一个每周窗口（例如 Gemini · 每周）。
3. 否则沿用 Research/065：原来的配速窗口有配速就用它（例如只有月度窗口的服务商）。
4. 都没有：保持原来的“按曲线车道回退”（例如每周用量未知时显示当前周期的曲线）。

用户没选、选了“默认”、选项属于别的服务商、选的窗口已经不在数据里，都走这个默认。

### 3.2 小组件数据

- `CodexBarWidgetPaceSummary` 新增 `windows`（每个窗口的 id、label、period、时长、配速、剩余、重置时间、对应的曲线车道）、`windowID`（当前描述的窗口）、`isExplicitWindow`。`pace` / `paceRemainingPercent` / `paceResetsAt` 仍表示当前描述的窗口，原有调用不变。`selecting(windowID:)` 返回指向所选窗口的同一份数据。
- 配速仍用 `QuotaPace(window:capturedAt:referenceDate:providerID:)`，按 Mac 观测时间算，和详情页同一个公式；不到一天的窗口（5 小时当前周期）不出配速，和 App 一致。OpenCodeGo 估算用量不出配速的规则对所有窗口生效。
- 曲线只有 Codex、Claude 的原生槽位有观测历史（`MobileQuotaBurndown.resolvedLanes`），窗口和车道按同一个 `SyncRateWindow` 对应。
- 自动选择服务商时不看窗口选择，用默认窗口；候选条件仍是“有配速或有曲线”（`isAutomaticCandidate`），所以只有短窗口的服务商仍不会被自动选中。
- 解码兼容：新字段都用 `decodeIfPresent`，旧数据解码为空。

### 3.3 显示

- 小：选了窗口时，主数字后面写窗口名（“29% 仅 Fable · 剩余”）；默认时保持原样。
- 中：主数字后的标签用所选窗口名；有曲线就画曲线，没有曲线（仅 Fable、Antigravity）就在右栏画剩余进度条，并且不再显示当前周期那一行，免得进度条被看成当前周期的。
- 大：所选窗口有曲线时，显示包含它的前两条曲线（当前周期和每周）；没有曲线时显示主数字和进度条。
- 超大：两列，每列只画所选窗口的曲线。
- 重置时间：不到一天的窗口改成按小时（“2.4小时”），新增文案 `%@h` 四语言。

### 3.4 兼容性

| 情况 | 行为 |
| --- | --- |
| 237 之前添加的额度消耗趋势小组件 | 编辑面板没有“额度窗口”参数（配置结构存死），一直走默认（每周）。Codex、Claude 和以前一样 |
| 旧 catalogue（App 还没在新版本里刷新过） | 服务商只给“默认（每周）” |
| 新窗口出现（例如 Antigravity 新桶） | App 下次同步刷新后写入 catalogue，编辑面板才有 |
| 改了服务商 | 原窗口选项不属于新服务商，走默认 |
| 窗口消失 | 走默认 |
| 选的窗口暂时没有用量 | 显示服务商名和“暂无配速数据”（和服务商不可用时一样） |

**行为变化**：附加窗口里才有每周额度的服务商（Antigravity 等），以前没有配速、不会被自动选中；现在默认用每周窗口，有了配速，会参与自动选择（排在 Codex、Claude 之后，因为它们还有曲线）。

## 4. 主要文件

- `CodexBarWidgetShared/Base.lproj/WidgetStatus.intentdefinition`：`SelectQuotaPaceWidget` 加参数 `quotaWindow`（tag 3，类型 `QuotaPaceWindowOption`，父参数 `provider` / `HasAnyValue`，动态选项），`INIntentLastParameterTag` 2 → 3；四个 `WidgetStatus.strings` 加 `CBPacequotaWindow`、`CBPaceQuotaWindowType`（额度窗口 / 額度區間 / 表示するクォータ）。
- `CodexBarMobileWidgetOptions/IntentHandler.swift`：`provideQuotaWindowOptionsCollection`、`defaultQuotaWindow`；`Localizable.xcstrings` 加“Default (Weekly)”四语言。
- `CodexBarWidgetShared/WidgetProviderCatalogue.swift`：`WidgetProviderWindowRecord`、`QuotaPaceWindowChoice`（identifier 编解码、选项生成）、按服务商合并窗口。
- `CodexBarWidgetShared/QuotaPaceWindowSelection.swift`：窗口列表、默认窗口、catalogue 标题。
- `CodexBarWidgetShared/ProviderWindowLabel.swift`：从 `Views/V045ProviderCards.swift` 挪过来。
- `CodexBarWidgetShared/CodexBarWidgetSnapshot.swift`、`WidgetProviderSelection.swift`、`CodexBarWidgetView.swift`、`StatusWidgetConfigurationAdapter.swift`、`CodexBarWidgetEntry.swift`，`CodexBarMobileWidgets/*Timeline.swift`：窗口选择从意图传到渲染。窗口选择放在 `CodexBarWidgetEntry.paceWindowChoice`，不加到旧的 App Intent 里，免得改它的存储结构。
- `CodexBarMobile/Models/WidgetActivityPublisher.swift`：catalogue 带上窗口。

## 5. 测试

- 新增 `QuotaPaceWindowPickerTests`（Swift Testing，16 项）：
  - 选项：Claude 三个窗口（id、英文标题、简繁日标题、时长副标题）；Codex、muse.ai 只有默认；Antigravity 多个窗口按卡片顺序、排除用量未知的窗口；标题重复时加时长；没选服务商、未知服务商、旧 catalogue 只有默认；多账号合并窗口并能写读 catalogue。
  - 默认：Claude、Codex 用每周，配速与详情页 `QuotaPace(provider:)` 相同；Antigravity 用第一个每周窗口；只有月度窗口时沿用原来的配速窗口；只有短窗口时默认不显示、不参与自动选择，但手动选了能显示剩余。
  - 选择：Claude 选当前周期（剩余 80%、无配速、当前周期曲线）、选仅 Fable（剩余 30%、配速与按该窗口计算的 `QuotaPace` 相同、无曲线）；从合并快照到 `WidgetProviderSelection.pace` 的完整路径；窗口消失、属于别的服务商、选“默认”、自动选服务商时都回到每周；选的窗口没有用量时显示不可用。
  - 兼容：identifier 只对本服务商生效；没有 `quotaWindow` 的旧意图、选“默认”的意图都返回 nil；旧格式的配速数据能解码；占位数据带 Claude 三个窗口。
- `QuotaPaceWidgetTests` 一项改写：只有短窗口时，原来断言“没有数据”，现在断言“默认不显示、不参与自动选择”（窗口仍可手动选）。
- 渲染矩阵新增 `testQuotaPaceChosenWindowsRenderAcrossFamilies`：Claude 选当前周期、选仅 Fable，四种尺寸 × 浅色 / 深色 / tinted × 单色 / 彩色，全部可见；彩色和 tinted 的图片作为附件保存。
- 全量 iOS 单测、i18n 审计结果见第 6 节。

## 6. 验证记录

日志和截图都在 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/widget-window/`（模拟器 iPhone 17 Pro `E1DD6B03`，系统语言简体中文）。

- **全量 iOS 单测**（`-only-testing:CodexBarMobileTests`）：Swift Testing 1018 项（63 个 suite）+ XCTest 59 项全部通过；提交后在 HEAD 上再跑一次结果相同。`full1.log`、`full2.log`（及对应 `.xcresult`）。
- **小组件相关单测再跑**（窗口选择、Quota pace、小组件配置、服务商选择、WidgetSnapshotBuilder、渲染矩阵）：Swift Testing 58 项 + XCTest 19 项通过。`focused3.log`、`focused3.xcresult`；渲染图附件见 `focused2.xcresult`（导出到 `attach2/`）。
- **i18n 审计**：`Scripts/lint.sh lint-macos`（含 xcstrings 审计）通过，两个 xcstrings 全部翻译、406 个源 key 都在目录里。`lint-macos.log`。`Scripts/lint.sh lint` 在 portable checks 的 `test_swift_test_process_cleanup.py` 上失败（`fixture must exit before drain begins`，计时类断言，机器 load average 约 530；本次没有改 `Scripts/`），所以 xcstrings 审计用 `lint-macos` 跑。swiftlint 本机未安装，且仓库 swiftlint/swiftformat 范围只有 `Sources`、`Tests`；新文件单独用 swiftformat 检查过。
- **SpringBoard（新添加的小组件）**：App Group 里写入测试用 catalogue（Claude 三个窗口、Codex 一个、Antigravity 四个），小组件扩展在模拟器里用内置的模拟数据。
  - 添加中尺寸“额度消耗趋势”，编辑面板依次是颜色样式、服务商、**额度窗口**（`sb-config-default.png`）。
  - 服务商未选择时，额度窗口只有“默认（每周）”。
  - 选 Claude：默认（每周）、当前周期 · 5小时、每周 · 7天、仅 Fable · 7天（`sb-claude-window-options.png`）。
  - 选 Codex：只有“默认（每周）”（`sb-codex-window-options.png`）。
  - 选 Antigravity：默认（每周）、Gemini · 每周、Gemini · 5 小时、Claude/GPT · 每周、Gemini 3 Pro Image（`sb-antigravity-window-options.png`）。
  - Claude + 仅 Fable 后，小组件显示“29% 仅 Fable · 剩余”、“用量比均匀进度高 22 个百分点”、预计用尽时间和进度条（`sb-widget-claude-fable.png`）。
  - 把服务商改成 Codex、窗口仍留着“仅 Fable”时，小组件显示 Codex 的“61% 每周 · 剩余”和曲线，即回到默认每周（`sb-config-codex-stale-fable.png`、`sb-widget-codex-stale.png`）。
- 没有做：在旧版本上添加小组件再覆盖安装新版本的升级实测（依据 065 的同类实测）；真机验证。

## 7. 限制与待办

- **已添加的小组件看不到新参数**，只能移除后重新添加（SiriKit 限制，Research/065）。这次没有做“旧版添加 → 新版覆盖安装”的升级实测，依据是 065 对同一类改动的实测。
- **新添加的小组件里“额度窗口”初始显示“选取”**，不是“默认（每周）”（系统没有调用子参数的默认值）；行为上等同于默认。
- **单窗口服务商也会显示“额度窗口”这一行**，只有“默认（每周）”一个选项。SiriKit 的参数关系不能按动态数据隐藏。
- **选项列表依赖 App 刷新**：catalogue 由 App 写，Mac 新增的窗口要等 App 下次同步刷新后才出现在编辑面板。
- **标题语言**：catalogue 里预先存了英文、简体、繁体、日文四种标题；系统语言是其他语言时显示英文。
- **配速只对至少一天的窗口**（和 App 一致）；当前周期（5 小时）只显示剩余和曲线。
- **曲线只有 Codex、Claude 的原生窗口**；仅 Fable、Antigravity 等附加窗口没有观测历史，只显示进度条。
- 真机验收和升级路径实测待做。
