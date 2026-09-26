---
summary: "Bifrost provider setup and usage data shape."
read_when:
  - Configuring Bifrost usage tracking
  - Troubleshooting Bifrost virtual-key usage in CodexBar
---

# Bifrost

[Bifrost](https://github.com/maximhq/bifrost) is a self-hosted AI gateway. CodexBar reads a virtual key's own
governance budgets and rate limits through Bifrost's self-service quota endpoint — no admin/master credential is
required or used.

The bundled TypeScript plugin owns quota fetching and parsing on both QuickJS and JavaScriptCore. Swift supplies
registration, endpoint validation, and the standard virtual-key/Base URL settings. There is no native fetch fallback.

Configure it in Settings -> Providers -> Bifrost, or add this provider entry to the `providers` array in
`~/.codexbar/config.json`:

```json
{
  "id": "bifrost",
  "enabled": true,
  "apiKey": "<BIFROST_API_KEY>",
  "enterpriseHost": "https://bifrost.example.com"
}
```

Equivalent environment variables:

```bash
export BIFROST_API_KEY=vk-...
export BIFROST_BASE_URL=https://bifrost.example.com
```

Both the virtual key and the base URL are required; Bifrost has no default public host and CodexBar does not guess
one. The base URL must use HTTPS unless it names a loopback or private-network address, or a `.local` mDNS host, and
must not embed credentials because the key is sent to it as a header. Plain HTTP remains available for self-hosted
gateways on loopback, RFC 1918, link-local, and IPv6 unique-local networks. A base URL that does not meet these rules
is rejected, and the provider reports that `BIFROST_BASE_URL` is invalid instead of fetching.

## Data Source

The provider calls:

```
GET {baseURL}/api/governance/virtual-keys/quota
x-bf-vk: <virtual key>
```

This is a self-service endpoint scoped to the calling virtual key — it ships in Bifrost's open-source edition with no
admin middleware, and CodexBar never requests or stores a Bifrost admin/master key.

The response's budgets are ordered by shortest reset cycle: the shortest is the primary window, the next is the
secondary window, and any further budgets appear as additional named windows. Provider- and model-scoped budgets
and rate limits also appear as named windows, without being added into the key-wide spend total. Rate limits (token
and request) appear alongside budgets. Per-model spend for the primary key-wide budget is shown as a details section
when Bifrost's request logging provides it. An unlimited budget (`max_limit: 0`) keeps reported spend visible as an
API-spend row without inventing a quota window. A response without budget rows supplies no spend value.
A disabled key (`is_active: false`) keeps showing its remaining budgets and rate limits with an
inactive-key marker, rather than being treated as an error, unless it has neither budgets nor rate limits.

When `rate_limits` contains components, each source supplies its own token/request windows and usage. The singular
`rate_limit` is Bifrost's tightest-per-dimension compatibility merge of those components, not a separate total or pool,
so it is used only when the component list is absent, null, or empty. Source names remain visible even on the first
component. Rate-window IDs use the scope, dimension, and component position so reused or missing backend IDs cannot
drop another source's usage or produce duplicate rate-window IDs. See the upstream
[quota response schema](https://github.com/maximhq/bifrost/blob/main/docs/openapi/schemas/management/governance.yaml#L703).
A last-reset timestamp alone does not imply a configured token/request quota: Bifrost includes these timestamps for
unused dimensions too. A positive limit or a nonempty reset duration is required to display that dimension.

Bifrost's `override_amount`/`override_mode`/`override_cycles_remaining` fields determine the effective budget limit.
Duration shorthand supplies labels and orders budget windows. The quota response omits the owner's calendar-alignment
policy, so CodexBar does not guess reset dates or exact window lengths for `d`/`w`/`M`/`Q`/`Y` periods. Sub-day Go-style
durations such as `1h30m` retain their next reset date when `last_reset` is present.
Reset-only rate limits retain their reset metadata and display **Unavailable** instead of a measured 0% usage.
Budget detail bars use a consumed fraction capped at 100%; numeric spend remains uncapped, including overages.

Per-model rows normalize the upstream `model` ID for display: known AWS Bedrock cross-region geo (`us.`, `eu.`,
`apac.`, `global.`, `us-gov.`) and vendor (`anthropic.`, `amazon.`, `meta.`, …) prefixes, and the trailing Bedrock
revision suffix (`-v1:0`), are stripped, since `per_model_usage[].model` reports that ID verbatim — Bifrost's
`provider/model` request syntax is routing-only and does not shorten it. The `provider` field is shown as a
`provider · model` prefix only when a section actually spans more than one upstream provider; a single-provider
section shows the bare model name, matching every other provider's model rows. A normalization collision (two rows
resolving to the same label) falls back to the raw model ID for the affected rows instead of merging them.

A model entry that is zero on both cost and tokens — for example, a request that failed entirely inside Bifrost
before it could be billed or counted — is dropped rather than shown as an empty `$0.00` / `0 tokens` row; a request
that failed but still incurred cost or token usage still appears. If every model entry is empty this way, the
Models section is omitted entirely. The remaining rows are ranked by cost, then tokens, then model name, and only
the top 5 are shown; any further models are folded into a single "Other models" row reporting the remainder.

## Security

Treat Bifrost virtual keys as secrets. CodexBar stores configured keys only in provider config or token-account
storage and sends them only to the configured Bifrost base URL.
