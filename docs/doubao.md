---
summary: "Doubao provider notes: arkcli plan usage, API-key auth, and Volcengine Ark request limits."
read_when:
  - Adding or modifying the Doubao provider
  - Debugging Doubao API-key setup
  - Explaining Doubao usage display
---

# Doubao Provider

Doubao reads Coding Plan and Agent Plan quota windows from the official `arkcli` CLI. Existing Volcengine AK/SK credentials and Ark API-key request-limit probes remain supported.

## Setup
1. Enable **Doubao** in Settings → Providers.
2. Install `arkcli`, then run `arkcli auth login`.
3. Refresh provider usage. CodexBar resolves `arkcli` through `ARKCLI_PATH`, the login-shell/host `PATH`, and standard install locations.

To keep using API credentials instead, paste an API key or AK/SK pair in provider settings. Environment variables `ARK_API_KEY`, `VOLCENGINE_API_KEY`, and `DOUBAO_API_KEY` remain supported.

### Multiple Ark API keys

Use **Doubao API-key accounts** in Settings → Providers → Doubao to save labeled Ark API keys. The shared account
switcher selects the active account, and the account view can show each saved key's usage. Each saved account uses
the API route; CLI account selection also overrides a saved CLI source preference. Removing all saved accounts
restores the existing single-account behavior without changing stored source preferences or provider-wide credentials.

For CLI usage, select a saved account with `codexbar usage --provider doubao --account <label>` or fetch all saved
keys with `codexbar usage --provider doubao --all-accounts`. Selected keys are isolated from provider-wide and
environment API keys, AK/SK pairs, and the ambient arkcli session; a failed key never falls back to another account.

These entries accept Ark API keys only. Multiple AK/SK pairs and arkcli SSO profiles are not supported by this
account editor. API keys expose the existing Coding Plan request-limit probe, not the richer arkcli/AK-SK plan
windows; valid keys without reliable request-limit headers still show limits as unavailable.

## Behavior
- Auto mode honors configured API credentials first so an ambient arkcli SSO session cannot silently switch accounts. Without configured credentials, it uses `arkcli usage plan --format json`.
- CLI mode uses only `arkcli`; API mode uses only configured AK/SK or Ark API-key credentials.
- `arkcli` output provides distinct personal and team Coding Plan and Agent Plan 5-hour, weekly, and monthly windows when those subscriptions are present.
- The menu bar icon uses personal Agent Plan 5-hour and weekly quotas when the corresponding Coding Plan lanes are absent. Coding Plan lanes keep priority; named Agent Plan windows remain separate in the card.
- Volcengine AK/SK mode checks Coding Plan and Agent Plan independently, so accounts subscribed to both show both sets of windows.
- Ark API-key endpoint: `POST https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions`
- Probe models: `doubao-seed-2.0-code`, `doubao-1.5-pro-32k`, `doubao-lite-32k`
- Reads `x-ratelimit-remaining-requests`, `x-ratelimit-limit-requests`, and `x-ratelimit-reset-requests` when returned.
- If the key is valid but rate-limit headers are missing, CodexBar shows the key as active and links to the dashboard for details.
- Agent Plan bearer keys for `/api/plan/v3/chat/completions` are not part of the arkcli usage path; see issue #1835.
