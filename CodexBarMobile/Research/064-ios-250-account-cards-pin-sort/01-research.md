# 064 — 调研与设计

状态：done（设计已实现，见 `02-implementation.md`）

## 1. 现状

- Usage 列表：`ContentView.swift` 的 `ProviderListView` 先用 `MockProviderDetector.filteredProviders` 过滤快照，再用 `groupedByProvider()`（`Models/ProviderAccountGroup.swift`）按 `providerID` 合成卡片，每个 provider 一张。顺序就是 Mac 同步过来的 provider 首次出现顺序，iOS 端没有排序层。
- 多账号：同一 provider 的多个账号挤在一张卡片里，卡片上显示“· N”，进入 `ProviderDetailView` 后用分段控件切换账号。issue #154 的诉求是：不切换就能在列表里同时看到每个账号。
- 选中状态：`UsageTab.selectedProviderID` 按 provider 记录。iPad 左右分栏时会默认选中第一个 provider。
- 详情页 toolbar 只有 mock 徽标，没有菜单。

## 2. 账号身份与 key 稳定性

合并器 `ProviderSnapshotMerger` 对同一个账号取 `accountRecordKey` 和 `accountIdentities` 时，用的都是“各台 Mac 中最新的非空值”。`accountRecordKey` 是每台 Mac 安装时生成的 token UUID，所以同一个账号在多台 Mac 之间，record key 会随着哪台 Mac 最近同步而来回变。直接拿 record key 当置顶或排序的 key，最近同步的 Mac 一换，用户的置顶和顺序就丢了。

方案：**本地账号锚点**（`UsageAccountAnchor`）。

- 每个锚点记录 `providerID` 和它见过的全部身份 token。token 来源是合并器的 `effectiveIdentifiers`（真实账号、组织、邮箱身份），再加上 `providerID:record:<recordKey>`。合并器那个“没有身份”的占位值不算 token；什么身份都没有的旧数据，用 `providerID:card:<cardIdentityKey>` 兜底。
- 匹配规则：一个 provider 的账号按来源顺序逐个匹配。每个账号选择**与自己 token 重叠最多、且还没被别的账号占用**的锚点（重叠数相同时选先存的锚点）。所以两个账号永远不会共用一张卡片的 key。
- 新账号的锚点 ID 取当时的 `cardIdentityKey`，被占用时加 `#2` 这样的后缀。列表在锚点写入之前渲染出的 key，和写入之后完全相同，卡片不会因为锚点刚存下来就“换身份”。
- 自愈：每次数据变化时调用 `reconcileAnchors`，把新出现的 token（例如第二台 Mac 的 record key）并入匹配到的锚点。只给已展开 provider 的账号建锚点，未展开的 provider 不会产生存储。
- 不使用可编辑的 label：有真实身份时，`effectiveIdentifiers` 不包含 label 当作 email 的兜底值。账号改名不会影响匹配，因为 record key 不变。

验证见 `UsageCardOrderingTests`：record key 跨 Mac 变化、改名加新增账号、旧锚点同时含两个账号的 token、无身份旧数据。

## 3. 数据模型与存储

`Models/UsageCardPreferences.swift`：

| 字段 | 含义 | 默认 |
| --- | --- | --- |
| `schemaVersion` | 当前为 1 | 1 |
| `expandedProviderIDs` | 展开为独立账号卡片的 provider | 空 |
| `pinnedCardKeys` | 已置顶的卡片 key | 空 |
| `usesDefaultSort` | 是否使用默认排序规则 | `false` |
| `defaultSortRule` | `alphabeticalAscending` / `alphabeticalDescending` / `weeklyReset` | A→Z |
| `manualOrder` | 手动顺序（两栏合在一个列表里） | 空 |
| `accountAnchors` | 账号锚点 | 空 |

卡片 key：`provider:<providerID>`（整个 provider 一张卡片）、`account:<anchorID>`（展开后每个账号一张）。

- 存储：`UsageCardPreferencesStore` 以 JSON 形式存在本机 `UserDefaults.standard` 的 `usageCardPreferences.v1`。**不写 CloudKit/KVS，不进 `Shared/` payload，Mac 完全不知道这些设置。**
- 解码容错：字段缺失时用默认值；未知的排序规则回退到 A→Z；JSON 损坏时整体回退到默认值。
- 降级保护：遇到比当前版本更新的 `schemaVersion` 时，本次运行按默认值显示，并且**不覆盖**已存的数据，避免装回旧版本把新版本的设置清掉。
- 演示模式使用内存里的 store，试用演示不会改动真实布局。UI 测试的 `UI_TEST_RESET_DEFAULTS` 会清除这个 key。

## 4. 交互

