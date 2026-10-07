# 多台 Mac：一台刷新失败时不再覆盖另一台的有效数据

Status: `in-progress`
Date: 2026-10-07
Version: iOS 2.6.0 (236)（2.6.0 撤回审核后同版本修复）

## 现象

两台 Mac（MacBook Pro、Mac Studio）都开启 iPhone 同步。muse.ai 只在 Mac Studio 的浏览器登录过：Mac Studio 发布 21% 用量；MacBook Pro 读不到 Cookie，发布“无数据 + 报错”。iPhone 先显示 21%，随后变成 MacBook 的报错。Mac 版自己的多设备同步（上游 fleet sync）会在本机拿不到数据时显示“通过 Mac Studio”的数据，iPhone 没有对应逻辑。

## 根因

1. Mac 每次同步都会为每个启用的 provider 发布一条 `ProviderUsageSnapshot`。刷新失败且本机从未拿到数据时，`snapshot == nil`，于是 `isError = true`、无窗口/详情/余额、`lastUpdated = Date()`（发布时间），见 `SyncCoordinator.buildProviderUsageSnapshot`。
2. iOS `ProviderSnapshotMerger.mergeProviderEntries` 以 `lastUpdated` 最新者为 base，额度窗口、状态、`isError`、账号与详情都取 base；“报错”被当作最新观测。只有 Kimi 的月池选择会跳过报错条目。
3. `mergedDetails` 把 v0.48+ writer 的空 `details` 视为权威清空，报错条目会把另一台 Mac 的详情行清空。
4. 失败条目没有账号身份（`providerID:legacy-no-identity`），当另一台 Mac 的条目带邮箱等身份时，两者不在同一组，失败条目会变成一张单独的“报错账号”卡。
5. iPhone 数据通道与 Mac 的 fleet sync 相互独立：每台 Mac 都直接把自己的结果发给 iPhone，不会转发其它 Mac 的数据。因此无论 Mac 是否开启 fleet sync，问题都一样，修复必须在 iPhone 合并层完成。

测试漏网：多设备兼容矩阵与合并测试的 writer 都是“成功”或“缺失”，没有“一台成功、一台无数据报错”的组合。

## 设计（经第一轮本地 review 修订）

**定义**：报错、且所有由 Mac 刷新结果派生的字段（额度窗口、详情、余额、预算、账号邮箱/组织/登录方式、订阅日期及各 provider 专用数据）都为空的条目是 *failure-only*。本地成本、利用率历史、图标、缓存的工作区/账号列表不算观测。报错但带上次数据的条目仍算观测，按其采集时间参与比较。

1. **选择**：组内存在观测时，额度、状态、账号、详情、窗口并集、登录方式等只在观测中按采集时间取最新；成本与利用率历史仍合并全部条目。全部是 failure-only 时保持原行为（最新报错）。
2. **吸收而不是丢弃**：没有身份（`legacy-no-identity`）的 failure-only 组，若同一 provider 恰好只有一个“真实账号”观测组，就并入该组：不再单独成卡，但它所在 Mac 的本地成本照常合并。OpenRouter 管理成本信封和 debug mock 不算真实账号，不会吞掉真实报错。有多个账号时归属不明，保留原来的单独报错条目。带 token 账号身份（record key）的失败也保留原行为。
3. **同一台物理 Mac**：设备别名合并（重装后的新旧 deviceID）不启用上述规则，仍是最新状态胜出，当前失败不会被旧 ID 的陈旧数据盖住。
4. **来源报告由合并器产出**：分组时直接生成 `sourceReport`（只在 iPhone 本地，Mac 不发布）：数据来源 Mac、采集时间、比它更晚的失败（设备名、时间、原文）、参与的 Mac 数。界面只读这份报告，与合并器实际分组（含 linkage、传递合并）完全一致。
5. **展示**：
   - 详情页顶部：有更晚失败或所有 Mac 都失败（≥2 台）时显示警告样式，说明数据来自哪台 Mac、多久前，以及每台失败的 Mac 与原因；只是数据超过 6 小时则显示信息样式“数据可能不是最新的”。单台 Mac 自己的报错已由卡片显示，不重复提示。提示每分钟刷新相对时间。
   - 列表卡片：存在更晚失败时，在更新时间旁显示“来自 {Mac}”。
6. **缓存**：iOS 对无邮箱条目的 30 分钟过期规则豁免仍在报错的条目（7 天上限），避免“带旧数据的报错”被提前丢弃而只剩另一台的报错。
7. **范围**：卡片、详情、小组件共用合并器，一起生效。只改 iOS；Shared 新增字段只在 iPhone 本地使用，不上 CloudKit，不需要 Mac 发布。

## 场景覆盖

| 场景 | 结果 |
|---|---|
| A 成功、B failure-only（B 更新） | 显示 A 数据；详情警告说明 B 失败；卡片“来自 A” |
| A 成功（很旧）、B failure-only（最新） | 显示 A 数据并标明多久前；警告 |
| A 只是很旧，没有失败 | 信息样式提示数据可能不是最新 |
| A 成功、B 带旧数据报错 | 取采集时间较新者；B 的报错列入提示 |
| A、B 都 failure-only | 显示最新报错；详情说明所有 Mac 都失败 |
| A 带邮箱身份成功、B 无身份失败（含本地成本） | 一张 A 的卡，成本包含 B，附 B 失败提示 |
| 多个账号 + 无身份失败 | 归属不明，保留原单独报错条目 |
| OpenRouter 成本信封 / mock + 真实失败 | 真实失败照常显示 |
| 同一 Mac 新旧 deviceID | 最新状态（含失败）胜出 |
| 已确认 linkage 合并 | 来源报告指向卡片实际使用的数据 |
| 只有一台 Mac 且失败 | 与现有一致，不额外提示 |
| Mac 开/关 fleet sync | 不影响：iPhone 只看各 Mac 直接发布的结果 |

## 测试证据

- `MultiMacFailureFallbackTests` 16 项（上表全部场景、四语言提示、缓存 TTL 豁免）通过。
- iOS 完整单测 974 项通过；Mac `Sync|MockProviderInjector|QuotaProviderList|CloudSync` 416 项通过（Shared 字段变更）。
- 冻结旧/新 Shared 16 组合重跑通过（frozen-wire-ff2）。

## Review

- 第一轮本地独立 review：1 阻塞（丢弃失败组会丢本地成本）、3 重要（成本信封/mock 吞掉报错、同 Mac 别名合并被盖、界面反推来源与分组不一致）及若干建议，均已按上文修订并补测试。
