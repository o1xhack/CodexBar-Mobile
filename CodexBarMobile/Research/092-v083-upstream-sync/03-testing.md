# 本轮验证

状态：in-progress；禁止把运行中的门禁写成通过。

## 环境

Xcode27.2(27B52)，macOS/iOS SDK27.2；StudioSSD挂载/UUID/逻辑入口及所有scratch路径已核对。真实provider/浏览器Cookie/Keychain探测未运行。Mac测试隔离HOME、CFFIXED_USER_HOME、Codex/session路径，禁止Keychain UI。

## 本地门禁

- Mac初次 `swift build --jobs 6` 通过；最终签名构建另记。
- Python cleanup 工具最终103项（1项平台skip）通过；测试保留3秒grace、5秒drain上限，只补强本任务owned child的重复SIGKILL，未弱化身份校验。
- Mac全量最终1869 selections / 89 groups通过，exit0；89组首轮全部通过，0失败/0timeout/0重试，总耗时775.2秒。首轮68组通过、1组失败后停止；架构检查准确发现新增OpenDesign在三个现有精确指纹中的变化，分别记录合成fixture、非Tier-A身份分组、device-scoped key的理由与引用，未修改scanner或放宽规则。
- 独立multi-account focused命令通过：AccountIdentity/MultiAccount/DualZoneReader筛选覆盖137+11个Swift Testing用例及相关XCTest；1个需显式截图目录的opt-in截图用例skip。HOME/CFFIXED_USER_HOME隔离到本轮scratch，禁Keychain UI。
- iOS最终普通17e单元门禁通过：1300 Swift Testing / 87 suites，75 XCTest（1 skip）；xcresult汇总1374 passed / 1 skipped。首次pixel inspection失败完整重跑已通过；旧的quota suffix断言和实际DST bug分别修正。
- CWL DST：固定LA时区，覆盖2026-10-31/11-01/11-02和365天区间；GMT formatter使用相同GMT calendar，避免重复/遗漏日期。新增三日成本总计保持正确。
- fork parser迁移：明确旧revision12、13→14均须bounded重解析；以独立Codex home校验行、快照、checkpoint及fork baseline与clean scan一致，不能复用12→13的旧捷径。相关104 tests / 7 suites通过。
- iOS本地Release Archive来源 `23ff6887da5ef996c47dcfc967d7b369e78b7cd7`，全部353个shipping输入与当前版本一致；四角色版本3.5.0(263)，Apple Development签名。主App/Push/Widget均Production；WidgetOptions为AppGroup-only。没有IPA导出或上传。
- Duo2本轮获得使用权；Duo1/SE27.2原有Booted会话未动。Duo2 bootstatus报告Data Migration Failed，但实际App与原生Device Hub姿态可操作，不能把bootstatus退出0当成功证据。一次仅针对共享非Persistent Duo2的重置未消除该系统警告，后续以实际viewport和XCTest结果判断。
- Duo实际native fold/unfold通过：inner 951×669 → outer466×678 → inner951×669；heatmap草稿、范围、账号选择保留，取消后创建新classic草稿成功。`duo-fold.xcresult`。
- Duo内屏横向三项通过：Cost/share controls、双pane独立滚动、Summary实际viewport/columns/filter/action；`duo-inner-landscape.xcresult`。
- Duo内屏竖向2项、外屏横向Summary 1项、外屏竖向2项通过；外屏横向Cost/share亦在首次外屏运行通过。首次外屏运行的Summary仅因仍处于678×466横向却选择portrait用例而失败，按真实姿态分别重跑通过，失败摘要保留。Duo共10个成功用例执行，另有1个错姿态断言失败及一次automation setup卡住后主动取消，不算通过。
- 普通小屏SE26.5和iPad mini26.5各3项通过：账号选择/旋转后草稿与取消、Cost/share控件可达、Summary筛选/详情/返回。当前最低验证runtime为26.5，未声称验证无安装的iOS17 runtime。
- UI测试使用合成preview/multi-account数据，无真实CloudKit或用户导出。Duo全屏原始附件同时保留两display；选取的6张PNG和来源/hash在evidence/duo-screenshot-manifest.json，保留XCUIScreen原始朝向（包含倒置竖向/固定display像素坐标），方向断言使用实际app/window/grid frame，不从PNG长宽猜测。
- WidgetSnapshotBuilder及完整WidgetRenderMatrix包含在最终iOS门禁中。共享ProviderColorPalette影响WidgetKit渲染，已补做真实SpringBoard native gate：放置status widget，系统编辑面板Overview→Today Cost，桌面实际显示$19.42 / 822.0K tokens，关闭重开读回Today Cost。6张原始截图/hash和已安装Debug二进制与最终测试产品一致证明见evidence/springboard-native-gate.json。XCTest初次setup被图库non-hittable StaticText阻止；第二次等待SpringBoard idle卡住后主动取消，均未标成自动通过；以实际native操作和重开回读完成该门禁。
- 本任务启动的17e、Duo2、SE26.5、iPad mini26.5均已关闭；未操作其他会话Booted设备或Persistent设备。

最终iOS log/xcresult及原始附件已复制到项目CodexBarMobile/build/upstream-v083/qa；摘要/hash和精选原图进入evidence，避免依赖BuildScratch长期保留。Mac最终全量log也已复制。

## 16组合兼容矩阵

本机无可独立调度的两Mac、两iPhone及授权测试账号环境；全部使用允许的离线替代路径。冻结最新公开Mac tag v0.82.0.1-mobile.3.2.0的Shared模型和真实ProviderSnapshotMerger，与当前版本各自编译为独立writer/reader进程。两Mac不同deviceID，两reader独立进程读取并双顺序合并。16组合共64次读取、32次consumer merge全部通过。原始失败为沿用旧Research中sourceRecorded不支持的断言，与本轮old reader实际已支持不符；修订断言后重跑全部通过，失败log保留Scratch/wire。

这验证序列化、optional元数据、provider注册、来源隔离和纯合并，不覆盖真实CloudKit记录写入、网络、APNs、SwiftData独立缓存收敛或物理设备。新OpenDesign真实producer key另有SyncCoordinatorV083Tests，不能以手工wire fixture代替producer测试。

| Case | Mac A | Mac B | iPhone A | iPhone B | 结果 | 证据 | 限制 |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 2 | old | old | old | new | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 3 | old | old | new | old | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 4 | old | old | new | new | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 5 | old | new | old | old | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 6 | old | new | old | new | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 7 | old | new | new | old | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 8 | old | new | new | new | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 9 | new | old | old | old | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 10 | new | old | old | new | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 11 | new | old | new | old | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 12 | new | old | new | new | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 13 | new | new | old | old | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 14 | new | new | old | new | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 15 | new | new | new | old | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |
| 16 | new | new | new | new | substituted | wire-matrix-wire.json | 无实体CloudKit/APNs/独立缓存收敛证明 |

源文件SHA清单、矩阵操作/结果在evidence/wire-source-manifest.json和wire-matrix-wire.*；测试工具在tools/。old/new为冻结版本角色，不是实机安装版本。
