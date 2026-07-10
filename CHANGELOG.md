# Changelog

## 0.41.0 — 2026-07-06

### Added
- CLI: add responsive `codexbar cards` and compact `--brief` terminal usage views. Thanks @DonnieFi!
- Antigravity: show pace details for legacy model-family and current session/weekly quota rows without changing compact icon lane semantics. Thanks @Zihao-Qi!
- Widgets: make Kimi available with Weekly, Rate Limit, and Monthly quota rows. Thanks @joeVenner!
- Kimi: show the subscription 7-day Code quota in menus and large widgets. Thanks @skyzer!
- Claude: distinguish Max 5x and Max 20x in the plan label instead of a flat "Max". Thanks @kes02!

### Fixed
- Ollama: point missing-session recovery to the current `/signin` page instead of the protected settings page. Thanks @joeVenner!
- Alibaba Token Plan: support International Model Studio while preserving China-mainland upgrades and isolating regional cookie caches. Thanks @harshav167!
- Amp: open the current Usage page from the menu dashboard action. Thanks @3kh0!
- Browser cookies: stop automatic Chromium-family probes after the first Safe Storage denial, while keeping an explicit Refresh retry available (#1952). Thanks @CoreyCole!
- Claude: keep yearless reset dates in the upcoming year when a quota crosses New Year's Day. Thanks @devYRPauli!
- Claude web: preserve fractional session and weekly utilization instead of displaying it as zero or unavailable. Thanks @devYRPauli!
- Gemini: detect Google's consumer-tier shutdown response and offer an explicit Antigravity handoff without changing ordinary auth failures or enabling fallback automatically. Thanks @Yuxin-Qiao!
- Gemini: use the real Flash quota in menu-bar metrics when an account has no Pro quota. Thanks @devYRPauli!
- Ollama API: describe rejected keys as invalid or revoked, matching Ollama's current key lifecycle. Thanks @joeVenner!
- Settings: keep Language, Default Terminal, and Refresh cadence selectors interactive on macOS 27.
- Usage formatting: show every positive sub-1% value as `<1%` instead of rounding values above 0.5% up to `1%`. Thanks @devYRPauli!
- Codex menu: hide error-only optional Credits and OpenAI web setup diagnostics while keeping them visible in provider Settings.
- Codex quotas: show the session quota as unavailable while an exhausted weekly limit is still binding, including menu-bar icons and widgets. Thanks @Yuxin-Qiao!
- Codex cost history: reuse cached aggregate pricing and one pricing catalog across daily and project reports, carry fresh cache state across launches, and treat unpriced models as migrated, avoiding repeated row scans, filesystem work, and duplicate background scans on large local histories.
- Devin: keep exact 1% usage from being inflated to 100% while preserving fractional fallback quota semantics. Thanks @Lex-ic-on!
- Kimi K2: reject invalid and out-of-range numeric timestamps while preserving valid second and millisecond values. Thanks @joeVenner!
- Kimi K2: reject non-finite credit and token values before they reach menus, CLI output, or widgets. Thanks @joeVenner!
- Kimi: call the current `GetSubscriptionStats` membership endpoint so the Monthly subscription quota is populated again. Thanks @skyzer!
- Kimi: show the five-hour rate limit before the weekly quota while preserving existing menu-bar metric preferences. Thanks @Zihao-Qi!
- Menu bar: detect Tahoe's blocked no-window state at startup when macOS still records the icon as enabled, so affected users receive recovery guidance instead of a silently missing icon (#1945). Thanks @mmyyfirstb!

## 0.40.0 — 2026-07-05

### Added
- Claude: show opt-in read-only claude-swap accounts as stacked usage cards without delaying ambient refreshes. Thanks @optimiz-r!
- Claude: switch inactive claude-swap accounts directly from their stacked usage cards and refresh usage immediately.
- Codex dashboard: show calendar-correct raw Today and 30-day credit totals without converting credits to billed dollars. Thanks @avenoxai!
- Cost charts: show visible, unit-safe scale labels across detailed history, inline menus, and widgets. Thanks @FNDEVVE!
- Cursor: read the signed-in app token on Linux, with explicit manual-cookie web-source support and XDG config paths. Thanks @DonnieFi!
- Devin: show remaining extra-usage balance in menus, CLI, and widgets while respecting optional-usage visibility. Thanks @FNDEVVE!
- Widgets: make Mistral available in provider selection and switching. Thanks @joeVenner!

### Changed
- Settings: keep the sidebar fixed and visible while resizing, prevent collapse or over-expansion, and cap detail content width for readability. Thanks @Zihao-Qi!
- Debug builds: add a compact `D` beside menu-bar icons and identify them as CodexBar Debug in tooltips and accessibility.
- Usage bars: distinguish full-height quota-warning thresholds from subtle workday-boundary markers. Thanks @Alekstodo!

### Fixed
- Codex cost history: reuse one pricing catalog while building project rollups and carry fresh cache state across launches, avoiding repeated filesystem work and duplicate background scans on large local histories.
- Providers: detect Claude Desktop on fresh installs and ignore Gemini CLI installations without usable OAuth credentials.
- Claude cost history: include nested Claude Desktop local-agent logs while preserving current Code/Cowork coverage through the shared `~/.claude/projects` store. Thanks @Zihao-Qi!
- Claude: give multiple claude-swap accounts precedence over token-account cards and segmented switching so adapter rows remain visible. Thanks @optimiz-r!
- Menus: scope manual refresh state to the provider being refreshed, allowing independent provider refreshes without greying unrelated rows. Thanks @hhh2210!
- Claude history: quarantine same-directory account-switch samples until credential ownership is stable, preventing plan-utilization history from crossing accounts. Thanks @ss251!
- Language picker: keep language names readable in their native form and make System follow macOS without removing unrelated overrides. Thanks @Zihao-Qi!
- Reset times: preserve minute precision in long day-scale countdowns when there are no whole hours, while keeping countdowns compact to two units. Thanks @konon4!
- Mistral: reject non-finite and overflowing credit balances before they can reach menu, CLI, or widget formatting. Thanks @joeVenner!

## 0.39.0 — 2026-07-04

Syncs the Mac app to upstream CodexBar **v0.39.0** (spanning v0.38.0–v0.39.0)
and pairs it with iOS **1.17.0**. This is one combined upstream-sync release
for the current upstream-sync issue set, keeping the provider additions,
settings redesign, menu/provider fixes, and iOS compatibility work together.

### Added / Improved

- **New upstream providers** — Sakana AI, Qoder, CrossModel, and ClawRouter are
  included in the Mac provider registry, diagnostics, status/menu rendering,
  and the fork's iCloud sync path.
- **iOS provider parity** — The companion app now registers the new providers
  for quota-transition zones, provider colors, synthetic test data, and detail
  pages. CrossModel gets a typed optional sync payload for wallet balance,
  uncollected spend, and day/week/month usage windows.
- **Cost sync bridge** — CrossModel native spend maps into `SyncCostSummary`,
  so iOS Cost views can include it without requiring a CloudKit schema change.
- **Settings sync preservation** — The upstream Settings `NavigationSplitView`
  redesign is merged while preserving the fork's Mobile pane and iCloud sync
  controls.
- **Mock QA coverage** — Mac mock sync now emits 69 synthetic providers across
  59 IDs, including the v0.38/v0.39 provider set for iPhone layout and
  compatibility testing.

### Compatibility

- CloudKit stays in the Production environment. No CloudKit Dashboard deploy is
  expected for this release because the sync changes are additive optional
  fields inside the existing compressed provider payload.
- The 2 Mac x 2 iPhone old/new compatibility gate and substituted evidence are
  tracked in `CodexBarMobile/Research/037-v039-upstream-sync/03-testing.md`.

### 中文说明

同步 Mac 端到上游 CodexBar **v0.39.0**（覆盖 v0.38.0–v0.39.0），并配套 iOS
**1.17.0**。本次把当前 upstream-sync issue 集合合并为一个版本，避免把 provider
新增、Settings 改版、菜单/provider 修复和 iOS 兼容工作拆散。

### 新增 / 改进

- **新增上游 provider** —— Sakana AI、Qoder、CrossModel、ClawRouter 已纳入 Mac
  provider registry、诊断、状态/menu 渲染，以及 fork 的 iCloud sync 路径。
- **iOS provider 对齐** —— companion app 为新 provider 补齐 quota-transition zone、
  provider 颜色、合成测试数据和详情页；CrossModel 通过可选 typed payload 显示钱包余额、
  待结算金额和 day/week/month 用量。
- **Cost sync bridge** —— CrossModel 原生 spend 会映射为 `SyncCostSummary`，
  iOS Cost 视图无需 CloudKit schema 变更即可纳入它。
- **Settings sync 保留** —— 合并上游 Settings `NavigationSplitView` 改版，同时保留
  fork 的 Mobile pane 和 iCloud sync 控件。
- **Mock QA 覆盖** —— Mac mock sync 现在推送 69 个 synthetic provider、覆盖 59 个 ID，
  包含 v0.38/v0.39 provider 集，用于 iPhone 布局和兼容测试。

### 兼容性

- CloudKit 保持 Production 环境。本次 sync 变更只是既有压缩 provider payload 内的可选字段，
  预期不需要 CloudKit Dashboard deploy。
- 2 Mac x 2 iPhone 新旧版本兼容 gate 与替代证据记录在
  `CodexBarMobile/Research/037-v039-upstream-sync/03-testing.md`。

---

## 0.37.2.1 (Mobile 1.15.0 · build 92.1) — 2026-06-23 — upstream v0.37.2 sync

Syncs the Mac app to upstream CodexBar **v0.37.2** (spanning v0.37.0–v0.37.2)
and pairs it with the next iOS train, **1.15.0**. This is one combined
upstream-sync release for issues #30, #32, and #33; it intentionally does not
split the v0.37 provider, widget, security, diagnostics, and menu reliability
work into separate user-visible versions.

### Added / Improved

- **New Mac widgets** — Codex and Claude burn-down widgets now include
  single-window and combined session/weekly views for faster quota planning.
- **Provider data improvements** — Bedrock can show rolling 14-day CloudWatch
  activity, Mistral adds Vibe monthly-plan usage, Cursor separates personal
  on-demand spend from shared team pool, Codex can expose configured profile
  homes as switchable accounts, and Codex OAuth accounts can show manual reset
  credits with expiry.
- **Diagnostics and CLI visibility** — provider diagnostics can be exported as
  redacted reports with platform/app-version context, and the CLI server reports
  its startup build version from `/health`.
- **Security hardening** — Codex OAuth credentials are refreshed with private
  file permissions, and unsafe endpoint overrides are rejected before attaching
  credentials for Deepgram, z.ai, Xiaomi MiMo, and Azure OpenAI.
- **Menu and performance fixes** — refresh stays in-place while the menu remains
  open, provider cards align with the Overview layout, memory-pressure callbacks
  avoid actor-isolation crashes, idle WebViews and rebuildable caches are trimmed
  safely, and release packages are smaller.
- **iOS 1.15 readiness** — the companion app will use this release train for any
  new mobile-side rendering or compatibility support required by the v0.37 Mac
  data. The already-reviewing iOS 1.14 release remains separate.

### Compatibility

- CloudKit stays in the Production environment. Schema deploy decisions and the
  2 Mac x 2 iPhone old/new compatibility gate are tracked in
  `CodexBarMobile/Research/033-v037-upstream-sync/03-testing.md`.
- Provider-display values are expected to stay inside the existing compressed
  provider payload or existing quota-transition record path unless the v0.37
  payload audit records an explicit optional-field addition.

### 中文说明

同步 Mac 端到上游 CodexBar **v0.37.2**（覆盖 v0.37.0–v0.37.2），并配套下一条
iOS 发布线 **1.15.0**。本次把 issue #30、#32、#33 覆盖的上游内容合并为一个用户可见版本，
不把 v0.37 的 provider、widget、安全、诊断和菜单可靠性改动拆成多次发布。

### 新增 / 改进

- **新的 Mac widget** —— Codex 与 Claude burn-down widget 支持单窗口和 session/weekly
  组合视图，方便判断 quota 消耗节奏。
- **Provider 数据增强** —— Bedrock 可显示 14 天 CloudWatch 活动，Mistral 增加 Vibe
  月度套餐用量，Cursor 区分个人按需消费和团队共享池，Codex 可把显式配置的 profile home
  作为账号切换，并显示 OAuth 手动重置额度及到期时间。
- **诊断与 CLI 可见性** —— provider 诊断可导出带平台/app 版本上下文的脱敏报告；
  CLI server 的 `/health` 会报告启动时的 build version。
- **安全加固** —— Codex OAuth 凭据刷新后使用私有文件权限；Deepgram、z.ai、Xiaomi MiMo
  与 Azure OpenAI 的不安全 endpoint override 会在附加凭据前被拒绝。
- **菜单与性能修复** —— 刷新时菜单保持打开并原地显示进度，provider card 对齐 Overview
  布局，memory-pressure callback 避免 actor-isolation crash，空闲 WebView 和可重建缓存会安全释放，
  release 包体积也更小。
- **iOS 1.15 准备** —— companion app 会用 1.15 发布线承接 v0.37 Mac 数据所需的新渲染或兼容支持；
  已在 review 的 iOS 1.14 保持独立。

### 兼容性

- CloudKit 保持 Production 环境。schema deploy 判断以及 2 Mac x 2 iPhone 新旧版本兼容 gate
  记录在 `CodexBarMobile/Research/033-v037-upstream-sync/03-testing.md`。
- Provider 展示值预期继续保留在现有压缩 provider payload 或既有 quota-transition record 路径中；
  如 v0.37 payload 审计需要新增可选字段，会在 Research 中单独记录。

---

## 0.36.1.1 (Mobile 1.13.0 · build 88.1) — 2026-06-16 — upstream v0.36.1 sync

Syncs the Mac app to upstream CodexBar **v0.36.1** (spanning v0.36.0–v0.36.1)
and pairs it with iOS **1.13.0**. This is one combined upstream-sync release
for issue #28; it intentionally does not split LiteLLM, Poe, Chutes, Zed, and
the Antigravity/provider reliability fixes into separate user-visible versions.

### Added / Improved

- **New upstream providers** — LiteLLM personal/team budget tracking, Poe point
  balance and recent history, Chutes subscription/quota/pay-as-you-go tracking,
  and Zed editor-session plan/quota/billing-cycle tracking.
- **iOS provider readiness** — the mobile companion is prepared to recognize and
  render the new provider data that arrives through the existing Mac → CloudKit
  sync payload. Provider credentials and live API/Keychain access remain Mac-only.
- **iOS 1.13.0 direct train** — the companion release folds in the unreleased
  1.12.0 sync work as well, including MiniMax renewal/expiration metadata,
  Devin quotas, Copilot budget windows, MiMo balance/token-plan updates, Kimi
  Code API usage, and rolling-upgrade preservation of rich provider details.
- **Antigravity accuracy** — quota summaries now prefer current local app/CLI
  sources, group Gemini and Claude + GPT session/weekly windows, and preserve
  structured reset timestamps for localized display.
- **Menu bar reliability** — upstream fixes stale open-menu values, provider
  switcher background, hosted submenu refresh timing, subprocess pipe hangs, Kiro
  helper cleanup, Gemini package discovery, and bounded optional provider work.
- **Configuration and localization** — Mac config resolution now honors absolute
  `XDG_CONFIG_HOME` while preserving legacy paths, and upstream Mac resources
  expand to the 21-language catalog. iOS remains on this fork's required
  English, Simplified Chinese, Traditional Chinese, and Japanese localizations.
- **Provider polish** — Ollama uses the official icon, Copilot exposes shared
  reset dates for limited windows, OpenCode Go handles Zen balances without a
  subscription window, and the website/provider gallery gains LiteLLM, Poe,
  Chutes, Zed, Devin, and T3 Chat assets.

### Compatibility

- CloudKit stays in the Production environment. Schema deploy decisions and the
  2 Mac x 2 iPhone old/new compatibility gate are tracked in
  `CodexBarMobile/Research/030-v036-upstream-sync/03-testing.md`.
- New provider values are expected to stay inside the existing compressed
  provider payload or existing quota-transition record path. Existing iOS builds
  should ignore unrecognized optional payload fields.

### 中文说明

同步 Mac 端到上游 CodexBar **v0.36.1**（覆盖 v0.36.0–v0.36.1），并配套 iOS
**1.13.0**。本次把 issue #28 覆盖的上游内容合并为一个用户可见版本，不把
LiteLLM、Poe、Chutes、Zed 和 Antigravity/provider 稳定性修复拆成多次发布。

### 新增 / 改进

- **新增上游 provider** —— LiteLLM 个人/团队 budget、Poe 积分余额和近期历史、Chutes
  订阅/quota/pay-as-you-go 用量，以及 Zed 编辑器 session 的套餐、quota、账期和逾期发票状态。
- **iOS provider 准备** —— mobile companion 会识别并渲染通过现有 Mac → CloudKit 同步
  payload 传来的新 provider 数据；provider 凭证、API 请求和 Keychain/editor session 仍只在 Mac 端处理。
- **iOS 1.13.0 直接发布线** —— companion release 同时合入未单独发布的 1.12.0 同步工作，
  包括 MiniMax 续费/到期元数据、Devin 配额、Copilot budget 窗口、MiMo 余额与 token-plan 更新、
  Kimi Code API 用量，以及滚动升级时保留丰富 provider 详情。
- **Antigravity 准确性** —— quota summary 优先使用当前本地 app/CLI 来源，按 Gemini 与
  Claude + GPT 的 session/weekly 窗口分组，并保留结构化 reset timestamp 用于本地化显示。
- **菜单栏可靠性** —— 合入打开菜单时数值原地刷新、provider switcher 背景、submenu 刷新时序、
  子进程 pipe hang、Kiro helper 清理、Gemini package discovery 和可选 provider enrichment 超时边界修复。
- **配置与本地化** —— Mac config resolution 支持绝对 `XDG_CONFIG_HOME` 并保留 legacy 路径；
  上游 Mac 资源扩展到 21 语言。iOS 仍按本 fork 规则保持 English、简体中文、繁体中文、日文四语言。
- **Provider polish** —— Ollama 使用官方图标，Copilot 显示 limited window 的共享 reset date，
  OpenCode Go 在无订阅窗口时仍显示 Zen balance，网站/provider gallery 加入 LiteLLM、Poe、Chutes、
  Zed、Devin 和 T3 Chat 资产。

### 兼容性

- CloudKit 保持 Production 环境。schema deploy 判断以及 2 Mac x 2 iPhone 新旧版本兼容 gate
  记录在 `CodexBarMobile/Research/030-v036-upstream-sync/03-testing.md`。
- 新 provider 值预期保留在现有压缩 provider payload 或既有 quota-transition record 路径中；
  旧 iOS build 应安全忽略不认识的可选字段。

---

## 0.35.0.1 (Mobile 1.12.0 · build 85.1) — 2026-06-14 — upstream v0.35.0 sync

Syncs the Mac app to upstream CodexBar **v0.35.0** (spanning v0.32.5–v0.35.0) and ships the paired iOS **1.12.0** companion. This is one combined upstream-sync release; it intentionally folds the open upstream-sync issues for v0.32.5, v0.33.0, v0.34.0, and v0.35.0 into a single user-visible version.

### Added / Improved

- **New upstream providers and data paths** — Devin daily/weekly quota tracking, Copilot billing budget windows, MiMo balance/token-plan improvements, Kimi Code API key usage, and MiMo local session-log fallback.
- **MiniMax on iPhone** — subscription renewal/expiration dates now sync as additive optional metadata and render on the iOS provider card when Mac sends them.
- **Menu bar reliability and performance** — upstream fixes for merged-provider menu flicker, delayed switching, tracking-session stalls, shortcut handling, layout stability, and open-menu refresh behavior.
- **Provider accuracy** — upstream fixes for Antigravity, Cursor, Grok, OpenAI API pagination, Amp, Doubao, Bedrock, Claude pricing/cache behavior, and provider endpoint security validation.
- **Localization** — upstream adds French, Ukrainian, Dutch, Vietnamese, Japanese, German, Korean, and Turkish Mac localizations.
- **iOS bridge preparation** — Mac sync payloads and iOS compatibility handling are updated for the upstream fields that matter to the mobile companion, with old/new device matrix testing recorded in Research.

### Compatibility

- CloudKit stays in the Production environment. Any wire/schema decision and the 2 Mac x 2 iPhone old/new compatibility gate are tracked in `CodexBarMobile/Research/029-v035-upstream-sync/03-testing.md`.
- Existing iOS builds safely ignore fields they do not understand; iOS 1.12.0 is the paired build for the complete v0.35.0 data set.

### 中文说明

同步 Mac 端到上游 CodexBar **v0.35.0**（覆盖 v0.32.5–v0.35.0），并配套发布 iOS **1.12.0**。本次把当前 open 的 v0.32.5、v0.33.0、v0.34.0、v0.35.0 upstream-sync issue 合并为一个用户可见版本，不拆多次发布。

### 新增 / 改进

- **新增上游 provider 与数据通道** —— Devin 每日/每周配额、Copilot billing budget、MiMo 余额与 token-plan 改进、Kimi Code API key 用量、MiMo 本地 session-log fallback。
- **MiniMax on iPhone** —— 订阅续费/到期日期现在作为可选同步元数据传到 iOS，并在 Mac 发送这些字段时显示在 provider 卡片上。
- **菜单栏可靠性和性能** —— 合入上游针对合并 provider 菜单闪烁、切换延迟、tracking-session 卡顿、快捷键、布局稳定性和打开菜单刷新行为的修复。
- **Provider 准确性** —— 合入 Antigravity、Cursor、Grok、OpenAI API 分页、Amp、Doubao、Bedrock、Claude 定价/cache 行为和 provider endpoint 安全校验修复。
- **本地化** —— 合入上游 Mac 端 French、Ukrainian、Dutch、Vietnamese、Japanese、German、Korean、Turkish 语言支持。
- **iOS 同步准备** —— 针对 mobile companion 需要展示或兼容的上游字段更新 Mac sync payload 与 iOS 兼容处理；新旧设备矩阵测试记录在 Research 中。

### 兼容性

- CloudKit 保持 Production 环境。wire/schema 判断以及 2 Mac x 2 iPhone 新旧版本兼容 gate 记录在 `CodexBarMobile/Research/029-v035-upstream-sync/03-testing.md`。
- 旧 iOS build 会安全忽略无法识别的新字段；iOS 1.12.0 是完整 v0.35.0 数据集的配套版本。

---

## iOS 1.11.1 (build 151) — 2026-06-06 — Daily Spend chart scroll fix (iOS-only; Mac unchanged at 0.32.4.1)

iOS-only patch on top of 1.11.0. The Cost tab's **Daily Spend** chart now shows a ~30-day viewport and scrolls horizontally through the full accumulated history (50 / 90 / 365-day windows) instead of cramming every day into one non-scrollable screen. No Mac change — Mac stays at 0.32.4.1. Re-versioned from the unreleased build 150 because iOS 1.11.0 (build 149) is already in App Store review.

### 中文说明

仅 iOS 的补丁，叠加在 1.11.0 之上。「费用」标签的「每日支出」图表现在显示约 30 天的视口，并可横向滚动浏览完整的已积累历史（50 / 90 / 365 天窗口），不再把所有天数挤在一屏里无法滚动。Mac 端无变化，仍为 0.32.4.1。因 iOS 1.11.0（build 149）已在 App Store 审核中，故从未发布的 build 150 重新定版为 1.11.1。

## 0.32.4.1 (Mobile 1.11.0 · build 79.1) — 2026-06-03 — upstream v0.32.4 sync

Syncs the Mac app to upstream CodexBar **v0.32.4** (spanning 0.32.0–0.32.4) and ships the paired iOS **1.11.0** companion. A refinement + reliability batch — no new providers; the visible wins are quieter, more accurate provider data that flows through to iPhone automatically.

### Fixed / Improved

- **Antigravity** quota rows are cleaner — image / lite / autocomplete / internal noise rows no longer skew the summary bar (#1209).
- **Copilot** zero-entitlement business tokens no longer show a misleading usage percentage (#1258).
- **Augment** usage parses correctly again after the upstream `auggie` status-format change, with a browser-cookie fallback (#1224).
- **Claude** keeps the last good web-usage snapshot through a brief Unauthorized refresh instead of blanking, and delegates the CLI OAuth refresh token so CodexBar stops forcing re-logins (#1220, #1239).
- **Codex cost** scanner rewrite (faster scans, new fast-JSON path) — the on-disk cost cache is invalidated and re-scanned so Codex and Claude cost cards reflect the new parser.
- Plus upstream menu-bar, OpenAI Web, and notarization-path hardening for macOS 26.
- **iOS** — new provider search at the top of the Usage list (filter by name) for easier navigation of a long synced provider list.

### Compatibility

- No wire-format, schema, or CloudKit change. Mixing app versions across Macs and iPhones stays safe — the refinements arrive once Mac is on 0.32.4.

### 中文说明

同步 Mac 端到上游 CodexBar **v0.32.4**（覆盖 0.32.0–0.32.4），并配套发布 iOS **1.11.0**。本批以精修 + 可靠性为主，无新增 provider；可见收益是更干净、更准确的 provider 数据，并自动同步到 iPhone。

### 修复 / 改进

- **Antigravity** 配额行更干净 —— image / lite / autocomplete / internal 噪声行不再干扰汇总进度条（#1209）。
- **Copilot** zero-entitlement 商业 token 不再显示误导性用量百分比（#1258）。
- **Augment** 在上游 `auggie` 状态格式变更后用量重新正确解析，并增加浏览器 cookie fallback（#1224）。
- **Claude** 短暂 Unauthorized 刷新期间保留最后有效的 web 用量快照而不清空，并把 CLI 的 OAuth refresh token 委托出去，避免强制重登（#1220、#1239）。
- **Codex 成本** 扫描器重写（更快、新增 fast-JSON 路径）—— 失效并重扫磁盘成本缓存，使 Codex 与 Claude 成本卡反映新 parser。
- 以及上游菜单栏、OpenAI Web、公证路径加固（macOS 26）。
- **iOS** —— Usage 列表顶部新增 provider 搜索（按名称过滤），同步的 provider 多时更好找。

### 兼容性

- 无 wire / schema / CloudKit 变更。Mac 与 iPhone 间混用版本安全 —— 待 Mac 升级到 0.32.4 后这些精修即到达。

---

## 0.31.0.2 (Mobile 1.10.0 · build 73.2) — 2026-06-02 — cost-cache invalidation hotfix

Hotfix on top of 0.31.0.1: forces the Codex and Claude cost-usage caches to re-scan after the v0.31.0 parser update, so cost cards show the new parser's numbers instead of stale cached attributions.

### Fixed

- **Cost caches now re-scan after the v0.31.0 parser update** — the upstream merge rewrote the Codex and Claude cost-usage scanner, but neither cache-invalidation axis was rolled, so upgrading users kept the old parser's cached cost attributions. Bumped `parserLogicVersion` and regenerated the parser-source hash so every Codex and Claude cost cache is invalidated and re-scanned on next launch. Codex was already covered by the scanner-hash axis (its value changed across the upgrade); this closes the Claude gap — Claude has no producer-key axis and relies solely on the pricing fingerprint.

### Compatibility

- No wire-format, schema, or CloudKit change. iOS app code is identical to build 145; iPhone build 146 is a version bump to pair with this Mac hotfix. Mixing app versions across Macs and iPhones stays safe.

### 中文说明

0.31.0.1 的热修复：v0.31.0 合并重写了 Codex 与 Claude 的成本扫描器，但两条缓存失效轴都没滚动，导致升级用户的成本卡仍显示旧 parser 的缓存归因。本次 bump `parserLogicVersion` 并重生成 parser 源码 hash，强制所有 Codex 与 Claude 成本缓存在下次启动时失效并重扫。Codex 原本已被 scanner-hash 轴覆盖（其值在升级间已变化）；本次补齐 Claude —— Claude 没有 producer-key 轴，只依赖定价 fingerprint。无 wire / schema / CloudKit 变更，iOS app 代码与 build 145 完全一致，手机端 build 146 仅为配套 Mac 热修复的版本号 bump。

---

## 0.31.0.1 (Mobile 1.10.0 · build 73.1) — 2026-05-30 — upstream v0.31.0 + iOS 1.10.0

Syncs the Mac app to upstream CodexBar **v0.31.0** (spanning 0.29.1–0.31.0) and ships the paired iOS **1.10.0** companion.

### Highlights — Mobile 1.10.0

- **DeepSeek** now shows web-session usage + cost on iOS — today / this-month tokens, spend, and request counts beside the balance.
- **Codex Spark** (5-hour + weekly) and **Antigravity** per-model quota lanes now sync through to iOS.
- **Cost cards** display request counts and the correct currency (EUR / CNY), not just USD.
- Upstream fixes flow through automatically: Claude Enterprise extra-usage amount (no longer 100× too high), Grok / Ollama window labels + pace projection, and the Claude "Design" lane folded into the main Claude limit.

### Compatibility

- Mixing app versions across Macs and iPhones is safe — older iPhones ignore the new fields and older Macs simply don't send them. No crashes or data loss across any new/old device combination.

### CodexBar v0.29.1–v0.31.0 (Upstream)

- Codex Spark model usage, Antigravity per-model quotas, DeepSeek usage summaries, OpenAI project-scoped Admin API, Ollama pace projection, Bedrock AWS-profile auth, Swedish + Brazilian-Portuguese localization, plus numerous menu-bar and stability fixes for macOS 26.5.

### 中文说明

同步 Mac 端到上游 CodexBar **v0.31.0**（覆盖 0.29.1–0.31.0），并配套发布 iOS **1.10.0**。iOS 新增 DeepSeek 用量+成本卡；Codex Spark 与 Antigravity 分模型配额条同步到手机；成本卡显示请求数与正确币种；上游的 Claude 企业版金额、Grok/Ollama 窗口与配速、Claude Design 合并等修复自动透传。任意新旧设备混用同步均安全。

---

## 0.29.0.1 (Mobile 1.9.0 · build 68.1) — 2026-05-27 — upstream v0.29.0 + iOS 1.9.0

Syncs the Mac app to upstream CodexBar v0.29.0 and ships the paired iOS 1.9.0 companion. Three new providers — Azure OpenAI, Alibaba Token Plan (Bailian), and T3 Chat — plus the upstream v0.28.0 + v0.29.0 fixes.

### New providers

- **Azure OpenAI** — validate a deployment via API key, endpoint, and deployment name.
- **Alibaba Token Plan (Bailian)** — monthly token-plan quota via browser or manual cookies.
- **T3 Chat** — web-session usage with a 4-hour base window and a monthly overage window; paste a full browser cURL if a cookie-only refresh hits a 429 challenge.

### Also from upstream

- Codex cost history now splits standard vs fast spend/token usage in model breakdowns.
- OpenCode / OpenCode Go show workspace renewal dates.
- Ollama can authenticate with an API key as an alternative to browser cookies.
- Plus the upstream v0.28/v0.29 menu-bar, Codex, Antigravity, and localization fixes.

### Compatibility

- Mixing app versions across Macs and iPhones is safe — older iPhones ignore the new providers and older Macs simply don't send them. No crashes or data loss across any new/old device combination.

### Required versions

- iPhone companion: iOS 1.9.0 (build 139), via TestFlight / App Store.
- This Mac build: 0.29.0.1 (fork build 68.1). Update both for the full feature set.

### 中文说明

同步 Mac 端到上游 CodexBar v0.29.0，并配套发布 iOS 1.9.0。本次新增三个 provider —— Azure OpenAI、Alibaba Token Plan（百炼）和 T3 Chat —— 外加上游 v0.28.0 + v0.29.0 的修复。

### 新增 provider

- **Azure OpenAI** —— 通过 API key、endpoint 和部署名称校验部署。
- **Alibaba Token Plan（百炼）** —— 通过浏览器或手动 cookie 跟踪每月 token 套餐额度。
- **T3 Chat** —— web session 用量，含 4 小时基础窗口和每月超额窗口；若 cookie 刷新遇到 429 挑战，可粘贴完整的浏览器 cURL。

### 同样来自上游

- Codex 费用历史现在区分标准 / 快速的消费和 token 用量。
- OpenCode / OpenCode Go 显示工作区续费日期。
- Ollama 可用 API key 作为浏览器 cookie 之外的认证方式。
- 以及上游 v0.28/v0.29 的菜单栏、Codex、Antigravity 和本地化修复。

### 兼容性

- 在 Mac 和 iPhone 间混用新旧版本是安全的 —— 旧 iPhone 会忽略新 provider，旧 Mac 干脆不发送。任意新 / 旧设备组合都不会崩溃或丢数据。

### 所需版本

- iPhone 配套：iOS 1.9.0（build 139），经 TestFlight / App Store。
- 本 Mac 版本：0.29.0.1（fork build 68.1）。两边都更新才能用全套功能。

---
## 0.32.4 — 2026-06-02

### Fixed
- Menu bar: avoid queuing redundant provider refreshes when opening a fresh merged-menu dropdown, while still retrying missing or stale provider data after menu tracking ends (#1235, #1277). Thanks @hhh2210!

## 0.32.3 — 2026-06-02

### Fixed
- Menu bar: stop forcing a private preferred-position value for fresh status items; suspicious stored positions are now cleared so AppKit can place CodexBar normally on macOS 26 / 5K displays (#1267). Thanks @AdrianSimionov, @kirocop, and @Yuxin-Qiao!
- Menu bar: cache provider brand icons so merged-icon status updates no longer repeatedly parse SVG assets on the main thread during hover/open animations (#1235, #1274). Thanks @andradebruno, @xingpz2008, and @Yuxin-Qiao!
- Copilot: treat GitHub Copilot Business token-billing zero-entitlement quotas as unavailable instead of showing misleading 0% used usage (#1258, #1270). Thanks @devYRPauli!
- Menu bar: prepare closed menus after refresh and only reuse stale dropdown content for data-refresh invalidations so merged menu opens stay responsive without bypassing privacy or structure changes (#1261). Thanks @ProspectOre!
- OpenAI Web: stop reloading away from login and Cloudflare blocking states so the dashboard WebView does not loop on route corrections (#1259). Thanks @ProspectOre!

## 0.32.2 — 2026-06-01

### Added
- QA: document the live CodexBar e2e flow and add a redacted provider-matrix helper for packaged CLI smoke tests.

### Fixed
- Menu bar: add breathing room to compact Codex account rows so the provider, account, status, and plan labels no longer hug the row edges.
- Performance: make Codex token-cost scanning faster and more memory-efficient on large local session corpora.

## 0.32.1 — 2026-05-31

### Fixed
- Claude: keep Claude CLI-owned OAuth refresh tokens delegated to Claude Code when CLI storage is present, preventing CodexBar from consuming rotating refresh tokens and forcing re-login (#1161, #1239). Thanks @RajvardhanPatil07!
- Menu bar: reuse short-lived Codex account reconciliation snapshots so repeated menu rebuilds do not reread local auth state on every open.
- Menu bar: defer automatic provider refreshes until after AppKit menu tracking ends so opening the dropdown no longer starts work that can freeze focus and keyboard input.
- Menu bar: suppress background keychain and OpenAI dashboard work during startup/menu tracking so the dropdown stays clickable without macOS keychain prompts or WebKit memory spikes.

## 0.32.0 — 2026-05-31

### Added
- Settings: add search to the Providers pane so large provider lists can be filtered by name or id (#1184). Thanks @046081-dotcom!

### Fixed
- Augment: parse the updated `auggie account status` output format, fall back to browser cookies when CLI parsing fails, and restore session cookie detection (#1224). Thanks @bcharleson!
- Amp/Ollama: require HTTPS before reattaching imported browser cookies on provider redirects to avoid cleartext cookie exposure (#1226). Thanks @Hinotoi-agent!
- Antigravity: filter noisy remote OAuth per-model quota rows, keep consumed noisy rows detail-only, and prevent image/lite/autocomplete/internal rows from driving summary bars (#1209). Thanks @guhyun9454!
- Claude: preserve the last good Claude Web usage snapshot across transient Unauthorized refresh failures while still surfacing repeated auth failures (#1220). Thanks @LeoLin990405!
- CLI: avoid executing a same-user mutable temporary installer script across the macOS administrator privilege boundary (#1222). Thanks @Hinotoi-agent!
- Codex: cancel OpenAI WebKit dashboard refreshes promptly and avoid an immediate second background WebView retry after timeouts, reducing launch-time Web Content CPU spikes (#1217).
- Menu: refresh open Codex menu adjuncts as dashboard, credits, token-cost, and plan-history data become ready after cold start (#1150). Thanks @AmrMohamad!
- Menu bar: defer background parent-menu rebuilds until AppKit menu tracking ends so late-arriving usage data cannot stall dropdown hover on macOS 26.5 (#1227).
- Menu bar: give CodexBar status items stable placement identities while preserving existing upgrade placement state (#1216). Thanks @pdurlej!
- Release: isolate notarization API keys and upload ZIPs in a private per-run temporary directory instead of predictable shared /tmp paths (#1228). Thanks @Hinotoi-agent!
- Status: retry startup refreshes a few times after transient offline/network failures so provider status can recover after macOS brings the network online (#1211).

## 0.31.0 — 2026-05-28

### Changed
- Docs: update the Homebrew install command to use the official `codexbar` cask now that it supports Intel Macs (#1189). Thanks @SSakutaro!
- Tests: document and audit that routine validation must not trigger macOS Keychain prompts.
- Localization: localize popup panels and provider settings UI across supported languages (#1181). Thanks @jack24254029!
- Localization: complete Brazilian Portuguese coverage so pt-BR no longer falls back to English for new UI strings (#1188). Thanks @ManuzimFerreira!

### Added
- AWS Bedrock: support resolving usage and cost-history credentials from a named AWS profile via the AWS CLI (#1190). Thanks @oleksandr-soldatov!
- Codex: show Codex Spark model-specific usage as an optional extra quota lane (#1195, fixes #1177). Thanks @LeoLin990405!
- Localization: add Swedish as a selectable app language (#1186). Thanks @yeager!

### Fixed
- CLI: bound `codexbar serve` requests with a configurable timeout and coalesce concurrent cache misses so hung `/usage` callers no longer stampede provider refreshes (#1208). Thanks @enieuwy!
- Claude: add Opus 4.8 to the built-in pricing fallback so stale models.dev caches still show token cost (#1214, fixes #1210). Thanks @devYRPauli!
- Codex: preserve authorized web dashboard credits-only snapshots instead of treating missing usage windows as a failed refresh (#1206, fixes #1204). Thanks @soumikbhatta!
- Cost history: make token-cost JSONL scans cancellation-aware so quitting, forced refreshes, and account switches can stop stale scans sooner.
- Codex: show Spark 5-hour and weekly usage as separate quota lanes in Codex breakdowns (#1201).
- Codex: show captured `codex login` output when managed Add Account fails so users can recover from account-selection or OAuth failures (#1199). Thanks @chapati23!
- Claude: hide the obsolete Design quota lane now that Claude Design shares the main Claude usage limit (#1197).
- Menu bar: coalesce visible-menu rebuilds and reduce hover highlight work so the dropdown stays responsive on macOS 26.5 (#1196).

## 0.30.1 — 2026-05-28

### Changed
- CLI: make `codexbar diagnose` use a generic safe provider diagnostic export for all providers, with MiniMax details attached only as provider-specific metadata.

### Fixed
- Settings: add trailing breathing room to provider-sidebar controls (#1183). Thanks @Yuxin-Qiao!
- Claude: treat OAuth usage HTTP 429s as rate limits, preserve cached credentials, and back off background retries while still allowing manual refresh (#1179). Thanks @LeoLin990405!
- Menu bar: stop repeated display-change status-item recreation from corrupting Control Center or confusing menu bar managers (#1176, fixes #1175). Thanks @diazdesandi!

## 0.30.0 — 2026-05-27

### Added
- MiniMax: add a redacted diagnostic CLI export for safe issue reports (#1128). Thanks @Yuxin-Qiao!
- Antigravity: show the complete per-model quota breakdown alongside the existing summary lanes (#1139). Thanks @guhyun9454!
- Widget: show tertiary usage rows for providers that expose a third quota lane (#1160). Thanks @LeoLin990405!
- DeepSeek: show optional web-session usage and cost summaries alongside the balance card (#1166). Thanks @Yuxin-Qiao!
- OpenAI: scope Admin API usage to the configured project and keep token accounts from inheriting stale project filters (#1168). Thanks @mstallone!

### Fixed
- App shutdown: detach status items, close tracked menus, and cancel menu tasks before quit so Dock autohide stays responsive on macOS 26.5 (#1174). Thanks @jskoiz!
- Widgets: package the macOS widget as a real Xcode app-extension target so WidgetKit descriptors load on macOS 26.5 (#1095). Thanks @jamesjlopez!
- Menu: render quota-warning markers as subtle inset ticks instead of full-height bars (#1149).
- Codex: show sign-in guidance when the Codex CLI is logged out instead of reporting a temporary usage outage (#1171, fixes #1170). Thanks @jskoiz!
- Menu bar: clear stale hidden macOS status-item visibility defaults once before creating CodexBar items (#1169).
- StepFun: refresh expired Oasis tokens and persist recovered manual sessions. Thanks @LeoLin990405!
- Release: prevent manual CLI artifact builds from publishing or clobbering release assets (#1154). Thanks @jskoiz!
- Cost history: route OpenAI and Mistral API spend through the shared cost-history cards, including OpenAI request counts (#1163). Thanks @LeoLin990405!
- Menu: keep provider switcher Cmd-number and arrow shortcuts working while the open menu is tracking events (#1157, fixes #1156 and #1144). Thanks @anirudhvee!
- Codex: prevent fork token replay from overcounting corrected cumulative session totals (#1164). Thanks @xx205!
- Alibaba Token Plan: update usage refreshes to the Bailian subscription-summary endpoint (#1142). Thanks @YanxinXue!
- Ollama: show pace projections for documented 5-hour session and 7-day weekly usage windows (#1136). Thanks @bdamokos!
- Localization: polish Simplified Chinese wording and add notification strings (#1165). Thanks @fanfanci!
- Localization: improve Traditional Chinese wording and localize notification copy (#1158). Thanks @jack24254029!
- Localization: improve Simplified Chinese visible menu, dashboard, and usage labels (#1145). Thanks @Yuxin-Qiao!

## 0.29.1 — 2026-05-26

### Added
- Integrations: list the Noctalia/Quickshell Codex usage plugin in the Linux CLI integrations (#1115). Thanks @rayoplateado!
- Display: add optional workday markers for weekly progress bars (#1102). Thanks @Yuxin-Qiao!
- Localization: add Traditional Chinese (`zh-Hant`) app strings. Thanks @ilyaliao!

### Fixed
- Claude: classify Claude CLI 2.1 subscription-only `/usage` output separately and fall back to direct CLI usage when the PTY panel fails to load (#1121, fixes #1116). Thanks @Yuxin-Qiao!
- Provider switcher: keep multi-row account/provider controls compact so large menus stay within bounds (#1113). Thanks @Yuxin-Qiao!
- Grok: label usage bars from the actual reset window instead of the remaining reset distance (#1148). Thanks @kiankyars!
- Config: keep legacy credentials when migrated config changes fail to save so retry can recover them (#1146). Thanks @RajvardhanPatil07!
- Codex: avoid overcounting forked sessions when parent logs are missing while still counting incremental usage (#1143). Thanks @jskoiz!
- Groq: show a distinct Groq provider icon instead of reusing the Grok glyph (#1112). Thanks @kiankyars!
- Claude: normalize OAuth extra-usage spend limits from minor units so Enterprise spend displays as currency instead of 100x too high (#1114, fixes #1111). Thanks @Yuxin-Qiao!
- Menu bar: preserve status item identity during display-change recovery so menu bar managers do not treat CodexBar as a new hidden item (#1122, fixes #1109). Thanks @lederniermagicien!
- OpenAI: retry transient Admin API usage failures once before surfacing an access error (#1117).
- OpenCode Go: read local usage history before falling back to browser-cookie dashboard fetches (#1021). Thanks @sopenlaz0!
- Menu bar: show extra-usage spend as currency text for Claude and Cursor when that metric is selected (#1107). Thanks @Yuxin-Qiao!
- Codex: run regular credits and OpenAI dashboard refreshes in the background while coalescing overlapping refresh work (#1078). Thanks @ptstory!

## 0.29.0 — 2026-05-22

### Added
- Cost history: show Codex standard and fast spend/token splits in model breakdowns (#1070). Thanks @iam-brain!
- Alibaba Token Plan: add Bailian token-plan quota tracking via browser or manual cookies (#1098). Thanks @YanxinXue!
- OpenCode: show workspace renewal dates for OpenCode and OpenCode Go usage windows (#1099). Thanks @Yuxin-Qiao!

### Fixed
- Localization: improve Simplified Chinese settings and menu translations (#1059). Thanks @narallee!
- Alibaba Token Plan: reject non-HTTPS endpoint overrides and keep the provider building on Linux (#1104). Thanks @YanxinXue!
- Settings: avoid crashing when API key or cookie settings contain only a single quote character (#1106). Thanks @m1qaweb!
- Build scripts: derive the local development signing team ID from the certificate OU before falling back to the CN suffix (#1095).
- Menu bar: keep retrying display-change recovery when macOS leaves status items detached from the current screen (#1077, #1088).
- Codex: preserve last successful per-account quota snapshots when later network or DNS refreshes fail (#1097, #1101). Thanks @Yuxin-Qiao!

## 0.28.0 — 2026-05-22

### Added
- Ollama: add API key authentication as an alternative to browser cookies for validating Cloud access (#1044). Thanks @nandorocker!
- Azure OpenAI: add deployment-status validation via API key, endpoint, and deployment settings (#1045). Thanks @ZenoRewn!
- Localizations: add Spanish and Catalan language packs and fill missing localization keys (#1041). Thanks @seifreed!
- Providers: T3 Chat - add web-session usage tracking, can paste a full browser cURL when cookie-only refreshes hit a 429 challenge (#1091). Thanks @Quicksaver!

### Fixed
- Menu: restore full-width provider switcher quota bars and refresh them while the menu stays open (#1094). Thanks @bcharleson!
- Codex: accept the first click in the account switcher inside menu popovers (#1079). Thanks @ptstory!
- Codex/Claude: terminate PTY child process trees during probe cleanup so wrapper-launched CLI descendants do not linger after sessions finish (#1085). Thanks @mickobizzle!
- MiniMax: exclude explicitly failed billing-history records from token charts and model/method totals (#1089). Thanks @Yuxin-Qiao!
- OpenAI: parse Wednesday and Saturday dashboard reset lines so rate-limit reset times are not dropped on those days (#1080). Thanks @m1qaweb!
- Localization: translate provider-detail labels and empty states when Simplified Chinese is selected (#1051). Thanks @wang93wei!
- Antigravity: discover OAuth credentials from the bundled extension language server in newer IDE builds so Add Account works again (#1076). Thanks @xARSENICx!
- Menu bar: suppress redundant icon observer work during refresh cycles, reducing icon update passes without changing rendered state (#1081). Thanks @ptstory!
- Menu bar: wait for display changes to settle before recovering status items and retry if macOS still leaves the icon detached (#1074). Thanks @yipjunkai!
- Menu: keep lower action rows stable when Refresh is highlighted or pressed (#1071). Thanks @MadanChaollaPark!
- Linux CLI: avoid linking JetBrains provider parsing against `libxml2.so.2`, improving compatibility with newer distros that ship libxml2 2.15+ (#1046). Thanks @semsemyonoff!
- Claude: remove the obsolete peak-hours indicator and setting now that Anthropic no longer applies peak-hour limits (#1023). Thanks @rohitjavvadi!
- Antigravity: verify cloud model lists that report every quota as full against the user quota endpoint before showing remote OAuth usage (#1063). Thanks @devpras22!
- Codex: avoid recounting repeated local token snapshots when total usage has not changed (#1062). Thanks @BarryYangi!
- Antigravity: discover OAuth clients from Antigravity 2 app bundles and binary artifacts so Add Account works again (#1053). Thanks @vyctorbrzezowski!
- Codex: honor the explicit OAuth credits source and keep automatic credits refresh falling back to CLI when OAuth usage has no credits (#1054). Thanks @soumikbhatta!
- Codex: show missing-CLI installation guidance in app and CLI errors without dropping cached-refresh context (#1030). Thanks @rohitjavvadi!
- LLM Proxy: parse fractional-second quota reset timestamps from API responses (#1022). Thanks @rohitjavvadi!
- ElevenLabs: keep progress text legible in light mode (#1055). Thanks @vyctorbrzezowski!
- Claude: detect loading-only CLI usage screens and give CLI-only auto refreshes one longer retry instead of stalling or reporting a false missing-session error (#1032, fixes #1031). Thanks @rohitjavvadi!
- OpenAI: avoid serializing the full dashboard DOM during normal web refreshes, reducing CPU and memory churn while preserving account and plan detection (#1034, fixes #1033). Thanks @jb510!
- Codex: skip macOS-blocked Codex CLI candidates during automatic binary resolution and let CLI auto mode use OAuth before falling back to `codex app-server` (#1038, fixes #1028). Thanks @m-rokai!
- Codex: wait for explicit Refresh to finish token-cost history before rebuilding open menus, while keeping automatic/menu-open refreshes non-blocking (#1040). Thanks @zhulijin1991!
- Antigravity: detect the new 2.0 unsuffixed `language_server` process so local IDE usage probing works again (#1049). Thanks @urbanonymous!
- Claude: prevent headless CLI usage probes from creating Claude Code URL Handler apps in Launchpad (#1047).
- Codex: invalidate local cost-history caches from the scanner source hash so parser fixes rebuild stale cached rows automatically (#1042). Thanks @hhh2210!
- Release: update Homebrew automation so CodexBar releases publish both the CLI formula and app cask from the same workflow.

## 0.27.0 (Mobile 1.8.0 · build 65.5) — 2026-05-25 — upstream v0.27.0 + iOS 1.8.0

Syncs the Mac app to upstream CodexBar v0.27.0 and ships the paired iOS 1.8.0 companion. Five brand-new providers, five existing-provider detail upgrades, account-aware quota notifications, and a Codex workspace + weekly-pace badge — all in one release.

### New providers

- **Grok (xAI)** — monthly USD spend, plan tier badge, percent used, and renewal date.
- **ElevenLabs** — character credits plus standard and professional voice-slot counts.
- **Deepgram** — speech / agent / total hours, request count, agent tokens, and TTS characters.
- **GroqCloud** — live request / token / cache-hit-per-minute rates for Enterprise keys.
- **LLM Proxy** — aggregate usage across all upstream providers with per-credential pool health.

### Existing providers — richer detail

- **Claude Admin API** — today / 7-day / 30-day spend, top models, and top cost items when an `sk-ant-admin…` key is configured in Preferences.
- **Claude Extra usage** — spend-limit utilization gauge for Enterprise and Team plans.
- **OpenAI API** — configurable 1–365 day cost-history window, with a range picker on the iPhone dashboard.
- **OpenCode Go** — Zen workspace pay-as-you-go USD balance.
- **MiniMax** — 30-day billing history with a token chart and top method / model breakdown.
- **Kiro** — overage credit count and estimated cost when your monthly plan is exhausted.

### Quota notifications now name the account

- Push notifications on multi-account providers include the triggering account — e.g. "Codex · admin@example.com" instead of bare "Codex". Honours the Hide-personal-info privacy setting.

### Codex workspace + weekly pace

- When your active Codex account belongs to an OpenAI workspace, the workspace name shows on the Codex detail page along with a weekly-pace arrow (ahead of / on / under pace).

### Compatibility

- Mixing app versions across Macs and iPhones is safe — an older iPhone ignores the new fields and an older Mac simply doesn't send them. No crashes or data loss across any new/old device combination.

### Required versions

- iPhone companion: iOS 1.8.0 (build 137), via TestFlight / App Store.
- This Mac build: 0.27.0 (fork build 65.5). Update both for the full feature set.

### 中文说明

同步 Mac 端到上游 CodexBar v0.27.0，并配套发布 iOS 1.8.0。本次一口气带来 5 个全新 provider、5 个现有 provider 的详情升级、带账号的额度推送通知，以及 Codex 工作区 + 周用量节奏徽章。

### 新增 provider

- **Grok (xAI)** —— 每月美元消费、套餐徽章、使用百分比、续费日期。
- **ElevenLabs** —— 字符额度，外加标准语音槽和专业语音槽数量。
- **Deepgram** —— 语音 / 智能体 / 总时长、请求数、智能体 token、TTS 字符数。
- **GroqCloud** —— 企业版 key 的实时每分钟请求 / token / 缓存命中速率。
- **LLM Proxy** —— 跨所有上游 provider 的聚合用量，含每个凭证的池健康度。

### 现有 provider 详情升级

- **Claude Admin API** —— 配置 `sk-ant-admin…` key 后显示今天 / 7 天 / 30 天花费、主要模型、主要费用项。
- **Claude 额外用量** —— 企业版 / Team 套餐的花费上限使用率仪表。
- **OpenAI API** —— 可配置 1–365 天的费用历史窗口，iPhone 仪表盘带范围选择器。
- **OpenCode Go** —— Zen 工作区按量付费美元余额。
- **MiniMax** —— 30 天计费历史，含 token 柱状图和主要接口 / 模型分解。
- **Kiro** —— 月度套餐耗尽后显示超额信用数和预估费用。

### 额度通知现在带上账号

- 多账号 provider 的推送通知会带上触发的账号 —— 例如「Codex · admin@example.com」而非单纯的「Codex」。遵守「隐藏个人信息」隐私开关。

### Codex 工作区 + 周节奏

- 当激活的 Codex 账号属于某个 OpenAI 工作区时，Codex 详情页会显示工作区名称，并配一个周用量节奏箭头（超前 / 正常 / 落后）。

### 兼容性

- 在你的 Mac 和 iPhone 间混用新旧版本是安全的 —— 旧 iPhone 会忽略新字段，旧 Mac 干脆不发送。任意新 / 旧设备组合都不会崩溃或丢数据。

### 所需版本

- iPhone 配套：iOS 1.8.0（build 137），经 TestFlight / App Store。
- 本 Mac 版本：0.27.0（fork build 65.5）。两边都更新才能用全套功能。

---

## 0.27.0 — 2026-05-18 (upstream)

### Added
- Usage charts: reuse the OpenAI API inline dashboard for local Codex/Claude/Vertex/Bedrock cost history, OpenRouter day/week/month spend, z.ai hourly tokens, and Mistral daily spend.
- Usage history: let OpenAI Admin API charts and local cost-history scans use a configurable 1–365 day window instead of a fixed 30 days (#83).
- Grok: add xAI Grok provider support with local identity detection and billing decoding for the Grok CLI integration (#965). Thanks @taibaran!
- ElevenLabs: add API-key usage tracking for subscription credits, reset time, and voice-slot limits.
- Deepgram: add API-key usage tracking with project discovery and speech/agent usage breakdowns (#1003, fixes #994). Thanks @czjzpz!
- GroqCloud: add API-key usage tracking for Enterprise Prometheus metrics with request, token, and cache-hit rate summaries (#993).
- LLM Proxy: add API-key quota-stats support for aggregate proxy usage, key health, spend, provider breakdowns, and reset windows (#264).
- Claude: add an Anthropic Admin API source and allow `sk-ant-admin...` keys in Claude token accounts for API spend/token tracking (#966).
- MiniMax: add web-session billing-history summaries with 30-day token charts and top model/method breakdowns (#1007).
- OpenCode Go: show the optional Zen pay-as-you-go balance from the workspace dashboard alongside subscription windows (#1006).
- Kiro: add overage-credit and overage-cost menu bar display modes for exhausted plans (#972). Thanks @raflyazf!
- CLI: add `codexbar config set-api-key` for safely storing provider API keys from stdin.
- CLI: add `codexbar config providers`, `enable`, and `disable` for scripting the same provider toggles used by Settings.
- CLI: let `--all-accounts` and `codexbar serve` export every visible Codex account instead of only the selected account (#1019).
- Permissions: notify when a provider probe detects a macOS/browser permission prompt waiting for user action (#456).
- Quota warnings: include the triggering account in notification copy when personal info is visible (#973). Thanks @raflyazf!
- Website: replace provider-letter tiles with brand logos, add light/dark landing-page themes, and collapse OpenCode/OpenCode Go into one company entry (#989). Thanks @pasangimhana!
- Providers: route app-owned provider HTTP calls through a shared transport seam for cleaner proxy and test support (#892). Thanks @serezha93!

### Fixed
- Codex: make local cost-history scans faster and more stable for large session archives while preserving fork attribution, priority pricing, and cached history windows.
- Codex: collapse near-duplicate session and weekly plan-utilization history windows so charts no longer show repeated tabs (#1027). Thanks @ngutman!
- Multi-account menus: fetch stacked Codex/token-account usage concurrently so account switchers stay responsive with many accounts (#1011).
- Codex: keep local cost history attributed to the correct model when long or oversized `turn_context` rows precede model-less token events (#1014, fixes #1013). Thanks @hhh2210!
- Codex: prefer per-event token usage over divergent total counters when scanning local cost history, preventing large false cost spikes (#968). Thanks @Ifan24!
- Claude: de-duplicate copied fork/resume transcript history by provider response identity so local cost estimates do not overcount repeated rows (#1002). Thanks @Neverdie-2!
- Codex: improve multi-account switching with quota-aware ordering, workspace grouping, persisted per-account snapshots, health labels, and auth fingerprint matching.
- Codex: improve managed account login recovery guidance when macOS blocks or moves a stale `codex` CLI to Trash (#977).
- Codex: show weekly pace reserve details in the menu even when the caller did not precompute pace data (#1009). Thanks @zhulijin1991!
- Overview: expose provider chart and storage detail submenus from overview rows instead of requiring a provider-tab switch first.
- Claude: reset stuck CLI sessions after usage probe timeouts, give slow probes longer to render, and keep stale data visible across transient timeouts.
- Claude: keep the last successful usage card visible across transient probe timeouts while still clearing stale data after Claude auth changes.
- Claude: keep Team and Personal Max plan-utilization history separate when the same email appears on multiple Claude accounts (#213).
- Claude: label Extra usage denominators as the monthly cap so recharge balances are not confused with the maximum spend limit (#975).
- Claude: wait for the CLI usage panel to finish rendering after the Current session label so slow Claude Code builds do not produce false "Missing Current session" errors (#959).
- Claude: label five-hour session pace as "Projected empty" so it is not confused with the reset countdown (#960).
- Claude: show Enterprise spend-limit usage in automatic menu bar metrics and expose the Extra usage metric picker when spend data is available (#964).
- Grok: retry transient web billing timeouts once and allow slower billing RPCs to finish before showing an error.
- Grok: fall back to grok.com's billing endpoint when `grok agent stdio` omits the xAI billing method (#984). Thanks @bcharleson!
- OpenAI: shorten the provider label to "OpenAI" so the menu tab no longer clips.
- OpenAI: accept numeric-string Admin API cost amounts so usage does not fail when `/v1/organization/costs` returns `"amount": { "value": "12.50" }` (#999, #1000). Thanks @SergeyLavrentev!
- Menu: keep provider switcher buttons centered by moving quota indicators out of the button layout.
- Menu: rebuild the selected provider content after switching tabs while an overview chart submenu is open.
- Menu: keep the persistent Refresh row at a fixed height while highlighted or pressed so nearby items no longer jump (#1001).
- Menu bar: avoid re-reading provider credentials, Codex account state, Claude terminal probe text, and storage footprints on hot menu paths, reducing idle CPU while providers are still loading.
- Menu bar: skip unchanged split-provider icon redraws and avoid an extra animation-state scan during blink ticks.
- Menu bar: recover visible status items after the display hosting the menu bar item is unplugged (#998, fixes #997). Thanks @Llldmiao!
- Menu bar: recreate status items on startup when macOS reports them visible but never attaches a menu bar button/window (#988).
- MiniMax: show Coding Plan model-remains quotas as used/limit cards and include weekly text-generation quota windows (#970). Thanks @Yuxin-Qiao!
- Ollama: let automatic session import fall back from Chrome to Safari, Comet, and the rest of the browser import order when Chrome has no Ollama session (#962).
- Kimi K2: label the legacy provider as unofficial and remove links that presented the legacy endpoint as an official Kimi account surface (#967, fixes #473). Thanks @mturac!
- CLI: use explicit provider HTTP timeouts so blocked network connections fail instead of leaving usage commands stuck for days (#1005, fixes #1004). Thanks @msmolkin!
- CLI: reject non-loopback `Host` headers in `codexbar serve` before serving local usage and cost metadata (#995). Thanks @rohitjavvadi!
- Packaging: skip slow widget App Intents metadata during dev restarts and preserve the previous app bundle if required metadata generation times out.
- Localization: fall back to English when a bundled localized string is blank instead of rendering empty menu/settings text (#952). Thanks @xiaoqianWX!
- Settings: localize the provider storage usage toggle in the Advanced pane (#985, fixes #971). Thanks @tanish19078!

---

## 0.26.4 (Mobile 1.7.0 · build 63.4) — 2026-05-18 — Phase G hotfix: decouple CloudKit sync from Mac menu layout

> Patch on top of 63.3 fixing a user-reported regression where iPhone
> still showed only 1 OpenAI card despite 63.3 shipping the universal
> multi-account mechanism. Root cause was orthogonal to Phase G —
> upstream's `shouldFetchAllTokenAccounts` gated the per-account
> fan-out on `multiAccountMenuLayout == .stacked`. Users on the
> default `.segmented` layout had only their *active* token-account
> fetched, so `accountSnapshots[provider]` ever contained one entry,
> so SyncCoordinator only ever pushed one snapshot to CloudKit even
> after the Phase G universalization. iPhone was blameless — Mac
> wasn't sending the other accounts.
>
> Fix: when `iCloudSyncEnabled` is true, ignore the menu-layout gate
> and fan-out unconditionally (subject to the existing count > 1 and
> catalog-membership guards). Mac-only users (no iCloud sync) keep
> upstream's API-frugality behavior: segmented layout fetches just
> the active account, stacked fetches all. The menu layout choice
> stays a local Mac UI ergonomics decision; it no longer dictates
> what reaches iPhone.

### Mac

- `UsageStore.shouldFetchAllTokenAccounts(provider:accounts:)` now
  short-circuits to `true` when `settings.iCloudSyncEnabled == true`
  (after the catalog + count > 1 guards). Mac-only users see no
  behavior change.
- New `Tests/CodexBarTests/ShouldFetchAllTokenAccountsTests.swift`
  (9 tests, all green) pins both branches: iCloud-on always fans out
  for multi-account providers; iCloud-off preserves upstream's
  layout-gated behavior. Includes a regression case for the exact
  scenario reported (OpenAI + 2 admin keys + segmented + iCloud-on).

### iOS

- No iOS-side code change. The Phase G UI shipped in 63.3 was
  correct; it just never received the second snapshot. Hotfix is
  Mac-only; iOS 1.7.0 build 130 (already on TestFlight) consumes
  the now-correct snapshot stream automatically.

### CloudKit deploy

No schema deploy needed. Hotfix is consumer-side gating logic only.

### Notes
- `version.env`: `MARKETING_VERSION=0.26.4`, `BUILD_NUMBER=63.4`, `MOBILE_VERSION=1.7.0`, `UPSTREAM_VERSION=v0.26.1`, `UPSTREAM_SYNC_DATE=2026-05-18`.
- Tag name: `v0.26.4-mobile.1.7.0` (new release). Per [[docs/versioning.md]] rule: BUILD `63.y` ↔ MARKETING `0.26.y`. `0.26.3` is intentionally skipped because BUILD `63.3` was incorrectly shipped as MARKETING `0.26.2`; aligning forward instead of relabeling history.

---

## 0.26.2 (Mobile 1.7.0 · build 63.3) — 2026-05-18 — universal multi-account mechanism (Phase G)

> Fork-only patch on top of upstream v0.26.1. **No Mac UI deltas
> beyond what v0.26.1 already shipped** — the Mac menu's per-provider
> account-tab switcher (e.g., OpenAI admin keys) already worked. The
> change in this release is two-sided plumbing so iPhone finally
> mirrors that Mac UX: catalog-driven multi-account sync fan-out
> (Mac → CloudKit) plus a generic account-tab UI inside iOS provider
> detail pages.

### Mac

- `SyncCoordinator.tokenBasedMultiAccountProviders` is now a computed
  property reading `TokenAccountSupportCatalog.allProviders` (single
  source of truth). Fan-out now covers all 18 token-account providers
  instead of the prior hardcoded 11 — silently fixes 7 providers
  (openai, deepseek, antigravity, manus, copilot, venice, stepfun)
  whose extra accounts were never reaching iOS via CloudKit.
- New `Tests/CodexBarTests/TokenAccountSyncCoverageTests.swift` —
  pins the catalog⇔sync-list equality so future upstream-added token
  providers automatically flow through; missing-mirror cases fail
  the build instead of silently losing multi-account on iPhone.
- `MockProviderInjector` +7 second-tab simple mocks (one per Phase G
  provider above) so the iOS multi-account tab UI is exercised
  end-to-end via the mock-injection toggle. Total mock count 45 → 52.
- Localized `mobile_toggle_mock_subtitle` updated to reflect the new
  52/42/44 count.

### iOS (pairs with the same 1.7.0 marketing version, build 130)

- Universal `ProviderAccountGroup` model — groups post-merge snapshots
  by providerID. Mac multi-account providers now show **one row** in
  the iOS Usage list (with a `· N` count badge) instead of N separate
  rows.
- `ProviderDetailView` segmented account-tab bar at the top when the
  group has 2+ accounts. Tab labels prefer email local-part →
  loginMethod → `Account N`. Tapping a tab re-renders all the
  existing cards (rate windows, cost, OpenAI Dashboard, daily chart,
  Phase B typed cards) against the selected account's data —
  mirroring Mac's "click into provider, switch between admin tabs"
  flow.
- See `CodexBarMobile/CHANGELOG.md` for the iOS-side detail.

### CloudKit deploy

Per pre-release audit (`docs/cloudkit-deploy-audit.md`): **no schema
deploy needed**. Phase G is 100% consumer-side — Mac pushes more
records of the existing `DeviceProviderSnapshot` type; iOS renders
the post-merge snapshot list with grouping. No new record types, no
new fields outside the existing zlib-compressed `payload: Data`,
no new indexes or zones.

### Notes
- `version.env`: `MARKETING_VERSION=0.26.2`, `BUILD_NUMBER=63.3`, `MOBILE_VERSION=1.7.0`, `UPSTREAM_VERSION=v0.26.1`, `UPSTREAM_SYNC_DATE=2026-05-18`.
- Tag name: `v0.26.2-mobile.1.7.0`. Release branch: `mobile-dev`.
- Naming scheme: see `docs/versioning.md`.

---

## 0.26.1 (Mobile 1.7.0 · build 63.2) — 2026-05-18 — upstream v0.26.0/v0.26.1 fold-in + iOS 1.7.0 pairing

> Fork release that **tracks upstream v0.26.1 exactly** for the
> Mac-visible feature set (no Mac UI deltas beyond what upstream
> shipped). Pairs with the freshly-published **iOS 1.7.0** which
> renders six new dedicated provider cards (Kiro / Bedrock /
> Moonshot / z.ai hourly chart / OpenAI Admin Dashboard / Antigravity
> multi-account) plus two new settings toggles via the Shared iCloud
> envelope extensions in this release. End-to-end verified via mock
> injection before publish: all 6 new cards render correctly on
> iPhone with the typed data Mac pushes through CloudKit.

### Mac changes folded in (all from upstream)
- Sync upstream v0.26.0 + v0.26.1 in full (Kiro credits, Antigravity multi-account, OpenRouter spend, AWS Bedrock provider, Moonshot/Kimi API, z.ai hourly chart, OpenAI Admin API Dashboard, Brazilian Portuguese, quota-warning marker toggle, provider changelog links setting).
- `Sources/CodexBarCore/Sync/AccountIdentityComputer` + `SyncCoordinator.isModelEstimated()` extended for new providers `moonshot` and `bedrock` (fork-private wiring, no Mac UI change).
- `Sources/CodexBar/Sync/MockProviderInjector` extended to emit Moonshot + Bedrock mocks (43 → 45 synthetic providers).
- Cost cache invalidation: codex `v5 → v6` (adopts upstream's bump; supersedes fork 0.23.1 hotfix); claude/vertex stay at fork's `v3`.

### Mobile bridge — Shared envelope extensions (no user-visible Mac change)
- `Shared/Models/UsageSnapshot.swift` adds six optional `decodeIfPresent` fields so a future iOS 1.7 reader can pick up the data without a wire-format break:
  - `openAIAPIDashboard: SyncOpenAIAPIDashboard?` — Today/7d/30d summaries + daily breakdown + top models / line items.
  - `zaiHourlyUsage: SyncZaiHourlyUsage?` — per-model hourly token series.
  - `kiroCredits: SyncKiroCredits?` — plan + credits + bonus + expiry countdown.
  - `bedrockCost: SyncBedrockCost?` — monthly spend + budget + region.
  - `moonshotBalance: SyncMoonshotBalance?` — account balance + region + last-updated.
  - `antigravityAccounts: SyncMultiAccountList?` — OAuth account list + active index (Mac stub for now).
- `Shared/iCloud/CloudConstants.providerPayloadVersion` deliberately NOT bumped (additive optional fields).
- Mac `SyncCoordinator` populates the new fields whenever upstream's per-provider snapshot carries the corresponding data.
- Bedrock region & Moonshot balance flow through dedicated paths (Mac `SettingsStore.bedrockRegion` plumb-through, loginMethod parser) — not the composite display strings — so iOS reads the actual values, not the menu copy.

### iOS pairing
- Pairs with **iOS 1.7.0** (build 129); see `CodexBarMobile/CHANGELOG.md`. iOS 1.7.0 renders six new dedicated provider cards driven by the typed envelope fields. iOS 1.6.0 (126) on TestFlight remains forward-compatible — `decodeIfPresent` makes the new keys invisible to it.

### Notes
- `version.env`: `MARKETING_VERSION=0.26.1`, `BUILD_NUMBER=63.2`, `MOBILE_VERSION=1.7.0`, `UPSTREAM_VERSION=v0.26.1`, `UPSTREAM_SYNC_DATE=2026-05-18`.
- Tag name: `v0.26.1-mobile.1.7.0`. Release branch: `mobile-dev`.
- Naming scheme: see `docs/versioning.md`.

---

## Upstream v0.26.0 / v0.26.1 — 2026-05-15

Folded into fork 0.26.1 (above). Original upstream release notes:

### Upstream v0.26.1 — 2026-05-15

**Added**
- OpenAI API: show Admin API usage inline with Today/7d/30d summaries, a 30-day spend graph, and an interactive detail chart for daily spend, tokens, and requests.
- CLI: add `codexbar serve` for localhost JSON access to usage and cost endpoints (#957). Thanks @ThiagoCAltoe!

**Fixed**
- OpenCode Go: block cross-host redirects when fetching usage so imported cookies cannot follow external redirect targets (#969). Thanks @pavbar!
- Codex: keep background `/status` probes out of Codex Desktop history by using isolated non-persistent CLI storage (#953).
- Menu: stabilize the Cost submenu by using a native menu item and deferring open-menu rebuilds while tracking (#954). Thanks @getogrand!
- Localization: add Brazilian Portuguese quota-warning settings strings (#958). Thanks @ThiagoCAltoe!

### Upstream v0.26.0 — 2026-05-15

**Added**
- Codex: add tiered long-context and Fast/Priority pricing to local cost history using local app-server priority traces (#917). Thanks @iam-brain!
- Kiro: show account/auth details, plan labels, credit and bonus-credit balances, overage state, and Kiro-specific menu bar display options (#933, fixes #934). Thanks @solnikhil!
- Antigravity: add Google OAuth token-account switching with selected-account refresh persistence (#937, fixes #936). Thanks @hhh2210!
- OpenRouter: show daily and weekly API key spend from `/api/v1/key` in the menu (#685). Thanks @ThiagoCAltoe!
- Display: add a setting to hide quota-warning tick marks on usage bars while keeping quota warning notifications active (#918, fixes #916). Thanks @ThiagoCAltoe!
- Menu: add left/right arrow keyboard navigation for the merged provider switcher (#266).
- Menu: add an opt-in setting for provider changelog links, starting with Codex, Claude Code, and Gemini CLI (#929, fixes #660). Thanks @ThiagoCAltoe!
- AWS Bedrock: add Cost Explorer usage and monthly budget tracking (#897). Thanks @afalk42!
- Kilo: add organization selection, scoped organization fetches, and stacked Kilo usage cards (#920). Thanks @NoeFabris!
- Moonshot / Kimi API: add API-key balance tracking, CLI support, docs, and menu bar balance copy (#899). Thanks @giuseppebisemi!
- z.ai: add an hourly per-model token usage chart in the menu (#913). Thanks @n1majne3!
- Localization: add Brazilian Portuguese translations (#902). Thanks @ThiagoCAltoe!
- Localization: add Simplified Chinese translations for Claude peak-hour labels (#921). Thanks @whtis!

**Fixed**
- Codex: show authenticated plan/account rows as "Limits not available" instead of a red no-rate-limit error when Codex reports profile data but no rate-limit windows yet.
- Overview: hide provider rows that only contain an error, and avoid showing a one-item Codex System Account submenu.
- Menu: disable implicit provider-switcher layer animations and reuse the deferred rebuild path so open menus stay stable under pointer movement (#950).
- Menu: defer account-switcher menu rebuilds so switching Codex or token accounts does not send the open menu into a flicker loop (#946, fixes #944). Thanks @kubahasek!
- Menu: avoid rebuilding visible menus during background open-menu refreshes so hover submenus stay responsive (#923, fixes #909). Thanks @AmrMohamad!
- Codex: scope local cost history to the selected managed account's `CODEX_HOME` and label cost cards as local-log estimates (#910).
- Cost history: label local log totals as API-rate estimates in menu cards, charts, and CLI output (#926). Thanks @yashiels!
- Cursor: open Add Account in the user's browser and import the resulting browser session instead of trapping login in an embedded web view (#922).
- Claude: handle Enterprise and organization spend-limit usage across OAuth/web accounts, including null session quota windows, inline spend-limit usage, `extra_usage`-only responses, and token-account Org ID support (#925, #941, fixes #940). Thanks @clintandrewhall!
- OpenCode Go: let automatic cookie import scan all supported browser sources instead of Chrome only (#665).
- Copilot: preserve over-quota usage so paid overage can show above 100% instead of clamping to exhausted (#818).
- Codex: pause background CLI launches after macOS blocks or quarantines `codex`, avoiding repeated "Malware Blocked" prompts (#942).
- Claude: clarify that local cost/token estimates include cache read/write tokens and may differ from Claude Code `/status` (#781, #787).
- Updates: make the restart/apply-update menu action use Sparkle's prepared install callback on the first click (#947). Thanks @velvet-shark!
- Multi-account menus: keep stacked token-account cards capped to current accounts and ignore stale snapshots from removed accounts (#949).
- Droid: accept pasted Factory `Authorization: Bearer` headers and bearer tokens for manual sessions when cookies alone are insufficient (#914).
- Menu bar: detect when macOS Tahoe hides CodexBar behind the new Allow in Menu Bar setting and show recovery guidance (#945, fixes #890). Thanks @pdurlej!
- CLI: route Claude token-account `--source cli` reads through the selected OAuth/session credential so `--all-accounts` no longer relabels ambient CLI usage (#403).
- Codex: route menu account refreshes through the resolved live-vs-managed account source so matched accounts keep using the stable `CODEX_HOME` (#932, fixes #931). Thanks @ThiagoCAltoe!
- Gemini: refresh OAuth credentials when the CLI has a refresh token but no cached access token instead of reporting "not logged in" after authentication (#915).
- Gemini: label OAuth-backed API fetches as `oauth-api` instead of plain `api` (#930). Thanks @ThiagoCAltoe!
- Codex: keep session and weekly quota-warning marker thresholds independent so usage bars do not duplicate marker lines (#938, fixes #927). Thanks @iam-brain!
- Codex: coalesce historical pace reset timestamps into 5-minute buckets so dashboard and live reset jitter do not duplicate weekly history windows (#901). Thanks @zhulijin1991!
- Menu: middle-truncate long account emails in Codex account controls and keep the Codex account switcher visible during merged-menu refreshes with transient account snapshots.
- Settings: apply the selected app language from packaged SwiftPM resources instead of falling back to English when the `.lproj` directory casing differs (#908).
- Settings: let stale managed Codex account records be removed even when their stored home path is outside CodexBar's managed-home directory, and keep CLI known-owner tests from writing fixtures into the live app store.
- ChatGPT credits: restrict purchase links to real HTTPS `chatgpt.com` settings/usage/billing/credits paths and drop query/fragment data (#903). Thanks @ThiagoCAltoe!
- z.ai: show the MCP quota bucket as monthly instead of a misleading 1-minute window (#904). Thanks @ThiagoCAltoe!
- Kimi: rebalance provider icon alignment within its viewBox (#912). Thanks @giuseppebisemi!
- Release: include macOS platform and architecture in notarized app and dSYM asset names (#164).
- Upstream tooling: resolve remote default branches and tolerate missing upstream remotes in review scripts (#906).

---

## 0.25.2 — 2026-05-15 — Mac quota warnings now push to iPhone

Mac quota warning notifications can now also be pushed to your iPhone (previously, only depletion / restoration triggered a push). Requires iOS 1.6.0+.

# 中文

Mac 的配额警告通知现在也可以推送到 iPhone 上（之前只有耗尽 / 恢复才会推送）。需配合 iOS 1.6.0+。

---

## 0.25.1 — 2026-05-12 — Mobile fork's first 0.25.1 release (folds v0.24 / v0.25 / v0.25.1)

**0.25.1-mobile.1.5.3** folds three upstream releases (v0.24, v0.25, v0.25.1) into one Mac build, plus a small zh-Hans / en translation gap fix our audit caught.

### What's new

- **11 new providers** — Windsurf, Codebuff, DeepSeek, Manus, MiMo, Qwen, Doubao, Command Code, StepFun, Crof, Venice, plus OpenAI API balance tracking.
- **Simplified Chinese** localization with in-app language selector.
- **Quota warning notifications** — opt-in alerts at configurable thresholds (e.g. 80%) for session and weekly quota windows.
- **Codex multi-account switcher** — stacked or segmented layout in the menu bar.
- **Codex cost attribution fix** — GPT-5.4 / GPT-5.5 sessions no longer bucket under GPT-5.
- **MiniMax** multi-service quota cards (text / speech / image / video / music).
- **Copilot multi-account** + Claude peak-hours indicator + Storage usage view.
- **VoiceOver** labels across the menu bar.

### Fixes

- Settings / About no longer crashes on packaged-app launch (SwiftPM bundle lookup).
- Codex hung RPC reads time out instead of looping; menu reopen behaves as a true toggle.
- Cursor Enterprise / Team usage displays correctly (was reporting 100% remaining).
- macOS 26.4 menu bar icon visible again.
- Pi session cost cache rebuilds automatically after pricing changes.
- Simplified Chinese peak-hours strings (`off_peak`, `peak_ends_in`, `off_peak_peak_in`) and English `not_found` fallback translated (fork hotfix).

### iOS compatibility

Wire format unchanged. Compatible with iOS 1.5.0+. iOS clients without native UI for the new providers show them as fallback (blue) cards; a future iOS release will add native rendering. No iOS update required for this Mac build.

---

# 中文

**0.25.1-mobile.1.5.3** 一次性合入上游三个版本（v0.24、v0.25、v0.25.1），并附带一个 zh-Hans / en 翻译补缺。

### 新功能

- **11 个新 provider** —— Windsurf、Codebuff、DeepSeek、Manus、Xiaomi MiMo、Qwen、Doubao、Command Code、StepFun、Crof、Venice，加 OpenAI API balance 跟踪。
- **简体中文** 本地化 + 应用内语言选择器。
- **配额警告通知** —— session / 周额度按可配置阈值（例如 80%）提醒，可选开启。
- **Codex 多账号切换器** —— 菜单栏堆叠 / 分段两种布局。
- **Codex 成本归因修复** —— GPT-5.4 / GPT-5.5 session 不再被归入 GPT-5。
- **MiniMax** 多业务额度卡（文本 / 语音 / 图像 / 视频 / 音乐）。
- **Copilot 多账号** + Claude 高峰时段指示器 + 本地存储用量视图。
- **VoiceOver** 标签覆盖菜单栏。

### 修复

- Settings / About 在打包 app 启动时不再崩溃（SwiftPM bundle 查找）。
- Codex 卡死的 RPC 读取会超时退出；菜单重开行为修正为 toggle。
- Cursor 企业 / 团队用量显示正确（之前误报 100% remaining）。
- macOS 26.4 菜单栏图标重新可见。
- Pi session 成本缓存在价格变更后自动重建。
- 简体中文高峰时段 3 个字符串（`off_peak`、`peak_ends_in`、`off_peak_peak_in`）+ 英文 `not_found` fallback 补译（fork hotfix）。

### iOS 兼容

Wire format 未变，兼容 iOS 1.5.0+。iOS 客户端没有原生支持新 provider 的会显示为 fallback（蓝色）卡片；后续 iOS 版本会上原生 UI。本 Mac 版本不强制 iOS 同步升级。

## 0.23.6 — 2026-05-05 — Pairs with iOS 1.5.2

Bump from 0.23.5 → 0.23.6. The 0.23.5 internal cycle bundled mock
infrastructure groundwork (mix-mode injector + Settings UI gating
fix + L1 ghost cleanup survives Mac restart). 0.23.5 was never
published; everything ships as 0.23.6.

### Mac-side changes folded in

- **L1 ghost cleanup survives Mac restart** (commit `4e633c02`)

User QA 2026-05-05: stranded mock CKRecords from a previous Mac process
incarnation persisted on iOS forever after the user toggled mock injection
off. Build 95's Research/017 already noted "the codebase has zero explicit
record or zone deletion semantics" for cross-process scenarios; this hits
that gap directly — the in-memory `lastPushedRecordNames` was wiped on
every Mac process restart, so the L1 cleanup never knew about records
pushed by a previous process.

### Fixed

- `SyncCoordinator.startObserving` now triggers a one-shot
  `fetchPerProviderRecordNames(forDeviceID:)` against `DeviceProvidersZone`
  and seeds `lastPushedRecordNames` with the result. The next push cycle's
  diff sees pre-existing records that this Mac process never knew about,
  so L1 cleanup deletes them via the existing `deletePerProviderRecords`
  path. Closes the failure mode where:
  1. Mac pushes mocks (toggle on) → records land in CloudKit
  2. Mac process restarts (binary upgrade, normal quit, etc.)
  3. User toggles mocks off
  4. New Mac process starts with empty in-memory `lastPushedRecordNames`
  5. First-cycle guard skips delete → mocks stranded forever
- Generalises beyond mocks: ANY orphan record from a previous process
  (e.g. user disabled Codex on Mac before restart) now gets cleaned up
  on next restart's first push cycle.

### Added

- `SyncPushing.fetchPerProviderRecordNames(forDeviceID:)` protocol
  method with no-op default. CloudSyncManager implements via
  `desiredKeys: []` CKQuery (metadata only — no payload download)
  filtered by `NSPredicate(format: "deviceID == %@", deviceID)`.
- 3 new SyncCoordinator tests (`l1Reconcile*`): stranded-record
  cleanup confirmed, empty-CloudKit no-op, sync-disabled skip.

## 0.23.6 — Mock-First infrastructure groundwork (folded into 0.23.6 release)

Mock-First quality infrastructure groundwork. This release establishes
the synthetic-mock injection layer that subsequent iOS releases (1.5.2+)
build on for first-class multi-account testing without requiring real
provider subscriptions.

### Highlights — internal-only (no Sparkle release)

- **Mock provider injector — mix design + full provider coverage.**
  `MockProviderInjector` now emits **32 synthetic
  `ProviderUsageSnapshot` entries spanning 29 distinct providerIDs**:
  - 6 rich mocks with REAL provider IDs (`codex` × 3, `claude` × 2,
    `perplexity` × 1) so iOS renders them with first-class provider UI
    (icon, color, native multi-account affordances). Exercises the
    critical "3 Codex on Mac, 1 on iOS" rendering path that real users
    hit.
  - 24 simple single-account mocks covering every other real provider
    (cursor, opencode, opencodego, alibaba, factory, gemini,
    antigravity, copilot, zai, minimax, kimi, kilo, kiro, vertexai,
    augment, jetbrains, kimik2, amp, ollama, synthetic, warp,
    openrouter, abacus, mistral). Each emits a 1-account snapshot with
    a primary rate window + cost data (where applicable) so iPhone's
    first-class card UI for each provider is exercised.
  - 2 mocks with synthetic `_mock_*` IDs (`_mock_cursor_unknown` for
    error-state fallback, `_mock_synthetic_unknown` for rich-data
    fallback). Forward-compat insurance: when a future Mac adds a new
    provider iOS doesn't know yet, that fallback path must still
    render.
- **Cost data on most real-borrowed mocks.** 28 of 32 mocks carry a
  synthetic `SyncCostSummary` (session + 30-day total). The 4
  intentionally cost-less mocks: `_mock_cursor_unknown` (error state),
  `_mock_synthetic_unknown` (budget-driven), `antigravity` (preview /
  no billing), `ollama` (local inference, no spend). Codex Alice
  additionally carries a 30-day daily breakdown with model breakdowns
  so the iPhone Cost dashboard's Daily Spend / per-day chart /
  model-breakdown pie are all end-to-end testable. Aggregate
  ~$85/30day across all 28 cost-bearing mocks — visible but capped so
  it doesn't dwarf real users' real numbers.
- **Universal `*-mock@*.test` email TLD.** Every mock account uses the
  RFC 6761 reserved `.test` TLD as the universal "is this a mock?"
  signal. Works regardless of whether the providerID is real-borrowed
  or synthetic. iOS 1.5.2+ uses this TLD as the trigger for the MOCK
  badge + purple-striped card treatment.
- **Settings UI surface.** New "Debug · Mock Provider Data" section in
  Settings → Mobile, visible to all users (default OFF). Toggle flips
  `CodexBarMockProvidersEnabled` UserDefaults; the same flag drives
  `MockProviderInjector.isEnabled`. When ON, displays a reference list
  of the 8 mocks (display name + email + state) so QA can compare
  against what shows on iPhone. When toggled off, CloudKit ghost-
  records cleanup automatically purges the mock CKRecords within ~1
  cycle.
- **SyncCoordinator dependency injection for mock injector.**
  `mockInjector: () -> [ProviderUsageSnapshot]` parameter (default
  empty closure) decouples production from process-global UserDefaults
  state, enabling cross-suite parallel test isolation.
- **55 mock tests** (15 unit + 35 integration + 5 cost dashboard
  end-to-end) covering: providerID allowlist enforcement, real vs.
  fallback path coverage, .test TLD invariant, multi-account distinct
  recordNames, ghost-records cleanup on toggle, env var precedence,
  cost data sums match aggregates, daily breakdown model labels.
- **All 82 Sync regression tests still pass** with the redesigned
  mocks — R1 Codex multi-account, R2 token-based 11 provider expansion,
  R3-R5 multi-Mac merge + edge cases all unaffected. Combined Sync +
  Mock filter run: 136 tests pass.

### Activation (any one)

```sh
# Env var (developer)
CODEXBAR_MOCK_PROVIDERS=1 /Applications/CodexBar.app/Contents/MacOS/CodexBar

# defaults write (CLI / scripted QA)
defaults write com.o1xhack.codexbar CodexBarMockProvidersEnabled -bool true

# Settings UI (everyone)
CodexBar → Settings → Mobile → Debug · Mock Provider Data → toggle on
```

### Production safety

- Default is OFF; user must explicitly opt in. App Store / Sparkle
  distribution never accidentally activates.
- Mock CKRecords are stored under composite keys distinct from real
  data: `{deviceID}|{providerID}|*-mock@*.test`. Real provider records
  use a different email bucket and are never touched.
- L1 ghost-records cleanup auto-purges mock records within ~1 cycle
  after toggle-off. Real numbers restore fully.

---

## 0.23.4 — 2026-04-28

### Highlights — Mobile 1.5.1 — 2026-04-29

- Fork repository renamed from `o1xhack/CodexBar` to `o1xhack/CodexBar-Mobile`
  to differentiate from the upstream Mac repo. The Mac binary is unchanged
  from Mobile 1.3.1 — this bump just stamps the new fork URL into the
  appcast and GitHub release tag. All previous download URLs continue to
  resolve via GitHub's permanent redirect, so the Sparkle update flow stays
  uninterrupted for existing installs.
- Pairs with iOS **1.5.1 (102)** which carries the same rename through
  every iOS user-visible string and the in-app release notes.

---

Hotfix that closes a long-standing Codex JSONL parser bug — pre-existing
all the way back to when the Codex scanner was first written, only
became visible recently because Codex CLI 0.125 changed its
`turn_context` shape. Caused 90%+ of Codex token usage to be silently
misattributed to `gpt-5`, no matter what model the user actually ran.

Every previous version's user (0.18 / 0.19 / 0.20 / 0.20.x / 0.21 /
0.22 / 0.23 / 0.23.1) is automatically corrected on first launch of
0.23.4 — the fingerprint mechanism rolls and triggers a fresh full
re-scan with the fixed parser.

### Root cause

`Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner.swift:669`
declared `prefixBytes = 32 * 1024` for the Codex JSONL parser. Any line
larger than that gets `wasTruncated = true` from `CostUsageJsonl.scan`
and is skipped entirely.

Codex CLI 0.125+ ships `turn_context` events that bundle the project's
`AGENTS.md` / `CLAUDE.md` / `developer_instructions` into
`payload.user_instructions`, growing the line to **~38–41 KB** on a
typical project. Every `turn_context` was therefore truncated → skipped
→ `currentModel` never updated. All subsequent `event_msg/token_count`
events fell through the priority chain to `?? "gpt-5"` (line 763) and
got bucketed under `gpt-5` regardless of the real model.

The bug was masked because almost all earlier test fixtures included
`info.model` directly inside the token_count event (which bypasses
`currentModel`). Real Codex CLI 0.125 traffic doesn't.

### Fix

- Bumped `prefixBytes` from 32 KB to `maxLineBytes` (256 KB), matching
  what `CostUsageScanner+Claude.swift:80` and `PiSessionCostScanner.swift:280`
  already use. The cap remains in place for runaway-JSONL safety, just
  at a level that fits modern Codex events.
- Bumped `CostUsagePricing.parserLogicVersion` from `1` → `2`. The
  `pricingFingerprint` mechanism (added in 0.23.1) detects the rolled
  fingerprint on first launch and runs a fresh full scan with the fixed
  parser. Caches written without a fingerprint at all (every release
  before 0.23.1) also fail the equality check and get invalidated, so
  long-time users on older versions are corrected too.
- Two new regression tests in `CostUsageScannerTests.swift` pin the
  contract: one writes a single 50 KB turn_context + bare token_count
  (no `info.model`) and asserts attribution lands on `gpt-5.5`; the
  other simulates a mid-session model switch (gpt-5.4 → gpt-5.5) with
  two large turn_contexts and asserts the delta-split attribution
  lands on the right model in both segments. Both tests assert that
  `gpt-5` (the default fallback bucket) stays empty.

### Code-review follow-ups (folded in before ship)

A self-review with codex-reviewer caught three P1 issues across the
0.23 / 0.23.1 / 0.23.4 commit cluster. All three are fixed in this
release rather than deferred:

- **P1-1 — Lint guard fail-closed.** The new `audit_parser_version`
  check silently `return 0`'d when its base ref (`origin/mobile-dev`)
  was missing. CI shallow-clone checkouts (`actions/checkout` without
  `fetch-depth: 0`) would never have this ref, so parser changes could
  ship with no `parserLogicVersion` bump and the audit would still
  report success. Now it tries to fetch the missing ref first; if
  fetch fails it errors out instead of skipping. Explicit opt-out via
  `ALLOW_MISSING_BASE=1` for offline / fresh-fork-clone scenarios.
- **P1-2 — Fingerprint must include prices, not just keys.** The
  `pricingFingerprint` introduced in 0.23.1 hashed only model **names**,
  not their prices. A same-name reprice (existing model gets a new
  rate) wouldn't roll the fingerprint, leaving stale baked
  `costNanos` in `PiSessionCostCache` (and similarly in Claude
  caches that persist computed cost). Fingerprint now embeds the
  full price tuple per model — input / output / cacheRead /
  cacheCreation / threshold and above-threshold rates — so any
  edit invalidates every cache. New `pricingFingerprint rolls when
  a price changes` test pins the contract.
- **P1-3 — iOS legacy-email normalization byte-matches Mac.** Mac
  `AccountIdentityComputer` normalizes (NFC + percent-encode + length
  cap) before writing identifiers like `codex:email:...`. iOS's
  legacy-fallback synthesis in `CloudSyncReader.effectiveIdentifiers`
  used only `trim + lowercased`, so non-ASCII emails (e.g.
  `café@example.com`) split into separate cards across versions
  (Mac on 0.23+ writes `caf%C3%A9@…`; iOS synthesized
  `café@…` from a 0.20.x snapshot). Extracted the normalization
  to `Shared/iCloud/AccountIdentityNormalize.swift` so both sides use
  it. Pinned by paired tests on Mac and iOS asserting byte-identical
  output for the same fixture inputs.

### Hardening — preventing the next prefixBytes-class bug

Two infrastructure additions so this kind of regression can't reach
users again:

- **Lint guard.** New `Scripts/lint.sh audit-parser-version` step
  fails CI when any of `CostUsageScanner.swift`,
  `CostUsageScanner+Claude.swift`, or `CostUsageJsonl.swift` change
  without a matching bump to `CostUsagePricing.parserLogicVersion`.
  Wired into the default `lint` command so `./Scripts/lint.sh lint`
  catches it pre-push and CI re-runs the same check on every PR.
  Cosmetic / comment-only edits can opt out via `ALLOW_PARSER_CHANGE=1`.
  Why: this 0.23.4 fix needed a manual `parserLogicVersion` bump for
  the cache to actually re-roll on user machines — easy to forget on
  future parser tweaks.
- **Real-shape regression fixtures in tests.** The new tests
  deliberately model real Codex CLI 0.125 output (multi-KB
  `user_instructions` payloads, no `info.model` on token_count)
  rather than the cooperative shape earlier tests used. Future
  scanner changes that re-introduce the truncation class of bugs
  break these tests immediately.

### Notes

- CFBundleVersion = `58.4.1.3.1`. Sparkle on 0.23 prompts the upgrade
  on next check-for-updates.
- iOS unchanged (1.5.0 Build 96 / 98). Mac re-scan repushes corrected
  numbers to CloudKit; iOS reads automatically.
- 0.23.1 GitHub draft superseded — 0.23.4 carries the same cache
  invalidation infrastructure plus this parser fix, so 0.23.1 was
  never finalized.

## 0.23.1 — 2026-04-28

Hotfix on top of 0.23. Closes a stale-cache bug exposed during 0.23 QA: the
0.20.3 → 0.23 upgrade added new pricing (gpt-5.5, claude-opus-4-7) and the
fallback resolver, but the on-disk cost cache wasn't invalidated. Existing
users saw token usage attributed to the wrong model bucket (e.g., gpt-5.4
/ gpt-5.5 traffic stuck under gpt-5 in the cache, making Daily Spend
visibly low).

### Fix

- **Cost cache auto-invalidates on upgrade.** Bumped on-disk artifact
  versions: `codex-v4` → `codex-v5`, `claude-v2` / `vertexai-v2` →
  `claude-v3` / `vertexai-v3`, `pi-sessions-v1` → `pi-sessions-v2`. First
  launch on 0.23.1 ignores old cache files and runs a fresh full scan
  (10–60 s depending on JSONL volume).
- **Future-proofed against the same bug class.** Added
  `CostUsagePricing.pricingFingerprint` — a deterministic string of
  parser-logic version + sorted pricing keys. `CostUsageCache` and
  `PiSessionCostCache` carry this fingerprint at write time; load()
  rejects any cache whose fingerprint doesn't match the current build.
  Any future pricing-table edit (new model added, repriced, removed)
  auto-invalidates every user's cache on next launch — no manual
  artifact-version bump required.
- 9 new test cases pin the fingerprint contract.

### Notes

- CFBundleVersion = `58.2.1.3.1` (was `58.1.3.1` for 0.23). Sparkle on 0.23 prompts the upgrade.
- iOS unchanged (1.5.0 Build 96/98). Once Mac re-scans and pushes,
  iOS sees the corrected numbers automatically.

## 0.23 — 2026-04-26

Mac-side rollup of upstream v0.21 / 0.22 / 0.23 (109 commits, 2 new providers, multiple provider enhancements) plus iOS 1.5.0 data-channel scaffolding pre-loaded so future iOS iterations don't need a new Mac release. Mobile companion stays at **1.3.1** — this is a Mac-only release; iOS users on 1.3.1 / 1.3.0 / 1.2.0 see existing 25 providers unchanged plus 2 new providers (Abacus AI, Mistral) as fallback cards.

### Highlights — upstream 0.21–0.23 (Mac)
- **Mistral provider** (#607) — monthly spend tracking, browser-cookie import, manual cookies, CLI / token-account support. Thanks @welcoMattic!
- **Abacus AI provider** — ChatLLM and RouteLLM monthly compute-credit tracking with browser-cookie import, manual-cookie support, and monthly pace rendering. Thanks @ChrisGVE!
- **Claude Designs / Daily Routines / Web Sonnet bars** (#740) — live OAuth/Web quota data shown as additional usage bars on the Claude provider. Thanks @AISupplyGuy!
- **Cursor Extra usage** menu metric for on-demand budgets (#789). Thanks @huiye98!
- **Synthetic** — parses live 5-hour / weekly / search quota payloads with continuous reset/regeneration details (#732). Thanks @baanish!
- **Codex Pro $100 plan** support across OAuth / OpenAI web / menu / CLI; **GPT-5.5 / GPT-5.5 Pro pricing** for the local cost scanner.
- **Codex** — opt-in OpenAI web extras for fresh installs with battery-saver toggle; restored OpenAI web dashboard fetching on the new analytics route; Edge browser-cookie import.
- **Antigravity** — restored localhost endpoint/token probing across newer builds with async TLS challenge handling, retry on API-level errors.
- **z.ai** — preserve weekly + 5-hour token quotas together, surface 5-hour lane correctly across menu/menu bar.
- **OpenCode** — weekly pace visualization (reserve / expected / "Lasts until reset" details like Codex/Claude).
- **Menu shortcuts** ⌘R / ⌘, / ⌘Q while status menu is open (#737); fix macOS 26 RenderBox icon regression (#677); merged-menu width/alignment fixes.
- **Battery / refresh** — cut menu redraw churn, skip background work for unavailable providers, reuse cached OpenAI web views (#708).
- **Confetti** — opt-in celebration when weekly limits reset after active use (#785).

### Mobile 1.3.1 — Mac-side data channel pre-loaded for iOS 1.5.0 (Option B)

Mac 0.23 now writes 6 new optional `Shared/` Codable types to CloudKit so iOS 1.5.0 can render Abacus / Mistral structured detail, Synthetic 3-lane, Claude extras, Cursor Extra without ever needing a Mac patch later. iOS 1.3.x silently drops these unknown fields via existing `decodeIfPresent` (Build 79 forward-compat regression test pins this behavior) — bit-for-bit safe.

Types added: `SyncAbacusCreditSummary` · `SyncMistralUsageSummary` · `SyncSyntheticQuotaSummary` · `SyncClaudeExtraBars` · `SyncCursorExtraUsage` plus 6 optional fields on `ProviderUsageSnapshot`. `SyncCoordinator` adds 6 mapping sites mirroring how `SyncPerplexityCreditSummary` was added in 0.20.3.

### L1 ghost-records cleanup (root-cause fix)

Closes the bug class user reported on iOS 1.3.0 right after the 0.20.3 release (duplicate Codex cards from upgrade-induced identity drift, plus stale Perplexity card after disable). iOS 1.3.1 Build 94 shipped a display-time filter; this Mac release adds the *root cause* fix in `SyncCoordinator`:

- **Provider-disable hook** — when a previously-enabled provider transitions to disabled, delete its CKRecord from `DeviceProvidersZone` instead of leaving it as a stale ghost.
- **Account-identity-drift cleanup** — when a provider's composite key changes (e.g., Codex OAuth refactor between Mac versions), find and delete the stale recordName for that provider before writing the new one.

Together, the 6 known orphan-producing state transitions (provider enable/disable × 3 identity-rewrite paths) now self-heal.

### Notes

- CFBundleVersion = `56.1.3.1`. `BUILD_NUMBER` jumped 55.3 → **56** for the upstream-aligned slot. Sparkle `MOBILE_VERSION` tracks the current iOS train (1.3.1 — App Store hotfix).
- Multi-device / multi-version compat verified against TestFlight Build 95 and Macs on legacy + per-provider zones.

---

## 0.23 (upstream) — 2026-04-26

### Highlights
- Mistral: add provider support with monthly spend tracking, browser-cookie import, manual cookies, and CLI/token-account support (#607). Thanks @welcoMattic!
- Claude: show Designs and Daily Routines usage bars from live Claude OAuth/Web quota data, and restore the Web-mode Sonnet bar (#740). Thanks @AISupplyGuy!
- Cursor: add an Extra usage menu bar metric for on-demand budgets (#789). Thanks @huiye98!
- Usage: add an opt-in confetti celebration when weekly limits reset after active use (#785). Thanks @zats!
- Codex: add GPT-5.5 and GPT-5.5 Pro pricing so local cost scanning recognizes the new models.
- Copilot: show a clearer GitHub Device Flow hint in Settings when the copied device code needs to be pasted into GitHub (#369). Thanks @amoranio!

### Fixes
- Droid: preserve Factory session fallbacks, use the current usage endpoint, and clarify browser-login messaging (#792). Thanks @JosephDoUrden for the original stale-session fix!
- Widgets: package App Intents metadata for the widget extension and use configuration defaults so configurable widgets load correctly in WidgetKit (#783). Thanks @ngutman and @vincentyangch!
- Menu: keep merged-menu cards, switcher rows, wrapped status text, and hosted chart submenus aligned with the real AppKit menu width so menus no longer grow oversized or show narrower chart submenus after width changes. Thanks @ngutman!
- Codex: ignore invalid zero-minute subscription history so the utilization submenu no longer shows duplicate Session tabs.
- CLI: report the app bundle version correctly when the bundled helper is launched through a symlink.
- Codex/Claude: clean up cached CLI status probes during app shutdown so `codex -s read-only` workers are not orphaned after restart.

## 0.22 — 2026-04-21

### Highlights
- Codex: restore OpenAI web dashboard fetching on the new analytics route and tighten hidden WebView reuse/expiry.
- Synthetic: parse live quota payloads for five-hour, weekly, and search limits, including continuous reset/regeneration details (#732). Thanks @baanish!
- Antigravity: restore account/quota probing across newer localhost endpoint/token layouts and retry paths (#727). Thanks @icey-zhang!
- Menu: add standard shortcuts for Refresh, Settings, and Quit while the status menu is open (#737). Thanks @anirudhvee!
- Widgets: migrate app-group sharing to the Team-ID-prefixed container and carry widget state across the move (#701). Thanks @ngutman!

### Providers & Usage
- Synthetic: parse live five-hour, weekly, and search quota payloads, including continuous reset/regeneration details (#732). Thanks @baanish!
- Antigravity: restore localhost probing with async TLS challenge handling, extension-token fallback, and best-effort port selection (#727). Thanks @icey-zhang!
- Gemini: discover OAuth config in fnm/Homebrew/bundled CLI layouts so expired-token refresh keeps working (#723). Thanks @Leechael!
- Copilot: open the complete device-login verification URL when available so the browser flow carries the user code (#739). Thanks @skhe!
- Alibaba: update the China mainland Coding Plan endpoint and browser-cookie domain while keeping older domains as fallbacks (#712). Thanks @hezhongtang!
- Codex: restore OpenAI web dashboard fetching on the new analytics route and tighten hidden WebView reuse/expiry. @ratulsarna

### Menu & Settings
- Menu: show and handle standard shortcuts for Refresh (⌘R), Settings (⌘,), and Quit (⌘Q) while the status menu is open (#737). Thanks @anirudhvee!
- Settings: fix provider-sidebar clipping on macOS Tahoe and resize the Preferences window when switching tabs (#580). Thanks @chadneal!

### Fixes
- Keychain cache: preserve cached credentials when macOS temporarily denies keychain UI after wake, avoiding repeated prompts (#594). Thanks @josepe98!

## 0.21 — 2026-04-18

### Highlights
- Abacus AI: add a new provider for ChatLLM and RouteLLM credit tracking with browser-cookie import, manual-cookie support, and monthly pace rendering. Thanks @ChrisGVE!
- Codex: recognize the new Pro $100 plan in OAuth, OpenAI web, menu, and CLI rendering, and preserve CLI fallback when partial OAuth payloads lose the 5-hour session lane (#691, #709). Thanks @ImLukeF!
- Codex: make OpenAI web extras opt-in for fresh installs, preserve working legacy setups on upgrade, add an OpenAI web battery-saver toggle, and keep account-scoped dashboard state aligned during refreshes and account switches (#529). Thanks @cbrane!
- Codex: fix local cost scanner overcounting and cross-day undercounting across forked sessions, cold-cache refreshes, and sessions-root changes (#698). Thanks @xx205!
- z.ai: preserve weekly and 5-hour token quotas together, surface the 5-hour lane correctly across the menu/menu bar, and add regression coverage (#662). Thanks to @takumi3488 for the original fix and investigation.
- Cursor: fix a crash in the usage fetch path and add regression coverage (#663). Thanks @anirudhvee for the report and validation!
- Antigravity: restore account and quota probing across newer localhost endpoint/token layouts and API-level retry failures (#693, fixes #692). Thanks @anirudhvee!
- Menu bar: fix missing icons on affected macOS 26 systems by avoiding RenderBox-triggering SwiftUI effects (#677). Thanks @andrzejchm!
- Battery / refresh: cut menu redraw churn, skip background work for unavailable providers, and reuse cached OpenAI web views more efficiently (#708).
- Claude: add Opus 4.7 pricing so local cost scanning and cost breakdowns recognize the new model. Thanks @knivram!
- Codex: add Microsoft Edge as a browser-cookie import option for the Codex provider while preserving the contributor-branch workflow from the original PR (#694). Thanks @Astro-Han!

### Providers & Usage
- Abacus AI: add provider support for ChatLLM and RouteLLM monthly compute-credit tracking with cookie import, manual cookie headers, timeout/browser-detection threading, optional billing fallback, and hardened cached-session retry behavior. Thanks @ChrisGVE!
- Codex: render the new Pro $100 plan consistently across OAuth, OpenAI web, menu, and CLI surfaces, tolerate newer Codex OAuth payload variants like `prolite`, and only fall back to the CLI in auto mode when OAuth decode damage actually drops the session lane (#691, #709).
- Codex: make OpenAI web extras opt-in by default, preserve legacy implicit-auto cookie setups during upgrade inference, add battery-saver gating for non-forced dashboard refreshes, and preserve provider/dashboard state for enabled providers that are temporarily unavailable.
- Cost: tighten the local Codex cost scanner around fork inheritance, cold-cache discovery, incremental parsing, and sessions-root changes so replayed sessions no longer overcount or slip usage across day boundaries (#698). Thanks @xx205!
- z.ai: preserve both weekly and 5-hour token quotas, keep the existing 2-limit behavior unchanged, and render the 5-hour quota as a tertiary row in provider snapshots and CLI/menu cards (#662). Credit to @takumi3488 for the original fix and investigation.
- Cursor: fix the usage fetch path so failed or cancelled requests no longer crash, and add Linux build and regression test coverage fixes (#663).
- Antigravity: try both language-server and extension-server endpoint/token combinations, retry after API-level errors, scope insecure localhost trust handling to loopback hosts, and restore local quota/account probing on newer Antigravity builds (#693, fixes #692). Thanks @anirudhvee!
- Antigravity: prefer `userTier.name` over generic plan info when rendering the account plan so Google AI Ultra and similar tiers show their real subscription name, while still falling back cleanly when the tier label is absent or blank (#303). Thanks @zacklavin11!
- Ollama: recognize `__Secure-session` cookies during manual cookie entry and browser-cookie import so authenticated usage fetching continues to work with the newer cookie name (#707). Thanks @anirudhvee!
- OpenCode: enable weekly pace visualization for the app and CLI so weekly bars show reserve percentage, expected-usage markers, and "Lasts until reset" details like Codex and Claude (#639). Thanks @Zachary!
- Refresh pipeline: skip background work for unavailable providers, clear stale cached state, and show explicit unavailable messages (#708).
- Codex: support Microsoft Edge in browser-cookie import for the Codex provider while keeping the contributor branch untouched in the superseding integration path (#694). Thanks @Astro-Han!
- OpenCode / OpenCode Go: treat serialized `_server` auth/account-context failures as invalid credentials so cached browser cookies are cleared and retried instead of surfacing a misleading HTTP 500.
- OpenAI web: keep cached WebViews across same-account refreshes and clean them up only when accounts or providers go stale (#708).
- Claude: add Opus 4.7 pricing so local cost usage and breakdowns price the new model correctly. Thanks @knivram!
- Claude: broaden CLI binary lookup to native installer paths (#731). Thanks @dingtang2008!

### Menu & Settings
- Menu bar: fix missing icons on affected macOS 26 systems by replacing RenderBox-triggering material/offscreen SwiftUI effects in the provider sidebar and highlighted progress bar (#677). Thanks @andrzejchm!
- z.ai: fix menu bar selection when both weekly and 5-hour quotas are present (#662).
- Menu bar: avoid redundant merged-icon redraws and make hosted chart submenus load lazily without losing provider context (#708).
- Merged menu: when Overview is selected, keep the merged menu bar icon aligned with the first Overview provider in configured order, even while that provider is still loading (#724). Thanks @anirudhvee!
- Codex: add an OpenAI web battery-saver toggle, keep manual refresh available when battery saver is on, and hide OpenAI web submenus when web extras are disabled.

### Development & Tooling
- Diagnostics: add lightweight battery instrumentation for menu updates and refresh work (#708).
- Build script: make CodexBar-owned ad-hoc keychain cleanup opt-in with `--clear-adhoc-keychain`, and extend the explicit reset path to clear both `com.steipete.CodexBar` and `com.steipete.codexbar.cache`. Thanks @magnaprog!

## 0.20 — 2026-04-07

### Highlights
- Codex: switch between system accounts/profiles without manually logging out and back in. @ratulsarna
- Add Perplexity provider support with recurring, bonus, and purchased-credit tracking, Pro/Max plan detection, browser-cookie auto-import, and manual-cookie fallback (#449). Thanks @BeelixGit!
- Add OpenCode Go as a separate provider with 5-hour, weekly, and monthly web usage tracking, widget integration, and browser-cookie support.
- Claude: fix token and cost inflation caused by cross-file double counting of subagent JSONL logs, fix streaming chunk deduplication, and add `claude-sonnet-4-6` pricing. Thanks @enzonaute for the investigation!
- Cost history: include supported pi session usage in Codex/Claude provider history so provider charts reflect those local runs (#653). Thanks @ngutman!

## 0.20.3 — 2026-04-23

Mobile 1.3.0 release. Mac 0.20.3 (and the preceding 0.20.2) are small user-invisible data-layer patches on top of 0.20.0 that enable the iOS 1.3.0 experience — everything user-facing in this release lives on iPhone.

### Highlights — Mobile 1.3.0
- **2 new providers on iPhone** — Perplexity (3-segment credit detail + Pro/Max badge + renewal countdown) and OpenCode Go, with dedicated colors and Mac→iPhone push notifications.
- **Codex multi-account cards** — when you run multiple Codex accounts / workspaces, each card shows its email / workspace subtitle.
- **Faster, leaner sync** — per-provider CloudKit records with zlib compression (typical sync transfer drops from ~2 MB to a few dozen KB); silent-push-driven refresh updates views without pull-to-refresh.
- **Cold-start polish** — Usage tab no longer flashes blank on launch; transient CloudKit failures preserve cached data instead of blanking the screen.
- **Per-device Mac version in About & Sync** — see which Mac is running which CodexBar version, with an orange "Update available" chip on any Mac that's not on the latest.
- **Multi-device + multi-version correctness** — Subscription Utilization numbers stay consistent between the aggregate view and each provider's detail; older Macs can no longer silently drop fields the newer Mac wrote.

### Mobile 1.3.0 — new providers
- **Perplexity detail page** — 3-segment credit bar (recurring / bonus / purchased), Pro/Max plan badge, renewal and promo-expiration countdowns, dollar balance.
- **Perplexity + OpenCode Go push notifications** — both now in the 25-provider × 2-state push set (50 zones), with the provider name baked into the alert body in all 4 languages.
- **Unified provider color palette** — consolidated across 5 previously-drifted call sites; OpenCode Go no longer collides with OpenCode Zen.
- **Codex cards** with ≥2 accounts show email / workspace subtitles; single-account setups stay minimal.

### Mobile 1.3.0 — sync & stability
- **Per-provider CloudKit records** in a new `DeviceProvidersZone`, zlib-compressed. Older iPhones fall back to the legacy monolithic zone with zero regression.
- **Silent-push-driven refresh** — iPhone wakes silently when Mac writes, applies the delta, views refresh in the background.
- **SwiftData cold-start hydrate** — Cost tab no longer flashes a stale value before settling; Usage tab cold-start blank (two root causes — date-strategy mismatch + ghost records) fixed.
- **Transient-failure defense** — if CloudKit is momentarily unreachable, cached data is preserved instead of the screen blanking.
- **Multi-device merge correctness** — aggregate and per-provider utilization views share the same daily-peak semantic; cross-version field preservation stops older Macs from dropping fields the newer Mac knows about.
- **Forward-compatible wire format** — iPhones on today's build silently tolerate unknown fields from future Mac versions.

### Mobile 1.3.0 — polish
- **Per-device Mac version** in About & Sync, with a "· Update available" chip on older Macs.
- 4-language localization for all new strings (en / zh-Hans / zh-Hant / ja).
- Comprehensive regression-guard test fixtures for realistic multi-device, cross-version data distributions.

### Mac — 0.20.0 → 0.20.3
Two user-invisible Mac-side data-layer patches that power the iOS 1.3.0 experience above — per-provider CloudKit records with zlib compression (0.20.2) and Perplexity credit-pool pass-through (0.20.3). Mac user-facing behavior is unchanged since 0.20.0.

Mac 0.20.0 (2026-04-17) was the fork's alignment with upstream CodexBar 0.20. Highlights:
- **Codex system account switching** — switch between system accounts / profiles without manually logging out and back in (contribution by @ratulsarna).
- **Perplexity provider** (PR #606) — recurring, bonus, and purchased-credit tracking; Pro/Max plan detection; browser-cookie auto-import with manual-cookie fallback.
- **OpenCode Go** — separate provider from OpenCode Zen, with 5-hour / weekly / monthly web usage tracking, widget integration, and browser-cookie support.
- **Claude token/cost accuracy** — fixes cross-file double counting of subagent JSONL logs and streaming chunk deduplication; adds `claude-sonnet-4-6` pricing.

---

2026-04-23 Mobile 1.3.0 发布。Mac 0.20.3（以及前一个 0.20.2）只是在 0.20.0 之上的两个 Mac 端用户不可见数据层补丁，用来让 iOS 1.3.0 的能力落地 —— 本次所有用户可见变化都在 iPhone 端。

### 亮点 — Mobile 1.3.0
- **iPhone 新增 2 个 Provider** —— Perplexity（三段式 credit 详情页 + Pro/Max 徽章 + 续费倒计时）和 OpenCode Go，带专属配色以及 Mac→iPhone 推送通知。
- **Codex 多账号卡片** —— 同时运行多个 Codex 账号 / workspace 时，每张卡片在副标题显示对应的 email / workspace。
- **更快更省的同步** —— 按 provider 拆分的 CloudKit 记录 + zlib 压缩（典型同步流量从约 2 MB 降到几十 KB）；静默推送驱动刷新，视图不用下拉即可更新。
- **冷启动抛光** —— Usage tab 冷启动不再白屏；CloudKit 临时失败时保留缓存而不是清空界面。
- **About & Sync 按设备显示 Mac 版本** —— 清晰看到每台 Mac 运行的 CodexBar 版本，落后版本带橙色"可升级"标识。
- **跨 Mac + 跨版本数据正确性** —— 订阅利用率在聚合视图与单 provider 详情之间数字一致；旧 Mac 不再静默丢弃新 Mac 写入的字段。

### Mobile 1.3.0 — 新 Provider
- **Perplexity 详情页** —— 三段式 credit 柱（recurring / 赠送 / 购买）、Pro/Max 套餐徽章、续费 / 赠送到期倒计时、美元余额。
- **Perplexity + OpenCode Go 推送通知** —— 两者均加入 25 Provider × 2 状态的推送集合（50 个 zone），Provider 名称烤进 alertBody，4 语言本地化。
- **统一 Provider 配色** —— 收敛之前在 5 个调用点漂移的实现；OpenCode Go 视觉上不再与 OpenCode Zen 混淆。
- **Codex 卡片** 在 ≥2 账号时副标题显示 email / workspace；单账号保持极简。

### Mobile 1.3.0 — 同步 & 稳定性
- **按 provider 拆分的 CloudKit 记录**，新 zone `DeviceProvidersZone`，zlib 压缩。老版本 iPhone 回落到传统整体 zone，零回退。
- **静默推送驱动刷新** —— Mac 写入时 iPhone 静默唤醒，应用 delta，视图在后台刷新。
- **SwiftData 冷启动水合** —— Cost tab 不再闪一下旧值；Usage tab 冷启动白屏（两个根因 —— 日期策略不一致 + 幽灵记录）已修复。
- **瞬时失败防御** —— CloudKit 临时不可达时保留缓存，而不是清空屏幕。
- **多设备合并正确性** —— 聚合视图与单 Provider 利用率视图共用"日峰值"语义；跨版本字段保留，防止旧 Mac 静默丢弃新 Mac 知道的字段。
- **前向兼容的 wire 格式** —— 今日构建的 iPhone 静默容忍未来 Mac 版本加入的未知字段。

### Mobile 1.3.0 — 打磨
- About & Sync 按设备显示 Mac 版本，落后 Mac 带"· 可升级"标识。
- 所有新字符串 4 语言本地化（en / zh-Hans / zh-Hant / ja）。
- 针对真实多设备、跨版本数据分布的回归测试 fixture 全面扩展。

### Mac — 0.20.0 → 0.20.3
配合 iOS 1.3.0 落地的两个 Mac 端用户不可见数据层补丁 —— 按 provider 拆分的 CloudKit 记录 + zlib 压缩（0.20.2），以及 Perplexity credit 分段字段透传（0.20.3）。Mac 端用户可见行为自 0.20.0 以来无变化。

Mac 0.20.0（2026-04-17）是本 fork 对齐上游 CodexBar 0.20 的主版本，亮点：
- **Codex 系统账号切换** —— 不用手动登出再登入即可切换系统账号 / profile（@ratulsarna 贡献）。
- **Perplexity 服务商**（PR #606）—— recurring / 赠送 / 购买三段式 credit 追踪，Pro/Max 套餐识别，浏览器 cookie 自动导入加手动 cookie 兜底。
- **OpenCode Go** —— 从 OpenCode Zen 分离出独立 provider，支持 5 小时 / 周 / 月 web 用量追踪、widget、浏览器 cookie。
- **Claude token/费用修正** —— 修复子 agent JSONL 跨文件重复计数和流式分片去重；新增 `claude-sonnet-4-6` 定价。

## 0.20.2 — 2026-04-21

Mac-side data-plane support for the ongoing iOS 1.3.0 data-architecture refactor — per-provider CloudKit records, zlib compression, and a ghost-record fix. No user-visible change on Mac; everything below from 0.20.0 still applies.

### Highlights — upstream 0.20 (Mac)
- **Codex system account switching** — switch between system accounts/profiles without manually logging out and back in (contribution by @ratulsarna).
- **Perplexity provider** (PR #606) — recurring, bonus, and purchased-credit tracking; Pro/Max plan detection; browser-cookie auto-import with manual-cookie fallback.
- **OpenCode Go** — separate provider from OpenCode Zen, with 5-hour / weekly / monthly web usage tracking, widget integration, and browser-cookie support.
- **Claude token/cost accuracy** — fixes cross-file double counting of subagent JSONL logs and streaming chunk deduplication; adds `claude-sonnet-4-6` pricing.

### Mac — providers & usage
- Codex: workspace attribution for account labels and same-email multi-workspace accounts.
- Codex: reconcile live-system and managed accounts by canonical identity, preserve per-account usage/history/dashboard state, OAuth CLI fallback, tighter OpenAI web ownership gating.
- Codex: normalize weekly-only rate limits across OAuth and CLI/RPC; free-plan accounts render as Weekly instead of a fake Session.
- Codex: end-to-end refactor into clearer components (CodexDashboardAuthority / CodexAccountReconciliation / CodexIdentity / CodexConsumerProjection / ManagedCodexAccountCoordinator).
- OpenCode: preserve product separation between Zen and Go; harden cookie/domain behavior for authenticated web fetches.
- Cost history: merge supported pi session usage into Codex/Claude provider history (#653).

### Mac — menu & settings
- Codex: UI for switching the system-level Codex account and promoting a managed account into the live system slot.
- Claude: "Avoid Keychain prompts" enabled by default (experimental label removed).
- Fix alignment of menu chart hover coordinates on macOS.

### Mac — fixes (selected)
- Cursor fetch crash path (#663).
- z.ai 5-hour lane selection.
- Ollama `__Secure-session` cookie recognition (#707).
- Edge browser cookie import for Codex (#694).
- Antigravity localhost TLS challenges (#693).
- Battery-drain mitigations: menu bar updates and OpenAI web extras (#708, #684).
- Menu bar icon regression on macOS 26 RenderBox Metal shader (#677).
- Claude CLI well-known path fallback precedence (#675).

---

2026-04-21 配合 iOS 1.3.0 数据架构重构的 Mac 端数据层补丁 —— 按 provider 拆分的 CloudKit 记录、zlib 压缩，以及一个幽灵记录修复。Mac 端用户可见行为不变；下面 0.20.0 的内容全部继续适用。

### 亮点 — 上游 0.20（Mac）
- **Codex 系统账号切换** —— 不用手动登出再登入即可切换系统账号/profile（@ratulsarna 贡献）。
- **Perplexity 服务商**（PR #606）—— recurring / 赠送 / 购买三段式 credit 追踪，Pro/Max 套餐识别，浏览器 cookie 自动导入加手动 cookie 兜底。
- **OpenCode Go** —— 从 OpenCode Zen 分离出独立 provider，支持 5 小时 / 周 / 月 web 用量追踪、widget、浏览器 cookie。
- **Claude token/费用修正** —— 修复子 agent JSONL 跨文件重复计数和流式分片去重；新增 `claude-sonnet-4-6` 定价。

### Mac — 服务商 & 用量
- Codex：账号 label 的 workspace 归属，支持同 email 多 workspace。
- Codex：用 canonical 身份协调实时与 managed 账号，保留每账号独立用量/历史/dashboard；OAuth CLI 兜底；OpenAI web 所有权收紧。
- Codex：周限额在 OAuth/CLI/RPC 间归一化，免费账号显示为 Weekly 而非虚假 Session。
- Codex：端到端重构（CodexDashboardAuthority / CodexAccountReconciliation / CodexIdentity / CodexConsumerProjection / ManagedCodexAccountCoordinator 等）。
- OpenCode：Zen 与 Go 的产品边界保留；web 认证抓取的 cookie/domain 行为强化。
- 费用历史：支持将 pi session 用量合并到 Codex/Claude 历史（#653）。

### Mac — 菜单 & 设置
- Codex：切换系统级 Codex 账号、将 managed 账号晋升为 live system 的 UI。
- Claude："避免 Keychain 弹窗" 改为默认开启（不再是 experimental）。
- 修复 macOS 上菜单栏图表 hover 坐标对齐。

### Mac — 修复（节选）
- Cursor 抓取崩溃路径（#663）。
- z.ai 5 小时额度通道选择。
- Ollama `__Secure-session` cookie 识别（#707）。
- Edge 浏览器 cookie 导入 for Codex（#694）。
- Antigravity localhost TLS 握手。
- 电量回归修复（#708、#684）。
- macOS 26 RenderBox Metal 着色器导致的菜单栏图标不显示（#677）。
- Claude CLI well-known 路径 fallback 优先级（#675）。

## 0.20.0 — 2026-04-16

Mac-side alignment with upstream CodexBar 0.20. Mobile companion stays at 1.2.0. New upstream providers (Perplexity, OpenCode Go) appear in the Mac app; iPhone 1.2.0 displays them as fallback cards, full iOS-side adaptation ships in Mobile 1.3.0.

### Highlights — upstream 0.20 (Mac)
- **Codex system account switching** — switch between system accounts/profiles without manually logging out and back in (contribution by @ratulsarna).
- **Perplexity provider** (PR #606) — recurring, bonus, and purchased-credit tracking; Pro/Max plan detection; browser-cookie auto-import with manual-cookie fallback.
- **OpenCode Go** — separate provider from OpenCode Zen, with 5-hour / weekly / monthly web usage tracking, widget integration, and browser-cookie support.
- **Claude token/cost accuracy** — fixes cross-file double counting of subagent JSONL logs and streaming chunk deduplication; adds `claude-sonnet-4-6` pricing.

### Mac — providers & usage
- Codex: workspace attribution for account labels and same-email multi-workspace accounts.
- Codex: reconcile live-system and managed accounts by canonical identity, preserve per-account usage/history/dashboard state, OAuth CLI fallback, tighter OpenAI web ownership gating.
- Codex: normalize weekly-only rate limits across OAuth and CLI/RPC; free-plan accounts render as Weekly instead of a fake Session.
- Codex: end-to-end refactor into clearer components (CodexDashboardAuthority / CodexAccountReconciliation / CodexIdentity / CodexConsumerProjection / ManagedCodexAccountCoordinator).
- OpenCode: preserve product separation between Zen and Go; harden cookie/domain behavior for authenticated web fetches.
- Cost history: merge supported pi session usage into Codex/Claude provider history (#653).

### Mac — menu & settings
- Codex: UI for switching the system-level Codex account and promoting a managed account into the live system slot.
- Claude: "Avoid Keychain prompts" enabled by default (experimental label removed).
- Fix alignment of menu chart hover coordinates on macOS.

### Mac — fixes (selected)
- Cursor fetch crash path (#663).
- z.ai 5-hour lane selection.
- Ollama `__Secure-session` cookie recognition (#707).
- Edge browser cookie import for Codex (#694).
- Antigravity localhost TLS challenges (#693).
- Battery-drain mitigations: menu bar updates and OpenAI web extras (#708, #684).
- Menu bar icon regression on macOS 26 RenderBox Metal shader (#677).
- Claude CLI well-known path fallback precedence (#675).

---

2026-04-16 Mac 端对齐上游 CodexBar 0.20。Mobile 版本保持 1.2.0。上游新增 Provider（Perplexity、OpenCode Go）会出现在 Mac 端；iPhone 1.2.0 以兜底卡片形式显示，完整的 iOS 端适配在 Mobile 1.3.0 推出。

### 亮点 — 上游 0.20（Mac）
- **Codex 系统账号切换** —— 不用手动登出再登入即可切换系统账号/profile（@ratulsarna 贡献）。
- **Perplexity 服务商**（PR #606）—— recurring / 赠送 / 购买三段式 credit 追踪，Pro/Max 套餐识别，浏览器 cookie 自动导入加手动 cookie 兜底。
- **OpenCode Go** —— 从 OpenCode Zen 分离出独立 provider，支持 5 小时 / 周 / 月 web 用量追踪、widget、浏览器 cookie。
- **Claude token/费用修正** —— 修复子 agent JSONL 跨文件重复计数和流式分片去重；新增 `claude-sonnet-4-6` 定价。

### Mac — 服务商 & 用量
- Codex：账号 label 的 workspace 归属，支持同 email 多 workspace。
- Codex：用 canonical 身份协调实时与 managed 账号，保留每账号独立用量/历史/dashboard；OAuth CLI 兜底；OpenAI web 所有权收紧。
- Codex：周限额在 OAuth/CLI/RPC 间归一化，免费账号显示为 Weekly 而非虚假 Session。
- Codex：端到端重构（CodexDashboardAuthority / CodexAccountReconciliation / CodexIdentity / CodexConsumerProjection / ManagedCodexAccountCoordinator 等）。
- OpenCode：Zen 与 Go 的产品边界保留；web 认证抓取的 cookie/domain 行为强化。
- 费用历史：支持将 pi session 用量合并到 Codex/Claude 历史（#653）。

### Mac — 菜单 & 设置
- Codex：切换系统级 Codex 账号、将 managed 账号晋升为 live system 的 UI。
- Claude："避免 Keychain 弹窗" 改为默认开启（不再是 experimental）。
- 修复 macOS 上菜单栏图表 hover 坐标对齐。

### Mac — 修复（节选）
- Cursor 抓取崩溃路径（#663）。
- z.ai 5 小时额度通道选择。
- Ollama `__Secure-session` cookie 识别（#707）。
- Edge 浏览器 cookie 导入 for Codex（#694）。
- Antigravity localhost TLS 握手。
- 电量回归修复（#708、#684）。
- macOS 26 RenderBox Metal 着色器导致的菜单栏图标不显示（#677）。
- Claude CLI well-known 路径 fallback 优先级（#675）。

## 0.19.0 — 2026-04-15

This release ships the Mac-side changes that support Mobile 1.2.0: a CloudKit push notification writer (with multi-Mac dedup and 5-minute debounce per provider/state), 4 DEV test buttons in Preferences → Mobile, and an About-page locale fix. Upstream CodexBar 0.19.0 features are unchanged since the original release.

### Highlights — Mobile 1.2.0
- **Subscription Utilization visualization on iPhone** — see each session / weekly / opus quota per provider and across all providers, with a 30-day daily bar chart in the Cost tab and a utilization history chart on every provider detail page.
- **Multi-Mac data merge on iPhone** — if you run CodexBar on more than one Mac, iPhone now dedupes data by hour and combines across Macs, so iPhone charts stay consistent regardless of which Mac was last active.
- **Mac→iPhone push notifications** — when a session quota hits 0% or becomes available again on any of your Macs, your iPhone receives a localized notification that includes the provider name (e.g. "Codex session quota depleted" / "Codex 的会话额度已耗尽"). Background App Refresh is not required.

### Mac — Mobile 1.2.0 push infrastructure
- **`QuotaTransition` CloudKit record writer** — every session quota transition writes one record into the matching `Quota-{providerID}-{state}Zone` (~46 zones for 23 providers × 2 states). iPhone has a pre-baked `CKRecordZoneSubscription` per zone, with the provider name baked into the localized `alertBody` at subscription setup.
- **5-minute debounce per `(provider, state)`** to prevent oscillation near 0% from spamming.
- **Multi-Mac dedup** — `recordName = (providerID, hourBucket)` collapses concurrent transitions from 2+ Macs in the same hour to one record, so iPhone receives at most one push per `(provider, state)` per hour.
- **DEV test buttons in Preferences → Mobile** (debug builds only) — Codex / Claude × Depleted / Restored, for end-to-end push validation without waiting for a real quota change.

### Mac — fixes
- About page build date is now formatted with `en_US_POSIX` locale, avoiding mixed Chinese + English format on Chinese-system Macs.

### Highlights — Mobile 1.1.0
- iCloud sync upgraded from KVS to CloudKit for multi-device sync.
- Session quota push notifications for iOS.
- Composite Sparkle build number for upstream-safe version detection.

### CodexBar 0.19.0 (Upstream)
- Alibaba Coding Plan provider with region-aware quota fetching.
- Subscription utilization history chart in menu bar.
- Claude provider end-to-end refactor with expanded tests.
- Cursor dashboard alignment (Total/Auto/API lanes).
- Codex code review reset time display.
- Per-model token counts in cost history.
- GPT-5.4 mini and nano pricing.
- Antigravity model selection fix.

---

本版本带来 Mobile 1.2.0 配套的 Mac 端改动：CloudKit 推送通知写入（支持多 Mac 去重和按 provider/state 的 5 分钟 debounce）、Preferences → Mobile 下的 4 个 DEV 测试按钮，以及 About 页 locale 修复。上游 CodexBar 0.19.0 自原始发布以来无变化。

### 亮点 — Mobile 1.2.0
- **iPhone 订阅利用率可视化** —— 直观看到每个 session / weekly / opus 额度的使用情况，可按 Provider 分开看也可以跨 Provider 看总体。Cost tab 有 30 天日级柱状图，每个 Provider 详情页还有独立的利用率历史图。
- **iPhone 多 Mac 数据合并** —— 如果你在多台 Mac 上使用 CodexBar，iPhone 上会按小时去重后把所有 Mac 的数据合并，不管最后活跃的是哪台 Mac，iPhone 图表都一致。
- **Mac→iPhone 推送通知** —— 当你任何一台 Mac 上会话额度耗尽或恢复可用时，iPhone 收到一条本地化的通知，内容包含 Provider 名称（如"Codex 的会话额度已耗尽"）。不需要启用 Background App Refresh。

### Mac — Mobile 1.2.0 推送基础设施
- **`QuotaTransition` CloudKit record 写入** —— 每次会话额度状态变化，Mac 向对应的 `Quota-{providerID}-{state}Zone`（23 providers × 2 states ≈ 46 个 zone）写一条 record。iPhone 端为每个 zone 预创建 `CKRecordZoneSubscription`，subscription 创建时就把 Provider 名烤进 `alertBody`。
- **5 分钟 (provider, state) 级 debounce**，防止额度在 0% 附近抖动导致重复推送。
- **多 Mac 去重** —— `recordName` 用 `(providerID, hourBucket)`，多台 Mac 同一小时内检测到同一状态变化合并为单条 record，iPhone 每小时每种 `(provider, state)` 最多收到 1 条推送。
- **Preferences → Mobile 新增 4 个 DEV 测试按钮**（仅 debug 构建），Codex / Claude × 耗尽 / 恢复，端到端验证推送链路无需等真实额度变化。

### Mac — 修复
- About 页 Build 日期强制 `en_US_POSIX` locale，避免中文系统 Mac 显示中英文混合格式。

### 亮点 — Mobile 1.1.0
- iCloud 同步从 KVS 升级至 CloudKit，支持多设备同步。
- 会话配额推送通知：iOS 后台接收耗尽/恢复提醒。
- Sparkle 复合版本号方案，避免与上游版本号冲突。

### CodexBar 0.19.0（上游更新）
- 新增阿里巴巴 Coding Plan 服务商，支持区域化配额查询。
- 菜单栏新增订阅利用率历史图表。
- Claude 服务商端到端重构，测试覆盖更完整。
- Cursor 用量与仪表盘 Total/Auto/API 对齐。
- Codex 代码审查限制显示重置时间。
- 费用历史新增每模型 Token 统计。
- GPT-5.4 mini 和 nano 定价支持。
- Antigravity 模型选择修复。

## 0.18.0 — 2026-03-15

### Highlights — Mobile 1.1.0
- **iCloud sync upgraded from KVS to CloudKit** for reliable multi-device sync.
- Each Mac now writes its own CloudKit device record; iPhone merges all devices automatically.
- Multi-Mac support: providers from different Macs are combined on iPhone instead of last-write-wins.
- Cost data from local-source providers (Claude, Codex, VertexAI) is summed across devices; account-level providers deduplicate.
- Sync status shows specific CloudKit errors (network, auth, quota) instead of generic messages.
- Mac generates a stable device UUID (persisted in UserDefaults) for CloudKit record identity.
- Set CloudKit container environment to Production for both Mac and iOS.
- Composite Sparkle build number (`BUILD_NUMBER.MOBILE_VERSION`) for upstream-safe version detection.
- Updated About page with fork project links (GitHub, Website, Twitter, Email) and license.

### Mobile 1.0.0
- Sync cost/usage data (session cost, 30-day cost, daily spend) to iOS via iCloud KVS.
- Sync dynamic rate windows with labels (Session, Weekly, Sonnet, etc.).
- Push Mac app version and mobile version in iCloud payload for iOS traceability.
- Diagnose iCloud sync failures when the Mac build is missing iCloud entitlement or has no active iCloud account.
- Show explicit iCloud sync failure reasons in Mac Settings instead of reporting a false success state.
- Display "Mobile 1.0.0" in Mac About panel alongside app version.
- Update signing identity and Sparkle keys for o1xhack fork.

### CodexBar 0.18.0 (Upstream)
- Add Kilo provider support with API/CLI source modes, widget integration, and pass/credit handling (#454). Built on work by @coreh.
- Add Ollama provider, including token-account support in Settings and CLI (#380). Thanks @CryptoSageSnr!
- Add OpenRouter provider for credit-based usage tracking (#396). Thanks @chountalas!
- Add Codex historical pace with risk forecasting, backfill, and zero-usage-day handling (#482, supersedes #438). Thanks @tristanmanchester!
- Add a merged-menu Overview tab with configurable providers and row-to-provider navigation (#416). @ratulsarna
- Add an experimental option to suppress Claude Keychain prompts (#388).
- Reduce CPU/energy regressions and JSONL scanner overhead in Codex/web usage paths (#402, #392). Thanks @bald-ai and @asonawalla!

### Providers & Usage
- Codex: add historical pace risk forecasting and backfill, gate pace computation by display mode, and handle zero-usage days in historical data (#482, supersedes #438). Thanks @tristanmanchester!
- Kilo: add provider support with source-mode fallback, clearer credential/login guidance, auto top-up activity labeling, zero-balance credit handling, and pass parsing/menu rendering (#454). Thanks @coreh!
- Ollama: add provider support with token-account support in app/CLI, Chrome-default auto cookie import, and manual-cookie mode (#380). Thanks @CryptoSageSnr!
- OpenRouter: add provider support with credit tracking, key-quota popup support, token-account labels, fallback status icons, and updated icon/color (#396). Thanks @chountalas!
- Gemini: show separate Pro, Flash, and Flash Lite meters by splitting Gemini CLI quota buckets for `gemini-2.5-flash` and `gemini-2.5-flash-lite` (#496). Thanks @aladh
- Codex: in percent display mode with "show remaining," show remaining credits in the menu bar when session or weekly usage is exhausted (#336). Thanks @teron131!
- Claude: surface rate-limit errors from the CLI `/usage` probe with a user-friendly message, and harden "Failed to load usage data" matching against whitespace-collapsed output.
- Claude: restore weekly/Sonnet reset parsing from whitespace-collapsed CLI `/usage` output so reset times and pace details still appear after CLI fallback.
- Claude: fix extra-usage double conversion so OAuth/Web values stay on a single normalization path (#472, supersedes #463). Thanks @Priyans-hu!
- Claude: remove root-directory mtime short-circuiting in cost scanning so new session logs inside existing `~/.claude/projects/*` folders are discovered reliably (#462, fixes #411). Thanks @Priyans-hu!
- Copilot: harden free-plan quota parsing and fallback behavior by treating underdetermined values as unknown, preserving missing metadata as nil (#432, supersedes #393). Thanks @emanuelst!
- OpenCode: treat explicit `null` subscription responses as missing usage data, skip POST fallback, and return a clearer workspace-specific error (#412).
- OpenCode: surface clearer HTTP errors. Thanks @SalimBinYousuf1!
- Codex: preserve exact GPT-5 model IDs in local cost history, add GPT-5.4 pricing, and label zero-cost `gpt-5.3-codex-spark` sessions as "Research Preview" in cost breakdowns (#511). Thanks @iam-brain!
- Augment: prevent refresh stalls when `auggie account status` hangs by replacing unbounded CLI waits with timed subprocess execution and fallback handling (#481). Thanks @bryant24hao!
- Update Kiro parsing for `kiro-cli` 1.24+ / Q Developer formats and non-managed plan handling (#288). Thanks @kilhyeonjun!
- Kimi: in automatic metric mode, prioritize the 5-hour rate-limit window for menu bar and merged highest-usage calculations (#390). Thanks @ajaxjiang96!
- Browser cookie import: match Gecko `*.default*` profile directories case-insensitively so Firefox/Zen cookie detection works with uppercase `.Default` directories (#422). Thanks @bald-ai!
- MiniMax: make both Settings "Open Coding Plan" actions region-aware so China mainland selection opens `platform.minimaxi.com` instead of the global domain (#426, fixes #378). Thanks @bald-ai!
- Menu: rebuild the merged provider switcher when “Show usage as used” changes so switcher progress updates immediately (#306). Thanks @Flohhhhh!
- Warp: update API key setup guidance.
- Claude: update the "not installed" help link to the current Claude Code documentation URL (#431). Thanks @skebby11!
- Fix Claude setup message package name (#376). Thanks @daegwang!

### Menu & Settings
- Merged menu: keep Merge Icons, the switcher, and Overview tied to user-enabled providers even when some providers are temporarily unavailable, while defaulting menu content and icon state to an available provider when possible (#525). Thanks @Astro-Han!
- Merged menu: add an Overview switcher tab that shows up to three provider usage rows in provider order (#416).
- Settings: add "Overview tab providers" controls to choose/deselect Overview providers, with persisted selection reconciliation as enabled providers change (#416).
- Menu: hide contextual provider actions while Overview is selected and rebuild switcher state when overview availability changes (#416).

### Claude OAuth & Keychain
- Add an experimental Claude OAuth Security-CLI reader path and option in settings.
- Apply stored prompt mode and fallback policy to silent/noninteractive keychain probes.
- Add cooldown for background OAuth keychain retries.
- Disable experimental toggle when keychain access is disabled.
- Use a `claude-code/<version>` User-Agent for OAuth usage requests instead of a generic identifier.

### Performance & Reliability
- Codex/OpenAI web: reduce CPU and energy overhead by shortening failed CLI probe windows, capping web retry timeouts, and using adaptive idle blink scheduling (#402). Thanks @bald-ai!
- Cost usage scanner: optimize JSONL chunk parsing to avoid buffer-front removal overhead on large logs (#392). Thanks @asonawalla!
- TTY runner: fence shutdown registration to avoid launch/shutdown races, isolate process groups before shutdown rejection, and ensure lingering CLI descendants are cleaned up on app termination (#429). Thanks @uraimo!


## 0.18.0-beta.3 — 2026-02-13
### Highlights
- Claude OAuth/keychain flows were reworked across a series of follow-up PRs to reduce prompt storms, stabilize background behavior, surface a setting to control prompt policy and make failure modes deterministic (#245, #305, #308, #309, #364). Thanks @manikv12!
- Claude: harden Claude Code PTY capture for `/usage` and `/status` (prompt automation, safer command palette confirmation, partial UTF-8 handling, and parsing guards against status-bar context meters) (#320).
- New provider: Warp (credits + add-on credits) (#352). Thanks @Kathie-yu!
- Provider correctness fixes landed for Cursor plan parsing and MiniMax region routing (#240, #234, #344). Thanks @robinebers and @theglove44!
- Menu bar animation behavior was hardened in merged mode and fallback mode (#283, #291). Thanks @vignesh07 and @Ilakiancs!
- CI/tooling reliability improved via pinned lint tools, deterministic macOS test execution, and PTY timing test stabilization plus Node 24-ready GitHub Actions upgrades (#292, #312, #290).

### Claude OAuth & Keychain
- Claude OAuth creds are cached in CodexBar Keychain to reduce repeated prompts.
- Prompts can still appear when Claude OAuth credentials are expired, invalid, or missing and re-auth is required.
- In Auto mode, background refresh keeps prompts suppressed; interactive prompts are limited to user actions (menu open or manual refresh).
- OAuth-only mode remains strict (no silent Web/CLI fallback); Auto mode may do one delegated CLI refresh + one OAuth retry before falling back.
- Preferences now expose a Claude Keychain prompt policy (Never / Only on user action / Always allow prompts) under Providers → Claude; if global Keychain access is disabled in Advanced, this control remains visible but inactive.

### Provider & Usage Fixes
- Warp: add Warp provider support (credits + add-on credits), configurable via Settings or `WARP_API_KEY`/`WARP_TOKEN` (#352). Thanks @Kathie-yu!
- Cursor: compute usage against `plan.limit` rather than `breakdown.total` to avoid incorrect limit interpretation (#240). Thanks @robinebers!
- MiniMax: correct API region URL selection to route requests to the expected regional endpoint (#234). Thanks @theglove44!
- MiniMax: always show the API region picker and retry the China endpoint when the global host rejects the token to avoid upgrade regressions for users without a persisted region (#344). Thanks @apoorvdarshan!
- Claude: add Opus 4.6 pricing so token cost scanning tracks USD consumed correctly (#348). Thanks @arandaschimpf!
- z.ai: handle quota responses with missing token-limit fields, avoid incorrect used-percent calculations, and harden empty-response behavior with safer logging (#346). Thanks @MohamedMohana and @halilertekin!
- z.ai: fix provider visibility in the menu when enabled with token-account credentials (availability now considers the effective fetch environment).
- Amp: detect login redirects during usage fetch and fail fast when the session is invalid (#339). Thanks @JosephDoUrden!
- Resource loading: fix app bundle lookup path to avoid "could not load resource bundle" startup failures (#223). Thanks @validatedev!
- OpenAI Web dashboard: keep WebView instances cached for reuse to reduce repeated network fetch overhead; tests were updated to avoid network-dependent flakes (#284). Thanks @vignesh07!
- Token-account precedence: selected token account env injection now correctly overrides provider config `apiKey` values in app and CLI environments. Thanks @arvindcr4!
- Claude: make Claude CLI probing more resilient by scoping auto-input to the active subcommand and trimming to the latest Usage panel before parsing to avoid false matches from earlier screen fragments (#320).

### Menu Bar & UI Behavior
- Prevent fallback-provider loading animation loops (battery/CPU drain when no providers are enabled) (#283). Thanks @vignesh07!
- Prevent status overlay rendering for disabled providers while in merged mode (#291). Thanks @Ilakiancs!

### CI, Tooling & Test Stability
- Pin SwiftFormat/SwiftLint versions and harden lint installer behavior (version drift + temp-file leak fixes) (#292).
- Use more deterministic macOS CI test settings (including non-parallel paths where needed) and align runner/toolchain behavior for stability (#292).
- Stabilize PTY command timing tests to reduce CI flakiness (#312).
- Upgrade `actions/checkout` to v6 and `actions/github-script` to v8 for Node 24 compatibility in `upstream-monitor.yml` (#290). Thanks @salmanmkc!
- Tests: add TaskLocal-based keychain/cache overrides so keychain gating and KeychainCacheStore test stores do not leak across concurrent test execution (#320).

### Docs & Maintenance
- Update docs for Claude data fetch behavior and keychain troubleshooting notes.
- Update MIT license year.

## 0.18.0-beta.2 — 2026-01-21
### Highlights
- OpenAI web dashboard refresh cadence now follows 5× the base refresh interval.
- OpenAI web dashboard WebView is kept warm between scrapes to avoid repeated SPA downloads while idle CPU stays low (#284). Thanks @vignesh07!
- Menu bar: avoid fallback animation loop when all providers are disabled (#283). Thanks @vignesh07!
- Codex settings now include a toggle to disable OpenAI web extras.

### Providers
- Providers: add Dia browser support across cookie import and profile detection (#209). Thanks @validatedev!
- Codex: include archived session logs in local token cost scanning and dedupe by session id.
- Claude: harden CLI /usage parsing and avoid ANTHROPIC_* env interference during probes.

### Menu & Menu Bar
- Menu: opening OpenAI web submenus triggers a refresh when the data is stale.
- Menu: fix usage line labels to honor “Show usage as used”.
- Debug: add a toggle to keep Codex/Claude CLI sessions alive between probes.
- Debug: add a button to reset CLI probe sessions.
- App icon: use the classic icon on macOS 15 and earlier while keeping Liquid Glass for macOS 26+ (#178). Thanks @zerone0x!

## 0.18.0-beta.1 — 2026-01-18
### Highlights
- New providers: OpenCode (web usage), Vertex AI, Kiro, Kimi, Kimi K2, Augment, Amp, Synthetic.
- Provider source controls: usage source pickers for Codex/Claude, manual cookie headers, cookie caching with source/timestamp.
- Menu bar upgrades: display mode picker (percent/pace/both), auto-select near limit, absolute reset times, pace summary line.
- CLI/config revamp: config-backed provider settings, JSON-only errors, config validate/dump.

### Providers
- OpenCode: add web usage provider with workspace override + Chrome-first cookie import (#188). Thanks @anthnykr!
- OpenCode: refresh provider logo (#190). Thanks @anthnykr!
- Vertex AI: add provider with quota-based usage from gcloud ADC. Thanks @bahag-chaurasiak!
- Vertex AI: token costs are shown via the Claude provider (same local logs).
- Vertex AI: harden quota usage parsing for edge-case responses.
- Kiro: add CLI-based usage provider via kiro-cli. Thanks @neror!
- Kiro: clean up provider wiring and show plan name in the menu.
- Kiro: harden CLI idle handling to avoid partial usage snapshots (#145). Thanks @chadneal!
- Kimi: add usage provider with cookie-based API token stored in Keychain (#146). Thanks @rehanchrl!
- Kimi K2: add API-key usage provider for credit totals (#147). Thanks @0-CYBERDYNE-SYSTEMS-0!
- Augment: add provider with browser-cookie usage tracking.
- Augment: prefer Auggie CLI usage with web fallback, plus session refresh + recovery tools (#142). Thanks @bcharleson!
- Amp: add provider with Amp Free usage tracking (#167). Thanks @duailibe!
- Synthetic: add API-key usage provider with quota snapshots (#171). Thanks @monotykamary!
- JetBrains AI: include IDEs missing quota files, expand custom paths, and add Android Studio base paths (#194). Thanks @steipete!
- JetBrains AI: detect IDE directories case-insensitively (#200). Thanks @zerone0x!
- Cursor: support legacy request-based plans and show individual on-demand usage (#125) — thanks @vltansky
- Cursor: avoid Intel crash when opening login and harden WebKit teardown. Thanks @meghanto!
- Cursor: load stored session cookies before reads to make relaunches deterministic.
- z.ai: add BigModel CN region option for API endpoint selection (#140). Thanks @nailuoGG!
- MiniMax: add China mainland region option + host overrides (#143). Thanks @nailuoGG!
- MiniMax: support API token or cookie auth; API token takes precedence and hides cookie UI (#149). Thanks @aonsyed!
- Gemini: prefer loadCodeAssist project IDs for quota fetches (#172). Thanks @lolwierd!
- Gemini: honor loadCodeAssist project IDs for quota + support Nix CLI layout (#184). Thanks @HaukeSchnau!
- Claude: fix OAuth “Extra usage” spend/limit units when the API returns minor currency units (#97).
- Claude: rescale extra usage costs when plan hints are missing and prefer web plan hints for extras (#181). Thanks @jorda0mega!
- Usage formatting: fix currency parsing/formatting on non-US locales (e.g., pt-BR). Thanks @mneves75!

### Provider Sources & Security
- Providers: cache browser cookies in Keychain (per provider) and show cached source/time in settings.
- Codex/Claude/Cursor/Factory/MiniMax: cookie sources now include Manual (paste a Cookie header) in addition to Automatic.
- Codex/Claude/Cursor/Factory/MiniMax: skip cookie imports from browsers without usable cookie stores (profile/cookie DB) to avoid unnecessary Keychain prompts.
- Providers: suppress repeated Chromium Keychain prompts after access denied and honor disabled Keychain access.

### Preferences & Settings
- Preferences: swap provider refresh button and enable toggle order.
- Preferences: animate settings width and widen Providers on selection.
- Preferences: shrink default settings size and reduce overall height.
- Preferences: move “Hide personal information” to Advanced.
- Providers: shorten fetch subtitle to relative time only.
- Preferences: soften provider sidebar background and stabilize drag reordering.
- Preferences: restrict provider drag handle to handle-only.
- Preferences: move provider refresh timing to a dedicated second line.
- Preferences: tighten provider usage metrics spacing.
- Preferences: show refresh timing inline in provider detail subtitle.
- Preferences: move “Access OpenAI via web” into Providers → Codex.
- Preferences: add usage source pickers for Codex + Claude with auto fallback.
- Preferences: add cookie source pickers with contextual helper text for the selected mode.
- Preferences: move “Disable Keychain access” to Advanced and require manual cookies when enabled.
- Preferences: add per-provider menu bar metric picker (#185) — thanks @HaukeSchnau
- Preferences: tighten provider rows (inline pickers, compact layout, inline refresh + auto-source status).
- Preferences: remove the “experimental” label from Antigravity.

### Menu & Menu Bar
- Menu: add a toggle to show reset times as absolute clock values (instead of countdowns).
- Menu: show an “Open Terminal” action when Claude OAuth fails.
- Menu: add “Hide personal information” toggle and redact emails in menu UI (#137). Thanks @t3dotgg!
- Menu: keep a pace summary line alongside the visual marker (#155). Thanks @antons!
- Menu: reduce provider-switch flicker and avoid redundant menu card sizing for faster opens (#132). Thanks @ibehnam!
- Menu: keep background refresh on open without forcing token usage (#158). Thanks @weequan93!
- Menu: Cursor switcher shows On-Demand remaining when Plan is exhausted in show-remaining mode (#193). Thanks @vltansky!
- Menu: avoid single-letter wraps in provider switcher titles.
- Menu: widen provider switcher buttons to avoid clipped titles.
- Menu bar: rebuild provider status items on reorder so icons update correctly.
- Menu bar: optional auto-select provider closest to its rate limit and keep switcher progress visible (#159). Thanks @phillco!
- Menu bar: add display mode picker for percent/pace/both in the menu bar icon (#169). Thanks @PhilETaylor!
- Menu bar: fix combined loading indicator flicker during loading animation (incl. debug replay).
- Menu bar: prevent blink updates from clobbering the loading animation.

### CLI & Config
- CLI: respect the reset time display setting.
- CLI: add pink accents, usage bars, and weekly pace lines to text output.
- CLI: add config-backed provider settings, `--json-only`, and `--source api` for key-based providers.
- CLI: add `config validate`/`config dump` commands and per-provider JSON error payloads.
- CLI/App: move provider secrets + ordering to `~/.codexbar/config.json` (no Keychain persistence).
- Providers: resolve API tokens from config/env only (no Keychain fallback).

### Dev & Tests
- Dev: move Chromium profile discovery into SweetCookieKit (adds Helium net.imput.helium). Thanks @hhushhas!
- Dev: bump SweetCookieKit to 0.2.0.
- Dev: migrate stored Keychain items to reduce rebuild prompts.
- Dev: move path debug snapshot off the main thread and debounce refreshes to avoid startup hitches (#131). Thanks @ibehnam!
- Tests: expand Kiro CLI coverage.
- Tests: stabilize Claude PTY integration cleanup and reset CLI sessions after probes.
- Tests: kill leaked codex app-server after tests.
- Tests: add regression coverage for merged loading icon layout stability.
- Tests: cover config validation and JSON-only CLI errors.
- Build: stabilize Swift test runtime.

## 0.17.0 — 2025-12-31
- New providers: MiniMax.
- Keychain: show a preflight explanation before macOS prompts for OAuth tokens or cookie decryption.
- Providers: defer z.ai + Copilot Keychain reads until the user interacts with the token field.
- Menu bar: avoid status item menu reattachment and layout flips during refresh to reduce icon flicker.
- Dev: align SweetCookieKit local-storage tests with Swift Testing.
- Charts: align hover selection bands with visible bars in credits + usage breakdown history.
- About: fix website link in the About panel. Thanks @felipeorlando!

## 0.16.1 — 2025-12-29
- Menu: reduce layout thrash when opening menus and sizing charts. Thanks @ibehnam!
- Packaging: default release notarization builds universal (arm64 + x86_64) zip.
- OpenAI web: reduce idle CPU by suspending cached WebViews when not scraping. Thanks @douglascamata!
- Icons: switch provider brand icons to SVGs for sharper rendering. Thanks @vandamd!

## 0.16.0 — 2025-12-29
- Menu bar: optional “percent mode” (provider brand icons + percentage labels) via Advanced toggle.
- CLI: add `codexbar cost` to print local cost usage (text/JSON) for Codex + Claude.
- Cost: align local cost scanner with ccusage; stabilize parsing/decoding and handle large JSONL lines.
- Claude: skip pricing for unknown models (tokens still tracked) to avoid hard-coded legacy prices.
- Performance: reduce menu bar CPU usage by caching morph icons, skipping redundant status-item updates, and caching provider enablement/order during animations.
- Menu: improve provider switcher hover contrast in light mode.
- Icons: refresh Droid + Claude brand assets to better match menu sizing.
- CI: avoid interactive login-shell probes to reduce noisy “CLI missing” errors.

## 0.15.3 — 2025-12-28
- Codex: default to OAuth usage API (ChatGPT backend) with CLI-only override in Debug.
- Codex: map OAuth credits balance directly, avoiding web fallback for credits.
- Preferences: add optional “Access OpenAI via web” toggle and show blended source labels when web extras are active.
- Copilot: replace blocking auth wait dialog with a non-modal sheet to avoid stuck login.

## 0.15.2 — 2025-12-28
- Copilot: fix device-flow waiting modal to close reliably after auth (and avoid stuck waits).
- Packaging: include the KeyboardShortcuts resource bundle to prevent Settings → Keyboard shortcut crashes in packaged builds.

## 0.15.1 — 2025-12-28
- Preferences: fix provider API key fields reusing the wrong input when switching rows.
- Preferences: avoid Advanced tab crash when opening settings.

## 0.15.0 — 2025-12-28
- New providers: Droid (Factory), Cursor, z.ai, Copilot.
- macOS: CodexBar now supports Intel Macs (x86_64 builds + Sonoma fallbacks). Thanks @epoyraz!
- Droid (Factory): new provider with Standard + Premium usage via browser cookies, plus dashboard + status links. Thanks @shashank-factory!
- Menu: allow multi-line error messages in the provider subtitle (up to 4 lines).
- Menu: fix subtitle sizing for multi-line error states.
- Menu: avoid clipping on multi-line error subtitles.
- Menu: widen the menu card when 7+ providers are enabled.
- Providers: Codex, Claude Code, Cursor, Gemini, Antigravity, z.ai.
- Gemini: switch plan detection to loadCodeAssist tier lookup (Paid/Workspace/Free/Legacy). Thanks @381181295!
- Codex: OpenAI web dashboard is now the primary source for usage + credits; CLI fallback only when no matching cookies exist.
- Claude: prefer OAuth when credentials exist; fall back to web cookies or CLI (thanks @ibehnam).
- CLI: replace `--web`/`--claude-source` with `--source` (auto/web/cli/oauth); auto falls back only when cookies are missing.
- Homebrew: cask now installs the `codexbar` CLI symlink. Thanks @dalisoft!
- Cursor: add new usage provider with browser cookie auth (cursor.com + cursor.sh), on-demand bar support, and dashboard access.
- Cursor: keep stored sessions on transient failures; clear only on invalid auth.
- z.ai: new provider support with Tokens + MCP usage bars and MCP details submenu; API token now lives in Preferences (stored in Keychain); usage bars respect the show-used toggle. Thanks @uwe-schwarz for the initial work!
- Copilot: new GitHub Copilot provider with device flow login plus Premium + Chat usage bars (including CLI support). Thanks @roshan-c!
- Preferences: fix Advanced Display checkboxes and move the Quit button to the bottom of General.
- Preferences: hide “Augment Claude via web” unless Claude usage source is CLI; rename the cost toggle to “Show cost summary”.
- Preferences: add an Advanced toggle to show/hide optional Codex Credits + Claude Extra usage sections (on by default).
- Widgets: add a new “CodexBar Switcher” widget that lets you switch providers and remember the selection.
- Menu: provider switcher now uses crisp brand icons with equal-width segments and a per-provider usage indicator.
- Menu: tighten provider switcher sizing and increase spacing between label and weekly indicator bar.
- Menu: provider switcher no longer forces a wider menu when many providers are enabled; segments clamp to the menu width.
- Menu: provider switcher now aligns to the same horizontal padding grid as the menu cards when space allows.
- Dev: `compile_and_run.sh` now force-kills old instances to avoid launching duplicates.
- Dev: `compile_and_run.sh` now waits for slow launches (polling for the process).
- Dev: `compile_and_run.sh` now launches a single app instance (no more extra windows).
- CI: build/test Linux `CodexBarCLI` (x86_64 + aarch64) and publish release assets as `CodexBarCLI-<tag>-linux-<arch>.tar.gz` (+ `.sha256`).
- CLI: add alias fallback for Codex/Claude detection when PATH lookups fail.
- Providers: support Arc browser cookies for Factory/Droid (and other Chromium-based cookie imports).
- Providers: support ChatGPT Atlas browser data for Chromium cookie imports.
- Providers: accept Auth.js secure session cookies for Factory/Droid login detection.
- Providers: accept Factory auth session cookies (session/access-token) for Droid.
- Droid: surface Factory API errors instead of masking them as missing sessions.
- Droid: retry auth without access-token cookies when Factory flags a stale token.
- Droid: try all detected browser profiles before giving up.
- Droid: fall back to auth.factory.ai endpoints when cookies live on the auth host.
- Droid: use WorkOS refresh tokens from browser local storage when cookies fail.
- Droid: read WorkOS refresh tokens from Safari local storage.
- Droid: try stored/WorkOS tokens before Chrome cookies to reduce Chrome Safe Storage prompts.
- Menu: provider switcher bars now track primary quotas (Plan/Tokens/Pro), with Premium shown for Droid.
- Menu: avoid duplicate summary blocks when a provider has no action rows.
- OpenAI web: ignore cookie sets without session tokens to avoid false-positive dashboard fetches.
- Providers: hide z.ai in the menu until an API key is set.
- Menu: refresh runs automatically when opening the menu with a short retry (refresh row removed).
- Menu: hide the Status Page row when a provider has no status URL.
- Menu: align switcher bar with the “show usage as used” toggle.
- Antigravity: fix lsof port filtering by ANDing listen + pid conditions. Thanks @shaw-baobao!
- Claude: default to Claude Code OAuth usage API (credentials from Keychain or `~/.claude/.credentials.json`), with Debug selector + `--claude-source` CLI override (OAuth/Web/CLI).
- OpenAI web: allow importing any signed-in browser session when Codex email is unknown (first-run friendly).
- Core: Linux CLI builds now compile (mac-only WebKit/logging gated; FoundationNetworking imports where needed).
- Core: fix CI flake for Claude trust prompts by making PTY writes fully reliable.
- Core: Cursor provider is macOS-only (Linux CLI builds stub it).
- Core: make `RateWindow` equatable (used by OpenAI dashboard snapshots and tests).
- Tests: cover alias fallback resolution for Codex/Claude and add Linux platform gating coverage (run in CI).
- Tests: cover hiding Codex Credits + Claude Extra usage via the Advanced toggle.
- Docs: expand CLI docs for Linux install + flags.

## 0.14.0 — 2025-12-25
- New providers: Antigravity.
- Antigravity: new local provider for the Antigravity language server (Claude + Gemini quotas) with an experimental toggle; improved plan display + debug output; clearer not-running/port errors; hide account switch.
- Status: poll Google Workspace incidents for Gemini + Antigravity; Status Page opens the Workspace status page.
- Settings: add Providers tab; move ccusage + status toggles to General; keep display controls in Advanced.
- Menu/UI: widen the menu for four providers; cards/charts adapt to menu width; tighten provider switcher/toggle spacing; keep menus refreshed while open.
- Gemini: hide the dashboard action when unsupported.
- Claude: fix Extra usage spend/limit units (cents); improve CLI probe stability; surface web session info in Debug.
- OpenAI web: fix dashboard ghost overlay on desktop (WebKit keepalive window).
- Debug: add a debug-lldb build mode for troubleshooting.

## 0.13.0 — 2025-12-24
- Claude: add optional web-first usage via Safari/Chrome cookies (no CLI fallback) including “Extra usage” budget bar.
- Claude: web identity now uses `/api/account` for email + plan (via rate_limit_tier).
- Settings: standardize “Augment … via web” copy for Codex + Claude web cookie features.
- Debug: Claude dump now shows web strategy, cookie discovery, HTTP status codes, and parsed summary.
- Dev: add Claude web probe CLI to enumerate endpoints/fields using browser cookies.
- Tests: add unit coverage for Claude web API usage, overage, and account parsing.
- Menu: custom menu items now use the native selection highlight color (plus matching selection text/track colors).
- Charts: boost hover highlight contrast for credits/usage history bands.
- Menu: reorder Codex blocks to show credits before cost.
- Menu: split Claude “Extra usage” (no submenu) from “Cost” (history submenu) and trim redundant extra-usage subtext.

## 0.12.0 — 2025-12-23
- Widgets: add WidgetKit extension backed by a shared app‑group usage snapshot.
- New local cost usage tracking (Codex + Claude) via a lightweight scanner — inspired by ccusage (MIT). Computes cost from local JSONL logs without Node CLIs. Thanks @ryoppippi!
- Cost summary now includes last‑30‑days tokens; weekly pace indicators (with runout copy) hide when usage is fully depleted. Thanks @Remedy92!
- Claude: PTY probes now stop after idle, auto‑clean on restart, and run under a watchdog to avoid runaway CLI processes.
- Menu polish: group history under card sections, simplify history labels, and refresh menus live while open.
- Performance: faster usage log scanning + cost parsing; cache menu icons and speed up OpenAI dashboard parsing.
- Sparkle: auto-download updates when auto-check is enabled, and only show the restart menu entry once an update is ready.
- Widgets: experimental WidgetKit extension (may require restarting the widget gallery/Dock to appear).
- Credits: show credits as a progress bar and add a credits history chart when OpenAI web data is available.
- Credits: move “Buy Credits…” into its own menu item and improve auto-start checkout flow.

## 0.11.2 — 2025-12-21
- ccusage-codex cost fetch is faster and more reliable by limiting the session scan window.
- Fix ccusage cost fetch hanging for large Codex histories by draining subprocess output while commands run.
- Fix merged-icon loading animation when another provider is fetching (only the selected provider animates).
- CLI PATH capture now uses an interactive login shell and merges with the app PATH, fixing missing Node/Codex/Claude/Gemini resolution for NVM-style installs.

## 0.11.1 — 2025-12-21
- Gemini OAuth token refresh now supports Bun/npm installations. Thanks @ben-vargas!

## 0.11.0 — 2025-12-21
- New optional cost display in the menu (session + last 30 days), powered by ccusage. Thanks @Xuanwo!
- Fix loading-state card spacing to avoid double separators.

## 0.10.0 — 2025-12-20
- Gemini provider support (usage, plan detection, login flow). Thanks @381181295!
- Unified menu bar icon mode with a provider switcher and Merge Icons toggle (default on when multiple providers are enabled). Thanks @ibehnam!
- Fix regression from 0.9.1 where CLI detection failed for some installs by restoring interactive login-shell PATH loading.

## 0.9.1 — 2025-12-19
- CLI resolution now uses the login shell PATH directly (no more heuristic path scanning), so Codex/Claude match your shell config reliably.

## 0.9.0 — 2025-12-19
- New optional OpenAI web access: reuses your signed-in Safari/Chrome session to show **Code review remaining**, **Usage breakdown**, and **Credits usage history** in the menu (no credentials stored).
- Credits still come from the Codex CLI; OpenAI web access is only used for the dashboard extras above.
- OpenAI web sessions auto-sync to the Codex CLI email, support multiple accounts, and reset/re-import cookies on account switches to avoid stale cross-account data.
- Fix Chrome cookie import (macOS 10): signed-in Chrome sessions are detected reliably (thanks @tobihagemann!).
- Usage breakdown submenu: compact chart with hover details for day/service totals.
- New “Show usage as used” toggle to invert progress bars (default remains “% left”, now in Advanced).
- Session (5-hour) reset now shows a relative countdown (“Resets in 3h 31m”) in the menu card for Codex and Claude.
- Claude: fix reset parsing so “Resets …” can’t be mis-attributed to the wrong window (session vs weekly).

## 0.8.1 — 2025-12-17
- Claude trust prompts (“Do you trust the files in this folder?”) are now auto-accepted during probes to prevent stuck refreshes. Thanks @tobihagemann!

## 0.8.0 — 2025-12-17
- CodexBar is now available via Homebrew: `brew install --cask steipete/tap/codexbar` (updates via `brew upgrade --cask steipete/tap/codexbar`).
- Added session quota notifications for the sliding 5-hour window (Codex + Claude): notifies when it hits 0% and when it’s available again, based only on observed refresh data (including startup when already depleted). Thanks @GKannanDev!

## 0.7.3 — 2025-12-17
- Claude Enterprise accounts whose Claude Code `/usage` panel only shows “Current session” no longer fail parsing; weekly usage is treated as unavailable (fixes #19).

## 0.7.2 — 2025-12-13
- Claude “Open Dashboard” now routes subscription accounts (Max/Pro/Ultra/Team) to the usage page instead of the API console billing page. Thanks @auroraflux!
- Codex/Claude binary resolution now detects mise/rtx installs (shims and newest installed tool version), fixing missing CLI detection for mise users. Thanks @philipp-spiess!
- Claude usage/status probes now auto-accept the first-run “Ready to code here?” permission prompt (when launched from Finder), preventing timeouts and parse errors. Thanks @alexissan!
- General preferences now surface full Codex/Claude fetch errors with one-click copy and expandable details, reducing first-run confusion when a CLI is missing.
- Polished the menu bar “critter” icons: Claude is now a crisper, blockier pixel crab, and Codex has punchier eyes with reduced blurring in SwiftUI/menu rendering.

## 0.7.1 — 2025-12-09
- Menu bar icons now render on a true 18 pt/2× backing with pixel-aligned bars and overlays for noticeably crisper edges.
- PTY runner now preserves the caller’s environment (HOME/TERM/bun installs) while enriching PATH, preventing Codex/Claude
  probes from failing when CLIs are installed via bun/nvm or need their auth/config paths.
- Added regression tests to lock in the enriched environment behavior.
- Fixed a first-launch crash on macOS 26 caused by the 1×1 keepalive window triggering endless constraint updates; the hidden
  window now uses a safe size and no longer spams SwiftUI state warnings.
- Menu action rows now ship with SF Symbol icons (refresh, dashboard, status, settings, about, quit, copy error) for clearer at-a-glance affordances.
- When the Codex CLI is missing, menu and CLI now surface an actionable install hint (`npm i -g @openai/codex` / bun) instead of a generic PATH error.
- Node manager (nvm/fnm) resolution corrected so codex/claude binaries — and their `node` — are found reliably even when installed via fnm aliases or nvm defaults. Thanks @aliceisjustplaying for surfacing the gaps.
- Login menu now shows phase-specific subtitles and disables interaction while running: “Requesting login…” while starting the CLI, then “Waiting in browser…” once the auth URL is printed; success still triggers the macOS notification.
- Login state is tracked per provider so Codex and Claude icons/menus no longer share the same in-flight status when switching accounts.
- Claude login PTY runner detects the auth URL without clearing buffers, keeps the session alive until confirmation, and exposes a Sendable phase callback used by the menu.
- Claude CLI detection now includes Claude Code’s self-updating paths (`~/.claude/local/claude`, `~/.claude/bin/claude`) so PTY probes work even when only the bundled installer is used.

## 0.7.0 — 2025-12-07
- ✨ New rich menu card with inline progress bars and reset times for each provider, giving the menu a beautiful, at-a-glance dashboard feel (credit: Anton Sotkov @antons).

## 0.6.1 — 2025-12-07
- Claude CLI probes stop passing `--dangerously-skip-permissions`, aligning with the default permission prompt and avoiding hidden first-run failures.

## 0.6.0 — 2025-12-04
- New bundled CLI (`codexbar`) with single `usage` command, `--format text|json`, `--status`, and fast `-h/-V`.
- CLI output now shows consistent headers (`Codex 0.x.y (codex-cli)`, `Claude Code <ver> (claude)`) and JSON includes `source` + `status`.
- Advanced prefs install button symlinks `codexbar` into /usr/local/bin and /opt/homebrew/bin; docs refreshed.

## 0.5.7 — 2025-11-26
- Status Page and Usage Dashboard menu actions now honor the icon you click; Codex menus no longer open the Claude status site.

## 0.5.6 — 2025-11-25
- New playful “Surprise me” option adds occasional blinks/tilts/wiggles to the menu bar icons (one random effect at a time) plus a Debug “Blink now” trigger.
- Preferences now include an Advanced tab (refresh cadence, Surprise me toggle, Debug visibility); window height trimmed ~20% for a tighter fit.
- Motion timing eased and lengthened so blinks/wiggles feel smoother and less twitchy.

## 0.5.5 — 2025-11-25
- Claude usage scrape now recognizes the new “Current week (Sonnet only)” bar while keeping the legacy Opus label as a fallback.
- Menu and docs now label the Claude tertiary limit as Sonnet to match the latest CLI wording.
- PATH seeding now uses a deterministic binary locator plus a one-shot login-shell capture at startup (no globbed nvm paths); the Debug tab shows the resolved Codex binary and effective PATH layers.

## 0.5.4 — 2025-11-24
- Status blurb under “Status Page” no longer prefixes the text with “Status:”, keeping the incident description concise.
- PTY runner now registers cleanup before launch so both ends of the TTY and the process group are torn down even when `Process.run()` throws (no leaked fds when spawn fails).

## 0.5.3 — 2025-11-22
- Added a per-provider “Status Page” menu item beneath Usage that opens the provider’s live status page (OpenAI or Claude).
- Status API now refreshes alongside usage; incident states show a dot/! overlay on the status icon plus a status blurb under the menu item.
- General preferences now include a default-on “Check provider status” toggle above refresh cadence.

## 0.5.2 — 2025-11-22
- Release packaging now includes uploading the dSYM archive alongside the app zip to aid crash symbolication (policy documented in the shared mac release guide).
- Claude PTY fallback removed: Claude probes now rely solely on `script` stdout parsing, and the generic TTY runner is trimmed to Codex `/status` handling.
- Fixed a busy-loop on the codex RPC stderr pipe (handler now detaches on EOF), eliminating the long-running high-CPU spin reported in issue #9.

## 0.5.1 — 2025-11-22
- Debug pane now exposes the Claude parse dump toggle, keeping the captured raw scrape in memory for inspection.
- Claude About/debug views embed the current git hash so builds can be identified precisely.
- Minor runtime robustness tweaks in the PTY runner and usage fetcher.

## 0.5.0 — 2025-11-22
- Codex usage/credits now use the codex app-server RPC by default (with PTY `/status` fallback when RPC is unavailable), reducing flakiness and speeding refreshes.
- Codex CLI launches seed PATH with Homebrew/bun/npm/nvm/fnm defaults to avoid ENOENT in hardened/release builds; TTY probes reuse the same PATH.
- Claude CLI probe now runs `/usage` and `/status` in parallel (no simulated typing), captures reset strings, and uses a resilient parser (label-first with ordered fallback) while keeping org/email separate by provider.
- TTY runner now always tears down the spawned process group (even on early Claude login prompts) to avoid leaking CLI processes.
- Default refresh cadence is now 5 minutes, and a 15-minute option was added to the settings picker.
- Claude probes/version detection now start with `--allowed-tools ""` (tool access disabled) while keeping interactive PTY mode working.
- Codex probes and version detection now launch the CLI with `-s read-only -a untrusted` to keep PTY runs sandboxed.
- Codex warm-up screens (“data not available yet”) are handled gracefully: cached credits stay visible and the menu skips the scary parse error.
- Codex reset times are shown for both RPC and TTY fallback, and plan labels are capitalized while emails stay verbatim.

## 0.4.3 — 2025-11-21
- Fix status item creation timing on macOS 15 by deferring NSStatusItem setup to after launch; adds a regression test for the path.
- Menu bar icon with unknown usage now draws empty tracks (instead of a full bar when decorations are shown) by treating nil values as 0%.

## 0.4.2 — 2025-11-21
- Sparkle updates re-enabled in release builds (disabled only for the debug bundle ID).

## 0.4.1 — 2025-11-21
- Both Codex and Claude probes now run off the main thread (background PTY), avoiding menu/UI stalls during `/status` or `/usage` fetches.
- Codex credits stay available even when `/status` times out: cached values are kept and errors are surfaced separately.
- Claude/Codex provider autodetect runs on first launch (defaults to Codex if neither is installed) with a debug reset button.
- Sparkle updates re-enabled in release builds (disabled only for debug bundle ID).
- Claude probe now issues the `/usage` slash command directly to land on the Usage tab reliably and avoid palette misfires.

## 0.4.0 — 2025-11-21
- Claude Code support: dedicated Claude menu/icon plus dual-wired menus when both providers are enabled; shows email/org/plan and Sonnet usage with clickable errors.
- New Preferences window: General/About tabs with provider toggles, refresh cadence, start-at-login, and always-on Quit.
- Codex credits without web login: we now read `codex /status` in a PTY, auto-skip the update prompt, and parse session/weekly/credits; cached credits stay visible on transient timeouts.
- Resilience: longer PTY timeouts, cached-credit fallback, one-line menu errors, and clearer parse/update messages.

## 0.3.0 — 2025-11-18
- Credits support: reads Codex CLI `/status` via PTY (no browser login), shows remaining credits inline, and moves history to a submenu.
- Sign-in window with cookie reuse and a logout/clear-cookies action; waits out workspace picker and auto-navigates to usage page.
- Menu: credits line bolded; login prompt hides once credits load; debug toggle always visible (HTML dump).
- Icon: when weekly is empty, top bar becomes a thick credits bar (capped at 1k); otherwise bars stay 5h/weekly.

## 0.2.2 — 2025-11-17
- Menu bar icon stays static when no account/usage is present; loading animation only runs while fetching (12 fps) to keep idle CPU low.
- Usage refresh first tails the newest session log (512 KB window) before scanning everything, reducing IO on large Codex logs.
- Packaging/signing hardened: strip extended attributes, delete AppleDouble (`._*`) files, and re-sign Sparkle + app bundle to satisfy Gatekeeper.

## 0.2.1 — 2025-11-17
- Patch bump for refactor/relative-time changes; packaging scripts set to 0.2.1 (5).
- Streamlined Codex usage parsing: modern rate-limit handling, flexible reset time parsing, and account rate-limit updates (thanks @jazzyalex and https://jazzyalex.github.io/agent-sessions/).

## 0.2.0 — 2025-11-16
- CADisplayLink-based loading animations (macOS 15 displayLink API) with randomized patterns (Knight Rider, Cylon, outside-in, race, pulse) and debug replay cycling through all.
- Debug replay toggle (`defaults write com.o1xhack.codexbar debugMenuEnabled -bool YES`) to view every pattern.
- Usage Dashboard link in menu; menu layout tweaked.
- Updated time now shows relative formatting when fresher than 24h; refactored sources into smaller files for maintainability.
- Version bumped to 0.2.0 (4).

## 0.1.2 — 2025-11-16
- Animated loading icon (dual bars sweep until usage arrives); always uses rendered template icon.
- Sparkle embedding/signing fixed with deep+timestamp; notarization pipeline solid.
- Icon conversion scripted via ictool with docs.
- Menu: settings submenu, no GitHub item; About link clickable.

## 0.1.1 — 2025-11-16
- Launch-at-login toggle (SMAppService) and saved preference applied at startup.
- Sparkle auto-update wiring (SUFeedURL to GitHub, SUPublicEDKey set); Settings submenu with auto-update toggle + Check for Updates.
- Menu cleanup: settings grouped, GitHub menu removed, About link clickable.
- Usage parser scans newest session logs until it finds `token_count` events.
- Icon pipeline fixed: regenerated `.icns` via ictool with proper transparency (docs in docs/icon.md).
- Added lint/format configs, Swift Testing, strict concurrency, and usage parser tests.
- Notarized release build "CodexBar-0.1.0.zip" remains current artifact; app version 0.1.1.

## 0.1.0 — 2025-11-16
- Initial CodexBar release: macOS 15+ menu bar app, no Dock icon.
- Reads latest Codex CLI `token_count` events from session logs (5h + weekly usage, reset times); no extra login or browser scraping.
- Shows account email/plan decoded locally from `auth.json`.
- Horizontal dual-bar icon (top = 5h, bottom = weekly); dims on errors.
- Configurable refresh cadence, manual refresh, and About links.
- Async off-main log parsing for responsiveness; strict-concurrency build flags enabled.
- Packaging + signing/notarization scripts (arm64); build scripts convert `.icon` bundle to `.icns`.
