# 032 Design — Device Lifecycle Records

Status: `done`

## Data Model

`DeviceLifecycleEvent` is an additive CloudKit record:

```swift
DeviceLifecycleEvent
- recordID: String
- kind: alias | unalias | archive | unarchive
- primaryDeviceID: String
- relatedDeviceIDs: [String]
- confirmedAt: Date
- confirmedFromDeviceID: String
- note: String?
```

The model intentionally stores events rather than mutating or deleting existing
device/provider records. This keeps history inspectable and makes undo
possible.

## Reducer Semantics

### Alias

`alias(primary=A, related=[B])` means A and B are the same physical Mac. The
resolver unions those device IDs and emits one active device row.

Within an alias group, provider data is merged with same-physical-device
semantics:

- local-cost providers do not sum duplicated local history;
- newest/richer provider data wins;
- account linkages can still bridge provider identities if needed.

After aliases are collapsed, the existing cross-device merge still applies
across distinct physical Macs. At that layer, local-cost providers keep the
existing sum-across-devices behavior.

### Unalias

`unalias` carries the same normalized device ID set as the original `alias`.
The reducer suppresses the matching alias edge before union-find runs. This is
order-independent and mirrors `ProviderAccountLinkage.unmerge`.

### Archive

`archive(primary=A)` means A is a real retired Mac. It remains available as
history but is excluded from active device count and stale-sync warnings.

Archive is not the same as alias. A retired Mac remains a distinct device.

### Unarchive

`unarchive(primary=A)` restores A to the active device list. The latest
archive/unarchive action for the physical device group wins.

## UI

Settings -> About & Sync gains device management actions:

- Merge with Another Mac...
- Archive This Device
- Restore Device
- Unmerge

Rows show active, merged, and archived state with brief explanatory text. The
confirmation copy must state that history is preserved and operations are
reversible.

## Versioning

This is an iOS 1.14.0 user-facing feature. It does not require a Mac release.
Mac build validation is required only because Shared code is touched.
