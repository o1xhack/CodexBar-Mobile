# Ollama Cloud Sync Durability Testing

Status: `done`

## Focused regression tests

```text
swift test --filter 'empty Ollama API result preserves the last good quota snapshot|Ollama API fallback ghost does not delete the last good per-provider record'
```

Result: **2 tests passed in 2 suites**.

The passing assertions prove:

- the prior 38% / 12% Ollama windows remain in `UsageStore` after an empty API
  result;
- the latest source is recorded as `api` and the diagnostic is retained; and
- the second sync cycle performs no stale-record deletion after the provider
  becomes an empty API fallback ghost.

## Existing provider coverage

The Ollama parser and fetcher tests remain required because the browser path is
the authoritative quota source:

```text
swift test --filter 'OllamaUsageParserTests'
swift test --filter 'OllamaUsageFetcherRetryMappingTests'
```

## Build and residual evidence

The focused command rebuilt the affected Core, Mac, Shared, widget, CLI, and
test targets successfully before running the two regressions. The final full
Mac test gate passed:

```text
swift test --no-parallel
```

Result: **8,365 tests in 814 suites passed**.

The portable lint gate also passed:

```text
bash Scripts/lint.sh lint
```

It reported zero SwiftFormat/SwiftLint violations, complete locale coverage,
source-vs-catalog coverage, package checks, and CI policy checks.

The iOS simulator build was attempted with:

```text
xcodebuild -project CodexBarMobile/CodexBarMobile.xcodeproj \
  -scheme CodexBarMobile \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

It was blocked before project compilation because this host's Xcode 26.6
installation is missing
`/Library/Developer/PrivateFrameworks/CoreSimulator.framework`. This is an
environment gate, not a source-level failure. No physical iPhone, live
CloudKit, production deployment, or PR-CI result is claimed here.

The local unified-log query continues to show genuine CloudKit timeouts and
network failures. A later successful push was observed at 02:21:24 local time,
which supports eventual recovery but does not remove the need to surface failed
attempts.
