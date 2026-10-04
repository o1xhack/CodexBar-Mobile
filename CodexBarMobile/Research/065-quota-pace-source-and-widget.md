# 065 — Quota pace 数据来源与小组件可行性

状态：done（已实现并验证，见第 5–7 节；PR #174 于 2026-10-03 合并到 `mobile-dev`，merge commit `4652e3cc5`，Final CI 通过；TestFlight 2.5.0 (233) 已上传；233 真机反馈后改成独立小组件，见第 8 节）
日期：2026-10-03
相关：iOS 2.4.0 新增的 Quota pace（配额走势图）和 Codex 配速条；Research/064（2.5.0）

## 1. 现在的数据是从哪来的

Provider 详情页里和“配速”有关的内容有两块，数据来源不一样：

| 界面 | 数据来源 | iOS 本地做了什么 |
| --- | --- | --- |
| **Quota pace 走势图**（Codex、Claude 的 Session / Weekly） | 实线上的点：Mac 每次刷新时记录的观测值（`utilizationHistory`），加上当前窗口的已用百分比 | 在本地把同一个重置周期内的观测值整理成曲线（`MobileQuotaBurndown`），用窗口开始时间到重置时间画出平均消耗参考线（虚线），然后渲染 |
| **Codex 顶部配速条**（例如“低于平均配速 3 个百分点 · 预计可撑到重置”） | “差多少个百分点”是 Mac 算好同步过来的（`SyncCodexWorkspaceContext.weeklyPaceDelta`） | “预计可撑到重置 / 预计在某时耗尽”由 iOS 本地按同一个周窗口算（`CodexPacePresentation`），文案也在 iOS 本地按手机语言生成 |

补充：

- **Mac 的算法**：`SyncCoordinator.buildCodexWorkspaceContext` 调用 `UsagePace.weekly(window:)`，是**线性配速**：差值 = 已用百分比 − 按时间流逝比例应用掉的百分比，单位是百分点，然后除以 100 同步。`Shared/Models/V027Snapshots.swift` 注释里写的“actual / linearPace − 1”和实际实现不符，后续顺手改掉注释。
- **只有 Codex 有配速条**：Mac 只对 Codex 生成 `codexWorkspace`。Claude 有同样的周窗口和观测数据，但 iOS 没有拿到差值，所以 Claude 只有走势图，没有配速条（对照截图：Claude 页没有那一行）。
- **只有 Codex 和 Claude 有走势图**：`historySeriesName` 只识别这两家。其他 provider 没有对应的观测序列。

## 2. 改成在 iPhone 本地计算，会不会更准、更新、更好

**更新：不会。**

iPhone 拿不到任何 provider 的用量。用量都是 Mac 通过 CLI、Cookie、OAuth 去抓的，iOS 只能看到 Mac 最后一次同步的数字。配速只能算到“Mac 最后一次观测的那个时刻”。如果拿手机当前时间去算，会出错：时间在走，用量却停在上次同步的值，结果会越来越显示“低于平均”，这是假象。现有的预估（`CodexPacePresentation.forecast`）就是故意用 Mac 的观测时间 `updatedAt` 来算的。

**更准：公式相同，结果也相同。但有一个口径差异值得注意：**

- Mac 菜单栏和菜单卡片上的 Codex 配速，可能用的是“历史学习配速”（`CodexHistoricalPaceEvaluator`，需要开启 historical tracking），或者用户设置的工作日配速（`weeklyProgressWorkDays`）。
- 同步给 iOS 的却始终是**线性配速**。所以同一时刻，Mac 菜单和 iPhone 上显示的差值可能对不上。
- iOS 本地再算一遍线性配速，解决不了这个差异。想要两边一致，只能让 Mac 把它实际采用的配速（包括算法类型）同步过来，这需要改 Mac 端和 `Shared` 的数据格式。

**更好：在“覆盖面”和“一致性”上有实际好处：**

