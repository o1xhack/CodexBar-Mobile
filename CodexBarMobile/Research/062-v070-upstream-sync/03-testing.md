# 本轮测试证据

Status: `in-progress`

目前仅通过 SSD UUID/挂载/realpath/可写检查，以及 GitHub release/issue/version 读取。未执行构建或完整测试；下面 pending 不是 pass。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 2 | old | old | old | new | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 3 | old | old | new | old | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 4 | old | old | new | new | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 5 | old | new | old | old | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 6 | old | new | old | new | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 7 | old | new | new | old | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 8 | old | new | new | new | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 9 | new | old | old | old | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 10 | new | old | old | new | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 11 | new | old | new | old | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 12 | new | old | new | new | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 13 | new | new | old | old | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 14 | new | new | old | new | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 15 | new | new | new | old | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |
| 16 | new | new | new | new | pending | 未验证 | 尚待测试；不可推断 Production 收敛或 silent push |

## 当前命令证据

日志目录 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070`。

- mac-build-tests.log：swift build --build-tests，exit0，326.65秒；初次merge tree构建，不覆盖之后parser18和period细化。
- mac-focused-r1.log：Scripts/test_fast.sh，41 tests / 6 suites / 0 failed。对应filter GrokTokenSnapshotProjectionTests、SyncV070PartialHistoryTests、WidgetEmptyProjectionTests、QuotaBurndownModelTests、KimiMonthlyBlockingTests、ClaudeRateLimitResetCreditsTests。
- test-fast-runner-r2.log：环境脱敏及runner黑盒10 tests，exit0。
- CI policy、CI path gate、fork README guard通过。
- lint.log：Python3.9缺waitid，失败；lint-r2.log：env fixture没有识别--skip-build，失败；lint-r3.log：social image token不一致，失败；以上没有作为最终lint通过证据。
- mac-full-r1.log：完整测试已启动，session81548，仍需查询进程终态与实际计数，不得按启动视为通过。
