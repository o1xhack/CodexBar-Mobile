# fork parser revision 测试合同独立诊断

Reviewer: /root/upstream_audit

## 确定根因

1. `CostUsageForkParserRevisionTests` 所有 `CostUsageStoreAccess.read/replace(cacheRoot:...)` 与最后 `CostUsageStore(cacheRoot:...)` 都未传 fixture home。scanner options 指向 `env.codexSessionsRoot`，新home-scoped store把数据写到 `CodexHomeCostStoreScope.key(sessionsRoot: env.codexSessionsRoot)`，默认StoreAccess却读当前用户CODEx home。因此legacy.files为空不是scanner数据没写；应在每次read/replace和reopen一致传 `home: env.codexStoreHome`（CostUsageTestFactory已有该属性）。不可为测试恢复全库无home读写。
2. `CostUsageScanner+ForkParserRevision.swift` 的metadata-only优化只适用于12→13。`currentCodexParserRevision=14`后，helper显式current==13守卫使needs=false/adopt=nil是正确行为。上游14修复同一turn恢复后的service_tier：必须重读thread_settings_applied及后续turn_context，不能只补session_meta后把旧行盖成current。

## 正确更新测试合同

- 不把creatorAccountParserRevision改成14；不把守卫改成>=13；不为了旧测试在生产路径跳过14重算。
- 重新命名两个integration case为“native older revisions reparse to current accounting and preserve final history/fork baselines”，将fixture旧revision参数化为12、13。
- 保留已有完整最终校验：final.data等于干净reference-cache scan，token totals250/350和parent-child350/450，creator flag、token snapshot历史、token checkpoints、稳定父子fork baseline均保留。
- 一字节扫描只校验bounded/尚在catchup的真实合同，不再断言第一轮立即current或对所有旧版本metadata-only采用。先修home后观察缓存的codexScanCatchUpPending/覆盖状态；若系统保留已建立previousReport，则可以继续验证用户可见报告在catchup过程中不被当完整已知零覆盖，但不要用旧metadata-only路径模拟14已完成。
- helper测试在current14应明确断言：rev12/13/当前/更老版本均不会走creator-only adoption；可读无creator的apikey leaf也返回nil。不要保留必失败的#require(adopted)或仅用skip掩盖14升级。若保留历史helper作下次维护参考，在注释明确它已被14取代；无需扩展生产API只为让历史13目标可测试。
- `CostUsageCodexSessionTierTests`已有真实13→14回归：故意把三行tier设成standard/standard/priority，重扫后必须standard/priority/standard，totalCost 0.00592。可将旧revision参数化为12和13，将该校验作为防止今后放宽metadata-only守卫的证据。

## 成本保留边界

14的必要重算和历史13的metadata-only优化不是同一合同。不可要求14沿用错误Fast行，也不可通过清空用户数据库回避migration。应以home内原生行/归档保留、bounded catchup显式不完整、最终clean-reference一致及fork baseline/snapshots/checkpoints完整来证明新合同。

## DST补充复审

486be990f的生产修复正确：为formatter.calendar显式设置GMT，使逻辑日期加减不受系统DST影响。新固定三日fixture正确；建议同步@MainActor测试在开头临时把NSTimeZone.default设为America/Los_Angeles并defer恢复，确保UTC CI也能稳定重现原bug。未修改源码或争用xcodebuild DerivedData。
