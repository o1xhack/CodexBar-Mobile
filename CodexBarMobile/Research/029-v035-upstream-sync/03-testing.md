# v0.35.0 Upstream Sync Testing

Status: `in-progress`
Date: 2026-06-14
Branch: `upstream-sync/v0.35.0-mobile.1.12.0`

## Required Gates

- Mac build and relevant unit tests.
- Mac menu/provider regression checks for upstream `v0.32.5..v0.35.0`.
- Parser/pricing hash verification if CostUsage parser or pricing changed.
- iOS build and relevant tests.
- 4-language localization check for new iOS strings.
- CloudKit Production schema audit.
- `docs/ios-sync-compatibility-testing.md` 2 Mac x 2 iPhone compatibility gate.
- Final diff review with blocking issues fixed.

## CloudKit Production Schema Audit

Status: pending merge.

Required commands after implementation:

```text
LAST_TAG=$(gh release list --repo o1xhack/CodexBar-Mobile --limit 5 --json tagName,isDraft | python3 -c 'import json,sys;[print(r["tagName"]) for r in json.load(sys.stdin) if not r["isDraft"]][0]')
git diff $LAST_TAG..HEAD 2>&1 | grep -E "^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)"
git diff $LAST_TAG..HEAD -- Shared/iCloud/CloudConstants.swift
git diff $LAST_TAG..HEAD -- Shared/Models/UsageSnapshot.swift | grep -E "^\+.*public let|^-.*public let"
```

## 2 Mac x 2 iPhone Old/New Compatibility Matrix

Definitions for this release:

- Old Mac: shipped baseline before this branch, `0.32.4.1` / `1.11.1` appcast
  line. The prior `0.32.5.1` release exists but was not merged to `mobile-dev`;
  compatibility notes must explicitly account for it if used as a QA old/new
  stand-in.
- New Mac: target branch build `0.35.0.1`.
- Old iPhone: shipped `1.11.1`.
- New iPhone: target branch build `1.12.0 (153)`.

The matrix is required because this release changes provider display data and
is expected to add or preserve optional Shared payload fields.

| Case | Mac A | Mac B | iPhone A | iPhone B | Expected | Result | Evidence |
|---:|---|---|---|---|---|---|---|
| 01 | Old | Old | Old | Old | Existing shipped behavior unchanged | Pending | Pending |
| 02 | Old | Old | Old | New | New iPhone decodes old payloads | Pending | Pending |
| 03 | Old | Old | New | Old | Same as case 02 with phone order swapped | Pending | Pending |
| 04 | Old | Old | New | New | Both new phones decode old Mac payloads | Pending | Pending |
| 05 | Old | New | Old | Old | Old phones ignore new optional fields from one Mac | Pending | Pending |
| 06 | Old | New | Old | New | New phone renders new metadata; old phone remains stable | Pending | Pending |
| 07 | Old | New | New | Old | Same as case 06 with phone order swapped | Pending | Pending |
| 08 | Old | New | New | New | Both phones merge old/new Macs without field loss | Pending | Pending |
| 09 | New | Old | Old | Old | Same as case 05 with Mac order swapped | Pending | Pending |
| 10 | New | Old | Old | New | Same as case 06 with Mac order swapped | Pending | Pending |
| 11 | New | Old | New | Old | Same as case 07 with Mac order swapped | Pending | Pending |
| 12 | New | Old | New | New | Same as case 08 with Mac order swapped | Pending | Pending |
| 13 | New | New | Old | Old | Old phones ignore new optional fields from both Macs | Pending | Pending |
| 14 | New | New | Old | New | New phone renders all new data; old phone stable | Pending | Pending |
| 15 | New | New | New | Old | Same as case 14 with phone order swapped | Pending | Pending |
| 16 | New | New | New | New | Full new behavior on all devices | Pending | Pending |

## Test Evidence

Pending implementation.

## Review

Pending implementation.

