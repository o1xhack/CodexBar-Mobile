# 正式交付与 Final CI 修复

状态：`done`。授权的合并、Mac 公开、iOS 送审已执行，最终交付与当前外部审核边界见 [08-public-release.md](08-public-release.md)。下文按执行时间保留失败、修复和阶段性待办，不表示仍未发布。

## 已执行与来源

PR225已按当前head33cc5607b的clean review、0threads和FastChecks通过后merge为03f4e96f1493b61b067fbe4e2c2c8eb692222ab4。Mac1826/iOS353输入与18ebb/a36原产物逐项相等。当前ASC已公开3.2.0，Mac companion保持3.2.0正确。Mac未tag/public，iOS未上传/创建3.3版本。

合并后Final CI40925158735按merge SHA checkout执行；Linuxdesktop40925167440通过，lint通过。Mac分片5/6、2/6在fresh编译失败：StatusItemController+UserPlugins.swift:414复杂fingerprint表达式type-check超时，未进入测试。CI使用Xcode26.3/Swift6.2.4；本机Xcode27/Swift6.4已通过的结果不能替代此工具链验收。原日志保留BuildScratch/CodexBar/Release082-20261029/ci-job-*.log。

## 修复方案（执行前）

从已合并mobile-dev创建fix/v082-release-compiler。仅把fingerprint中的可选错误/旧快照消息提为显式String局部值，八个字段改为显式[String]，再与原reset数组按原顺序拼接；不改变任何字段、分隔符、默认值或持久化行为。用既有UserPluginQuotaPresentationTests、UserPluginRefreshTests覆盖标题、reset、错误捕获年龄、语言与恢复后的fingerprint；本地build/lint后独立review、PR当前head review，合并并确认新Final CI。

因Mac shipping source变化，重建同一0.82.0.1/Sparkle175.1.3.2.0候选、签名公证并替换固定draftID427366941的ZIP/dSYM；不增加用户版本，不复用旧Mac包冒充review修复。iOS源与3.3.0(261)导出包不变，五bundle Distribution/Production、UUID与原Archive一致；source和compiled图标均已验，Apple服务端图标待上传后核。

公开前正式body移除旧no-tag/placeholder/review-in-progress描述，绑定最终reviewed merge与实际artifact source。所有三步骤后续证据保留本目录、PR评论与SSD；CloudKit NO_DEPLOY不变，16组合仍是substituted，不改写实体PASS。

## 本地复测与夹具兼容

首轮测试/build未启动：新SSD tmp目录尚未创建；补齐后测试22项/2suite通过（测试5.164s，fresh编译562.14s），swift build通过（1.57s）。首次完整lint在签名重试夹具失败，原因是TMPDIR尾斜线导致mktemp路径包含双斜线，而Path(expected)规范化后与原字符串比较不等，真实两次签名参数未改变。规范化TMPDIR后该合同通过；同时将夹具断言改为Path等价比较，原first/retry所有参数逐字一致断言保留，并分别使用带/不带尾斜线验证，避免默认macOS临时路径写法造成假失败。

完整lint还要求条件赋值使用if expression；按仓库formatter改为显式String的if expression，仍隔离于显式[String]字段数组。将对最终写法重跑相同两suite及完整lint；旧结果不冒充最终冻结输入通过。

## 最终本地 gate（冻结前）

最终源码使用formatter要求的显式String if-expression，签名夹具以Path比较实际目标，原raw参数完整相等断言不变。compiler-fix-tests-3.log：22tests/2suites通过（fresh增量编译17.25s，测试5.235s）；compiler-fix-build-3.log：swift build通过（1.17s）。compiler-fix-lint-4.log完整lint通过，SwiftLint3211文件0违规，四语533source keys、parser/hash、CI/fork政策及所有脚本合同通过；无新parser变更。签名合同另以TMPDIR带/不带末尾斜线分别通过，每轮16个entitlement/profile cases以及timestamp retry参数保留检查。

独立本地review对最终if-expression、八字段及reset拼接、六种error/snapshot状态和路径夹具补审均0findings；source报告保留SSD independent-release-compiler-source-review.json，最终提交将再次核对diff与证据再push。Mac重签公证与固定draft附件更新、当前head PR review及新FinalCI尚待完成；iOS353输入和已导出分发包仍不变。

