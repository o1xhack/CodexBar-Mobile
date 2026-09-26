---
summary: "DevPass plan credits and premium weekly usage through the LLM Gateway API."
read_when:
  - Configuring DevPass usage
  - Debugging DevPass API authentication or allowance meters
---

# DevPass

Enable DevPass in Settings → Providers and enter a regular LLM Gateway API key, or set
`DEVPASS_API_KEY`. The masked field saves the key in CodexBar's local config file;
configured keys override the environment. See [CLI configuration](cli-configuration.md).
Publishable keys and end-user sessions cannot read plan state.

Auto and API use the bundled TypeScript plugin on macOS and Linux:

```sh
codexbar usage --provider devpass --source api
```

The plugin reads `GET https://api.llmgateway.io/v1/key` with bearer authentication.
It shows organization-wide billing-cycle credits and premium weekly usage separately from
the API key's all-time spending and optional spending limit. Plan allowances come from the
response, so changes to subscription prices or allowances require no hardcoded updates.
Remaining plan credits are an allowance, not a prepaid wallet balance.

The premium window starts with the first premium request and lasts seven days. An inactive
window has zero usage and no reset date. No monthly reset date is exposed by this endpoint;
CodexBar does not infer one. Zero allowances omit percentage bars, and over-limit amounts
remain visible while bars clamp to 100%. Pay-as-you-go keys show only key-scoped all-time spend.

No dashboard cookies, login flow, local agent files, model history, or live inference calls are used.
Only the declared HTTPS API origin receives the key. Invalid monetary values fail the refresh
instead of appearing as zero usage. No real-account verification was performed for this integration.

Public contract: [DevPass Usage API](https://docs.llmgateway.io/developers/devpass-usage)
and [LLM Gateway OpenAPI](https://llmgateway.io/openapi.json), fetched September 22, 2026.
Synthetic fixture parity: `CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS=1 swift test --filter DevPassPluginTests`.