1. **Claude 和其他有周窗口的 provider 也能有配速条**，不用等 Mac 新增字段，旧版 Mac 也能用。数据（已用百分比、重置时间、窗口时长、观测时间）iPhone 本来就有。
2. 配速条、走势图、预估全部用同一套本地数据和同一个观测时间算，不会出现“配速条按 Mac 当时的时间算、走势图按快照时间画”这种细微不一致。
3. 不再依赖 Mac 那段已经和实现不符的注释和字段。

**建议：**

- 在 iOS 本地按“Mac 观测时间”计算线性配速，覆盖所有有周窗口（`windowMinutes ≥ 1440`）且观测可信的 provider。Codex 先继续优先用 Mac 同步的值，以免和旧行为不同；没有这个值时再用本地计算的结果。
- 是否要和 Mac 菜单的“历史/工作日配速”保持一致，另开一项：Mac 端同步“配速算法类型和结果”，属于 Mac + iOS 的发版改动，不放进这次。
- 这部分改动小，可以放进 2.5.0；如果想控制范围，也可以放到下一版。

## 3. 能不能做成小组件

**可以做**，技术上没有障碍：

- **数据**：小组件扩展已经直接从 CloudKit 读同步数据，并用和 App 同一个合并器 `ProviderSnapshotMerger` 合并，合并结果里保留了 `utilizationHistory`。小组件能拿到和详情页一样的观测点。
- **代码**：`MobileQuotaBurndown`、`CodexPacePresentation` 现在在 App target 里，需要移到 `CodexBarWidgetShared`，让 App 和小组件共用。按“所有展示同步数据的地方共用同一个 reducer”的规则，不在小组件里另写一份。
- **绘图**：小组件里可以用 Swift Charts。曲线点数要做抽稀：一周的观测可能有几百个点，小组件内存和渲染时间有限，建议每条线最多保留约 60 个点，保留拐点和最新点。
- **刷新**：小组件不能自己去拉数据。现有机制是 App 收到 CloudKit 推送后 `reloadTimelines`，再加上系统的刷新预算。走势图里只有“平均消耗参考线上，现在走到哪了”会随时间变化，可以在 timeline 里预先排好每 30 分钟一条的 entry，让参考点自己往前走。观测数据只在 Mac 同步后更新，过期时沿用现有的过期提示（6 小时，`staleInterval`）。
- **范围**：只有 Codex 和 Claude 有观测序列，所以小组件里的走势图只对这两家开放。其他 provider 如果采用第 2 节的本地配速，可以只显示配速条，不显示曲线。

### 3.1 设计原则（和现有小组件保持一致）

- 作为现有可配置小组件里的**新模式**“配速 Quota Pace”，不新增小组件种类。沿用现有的 provider 选择和 Mono / Colorful 颜色参数。
- 间距全部复用 `CodexBarWidgetSpacing`：
  - small：padding 10，header 6，section 8，row 6
  - medium：padding 14，header 7，section 10，row 7
  - large：padding 17，header 8，section 12，row 7
  - 头部（provider 标识 + 名称 + 更新时间）和其他模式用同一个组件。
- 按 native widget 的要求做：
  - 主数字层级要强；Mono 下只用系统黑白，Colorful 下只给曲线和关键数字上色。
  - 不用渐变、不堆卡片；支持 tinted 主屏（`widgetAccentable` 用在曲线上）。
  - Light / Dark 都要验证。
- 文案四种语言，沿用 App 里已有的 key（“低于平均配速 %lld 个百分点”“预计可撑到重置”“预计在 %@ 耗尽”）。

### 3.2 各尺寸方案（草图）

**Small（单个 provider，只显示周窗口）**

```
┌────────────────────┐
│ ● Codex     2 分钟前 │  header
│ 剩余 61%            │  hero 数字（周窗口剩余）
│ 低于平均 3 个百分点   │  配速一句话（颜色表示快/慢）
│ ╲__  ⋯⋯⋯            │  迷你曲线 + 虚线参考线，不画坐标轴
│ 5 天后重置           │
└────────────────────┘
```

