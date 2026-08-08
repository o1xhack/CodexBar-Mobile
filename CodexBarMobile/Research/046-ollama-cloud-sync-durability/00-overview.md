# Ollama Cloud Sync Durability

Status: `done`
Date: 2026-08-09
Branch: `fix/ollama-cloud-sync-durability`

## Incident

The fork's Ollama Cloud card intermittently loses its quota windows, and the
iPhone companion can lose the corresponding provider record. The reported
pattern is distinct from Codex and Claude: Ollama's browser session expires or
fails to parse, then the API-key fallback succeeds but has no Cloud quota
statistics.

## Evidence

The investigation used the fork's Mac app, local persistence, unified logs,
and source-level tests. No cookie, API-key, account email, or payload contents
were read.

### Local state

- The app's file logger is disabled, so there is no useful
  `~/Library/Logs/CodexBar/CodexBar.log` to correlate.
- The fork's shared app-group container has no persisted sync cache on this
  Mac. Sync state is therefore in CloudKit/KVS and transient unified logs,
  not in a durable local sync database.
- Local history files exist for other providers, but no Ollama history file was
  present. This is not treated as proof of loss because historical tracking can
  be disabled; the reproducible source/test path is stronger evidence.

### Unified log

The narrow query below was used, avoiding the expensive broad history scan:

```text
/usr/bin/log show --style compact --info --debug --last 24h \
  --predicate 'subsystem == "com.o1xhack.codexbar" AND \
  (category == "cloudkit-sync" OR category == "com.steipete.codexbar.icloud-sync")'
```

The same running fork process (`CodexBar`, PID 69696) recorded repeated
write-side failures on 2026-08-09:

| Time (local) | Phase | Evidence |
|---|---|---|
| 01:18:51 | provider upload | Per-provider batch timed out |
| 01:21:12 | legacy record save | Legacy record save timed out |
| 01:22:45 | legacy conflict retry | Conflict retry timed out |
| 01:23:30 | provider zone check | Provider zone check timed out |
| 02:08:40 | legacy zone check | Legacy zone check timed out |
| 02:09:26 | provider upload | Per-provider batch timed out |
| 02:18:56 | legacy record save | Legacy record save timed out |
| 02:19:34 | legacy upload | Coordinator reported the timeout in cleanup |
| 02:21:24 | legacy upload | A later snapshot push succeeded |

The earlier process (PID 1028) also recorded repeated `Network unavailable`
and `client oplock error updating record` failures for the legacy
`DeviceSnapshotsZone` record. These are real CloudKit availability/conflict
signals, not an Ollama parser error. The fix makes legacy writes conflict
tolerant, but a network timeout remains a failed sync attempt and is still
reported as such.

No Ollama-specific unified-log event was emitted by the current provider path;
the provider failure is visible by tracing the fallback and snapshot
publication code instead.

## Root cause

1. In automatic mode, `OllamaStatusFetchStrategy` tries browser cookies first
   and `OllamaAPIFetchStrategy` is the fallback when an API key is available.
2. The API fallback calls `/api/tags`. A successful response verifies the key
   and returns model metadata, but it contains no Cloud quota windows. Its
   `UsageSnapshot` therefore has no rate windows, cost, or account email.
3. `UsageStore` previously treated that empty success as authoritative and
   replaced the last web quota snapshot.
4. `SyncCoordinator` then classified the provider as a ghost because the
   empty snapshot had no usable signal. It skipped a replacement envelope and
   treated the previous per-provider record as stale, deleting it during
   cleanup.
5. iOS prefers the per-provider zone when present, so losing that record makes
   the iPhone card lose the last known Ollama statistics even if an older
   legacy snapshot still exists.

The generic history-reconcile hypothesis was also tested. Existing session /
weekly history regressions prove that an incomplete page does not erase both
established series, so that path is not the cause of this incident.

## Required outcome

- Empty Ollama API verification must never erase a usable local quota sample.
- A transient empty provider state must not trigger per-provider record
  deletion while the provider remains enabled.
- Legacy snapshot writes must not fail solely because a concurrent server
  change tag is stale.
- No CloudKit record types, fields, zones, payload versions, or entitlements
  change.

Source and Mac verification are complete. Physical iPhone behavior, live
CloudKit availability, and PR CI remain separate gates; no production or
device-release claim is made here.
