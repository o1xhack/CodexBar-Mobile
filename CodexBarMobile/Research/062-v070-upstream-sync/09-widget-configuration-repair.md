# 主 Widget 配置参数恢复修复

状态：in-progress（原型验证；生产实现尚未完成）

## 问题与证据

真实 SpringBoard 保存非默认 mode，但 AppIntentTimelineProvider 收到 overview/mono/空 providers。标准 Xcode Simulator 权限已恢复 timeline；纯 enum whole-bundle 原型仍失败。显式 CaseIterable、固定 allCases/supportedValues 均不能恢复用户选择。详情及 source/artifact/evidence manifests 见 03-testing.md。不能用编译通过、离屏 ImageRenderer 或系统编辑值替代实际 timeline/Home 验收。

Research/058-ios-220-widget-redesign.md 的实际历史记录表明 Token Activity 曾有相同保存/接收不一致，SiriKit IntentConfiguration 路径能完成实际 source 切换，但沿用旧 kind 时序列化不兼容。因此不能直接将主 Widget 的配置类型换掉而保持原 kind，也不能仅复制固定三项 source 的实现。

## 选择的验证方向

先在独立无账号诊断项目验证 SiriKit 全配置原型，再接入生产；目标是恢复全部现有能力，不改变 CloudKit wire/schema、选择含义或数据来源。Apple 的[可配置 Widget 指南](https://developer-rno.apple.com/cn/documentation/widgetkit/making-a-configurable-widget/)定义了 IntentTimelineProvider 与为动态选项提供数据的 Intents extension；原型必须实证这条路径可用，文档说明不能替代验收。

| 现有能力 | 迁移必须保留 |
| --- | --- |
| mode | overview、providerFocus、todayCost、syncHealth 四项，unknown 映射 overview |
| colorStyle | mono、colorful，unknown 映射 mono |
| providers | 0–4 个动态 provider，空选择维持自动选择；每项稳定 provider ID 与展示名称；保留选择顺序与去重；已删除 ID 保持 unavailable |
| 数据 | 继续现有 WidgetProviderCatalogue 与 snapshot builder，禁止账号探测/云端读取充当模拟证据 |
| 尺寸 | small、medium、large、extraLarge，保持当前布局与选择行为 |
| 多实例 | 两个并置 Widget 可独立选择 mode/style/providers，禁止全局 defaults 替代每实例配置 |
| 本地化 | App、Widget、动态选项 extension 的 intent resources 四语言完整 |

## 拟定接入边界

新增 SiriKit status intent 定义与独立动态选项 extension，通过 INObject 的 identifier/display 承载 catalogue 数据；handler 仅读 App Group catalogue，不引入网络或共享 SwiftData migration。IntentDefinition 在包含 App、Widget 和 options extension 三 target 注册，使用 project.yml/xcodegen 生成项目。App Group 与签名配置只增加必要新 target，全部仍使用 Production CloudKit；没有原因添加 Development 环境。

把 framework intent 转换为现有 mode/style/provider 配置模型，再使用原 snapshot/render/selection；若需要拆出纯 value 配置，必须更新原单元/离屏测试而不是复制生产逻辑。并发接口与异步 timeline 的生命周期需要 review，不能启动脱离 completion 的无约束工作。

选择新的 status widget kind，保留旧 kind 的迁移策略需在原型结果后具体确定；不改 Token Activity V2 kinds。旧配置不能无证据静默迁移或表示已恢复；四语言 release notes 合并到现有 2.4.0 entry，说明经实际验证的重新添加步骤。旧包摆放→新包覆盖→编辑→移除/重新添加→新实例配置全过程需保留截图与日志，移除只针对诊断自有 fixture，不能删除其他设备数据。

## 必须完成的验证

1. 原型实际 SpringBoard 四模式、两样式、动态选项 0/1/4 项，实际 provider 参数和 Home 同时正确；不能只看 serializedParameters。
2. 两个并置实例配置不同，切换其中一个不得污染另一个。
3. provider 顺序、重复/超过四项边界、未知/已删除 ID 和空 catalogue 的单元测试；使用临时可注入文件与虚构数据。
4. 新旧 kind 升级行为、四语言实际编辑面板、四尺寸外观与现有 quota/UI/原 Widget tests 回归。
5. 新 target 本地构建与 signing/Production/App Group 审计；来源源码、实际 artifact hash 和测试证据保持一致。
6. 完成后 exact-current-head 本地 review；push/PR、GitHub CR、merge 和 Mac draft 继续遵循现有授权与发布顺序，不能用原型通过宣告 release 完成。

## 仍未完成

独立 SiriKit 全配置原型、生产修复、新旧配置迁移验证以及真实主 Widget Home 参数验收。仍有安全可执行工作，Goal 保持 active。
