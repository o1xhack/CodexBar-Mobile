# 032 — iOS Sync Device Management

Status: `done`
Date: 2026-06-20
Issue: https://github.com/o1xhack/CodexBar-Mobile/issues/29
Target iOS version: 1.14.0
Mac release: not required

## Context

This feature comes from Telegram user feedback: after a Mac reinstall, iOS can
show two Mac devices in Settings -> About & Sync because the Mac's stable
CloudKit device identity changes. The visible symptom is similar to a retired
Mac that no longer syncs, but the product semantics are different:

- Reinstall: one physical Mac, two historical device IDs.
- Retirement/replacement: two real Macs, one of which should stop producing
  stale-sync warnings.

The user explicitly allowed this issue to proceed on the current v0.36.1
mobile-dev baseline. Open upstream-sync issue #30 for v0.37.0 is not a blocker
for this work. This feature is iOS 1.14.0 scope; Mac does not need a new
release because the Mac producer payload is unchanged.

## Goals

- Let users merge duplicate Mac device identities after reinstall.
- Let users archive retired Mac devices without deleting historical data.
- Let users restore archived devices and undo mistaken merges.
- Keep the CloudKit data model non-destructive and auditable.
- Prevent merged aliases and archived devices from triggering active stale-sync
  warnings.
- Preserve correct local-cost semantics: duplicate identities for the same
  physical Mac must not be counted like two real Macs.

## Non-Goals

- No automatic merge. The app may suggest likely duplicates later, but the MVP
  requires explicit user confirmation.
- No CloudKit record deletion or rewrite of existing provider/device records.
- No Mac release, no live release, no TestFlight upload, and no CloudKit
  Production schema deploy without explicit user confirmation.

## Key Existing Code

- `Shared/Models/ProviderAccountLinkage.swift` provides the precedent for an
  additive, user-confirmed CloudKit linkage record.
- `Shared/iCloud/CloudSyncManager.swift` already saves and fetches linkage
  records from `DeviceProvidersZone`.
- `CodexBarMobile/CodexBarMobile/iCloud/CloudSyncReader.swift` merges provider
  snapshots across devices and sums local-cost providers only when devices are
  distinct machines.
- `CodexBarMobile/CodexBarMobile/Models/SyncedUsageData.swift` caches linkage
  records, retries pending saves, and republishes local state immediately.
- `CodexBarMobile/CodexBarMobile/ContentView.swift` renders the current
  Settings -> About & Sync device list directly from raw device snapshots.

## Decision

Add a shared `DeviceLifecycleEvent` model and store lifecycle records in
`DeviceProvidersZone` using a new `DeviceLifecycleEvent` CKRecord type.

The lifecycle reducer derives the iOS-visible physical devices from raw
CloudKit snapshots:

- `alias` groups old and new device IDs as one physical Mac.
- `unalias` cancels the matching alias edge.
- `archive` removes a real retired device from active stale-sync warnings.
- `unarchive` restores an archived device to active.

The app keeps raw snapshots intact for diagnostics and history, but Settings
uses the lifecycle-derived device list.

## CloudKit Audit

This introduces a new CKRecord type:

- `DeviceLifecycleEvent`
- record name prefix: `device-lifecycle-`
- zone: `DeviceProvidersZone`
- fields: `kind`, `primaryDeviceID`, `relatedDeviceIDs`, `confirmedAt`,
  `confirmedFromDeviceID`, optional `note`

Per `docs/cloudkit-deploy-audit.md`, a new record type requires Production
schema deploy before TestFlight or release. This PR documents that requirement
but does not perform the deploy without explicit user confirmation.

## Testing Scope

This changes Mac -> CloudKit -> iOS sync display semantics and therefore
triggers `docs/ios-sync-compatibility-testing.md`.

Required automated coverage:

- `DeviceLifecycleEvent` Codable round trip.
- CKRecord encode/decode round trip without reserved `recordID` field.
- alias / unalias replay.
- archive / unarchive replay.
- duplicate Mac identities collapse to one active device.
- archived Mac is excluded from active devices and stale warnings.
- same-name real Macs do not auto-merge.
- local-cost providers are not double-counted within an alias group.

Manual/compatibility evidence is recorded in `03-testing.md`.
