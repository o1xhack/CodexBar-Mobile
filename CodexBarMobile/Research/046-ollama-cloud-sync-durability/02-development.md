# Ollama Cloud Sync Durability Development

Status: `done`

## Red reproduction

Two public seams were made red before the fix:

1. `OllamaSyncCoordinatorDurabilityTests.Ollama API fallback ghost does not delete the last
   good per-provider record` uploaded a real Ollama-shaped snapshot, replaced
   it with the empty API fallback shape, and observed one stale-record delete.
2. `OllamaUsageStoreDurabilityTests.empty Ollama API result preserves the last
   good quota snapshot` seeded a good local snapshot, injected a successful
   empty `.apiToken` result, and observed both quota windows become `nil`.

The first red run recorded the expected cleanup deletion. The second red run
recorded the expected `nil` primary and secondary windows.

## Implementation

The fix is limited to the fork's existing Mac-to-iPhone bridge:

- `Sources/CodexBarCore/Providers/Ollama/OllamaUsageFetcher.swift`
  centralizes the API-only quota diagnostic.
- `Sources/CodexBarCore/Providers/Ollama/OllamaProviderDescriptor.swift`
  attaches that diagnostic to the empty API result.
- `Sources/CodexBar/UsageStore+Refresh.swift` retains prior Ollama quota data
  when the API probe has no quota signal.
- `Sources/CodexBar/Sync/SyncCoordinator.swift` prevents transient ghost
  cleanup from deleting the last known provider record.
- `Shared/iCloud/CloudSyncManager.swift` changes the legacy snapshot save to
  the conflict-tolerant policy already used by per-provider writes.
- Focused regression tests cover both local replacement and iPhone-record
  deletion behavior.

The implementation does not inspect or persist any credential value.
