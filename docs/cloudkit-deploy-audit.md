# CloudKit Production Deploy — 何时需要 deploy？

> 每次发版前先查这张表。从这次 Phase G release 起，**release checklist** 强制包含此审计。

## 背景：为什么这个老踩坑

iCloud CloudKit 有两个 environment：**Development** 跟 **Production**。fork app（Mac + iOS 都签 `com.apple.developer.icloud-container-environment = Production`）在生产环境读写。问题：

- 在 dev container 里加 record type / field / index → **不会自动同步到 prod**
- 必须显式去 CloudKit Dashboard → **Deploy Schema Changes to Production**
- 用户的 app 拿到新 schema 的 payload 但生产 container 没认识 → 错误或者数据黑洞

历史踩坑（来自项目 memory `CK Production schema deploy trap`）：indexes 不会自动 Dev→Prod，多次因为没 deploy 出问题。

## 什么情况**需要** deploy

如果你的 release 改了下面任何一个，**必须**上 CloudKit Dashboard 做 schema deploy：

| 改动类型 | 例子 | 必须 deploy？ |
|---------|------|--------------|
| 新增 CKRecord type | 新 record class | ✅ 必须 |
| 现有 record type 加新 field（**且参与查询/索引**） | 新字段被 NSPredicate 引用、被 sort key 用 | ✅ 必须 |
| 现有 record type 新加 queryable / sortable / searchable index | `addIndex` 调用 | ✅ 必须 |
| 新 CKRecordZone（用户私有数据库中的自定义 zone 实例） | 客户端调用 `saveRecordZone` / `CKModifyRecordZonesOperation` 创建 per-user zone | ❌ 不需要。zone 实例是运行时数据库数据，不是 Dashboard schema |
| 新 CKRecord type、被查询/排序的新 field，或新 index | 新 record class / NSPredicate / sort key / `addIndex` | ✅ 必须 |
| 新 CKQuerySubscription / CKRecordZoneSubscription（依赖**新** record type 或新 predicate field） | iOS 订阅尚未部署的 schema | ✅ 必须 |

## 什么情况**不需要** deploy

