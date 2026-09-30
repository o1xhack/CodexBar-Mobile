---
summary: "Aixy API-key setup, key-scoped usage, and applicable budget balances."
read_when:
  - Configuring Aixy usage tracking
  - Troubleshooting Aixy budgets or reporting access
---

# Aixy

[Aixy](https://aixy-gateway.com) is an AI gateway using customer-configured provider credentials. CodexBar reads key-scoped usage and applicable budgets without calling model providers, making inference requests, or using administrator credentials or browser sessions.

## Setup

In Settings → Providers → Aixy, enter the project-scoped API key used by your workload. Leave **Base URL** empty for `https://api.aixy-gateway.com`, or set a self-hosted/dedicated gateway. The key reports its traffic across machines and is capable of inference; it is not read-only.

Equivalent provider configuration:

```json
{
  "id": "aixy",
  "enabled": true,
  "apiKey": "<AIXY_API_KEY>",
  "enterpriseHost": "https://api.aixy-gateway.com"
}
```

`enterpriseHost` is optional. Environment variables are `AIXY_API_KEY` and `AIXY_BASE_URL`.
The CLI uses `codexbar usage --provider aixy --source api`.

Base URLs may include a path prefix and trailing `/v1`. Public hosts require HTTPS; loopback, private-network, and `.local` HTTP are supported. Embedded credentials, query strings, and fragments are rejected. Keys are stored in provider-config/token-account storage and sent only to the selected gateway origin.

Only the Automatic menu bar metric is offered because the selected budget depends on the current applicable limits.

## Data source and display

The provider calls `GET {baseURL}/v1/usage` with `Authorization: Bearer <AIXY_API_KEY>`. See Aixy's [API documentation](https://docs.aixy-gateway.com) and [usage guidance](https://docs.aixy-gateway.com/observe/usage).

- **Budgets:** applicable key, user, team, project, and organization limits. Hard limits rank first, then highest utilization among known balances. The first two become primary/secondary; others remain named windows. Labels identify scope, period, shared/personal allocation, and hard/monitor enforcement. Overlapping limits are never summed.
- **Hard availability:** settled ledger spend plus outstanding reservations, separated in details. Reservations are not confirmed provider charges. Monitor budgets use recorded spend. Unknown balances show **Unavailable**, retaining supplied reset metadata.
- **Resets:** supplied by Aixy, including calendar-month boundaries; lifetime budgets have no invented reset. Exhausted hard budgets remain reportable.
- **This key's usage:** requests, tokens, attributed USD spend, and attribution coverage for the retained last seven days, independent of budget cycles and potentially lagging enforcement. Estimated/partial spend is not an invoice. Missing analytics are not zero; explicit zero spend shows $0.00 alongside budgets.
- **No budgets:** usage stays visible without an invented quota or balance. Returned key/project labels identify scope; email and organization identity are never guessed.

Inactive keys (including disabled, revoked, or expired keys) return an authentication error. A 404 means the gateway lacks the usage endpoint or the base URL is wrong. There is no browser-cookie or inference fallback. Prefer refresh intervals of at least one minute.

## Operator and access model

Aixy's [legal notice](https://aixy-gateway.com/legal-notice/) identifies the hosted operator and jurisdiction. Upstream access uses customer credentials; this integration does not provide or resell model access. Self-hosted gateways use the same reporting contract.
