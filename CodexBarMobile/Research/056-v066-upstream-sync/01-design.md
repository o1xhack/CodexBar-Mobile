# 单版本设计与验证方案

Status: `done`（本 Goal 已确认并实施方案）

## 合并策略

以 `v0.66.0` 为第二 parent 做本地 merge，保留上游完整功能、修复、性能与安全提交。冲突逐 hunk 审阅；fork 拥有 `README.md`、发布与签名、公证/appcast、CI fast/final policy、CloudKit Production、Mobile Shared 同步、版本规则、iOS 工程。`README.md` merge 后保持 fork 字节并独立检查上游 factual/security 变化。`appcast.xml` 不在 draft 阶段改 live feed。Mac-only UI/CLI/Linux 等仍完整留在 Mac 代码。

## Mac→iOS 数据通道

追踪 `UsageStore`/plugin typed usage → `SyncCoordinator`/`DeviceProviderSnapshot.payload` → Shared decode → iOS `SyncedUsageData`/卡片、CWL、widget。逐 provider 审核新余额、额度、rate windows、费用、tokens、时间、region、账户身份和 unknown 值。复用现有 optional `details`/`rateWindows` 时写出代码证据；必要时仅加向后兼容 optional 字段并测试新旧解码。禁止将 key/cookie 或私有路径写入 payload。Mac fleet sync 删除需确认不会误删 Mobile `DeviceProviderSnapshot`。

## 版本

候选 Mac `MARKETING_VERSION=0.66.0.1`、`BUILD_NUMBER=156.1`（上游 v0.66.0 为 156）。iOS 当前主线 `2.0.0 (211)`，本轮功能性新增候选 `2.1.0 (212)`；`MOBILE_VERSION=2.1.0`。候选 `sparkle:version=156.1.2.1.0`，本地 tag 名 `v0.66.0.1-mobile.2.1.0`。这只是单一候选版本；验证发布状态与 App Store build 冲突后再最终固定。`UPSTREAM_VERSION=v0.66.0`，`UPSTREAM_SYNC_DATE=2026-09-24`（release UTC 日期）。按 `docs/versioning.md` 顶部四段规则，旧决策树中三段示例不覆盖新规则。

## 验证与发布边界

Mac `swift build`、完整 lint、`swift test`、provider/parser/account/sync 回归，`Scripts/check_ci_policy.sh`；不运行会触发 Keychain prompt 的 live account probes。iOS simulator build、相关 unit/widget/本地化与数据展示验证。按 `docs/ios-sync-compatibility-testing.md` 列出 16 组合；真实 2 Mac × 2 iPhone 不可用时标记 `substituted`，附代码/fixture/模拟器证据与剩余风险。按 `docs/cloudkit-deploy-audit.md` 对最后 published fork tag 审计；若发现 Production schema deploy 需要，暂停确认。最终按阶段 review、修复、复测。只准备 Mac draft；GitHub draft/签名使用凭证前暂停确认，绝不执行 live finalize 或上传 TestFlight。