## macOS 26 原生侧栏测试坐标审计（执行前）

PR227合并后的Final CI40931175535已通过Swift6.2.4完整build-tests（validated source3802170c，1676.25s）及shards4/5；shard1在SettingsSidebarSizingTests的fresh retry仍失败：outer split subview328而预期320；divider设300后geometry绑定292而预期300，折叠恢复仍292。最小宽度用sidebar.viewController.view.frame.width检验200则通过。其他矩阵仍在运行，不能把已通过的编译或分片当完整CI成功。

从mobile-dev3802170c新建fix/v082-sidebar-compatibility后调研。生产modifier记录content geometry并用相同width设native column ideal；测试则把outer split pane/divider坐标当内容width，macOS26原生外层包含8点chrome，本机macOS27表现不同。拟改测试以真正sidebar viewController内容frame检查saved/restored width，拖动时按实际outer/content差值换算divider坐标，保持300目标、折叠恢复、min/max/canCollapse等严格断言，不硬编码8、不增加容差、不跳过系统版本。独立审查若发现产品缺陷则改修产品；不以test-only为既定结论。

若最终仅测试与Research变化，1826 Mac/353 iOS发布输入保持逐项相等，可继续保留eca Mac签名公证包和a36 iOS Archive；新merge/tag及完整CI证据须更新。iOS3.3版本已创建AFTER_APPROVAL，四语whatsNew已apply并远端diff为0，261上传2bb3773f已committed/PROCESSING；尚未App Review提交，Mac仍draft无tag/live/feed。

## 侧栏测试修复最终本地 gate

独立诊断支持test-only坐标修复：取真实sidebar controller内容frame，divider按outer.maxX+(300-content.width)换算，不假定origin或系统chrome大小；initial内容320+binding320，拖后内容300+binding300，新窗口内容300+binding300，展开后内容300+binding300，折叠期间binding300，200/min/max/canCollapse原覆盖完整保留。生产代码未改，无硬编码8、容差、skip或OS分支；真正macOS26运行结果仍是发布门禁。

本机macOS27.0.1/Xcode27.1/Swift6.4：首轮2tests/1suite PASS（fresh build503.97s/test1.081s）；强化后的最终写法2tests/1suite PASS（build104.14s/test0.972s）。完整lint exit0，3211文件0违规，四语533keys、parser与所有脚本/fork/CI合同通过；合成超时fixture的预期warning不算真实进程超时。evidence/sidebar-compatibility-local-gates.json记录最终测试文件及日志hash。Mac1826/iOS353实际发布输入再次逐项等价，不重打同一实包；独立review0findings后提交当前head PR审查。

iOS261已由Apple处理为VALID/APP_STORE_ELIGIBLE，绑定3.3版本b0ab6af8-64dd-45a4-bef3-03f14051a471，buildID2bb3773f-28d9-4320-9dc5-94fea868add2；AFTER_APPROVAL已fresh回读，四语商店metadata远端等价、Apple CDN实际图标已目视核对。绑定后asc validate为0blockers；6条ASO建议是既有subtitle/keyword字段，未扩展本轮范围；公开3.2商店页已验证AppPrivacy发布。尚未AppReview提交/公开；正式送审仍在Maclive后。CloudKit NO_DEPLOY与16组合substituted限制不变。

## 最终门禁与正式交付

PR #227/#228 均经本地独立审查、GitHub 当前 head clean、Fast Checks 和零线程门禁合并。Final CI 40940572500 六个 Mac 分片、Swift 6.2.4 兼容构建和 aggregate 全部通过；macOS 26 原生侧栏严格断言通过。Mac 于 20:52:57Z 公开，签名 appcast 与匿名下载验签通过。iOS 3.3.0 (261) 于 20:55:36Z 提交审核，回读 WAITING_FOR_REVIEW / AFTER_APPROVAL；尚未代表 Apple 批准或公开。最终 source / hash / schema 审计与兼容限制见 [08](08-public-release.md)。