- small 放不下两条曲线，只显示 Weekly。没有周窗口时显示 Session。
- 预估文字（“预计可撑到重置”）放不下，用配速一句话代替；点击进入 App 详情页。

**Medium（单个 provider，Session + Weekly）**

```
┌───────────────────────────────────────────┐
│ ● Claude                         2 分钟前  │
│ 每周 剩余 46%        ┌──────────────────┐  │
│ 高于平均 4 个百分点    │ 周曲线 + 虚线      │  │
│ 预计 10/5 14:00 耗尽  │                  │  │
│ Session 剩余 83%      └──────────────────┘  │
│ 3 小时后重置                                │
└───────────────────────────────────────────┘
```

- 左栏是数字和结论，右栏放周曲线（带 0/50/100% 三条淡网格线，不显示坐标文字）。
- Session 只显示数字，不画曲线，避免两张小图挤在一起。

**Large（单个 provider 的完整版，或两个 provider 对比）**

方案 A（单个 provider，推荐）：

```
┌───────────────────────────────────────────┐
│ ● Codex                          2 分钟前  │
│ 低于平均 3 个百分点 · 预计可撑到重置           │  配速条
│ Session  剩余 98%                          │
│ ─曲线──────────────────────── ⋯虚线        │  Session 曲线
│ Weekly   剩余 61%                          │
│ ─曲线──────────────────────── ⋯虚线        │  Weekly 曲线
│ 最近观测 10/3 20:15 · 5 天后重置             │
└───────────────────────────────────────────┘
```

方案 B（Codex 和 Claude 上下对比，各一条周曲线）：适合同时用两家的人。

- large 建议先做方案 A，方案 B 作为第二个 provider 的可选项。是否需要 B，请你决定。

**Extra large（iPad）**：沿用现有做法，左右两栏，即两个 provider 并排的方案 A。

### 3.3 验收要求（实现时）

- 共用的 reducer 和抽稀要有单元测试，覆盖：周期重置后丢弃旧点、观测时间晚于“现在”、没有观测序列、窗口被 block。
- 渲染矩阵：
  - small / medium / large / extra large
  - Light / Dark / tinted
  - Mono / Colorful
  - 四种语言
  - 有数据 / 没有观测序列 / 数据过期 / 错误
- 必须在真实 SpringBoard 上添加小组件、切到“配速”模式并截图，按 `docs/` 和 Research/036 的小组件验收流程走。
- Widget Setting 预览页要加入新模式，复用同一个 shared view。

## 4. 用户决定（2026-10-03）

1. **配速条全部改为 iPhone 本地计算，包括 Codex**，放进 2.5.0：
   - 按 Mac 观测时间（快照 `lastUpdated`）计算线性配速，覆盖所有有 ≥1 天窗口的 provider。
   - 不再读 `codexWorkspace.weeklyPaceDelta`，公式和 Mac 同步值一致。
2. **不同步 Mac 的“历史 / 工作日配速”**：用户没有开启或不确定是否开启，以后 Mac 和 iOS 一起发版时再评估。
3. **配速小组件放进 2.5.0**：在现有小组件里新增“配速”模式，small / medium / large（方案 A：单个 provider 完整版）/ extra large 都做。

## 5. 实现（分支 `feature/ios-250-quota-pace`）

- **共享模型**（`CodexBarWidgetShared/`，App 和小组件共用）：
  - `QuotaPace.swift`：替代原来的 `CodexPacePresentation`。按 Mac 观测时间（快照的 `lastUpdated`）计算线性配速，公式和 Mac 的 `UsagePace.weekly` 一致。
    - 窗口选择沿用原来的偏好顺序：先 secondary，再 tertiary、primary，最后取剩下的、时长至少一天的窗口。
    - 窗口被 block、没有已知用量、时长不到一天、已经重置、观测时间晚于“现在”，或者新窗口刚开始就已有用量，这些情况都不出配速。
  - `MobileQuotaBurndown.swift`、`QuotaResetDateText.swift`、`MobileLocalizedString.swift` 从 App target 移过来。新增 `resolvedLanes(for:referenceDate:)`，详情页的走势图和小组件共用这一个入口；新增 `downsample`，每条线最多 60 个点。
