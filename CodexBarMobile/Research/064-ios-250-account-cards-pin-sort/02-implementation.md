# 064 — 实现

分支：`feature/ios-250-account-cards-pin-sort`（基于 `mobile-dev` `8c45b99fd`）。只改 `CodexBarMobile/`，`Shared/` 和 Mac 端没有任何改动。

## 新增文件

| 文件 | 内容 |
| --- | --- |
| `Models/UsageCardPreferences.swift` | 偏好模型（带 schema 版本）、卡片 key、账号身份 token、锚点匹配和 `reconcileAnchors`，以及展开/收起迁移、置顶、默认/手动切换、手动顺序这些纯函数修改 |
| `Models/UsageCardOrdering.swift` | `UsageCard`、`UsageCardBuilder`（provider 分组 → 卡片，展开的 provider 拆成账号卡片），以及排序纯函数 `UsageCardOrdering.arrange` 和 weekly reset 计算 |
| `Models/UsageCardPreferencesStore.swift` | `ObservableObject`：live 版写 `UserDefaults`，demo 版只在内存；带降级保护 |
| `Views/UsageCardSettingsViews.swift` | `ProviderSettingsView`（服务设置）、`UsageSortEditorView`（编辑排序）、`UsageCardPresentation`（账号副标题） |
| `CodexBarMobileTests/UsageCardOrderingTests.swift` | 24 个单元测试 |
| `CodexBarMobileUITests/UsageCardOrganizationUITests.swift` | 3 个 UI 测试 |

## 修改

- `ContentView.swift`
  - `ContentView` 持有 live 和 demo 两个 store，按是否在演示模式传给 `UsageTab`。
  - `UsageTab` 的选中状态改为卡片 key。新增“编辑排序”按钮（`usage-edit-order`）和服务设置 sheet。数据变化时用 `.task(id:)` 写入锚点；展开状态变化时把选中项移到同一 provider 的新卡片上。
  - `ProviderListView` 拿到排序结果后分两栏渲染，有置顶时显示“已置顶”和“其他卡片”标题。provider 卡片沿用原来的 `provider-group-<id>` 标识；账号卡片的标识是 `provider-account-card-<id>-<序号>`。
  - 应用内更新说明新增 2.5.0 条目，2.4.0 不再标为最新。
- `Views/ProviderDetailView.swift`：新增 `ProviderDetailCardMenu`，toolbar 加上 `…` 菜单（`provider-more-menu`、`provider-menu-pin`、`provider-menu-settings`）。
- `Views/ProviderUsageView.swift`：新增置顶图标、长按菜单里的置顶/取消置顶，以及 `visibleOrganization` 这个辅助方法。账号卡片通过 `duplicateOrdinal` 显示“Codex 2”这样的兜底副标题。
- `CodexBarMobileApp.swift`：`UI_TEST_RESET_DEFAULTS` 会同时清除卡片偏好；新增启动参数 `UI_TEST_MULTI_ACCOUNT_DATA`。
- `Preview Content/PreviewData.swift`：新增 `multiAccountSnapshot`，在原有演示数据上额外加 2 个 Codex 账号和 1 个 Claude 账号。只在 UI 测试启动参数下使用，原演示数据不变。
- `Localizable.xcstrings`：新增 26 条四语言文案（21 条界面文字和 5 条更新说明）。
- `project.yml`：所有 target 的版本改为 2.5.0 (231)。
- `CHANGELOG.md`：新增 2.5.0 (231) 条目。

## 说明

- 编辑排序页在 UI 测试启动参数下，会额外暴露一个 1×1 的不可见元素 `sort-order-state`，它的 accessibilityValue 是完整顺序。原因是 List 里屏幕外的行不在辅助功能树中，测试读不到。正常使用时不会生成这个元素。
