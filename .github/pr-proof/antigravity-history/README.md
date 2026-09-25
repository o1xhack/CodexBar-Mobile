# Antigravity quota history proof

The production SwiftUI chart is rendered offscreen from five synthetic balances
(18%, 37%, 64%, 82%, 20%), recorded through `UsageStore` one hour apart.
`before.png` uses production code at `b99a91694d78` plus the render fixture;
`after.png` uses this change. Both captures were inspected for unrelated content.
No app was launched, no visible window was created, and no real account,
credential, provider request, or production history was used. This proves chart
rendering, not the integrated menu workflow.

Reproduce the current render from the repository root:

```sh
source Scripts/test_environment.sh
CODEXBAR_ANTIGRAVITY_PROOF_PATH=/tmp/antigravity-history.png \
  swift test --jobs 2 --filter AntigravityHistoryNativeProofTests
```
