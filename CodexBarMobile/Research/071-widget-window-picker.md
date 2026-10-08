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

- **来源**：所选服务商最近一次同步的窗口里，用量已知的窗口（`usageKnown`），按卡片顺序（原生槽位在前，附加窗口在后）。没有 id 的旧 Mac 数据保留它原来的槽位名：只有 `primary` / `secondary` 字段时按字段名，`rateWindows` 里按位置叫 `primary` / `secondary` / `tertiary` / `window-N`。同一服务商多个账号的窗口取并集。
- **什么时候列出窗口**：有两个及以上窗口时全部列出；只有一个窗口时，**默认到不了它才列出**（App 写 catalogue 时一并写入当时的默认窗口 `defaultWindowID`）。Codex、muse.ai 的单个每周窗口就是默认，只给“默认（每周）”；单个 5 小时窗口、没有时长的窗口，或 Claude 只剩一个 Sonnet / 仅 Fable 额度（没有 session 也没有账号每周）时会列出来，只能手动选。
- **标题**：和 App 的服务商卡片同一套 `ProviderWindowLabel`（从 App target 挪到 `CodexBarWidgetShared`，App 和小组件共用），普通槽位名（Session、Weekly）再走一次和小组件曲线标签相同的 `ProviderDetailLocalization`。没有 label 的窗口和卡片用同一套兜底名：第 1 个叫“当前周期”、第 2 个叫“每周”、之后叫“限额 N”；Aixy 叫“预算 / 次级预算”，xkiro 第 1 个叫“每日免费 Token”。所以编辑面板里没有 label 的 muse.ai 每周窗口和卡片一样叫“当前周期”。**这个卡片兜底名只用于编辑面板**；小组件主数字旁显示窗口名时，没有 label 但时长 10080 分钟（或 period 为每周）的窗口一律叫“每周”，不会出现和时长矛盾的名字。四种语言的标题由 App 写进 catalogue，Intents 扩展按自己的首选语言取。
- **时长**：每个选项的副标题是窗口时长（例如“7 天”“5 小时”），用系统的 `DateComponentsFormatter` 本地化。两个选项标题相同时，标题后面再加时长区分。
- 例子：
  - Claude：默认（每周）、当前周期、每周、仅 Fable。
  - Codex（只有每周）、muse.ai：只有默认（每周）。
  - Antigravity：默认（每周）、Gemini · 每周、Gemini · 5 小时、Claude/GPT · 每周……（每个已知用量的窗口一项）。

### 2.5 CodexBar 小组件概览模式要不要同步

概览模式每个服务商只显示一个数字（用得最多的窗口），最多四个服务商。要按服务商选窗口，需要再加四个参数，而且已添加的小组件同样看不到。用户说这次只改一个小组件，所以**不改**，以后有需要再单独评估。

## 3. 设计

### 3.1 默认窗口与自动选择

**两套规则**（2026-10-08 本地 review 后的取舍，方案 a）：

- **自动选择服务商**（服务商为“未选择”，包括所有升级前添加、没选服务商的小组件）：完全保持 Research/065。数据、排序、门槛都不变：门槛仍是 `QuotaPace(provider:) != nil` 或有曲线（`isAutomaticCandidate`），显示的仍是 065 的配速窗口或曲线车道。只有附加窗口里才有每周额度的服务商（Antigravity）不会因为“默认每周”拿到新配速，也就不会因此参与自动排序。
- **手动选定服务商**（包括升级前添加、已选服务商的小组件）：按所选窗口；没选时按下面的默认窗口。

**默认窗口**（`QuotaPaceWindowSelection.defaultWindowID(for:now:)`，只考虑用量已知、还没重置的窗口）：

