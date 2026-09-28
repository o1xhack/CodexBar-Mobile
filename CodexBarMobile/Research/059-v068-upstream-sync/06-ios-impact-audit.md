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
- `QuotaProviderList` 是 quota warning subscription / notification 的静态 append-only 列表，影响 zone/subscription ID。不能重排或改名。只有 Mac 真正可发 transition 且同意新增 zone 时才追加；schema audit 将按仓库文档判断是否触发单独 deploy 授权。
- `Localizable.xcstrings` 的新固定文本需要 en、zh-Hans、zh-Hant、ja 四项均为 `translated`。release notes 应只新建 2.3.0 block，不改写 2.2.0 审核材料。
- CloudKit 使用现有 record type / zones / fields 时无需 Production schema deploy；若 quota push 新增 zone 或订阅，先按照 `docs/cloudkit-deploy-audit.md` 审计并记 `DEPLOY_REQUIRED` 或 `NO_DEPLOY`，未获 deploy 授权则不执行 Production 操作。

## 初步判断

上游 0.67–0.68 没有要求为 iOS 创建一套 Mac credential provider。绝大部分 provider 额度、金额、details 可走现有 generic payload。最可能需要实际修改的是 provider 可见 tint / fixed details localization，以及可通知 provider 的 append-only list；任何新 wire 字段必须由真实 merged snapshot 缺口证明，不能仅为上游 Mac 代码结构重构而加 schema。
