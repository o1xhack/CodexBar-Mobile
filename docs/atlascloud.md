---
summary: "Atlas Cloud account balance through its public billing API."
read_when:
  - Setting up or modifying the Atlas Cloud provider
---

# Atlas Cloud

Enable **Atlas Cloud** in Settings → Providers and enter a standard Atlas Cloud API key, or set
`ATLASCLOUD_API_KEY` for the CLI. The key is saved in CodexBar's local config file when entered in Settings.
Use `codexbar usage --provider atlascloud --source api` to fetch it.

The bundled JavaScript plugin reads `GET https://api.atlascloud.ai/public/v1/balance` with bearer authentication.
It displays the **account-wide available USD balance** from `available.value`, validating `object: "balance"`,
`scope: "account"`, and `available.currency: "usd"`. Account balance read permission is required: use the personal
account owner's key or an Account Admin/Finance key for a team. A public key ID (`ak_…`) cannot authenticate.

Zero and negative balances are preserved. Missing, malformed, or non-USD values fail the refresh rather than
becoming zero. The shared HTTP host bounds requests and retries transient failures. No percentage, reset,
spend history, or credit-line allowance is inferred from the balance. Coding Plan quotas are a separate meter
and are not included. No browser session or local credential discovery is used.

Sources: [Billing Public API](https://www.atlascloud.ai/docs/public-api),
[balance schema](https://www.atlascloud.ai/docs/public-api/balance), and
[balance and Coding Plan semantics](https://www.atlascloud.ai/docs/billing/credits).
