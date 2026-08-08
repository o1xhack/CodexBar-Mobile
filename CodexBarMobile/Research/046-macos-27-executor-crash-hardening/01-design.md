# macOS 27 Swift Executor Crash Hardening Design

Status: `in-progress`

## Hypothesis review

| Rank | Hypothesis | Prediction | Evidence / result |
|---:|---|---|---|
| 1 | A Swift executor check synthesized at an AppKit Objective-C callback boundary is faulting before the Swift body. | Main-thread `EXC_BAD_ACCESS` reports resolve through `swift_task_isMainExecutorImpl` and compiler-generated `_checkExpectedExecutor`, with `SettingsWindowAppearanceView` or `StatusItemController` above it. | Confirmed in two callback families and six relevant local reports. |
| 2 | The custom template-image drawing handler is a deferred Objective-C drawing callback with the same actor-isolation hazard. | `NSCustomImageRep draw` should appear below `MenuBarLayoutRenderer.attachmentImage` in the relevant reports. | Confirmed in three local reports; a regression test was red before the image was materialized. |
| 3 | The display-change notification selector is another direct `@MainActor` Objective-C entry point. | The screen-parameter callback should appear above the executor-check frames. | Confirmed in one local report and independently in upstream #2250. |
| 4 | Provider storage scanning, WebKit, or account refresh is corrupting memory. | The faulting thread should be a scanner/WebKit/provider frame rather than the executor-check chain. | Not supported; the scanner was a background thread in one report and was not faulting. |
| 5 | Sparkle or application policy is voluntarily quitting the app. | Reports should show clean termination or update activity rather than `SIGSEGV` / `KERN_INVALID_ADDRESS`. | Not supported for six reports; one `RegisterApplication` abort remains an unrelated outlier. |

## Implementation decisions

### Synchronous image materialization

`NSImage(size:flipped:drawingHandler:)` creates an `NSCustomImageRep`. AppKit
can invoke that closure later while drawing the `NSTextAttachment`, which puts
the closure on the same Objective-C/Swift executor seam seen in the crashes.

The renderer now creates a 2x `NSBitmapImageRep`, performs the source draw and
template tint while the renderer is already on `MainActor`, and attaches the
finished bitmap. The render cache already includes `appearanceName`; the
materializer resolves both the short test names (`aqua`, `darkAqua`) and the
raw AppKit names passed by `NSStatusBarButton`, preserving light/dark menu-bar
appearance.

### Explicit actor hop for notification selectors

The two AppKit notification selectors are now Objective-C-facing
`nonisolated` entry points. They do no actor-isolated work themselves. Each
starts a `Task { @MainActor ... }` and invokes the existing stateful logic only
after the hop. This removes the compiler-generated actor-entry check from the
Objective-C callback while retaining main-actor ownership for the actual view
and controller state.

### Deliberate non-goal: synchronous menu delegate

`menuNeedsUpdate(_:)`, `menuWillOpen(_:)`, and `menuDidClose(_:)` are
synchronous `NSMenuDelegate` callbacks. Converting them to an asynchronous
task would risk presenting an incompletely populated menu, while using an
unchecked actor escape would merely move the runtime assumption. The local
crash set did not include these callbacks, so this branch leaves them intact
and calls out upstream #2250 as a follow-up validation item.
