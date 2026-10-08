# 成本账本：数据缺失或无法定价时不再丢历史

Status: `done`
Date: 2026-10-08
Version: iOS 2.6.0 (237)

## 事故

2026-10-07，用户两台 Mac 升级到 0.72.0.1 后，iPhone 成本页的本地历史（CWL，365 天）从约 $15.5k 降到约 $9.4k，“今天”也没有数据。

证据来自三处：
- **Pro Max（2.6.0 build 236）的 SwiftData 账本**，用 `devicectl` 只读拷贝。
- **iPhone Air（2.5.0 build 231）的账本**：它停在 10/7 13:12 写入，早于 Mac 升级，可作对照。备份在 `BuildScratch/CodexBar/diag-236/air`。
- **Mac Studio 本机的成本缓存**。

账本有两处丢失：

1. **Codex：“未知”覆盖了“已知”。** Mac 0.72.0.1 的上游 v0.72.0 request-ledger 迁移有缺陷（见 Research 070），把 09-03 以后每天都发成 `costIsKnown=false`、金额 0。`CostLedgerService.upsertDayPoint` 让较新的“未知”覆盖了已知金额。例如 Studio 09-20 的 $363.1 变成 0，Studio Codex 合计从 $7,722 降到 $2,430。
2. **Studio Claude：账号缺失时历史被整段删除。** Studio 的 Claude 一度发布“没有账号、没有成本、也没有错误”的条目（见 Research 070 的 Claude 部分）。有三条路径会按“设备 + 服务商 + 账号”精确匹配，旧账号的全部历史（$2,833）就这样被删掉了：
   - `SwiftDataBridge.upsertSnapshot` 的旧快照裁剪；
   - CloudKit 记录删除；
   - `CostLedgerService.pruneLedgerRowsMissingProviderSnapshots`。

这两类问题在 Research 052 里已经指出过，但一直没有修完：
- “临时 provider 缺失”的账本生命周期；
- “未知不覆盖已知为伪零”。

Research 024 的原始产品规则是“Mac 卸载 provider 时旧 daily 点保留供历史查询”，而后加的裁剪与这条规则相悖。

## 规则

**账本只有一种删除：用户在设置里显式清除。** 其余场景如下：

| 场景 | 处理 |
|---|---|
| Mac 发布某天“成本未知”，账本已有该天的正金额 | 保留已知金额和 token；之后的已知发布仍会更新。已知 $0 不保护 |
| 同一天两行合并（旧键迁移、成本归属迁移、跨 Mac 的 account-level 取值） | 已知正金额胜过未知；否则取较新的 |
| 快照缺失、被缓存过滤、CloudKit 记录删除、服务商被关闭 | 只删快照行，账本历史保留 |
| `costSummaryCleared`（成本已转移）标记 | 不删除。若本快照有唯一的新成本归属，历史迁到它名下；否则留在原账号，等归属出现再迁 |
| 本地成本服务商（claude/codex/grok/opencodego/vertexai）出现唯一的新成本归属 | 只存在于账本里的旧归属（无快照）一并迁过去，同一台机器不会算两次 |
| account-level 服务商、account-native（Mistral） | 不在账号之间迁移 |

匹配不到当前卡片的历史保留在库中，但不计入成本页或 Token 活动；对应的服务商或账号回来时自动接回。补种判定与写入共用“保留已知”的判断，被保护的天不会在每次聚合时被重复补种。

## 取舍

- **当天先发已知部分值、后发未知时**，账本会停在最后一次的已知值，直到 Mac 再发出已知值。review 建议过“token 增长时改成下限值 + 未知”，但这次事故里 0.72.0.1 恰好把历史天的 token 也翻了倍，按那条规则正好会让被保护的历史天失去保护，所以没有采纳。
- **已经丢失的数据，这个修复恢复不了。**
  - Codex 天由修好的 Mac 0.73.0.1 从会话日志重建，重新发布正确的已知值。
  - Studio 6–9 月的 Claude 原始记录已被 Claude Code 清理，只能从 iPhone Air 的备份补回。另行处理，补回前先给用户看对账结果。
- **已归档或已移除的 Mac**，历史保留在账本里，但被 `activeDeviceIDs` 过滤，不计入成本页（行为不变）。

## 测试

`CostLedgerPreservationTests`：
- 未知不覆盖已知：单元级测试，以及经 `SwiftDataBridge` → 聚合 → `fromLedger` 的端到端测试，并断言不会重复补种；
- 已知 $0 与 legacy 金额的保护规则；
- 合并时已知优先；
- 账号暂时缺失时保留历史；
- 只存在于账本里的旧归属整体迁给下一个本地成本归属，并且只计一次；
- account-level 不跨账号迁移；
- 关闭服务商后历史保留但不显示；
- 记录改名时保留历史；
- tombstone 不删历史。

CWLSeedTests、SwiftDataBridgeTests 中原先断言“删除”的用例，已按新规则改为“保留、但不显示”。

## Review

- **第一轮本地 review**：0 个阻塞，3 个重要问题，均已处理：
  - 被保护的天让补种判定恒为真；
  - 已知优先规则过粗（已知 $0 也被保护）；
  - 事故场景缺端到端测试。
- **采纳的建议**：
  - tombstone 不再删除；
  - account-level 跨 Mac 取值也已知优先；
  - 修正注释错位；
  - 非本地服务商不再查询账本归属；
  - 测试改名。
- **Codex Review（PR #184 第 1 轮）**：4 条 P1，均已修复：
  - account-level 逐日选取改为确定的全序规则 `preferredDay`，三台 Mac 分别为已知正数、已知 0、未知时，结果与读取顺序无关；
  - build 升到 237；
  - CHANGELOG、App 内四语言 2.6.0 说明与 App Store 说明补上本修复；
  - 本文档状态改为 done。
