# 上游影响与 CloudKit Production 审计

状态：in-progress

| 上游改动 | Mac、Shared 与 iOS 处理 |
|---|---|
| SiliconFlow 与 Tripo | 通用详情保留 SiliconFlow 的 CNY/USD 原币种、Tripo 的 available/reserved credit 文本。Shared 目录尾部追加，旧通知 zone 标识保持不变。iOS 使用通用详情和对应品牌色，mock 用真实卡片形状。 |
| Google Developer Program | 保留订阅额度状态、账号和授予日期。余额复用 `providerAmount` 的货币、数值和观察时间，未激活时只显示状态。账号跨设备身份未加入 Tier A，设备记录分别保留。 |
| TrustedRouter | 复用通用详情展示 key limit、remaining 与周期支出。保持真实 0 与无上限的区别。设备级 fallback 不合并缺乏跨设备证据的 key。 |
| Notion、MiMo、Helmcode、Synthetic、Ollama、Grok 额度 | 已有 providerID。Provider 输出的 quota windows、详情、状态进入现有映射，手机无需复制 Mac 账号登录与抓取路径。Grok 余额继续使用已有的零值清除逻辑。 |
| OpenAI API legacy credits | 有实际 balance 时发布现有 `providerAmount`，含 0；没有余额时保留未知状态，不用支出冒充余额。旧 iOS 已经可读该字段。 |
| DeepSeek、Amp、Cursor、AWS Bedrock、OpenCode Go 成本 | 继续通过已支持的成本快照与日桶同步。DeepSeek 使用其报告货币与周期；Bedrock 保留 UTC 日桶、完整性、观测时间与真实零值。Cursor 保留账号归属；OpenCode Go 的等候上限为 Mac 本地。 |
| Codex Fast/Ultrafast、Claude 新模型及成本缓存 | 保留 Fast/Ultrafast 定价的独立内部归类，现有 iOS 金额汇总消费重算结果。申请分组和会话列表属于 Mac/CLI 本地工具。合并 fork 价格来源、cache 迁移和已发布 0.83.0.1 predecessor；不重写旧设备的未上报历史。 |
| Claude/Pi 会话、项目与 Models 视图 | Mac/CLI 原生报告。iOS 以已同步的每日金额及模型汇总为数据源，当前没有会话/项目的逐条数据合同；不将项目路径或逐会话使用明细扩展到 CloudKit。 |
| Codex reset follow-up、Claude swap、Cursor、Kiro、TypeSafe、Antigravity、MiniMax、Muse、Mistral、Alibaba、Devin | 同步前的 provider source、认证、CLI 或账号选择变化。Fork 保留当前账号关联及设备身份；新版可用快照按原路径更新，手机不读取认证状态及凭据。Alibaba 沿用分开的请求级 cookie 导流，同时共享连接池。 |
| Usage & Spend、菜单、设置、通知和 Widget | 上游 AppKit/SwiftUI 性能与 macOS Widget 运行行为在 Mac 原生入口生效。iOS Widget 使用独立 WidgetKit target；受影响的部分是共同消费的同步快照、provider 色彩和详情标签。 |
| Linux、CLI/server、浏览器、Keychain 及依赖 | 保持上游实现；无对应 iOS 用户入口。Mac PR 与发布 gates 检查平台配置，测试环境明确禁用真实凭据探测。 |

## CloudKit

对比公开发行 `v0.83.0.1-mobile.3.3.0` 与候选。Shared `CloudConstants.swift`、`UsageSnapshot.swift` 和 `Scripts/cloudkit` 无变更；未增加 record type、字段、索引、查询或编码版本。新增 provider 通知注册运行时 private zones 使用现有 `QuotaTransition`。现有 `providerAmount` 和详情位于现有 payload 内。代码审计结论为 **NO_DEPLOY**。不对 Production 执行 schema 发布或真实账号数据写入。

## Fork 合并保护

合并提交保留 fork README 字节一致，后续独立文档提交仅采用 MiMo 认证说明、四个新 provider 的官方来源、对应 provider 数及图片版本。CI 策略、Appcast、fork 签名发布入口保留，上游 post-tag 的三个 release/开发提交不在冻结范围内。Claude PTY fixture 的 CRLF 属于精确输入数据，diff 检查单独排除了该用例数据文件。
