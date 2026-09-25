---
summary: "GitKraken AI weekly personal and organization usage through its first-party API."
read_when:
  - Setting up GitKraken AI usage
  - Debugging GitKraken authentication or usage
---

# GitKraken AI

Enable GitKraken AI in Settings → Providers. Auto and API both use the bundled TypeScript plugin
on macOS and Linux. It reads `https://api.gitkraken.dev/v1/ai-tasks/usage`; it never sends AI prompts.
The plugin host has no subprocess capability, so `gk ai tokens` fallback and CLI session discovery
are not supported. The CodexBar CLI accepts `--provider gitkraken` (alias `gk`) with `--source api`.

## Authentication

Use a GitKraken **account session access token**. Sign in to the
[account usage page](https://gitkraken.dev/account#ai-usage), inspect its successful usage request
in browser developer tools, and copy only the value after `Bearer ` from the Authorization header.
Paste it into **GitKraken access token**. For a particular organization, copy the matching `gk-org-id`
header into **API organization ID**. Replace expired tokens manually; no OAuth client or refresh flow is added.

| Setting | Config field | Environment variable |
| --- | --- | --- |
| Access token | `apiKey` | `GITKRAKEN_API_TOKEN` |
| Organization ID (optional) | `workspaceID` | `GITKRAKEN_ORG_ID` |

Configured values override environment values. The masked token field saves plaintext in the resolved
CodexBar config file, normally `~/.config/codexbar/config.json`; it does not use Keychain.
Shell exports do not normally reach Finder-launched apps. See [CLI configuration](cli-configuration.md).

## Usage

Personal and shared-pool bars show weekly credit utilization and the API's timezone-qualified reset.
Raw counts remain visible when usage exceeds the limit; bars clamp at 100%. A zero limit means
“No allowance”, while `-1` means “Unlimited”; neither creates an invented percentage.
Your shared usage is a slice of the organization total, separate from personal usage. Missing or malformed
organization data is omitted while valid personal usage remains available. Invalid primary data fails closed.

Only the declared HTTPS API origin receives the bearer token and optional organization header.
The host bounds requests to 15 seconds, rejects redirects, and classifies authentication, permission,
rate-limit, availability, and parse failures without displaying response bodies.
No browser import, token-cost history, balance estimate, or widget support is added.

Offline synthetic tests: `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 swift test --filter GitKrakenPluginTests`.
The API schema follows [GitLens's usage parser](https://github.com/gitkraken/vscode-gitlens/blob/9761f154e3b7ad4b51c510c830ef770628fb43c7/src/plus/ai/aiProviderService.ts).
The icon comes from [GitKraken's browser extension](https://github.com/gitkraken/gk-browser-extension/blob/main/src/hosts/github.ts).