1. 原来的配速窗口（`QuotaPace.window(for:)`）是每周的、且不是 Claude 的模型限定额度，就用它。Codex、Claude 都在这一步，和以前一样。
2. 否则按 Mac 端每周切换器的规则（`UsageSnapshot+SwitcherWeeklyWindow` 的 `mostConstrainedSwitcherWeeklyWindow`）：所有时长 7 天的窗口里取**用得最多的那个**（最受限）；Claude 排除 tertiary（Sonnet/Opus 每周）、`claude-weekly-scoped-*`（仅 Fable 等）和 `claude-routines`。Antigravity 有 `antigravity-quota-summary-*` 桶时只在这组里取最受限的（与 `AntigravityProviderDescriptor.mostConstrained` 一致，平局取 id 较小的），没有时才看模型行；MiniMax 类（secondary 是 Today、tertiary 是每周）取 tertiary 的每周，和以前显示 Today 不同，这是用户要的“默认每周”。
3. 否则沿用 Research/065：原来的配速窗口有配速、且不是 Claude 的模型限定额度时用它（例如只有月度窗口的服务商）。
4. 都没有：跟随有曲线的账号窗口（每周，其次当前周期）；再没有就显示“暂无配速数据”。不会落到 Claude 的 Sonnet/Opus 曲线上。

**选择失效时静默回退**：用户没选、选了“默认”、选项属于别的服务商（换了服务商）、选的窗口已经不在数据里，都直接按上面的默认显示，小组件上不提示“原选择已失效”。窗口名会显示在主数字旁边（见 3.3），用户能看出现在跟的是哪个窗口。

**多账号**：选了窗口时，只在有这个窗口的账号里挑；没有账号有这个窗口时，所有账号都按默认窗口再挑。挑的时候“有配速”优先，其次“所跟窗口自己有曲线”（没有曲线的窗口不再因为别的曲线加分）。

### 3.2 小组件数据

- `CodexBarWidgetPaceSummary` 新增 `windows`（每个窗口的 id、label、period、时长、配速、剩余、重置时间、对应的曲线车道、在卡片里的位置）、`windowID`（当前描述的窗口）、`windowSource`（`automatic` / `defaultWindow` / `chosen`）、`automaticWindowID`、`defaultWindowID`。刚建出来的数据是 065 的自动数据；`configured(windowID:)` 返回手动选定服务商时要显示的数据。`pace` / `paceRemainingPercent` / `paceResetsAt` 始终表示当前描述的窗口。
- 跟随某个窗口时（`defaultWindow` / `chosen`），`primaryLane` 只取这个窗口自己的曲线，没有就是 nil，保证标签、数字、曲线是同一个窗口。
- 配速仍用 `QuotaPace(window:capturedAt:referenceDate:providerID:)`，按 Mac 观测时间算，和详情页同一个公式；不到一天的窗口（5 小时当前周期）不出配速，和 App 一致。OpenCodeGo 估算用量不出配速的规则抽成 `QuotaPace.allowsPace(for:)`，自动数据和每个窗口共用。
- 曲线只有 Codex、Claude 的原生槽位有观测历史（`MobileQuotaBurndown.resolvedLanes`），窗口和车道按同一个 `SyncRateWindow` 对应。
- 自动选择服务商时不看窗口选择，见 3.1。
- 解码兼容：新字段都用 `decodeIfPresent`，旧数据解码为空。

### 3.3 显示

- 小：选了窗口、或默认窗口和以前显示的窗口不同时，主数字后面写窗口名（“29% 仅 Fable · 剩余”）；默认窗口和以前相同时保持原样。
- 中：主数字后的标签和小、大尺寸同一规则（`heroLabel`）：需要点名窗口时（`namesWindow`）用窗口在小组件里的名字，否则用所画曲线的名字，没有曲线就不加；它有曲线就画曲线，没有曲线（仅 Fable、Antigravity）就在右栏画剩余进度条，并且不再显示当前周期那一行，免得进度条被看成当前周期的。
- 大：所选窗口有曲线时，显示包含它的前两条曲线（当前周期和每周）；没有曲线时显示主数字和进度条。
- 超大：两列，每列只画所选窗口的曲线。
- 重置时间：不到一天的窗口改成按小时（“2.4小时”，不到 0.1 小时显示“<0.1小时”），新增文案 `%@h`、`<0.1h` 四语言。

