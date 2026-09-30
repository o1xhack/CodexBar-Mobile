---
summary: "Nous Portal provider: Hermes Agent OAuth token reuse, account endpoint parsing, and credit display."
read_when:
  - Debugging Nous Portal credit or subscription parsing
  - Explaining why CodexBar asks to run `hermes` to refresh the token
  - Updating Nous Portal setup or environment variables
---

# Nous Portal Provider

[Nous Portal](https://portal.nousresearch.com) is Nous Research's subscription and credit portal for the Hermes
inference API. Plans grant a monthly credit budget that resets each billing cycle; purchased credits top up the
balance on top of that grant.

## Authentication

Account and billing endpoints require the Hermes Agent device-code OAuth login. Inference API keys work only for `/v1/chat/completions` and `/v1/completions`, not credits. CodexBar runs no login and stores no Nous secrets:

1. Sign in once with Hermes Agent (`hermes` and choose Nous Portal, or `hermes auth add nous`).
2. Hermes writes the token to `~/.hermes/auth.json` (and a cross-profile copy to `~/.hermes/shared/nous_auth.json`).
3. CodexBar reads the access token from those files on every refresh.

Overrides:

- `HERMES_HOME`: directory holding `auth.json` when Hermes runs from a custom root or profile. It is exclusive: when
  set, `~/.hermes` is never consulted, so a missing or expired custom profile reports an error rather than silently
  using another profile's login.
- `NOUS_PORTAL_ACCESS_TOKEN`: use this token instead of the Hermes files.
- `NOUS_PORTAL_BASE_URL` / `HERMES_PORTAL_BASE_URL`: point at a preview portal deployment. HTTPS only; plain HTTP
  is refused for every host, loopback included, and the default portal is used instead.

### Where the token is sent

The bearer token only ever goes to one origin, resolved in this order:

1. An explicit `NOUS_PORTAL_BASE_URL` / `HERMES_PORTAL_BASE_URL` override (HTTPS only, set by you).
2. The `portal_base_url` stored by Hermes, but only when its host is `nousresearch.com` or a subdomain.
3. `https://portal.nousresearch.com`.

A stored host outside `nousresearch.com` is ignored, logged as a warning, and reported in the verbose trace as
`rejectedStoredHost=<host>`; the request then goes to the default portal. Expired tokens, whether from the auth file or
from `NOUS_PORTAL_ACCESS_TOKEN`, are rejected before any request is made.

### Why CodexBar never refreshes the token

Access tokens last about an hour. Refresh tokens rotate on every use; replay revokes the entire session. To avoid logging Hermes out, CodexBar reads only the access token and asks you to run `hermes` when it expires. Any Hermes command or a running Hermes gateway renews it.

## Data Source

The `nous.ts` plugin makes one bearer request per refresh: `GET {portal}/api/oauth/account`. Swift resolves the Hermes credential and registers the provider.

| Field | Display |
| --- | --- |
| `subscription.monthly_credits`, `subscription.credits_remaining` | Primary meter "Monthly credits" as percent used |
| `subscription.current_period_end` | Meter reset time and renewal date |
| `subscription.plan` | Plan row (plan name only, e.g. `Ultra`) |
| `subscription.rollover_credits` | Subscription detail row when non-zero |
| `purchased_credits_remaining` | "Top-up credits" row in the Credits section |
| `paid_service_access.total_usable_credits` | Credits detail row |
| `user.email`, `organisation.name` | Identity (siloed to this provider) |

Money fields are accepted as finite JSON numbers or decimal strings. Missing amounts stay unavailable instead of
becoming zero; a monthly meter requires both a positive grant and a reported remaining balance. A Free tier with no
monthly grant shows no meter and only the reported purchased balance. Malformed amounts fail the refresh.

## Local usage and spend

Enable **Include OpenCodex usage logs** (default off) to attribute ledger rows with `provider: "nous"` to Nous in Usage & Spend. CodexBar reads `~/.opencodex/usage.jsonl` or `$OPENCODEX_HOME/usage.jsonl`, without running an extractor or reading Hermes's session database. These estimates retain the OpenCodex source label, separate from Portal credits. Nous has no native token-cost scanner; provider-level cost capability is disabled.

The [extractor supplied for #4008](https://github.com/steipete/CodexBar/issues/4008#issuecomment-5843400899)
writes `provider: "nous"`, epoch-second `timestamp` values, the exact inference `model` ID, and the standard
`usage` token counters. It emits one aggregate per session/model at `first_seen`, not one row per API call;
dashboard request counts therefore count ledger rows, and activity is dated to that first timestamp.
`usageStatus: "estimated"` rows use CodexBar's exact Nous/model catalog price or a custom pricing override.
Missing prices stay unpriced with token activity preserved; another vendor's rates are never inferred from a
model prefix. `unreported` rows retain tokens without a dollar estimate. See [model pricing](model-pricing.md).

The extractor's non-standard `_meta.hermesEstimatedCostUSD`, `_meta.costSource`, and `_meta.apiCalls` are ignored;
they are neither a pricing contract nor Portal-metered credits. Its `conversationID` spelling is also ignored
(the standard field is `conversationId`), so session grouping falls back to the unique `requestId`.

## CLI

```bash
codexbar usage --provider nous
```

Aliases: `nous-portal`, `hermes`. Source modes: `auto`, `api`.
