# 064 — 测试

状态：done。最终提交 `683074e99`（分支 `feature/ios-250-account-cards-pin-sort`），版本 2.5.0 (231)。

## 环境

- 模拟器：`CodexBar iOS 27 iPhone 18 Pro`（iOS 27）、`iPad Pro 13-inch (M5)`。构建目录在 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/ios250`。
- 真机：iPhone Air（iOS 27.0），Debug 签名，CloudKit 环境确认为 `Production`。安装前手机上是 2.3.0 (225)。

## 自动化测试

| 范围 | 结果 |
| --- | --- |
| 新增单元测试 `UsageCardOrderingTests`（34 项） | 全部通过 |
| 新增 UI 测试 `UsageCardOrganizationUITests`（4 项） | 全部通过 |
| 全量 iOS 测试（最终提交） | Swift Testing 924 项 / 57 个 suite 通过；XCTest 单元 55 项通过；UI 23 项通过，0 失败；6 项按条件跳过 |
| 补跑被跳过的 2 个 iPad 布局 UI 测试 | 在 iPad 模拟器上通过（`testTabletColumnsSearchAndSettingsSelectionSurviveResize`、`testRoomyNavigationPreservesProviderThroughPortraitResize`） |
| i18n 审计（`Scripts/audit_localized_keys.py` 和 `state=new` 检查） | 402 个源码 key 都在目录中，没有未翻译条目 |

被跳过的另外 4 项是 SpringBoard 小组件测试（需要系统小组件编辑面板，按条件跳过）。本次没有改动小组件。

### 单元测试覆盖

- **排序纯函数**
  - 升级后保持 Mac 原顺序
  - A→Z、Z→A 两栏各自排序
  - weekly reset 最近的在前，没有重置时间的排最后并按名称排
  - 名称相同时按账号副标题、再按来源顺序，保证稳定
  - 周窗口识别：`period` 优先，否则看 10080 分钟
  - 已过的重置时间按整周往后推
  - 刷新后重置时间变化会重新排序
- **手动顺序与置顶**
  - 没排过的卡片接在后面
  - 手动模式下置顶放到最前，取消置顶放到其他栏最前
  - 默认模式下置顶只改变所在的栏
  - 切到手动时以当前看到的顺序为起点，并保留离线卡片的 key
  - 编辑两栏后的存储结果
- **展开与收起**
  - 展开：置顶状态和位置交给各账号卡片
  - 收起：provider 卡片取第一个账号的位置，以及可见账号的置顶
  - 展开后再收起，回到原状态
  - 消失账号的置顶不会上提给 provider 卡片
- **账号锚点**
  - 只有展开的 provider 才拆成账号卡片
  - record key 在不同 Mac 之间变化时，key 不变
  - 改名、新增账号不影响已有卡片
  - 两个账号不共用一个锚点
  - 没有身份的旧数据也能得到不同的 key
  - record 槽位换了账号，新账号不继承旧卡片
  - 全局最优匹配
  - email 权重高于共享 workspace 身份
- **合并记录**
  - 确认合并后，旧卡片并入：最新数据来自旧 Mac 时，或者旧卡片本身没有身份时
  - 已撤销的合并不会触发并入
  - 离线的 label 账号不会被并入
  - 旧卡片本身不会通过占位标识吞掉别的账号
  - 账号卡片上的"撤销合并"只作用于自己
- **存储**
  - 读写往返
  - 演示 store 不写 UserDefaults
  - JSON 损坏或排序规则未知时回退到默认值
  - 遇到更新的 schema 版本时不覆盖已存数据

### UI 测试覆盖

- `testProviderMenuExpandsAccountsPinsCardsAndPersistsAcrossLaunch`：
  - 默认显示为一张合并卡片
  - `…` → 服务设置 → 打开展开开关后，Codex 出现 3 张账号卡片，Claude 不受影响
  - 从账号详情页置顶第 3 个账号后，出现置顶栏，顺序正确
  - 重启后展开和置顶都还在
  - 取消置顶、收起后，恢复成一张卡片
- `testEditOrderDefaultRulesManualDragAndPersistence`：
  - 打开默认排序，依次验证 Z→A、A→Z、weekly reset
  - 切到手动模式后拖动 Codex 到 Antigravity 上方，列表同步变化
  - 重启后仍是手动模式，顺序保持
- `testSingleAccountProviderSettingsExplainWhyExpansionIsUnavailable`：只有一个账号时开关不可用，并有说明文字
- `testCaptureOrganizationScreensOnCurrentDevice`：在 iPhone 和 iPad 上各截一套图（列表、服务设置、展开加置顶、编辑排序）

测试数据：启动参数 `UI_TEST_MULTI_ACCOUNT_DATA` 加载 `PreviewData.multiAccountSnapshot`（Codex 3 个账号、Claude 2 个账号，加上原有的单账号演示 provider）。

## 截图证据（`screenshots/`）

| 文件 | 内容 |
| --- | --- |
| `iphone-light-01-grouped.jpg` | 默认合并卡片 |
| `iphone-light-02-provider-settings.jpg` | 服务设置（展开开关打开） |
| `iphone-light-03-expanded-pinned.jpg` | 账号卡片加置顶栏 |
| `iphone-light-04-edit-order-manual.jpg` | 手动排序拖动之后 |
| `iphone-light-05-edit-order-weekly.jpg` | 按 weekly reset 排序，显示相对时间 |
| `iphone-dark-01…03` | 深色模式：展开加置顶、服务设置、weekly 排序 |
| `ipad-light-01/02`、`ipad-dark-01/02` | iPad 浅色和深色：展开加置顶、编辑排序 |
| `iphone-air-device-01-weekly-real-data.jpg` | 真机加真实同步数据：weekly reset 排序 |
| `iphone-air-device-02-pinned-real-data.jpg` | 真机加真实同步数据：置顶 DeepSeek 后的两栏布局 |

模拟器上服务设置页的截图，是在文案从“this iPhone”改成“this device”之前截的。改动后的文案由真机验证和 UI 测试断言覆盖。

## 真机验证（iPhone Air，真实 CloudKit 数据，简体中文）

1. 首次启动时，2.5.0 的中文更新说明正确显示。
2. 编辑排序 → 打开默认排序 → 选“每周重置（最近的在前）”。顺序是 Claude（1 天后）→ Codex（6 天后）→ Antigravity、DeepSeek、Grok（都显示“无每周重置”，按名称排），Usage 列表与之一致。
3. DeepSeek 的 `…` 菜单，无障碍标签读作“更多操作”。点“置顶”后出现“已置顶 / 其他卡片”两栏，卡片上有置顶图标，菜单变为“取消置顶”。
4. 服务设置：DeepSeek 只有一个账号，开关不可用，显示“这个服务目前只同步了一个账号。”和“仅保存在这台设备上，不会同步到 Mac。”
5. 结束并重新启动 App 后，置顶和排序都保留。
6. 验证结束后已恢复：取消置顶，排序设为“名称（A 到 Z）”，与测试前的顺序一致。

真机局限：这台手机同步过来的 5 个 provider 都只有一个账号，所以“多账号展开”无法用真实数据验证，只验证了单账号时开关不可用的状态。展开流程由 UI 测试中的多账号数据覆盖。手动拖动没在真机上做，因为 sim-use 在真机上不支持拖动手势，拖动由 UI 测试覆盖。

## 本地代码审查

子智能体做了四轮对抗式审查：

- 第一轮发现 7 项问题（2 个中等、1 个中低、4 个低），全部修复。
- 第二轮复审发现 2 项遗留问题（N1、N2），修复。
- 第三轮复审发现 N1 的修复引入了新问题 N3（中等），修复。
- 第四轮终审结论：没有剩余缺陷。

修复内容包括：账号卡片的撤销合并只作用于自身；weekly 排序改用独立时钟；锚点改为全局匹配和分权重打分；合并记录驱动的锚点并入（只认生效的合并）；“More Actions”改用独立 key；iPad 侧栏行支持长按置顶；收起时只上提可见账号的置顶。

## PR 与合并

- PR #172 两轮 Codex 审查：
  - 第 1 轮：1 条 P2，选中的卡片在刷新、账号消失或锚点并入后变成空白详情页。修复方式是监听卡片集合的变化，并抽出 `UsageCardSelection.resolve`，加上单测。
  - 第 2 轮：在 `fb32df66f` 上没有意见。
- `Scripts/check_pr_review_gate.sh 172` 通过：rounds=2，unresolved=0。PR Fast Checks 通过。
- 在最终提交 `fb32df66f` 上跑全量：Swift Testing 925 项，XCTest 单元 55 项，UI 23 项（6 项条件跳过），0 失败。2 个 iPad 布局测试在 iPad 上补跑后通过。
- 2026-10-03 合并进 `mobile-dev`，merge commit 是 `1ebd058e1`。Todoist 任务已移到 QA。

## TestFlight

- 合并后的 Final CI（run `37163341203`）通过。这次只改了 iOS，所以 lint 和 lint-build-test 运行，Mac/Linux 矩阵按路径选择被跳过。
- 2026-10-03 用 `Scripts/upload_ios_testflight.sh` 上传，源码是 `mobile-dev` 的 `93f7a08ce`。产品输入与审查通过的 PR head `fb32df66f` 完全一致，合并之后只追加了文档提交。
  - 第一次上传时，脚本自带的 lint 里 `test_swift_test_sharding.sh` 偶发超时（退出码 124）。单独重跑两次都通过，第二次上传正常完成。
- 归档：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-20261003-170544/CodexBarMobile.xcarchive`，版本 2.5.0 (231)。主 App、推送扩展和小组件的 CloudKit 环境都是 `Production`；WidgetOptions 扩展不使用 iCloud。
- ASC build `12b181cc-0e7f-4495-9e73-a3b23fbfc87a`：`VALID`，上传时间 2026-10-03 17:10 PDT。

## 未做 / 后续

- 还没有提交 App Review，等 TestFlight 在真机上验收。
- 发布前要核对 App Store Connect 上 2.4.0 是否已正式上架。如果没有，按惯例把 2.4.0 的应用内更新说明并入 2.5.0。
- 用户有多个真实账号时，最好在真机上再验证一次多账号展开（例如 issue #154 的提交者场景）。
