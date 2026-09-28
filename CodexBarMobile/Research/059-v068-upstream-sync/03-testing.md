# 测试、CloudKit 与 16 组合兼容证据

Status: `in-progress`
Date: 2026-09-28

## 环境与目标版本

- 分支：`upstream-sync/v0.68.0-mobile.2.3.0`，base `origin/mobile-dev` `91501264c1607f603240376208a094f94c8000ba`。
- Old Mac / iOS：已发布 Mac `v0.66.0.1`；现有 iOS 2.2.0 (222) 已送 App Review。New candidate：Mac `0.68.0.1 (159.1)` / iOS `2.3.0 (223)`。
- 本节在 implementation、构建和测试后补入确切命令、退出状态、测试数量、BuildScratch 路径、审计 verdict 和 review findings。当前还没有测试或真实设备结论。

## 计划测试

- Mac：`swift build`、完整 `swift test`、`bash Scripts/lint.sh lint`、`Scripts/check_ci_policy.sh`、provider/parser/cost/history/credential-safety/SyncCoordinator 重点回归。所有 Xcode / SwiftPM scratch、result bundle 和临时数据库在 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/`；只使用 mock / `KeychainNoUIQuery`，不运行 live provider/keychain probe。
- iOS：`xcodegen generate`、Simulator build、provider display/detail/color/payload compatibility 和 CloudKit merge tests；检查 build 223 的所有 targets 一致。
- i18n：`bash Scripts/lint.sh audit-i18n`，确认新增 source keys 在四语言为 `translated`。
- CloudKit：从最后发布 Mac tag `v0.66.0.1-mobile.2.1.0` 比较最终 tree，执行 docs 中的 schema keyword、`CloudConstants.swift`、`UsageSnapshot.swift` 检查。不得把 mock/Development evidence称作 Production deploy/readback。

## 2 Mac × 2 iPhone × old/new 16 组合

结果必须每格为 `pass`、`fail` 或 `substituted`。真实 Production 双 Mac、双 iPhone 若不可得，依规范标注 `substituted` 并列证据路径与剩余风险。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | pending | pending | |
| 2 | old | old | old | new | pending | pending | |
| 3 | old | old | new | old | pending | pending | |
| 4 | old | old | new | new | pending | pending | |
| 5 | old | new | old | old | pending | pending | |
| 6 | old | new | old | new | pending | pending | |
| 7 | old | new | new | old | pending | pending | |
| 8 | old | new | new | new | pending | pending | |
| 9 | new | old | old | old | pending | pending | |
| 10 | new | old | old | new | pending | pending | |
| 11 | new | old | new | old | pending | pending | |
| 12 | new | old | new | new | pending | pending | |
| 13 | new | new | old | old | pending | pending | |
| 14 | new | new | old | new | pending | pending | |
| 15 | new | new | new | old | pending | pending | |
| 16 | new | new | new | new | pending | pending | |

## Final verdict

Pending. Do not claim compatibility gate completion until all 16 rows have an evidence-backed result and every failure is fixed/rerun or explicitly held as a blocker.
