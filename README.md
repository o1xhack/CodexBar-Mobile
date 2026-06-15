# CodexBar iOS

[🇨🇳 简体中文](README.zh.md)

> **iPhone companion app for CodexBar.** Pulls every provider's usage from your Mac over iCloud, renders it as full-quality cards on your phone, and pushes a notification the moment any provider's quota hits zero.
>
> **This repository is the iOS app fork.** The Mac app lives in this same repo (forked from upstream) — **please download Mac builds from [our Releases page](https://github.com/o1xhack/CodexBar-Mobile/releases)**, not from the upstream repo. The iOS app you install from the App Store is wire-locked to the Mac builds we ship here, and a mismatched upstream build will produce subtle data drift on your iPhone.

<p>
  <a href="https://apps.apple.com/app/id6760216772"><img src="https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83" alt="Download on the App Store" height="56"></a>
  <a href="https://github.com/o1xhack/CodexBar-Mobile/releases"><img src="https://codexbarios.o1xhack.com/assets/badges/download-for-mac.svg" alt="Download Mac App" height="56"></a>
</p>

🌐 [codexbarios.o1xhack.com](https://codexbarios.o1xhack.com) · 💻 [Mac app — GitHub Releases](https://github.com/o1xhack/CodexBar-Mobile/releases) · 🐦 [@o1xhack](https://x.com/o1xhack)

## Highlights · 1.5.0

<p align="center">
  <a href="CodexBarMobile/AppStoreScreenshots/v1-styled-en/01-overview.png"><img src="CodexBarMobile/AppStoreScreenshots/v1-styled-en/01-overview.png" alt="Overview" width="180"></a>
  <a href="CodexBarMobile/AppStoreScreenshots/v1-styled-en/02-cost-overview.png"><img src="CodexBarMobile/AppStoreScreenshots/v1-styled-en/02-cost-overview.png" alt="Cost overview" width="180"></a>
  <a href="CodexBarMobile/AppStoreScreenshots/v1-styled-en/03-daily-spend.png"><img src="CodexBarMobile/AppStoreScreenshots/v1-styled-en/03-daily-spend.png" alt="Daily Spend" width="180"></a>
  <a href="CodexBarMobile/AppStoreScreenshots/v1-styled-en/04-model-mix.png"><img src="CodexBarMobile/AppStoreScreenshots/v1-styled-en/04-model-mix.png" alt="Model Mix" width="180"></a>
  <a href="CodexBarMobile/AppStoreScreenshots/v1-styled-en/05-share-cards.png"><img src="CodexBarMobile/AppStoreScreenshots/v1-styled-en/05-share-cards.png" alt="Share cards" width="180"></a>
</p>

- **Full sync** — all 30+ providers (Codex, Claude, Cursor, Gemini, Grok, GroqCloud, ElevenLabs, Deepgram, LLM Proxy, Vertex AI, Mistral, Abacus AI, Perplexity, Synthetic, …) refreshed from your Mac via iCloud silent push within ~500 ms. One screen, no manual reload.
- **Cost dashboard** — Daily Spend with 30-day chart, per-provider share, per-model breakdown, and renewal-cycle progress. Estimated rates kick in for newly-released models so a fresh `gpt-5.x` never silently drops the day to $0.
- **Share cards** — one-tap share images for any usage or cost view, clean dark-mode design with a QR back to the website. Ready for X, WeChat, Slack, or anywhere else you brag about token spend.

---

# CodexBar 🎚️ - May your tokens never run out.

Tiny macOS 14+ menu bar app that keeps your Codex, Claude, Cursor, Gemini, Grok, GroqCloud, ElevenLabs, Deepgram, Antigravity, Droid (Factory), Copilot, z.ai, MiniMax, Kiro, Vertex AI, Augment, Amp, JetBrains AI, OpenRouter, LLM Proxy, Perplexity, and Abacus AI limits visible (session + weekly where available) and shows when each window resets. One status item per provider (or Merge Icons mode with a provider switcher and optional Overview tab); enable what you use from Settings. No Dock icon, minimal UI, dynamic bar icons in the menu bar.

<img src="codexbar.png" alt="CodexBar menu screenshot" width="520" />

## Install

### Requirements
- macOS 14+ (Sonoma)

### GitHub Releases
Download: <https://github.com/steipete/CodexBar/releases>

### Homebrew
```bash
brew install --cask codexbar
```

### Linux (CLI only)
```bash
brew install steipete/tap/codexbar
```
Or download `CodexBarCLI-v<tag>-linux-<arch>.tar.gz` from GitHub Releases.
Linux support via Omarchy: community Waybar module and TUI, driven by the `codexbar` executable.

### First run
- Open Settings → Providers and enable what you use.
- Install/sign in to the provider sources you rely on (e.g. `codex`, `claude`, `gemini`, browser cookies, or OAuth; Antigravity requires the Antigravity app running).
- Optional: Settings → Providers → Codex → OpenAI cookies (Automatic or Manual) to add dashboard extras.

### Set API keys from the CLI
Provider toggles and API keys live in `~/.codexbar/config.json`. You can script the same provider list that Settings → Providers uses:

```bash
codexbar config providers
codexbar config enable --provider grok
codexbar config disable --provider cursor
```

For API-key providers, store a key without opening Settings:

```bash
printf '%s' "$ELEVENLABS_API_KEY" | codexbar config set-api-key --provider elevenlabs --stdin
```

`set-api-key` trims the piped value, stores it with restrictive config-file permissions, and enables the provider by default. Use `--no-enable` to only save the key, or `--api-key <key>` for one-off local scripts where shell history is not a concern.
See [CLI configuration](docs/cli-configuration.md) for the full flow.

## Providers

- [Codex](docs/codex.md) — OAuth API or local Codex CLI, plus optional OpenAI web dashboard extras.
- [OpenAI](docs/openai.md) — Admin API key usage/cost graphs with legacy credit-balance fallback.
- [Claude](docs/claude.md) — OAuth API, browser cookies, or CLI PTY fallback; session and weekly usage where available.
- [Cursor](docs/cursor.md) — Browser session cookies for plan + usage + billing resets.
- [OpenCode](docs/opencode.md) — Browser cookies for workspace subscription usage.
- [OpenCode Go](docs/opencode.md) — Browser cookies for Go usage windows.
- [Alibaba Coding Plan](docs/alibaba-coding-plan.md) — Web cookies or API key for coding-plan quotas.
- [Alibaba Token Plan](docs/alibaba-token-plan.md) — Bailian browser/manual cookies for token-plan credits.
- [Gemini](docs/gemini.md) — OAuth-backed quota API using Gemini CLI credentials (no browser cookies).
- [Antigravity](docs/antigravity.md) — Local language server probe (experimental); no external auth.
- [Droid](docs/factory.md) — Browser cookies + WorkOS token flows for Factory usage + billing.
- [Copilot](docs/copilot.md) — GitHub device flow + Copilot internal usage API.
- [Devin](docs/devin.md) — Chrome localStorage session or manual Bearer token for daily and weekly quotas.
- [z.ai](docs/zai.md) — API token (Keychain) for quota + MCP windows.
- [Manus](docs/manus.md) — Browser `session_id` auth for credit balance, monthly credits, and daily refresh tracking.
- [MiniMax](docs/minimax.md) — API token, cookie header, or browser cookies for coding-plan usage.
- [T3 Chat](docs/providers.md#t3-chat) — Browser cookies capture for Base and Overage usage buckets.
- [Kimi](docs/kimi.md) — Auth token (JWT from `kimi-auth` cookie) for weekly quota + 5‑hour rate limit.
- [Kimi K2 (unofficial)](docs/kimi-k2.md) — Legacy API key flow for credit-based usage totals.
- [Kilo](docs/kilo.md) — API token with CLI-auth fallback for Kilo Pass usage.
- [Kiro](docs/kiro.md) — CLI-based usage; monthly credits + bonus credits.
- [Vertex AI](docs/vertexai.md) — Google Cloud gcloud OAuth with token cost tracking from local Claude logs.
- [Augment](docs/augment.md) — Browser cookie-based authentication with automatic session keepalive; credits tracking and usage monitoring.
- [Amp](docs/amp.md) — Browser cookie-based authentication with Amp Free usage tracking.
- [JetBrains AI](docs/jetbrains.md) — Local XML-based quota from JetBrains IDE configuration; monthly credits tracking.
- [Warp](docs/warp.md) — API token for GraphQL request limits and monthly credits.
- [ElevenLabs](docs/elevenlabs.md) — API key for character credits and voice slot usage.
- [OpenRouter](docs/openrouter.md) — API token for credit-based usage tracking across multiple AI providers.
- [Windsurf](docs/windsurf.md) — Browser localStorage session import or local SQLite cache for plan usage.
- Perplexity — Account usage credits from Perplexity usage data.
- [Xiaomi MiMo](docs/mimo.md) — Browser cookies for balance and token-plan usage.
- [Doubao](docs/doubao.md) — API key for Volcengine Ark request-limit probes.
- [Abacus AI](docs/abacus.md) — Browser cookie auth for ChatLLM/RouteLLM compute credit tracking.
- Mistral — Browser cookies for monthly spend tracking.
- [DeepSeek](docs/deepseek.md) — API key for credit balance tracking (paid vs. granted breakdown).
- [Moonshot / Kimi API](docs/moonshot.md) — API key for Moonshot/Kimi API account balance tracking.
- [Venice](docs/venice.md) — API key for DIEM or USD balance tracking.
- [Codebuff](docs/codebuff.md) — API token (or `~/.config/manicode/credentials.json`) for credit balance + weekly rate limit.
- [Crof](docs/crof.md) — API key for dollar credit balance and request quota tracking.
- [Command Code](docs/command-code.md) — Browser cookies for monthly USD credits from Command Code billing.
- [StepFun](docs/stepfun.md) — Username + password login for Step Plan rate limits (5‑hour + weekly windows) and subscription plan name.
- [AWS Bedrock](docs/bedrock.md) — AWS access keys or a named AWS profile (SSO/assume-role via the AWS CLI) for Cost Explorer usage and monthly budget tracking.
- [Grok](docs/grok.md) — Grok CLI billing RPC plus grok.com browser-session fallback.
- [GroqCloud](docs/groqcloud.md) — API key for Enterprise Prometheus request/token/cache-hit metrics.
- [LLM Proxy](docs/llm-proxy.md) — API key + base URL for aggregate proxy quota stats and provider breakdowns.
- [Deepgram](docs/deepgram.md) — API key usage summaries across speech, agent, token, and TTS metrics.
- Open to new providers: [provider authoring guide](docs/provider.md).

## Icon & Screenshot
The menu bar icon is a tiny two-bar meter:
- Top bar: 5‑hour/session window. If weekly is missing/exhausted and credits are available, it becomes a thicker credits bar.
- Bottom bar: weekly window (hairline).
- Errors/stale data dim the icon; status overlays indicate incidents.

## Features
- Multi-provider menu bar with per-provider toggles (Settings → Providers).
- Session + weekly meters with reset countdowns.
- Optional Codex web dashboard enrichments (code review remaining, usage breakdown, credits history).
- Inline spend and usage charts for API-backed providers such as OpenAI, Claude Admin API, OpenRouter, z.ai, MiniMax, Mistral, and AWS Bedrock.
- Configurable cost-usage scans for Codex + Claude, plus reused chart UI for supported provider histories.
- Provider status polling with incident badges in the menu and icon overlay.
- Merge Icons mode to combine providers into one status item + switcher, with an optional Overview tab for up to three providers.
- Refresh cadence presets (manual, 1m, 2m, 5m, 15m).
- Bundled CLI (`codexbar`) for scripts and CI (including `codexbar cost --provider codex|claude` for local cost usage); Linux CLI builds available.
- WidgetKit widget mirrors the menu card snapshot.
- Privacy-first: on-device parsing by default; browser cookies are opt-in and reused (no passwords stored).

## Privacy note
Wondering if CodexBar scans your disk? It doesn’t crawl your filesystem; it reads a small set of known locations (browser cookies/local storage, local JSONL logs) when the related features are enabled. See the discussion and audit notes in [issue #12](https://github.com/steipete/CodexBar/issues/12).

## macOS permissions (why they’re needed)
- **Full Disk Access (optional)**: only required to read Safari cookies/local storage for web-based providers (Codex web, Claude web, Cursor, Droid/Factory). If you don’t grant it, use Chrome/Firefox cookies or CLI-only sources instead.
- **Keychain access (prompted by macOS)**:
  - Chrome cookie import needs the “Chrome Safe Storage” key to decrypt cookies.
  - Claude OAuth credentials (written by the Claude CLI) are read from Keychain when present.
  - z.ai API token is stored in Keychain from Preferences → Providers; Copilot stores its API token in Keychain during device flow.
  - **How do I prevent those keychain alerts?**
    - Open **Keychain Access.app** → login keychain → search the item (e.g., “Claude Code-credentials”).
    - Open the item → **Access Control** → add `CodexBar.app` under “Always allow access by these applications”.
    - Prefer adding just CodexBar (avoid “Allow all applications” unless you want it wide open).
    - Relaunch CodexBar after saving.
    - Reference screenshot: ![Keychain access control](docs/keychain-allow.png)
  - **How to do the same for the browser?**
    - Find the browser’s “Safe Storage” key (e.g., “Chrome Safe Storage”, “Brave Safe Storage”, “Firefox”, “Microsoft Edge Safe Storage”).
    - Open the item → **Access Control** → add `CodexBar.app` under “Always allow access by these applications”.
    - This removes the prompt when CodexBar decrypts cookies for that browser.
- **Files & Folders prompts (folder/volume access)**: CodexBar launches provider CLIs (codex/claude/gemini/antigravity). If those CLIs read a project directory or external drive, macOS may ask CodexBar for that folder/volume (e.g., Desktop or an external volume). This is driven by the CLI’s working directory, not background disk scanning.
- **What we do not request**: no Screen Recording, Accessibility, or Automation permissions; no passwords are stored (browser cookies are reused when you opt in).

## Docs
- Providers overview: [docs/providers.md](docs/providers.md)
- Provider authoring: [docs/provider.md](docs/provider.md)
- Issue labeling guide: [docs/ISSUE_LABELING.md](docs/ISSUE_LABELING.md)
- UI & icon notes: [docs/ui.md](docs/ui.md)
- CLI reference: [docs/cli.md](docs/cli.md)
- Configuration: [docs/configuration.md](docs/configuration.md)
- CLI configuration: [docs/cli-configuration.md](docs/cli-configuration.md)
- Widgets: [docs/widgets.md](docs/widgets.md)
- Architecture: [docs/architecture.md](docs/architecture.md)
- Refresh loop: [docs/refresh-loop.md](docs/refresh-loop.md)
- Status polling: [docs/status.md](docs/status.md)
- Sparkle updates: [docs/sparkle.md](docs/sparkle.md)
- Release checklist: [docs/RELEASING.md](docs/RELEASING.md)

## Getting started (dev)
- Clone the repo and open it in Xcode or run the scripts directly.
- Launch once, then toggle providers in Settings → Providers.
- Install/sign in to provider sources you rely on (CLIs, browser cookies, or OAuth).
- Optional: set OpenAI cookies (Automatic or Manual) for Codex dashboard extras.

## Build from source
```bash
swift build -c release          # or debug for development
./Scripts/package_app.sh        # builds CodexBar.app in-place
CODEXBAR_SIGNING=adhoc ./Scripts/package_app.sh  # ad-hoc signing (no Apple Developer account)
open CodexBar.app
```

Dev loop:
```bash
./Scripts/compile_and_run.sh
```

## Related
- ✂️ [Trimmy](https://github.com/steipete/Trimmy) — “Paste once, run once.” Flatten multi-line shell snippets so they paste and run.
- 🧳 [MCPorter](https://mcporter.dev) — TypeScript toolkit + CLI for Model Context Protocol servers.
- 🧿 [oracle](https://askoracle.dev) — Ask the oracle when you're stuck. Invoke GPT-5 Pro with a custom context and files.

## Looking for a Windows version?
- [Win-CodexBar](https://github.com/Finesssee/Win-CodexBar)

## Linux desktop integration?
- [codexbar-waybar](https://github.com/Marouan-chak/codexbar-waybar) — Waybar custom module + GTK4 popover for Hyprland / Sway / other Wayland compositors, built on top of the bundled Linux CLI.
- [Codexbar GNOME](https://extensions.gnome.org/extension/9841/codexbar/) — GNOME Shell extension that brings CodexBar usage into the desktop panel.
- [noctalia-codex-usage](https://github.com/rayoplateado/noctalia-codex-usage) — Noctalia/Quickshell plugin that shows Codex 5-hour and weekly usage limits, built on top of the bundled Linux CLI.


## Status bar & terminal integration
- [showy-quota](https://github.com/enieuwy/showy-quota) — always-on AI plan quota strips for SketchyBar, tmux, and Zellij (standalone WASM plugin), built on `codexbar serve` / the bundled CLI.

## Credits
Inspired by [ccusage](https://github.com/ryoppippi/ccusage) (MIT), specifically the cost usage tracking.

## License
MIT • Peter Steinberger ([steipete](https://twitter.com/steipete))
