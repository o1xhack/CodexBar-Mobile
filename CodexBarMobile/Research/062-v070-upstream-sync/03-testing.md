# 本轮测试证据

Status: `in-progress`

已执行初次Mac构建和定向测试；最终完整测试、iOS验证和设备矩阵尚未完成。下面pending不是pass。

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

## 后续验证状态（2026-10-01）

- lint-r4.log：portable/JS/SwiftFormat通过，SwiftLint发现新增测试12处multiline arguments；只修正两份测试参数换行，定向SwiftFormat/SwiftLint零违规。
- lint-r5.log：此前gates再次通过；扫描期间新增Claude桥接测试，SwiftLint发现1处Data→String规则，现已改用failable initializer，新增两测试文件定向lint通过。全树最终lint仍待终态。
- mac-full-r1.log：1518 selections以group-size=1执行到约第133组；因为后续Kimi/Claude桥接实现改变了受测源码，显式SIGINT停止旧binary运行，exit130。已运行部分只能作早期回归证据，不是完整pass。最新源码需重建并用默认group-size=12重新完整跑；不把中断计为测试失败修复或通过。
- mac-bridge-r1.log：最新Mac桥接、Grok projection、parser cache定向构建/测试已启动，session32408，结果尚待查询。

- lint-r6.log：exit0，全树所有lint与安全/CI/发布脚本guards通过；SwiftLint2749 files零违规，iOS367 source keys齐全且四语言translated。随后modelsUsed的Shared/mapper/test定向SwiftLint零违规。
- mac-bridge-r1.log：Core internal makeSection从app不可访问，编译失败；改为过滤已映射的Sync detail section。
- mac-bridge-r2.log：exit0，11 tests / 4 suites；mac-bridge-r3.log：exit0，12 tests / 4 suites，包含Kimi真实pusher与native Claude wire。
- mac-bridge-r4.log：新增modelsUsed wire roundtrip及旧JSON fallback后重跑；成功后同一session46144自动执行mac-full-r2.log（repo默认12 selections/group、180s timeout）。必须读取r4与full-r2终态，不能把pipeline启动作通过。

mac-bridge-r4.log最新树构建与12 tests/4 suites通过，含modelsUsed wire roundtrip/旧JSON fallback；同pipeline已进入mac-full-r2，137 groups（12 selections/group），当前未结束。session46144维持运行。