- **详情页**：`ProviderPaceBadge` 替代 `CodexWorkspaceBadge`，配速条对所有 provider 显示，Codex 另外显示工作区名称。说明弹窗的标题改为不限于“每周”的“Pace estimate / 用量配速估算”。
- **小组件**：
  - `CodexBarWidgetProviderSummary.quotaPace`：`CodexBarWidgetPaceSummary`，包含配速、剩余百分比、重置时间和抽样后的走势线。
  - 新模式 `quotaPace`，在 `WidgetStatus.intentdefinition` 里加了枚举值和四语言文案。显示名沿用 App 里已有的译法：额度消耗趋势 / 額度消耗趨勢 / クォータ消費の推移。
  - 意图定义里，一个参数只能对应模式的一个取值显示，所以新增了独立的单选参数 `paceProvider`，只在配速模式下显示，选项来自同一份 provider 列表。
  - 自动选择的顺序：先选有走势线的（Codex、Claude），再按剩余额度从少到多。
  - 四个尺寸：
    - small：剩余百分比，加配速一句话和迷你曲线。
    - medium：左边是剩余百分比、配速、预估和当前周期的剩余；右边是周曲线。
    - large（方案 A）：配速加预估，下面是当前周期和每周两条曲线。
    - extra large：两个 provider 并排，每个只画周曲线。
  - 单色模式下实线用主文字色，彩色模式下用 provider 自己的颜色。曲线带 `widgetAccentable`，适配 tinted 主屏。
  - App 的“小组件设置”预览页加入了新模式。
- 版本 2.5.0 (233)，CHANGELOG 和四语言更新说明已更新。

## 6. 验证

- **单元测试**：
  - `ResetAndPacePresentationTests` 改写为 `QuotaPace`，覆盖：公式和 Mac 一致、四种语言、预估、1.5 倍余量阈值、各种无效窗口、Codex 和 Claude 都不依赖 Mac 字段、观测时间锚定。
  - 新增 `QuotaPaceWidgetTests`，覆盖：小组件数据提取、抽样、自动和手动选择 provider、占位数据。
  - `StatusWidgetConfigurationTests` 新增“配速模式只读取自己的参数”。
- **渲染矩阵**：`CodexBarWidgetRenderMatrixTests` 的模式里加入配速，覆盖 4 种尺寸 × 浅色 / 深色 / tinted × 单色 / 彩色，还有空状态。所有渲染图都作为附件保存，供人工检查。
- **真实 SpringBoard**（模拟器 iPhone 18 Pro，iOS 27）：
  - 添加 CodexBar 小组件，在“编辑小组件”里能看到并选中“额度消耗趋势”。选中后配置面板只剩一个“服务商”参数。
  - 中尺寸（浅色）、大尺寸（深色）、小尺寸（深色）在主屏上渲染正常。
- **App**：演示数据下，Claude 和 ChatGPT 的详情页都出现了配速条，Claude 显示“低于平均配速 27 个百分点”，和手算结果一致。
- **截图**：`065-quota-pace-screenshots/`。

## 7. 本地审查与已知局限

子智能体做了 3 轮对抗式审查，最终结论是没有遗留缺陷。主要修正如下：

