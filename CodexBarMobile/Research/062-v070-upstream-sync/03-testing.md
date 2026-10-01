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
