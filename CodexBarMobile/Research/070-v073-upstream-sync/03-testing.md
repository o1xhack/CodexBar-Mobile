# 测试

Status: `done`（截至 0d2e3b365）

## Mac

- `Scripts/test.sh` 全量：1637 个选择，148 组。
  - 第 1–135 组在最终修复前已首轮全部通过。
  - 中途失败的三类均已修复，并在单测和定向测试中重跑通过：
    - 上游 0.73 的 Codex 选定账号快照保留测试：fork 开启 iCloud 同步时会抓取全部账号，夹具已关闭该开关；
    - ClinePass token 账号哨兵测试：已登记；
    - 负载导致的 `StatusMenuCodexSwitcherTests` 超时：单独运行 22 项、6 秒内通过。
  - 从 `TokenAccountSyncCoverageTests` 起的其余 137 个 suite 用 `--no-parallel` 补跑，1094 项全部通过。
  - 日志：`BuildScratch/CodexBar/v073-mac-full5.log`、`v073-mac-tail.log`。
- 定向测试：
  - `ProviderArchitectureGatekeeper|QuotaProviderList|MockProviderInjector|AccountIdentityComputer|SyncCoordinator|CloudOperationDeadline`：257 项通过；
  - `CostUsageStoreTests`：77 项通过，其中固定了全部已发布 fork 缓存哈希必须重建；
  - `CodexAccountScopedRefreshTests`：153 项通过。
- lint 全部步骤通过：
  - 分片计时套件在高负载下偶发失败，已单独重跑，`Scripts/` 未改动；
  - 解析器版本审计通过；
  - fork README guard 通过；
  - i18n 四语言完整。

## 真实数据：Codex 成本扫描

对象是本机 9.5G 的 Codex 会话日志只读快照，用最终版本的 release harness 扫描，覆盖 2026-08-30 到 10-07 共 39 天。工具和输出在 `BuildScratch/CodexBar/costdiag`。

| 场景 | 未知或缺口的天 | 与全新扫描是否一致 |
|---|---|---|
| 全新扫描 | 0 | — |
| 从 0.70.0.1 缓存升级 | 0 | 逐天完全一致 |
| 从 0.72.0.1 写坏的缓存升级 | 0 | 逐天完全一致 |

- 最终版本在全部 39 天的 token 和成本，与上游 v0.73.0 全新扫描完全一致。
- 上游 0.73 自己从 fork 0.70 缓存升级时，仍有 35/39 天带未定价请求。fork 的缓存重建解决了这个问题。
- 同期合计：0.70 为 $5,660，最终版本为 $8,369。差额主要来自 09-03 至 09-15，0.70 少算了 resume 后的用量，例如 09-05 从 $101 变为 $542。
- 与按原始 ledger 去重估算的 token 对照：35 天里 32 天偏差小于 0.1%；09-03、09-22、09-23 分别偏差 3.0%、7.7%、1.5%，与上游 0.73 的结果逐值相同，属于上游统计口径。

## iOS

- 完整单测：1001 项通过（同步分支合入 PR #184 之后）。
- 新增测试覆盖：
  - Langdock：配色、额度提醒追加、四语言详情本地化；
  - 空条目不盖掉另一台 Mac 的数据，无身份时被吸收；
  - 只有成本的 provider 在多台 Mac 上不会误报；
  - 不报错的说明是中性提示。

## 兼容（2 Mac × 2 iPhone）

- 冻结 wire 检查：对 `v0.72.0.1-mobile.2.6.0` 跑 16 mask、64 次 wire 读取、32 个新旧 consumer 合并进程，全部 PASS（`BuildScratch/CodexBar/v073-frozen.log`）。
- 没有实体四设备环境，全部记为 substituted。
- old 指 Mac 0.72.0.1 或 0.70.0.1、iPhone 2.6.0 (236) 或 2.5.0；new 指 Mac 0.73.0.1、iPhone 2.6.0 (237)。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | Notes |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测；old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据 |
| 2 | old | old | old | new | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测；old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据 |
| 3 | old | old | new | old | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测；old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据 |
| 4 | old | old | new | new | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测 |
| 5 | old | new | old | old | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测；old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据；new Mac 的 Langdock 在 old iPhone 上按未知 provider 通用卡显示 |
| 6 | old | new | old | new | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测；old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据；new Mac 的 Langdock 在 old iPhone 上按未知 provider 通用卡显示 |
| 7 | old | new | new | old | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测；old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据；new Mac 的 Langdock 在 old iPhone 上按未知 provider 通用卡显示 |
| 8 | old | new | new | new | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测 |
| 9 | new | old | old | old | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测；old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据；new Mac 的 Langdock 在 old iPhone 上按未知 provider 通用卡显示 |
| 10 | new | old | old | new | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测；old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据；new Mac 的 Langdock 在 old iPhone 上按未知 provider 通用卡显示 |
| 11 | new | old | new | old | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测；old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据；new Mac 的 Langdock 在 old iPhone 上按未知 provider 通用卡显示 |
| 12 | new | old | new | new | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old Mac 仍可能发出未知成本或空 Claude 条目；new iPhone 保留已知金额并把空条目视为非观测 |
| 13 | new | new | old | old | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据；new Mac 的 Langdock 在 old iPhone 上按未知 provider 通用卡显示 |
| 14 | new | new | old | new | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据；new Mac 的 Langdock 在 old iPhone 上按未知 provider 通用卡显示 |
| 15 | new | new | new | old | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | old iPhone 按旧规则：未知可能覆盖已知、空条目可能盖掉另一台 Mac 的数据；new Mac 的 Langdock 在 old iPhone 上按未知 provider 通用卡显示 |
| 16 | new | new | new | new | substituted | 冻结 wire 16 mask PASS；iOS/Mac 单测 | 新版组合，全部修复生效 |

残余风险：
- old iPhone 在 old Mac 的未知成本下仍会丢失已知金额，需要两端都升级。
- new Mac 首次启动会全量重建 Codex 缓存，有 CPU 和 IO 开销；推送重试会兜住期间的超时。
- Gate 结论：16 个组合全部列出，均为 substituted，无 fail。
