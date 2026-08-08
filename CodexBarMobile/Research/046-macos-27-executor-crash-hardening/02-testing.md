# macOS 27 Swift Executor Crash Hardening Testing

Status: `in-progress`

## Red-to-green regression

The new test was added before the implementation:

```text
swift test --filter 'CodexBarTests.MenuBarLayoutRendererTests/`template icon is materialized before AppKit draws the attachment`'
```

Before the fix it failed because the attachment contained an
`NSCustomImageRep` and no `NSBitmapImageRep`. After the fix the same test
passed, proving the deferred drawing representation was removed.

## Local verification

| Check | Result |
|---|---|
| `MenuBarLayoutRendererTests` | 13 passed, 0 failed |
| `SettingsWindowAppearanceTests` | 9 passed, 0 failed |
| `MenuBarVisibilityWatcherTests` | 36 passed, 0 failed |
| `swift build --product CodexBar` | passed |
| `git diff --check` | passed |

The focused tests cover the exact image boundary, preserve light/dark
appearance behavior, and exercise the existing window/display recovery suites
after the callback changes compile. The code was not installed over the
user's current app and no signing or release operation was performed.

## Historical crash detector

The deterministic local log query remains intentionally `RED` against the
seven historical reports:

```text
CodexBar reports=7 bad_access=6 executor_family=6 relevant_callbacks_or_drawing=6
RED: repeated executor-check crash family present
```

That is expected: changing source cannot rewrite old DiagnosticReports. There
was no safe, controlled live reproduction of the macOS 27 crash in this
session, so the fix is evidence-backed but not yet validated by a fresh
post-fix crash-free soak on the affected machine.

## Release gate

The draft PR should be tested by a maintainer on macOS `27.0 (26A5388g)` with
the fork's current Mac build. In particular, validate:

- repeated menu-bar appearance changes;
- display attach/detach and screen-parameter changes;
- status-item layout rendering in Aqua and Dark Aqua;
- opening and refreshing the status-item menu, because upstream #2250 leaves
  the synchronous `menuNeedsUpdate` family as a residual risk.
