# Sync v0.69–v0.70 and support upstream quota data on iOS

Local PR body preparation; no PR has been created. Base: mobile-dev.

Sync the two upstream releases as one train while retaining fork CloudKit, release, README and CI rules. iOS now displays actual captured Codex/Claude quota cycles, authoritative Kimi monthly blocking and observed model names. Persist producer publication times and optional metadata across disk reopen, retain old-reader compatibility, and update iOS to 2.4.0 (227) with one four-language release-notes block.

Validation: Mac safe regression runner passed 1520 selections in 137 groups with no retries/timeouts; unsigned universal Release/dSYM preflight passed. Original Swift Testing objects ran on iOS26.5 Simulator: 313 tests in 15 suites passed. Production quota view generated 32 four-language/light-dark/narrow-normal images including a 24h fixture. Frozen published-old/current-new compatibility covered all16 combinations:64 wire reads,32 merges and32 independent iOS disk caches/96 processes passed. CloudKit schema audit is NO_DEPLOY because new optional fields remain inside the existing opaque JSON payload.

Outstanding before release: Widget render matrix and real SpringBoard edit/configuration proof; real App navigation/accessibility; actual Production CloudKit/APNs/multi-device validation. Matrix results are substituted evidence, not physical four-device results. Standard XCTest and iOS27 revalidation remain live without terminal success. Root lint passed; targeted changed-line iOS lint found no new violations, not a claim that the entire existing iOS tree is lint-clean.

GitHub exact-head CR, thread resolution, review gate, PR Fast Checks, authorized merge and applicable Final CI must precede Mac draft. Local review does not replace remote CR. No signed/notarized draft, public release or TestFlight upload exists for this train yet. Update this body with actual remaining-gate results before handoff.

Related #166. Keep the issue open through draft; close only after the public release under the repository workflow.
