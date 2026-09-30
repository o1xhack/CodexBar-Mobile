# iOS 数据与展示影响审计

Status: `ready`（静态基线审计；最终结论在 implementation 后更新）

## 已核实的共享通路

1. Mac `Sources/CodexBar/Sync/SyncCoordinator.swift` 生成 `ProviderUsageSnapshot` 并写入既有 `DeviceProviderSnapshot.payload`。
2. Shared `ProviderUsageSnapshot` 使用字符串 `providerID` / `providerName`，包含 `rateWindows`、`providerAmount`、`budget`、`costSummary`、账户 identity 及 generic `details`。
3. `SyncProviderDetailSection` 支持 row、secondary value、chart；Mac `SyncCoordinator.mapDetails` 可映射 `ProviderDetailSection`；iOS `ProviderDetailsView` / `ProviderUsageView` 按数据动态显示窗口和 details。
4. `ProviderAccountGroup` 按 `providerID` 聚类，不要求新 provider 有静态 Codable enum case。SwiftData snapshot 唯一键也保留原 provider ID。
5. `CloudConstants.providerPayloadVersion` 当前为 1；新加 optional payload key 不需要 CloudKit schema 字段，也不应触发全量 rewrite。

## 需要逐项用 merged code 验证

| Release 数据项 | 当前通用承载路径 | iOS 检查 / 候选工作 |
|---|---|---|
| xKiro / Raycast / Aixy | provider ID + generic windows / amount / details | 卡片、图标 tint、reset/amount/partial 状态；评估 quota transition eligibility 与新增 subscription zone |
| LiteLLM model activity | generic `details` row/chart | raw model 名保留原文；固定 label 完成四语；不把无 cost model activity 算 spend |
| Claude Admin workspace breakdown | existing Claude provider + details | preserve organization totals；新 row value 不暴露未经批准的 identity |
| Grok product usage share | existing Grok provider + details / existing Grok billing extension | 按 release payload 选择既有 field 或 generic details，不重复计入 quota total |
| Antigravity windows / history | `rateWindows`, token/cost summary | known/unknown、lower-bound、reset 与 optional history 能兼容 2.2.0 payload |
| Mistral Monthly Plan | named generic rate window | Monthly Plan 不覆盖 Included API；是否有 reset 用 existing fields 表示 |
| Muse team quota | selected-team provider windows / details | team 选择/ cookie 不进 payload；只显示 Mac 实际选定的 quota |
| Nous / Codex / Cursor history & spend | existing cost summary + daily points | cost coverage、lower bound、session privacy 与 all-history 请求结果不混淆 |

## UI / localization / CloudKit decisions

- `UsageCardView` 通过 `ProviderWindowLabel.localized` 展示 window；`ProviderDetailLocalization` 仅翻译可确认的固定语义，模型名、用户名、scope、动态金额保持原样。
- `ProviderColorPalette` 优先读 Mac 提供的安全 hex tint，并处理 Light/Dark contrast；新增 provider 要确认 ID 映射不会落入错误的 substring color。
- `QuotaProviderList` 是 quota warning subscription / notification 的静态 append-only 列表，影响 zone/subscription ID，不能重排或改名。每用户 private zone 和 subscription 实例属于运行时数据；只有新 record type、被查询/排序的新 field 或新 index 才触发 schema deploy。本轮沿用已部署的 transition type/fields/predicate，审计为 `NO_DEPLOY`。
- `Localizable.xcstrings` 的新固定文本需要 en、zh-Hans、zh-Hant、ja 四项均为 `translated`。release notes 应只新建 2.3.0 block，不改写 2.2.0 审核材料。
- CloudKit 使用现有 record type / fields / predicate 时，即使为用户私有数据库创建 zone 或 subscription 实例，也无需 Production schema deploy；本轮未读取或写入 Production。

## 初步判断

上游 0.67–0.68 没有要求为 iOS 创建一套 Mac credential provider。绝大部分 provider 额度、金额、details 可走现有 generic payload。最可能需要实际修改的是 provider 可见 tint / fixed details localization，以及可通知 provider 的 append-only list；任何新 wire 字段必须由真实 merged snapshot 缺口证明，不能仅为上游 Mac 代码结构重构而加 schema。

## 实施后核实：Aixy identity

- 上游插件 `Sources/CodexBarCore/Resources/Plugins/aixy.ts` 从响应中的 `root.key.id` 取服务器 key ID，并以 `ProviderIdentitySnapshot.accountID` 暴露；同步路径中的 first-party `.aixy` 不经过 non-first-party plugin mapper。
- Aixy 用量按 API key 计量，故 Mac 发布 `aixy:key:<opaque-key-id>`，相同 key 可跨 Mac 合并，不同 key 即使属于同一 project 也保持分开。ID 保留大小写并做 NFC、trim、percent-encoding 与长度限制；不得用 workspace 标签、secret 或 email 推断身份。缺少 key ID 时不输出 Aixy identity，iOS 沿用 per-device legacy bucket。
- 此方案只增加已有 `accountIdentities` optional 数组中的字符串；iOS 已对 identity 做 opaque string equality，不新增 payload key、CloudKit 字段或 schema。对应测试覆盖大小写敏感 ID、缺失 ID 与 mapper 保留 key identity。

## 原币种费用与美元统计边界

Mistral API projection 可以携带 EUR 等原币种；字段名 costUSD 是历史 wire 名称，并不证明金额已经换汇。Provider detail 与 daily chart 使用 currencyCode 保留原币种显示。Overview、Cost dashboard、CWL、分享卡片和 Widget 的美元统计只接受 USD；旧 payload 缺少 currencyCode 时沿用原有 USD 契约，显式未知币种不参与总额。同一 local account 的多 Mac summaries 若币种不同，返回没有金额的 unavailable envelope，避免 metadata 丢失后退回旧 ledger。已存在的非美元 ledger rows 在展示/model mix 阶段也被排除；没有破坏性数据库删除或伪造 FX 转换。

Mac 对非美元 rolling summary 也写入已有 reportingPeriodSummary 结构。Shared encoder 保留 modern 原币种历史，隐藏旧版 USD historical fields；Mistral session/Today 字段继续为空，不把最后一个 dated bucket 当 Today。没有新增 wire key 或 CloudKit schema。16 组合 gate 以 synthetic old-reader/source-level 替代验证；旧 Mac 已经写入的 EUR legacy payload 不会被新 Mac retroactively 改写，实体旧 iOS/Production/APNs 仍是未覆盖风险。

Round 13 补充：plugin producer 与普通 producer 共用 Shared encoder 的强制原币种边界。新增 payload 内 optional `nativeCurrencySession` 保存 native session amount/known metadata；不是新的 CKRecord schema field。现代 reader 恢复原币种 session，旧 reader 无法把它计为 USD；modern history fallback 在 serialization 边界生成，不再要求每个 producer 自行记住 envelope。