| 改动 | 为什么 |
|------|--------|
| 改 payload `Data` 字段内部（zlib JSON 里加新 optional key） | CloudKit 不解析 payload bytes — 对它而言是 opaque blob |
| 新增对现有 record type 的 per-user 自定义 zone / zone subscription | CloudKit private database 由 zone owner 创建运行时 zone；订阅仍使用已部署的 record type 和字段。见 [Apple `CKRecordZone` documentation](https://developer.apple.com/documentation/cloudkit/ckrecordzone) |
| 推**更多**现有 record type 的 record（per-account 多账号 fan-out） | record type 不变，只是数量增加 |
| Render 层改 / iOS UI 改 / 测试改 | 跟 CloudKit 完全无关 |
| 文档 / appcast / version.env / 本地化文案 | 跟 CloudKit 完全无关 |

## 审计方法（每次发版前跑）

```bash
# 1. 找到上一次 published release 的 tag
LAST_TAG=$(gh release list --repo o1xhack/CodexBar-Mobile --limit 10 --json tagName,isDraft | python3 -c 'import json,sys; tags=[r["tagName"] for r in json.load(sys.stdin) if not r["isDraft"]]; print(tags[0])')

# 2. CK schema keyword grep 看 diff
git diff $LAST_TAG..HEAD 2>&1 | grep -E "^\+.*(recordType|CKRecordZone\(|addIndex|querySchema|CKContainer|providerPayloadVersion|CKQuerySubscription|CKRecordZoneSubscription|encodingVersion)"

# 3. 看 Shared/iCloud/CloudConstants.swift 是否动了（schema 单一源头）
git diff $LAST_TAG..HEAD -- Shared/iCloud/CloudConstants.swift

# 4. 看 Shared/Models/UsageSnapshot.swift 是否加 NON-decodeIfPresent 字段
# (decodeIfPresent 是 optional → payload-internal, 不算 schema 改)
git diff $LAST_TAG..HEAD -- Shared/Models/UsageSnapshot.swift | grep -E "^\+.*public let|^-.*public let"
```

如果 step 2 + step 4 grep 都没输出 → **不需要 deploy**。如果有输出 → 看具体是什么改动，对照上面"需要 deploy"表格判断。

## 发现需要 deploy 怎么办

1. macOS → 开 CloudKit Dashboard → 选 `iCloud.com.o1xhack.codexbar` container → **Schema** tab
2. 切到 **Development** environment 看新加的 type / field / index
3. 点 **Deploy Schema Changes to Production** 按钮
4. 等 review + apply（通常几秒到几分钟）
5. 截图保存到 release notes（防 hooks 把"我以为我 deploy 了"当成 deploy 了）
6. 然后再 publish GitHub release

## 历史 Phase 审计存档

| Phase / Release | CK schema deploy 需要？ | 原因 |
|----------------|------------------------|------|
| v0.25.2-mobile.1.6.0 | ❌ 不需要 | 只加 push warning state，沿用 existing zone naming convention |
| v0.26.1-mobile.1.7.0 | ❌ 不需要 | Shared envelope 加 6 个 optional decodeIfPresent 字段，在 zlib payload 里 — CloudKit 看不见 |
| v0.26.2-mobile.1.7.0 (Phase G) | ❌ 不需要 | 100% consumer-side。Mac 推**更多** existing record type 的 records；iOS render 层分组。`CloudConstants.swift` 零改动 |
| v0.27.0-mobile.1.8.0 build 65.2 (superseded) | ❌ 不需要 | Shared envelope 加 10 个 `decodeIfPresent` optional 字段（5 v0.27 NEW provider + 5 existing-provider extension），全在 zlib payload blob 内部。 |
| v0.27.0-mobile.1.8.0 build 65.3 | ✅ **需要** | 给 `QuotaTransition` CKRecord 加了第 6 个字段 `accountEmail`（String，未索引）。CloudKit Production schema 默认不接受未声明字段写入；deploy 步骤：(1) Mac 端切到 Development env 触发一次 quota warning，Dev schema 自动加上字段；(2) Dashboard → Schema → Deploy Schema Changes to Production → 勾选 `accountEmail`；(3) 切回 Production env 测一次 warning，确认写入成功。**先 deploy 再 ship**，否则用户更新到 65.3 后所有 QuotaTransition 写入会被 Prod 拒绝，导致 push notification 完全失效。 |
| iOS 1.14.0 / issue #29 | ✅ **需要，已完成** | 新增 `DeviceLifecycleEvent` CKRecord type，写入 `DeviceProvidersZone`，字段为 `kind`、`primaryDeviceID`、`relatedDeviceIDs`、`confirmedAt`、`confirmedFromDeviceID`、可选 `note`。这是 iOS-only 功能，不需要 Mac release。2026-06-21 已通过 CloudKit Console deploy 到 Production；2026-06-23 复核：`xcrun cktool export-schema --team-id 3TUERHN53E --container-id iCloud.com.o1xhack.codexbar --environment production` 输出包含 `DeviceLifecycleEvent` 以及上述 6 个字段。 |
| v0.47.0.1-mobile.1.20.0 | ✅ **需要，已完成** | upstream fleet sync 新增 `CodexBarSync` zone 与 `AccountSnapshot`、`Device`、`Preferences`、`ProviderIntent`，并补齐 iOS account-linkage writer 使用的 `ProviderAccountLinkage`。2026-08-08 已经单独授权并 deploy；Production readback 最终确认 10 个 types：上述 5 个、既有 `DeviceProviderSnapshot` / `DeviceSnapshot` / `QuotaTransition` / `Users`，以及 `DeviceLifecycleEvent`。 |
| v0.49.2.1-mobile.1.21.0 | ❌ 不需要 | published v0.47 tag → candidate 的 `Shared/iCloud/CloudConstants.swift` 零 diff，`providerPayloadVersion` 保持 `1`；`details`、plugin branding、`usageKnown` 等新字段仅位于既有 `DeviceProviderSnapshot.payload` opaque blob。2026-08-11 Production export 仍为同一组 10 types，无新 type/field/index/zone/query/schema version。 |
| v0.54.0.1-mobile.1.22.0 | ❌ 不需要 | 最后published `v0.52.0.1-mobile.1.21.0` → candidate 的`CloudConstants.swift`无schema diff，`providerPayloadVersion=1`；provenance、coverage、token mix、metered cost与history coverage都是既有`DeviceProviderSnapshot.payload`内的optional JSON。2026-08-22 Production export仍为同一组10 types，无新type/field/index/zone/query/subscription。 |
| v0.56.0.1-mobile.1.23.0 | ❌ 不需要 | 最后published `v0.54.0.1-mobile.1.22.0` → candidate 的`CloudConstants.swift`无schema diff，`UsageSnapshot.swift`无新增非optional `public let`，`providerPayloadVersion=1`；Kiro、Cursor、Fireworks与Antigravity变化只进入既有`DeviceProviderSnapshot.payload` opaque JSON。2026-08-28 `cktool export-schema` Production回读仍为同一组10 types，无新type/field/index/zone/query/subscription。 |
| v0.58.0.1-mobile.1.23.0 candidate | ❌ 不需要（代码审计） | published v0.56.0.1-mobile.1.23.0 → candidate：CloudConstants 无 diff；amount/budget observedAt、daily requestCount/tokenCountIsKnown 均是既有 opaque payload 内的 optional JSON，未改 record type/field/index/query/subscription，providerPayloadVersion=1。本轮未调用 Production export 或 schema deploy。 |
| v0.68.0.1-mobile.2.3.0 | ❌ 不需要（代码审计） | published v0.66.0.1-mobile.2.1.0 → candidate：CloudConstants 与 providerPayloadVersion 无 schema 变化；新增 `reportingPeriodSummary` / `nativeCurrencySession` 位于既有 `DeviceProviderSnapshot.payload` optional JSON；quota warning 沿用已部署 `QuotaTransition` type、fields 与 predicate。private-zone / zone-subscription 实例是运行时数据。本轮未读取或写入 Production。 |

## v0.70.0.1 候选代码审计（2026-10-01，尚未发布）

对照最新published `v0.68.0.1-mobile.2.3.0`，`Shared/iCloud/CloudConstants.swift`无diff，`providerPayloadVersion=1`。新增`SyncRateWindow.blockingQuota`与`SyncDailyPoint.modelsUsed`是既有`DeviceProviderSnapshot.payload`中的optional JSON；没有新增record type、CloudKit field/index、query或subscription，也不增加private zone。因此当前候选代码判定`NO_DEPLOY`。Mac打包与iOSentitlements仍为Production。本轮没有调用Production schema export、deploy或实际数据库读写；iOS实现后的最终diff仍需复核，兼容矩阵不能由本结论代替。

## v0.72.0.1 候选代码审计（2026-10-06，尚未发布）

对照最新 published `v0.70.0.1-mobile.2.4.0`：`Shared/iCloud/CloudConstants.swift` 与 `Scripts/cloudkit/` 无 diff，`providerPayloadVersion=1`。新增 `SyncRateWindow.balanceDescription`、`SyncProviderDetailSection.Row.id/progress/usageValue` 均为既有 `DeviceProviderSnapshot.payload` 内的 optional JSON（nil 不编码）。`QuotaProviderList` 追加 `museai`、`workbuddy` 只增加运行时 private zone 与 zone subscription，沿用已部署的 `QuotaTransition` type/fields。上游 fleet `CloudSyncEngine` 移植（#4147/#4161）沿用已部署的 `CodexBarSync` zone 与 `ProviderIntent`/`Preferences`/`Device`/`AccountSnapshot` record types；上游 push 注册只在签名含 `com.apple.developer.aps-environment` 时触发，CKSyncEngine 自管 database subscription，fork 打包不含该 entitlement。判定 `NO_DEPLOY`。Mac 打包与 iOS entitlements 仍为 Production。本轮未调用 Production schema export、deploy 或实际数据库读写。

## v0.73.0.1 候选代码审计（2026-10-08，尚未发布）

对照最新 published `v0.72.0.1-mobile.2.6.0`（appcast 已于 10-07 撤回该版本，回到 0.70.0.1）：
- **schema 定义**：`Shared/iCloud/CloudConstants.swift` 与 `Scripts/cloudkit/` 无 diff，`providerPayloadVersion=1`。
- **新增类型**：`SyncProviderSourceReport`（含 `Failure.isError`、`absorbedAccountIdentities`），只作为 `ProviderUsageSnapshot.sourceReport` 存在于 iPhone 本地合并结果，Mac 从不设置，nil 时不编码，不进入 CloudKit。
- **`QuotaProviderList`**：追加 `langdock`，只增加运行时私有 zone 与 zone subscription，沿用已部署的 `QuotaTransition` type 与 fields。
- **推送 QoS**：Mac 推送改为 userInitiated，只是运行时属性。
- **Mac 说明文字**：Claude 额度不可用的说明复用既有 `statusMessage` 字段。

判定 `NO_DEPLOY`。Mac 打包与 iOS entitlements 仍为 Production。本轮没有调用 Production schema export、deploy，也没有读写实际数据库。

## 注意事项

- **`providerPayloadVersion` bump = 强制全量重写**。看到 commit 改它必须警惕：除了 CK deploy，还会触发用户首次启动新版后 CPU/网络 spike。Phase B 加 6 个 optional 字段时**故意不 bump** 就是为了避这个。
- **新增用户私有数据库 custom zone 不等于新增 schema**。Apple 文档规定客户端可通过 CloudKit API 为该用户私有数据库保存自定义 zone；Dashboard 的 schema deploy 不创建每个用户的 zone。检查代码是否新增了 record type、字段/index 或依赖新 schema 的 subscription，再判断是否 deploy。
- **零 schema change**只代表"不需要 deploy"，不代表"不会出问题"。Phase G 这种"推更多 record" 的改动可能让用户 iCloud 配额吃紧（如果 record 数量大涨）— 那是 quota 问题不是 schema 问题，但同样要测。
- 这份 doc 的对照表必须跟 `docs/versioning.md` 一起读。版本 bump + schema deploy 是两个独立维度的决策。
