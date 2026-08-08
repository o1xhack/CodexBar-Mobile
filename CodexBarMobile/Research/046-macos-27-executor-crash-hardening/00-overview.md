# macOS 27 Swift Executor Crash Hardening

Status: `in-progress`
Date: 2026-08-09
Branch: `fix/macos-27-mainactor-callback-crashes`

## Incident

The installed Mac app was the iPhone-companion fork, not upstream CodexBar:

- bundle identifier: `com.o1xhack.codexbar`
- installed version: `0.45.2.2` (`CFBundleVersion 109.2.1.19.0`)
- fork: `o1xhack/CodexBar-Mobile`
- fork base branch: `mobile-dev`
- host: arm64 Mac on macOS `27.0 (26A5388g)`

Seven `CodexBar` DiagnosticReports were available from August 6–9, 2026. Six
were `EXC_BAD_ACCESS` / `SIGSEGV` failures with the same Swift executor-check
family. One was an unrelated `EXC_CRASH` / `SIGABRT` during
`RegisterApplication` and is treated as an outlier rather than part of this
fix.

The six relevant reports faulted on the main thread before the Swift method
body, in this shape:

```text
swift_getObjectType
  -> swift_task_isMainExecutorImpl
  -> swift_task_isCurrentExecutorWithFlagsImpl
  -> compiler-generated _checkExpectedExecutor
  -> Objective-C AppKit callback or NSCustomImageRep drawing closure
```

The application frames were split across three fork-owned boundaries:

| Reports | Application boundary |
|---:|---|
| 3 | `MenuBarLayoutRenderer.attachmentImage` drawing handler invoked by `NSCustomImageRep` |
| 2 | `SettingsWindowAppearanceView.windowDidUpdate(_:)` |
| 1 | `StatusItemController.handleScreenParametersDidChange(_:)` |

No useful CodexBar-specific rows were present in the unified log query, so the
DiagnosticReports are the primary local evidence. The background
`ProviderStorageFootprint` scanner appeared in one report but was not the
faulting thread.

## Diagnosis

This is not evidence of a voluntary quit, provider refresh failure, or the
iPhone sync path killing the Mac process. It is a repeatable crash family at
Swift 6.3 / AppKit Objective-C callback boundaries on the macOS 27 beta host.

The strongest diagnosis is an OS/runtime-sensitive interaction with
`@MainActor` entry points exposed directly to AppKit's Objective-C notification
and drawing machinery. The synthesized executor check can fault before the
application's Swift code runs. The deferred `NSImage` drawing handler adds the
same boundary later, when AppKit asks the attachment to draw.

Upstream issue [steipete/CodexBar#2250](https://github.com/steipete/CodexBar/issues/2250)
independently reports the same macOS build and executor-check family, including
fresh crashes in current upstream releases at `menuNeedsUpdate` and
`handleScreenParametersDidChange`. That corroborates the runtime boundary
diagnosis, but it does not prove that every AppKit callback is safe to change.

## Fix scope

This branch hardens the three application boundaries represented in the local
reports:

1. Materialize tinted template images synchronously into a bitmap before
   attaching them to the status-item attributed title. The image no longer
   contains a deferred `NSCustomImageRep` drawing handler.
2. Mark `windowDidUpdate(_:)` as an Objective-C-facing `nonisolated` shim and
   explicitly hop to `MainActor` before touching the view.
3. Apply the same nonisolated-selector / explicit-main-actor-hop pattern to
   `handleScreenParametersDidChange(_:)`.

The synchronous `NSMenuDelegate` callbacks are deliberately not changed in
this branch. Upstream issue #2250 shows a related `menuNeedsUpdate` crash, but
that callback has a synchronous AppKit contract and there is no controlled
local reproduction for safely redesigning menu population. It remains an
explicit residual risk for maintainer validation.

The iPhone app, CloudKit schema, provider credentials, signing, installed app,
and release artifacts are outside this change.
