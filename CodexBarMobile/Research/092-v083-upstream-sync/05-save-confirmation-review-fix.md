# 追加远端审查：无损 save-result 确认

状态：done（修复、本地验证与Mac重建完成；远端当前head审查/线程关闭以PR实时结果为准）。

PR232的dfa3dc0b8先收到手动审查clean回执；标记ready触发同head追加自动审查，发现[P1](https://github.com/o1xhack/CodexBar-Mobile/pull/232#discussion_r4498894600)。旧回执及Fast Checks不是追加审查完成的替代；本轮交接同时核对实时Codex Review Summary、receipt、threads与checks。

## 根因与修复

Claude/Grok原生reset-credit行只允许live展示；UsageSnapshot.init(from:)有意过滤这些details。CloudSyncBatchRecordProvider.shouldApplySaveResult此前对保存回执decode→re-encode，其hash因此不同于原始pending hash，成功save仍不能清marker，后续同账号snapshot一直defer。

保持原pending→confirmed hash及dedupe合同不变，改为要求pending marker与对应desired record存在，再对比两条CKRecord的原始序列化字段：schemaVersion/provider/deviceID/accountKey/fetchedAt/displayLabel/usagePayload。usagePayload作为opaque字符串，不走UsageSnapshot decoder；日期仍用原canonical ISO8601语义，system fields不参与。marker存在时新payload只进入pending/fleet、不覆盖desired；冲突与unknownItem只重建system fields，因此不会把旧回执确认成新内容。成功与失败两个filter共用该检查。缓存decode仍过滤live inventory，没有放松隐私/缓存规则，没有新hash版本或CloudKit schema变更。

## 验证与产物

CloudSyncBatchRecordProviderTests专项6个方法（13个参数化执行）通过：Claude/Grok live-only decode确实改变旧hash、成功确认清pending并保留原hash、只改变reset库存的旧回执拒绝、全部metadata字段差异拒绝、missing pending/desired与duplicate拒绝、system-field rebase后原始内容确认、非snapshot行为保持。

最终Mac全量1869 selections/89 groups首轮全部通过，0失败/timeout/重试；新source a6ab1035b重新签名、公证、staple、隔离smoke、双架构UUID/Production/AppGroup与Sparkle签名验证全部通过，GitHub替换附件digest/size匹配。该P1本身未改变iOS输入；后续P2改变本地化分发并重建Archive，见06，不再使用旧23ff候选。旧Mac附件已保留为superseded历史副本；新包已更新同一draft437184008，不新建tag或公开发布。最终source/hash与远端审查以04和PR当前head为准。
