# Grok grok.com-path product breakdown proof

These images are the production `UsageMenuCardView`, rendered offscreen at
310 pt with `hidePersonalInfo: true`. The data comes from a **live**
grok.com `GetGrokCreditsConfig` gRPC-web response (2026-09-26 21:58 UTC),
fetched and parsed by this branch's `GrokWebBillingFetcher`.

- **Credentials:** the run read the bearer from `~/.grok/auth.json`. No
  browser cookies and no Keychain were involved.
- **Parsed result:** `usedPercent 6.0` (wire-published) and
  `productUsage [GrokChat 4.0, GrokBuild 2.0]`. The same response is checked
  in, verbatim, as the fixture in `GrokWebBillingProductUsageTests`.
- **after.png:** that snapshot rendered as-is: one weekly bar plus
  `Grok Chat 4%` / `Grok Build 2%`.
- **before.png:** the same snapshot with `details` cleared. That is what main
  shows on this path, because its gRPC parser never pairs the `[1, 7]` ids with
  their percentages.

The fetch-and-render harness was a temporary test and was not committed. It
calls `GrokCredentialsStore.load`, then `GrokWebBillingFetcher.fetch`, then
`GrokUsageSnapshot.toUsageSnapshot`, and renders through `NSHostingView` +
`cacheDisplay`.