- **窗口选择和 Mac 对齐**：Mac 先写原生槽位，再写额外的具名窗口。因此排在最后一个标准槽位 id（secondary / tertiary / primary）之前的窗口都算原生，包括保留了自定义 id 的原生槽位（例如 Aixy 预算）；选择顺序是 secondary → tertiary → primary，然后是自定义 id 的原生窗口。之后的额外窗口（Codex Spark、Claude 模型窗口）不参与配速。窗口带 id 但一个标准 id 都没有的 payload，只有额外窗口（例如 Kimi 只剩月度和 Code 周窗口），不出配速；只有完全不带 id 的旧 Mac payload 才退回原来的 secondary / primary 字段。Aixy 在 Mac 上本来就不出配速，所以只带自定义 id 的 Aixy payload 不出配速，和 Mac 一致。
- **月度窗口时长按 Mac 各 provider 的规则**：
  - alibaba、alibabatokenplan、commandcode、doubao、mimo、notion、ollama、opencodego、stepfun：30 天占位值换算成以重置时间结尾的 UTC 日历月。
  - Zai：只换算 MCP 那个窗口。
  - Copilot：只在窗口没有时长时，按日历月推算。
  - 其他 provider（包括 Codex 的 30 天滚动窗口）：按原始时长。
- **窗口没有时长时**：对照 Mac 菜单的 `resetWindowPaceDetail` 全部规则核对过，只有两类 provider 会给没时长的窗口出配速：
  - Copilot：按日历月算。
  - Grok：网页额度没有时长时，离重置还剩 4–12 天就当作每周额度池，按 7 天算；剩 20–45 天是月度，不出配速；其他情况也不出。
  - 其他 provider 都必须自带时长。
- **OpenCodeGo** 在估算数据下不出配速，这是 Mac 唯一一个 `allowsEstimatedUsage: false` 的情况。
- **超过 100% 时**按 100% 算，预测为“现在已用完”；窗口还没开始走时，不给预测。
- **小组件**：
  - 没有配速时，剩余百分比改用走势线的最新值。
  - 自动选择时，有配速的排在只有走势线的前面。
  - 手动选的 provider 不可用时，显示它的名字和“暂无配速数据”，不再悄悄换成别的 provider；超大尺寸选了两个 provider、其中一个没有数据时，那一列也保留这个占位。
  - 车道标签和 App 用同一个 `ProviderDetailLocalization`（已移到共享目录）。
  - tinted 主屏下只给实线染色，虚线参考线和网格保持中性色。

**已知局限**：多台 Mac 合并时，Kimi 的额度窗口、Claude 从较旧 Mac 补进来的窗口，和 `lastUpdated` 可能不是同一台 Mac 的观测。误差约为两台 Mac 的同步时间差除以窗口时长（差 1 小时，周窗口约 0.6 个百分点）。Codex 不在这类合并逻辑里，不受影响。2.4 版的走势图用的也是同一个锚点。要彻底解决，需要在共享的同步数据里给每个窗口带上观测时间，这要改 `Shared/`，所以留到以后 Mac 和 iOS 一起发版时再做。

**已知局限 2（Codex 第 5 轮后的架构审视）**：Mac 是根据 `UsageSnapshot` 的原生槽位（primary/secondary/tertiary）和 `ProviderPaceCapability` 来选 pace 窗口的。同步数据里这两样都没有：`rateWindows` 不标记哪个是原生槽位、哪个是附加窗口，也不带每个服务商的 pace 规则。所以 iOS 只能靠 id、位置和服务商 id 去推断。这些规则现在都集中在 `QuotaPace.window(for:)` 和 `duration(of:providerID:capturedAt:)` 两处，每条服务商规则都有一个单测对应：Codex Spark / Claude 模型分项不算原生槽位，各服务商的自然月规则，Grok 不带时长的周额度池，没给时长的窗口按声明的 `period` 推算（Raycast 月度额度、没有开始时间的 Aixy 预算；Mac 端这两个服务商不显示 pace，iOS 按“全部本地算”的决定照样算），OpenCodeGo 的估算用量不算，Kimi 只有附加窗口时不出 pace，Aixy 原生槽位用自定义 id 时按位置识别。Mac 新增带自定义 id 的原生槽位或新的时长规则时，iOS 要跟着补。根本的解决办法是让 Mac 在同步数据里给每个窗口标出槽位类型（`native`/`extra`）和算好的 pace 时长，这同样要改 `Shared/`，所以和上面一样，留到 Mac 和 iOS 一起发版时再做。

