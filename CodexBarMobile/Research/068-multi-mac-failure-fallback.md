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

## 设计

**定义**：报错且不携带任何观测内容（无 primary/secondary/rateWindows、details、providerAmount、budget、账号邮箱、登录方式）的条目是 *failure-only*。报错但仍带有上次数据的条目（stale data + error）仍算观测，数据按其采集时间参与比较。

1. **选择**：组内存在非 failure-only 条目时，额度、状态、账号、详情、窗口并集等都只在这些条目中按采集时间选最新；failure-only 条目只作为失败提示。全部是 failure-only 时保持现有行为（显示最新报错）。
2. **失败提示**：比所选数据更新、来自其它 Mac 的 failure-only 条目，记录为“较新的失败”（设备名、时间、报错原文），挂在合并结果的来源信息上。
3. **身份分组**：没有身份的 failure-only 组，若同一 provider 还有带观测的组，则不再单独成卡，失败提示附加到这些组。若该 provider 只有失败条目则照常显示报错卡。
4. **展示**：
   - 详情页顶部提示：“显示的是 {Mac Studio} 在 {3 小时前} 获取的数据。{MacBook Pro} 在 {5 分钟前} 刷新失败：{原因}”。数据越旧越醒目（超过阈值用警告色）。
   - 列表卡片保留有效数据，并在存在较新失败时显示一行简短来源说明，避免把旧数据当成刚刷新的结果。
5. **范围**：卡片、详情、小组件共用合并结果，一起生效。只改 iOS 与 Shared 本地字段（来源信息新增可选字段，只在 iPhone 本地使用，不上 CloudKit wire，不需要 Mac 发布）。

## 场景覆盖

| 场景 | 结果 |
|---|---|
| A 成功、B failure-only（B 更新） | 显示 A 数据；详情提示 B 失败 |
| A 成功（很旧）、B failure-only（最新） | 显示 A 数据并标明多久前；提示醒目 |
| A 成功、B 带旧数据报错 | 按采集时间取较新数据；B 的报错不覆盖 A 较新的数据 |
| A、B 都 failure-only | 显示最新报错（与现有一致） |
| A 带邮箱身份成功、B 无身份失败 | 一张 A 的卡，附 B 失败提示，不再出现第二张报错卡 |
| 只有一台 Mac 且失败 | 与现有一致 |
| Mac 开/关 fleet sync | 不影响：iPhone 只看各 Mac 直接发布的结果 |

## 测试计划

合并单测覆盖上表每个场景（含输入顺序反转、平局、Kimi 不回归、details 不被清空、窗口并集不混入失败条目）；分组折叠测试；SwiftData 写入/重开后合并；详情提示与卡片说明的呈现模型测试（四语言）；iOS 完整单测与 WidgetSnapshotBuilder；冻结 wire 16 组合重跑。
