# v0.39.0 Upstream Sync Testing

Status: `in-progress`
Date: 2026-07-04
Branch: `upstream-sync/v0.39.0-mobile.1.17.0`

## Required Gates

- Mac build and lint.
- Full or sharded Mac test suite.
- Focused provider tests for new providers and changed providers:
  `sakana`, `qoder`, `crossmodel`, `clawrouter`, Codex, Claude, Kimi, Mistral,
  Doubao, OpenCode, OpenAI, Alibaba, and Keychain no-prompt safety.
- Parser version/hash gate for changed `CostUsageScanner*` and cost cache code.
- `swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'`.
- iOS project generation, build, and relevant tests.
- iOS four-language localization audit.
- CloudKit Production schema audit.
- 2 Mac x 2 iPhone old/new compatibility matrix because this release changes
  provider display data and likely Shared payload/rendering paths.
- Final diff review with all blocking issues fixed.

## CloudKit Production Schema Audit

Status: pending implementation.

Latest published fork release from `gh release list`:

```text
v0.37.2.1-mobile.1.15.0
publishedAt: 2026-06-24T20:57:30Z
```

Audit commands to run after implementation:

```text
git diff v0.37.2.1-mobile.1.15.0..HEAD -- | grep -E "^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)"
git diff v0.37.2.1-mobile.1.15.0..HEAD -- Shared/iCloud/CloudConstants.swift
git diff v0.37.2.1-mobile.1.15.0..HEAD -- Shared/Models/UsageSnapshot.swift | grep -E "^\+.*public let|^-.*public let"
```

Expected default:

- new providers and optional payload-internal fields should not require a
  CloudKit Production schema deploy;
- any new record type, record field outside compressed payload, zone,
  subscription, index, `providerPayloadVersion`, or `encodingVersion` change is
  a blocker until the user explicitly confirms deploy.

Verdict: pending.

## 2 Mac x 2 iPhone Old/New Compatibility Matrix

Definitions for this release:

- Old Mac: latest published fork Mac, `0.37.2.1` / Sparkle `92.1.1.15.0`.
- New Mac: target branch build `0.39.0.1` / Sparkle `97.1.1.17.0`.
- Old iPhone: current `1.16.0` shipped/TestFlight line before this branch.
- New iPhone: target branch build `1.17.0`.

This matrix applies because the release changes provider display data, new
providers, Shared payload candidate fields, cache/parser behavior, and
cross-version rendering.

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 01 | old | old | old | old | pending | | Baseline unchanged; record shipped behavior evidence or substitute with prior release proof. |
| 02 | old | old | old | new | pending | | New iOS must decode old Mac payloads and hide new sections. |
| 03 | old | old | new | old | pending | | Same as case 02 with phone roles swapped. |
| 04 | old | old | new | new | pending | | Both new iPhones should converge to old visible state. |
| 05 | old | new | old | old | pending | | Old iOS must tolerate new Mac optional payloads/provider IDs. |
| 06 | old | new | old | new | pending | | Mixed old/new read path with one new writer. |
| 07 | old | new | new | old | pending | | Same as case 06 with phone roles swapped. |
| 08 | old | new | new | new | pending | | Both new iPhones converge with mixed Mac writers. |
| 09 | new | old | old | old | pending | | Same as case 05 with Mac writer order swapped. |
| 10 | new | old | old | new | pending | | Same as case 06 with Mac writer order swapped. |
| 11 | new | old | new | old | pending | | Same as case 07 with Mac writer order swapped. |
| 12 | new | old | new | new | pending | | Same as case 08 with Mac writer order swapped. |
| 13 | new | new | old | old | pending | | Highest old-iOS risk if new Mac writes new provider fields/IDs. |
| 14 | new | new | old | new | pending | | Mixed phone rendering with two new writers. |
| 15 | new | new | new | old | pending | | Same as case 14 with phone roles swapped. |
| 16 | new | new | new | new | pending | | Full new-stack path. |

Substitution policy:

- Use `substituted` only when real 2 Mac x 2 iPhone hardware is unavailable.
- Each substituted row must name the replacement evidence: old/new payload
  decode tests, mock CloudKit records, simulator builds/tests, code audit,
  focused sync/account tests, or manual QA notes.
- Residual risk must be explicit for silent push delivery, two-phone
  convergence, old iOS unknown-field behavior, and real CloudKit Production
  latency.

## Test Evidence

Pending.

## Draft Release Evidence

Pending.

Required evidence:

- artifact names;
- notarization/signing result;
- GitHub draft release URL;
- Sparkle version and short version;
- appcast generation status;
- remaining live-release steps not executed.

## Review

Pending.
