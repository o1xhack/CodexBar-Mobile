---
summary: "o1xhack fork quick start: differences from upstream, iOS companion app, and key commands."
read_when:
  - Onboarding to the fork workflow
  - Reviewing fork-specific changes
---

# CodexBar Fork — Quick Start

**Fork Maintainer:** Yuxiao Wang ([o1xhack](https://x.com/o1xhack))
**Original Author:** Peter Steinberger ([steipete](https://twitter.com/steipete))
**Fork Repository:** https://github.com/o1xhack/CodexBar-Mobile
**Branch:** `mobile-dev`

---

## What Makes This Fork Different?

### iOS Companion App
The primary addition is **CodexBar Mobile** — an iOS app that syncs usage data from Mac via iCloud CloudKit.

- Multi-device sync: multiple Macs → one iPhone
- Session quota push notifications (depleted/restored)
- Cost dashboard with daily charts, model breakdowns
- Subscription utilization history charts
- 4-language localization (en/zh-Hans/zh-Hant/ja)

### Mac Changes (vs Upstream)
- **Signing:** Developer ID: Yuxiao Wang (3TUERHN53E)
- **Bundle ID:** com.o1xhack.codexbar
- **Sparkle feed:** Points to o1xhack/CodexBar-Mobile mobile-dev branch
- **Build number:** Composite `BUILD_NUMBER.MOBILE_VERSION` (e.g. 54.1.1.0)
- **CloudKit sync:** SyncCoordinator pushes usage data to CloudKit
- **About page:** Fork links (GitHub, website, Twitter, email)

## Key Files

| Path | Purpose |
|------|---------|
| `CLAUDE.md` | Project overview + Todoist integration rules |
| `AGENTS.md` | Complete 7-step development workflow |
| `CodexBarMobile/` | iOS app (Xcode project via xcodegen) |
| `Shared/` | Shared sync layer (Mac + iOS) |
| `docs/RELEASING-MOBILE.md` | Mac release workflow for the fork |
| `docs/ios-cloudkit-sync.md` | CloudKit sync architecture |
| `plan.md` | Feature tracking and roadmap |

## Quick Commands

```bash
# Mac build
swift build

# Mac test
swift test
make test

# iOS build
cd CodexBarMobile && xcodegen generate && xcodebuild -scheme CodexBarMobile build

# Mac release (sign + notarize)
./Scripts/sign-and-notarize.sh

# iOS TestFlight
cd CodexBarMobile && xcodebuild archive ... && xcodebuild -exportArchive ...
```

## Upstream Sync

```bash
git fetch upstream
git merge v0.XX.0 --allow-unrelated-histories
# Resolve conflicts: keep our fork files, take upstream for Sources/Tests
swift build && swift test
```

See `docs/RELEASING-MOBILE.md` for the full release workflow.