### 3.4 兼容性

| 情况 | 行为 |
| --- | --- |
| 237 之前添加、没选服务商的小组件 | 自动选择，和以前完全一样 |
| 237 之前添加、选了服务商的小组件 | 编辑面板没有“额度窗口”参数（配置结构存死），按 3.1 的默认窗口。**正常数据下**（账号每周窗口有用量、未重置）Codex、Claude 和以前一样；MiniMax 类改为每周、Antigravity 改为最受限的每周桶。每周窗口用量未知、被卡住（blocked）或已过期时有变化：以前按 065 跟配速窗口顺序或曲线回退，可能显示 Claude 的 Sonnet/Opus 每周（tertiary）或它的曲线；现在跳过这些模型限定额度，改跟有曲线的账号窗口（每周，其次当前周期），都没有就显示“暂无配速数据”。被卡住的每周窗口仍有剩余百分比时照常跟随它（无配速） |
| 旧 catalogue（App 还没在新版本里刷新过） | 服务商只给“默认（每周）” |
| 新窗口出现（例如 Antigravity 新桶） | App 下次同步刷新后写入 catalogue，编辑面板才有 |
| 改了服务商 | 原窗口选项不属于新服务商（系统不会清空它），静默走默认 |
| 窗口消失 | 静默走默认 |
| catalogue 读不出来 | 编辑面板仍给“默认（每周）” |
| 选的窗口暂时没有用量 | 显示服务商名和“暂无配速数据”（和服务商不可用时一样） |

**行为变化**：只发生在手动选定服务商的小组件上（见 3.1）：附加窗口里才有每周额度的服务商（Antigravity）现在显示最受限的每周桶和配速；MiniMax 类从 Today 改为每周。自动选择不变。

## 4. 主要文件

- `CodexBarWidgetShared/Base.lproj/WidgetStatus.intentdefinition`：`SelectQuotaPaceWidget` 加参数 `quotaWindow`（tag 3，类型 `QuotaPaceWindowOption`，父参数 `provider` / `HasAnyValue`，动态选项），`INIntentLastParameterTag` 2 → 3；四个 `WidgetStatus.strings` 加 `CBPacequotaWindow`、`CBPaceQuotaWindowType`（额度窗口 / 額度時段 / 表示するクォータ）。
- `CodexBarMobileWidgetOptions/IntentHandler.swift`：`provideQuotaWindowOptionsCollection`、`defaultQuotaWindow`；`Localizable.xcstrings` 加“Default (Weekly)”四语言。
- `CodexBarWidgetShared/WidgetProviderCatalogue.swift`：`WidgetProviderWindowRecord`、`QuotaPaceWindowChoice`（identifier 编解码、选项生成）、按服务商合并窗口。
- `CodexBarWidgetShared/QuotaPaceWindowSelection.swift`：窗口列表、默认窗口、catalogue 标题。
- `CodexBarWidgetShared/ProviderWindowLabel.swift`：从 `Views/V045ProviderCards.swift` 挪过来。
- `CodexBarWidgetShared/CodexBarWidgetSnapshot.swift`、`WidgetProviderSelection.swift`、`CodexBarWidgetView.swift`、`StatusWidgetConfigurationAdapter.swift`、`CodexBarWidgetEntry.swift`，`CodexBarMobileWidgets/*Timeline.swift`：窗口选择从意图传到渲染。窗口选择放在 `CodexBarWidgetEntry.paceWindowChoice`，不加到旧的 App Intent 里，免得改它的存储结构。
- `CodexBarMobile/Models/WidgetActivityPublisher.swift`：catalogue 带上窗口。

## 5. 测试

