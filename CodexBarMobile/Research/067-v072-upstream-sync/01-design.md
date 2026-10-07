# 合并与数据通道设计

Status: `ready`

## 合并规则

- 一次 `git merge v0.72.0`，保留 v0.70.0..v0.72.0 全部上游历史、provider、安全、性能和修复。
- 冲突逐 hunk 处理；fork 约束优先：README 保持 mobile-dev 字节（之后单独审计上游 README factual diff）；`appcast.xml`、`version.env` 保 fork；CI 保 fork 双层 trigger 与 6 shard（`docs/ci-policy.md`、`Scripts/check_ci_policy.sh`）；fork release 脚本不得被上游 wrapper 覆盖；CloudKit 容器保持 fork `CloudSyncConstants.containerIdentifier`。
- 上游与 fork 对同一问题各自修复时，优先采用上游实现（减少未来冲突），再补回 fork 独有语义：Spend Dashboard 同名项目分离、Claude 缓存测试隔离、子进程/任务超时测试 fixture。
- `CloudSyncEngine` 保留 fork 的全部修复（engine lease、revision gates、deletion recovery 等），并按上游 #4147/#4161 语义转为 `@MainActor` 单执行器：当前引擎守卫、removed-record `.unknownItem` 恢复、push 注册门控、apply generation 原子边界。

## Mac → iOS 数据通道

只在既有 opaque JSON payload 内增加 optional 字段，`decodeIfPresent`，nil 不编码，不提升 `providerPayloadVersion`，不新增 record type/field/index/subscription，不同步 credential/cookie/path/env。

1. `SyncProviderAmount` 复用：LithosAI（`limit <= 0` 的预付余额，period "Prepaid credits"）与 Grok（购买 credits 余额，0 也发布以清除旧值）。
2. `SyncProviderDetailSection.Row` 新增可选 `id`、`progress{used,total}`、`usageValue`：Mac `mapDetails` 原样转发并按 Shared 边界校验（非有限值/total≤0 丢弃该字段，不让整行解码失败）。旧 iOS 忽略未知键；新 iOS 读旧 payload 时字段为 nil。
3. `SyncRateWindow.balanceDescription`：Mac 按 descriptor `showsPrimaryBalanceDescription`/`showsSecondaryBalanceDescription` 发布已裁剪的描述；新 iOS 在有 reset 时间时也显示余额描述，旧 iOS 行为不变。
4. 新 provider ID（museai/lithosai/workbuddy）走既有 provider 列表与 per-provider runtime zone；QuotaTransition 订阅只追加有百分比窗口的 museai/workbuddy（tail 追加保持既有订阅 ID 稳定）。

## iOS 呈现

- Claude Cloud credits：按 `id == "claude-cloud-credits"` 识别；有 `usageValue`+`progress` 时本地化显示 “剩余 X / 共 Y”，进度条；`secondaryValue` 中 ISO 到期时间本地化；到期时间早于当前时间则显示“已过期”并隐藏进度（Mac 观测的到期时间是权威，不推断额度恢复）。无 `id` 的旧 payload 保持原文显示。
- 通用 detail 行有 `progress` 时显示细进度条（Muse top-up 等）。
- 余额描述与 reset 同显，避免与无 reset 时既有描述重复。

## CloudKit 判断（初判）

全部为 opaque JSON 内 optional 字段与运行时 zone，`CloudConstants`、record type、字段、索引、订阅不变 → 初判 `NO_DEPLOY`。最终在发版前按 `docs/cloudkit-deploy-audit.md` 对最后公开 tag `v0.70.0.1-mobile.2.4.0` 重跑并记录。

## 测试与完成门

- Mac：`swift build`、`Scripts/lint.sh lint`、完整 `Scripts/test.sh`（隔离分组）、多账号/多设备 filter、CloudSync/mapper/新 provider 定向测试、CI policy/README guard。
- iOS：xcodegen、Simulator build、完整单元测试、WidgetSnapshotBuilder（触及 provider 显示数据）、四语言 audit；颜色改动触及 widget 渲染则跑 render matrix。
- 同步兼容：本轮改 Shared payload → 触发 `docs/ios-sync-compatibility-testing.md` gate，16 组合逐格记录；实体硬件不可用时用冻结旧/新 Shared 源码独立读写替代验证并写明残余风险。
- Review：自查 + 独立 review agent 循环至 0 阻塞。