## 8. 233 真机反馈后的调整（build 234）

**问题**：233 装到真机后，之前已经放在主屏上的 CodexBar 小组件（新版，不是旧版），在“编辑小组件”里看不到“额度消耗趋势”。

**模拟器复现**（iPhone 18 Pro，iOS 27）：装 232，添加 CodexBar 小组件，确认类型列表只有 4 项；覆盖安装 233，类型列表仍然是 4 项。重启模拟器、改一次颜色样式并保存，也还是 4 项。在 233 上新添加的小组件能看到新类型。反过来，用 233 开发版添加的小组件，装回 232 再重启，类型列表里仍然有 “Quota pace”。233 安装包里三个 bundle 的 `WidgetStatus.intentdefinition` 都已经包含 `quotaPace`。

**结论**：SiriKit `IntentConfiguration` 的小组件在添加的那一刻，就把当时的配置结构（枚举值和参数）存进这个小组件，之后不跟着 App 更新。所以给已有的小组件加新类型或新参数，老小组件都看不到，用户只能移除后重新添加。这个限制对以后所有 SiriKit 小组件的改动都适用。

**用户决定**：
1. “额度消耗趋势”拆成独立小组件，不再作为 CodexBar 小组件的一个类型。
2. 旧版小组件从小组件库隐藏。

**实现**：
- `WidgetStatus.intentdefinition`：`StatusWidgetMode` 去掉 `quotaPace`，`SelectStatusWidget` 去掉 `paceProvider`（参数 tag 不复用）。新增意图 `SelectQuotaPaceWidget`，只有“颜色样式”和“服务商”两个参数；服务商选项和主小组件一样，由 `CodexBarMobileWidgetOptions` 的 `IntentHandler` 动态提供，`Info.plist` 的 `IntentsSupported` 也加上了这个意图。
- 新小组件 `CodexBarQuotaPaceWidget`（kind `CodexBarQuotaPaceWidget`），四个尺寸，渲染沿用原来的 `quotaPace` 视图。在 233 上添加的 CodexBar 小组件，因为配置结构已经存死，编辑面板里仍会列出“额度消耗趋势”类型和“服务商”参数（服务商没有选项，类型名在中日文下显示英文）。选了也只回退成概览（枚举原始值 5）。只有 TestFlight 用户会遇到，处理办法是移除后重新添加；本地审查讨论过手写 ObjC 方法兼容这个旧参数，为一个 TestFlight 版本不值得，没有做。
- 旧版小组件（kind `CodexBarStatusWidget`）加上 `.disfavoredLocations`，覆盖主屏、锁屏、待机、Mac 上的 iPhone 小组件，iOS 26 起还有 CarPlay。在模拟器上验证过：小组件库里 CodexBar 从 9 页变成 6 页，已经放在主屏上的旧版小组件仍然显示“重新添加此小组件”的提示。
- 版本 2.5.0 (234)，CHANGELOG 已更新。App 内更新说明本来写的就是“添加新的额度消耗趋势小组件”，不用改。
- **验收**（模拟器 iPhone 18 Pro，iOS 27，build 234）：小组件库里 CodexBar 依次是 Token 活动（小、中）、Token 活动对比（大）、CodexBar 小组件（小、中、大）、额度消耗趋势（小、中、大），旧版不再出现。添加中尺寸“额度消耗趋势”后，自动选了 Claude；编辑面板只有“颜色样式”和“服务商”，改选 Codex 后正常渲染。新添加的 CodexBar 小组件类型只有 4 项。覆盖安装后，编辑面板的参数名会暂时显示英文，重启后恢复中文，这是系统的本地化缓存（升级 232→233 时主小组件也出现过）。截图：`springboard-upgrade-232-keeps-four-types.jpg`、`springboard-pace-widget-config.jpg`、`springboard-pace-widget-medium.jpg`、`springboard-status-widget-four-types.jpg`。
