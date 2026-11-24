# 候选测试记录

状态：in-progress

- Xcode 27.2 (27B52)，StudioSSD 已核实 UUID、可写与项目和 scratch 的实际路径。
- 本地测试隔离外部 provider 凭据和账号数据。没有运行 live provider probe。
- 离线矩阵使用已发布 fork 与候选的 Shared/merge 源码分别编译，执行 64 次独立 reader 解码与 32 次双 writer 合并。未具备两台 Mac 与两台 iPhone 的独立旧/新实机组合，故以下记录为替代证据。未验证生产 CloudKit 网络、APNs、前后台收敛或 SwiftData 迁移，实机有残余风险。

| 组合 | Mac A | Mac B | iPhone A | iPhone B | 结果 | 验证 |
|---:|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 2 | old | old | old | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 3 | old | old | new | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 4 | old | old | new | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 5 | old | new | old | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 6 | old | new | old | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 7 | old | new | new | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 8 | old | new | new | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 9 | new | old | old | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 10 | new | old | old | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 11 | new | old | new | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 12 | new | old | new | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 13 | new | new | old | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 14 | new | new | old | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 15 | new | new | new | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 16 | new | new | new | new | substituted | 双 writer 分别解码并按两种顺序合并 |

## 已完成与复测中的验证

- iOS 单元前一轮在明确设置 en-US 的 27.2 iPhone 18 Pro 上通过，1301 个 Swift Testing 用例和 75 个 XCTest 执行（其中 1 个跳过）。最初未固定区域时费用断言将 `US$` 与 `$` 比较失败；修正地区并区分新品牌色与历史 v0.70 色表后复测。新增 Notion 和 Google 本地化及跨日成本分项测试后，最终候选另有一轮测试。
- Duo 1 的 Cost 页面、分享入口、报告和取消操作通过。首次 Summary 配额模块原生重排序用例未将模块移动到第一项并失败。Device Hub 的 AppleEvent 在多次调用中超时，尚未取得当前候选的原生折展矩阵。保留 `Duo-Current.xcresult` 与日志供诊断。
- Mac 初始候选编译后完成了后续源码修复，当前正在执行最终测试。全量 Gate、Mac 签名草稿和远端审查需各自取证。
- 上游 v0.85.0 的 [CI](https://github.com/steipete/CodexBar/actions/runs/44919945104) 通过。[Tag 发布流程](https://github.com/steipete/CodexBar/actions/runs/44925305336) 中构建与 assemble 通过，后续 publish 在发布已可见后因 GitHub CLI 参数过长退出。此差异应保留在发布证据链里。
