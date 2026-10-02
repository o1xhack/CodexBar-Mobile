# Goal 逐项验收与剩余 gate

Status: `in-progress`
Date: 2026-10-01
Source checkpoint: `577ceb90aa1cb37e68e996ead44aa10fc41cc48e`

本表保持完整 Goal 范围。证据均位于 StudioSSD BuildScratch/CodexBar/upstream-v070 或本 Research；local、离屏、替代矩阵、实体和远端 gate 分别记录。

| Goal 项 | 当前证据 | 判定与剩余工作 |
|---|---|---|
| 1 调研范围/issue/设计 | 00/01/06、两 release JSON、commit 清单；#166；v0.68→v0.69+v0.70 单 train | 已记录；正式发布前回读 issue/release 当前状态 |
| 2 从 mobile-dev 建新分支 | 基线322865d30，upstream-sync/v0.70.0-mobile.2.4.0；独立worktree | 已完成；原 checkout 变动保留 |
| 3 Mac 完整同步与 fork 保留 | 上游 merge、Mac全回归 mac-full-r5 1520 selections/137 groups exit0，lint-r12，02实现记录 | 本地完成；远端 Final CI未执行 |
| 4 Mac→iOS数据准备 | Shared optional blocking/modelsUsed；真实old/new wire+merger+cache；CloudConstants/schema audit | 已实现；Production/APNs实际同步未验证 |
| 5 单版本/version | version.env 0.70.0.1/161.1/2.3.0；四iOS targets 2.4.0(227) | 已配置；正式签名来源再核对 |
| 6 Mac构建/回归/CloudKit/draft | mac-full-r5、unsigned universal/dSYM预检、NO_DEPLOY静态审计 | draft/签名/公证/Gatekeeper/资产回读未完成 |
| 7 iOS功能/notes/本地化/测试 | 02/05/06、CHANGELOG、单2.4 release block；原始313/15 iOS26.5 passed；32生产图表离屏图 | 实现与定向runtime通过；真实App UI与Widget gate未完成；iOS27复验仍live |
| 8 16 old/new兼容组合 | 03全16行substituted；冻结wire64 reads/32 merges；frozen-ios-cache-r4 32stores/96processes exit0 | 替代验证完成，未等同实体2Mac×2iPhone、CloudKit/APNs或真实UI |
| 9 循环review/零阻塞 | 本地 exact577ceb90a review clean | GitHub PR/CR尚未创建；local不能代替remote exact-head review |
| 10 证据/链接/状态 | Research保持in-progress，各artifact source/hash/log证明 | PR/draft链接不存在，不虚构；后续实际结果再回写 |

## 新发现的 Widget 渲染前置条件

RELEASE-CHECKLIST第26行：触及 mode/color style 或 WidgetKit rendering 时必须跑 CodexBarWidgetRenderMatrixTests 与真实 SpringBoard gate。ProviderColorPalette虽放在app Models，却被 CodexBarWidgetShared/WidgetActivityView.swift:111 和 CodexBarWidgetView.swift:992调用；本轮品牌颜色改变会影响Colorful Widget。因此本轮适用，不能以Widget布局文件未改判为不适用。

已有313项包含WidgetSnapshotBuilder，只证明数据构建。本轮另运行原始Widget矩阵：5/6方法通过，附件方法因独立runner activities禁用失败；仅将附件保存改为PNG后6/6方法通过、220次离屏渲染、12截图已查看。证据为ios-widget-tests-r1/r2，完整边界见03-testing。该替代证据不等同标准Xcode XCTest全部通过。真实SpringBoard仍须打开编辑面板、核对选项、切换mode并截图；离屏矩阵不等同真实Home Screen。

## UI 与进程状态

本次ps确认 xcodebuild 64477/70255/84611 和iOS27 UnitRunner 99312仍live；未见terminal，不因观察超时取消重启。sim-use preflight此前失败，标准XCTest等待debugger；不能绕过SecurityAgent或冒称App UI通过。用户自行处理主机debugger权限的既有问题仍待回复。

## 远端与发布顺序

iOS全部适用本地gate → 获准push/PR → current-head CR清洁/全thread resolved/PR Fast Checks → review gate → 获准merge → 适用Final CI与正式来源核对 → 获准凭证/tag范围后Mac draft。不得执行live release或TF，不因自动Goal继续而扩大授权。#166只关联，不用closing keyword，draft阶段保持open。
