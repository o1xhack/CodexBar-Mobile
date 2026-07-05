# v0.39.0 Upstream Sync Development Log

Status: `in-progress`
Date: 2026-07-04
Branch: `upstream-sync/v0.39.0-mobile.1.17.0`

## Checkpoints

### 2026-07-04 Research and Branch Setup

Evidence gathered:

```text
git status --short --branch
git fetch origin --prune --tags
git fetch upstream --prune --tags
git switch mobile-dev
git pull --ff-only origin mobile-dev
gh issue list --repo o1xhack/CodexBar-Mobile --state open --limit 100 --json number,title,labels,createdAt,updatedAt,url,body
gh issue list --repo o1xhack/CodexBar-Mobile --state closed --search "upstream-sync OR 上游" --limit 30 --json number,title,closedAt,labels,url
gh release list --repo steipete/CodexBar --limit 30 --json tagName,name,publishedAt,isDraft,isPrerelease,isLatest
gh release view v0.38.0 --repo steipete/CodexBar --json tagName,name,publishedAt,body
gh release view v0.38.1 --repo steipete/CodexBar --json tagName,name,publishedAt,body
gh release view v0.39.0 --repo steipete/CodexBar --json tagName,name,publishedAt,body
git ls-remote --tags upstream 'v0.37.2' 'v0.38.0' 'v0.38.1' 'v0.39.0'
git show v0.39.0:version.env
git diff --stat v0.37.2..v0.39.0
git diff --name-only v0.37.2..v0.39.0 -- Sources/CodexBarCore/Sync Shared CodexBarMobile Sources/CodexBarCore/UsageFetcher.swift Sources/CodexBarCore/WidgetSnapshot.swift Sources/CodexBar/UsageStore+WidgetSnapshot.swift Sources/CodexBarCore/ProviderCostSnapshot.swift Sources/CodexBarCore/CostUsageModels.swift Sources/CodexBarCore/CreditsModels.swift
git diff --name-only v0.37.2..v0.39.0 -- Sources/CodexBarCore/Providers
```

Result:

- `mobile-dev` was up to date with `origin/mobile-dev`.
- Work branch created: `upstream-sync/v0.39.0-mobile.1.17.0`.
- Open upstream-sync issue scope is #37 only.
- Closed upstream-sync issues confirm prior one-version consolidation pattern.
- Upstream latest official release is `v0.39.0`.
- Target fork versions are `0.39.0.1`, `97.1`, `1.17.0`, Sparkle
  `97.1.1.17.0`.

## Pending Implementation Steps

1. Merge `v0.39.0`.
2. Resolve conflicts, preserving fork release/sync/iOS constraints.
3. Fix provider switch exhaustiveness for `sakana`, `qoder`, `crossmodel`, and
   `clawrouter`.
4. Audit and implement iOS support for new provider data and any lost
   user-visible upstream values.
5. Update version files, changelogs, release notes, localization, tests, and
   mock/preview data.
6. Run build/lint/test gates and compatibility matrix substitutions or real
   hardware evidence.
7. Run draft release prep and record artifact evidence.
8. Run final review loop and fix all blockers.

## Merge Notes

Pending.

## iOS Bridge Notes

Pending.

## Review Notes

Pending.
