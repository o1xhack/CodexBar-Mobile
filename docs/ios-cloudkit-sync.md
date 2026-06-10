---
summary: "Current iCloud sync architecture: CloudKit multi-device sync with silent push notifications."
read_when:
  - Understanding how Mac data reaches the iOS app
  - Debugging sync issues between Mac and iOS
  - Adding new data fields to the sync payload
---

# iOS CloudKit Sync Architecture

> Replaces the original KVS-based sync (docs/ios-icloud-sync.md). CloudKit upgrade shipped in Mobile 1.0.0 (Build 23).

## Architecture Overview

```
Mac A (deviceID: uuid-aaa)          Mac B (deviceID: uuid-bbb)
        │                                   │
        ▼                                   ▼
  SyncCoordinator                     SyncCoordinator
        │                                   │
        ▼                                   ▼
  CloudSyncManager.pushSnapshot()     CloudSyncManager.pushSnapshot()
        │                                   │
        ▼                                   ▼
┌──────────────────────────────────────────────────┐
│            CloudKit Private Database              │
│                                                   │
│  DeviceSnapshot/uuid-aaa    DeviceSnapshot/uuid-bbb│
│   ├─ payload (JSON)          ├─ payload (JSON)     │
│   ├─ deviceName              ├─ deviceName         │
│   ├─ syncTimestamp           ├─ syncTimestamp       │
│   └─ appVersion              └─ appVersion         │
└──────────────┬───────────────────────────────────┘
               │ CKQuerySubscription
               │ (shouldSendContentAvailable = true)
               ▼
         ┌──────────┐
         │  iPhone   │
         │           │
         │  AppDelegate.didReceiveRemoteNotification
         │     ↓
         │  CloudSyncReader.fetchAllDeviceSnapshots()
         │     ↓
         │  mergeSnapshots() ← combines all devices
         │     ↓
         │  SessionQuotaMonitor ← detects depleted/restored
         │     ↓
         │  Local notification to user
         └──────────┘
```

## Key Components

### Mac Side (Writer)

| Component | File | Role |
|-----------|------|------|
| `SyncCoordinator` | `Sources/CodexBar/Sync/SyncCoordinator.swift` | Observes UsageStore, builds SyncedUsageSnapshot, pushes to CloudKit |
| `CloudSyncManager` | `Shared/iCloud/CloudSyncManager.swift` | CKRecord CRUD, CKSubscription setup |
| `CloudConstants` | `Shared/iCloud/CloudConstants.swift` | Container ID, record type, keys |

### iOS Side (Reader)

| Component | File | Role |
|-----------|------|------|
| `AppDelegate` | `CodexBarMobile/AppDelegate.swift` | Receives silent push, triggers fetch + quota check |
| `CloudSyncReader` | `CodexBarMobile/iCloud/CloudSyncReader.swift` | Fetches all device snapshots, merges multi-device data |
| `SyncedUsageData` | `CodexBarMobile/Models/SyncedUsageData.swift` | Observable view model, CloudKit + KVS fallback |
| `SessionQuotaMonitor` | `CodexBarMobile/Notifications/SessionQuotaMonitor.swift` | Detects quota transitions, posts local notifications |

### Shared (Both Platforms)

| Component | File | Role |
|-----------|------|------|
| `SyncedUsageSnapshot` | `Shared/Models/UsageSnapshot.swift` | Root payload: providers, timestamp, device info |
| `ProviderUsageSnapshot` | `Shared/Models/UsageSnapshot.swift` | Per-provider: rate windows, cost, budget, utilization history |
| `CloudSyncManager` | `Shared/iCloud/CloudSyncManager.swift` | Push/fetch/subscribe operations |

## CloudKit Record Schema

**Record Type:** `DeviceSnapshot`
**Container:** `iCloud.com.o1xhack.codexbar`
**Environment:** Production (both Mac and iOS)

| Field | Type | Description |
|-------|------|-------------|
| `recordName` | String | = deviceID (stable UUID per Mac) |
| `deviceName` | String | `Host.current().localizedName` |
| `deviceID` | String | Stable UUID persisted in UserDefaults |
| `appVersion` | String | Mac CFBundleShortVersionString |
| `syncTimestamp` | Date | Push time |
| `payload` | Data | JSON-encoded `SyncedUsageSnapshot` |

## Multi-Device Merge Strategy

When iOS fetches snapshots from multiple Macs:

1. Group providers by `providerID + accountEmail`
2. Same provider+account across devices:
   - Rate limits, identity, status: use most recent `lastUpdated`
   - Local-cost providers (Claude, Codex, VertexAI): **SUM** daily costs
   - Account-level providers: use most recent
   - Utilization history: use most recent device's data
3. Different providers: combine all

## Silent Push Notifications

- `CKQuerySubscription` on `DeviceSnapshot` with `shouldSendContentAvailable = true`
- iOS `AppDelegate.didReceiveRemoteNotification` receives silent push
- Fetches latest data, runs `SessionQuotaMonitor.detectTransitions()`
- Posts local notification for depleted (<=0.0001%) / restored transitions
- Works in background; system controls wake frequency

## Backward Compatibility

- Mac still dual-writes to KVS (`com.codexbar.usage.snapshot`) for old iOS versions
- iOS reads CloudKit first; falls back to KVS if no CloudKit data
- New fields (utilizationHistory) use `decodeIfPresent` — old payloads decode safely

## Cross-version Multi-device Test Matrix

The canonical cross-version multi-device test gate lives in
[`docs/ios-sync-compatibility-testing.md`](ios-sync-compatibility-testing.md).
Use that document for the reusable 2 Mac × 2 iPhone old/new matrix and record
per-release evidence in that release's `CodexBarMobile/Research/NNN-*/03-testing.md`.

## Entitlements Required

**Mac (`Scripts/package_app.sh`):**
- `com.apple.developer.icloud-services`: CloudKit
- `com.apple.developer.icloud-container-identifiers`: iCloud.com.o1xhack.codexbar
- `com.apple.developer.icloud-container-environment`: Production

**iOS (`CodexBarMobile.entitlements`):**
- Same CloudKit entitlements
- `aps-environment`: development (auto-replaced to production for TestFlight/App Store)
- `UIBackgroundModes`: remote-notification
