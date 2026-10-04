# 066 — 设置页“联系”和“我的更多 App”

状态：done（2.5.0 (234)，分支 `feature/ios-250-developer-links`）
日期：2026-10-04
相关：Research/065 第 8 节（同一个 build 的小组件调整）

## 需求

设置页开发者一栏原来只有“Yuxiao”一行，点击跳转到 X。用户要求加两行：

1. **联系**：点击后给 codexbar@yuxiaow.com 写邮件。
2. **我的更多 App**：点进去列出开发者的其他 App 和项目，内容和 app.o1xhack.com 一致。

## 用户决定（2026-10-04）

- 列 app.o1xhack.com 第一个板块里的项目，去掉 Freight Fee Calculator；CodexBar 自己不列。
- 下面单独、极简地列 Obsidian 插件。
- 每个项目的跳转规则：有 iOS App（上了 App Store）就跳 App Store；没有就跳官网；没有官网就跳 GitHub。

## 实现

- `ContentView.swift`：开发者一栏在 Yuxiao 下面加两行。
  - “联系”是 `mailto:` 链接，副标题显示邮箱，长按可拷贝邮箱地址。没有配置邮件 App 时，iOS 会自己提示。
  - “我的更多 App”是 `NavigationLink`，进入 `MoreAppsView`。`Destination` 新增 `.moreApps`，紧凑布局和 iPad 列表-详情布局都可用。
- `Views/MoreAppsView.swift`：

  | 项目 | 跳转 | 图标 |
  |---|---|---|
  | Coffee It | App Store id1216049514 | 自己的 App 图标 |
  | Photo Status | App Store id6784043470 | 自己的 App 图标 |
  | Scrobble Bridge | 官网 scrobble-bridge.o1xhack.com（Mac App，不在 App Store） | 自己的 App 图标 |
  | Telegram Watch | GitHub o1xhack/telegram-watch（没有官网） | 中性的纸飞机符号 |
  | Obsidian：Chatting with AI、Daily Note Plus、Sync Todoist、Sync Trakt | Obsidian 社区插件页（算作官网） | 不显示图标，只列名字 |

  - 每行右侧写明跳去哪里：App Store / 官网 / GitHub。
  - 列表最下面链接到 app.o1xhack.com。
  - App 图标从 app.o1xhack.com 下载，缩到 180×180 放进 `Assets.xcassets`（`MoreApp*`）。
  - Telegram Watch 网站上用的是 Telegram 官方 logo，放进 App 有被 App Review 按第三方商标质疑的风险，所以 App 里改用纸飞机符号。
  - `Link` 里的 `.primary`、`.secondary` 等层级样式会被解析成强调色，所以文字和描边都直接用系统的 label、separator 颜色。
- 四种语言的文案，2.5.0 更新说明加了一句，CHANGELOG 已更新。
- 列表写死在 App 里，以后加项目要跟着发版。

## 验证

- 模拟器（iPhone 18 Pro，iOS 27，中文）：开发者一栏显示三行；“我的更多 App”页面的图标、简介和跳转标签都正常，文字是正常的黑色，不是强调色。
- UI 测试 `testSettingsDeveloperContactAndMoreApps`：找到“联系”行和邮箱，进入“我的更多 App”，检查 8 个项目都在。
- 本地子智能体审查：没有 P1 或 P2；7 个 nit 已改（描边颜色、UI 测试的滚动条件、箭头不参与 VoiceOver 朗读、超大字号下去向标签不换行、图标不和小组件设置重复、CHANGELOG 措辞、Telegram 图标）。审查时实际请求过 8 个跳转 URL，都返回 200。
