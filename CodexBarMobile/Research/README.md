# Feature Research

This directory contains research documents for features being considered for CodexBar Mobile (iOS).

## Status Legend

| Status | Meaning |
|--------|---------|
| `draft` | Feature is under research / investigation |
| `blocked-upstream` | Research done, waiting for upstream PR to merge before we can proceed |
| `ready` | Research done, ready to implement |
| `in-progress` | Currently being implemented |
| `done` | Research completed and feature has been implemented |
| `dropped` | Decided not to pursue this feature |

## Index

| # | Feature | Status | Blocker | File | Date |
|---|---------|--------|---------|------|------|
| 001 | Daily Provider Utilization Chart | `blocked-upstream` | [upstream PR #565](https://github.com/steipete/CodexBar/pull/565) | [001-daily-utilization-chart.md](001-daily-utilization-chart.md) | 2026-03-19 |
| 002 | Cost Share Card (One-Tap Share) | `done` | — | [002-cost-share-card.md](002-cost-share-card.md) | 2026-03-19 |
| 008 | iOS Data Architecture Refactor (CloudKit split + view caching + local persistence) | `ready` | — | [008-ios-data-architecture-refactor.md](008-ios-data-architecture-refactor.md) | 2026-04-18 |
| 009 | iOS 1.3.0 Implementation Plan (SwiftData + per-provider CloudKit + change tokens) | `ready` | — | [009-1.3.0-implementation-plan.md](009-1.3.0-implementation-plan.md) | 2026-04-18 |
| 018 | Generic Model Fallback Pricing (Tier-A resolver design + 27-provider survey) | `ready` | — | [018-model-fallback-pricing.md](018-model-fallback-pricing.md) | 2026-04-27 |
| 019 | Account Identity Multi-Version Merge (set-based identity + iOS union-find + L3 user-confirmed linkage + 23-case edge audit) | `ready` | — | [019-account-identity-multi-version-merge.md](019-account-identity-multi-version-merge.md) | 2026-04-27 |
| 021 | Mock-First Quality Infrastructure (32-mock injection + iOS visual + CI gating + PR template) | `done` | — | [021-mock-first-infrastructure.md](021-mock-first-infrastructure.md) | 2026-05-03 |
| 022 | v0.27.0 Upstream Sync + iOS 1.8.0 (7 new providers + Claude Admin API + Kiro overage + MiniMax billing history) | `in-progress` | — | [022-v027-upstream-sync-ios-180.md](022-v027-upstream-sync-ios-180.md) | 2026-05-19 |
| 024 | Cost Window Ledger (B path: iOS local per-day ledger so iOS window selection is independent of Mac historyDays) | `ready` | — | [024-cost-window-ledger/README.md](024-cost-window-ledger/README.md) | 2026-05-28 |
| 025 | v0.31.0 Upstream Sync + iOS 1.10.0 (0.29.1 deferred + 0.30.0/0.30.1/0.31.0 → DeepSeek usage card + Codex Spark/Antigravity lanes auto-passthrough + value fixes; 4-doc set: overview/design/dev+arch/testing) | `ready` | — | [025-v031-upstream-sync/00-overview.md](025-v031-upstream-sync/00-overview.md) | 2026-05-30 |
| 026 | v0.32.x Upstream Sync + iOS 1.11.0 (v0.32.0-v0.32.4 value fixes, parser cache invalidation, release notes, shipped Mac/iOS) | `done` | — | [026-v032-upstream-sync/00-overview.md](026-v032-upstream-sync/00-overview.md) | 2026-06-03 |
| 027 | Upstream Release Monitor Fix (version.env-based release issue generation, stop quotio commit noise) | `done` | — | [027-upstream-release-monitor.md](027-upstream-release-monitor.md) | 2026-06-09 |
| 029 | v0.35.0 Upstream Sync + iOS 1.12.0 (open issues #22/#23/#24/#26, v0.32.5-v0.35.0 as one release, MiniMax metadata + Devin/Amp/Copilot/Kimi/MiMo audit; Mac release live) | `done` | — | [029-v035-upstream-sync/00-overview.md](029-v035-upstream-sync/00-overview.md) | 2026-06-14 |
| 030 | v0.36.1 Upstream Sync + iOS 1.13.0 (issue #28, v0.36.0-v0.36.1 as one release, LiteLLM/Poe/Chutes/Zed + Antigravity reset audit) | `done` | — | [030-v036-upstream-sync/00-overview.md](030-v036-upstream-sync/00-overview.md) | 2026-06-16 |
| 031 | Post-Merge Mobile Dev Audit (already-merged mobile-dev review, v0.26.4-mobile.1.7.0 -> v0.35.0.1-mobile.1.12.0; push diagnostics + compiler warning cleanup) | `done` | none | [031-post-merge-mobile-dev-audit.md](031-post-merge-mobile-dev-audit.md) | 2026-06-17 |
| 032 | iOS Sync Device Management (issue #29, merge duplicate Mac identities, archive retired devices, restore/unmerge, iOS 1.14.0) | `done` | CloudKit Production schema deploy required before TestFlight/release | [032-ios-sync-device-management/00-overview.md](032-ios-sync-device-management/00-overview.md) | 2026-06-20 |
| 034 | iOS WidgetKit Suite (small/medium/large configurable Home Screen widgets for provider usage, today cost, and sync health) | `done` | None; App Group cache path deferred pending explicit entitlement approval | [034-ios-widget-suite.md](034-ios-widget-suite.md) | 2026-06-28 |
| 035 | Cost Ledger Summary Floor (CWL provider totals must not undercount Raw Sync Data summaries) | `done` | None | [035-cost-ledger-summary-floor.md](035-cost-ledger-summary-floor.md) | 2026-06-29 |
| 036 | Widget Completion Audit (data parity, fallback, AppIntent configuration, visual matrix, and release handoff gate) | `in-progress` | Stable SpringBoard gate now opens the real edit panel and switches one mode; tinted and continuous all-mode switching still need stronger proof before closure | [036-widget-completion-audit.md](036-widget-completion-audit.md) | 2026-07-02 |
| 037 | v0.39.0 Upstream Sync + iOS 1.17.0 (issue #37, v0.38.0-v0.39.0 as one release, new providers + provider display data + draft release gate) | `in-progress` | GitHub draft release requires remote tag confirmation; full Mac `swift test` timing residual documented | [037-v039-upstream-sync/00-overview.md](037-v039-upstream-sync/00-overview.md) | 2026-07-04 |
| 038 | Cost Data Integrity Audit (CWL reducer parity, Provider Share, daily/category/share-card correctness) | `done` | — | [038-cost-data-integrity-audit.md](038-cost-data-integrity-audit.md) | 2026-07-06 |
| 039 | v0.41.0 Upstream Sync + iOS 1.18.0 (issues #42/#44/#46, v0.40.0-v0.41.0 as one release, Kimi quota lanes + Claude Max multiplier + sub-1% formatting, Mac draft gate) | `in-progress` | None; remote draft must respect no-push/no-published-tag boundary | [039-v041-upstream-sync/00-overview.md](039-v041-upstream-sync/00-overview.md) | 2026-07-09 |
| 041 | Release CLI Fork Homebrew Gate (issue #50, keep fork CLI assets while skipping upstream-only tap dispatch) | `done` | — | [041-release-cli-fork-homebrew-gate.md](041-release-cli-fork-homebrew-gate.md) | 2026-07-16 |
| 042 | v0.45.2 Upstream Sync + iOS 1.19.0 (issues #48/#51 plus authoritative Releases v0.42.0-v0.45.2 as one train) | `done` | Draft ready; push/merge/live release/TestFlight/tag/appcast publish remain intentionally unperformed | [042-v045-upstream-sync/00-overview.md](042-v045-upstream-sync/00-overview.md) | 2026-07-19 |
| 043 | Alibaba Token Plan Rate Windows Hotfix (issue #59, rolling 5-hour and weekly usage restoration ahead of upstream release) | `done` | Live Alibaba account proof and signed publication remain separate gates | [043-alibaba-token-plan-rate-windows.md](043-alibaba-token-plan-rate-windows.md) | 2026-07-24 |
| 044 | Subscription Utilization Fresh-Series Fallback (stale session history no longer masks current weekly quota data) | `done` | — | [044-subscription-utilization-freshness-fallback.md](044-subscription-utilization-freshness-fallback.md) | 2026-07-26 |
| 045 | v0.47.0 Upstream Sync + iOS 1.20.0 (issue #66 plus authoritative Releases v0.46.0-v0.47.0 as one train; upstream Mac fleet sync isolated from the existing Mobile sync contract) | `done` | Draft complete; CloudKit Production schema deploy and live publication remain separate authorization gates | [045-v047-upstream-sync/00-overview.md](045-v047-upstream-sync/00-overview.md) | 2026-08-03 |
| 046 | v0.49.2 Upstream Sync + iOS 1.21.0 (issues #77-#80 plus authoritative v0.49.2; provider plugins/instance identity, generic details, Fireworks/IBM Bob, fleet dedupe) | `done` | Mac `0.49.2.1` live + signed appcast/CLI assets; iOS `1.21.0 (193)` TestFlight `VALID`; CloudKit `NO_DEPLOY`; substituted 16-mask matrix pass | [046-v049-upstream-sync/00-overview.md](046-v049-upstream-sync/00-overview.md) | 2026-08-17 |
