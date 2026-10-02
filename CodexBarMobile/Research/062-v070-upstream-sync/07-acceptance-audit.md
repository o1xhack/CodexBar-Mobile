# Goal 逐项验收与剩余 gate

Status: `in-progress`
Date: 2026-10-02
Product source checkpoint: `55fdc080dc5b228d811e34a3969ed49b5a6fec95`; all 192 production inputs match frozen `status-slots-r16-inputs.json`. Subsequent acceptance-summary corrections are documentation only.

本表保持完整 Goal 范围。证据均位于 StudioSSD BuildScratch/CodexBar/upstream-v070 或本 Research；local、离屏、替代矩阵、实体和远端 gate 分别记录。

| Goal 项 | 当前证据 | 判定与剩余工作 |
|---|---|---|
| 1 调研范围/issue/设计 | 00/01/06、两 release JSON、commit 清单；#166；v0.68→v0.69+v0.70 单 train | r18已只读回读：唯一open upstream-sync为#166，最新稳定v0.70.0；正式发布前再次核对 |
| 2 从 mobile-dev 建新分支 | 基线322865d30，upstream-sync/v0.70.0-mobile.2.4.0；独立worktree | 已完成；原 checkout 变动保留 |
| 3 Mac 完整同步与 fork 保留 | 上游 merge、Mac全回归 mac-full-r5 1520 selections/137 groups exit0，lint-r12，02实现记录 | 本地完成；远端 Final CI未执行 |
| 4 Mac→iOS数据准备 | Shared optional blocking/modelsUsed；真实old/new wire+merger+cache；CloudConstants/schema audit | 已实现；Production/APNs实际同步未验证 |
| 5 单版本/version | version.env 0.70.0.1/161.1/2.3.0；五iOS targets 2.4.0(227) | 已配置；正式签名来源再核对 |
| 6 Mac构建/回归/CloudKit/draft | mac-full-r5、unsigned universal/dSYM预检、NO_DEPLOY静态审计 | draft/签名/公证/Gatekeeper/资产回读未完成 |
| 7 iOS功能/notes/本地化/测试 | 02/05/06/09、CHANGELOG、单2.4 release block；r7完整916tests/1012runs零失败，r16 focused51/66零失败；标准Widget6方法、真实App四语言quota UI、生产四模式两样式/0–4槽/双实例/四尺寸、四语言配置资源与实际界面见03逐轮范围 | 生产SiriKit四槽修复已实现，非默认配置可消费；r17繁体medium六组固定等待/滚动/同不同ID/Home与outside退出对照均通过，配置截图读回及Home内容经人工核对；保留r15/r16偶发无法载入的未知原因风险，不宣称根因已修复。人工VoiceOver及实体同步仍未验证 |
| 8 16 old/new兼容组合 | 03全16行substituted；冻结wire64 reads/32 merges；frozen-ios-cache-r4 32stores/96processes exit0 | 替代验证完成，未等同实体2Mac×2iPhone、CloudKit/APNs或真实UI |
| 9 循环review/零阻塞 | 本地exact9974283e2及四槽迁移/翻译/默认值新增diff review clean；产品检查点55fdc080d已提交，本地exact-head审查无新源码阻塞；验收摘要文档修正单独记录 | GitHub PR/CR尚未创建；local不能代替remote exact-head review |
| 10 证据/链接/状态 | Research保持in-progress，各artifact source/hash/log证明 | PR/draft链接不存在，不虚构；后续实际结果再回写 |

## 新发现的 Widget 渲染前置条件

RELEASE-CHECKLIST第26行：触及 mode/color style 或 WidgetKit rendering 时必须跑 CodexBarWidgetRenderMatrixTests 与真实 SpringBoard gate。ProviderColorPalette虽放在app Models，却被 CodexBarWidgetShared/WidgetActivityView.swift:111 和 CodexBarWidgetView.swift:992调用；本轮品牌颜色改变会影响Colorful Widget。因此本轮适用，不能以Widget布局文件未改判为不适用。

已有313项包含WidgetSnapshotBuilder，只证明数据构建。本轮另运行原始Widget矩阵：5/6方法通过，附件方法因独立runner activities禁用失败；仅将附件保存改为PNG后6/6方法通过、220次离屏渲染、12截图已查看。证据为ios-widget-tests-r1/r2，完整边界见03-testing。后续after-auth-r1原始Widget六方法标准Xcode XCTest全部通过并生成12附件，替代证据保留作历史。真实SpringBoard仍须打开编辑面板、核对选项、切换mode并截图；离屏矩阵不等同真实Home Screen。

## UI 与进程状态

历史等待授权的旧PID均已退出，用户已报告处理密码提示。新的生产`CodexBarStatusWidgetV2`采用SiriKit四个独立optional provider槽，旧kind保留重加提示；实际模式/样式、槽序/去重、清空、双实例与四尺寸证据见03及09，不能继续把早期默认overview失败描述为当前状态。r16补明确空槽默认方法，默认查询1003在新捕获日志中消失，但繁体同ID空选重选/滚动/outside退出仍出现系统面板“無法載入”。不同ID Claude通过Home退出实际timeline及桌面42%正确。r17已完成六组固定停留时间/滚动的对照，正常退出、重开及已查看的槽值/Home内容均通过；实际停留46.26–47.91s，脚本自动检查退出与重开，槽值及Home为截图审阅。正常退出也产生interrupted/Invalidation日志，不能单独用这些消息证明崩溃、handler超时或保存失败。早期失败原因仍未知，不宣称r16默认方法修复了根因；完整配置会话日志与失败记录保留。

r7完整单元与r16相关回归均为标准Xcode终态通过。r7/r10/r16有不同冻结来源：r10仅两项中文文案修复；r16仅options默认值补全，不把旧UI证据倒推为r16全部复跑。实体2Mac×2iPhone、CloudKit/APNs、人工VoiceOver仍保持未验证边界。

## 远端与发布顺序

iOS全部适用本地gate → 获准push/PR → current-head CR清洁/全thread resolved/PR Fast Checks → review gate → 获准merge → 适用Final CI与正式来源核对 → 获准凭证/tag范围后Mac draft。不得执行live release或TF，不因自动Goal继续而扩大授权。#166只关联，不用closing keyword，draft阶段保持open。

## r17本地检查点

本地审查未发现新的可证实源码阻塞。各适用本地功能gate按03/09的分来源范围记录，不能扩展为所有family×mode×style×language均在r16实际复跑。专用iOS26已恢复原AppleLanguages=zh-Hans-US,en-US及AppleLocale=zh-Hans_US，主动重启后的sim-use基线已重置，SpringBoard读回正常简中。未重置全局Simulator、未操作其他项目设备。最终Git来源检查点及exact-head本地review另行记录；远端与发布gate仍未执行。

## r18补充核验

安全Mac多账号专项128 tests/12 suites终态通过；r7标准xcresult中7个iOS多账号/双zone suites共65 case节点Passed，含DualZoneReader10项。当前CI policy/fork README guard和fork changelog HTML提取通过。具体命令、来源及范围见03的r18段。产品及文档检查点本地review clean；尚无push/PR授权和远端PR，后续用户明确授权后才执行remote handoff，Mac draft仍按既定顺序等待。
