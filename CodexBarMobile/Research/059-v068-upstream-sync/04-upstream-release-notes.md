# 上游 Release Notes 人工复核：v0.67.0–v0.68.0

Status: `done`
Source of truth: [steipete/CodexBar GitHub Releases](https://github.com/steipete/CodexBar/releases)

## v0.67.0 — 2026-09-26 UTC

正式页面：[CodexBar 0.67.0](https://github.com/steipete/CodexBar/releases/tag/v0.67.0)，发布 tag commit `e0286a895055e60ddaefa6a5f176f246aa2f05e4`。

- **功能与 provider**：跨菜单、Usage & Spend、CLI、HTTP 输出和 widgets 统一成本报告期；可导入导出带版本的 portable preferences；Stay Awake 与 credential-expiry notice 为可选 Mac 能力；plugin checkpoint；扩展 Burn Down provider quotas；增加 xKiro、Raycast、Aixy；LiteLLM model activity、Claude Admin workspace spend、Grok product shares；新增 12 种 spend currency。
- **数据与算法修正**：OpenCode Go daily/per-model token counts；长 ledger 默认先呈现最新 30 行且保留全量 totals/charts；Antigravity 独立 pin Gemini 与 Claude/GPT weekly percentages、尽量保留部分 history lower bound；Mistral plan-covered tokens 不误作 spend；保留 Codex direct-fork 累计 counter；daily reset 与当前 refresh clock 对齐。
- **安全 / 可靠性**：浏览器 cookie refusal 跨重启保留；凭证文件先私有 staging 再 atomic replace；QuickJS-NG 升到 0.17.0；缓存和 history 扫描复用以减少重复工作。
- **macOS/CLI 专属**：portable UI preference 文件、provider-switcher shortcuts、Stay Awake、menu/burn-down widgets、部分 key/region 选择与 local provider discovery 属于 Mac UI/本地配置；不会原样同步到 iPhone 或同步凭证/consent。

## v0.68.0 — 2026-09-27 UTC

正式页面：[CodexBar 0.68.0](https://github.com/steipete/CodexBar/releases/tag/v0.68.0)，发布 tag commit `7998bf66c796befcb91c38e6b1096e702e511481`。上游 `version.env` 为 Mac build `159`。

- **功能与 provider**：Mistral Vibe Monthly Plan 在 CLI、menu descriptor 和 widgets 可见；ClinePass 可复用已有 Cline browser session（不复制或刷新 token）；Muse Code 可选择 dev.meta.ai team quota，默认 cookies Off；Homebrew cask install 增加一键升级；plugin runtime 支持 host-encoded form POST、有限 POST enrichment 与时区感知月份计算。
- **成本与 provider details**：Codex session 标题 / 排序增加 local thread metadata 但在 Hide personal information 下遮蔽标题和 project；Nous Portal 纳入 Nous 计费的 OpenCodex ledger 并区分估算/无价格记录；web dashboard per browser 选择 Follow server / Used / Remaining；Cursor all-history 请求限制在 API 支持日期范围。
- **修复与安全**：Codex system-account daemon restart 解析 control-socket symlink，Usage Dashboard 指向当前 analytics；菜单栏正常退出/恢复更新后保持 status-item identity；Claude cache outage 时继续使用未过期的 memory credential；Venice 支持 Clerk session；plugin 超时/取消后 retire worker 再允许 retry。
- **macOS/Linux 专属**：Homebrew、自定义菜单栏启动诊断、Mistral Linux manual-cookie 支持、settings layout 与 browser dashboard preference 只属于各自平台。iOS 不模拟这些系统能力；只在 Mac push 中存在可安全映射的 provider usage 时显示其 quota / details。

## iOS 影响判断

优先核验的数据面：xKiro / Raycast / Aixy 新 provider IDs，LiteLLM/Claude Admin/Grok details，Antigravity partial lower-bound 与多 quota windows，Mistral Monthly Plan，Muse 选定 team quota，Nous cost ledger，Codex history/session privacy，以及新的 reset/window 字段。判断以最终 merged payload 和实际 view 为准；issue 自动生成的“初筛”不是代码证据。
