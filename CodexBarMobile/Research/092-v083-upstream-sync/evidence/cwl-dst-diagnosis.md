# CWL T17 独立诊断：UTC逻辑日历未固定timezone

Reviewed commit: `84410b51995415978b16f0a00fe23a4f678e9166`
Reviewer: /root/upstream_audit
结论：**确定的既有生产逻辑缺陷（P1），不是性能超时或随机fixture flake**。这两个生产/测试文件本轮原来没有diff；在本轮全量测试中暴露，不能通过把预期365降成364来处理。

## 证据链

`ios-tests.log`第6262–6271行：dailyPoints=364、totalCost少40、totalTokens少4000，正好40个provider各少1天。elapsed阈值没有报失败。

`CWLPerformanceTests.swift`第32–40行以同一个now按86400秒生成365个UTC日期，producer明确bucketTimeZoneIdentifier=UTC且readerTimeZone=UTC。在2026-11-06T22:07Z这个时刻，这组fixture确实有365个不同UTC dayKey，fixture目标成立。

问题位于`CostLedgerService.swift:1202–1207`：logicalDayKeyFormatter设置formatter.timeZone=.gmt，但给formatter的Gregorian calendar未设置calendar.timeZone。Foundation返回的formatter.calendar仍是America/Los_Angeles。`makeSourceDayWindows`第1134、1145–1148行直接用它做逻辑日加减，计算从UTC午夜出发却用LA日历跨DST，最终字典缺失2026-11-01。readerRelativeDayKey查不到映射，整个日期的40条数据被丢弃。

独立合成Foundation复现（不调用App、不访问SwiftData/真实数据、不使用xcodebuild或共用DerivedData）：

```text
formatter zone GMT calendar zone America/Los_Angeles
unique fixture 365 window 364 intersection 364
missing ["2026-11-01"]
oldest key 2025-11-07 min fixture 2025-11-07
fixed calendar zone GMT window 365 intersection 365
formatter zone GMT calendar zone America/Los_Angeles
unique fixture 365 window 364 intersection 364
missing ["2026-11-01"]
oldest key 2025-11-07 min fixture 2025-11-07
fixed calendar zone GMT window 365 intersection 365
age 0 buggy 2026-11-06 UTC 2026-11-06
age 1 buggy 2026-11-05 UTC 2026-11-05
age 2 buggy 2026-11-04 UTC 2026-11-04
age 3 buggy 2026-11-03 UTC 2026-11-03
age 4 buggy 2026-11-02 UTC 2026-11-02
age 5 buggy 2026-10-31 UTC 2026-11-01
age 6 buggy 2026-10-30 UTC 2026-10-31
age 7 buggy 2026-10-29 UTC 2026-10-30

```

复现脚本：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/v083/repro-cwl-calendar.swift`。
脚本SHA-256：`00df53cff436b84787940a8b5553e773ac6c672866d19989120eb86ebb687b0a`。
日志SHA-256：`116a829855dacf3f4d6ae51acfe8d5d5d0d5756036f5945482fa3739db9dcae4`。

## 建议最小修复

给逻辑日历本身固定UTC，再赋给DateFormatter，继续保留formatter的GMT设置：

```swift
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = .gmt
formatter.calendar = calendar
```

同一复现加此修复后window distinct=365、intersection=365，所有fixture日期均保留。

补一个确定性source-aware aggregate回归：固定asOf=2026-11-06T22:07Z、producer UTC/reader UTC、默认系统日历timezone为America/Los_Angeles，365天×至少1provider（或跨11月1日的短窗口），断言全日期和总额。默认timezone必须defer恢复；或用可注入逻辑日历的纯seam避免全局状态。保留现有T17数值预期和性能阈值，修复后单独复测再重跑所需受影响回归。

本诊断没有修改源码。ImageRenderer的cgImage nil未在本诊断重现，不能从这次DST证据推断其原因。
