# Ollama Cloud Sync Durability Design

Status: `done`

## Local snapshot authority

`OllamaAPIFetchStrategy` now carries a stable diagnostic explaining that the
API key is verified but Cloud quotas require browser cookies. When a successful
Ollama API result contains no rate windows, cost, or extra windows and a prior
snapshot has usable rate windows, `UsageStore`:

- keeps the prior snapshot and its reset times;
- records the latest source as `api`;
- clears the fetch error and records the diagnostic;
- records the fetch attempt and a successful failure-gate transition; and
- completes the normal refresh publication without recording a duplicate
  utilization sample.

This preserves visible data while making the degraded source explicit. The
guard is scoped to Ollama API results, so a genuinely empty result from another
provider is not silently reinterpreted.

## Per-provider cleanup authority

`SyncCoordinator.computeCurrentRecordNames` now retains the last pushed record
names for an enabled provider whose current snapshot is a ghost. A disabled
provider is absent from the current provider list and still follows the
existing one-cycle deletion contract. When a real Ollama snapshot returns, its
normal composite record is emitted and the retained record set converges.

This is deliberately conservative for account identity: a temporary empty
state retains all prior composites for that provider until a usable snapshot
re-establishes the account set. It prevents data loss at the cost of retaining
an old record for one transient cycle.

## CloudKit conflict handling

The legacy `DeviceSnapshotsZone` record is a Mac-authored projection that iOS
reads. Its save operation now uses `.changedKeys`, matching the already-working
per-provider write path. This avoids rejecting a fresh snapshot solely because
the server change tag advanced between the fetch and save. The existing
timeout and error reporting remains intact; this change does not pretend that
an unavailable network is a successful sync.

No schema or wire-format change is needed. Old iOS readers continue to receive
the same legacy record and the same per-provider record family.

## Deliberately out of scope

- Retrying arbitrary CloudKit network timeouts until they appear successful.
- Changing iOS's ghost filter to accept empty records as quota data.
- Persisting API keys, cookies, or raw account identifiers in logs.
- Replacing the existing CloudKit/KVS architecture with an app-group cache.
