---
summary: "LiteLLM provider setup and usage data shape."
read_when:
  - Configuring LiteLLM usage tracking
  - Troubleshooting LiteLLM API-key usage in CodexBar
---

# LiteLLM

LiteLLM uses a virtual key plus the proxy base URL. The key reads its own identity and budget data through LiteLLM's
authenticated information endpoints, with a spend-report fallback for deployments that disable management access.

Configure it in Settings -> Providers -> LiteLLM, or in `~/.codexbar/config.json`:

```json
{
  "id": "litellm",
  "enabled": true,
  "apiKey": "<LITELLM_API_KEY>",
  "enterpriseHost": "https://litellm.example.com"
}
```

Equivalent environment variables:

```bash
export LITELLM_API_KEY=sk-...
export LITELLM_BASE_URL=https://litellm.example.com
```

`LITELLM_BASE_URL` may include `/v1`; CodexBar strips that suffix before calling LiteLLM management endpoints.

The base URL must use HTTPS unless it names a loopback or private-network address, or a `.local` mDNS host,
and must not embed credentials because the API key is sent to it as a bearer token. Plain HTTP remains
available for self-hosted proxies on loopback, RFC 1918, link-local, and IPv6 unique-local networks. A base
URL that does not meet these rules is rejected, and the provider reports that `LITELLM_BASE_URL` is invalid
instead of fetching.

The bundled TypeScript provider runs on both plugin engines and preserves the same configured-origin validation,
including authenticated private-network and `.local` HTTP. The host attaches the bearer key; the plugin validates
key, user, and team identity before projecting spend and budgets.

## Data Source

The provider calls:

1. `GET /key/info` to discover the authenticated key's `user_id` and `team_id`.
2. `GET /user/info?user_id=<user_id>` to read personal spend, budget, and teams.
3. For team-only keys without a `user_id`, `GET /team/info?team_id=<team_id>` to read team spend and budget.

All requests use `Authorization: Bearer <apiKey>`. CodexBar does not request or store a LiteLLM master key.

For user-bound keys, personal usage is shown as the primary window. If the key has a team, its exact matching team
budget is shown as the secondary window and becomes the automatic menu bar metric because that budget is enforced for
the key. Team-only keys show that team budget as their sole usage window. Spend remains visible as an API-spend row
when LiteLLM does not configure a budget.

CLI text/cards and native menus show budget amounts as details, with actual reset dates separately; an absent reset
never turns the amount into a reset clock.

Budget tracking requires access to `/key/info` and the corresponding user or team information endpoint. CodexBar
validates returned user and team IDs against `/key/info` before displaying budget usage.

### Spend-only deployments

When `/key/info` returns HTTP 401, 403, or 404, CodexBar tries `GET /key/spend/report`. If that report also returns
401, 403, or 404, it tries `GET /user/spend/report`. These routes are deployment-dependent; the virtual key must be
permitted to read a self-scoped report. CodexBar sends only `start_date` (the first day of the current UTC month) and
`end_date` (today in UTC), without `api_key` or `internal_user_id` overrides.

The snapshot sums each row's `total_cost` once and labels the amount **Key spend only** or **User spend only**, with
the requested date range and UTC. A key total is never presented as a user total, and model subtotals are not added
again. CLI text and cards preserve the spend label and currency amount without displaying a zero budget denominator.
The reporting period is calendar month-to-date, which may differ from the server's budget window.

Spend reports do not supply budgets, remaining percentages, reset dates, or account identity in the supported row
shape, so those fields remain unavailable. Returned `api_key` identifiers are neither displayed nor logged. The
shared snapshot model uses `limit: 0` to represent an absent budget; no quota window is created. An explicit numeric
zero spend is valid, while empty, malformed, or unavailable reports remain errors. Other management failures and
report rate limits, server errors, or transport failures are not hidden by fallback.

## Security

Treat LiteLLM keys as secrets. CodexBar stores configured keys only in provider config or token-account storage and
sends them only to the configured LiteLLM base URL.
