# 064 — iOS 2.5.0：多账号独立卡片、置顶与排序

状态：draft（Goal 已定义，待调研与实现）

## Goal

在 iOS 2.5.0 中交付三个连在一起的用户可见能力：

1. **多账号展开为独立卡片**（issue #154）：支持多账号的 provider 可以在 Usage 页把每个账号显示成独立卡片，不必进入详情页再切换账号标签。按 provider 单独开关，默认关闭。例如 3 个 Claude 账号和 3 个 Codex 账号，可以只展开 Codex。
2. **Provider 三点菜单与卡片置顶**：provider 详情页右上角新增 `…` 菜单，所有 provider 统一有这个入口。菜单里有：
   - 进入该 provider 的专属设置页（目前放“多账号展开”开关，以后可以继续加别的自定义项）；
   - 置顶 / 取消置顶当前卡片。置顶后，卡片自动移到 Usage 页最上方。
3. **Usage 页排序**：Usage 页右上角新增入口，进入“编辑排序”。页面分成“置顶”和“其他”两栏，两栏各自都能排序：
   - **默认排序**：三条规则可选：首字母 A→Z、首字母 Z→A、按 weekly reset 时间（最近重置的排最上面，最远的排最下面；没有 weekly reset 的卡片排在后面，彼此按首字母排）。
   - **手动排序**：切换后用户可以自由拖动，置顶栏和其他栏都能调整。

## Context

- 先读仓库 `AGENTS.md`，按其中的 7 步流程推进。调研与设计写在本目录（`01-research.md` / `02-implementation.md` / `03-testing.md`）。
- 用户诉求原文与讨论：GitHub issue #154（同一用户的第二个问题“3 个 plan 只显示 2 个”不在本次范围；调研中若发现和卡片展开是同一个根因，记录下来再判断）。
- 现有多账号聚合：`Models/ProviderAccountGroup.swift`（`groupedByProvider()`），调用点在 `ContentView.swift`；详情页 `Views/ProviderDetailView.swift`（已有账号标签和 toolbar）。
- 账号身份规则（必须遵守）：本地存储和唯一性只用持久化 opaque `accountRecordKey`，不要用可以编辑的 label 或 email；跨 Mac 合并按完整 identity set 求并集。置顶和排序的 key 必须在刷新、改名、增删账号、多 Mac 合并、设备合并（Sync Device Management）之后依然稳定。
- 所有展示同步数据的地方共用同一套 reducer（`ProviderSnapshotMerger` 等）。排序和置顶只作用于展示层，不要另写一份数据合并。

## Constraints

- 只改 iOS（`CodexBarMobile/`）。provider 设置、置顶、排序都只存在本机（本地持久化，带 schema 版本），**不写入 CloudKit / KVS，也不同步到 Mac**；Mac 行为和 `Shared/` payload 不变。
- 小组件、Cost 页、分享卡片的顺序和内容不受影响；如果认为应该受影响，先写进调研文档等用户确认。
- “多账号展开”默认关闭；provider 只有一个账号时不显示这个开关，或显示为不可用并附说明。
- 排序必须是可以单独测试的纯函数（输入：卡片列表、置顶集合、排序模式、手动顺序、当前时间；输出：两栏的有序列表）。视图只负责调用它。
- 以下边界情况必须定义清楚，并写进调研文档：
  - 展开 / 收起多账号时，原来的置顶状态和手动顺序怎么迁移（例如合并卡片已置顶，展开后各账号卡片是否继承置顶，排在什么位置）；
  - 手动模式下新出现的卡片放在哪里，消失的卡片残留的 key 怎么清理；
  - 默认模式切换到手动模式时，以当时的顺序作为手动顺序的初始值；
  - 数据刷新导致 weekly reset 时间变化时，列表要重新排序，但不能在用户滚动或编辑时乱跳；
  - Usage 页搜索 / 过滤、演示（mock）模式、iPad 宽屏和横屏下行为一致。
- 所有新增的用户可见文字必须有四种语言（en、zh-Hans、zh-Hant、ja）。
- 版本号 2.4.0 (230) → 2.5.0，build 号按 `docs/versioning.md` 递增；更新 `CodexBarMobile/CHANGELOG.md` 和应用内 release notes（新建 2.5.0 条目）。
- 不上传 TestFlight，也不发布。

## Done when

- 调研和设计文档写完，里面有交互流程、存储 schema、key 稳定性分析和边界情况表，状态更新为 `done`。
- 单元测试覆盖：
  - 排序纯函数：三种默认规则、手动模式、两栏分组、缺少 reset 时间时的回退、名字相同时的稳定排序；
  - 展开 / 收起时置顶和顺序的迁移；
  - 用 `accountRecordKey` 作为 key 时，账号改名、增删账号、多 Mac 合并之后 key 依然稳定；
  - 本地存储的读写和 schema 版本迁移；
  - 刷新后重新排序。
- UI 测试覆盖：
  - `…` 菜单 → provider 设置 → 打开多账号展开 → Usage 页出现各账号的独立卡片；
  - 置顶 / 取消置顶；
  - 编辑排序页切换三种默认规则、切换手动排序并拖动，两栏都要测；
  - 重启 App 后上面的设置都还在。
- 构建和完整 iOS 单测通过；用模拟器截图验证 iPhone 与 iPad、浅色与深色、展开与收起、置顶与排序页，截图存证到本目录 `03-testing.md`。条件允许时，在真机上用真实多账号数据点一遍。
- CHANGELOG、四语言 release notes、版本号都已更新；`Research/README.md` 索引已登记。