- 新增 `QuotaPaceWindowPickerTests`（Swift Testing）：
  - 选项：Claude 三个窗口（id、英文标题、简繁日标题、时长副标题）；Codex、muse.ai 只有默认；只有一个短窗口或没有时长的窗口时会列出，并且经过 `options()` 选出的选项能让小组件显示它（端到端）；Antigravity 多个窗口按卡片顺序、排除用量未知的窗口；没有 label 的窗口和卡片同名（当前周期 / 每周 / 限额 3，Aixy 预算）；旧数据只有 `secondary` 时仍叫 `secondary`；标题重复时加时长；没选服务商、未知服务商、旧 catalogue 只有默认；多账号合并窗口；catalogue 没变时不重写文件。
  - 默认：手动选定 Claude、Codex 时是每周，配速与详情页 `QuotaPace(provider:)` 相同；Antigravity 是最受限的每周桶；Claude 的每周过期、Sonnet/仅 Fable 仍有效时不选它们，也不画 Sonnet 曲线，改跟当前周期；Claude 每周不存在时同样；`claude-routines` 被排除，普通附加每周窗口可以；默认窗口没有曲线时不借别的曲线；只有月度窗口时沿用原来的配速窗口；只有短窗口时默认不显示，手动选了能显示剩余。
  - 自动选择：Codex、Claude、MiniMax 类逐个对比，自动数据和 065 的算法完全相同；MiniMax 类手动选定后改为每周；Antigravity 不会因附加每周窗口进入自动选择，只有曲线的 Claude 仍被选中，手动选定 Antigravity 时才显示每周配速。
  - 多账号：两个 Claude 账号，只有 A 有仅 Fable（B 有曲线、默认排名更高），选仅 Fable 时两种顺序都选 A，且不给曲线加分；选了一个谁都没有的窗口时回到默认每周。
  - 选择：Claude 选当前周期（剩余 80%、无配速、当前周期曲线）、选仅 Fable（剩余 30%、配速与按该窗口计算的 `QuotaPace` 相同、无曲线）；从合并快照到 `WidgetProviderSelection.pace` 的完整路径；窗口消失、属于别的服务商、选“默认”时回到每周；自动选服务商时忽略窗口选择；选的窗口没有用量时显示不可用。
  - 兼容：identifier 只对本服务商生效；没有 `quotaWindow` 的旧意图、选“默认”的意图都返回 nil；旧格式的配速数据能解码；占位数据带 Claude 三个窗口。
- `QuotaPaceWidgetTests` 一项改写：只有短窗口时，原来断言“没有数据”，现在断言“默认不显示、不参与自动选择”，手动选择由上面的端到端测试覆盖。
- 渲染矩阵新增 `testQuotaPaceChosenWindowsRenderAcrossFamilies`：Claude 选当前周期、选仅 Fable，四种尺寸 × 浅色 / 深色 / tinted × 单色 / 彩色，全部可见；彩色和 tinted 的图片作为附件保存。
- 全量 iOS 单测、i18n 审计结果见第 6 节。

## 6. 验证记录

日志和截图都在 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/widget-window/`（模拟器 iPhone 17 Pro `E1DD6B03`，系统语言简体中文）。

- **全量 iOS 单测**（`-only-testing:CodexBarMobileTests`）：Swift Testing 1018 项（63 个 suite）+ XCTest 59 项全部通过；提交后在 HEAD 上再跑一次结果相同。`full1.log`、`full2.log`（及对应 `.xcresult`）。
- **小组件相关单测再跑**（窗口选择、Quota pace、小组件配置、服务商选择、WidgetSnapshotBuilder、渲染矩阵）：Swift Testing 58 项 + XCTest 19 项通过。`focused3.log`、`focused3.xcresult`；渲染图附件见 `focused2.xcresult`（导出到 `attach2/`）。
- **本地 review 修复后**（提交 `d699e6b10`）：全量 iOS 单测 Swift Testing 1025 项 + XCTest 59 项通过（`fix-full1.log`）；小组件相关（窗口选择 23 项、Quota pace、小组件配置、服务商选择、WidgetSnapshotBuilder、配速文案、渲染矩阵）77 + 19 项通过（`fix-focused2.log`）；`lint-macos` 的 i18n 审计通过（`fix-lint-macos.log`）。SpringBoard 截图是修复前的，选项列表和 Claude 仅 Fable 的显示不受这次修复影响，没有重拍。
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
