# 本轮验证

状态：done（本地门禁与允许的替代验证完成；远端审查单独记录于PR）。

## 环境

Xcode27.2(27B52)，macOS/iOS SDK27.2；StudioSSD挂载/UUID/逻辑入口及所有scratch路径已核对。真实provider/浏览器Cookie/Keychain探测未运行。Mac测试隔离HOME、CFFIXED_USER_HOME、Codex/session路径，禁止Keychain UI。

## 本地门禁

- Mac `swift build --jobs 6` 和最终universal签名构建均通过；严格lint 3239 Swift文件零违规，四语言/parser版本/hash/CI/README等guards通过。最初worktree缺gitignored本机profile时门禁主动停止，复制主仓库现有profile后完整签名、公证、staple、分发策略与隔离启动smoke通过。
- Python cleanup 工具最终103项（1项平台skip）通过；测试保留3秒grace、5秒drain上限，只补强本任务owned child的重复SIGKILL，未弱化身份校验。
- Mac全量最终1869 selections / 89 groups通过，exit0；89组首轮全部通过，0失败/0timeout/0重试，修复后source a6ab1035b总耗时562.1秒。首轮68组通过、1组失败后停止；架构检查准确发现新增OpenDesign在三个现有精确指纹中的变化，分别记录合成fixture、非Tier-A身份分组、device-scoped key的理由与引用，未修改scanner或放宽规则。
- 独立multi-account focused命令通过：AccountIdentity/MultiAccount/DualZoneReader筛选覆盖137+11个Swift Testing用例及相关XCTest；1个需显式截图目录的opt-in截图用例skip。HOME/CFFIXED_USER_HOME隔离到本轮scratch，禁Keychain UI。
- iOS前次普通17e单元门禁通过：1300 Swift Testing / 87 suites，75 XCTest（1 skip）；xcresult汇总1374 passed / 1 skipped。首次pixel inspection失败完整重跑已通过；旧的quota suffix断言和实际DST bug分别修正。
- CWL DST：固定LA时区，覆盖2026-10-31/11-01/11-02和365天区间；GMT formatter使用相同GMT calendar，避免重复/遗漏日期。新增三日成本总计保持正确。
- fork parser迁移：明确旧revision12、13→14均须bounded重解析；以独立Codex home校验行、快照、checkpoint及fork baseline与clean scan一致，不能复用12→13的旧捷径。相关104 tests / 7 suites通过。
- iOS最终重建Release Archive来源 `c5227b588a71a23dacd123bd2e2d3f9df6b3d782`，全部353个shipping输入与当前版本一致；四角色版本3.5.0(263)，Apple Development签名。主App/Push/Widget均Production；WidgetOptions为AppGroup-only。没有IPA导出或上传。
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

## Mac候选打包

最终source a6ab1035b56be911e64479feb3c90696ded4edcb，双架构arm64/x86_64，App/CLI/Watchdog/Widget的Mach-O minimum均14.0；Developer ID Application签名、hardened runtime、App CloudKit Production与App/CLI/Widget实际runtime App Group一致。App/dSYM UUID双架构匹配，资源与隔离CLI/App smoke通过。Sparkle对实际ZIP的Ed25519签名同时用工具及包内SUPublicEDKey验证。GitHub draft两个uploaded asset的digest/size均与本地一致。完整结果见evidence/mac-artifacts-verified.json、mac-draft-verified.json和04；没有live provider测试或公开发布。

追加远端P1的修复、6方法/13执行专项与重新跑完的1869 selections/89 groups见05；新Mac包重新签名、公证、staple与验证，替换相同draft的两个附件，旧c8f仅保留superseded历史副本。该P1时Shared wire/merger以及全部353个iOS shipping输入未变化；后续P2改变App/Widget文字分发，重建与新验证见06，旧Duo/SpringBoard证据保留其实际来源而非新二进制实测，不声称其覆盖真实CloudKit保存回执；该回执由新增原始CKRecord回归覆盖。

最终P2后全量iOS门禁重新通过：1375 passed / 1 skipped / 0 failed（1301 Swift Testing /87 suites，75 XCTest含skip）；新Summary为evidence/ios-unit-label-fix-summary.json，验证记录ios-label-fix-validation.json，Archive来源与ZIP已替换为c5227b588。详见06。
