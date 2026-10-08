---
summary: "ClinePass API-key or browser sign-in setup and five-hour, weekly, and monthly subscription limits."
read_when:
  - Configuring ClinePass usage tracking
  - Debugging ClinePass credentials or usage-limit parsing
---

# ClinePass

ClinePass tracks subscription quota, separate from Cline pay-as-you-go balances. Enable it in Settings → Providers
and add an API key, or sign in with your browser via `cline auth` (no API key needed):

```bash
printf '%s' "$CLINE_API_KEY" | codexbar config set-api-key --provider clinepass --stdin
# or browser sign-in (writes ~/.cline/data/settings/providers.json, reused automatically):
cline auth
```

The CLI accepts `CLINE_API_KEY` or `CLINEPASS_API_KEY` from its environment, in that order, then falls back to the
`cline` OAuth session in Cline's `providers.json` (`workos:` bearer token, shared by `cline` and `cline-pass`).
CodexBar config and environment API keys take precedence over the session file. Within that file, Cline's own
[`getApiKey` resolver](https://github.com/cline/cline/blob/main/sdk/packages/core/src/auth/provider-auth-registry.ts)
prefers `auth.accessToken`, then `apiKey`, then `auth.apiKey`; CodexBar follows the same order. Source modes are
`auto` and `api`; both use the same bundled provider plugin on macOS and Linux.

The file read is local and read-only: CodexBar never starts a login flow, imports browser cookies, refreshes tokens,
or copies the session into its config. If Cline's access token expires, the error asks you to run `cline auth` again.
Keep Cline responsible for signing in and renewing its session. A stored Cline API key is also supported and remains
labeled **API key**; an OAuth session is labeled **Browser**.

The path follows Cline's overrides, in order: `CLINE_PROVIDER_SETTINGS_PATH` (a file), `CLINE_DATA_DIR`
(containing `settings/providers.json`), then `CLINE_DIR` (containing `data/settings/providers.json`). Otherwise it uses
`$HOME/.cline/data/settings/providers.json`. Only the `providers.cline.settings` entry is read; the same Cline entry
is used upstream for ClinePass. The reader ignores refresh tokens and unrelated providers.

## Multiple API keys

Settings → Providers → ClinePass stores labeled API keys for tracking several ClinePass subscriptions at once. The
selected account's key is injected as `CLINE_API_KEY` for that fetch, replacing the configured API key, an ambient
`CLINE_API_KEY` / `CLINEPASS_API_KEY`, and the `cline auth` session. Only the selected key is sent; a rejected
account never falls back to another credential. The menu bar account switcher and
`codexbar usage --provider clinepass --account <label>` (or `--all-accounts`) select accounts without editing files.
With no selected account, the existing configured-key, environment-key, and Cline-session precedence is unchanged.

## Data source

The plugin sends a bearer-authenticated `GET https://api.cline.bot/api/v1/users/me/plan/usage-limits` request.
Reported `five_hour`, `weekly`, and `monthly` limits map to the primary, secondary, and tertiary windows.
Each window uses the returned `percentUsed` and optional `resetsAt`; absent windows remain unavailable.
This endpoint does not provide pay-as-you-go balances or local cost history.

```bash
codexbar usage --provider clinepass --source api --format json --pretty
```

## Implementation

- `Sources/CodexBarCore/Providers/ClinePass/ClinePassProviderDescriptor.swift` owns metadata and source selection.
- `Sources/CodexBarCore/Providers/ClinePass/ClinePassSettingsReader.swift` resolves environment keys and the `cline auth`
  browser session (`~/.cline/data/settings/providers.json`, `workos:` bearer token).
- `Sources/CodexBarCore/Resources/Plugins/clinepass.ts` owns the request and response mapping; its JavaScript is generated.
