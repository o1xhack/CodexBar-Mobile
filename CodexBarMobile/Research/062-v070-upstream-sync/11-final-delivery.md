# 最终 beta / Draft 交付验收

Status: `in-progress`
Date: 2026-10-03

## 审查与来源

PR168 clean 合并，Final CI 37076651555 success。PR169 的 Ready 后新增审查未通过却被错误批处理合并，已向用户同步；该问题及新增生命周期 race 由 PR170 修复。PR167/169 原发现已回复并 resolve，不能把早期 clean 倒推为后续 head clean。

PR170 最终审查 head `99e9c6622bda6d6264ff64d7c57ef58cbc85ac7f`：远端 Codex CR clean、0 unresolved，review gate 和 Fast Checks success 后，独立执行 match-head merge，来源 `afdb6a23095d37a15638cc10e981791726d9f1d0`。本次记录为文档跟进；发行物仍来自该已审查来源。

Final CI [37103373939](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/37103373939) 尚在运行；lint、macOS compatibility build 和部分测试 shard success。未来公开发布仍须全部适用 gate 通过。

## 测试边界

Mac 完整隔离回归 `Scripts/test.sh` 六 shard 全部 exit0，1520 selections，无重试/超时；各 shard 使用独立 scratch SwiftPM metadata，复用只读编译产物并 skip-build，避免共享 index 的锁串行化。直接整体测试的其他套件失败保留，没有把它宣称为通过。

iOS 完整单元 945 项（0 failed/skipped）；最终资源聚焦 27 项（0 failed/skipped）；真正的四语言 UI 用例 1 项（内部遍历 en/zh-Hans/zh-Hant/ja，0 failed/skipped）。旧不含类名的 UI selector 实际选中 0 项，不能作为 UI 证据。四语言 384 source keys 与 Mac locale/lint 均通过。

2 Mac × 2 iPhone 全 16 old/new 组合仍是 03 记录的替代 wire/merger/cache 验证，不能称实体 Production/APNs 时序或人工 VoiceOver 已验收。

## iOS 2.4.0 (230)

Archive 来源 afdb6a230 与审查源码/资源/版本一致，五 bundle 全部 2.4.0 (230)，CloudKit Production。archive ZIP SHA256 `7cf02ec87743aa16d64c7e617d2f3afa796564ab557e6988fb14cf66555b3bf0`。云端 upload 无持久导出 IPA，不虚构 IPA hash。

ASC build `3e1942ed-2a7b-4359-a78d-7eaef8385a5c`，VALID；Internal group `eb0df43e-af6b-42ad-a429-efe2f5478702` 包含 230，internal `IN_BETA_TESTING`。实体手机未由本次流程安装 230，TestFlight 可用不等同已装机。

ASC 2.4.0 version `fe49ae08-79b4-49c8-946a-92b2f625f8d6`，PREPARE_FOR_SUBMISSION / MANUAL，绑定 230；四语言 what's new 和 beta notes、继承截图 hash、原描述/关键词/链接/联系人回读一致。审核备注原有旧版本说明已更新为 2.4；独立审查发现 Settings 的 Setup Guide 没有 Demo 回调，已改为首次说明点 Done → Usage 等待同步页的 View Demo，并重新 apply/readback 确认。文案保存在 AppStoreMetadata/2.4.0/review_notes.txt。未提交 App Review 或外部 beta review。

图标三层验证：源码 opaque 1024 图标、archive 编译 120 图标、Apple 处理后的 152 iconAssetToken 在 Aside 可见一致。私有 provenance 和完整回读位于 SSD scratch：ios230-archive-source.json、asc-230-beta-and-version-final.json、asc-240-final-preparation.json。

## Mac Draft 与 Studio QA

最终 Draft/资产 hash/来源见 04。App 与 dSYM 的两个 UUID 对应：x86_64 `2F215C03-1301-3133-B051-494534114DDE`，arm64 `F2A321B8-3EF4-3323-8BA7-9AC973D443CB`。ZIP 解包签名、公证、stapler、Production 和 universal 架构复验通过。

Studio 最终安装 `/Applications/CodexBar.app`，0.70.0.1 / 161.1.2.4.0 / afdb6a230，已启动。安装前实际 UI 检查来自 ddbfe464 的本地 0.70：Mobile 布局有正确内边距；Mac Fleet 显示两台 Mac，手动刷新更新为“刚刚”；立即同步成功；用量与支出具名显示 Antigravity 本地历史不可用，Codex/Claude 对应历史日期存在。切换与滚动没有复现持续卡顿，主线程采样以 AppKit 消息等待为主；不宣称 FPS 基准或未开启的登录 provider 均正常。

最终包重启后暂因电脑控制工具无法绑定无窗口菜单栏 App，正在等待设置窗口重新打开，以补最终包的实际界面复查。之前 UI 证据不倒推为最终包实测。未操作用户手机的本地数据库，未将私人金额/截图写入 GitHub。

## 授权边界

已按用户明确授权完成 reviewed merge → iOS beta/ASC 准备 → Mac Draft。Mac Draft 保持非公开，appcast 未更新，#166 保持 open。App Review、Mac 正式发布、人工 VoiceOver 与实体全矩阵未完成；这些不能以当前 beta/Draft 结果替代。
