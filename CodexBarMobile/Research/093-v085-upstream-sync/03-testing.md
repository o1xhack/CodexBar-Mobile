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
- Mac 候选已完成双架构签名、公证和本机分发检查。全量测试复跑、GitHub 草稿和远端评审仍各自等待核验。
- 上游 v0.85.0 的 [CI](https://github.com/steipete/CodexBar/actions/runs/44919945104) 通过。[Tag 发布流程](https://github.com/steipete/CodexBar/actions/runs/44925305336) 中构建与 assemble 通过，后续 publish 在发布已可见后因 GitHub CLI 参数过长退出。此差异应保留在发布证据链里。

### 当前证据

- 最终 iOS shipping 输入在 `289116106` 冻结。27.2 iPhone 18 Pro 的全量测试通过，包括 1303 个 Swift Testing 用例、75 个 XCTest 执行（1 个跳过），覆盖 WidgetSnapshotBuilder 与 Widget 渲染矩阵。
- iOS 26.5 iPhone SE 通过 Usage 选择、旋转、Cost 分享草稿和取消、Summary 返回保留筛选两条用户路径。本轮没有改变 iOS 的最低部署版本。
- 候选 3.6.0 (264) 使用 Apple Development 签名，主 App、Push Extension、Widget Extension 均为 CloudKit Production；Widget Options 仅 App Group。Archive 未上传。真实源码、四 bundle 哈希与 Archive ZIP SHA256 见 [签名归档证据](evidence/ios-candidate-archive-verified.json)。
- 严格 SwiftLint 扫描 3,337 个文件，0 违规。CI 和 README guard、四语言、Mac 打包 WebKit 冒烟脚本单测通过。Mac 独立多账号筛选通过 137 和 11 个 Swift Testing 用例，两项 XCTest 执行含 1 个 opt-in 跳过。Claude 路径去重和 Codex 延迟确认测试修正均在全量运行中通过；该次运行在四个新 provider 的 mock 守卫处停止，固定成本历史例外后已启动全量复跑。
- iPad mini 26.5 与 Duo 1 当前姿态复测中，Cost 页面、分享面板、取消及 Summary 详情往返保留筛选均通过。最初 Summary 模块重排序失败独立保留。Duo 外屏竖屏重排序复跑通过。最初测试把从 y=82 起的第一行排除在起点为 y=90 的手势区之外，修订后实际落点约 y=91。重排序立即生效，关闭重开后仍在首位，详情及账号往返通过。旧失败、复跑 `xcresult` 摘要均保留。正在验证外屏横向与旋转交互。其他会话的 17e 保持运行。

- iPhone 18 Pro 27.2 的 SpringBoard 小组件安装和「今日费用」用例各通过 1 项。截图确认系统编辑面板及重新打开后的模式设置。在 iPhone SE 26.5 安装同一测试产品的 App 和 Widget 并核对四个二进制后，主屏实际显示合成数据 `$19.42` 与 `822.0 K tokens`。截图 SHA256 为 `a5e678eac7474ed68c1bd119727550f95dad9f80182215a050d5916025429b38`。保留 iPhone 18 Pro 首次主屏尚为占位的截图。两个用例的 `xcresult` 摘要和原始附件存于项目 `CodexBarMobile/build/upstream-v085/qa`。

## Mac 安装包

- `0.85.0.1`、Sparkle `178.1.3.5.0`。构建启动时生产源码为 `6ace40c0f93e58fff6f9e63b7009c2310dae1cf8`，打包后的 `CodexGitCommit` 为 `7c14b3c1e`。两者之间仅有测试变更，后续至本地复审的发行输入也没有变化。
- arm64 与 x86_64 的 App/dSYM UUID 均匹配。Developer ID 签名完整，主 App 的 CloudKit entitlement 为 Production。Apple 公证接受、stapler 校验、系统分发检查及独立启动通过。
- 安装包 SHA256 `a354e0db149b1e54947b9c0b9bb424fca8cce2830925f693e3c433655557dc8f`。dSYM SHA256 `a93d50975656711d4c547f798d22343087e38dc455433a207a6b2b9db7cc528c`。安装包、符号包和已签名 iOS Archive 副本均保存在项目 `CodexBarMobile/build/upstream-v085`。
