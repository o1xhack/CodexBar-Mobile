---
summary: "Vercel AI Gateway credit balance and lifetime spend through its public API."
read_when:
  - Setting up or modifying the Vercel AI Gateway provider
---

# Vercel AI Gateway

Enable **Vercel AI Gateway** in Settings → Providers and enter an AI Gateway API key, or set
`AI_GATEWAY_API_KEY` for the CLI. The key is saved in CodexBar's local config file when entered in Settings.
Use `codexbar usage --provider vercel --source api` to fetch it.

The bundled JavaScript plugin reads `GET https://ai-gateway.vercel.sh/v1/credits` with bearer authentication.
It displays the key's **team-wide remaining USD balance** and **lifetime USD spend**, from the documented
`balance` and `total_used` decimal strings. Zero and negative balances are preserved. Missing or malformed
values fail the refresh; they do not become zero. The shared HTTP host bounds requests and retries transient failures.

This endpoint has no spending limit or reset date, so the provider shows amounts without a percentage bar,
reset countdown, or billing-period estimate. It does not read Vercel CLI credentials, switch teams, inspect
Keychain, or query the metered Custom Reporting API. Budgets, per-key quotas, and detailed usage reporting
remain outside this balance-only integration. Select the appropriate team's API key to change scope.

Sources: [REST credit API](https://vercel.com/docs/ai-gateway/sdks-and-apis/rest-api#check-credit-balance),
[usage semantics](https://vercel.com/docs/ai-gateway/observability-and-spend/usage), and
[reporting pricing](https://vercel.com/docs/ai-gateway/observability-and-spend/custom-reporting#pricing).