1. **详情页 `…` 菜单**：所有 provider 都有，里面是“置顶 / 取消置顶”和“服务设置”。卡片长按菜单里也有置顶。
2. **服务设置**（sheet，从 Usage 页这一层弹出）：
   - 开关“账号分开显示为独立卡片”。只有一个账号、且当前没有展开时，开关不可用，并说明原因。
   - 页面写明“仅保存在这台 iPhone 上，不会同步到 Mac”。
   - sheet 挂在 Usage 页而不是详情页上，所以切换展开状态后，背后的详情页会跟着换成对应卡片，sheet 本身不会被关掉。
3. **Usage 页**：有置顶卡片时，先显示“已置顶”栏，再显示“其他卡片”栏；没有置顶时，界面和以前一样。搜索在排序之后过滤，两栏都生效。
4. **编辑排序**（Usage 页右上角，sheet）：
   - 顶部是“默认排序”开关。打开后可以选三种规则，两栏各自排序，拖动不可用。
   - 关闭后是手动排序，两栏都可以拖动。
   - 按 weekly reset 排序时，每一行显示距离重置还有多久；没有 weekly reset 的行显示“无每周重置”。

## 5. 排序规则（纯函数 `UsageCardOrdering.arrange`）

- 输入：卡片描述（key、名称、账号副标题、下次 weekly reset 时间）和偏好设置。输出：`pinned` 和 `others` 两栏。
- **A→Z / Z→A**：先按 provider 名称比较（忽略大小写和变音，数字按数值比），再按账号副标题升序，最后按来源顺序，保证结果稳定。Z→A 只把名称这一层倒过来，同一 provider 的账号仍按副标题升序。
- **weekly reset**：只看周窗口。`period == .weekly` 算周窗口；没有 `period` 时，`windowMinutes == 10080` 也算。多个周窗口取最早的一个。如果重置时间已经过去，就按整周往后推到下一次，所以一张很久没刷新的卡片也会按它真正的下一次重置排序。没有周窗口或没有重置时间的卡片排在最后，彼此按 A→Z。
- **手动**：按 `manualOrder` 里的位置排；没在里面的卡片接在后面，按来源顺序。

## 6. 边界情况

| 场景 | 规则 |
| --- | --- |
| 升级后第一次打开 | 手动模式、手动顺序为空，等于原来的 Mac 顺序，用户看不到任何变化 |
| 展开 provider | provider 卡片的置顶状态交给它的每个账号卡片；手动顺序里 provider 卡片的位置，换成它的各账号卡片（按账号顺序） |
| 收起 provider | provider 卡片放到它排得最靠前的那个账号卡片的位置；只要有一个账号卡片置顶，provider 卡片就置顶；该 provider 的账号 key 全部从顺序和置顶里移除，锚点保留 |
| 手动模式下置顶 | 先把当前看到的顺序固化下来，再把这张卡片放到置顶栏第一位 |
| 手动模式下取消置顶 | 放到其他卡片栏的第一位 |
| 默认模式下置顶或取消置顶 | 只改变所在的栏，位置由规则决定 |
| 默认排序切到手动 | 以当时看到的顺序作为手动顺序的初始值 |
| 手动模式下出现新卡片 | 排在已排好的卡片后面，按来源顺序 |
| 卡片暂时消失（Mac 离线、搜索中） | 手动顺序里保留它的 key；它回来时回到原位置。编辑排序和切换模式时，这些 key 接在可见卡片后面 |
| 账号永久删除 | 留下的 key 不显示；收起该 provider 时一并清掉 |
| 数据刷新导致 weekly reset 变化 | 下一次渲染重新排序，并带动画。排序用的“现在”是根视图的 `costReferenceDate`（只在跨天时前进），所以列表只在数据刷新或跨天时变化，不会在滚动途中自己跳动。编辑排序页每次渲染都从最新数据计算，拖动只在手动模式下可用，而手动顺序不受刷新影响 |
| 展开或收起时，详情页正打开着 | 选中项改到同一个 provider 的新卡片上，iPhone 不会掉回空白页 |
| 演示模式 | 用独立的内存 store，退出演示后真实布局不变 |
| iPad 分栏 | 左栏紧凑行使用同一套排序，显示置顶图标；默认选中排序后的第一张卡片 |

## 7. 不在范围内

- 小组件、Cost 页、分享卡片的顺序不变（它们不读这些偏好）。
- issue #154 的第二个问题（Codex 3 个 plan 只显示 2 个）：Mac 端按账号合并 plan，iOS 只显示同步过来的每个账号快照。展开账号卡片不会改变 plan 的数量，两者不是同一个原因。需要等用户提供 Mac 端截图后单独分析。
- 不同步到 Mac，不提供跨设备同步布局。
