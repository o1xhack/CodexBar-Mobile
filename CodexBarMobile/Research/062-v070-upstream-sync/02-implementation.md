# 实现记录

Status: `in-progress`

## 合并冲突决策（2026-10-01）

- 24 个冲突逐 hunk 检查。README 保留 mobile-dev 字节内容；上游仅更新 social token 与 quota burndown 说明，待功能最终完成后再有意适配说明。appcast 保留现有 fork published feed，不接受上游 binary/feed。
- CI 保留 fork post-merge / manual triggers、path gates 和 upstream-release reuse，主动移植 Xcode 26.3 app/CLI/tests compatibility job，绑定实际 merge SHA 并加入 aggregate result gate。Linux 保留 fork no-parallel，先 source 新 security test_environment。CI policy/path/README guards 通过。
- Widget snapshot 同时保留 fork account publication source/revision/generation/authoritative-provider metadata 与 upstream per-provider invalidation 集合，移除已被上游替代的全 snapshot preservable bool。
- Grok 保留 fork Gregorian calendar/dayKey、采用上游排除 future-day 的 lookbackEnd 和 package dayKey 可见性；不退回用户非 Gregorian calendar。
- provider colors 接受 upstream hex 初始化（本轮上游已验证 Xcode 26.3）；CostUsageStore 合并双方 predecessor hashes；parser hash 初次工具生成 4dcbc89a71e137b5，fork parserLogicVersion 随本轮 semantic merge 提升至18后最终生成 11b5eaedd0f337a7，不手填。
- Plugin parity 保留 fork 5 秒 scheduler margin，适配 upstream 新 beforeHTTPAttempt 参数签名。
- Mac version 为 0.70.0.1 / 161.1 / Mobile 2.3.0；iOS 2.4.0 (227) 尚待实现。Changelog 保留上游两版本完整记录与旧 fork release 历史。

上游 SSH tag 验证在本机因未配置 gpg.ssh.allowedSignersFile 未能完成；不声称本地 tag signature 验证通过。Release API 已确认发布事实。

## 第一次独立 review 与验证

初次review确认Grok窄窗口丢生产者时区，已修复并补跨日测试；第二次review建议窄窗口重建rolling period/label，已采用，待最新树复测。Partial-history初始疑点经生产构造审计撤回为阻塞，现已统一historyIsFullyScanned映射作为兼容改进。Claude captured reset和Kimi blocking仍是iOS实现必修项。

Mac初次swift build --build-tests通过，326.65秒；随后定向41 tests/6 suites通过（含Grok、partial wire、widget、burndown、Kimi、Claude resets）。在parser version18/缓存predecessor、窄窗口period细化后，已启动完整测试，尚未获得终态，不能用初次41通过声明最终树通过。

Lint遇到上游env scrub fixture与fork重复test discovery的不兼容：fixture只识别无参数test list，改为支持--skip-build。10 harness测试通过。默认Python3.9缺waitid，重跑使用Homebrew3.14。第三次lint已通过此前harness，停在social image content hash：upstream图片已变而README按fork要求保持旧字节；merge后将以单独有意README适配更新token和burndown说明，禁止仅为过gate机械替换README/hash。

## 合并后 README 有意适配

Merge commit13d7101ef的README与mobile-dev字节相同，SHA256 1bc04267c61dca67c2f8a258386a1ea8c84be659bed1b8d9661b61e3d54a5add。合并完成后单独审计v0.68..v0.70 README只有social image token和新增quota burndown说明；本次有意移植这两项，fork iOS/App Store/Mac下载入口和身份内容保留，更新guard hash与这项文档变化一起审查。未移植上游整份README。

本地独立README review通过：核对merge commit README与mobile-dev SHA256一致，后续diff与上游两项事实完全一致，fork身份/App Store/Mac Releases入口保留，guard新hash 56b7ebcf36aed3ee70c7429f1e38ae3e92356889ab47c87e828bb4120c04f730。只读review不代表remote CR。

## 后续发布路径

Scripts/release.sh已支持DRAFT_NO_TAG_PUSH=1：GitHub draft先用mobile-dev作为placeholder target，在notes明确local source commit；不会创建/推送tag，publish前需授权并retarget reviewed source。该路径符合本Goal禁止push/tag publish边界。签名脚本需要Developer ID、ASC与Sparkle凭证；尚未读取或使用这些凭证。实际签名公证前按Goal询问凭证使用授权。现有draft清理步骤有删除行为，执行前必须先列出现有同tag draft，存在时不能自动删除。

## Mac→iOS 桥接补齐

新增optional SyncBlockingQuota/SyncRateWindow.blockingQuota，native Kimi映射同一组effective rateWindows与legacy windows；保留raw usage/reset/regen供新iOS解释。同步算法使用snapshot.updatedAt，不用手机当前时间伪造恢复；upstream历史输入未改变。Claude native generic details过滤live reset row，保留其它rows/chart和插件任意label。研究、定向测试已补，尚未取得最终构建/测试终态，iOS消费实现与旧缓存过滤仍待下一阶段。

初次完整测试因新增桥接实现使旧binary不再对应最新树，exit130主动停止；将重建后使用repo默认12 selections/group完成最终Mac gate。

Grok模型观察补齐：SyncDailyPoint新增optional modelsUsed，native、plugin、Mistral三个生产daily mapper均转发entry.modelsUsed；token-only模型不伪造cost breakdown。独立只读审查确认所有生产路径覆盖、reporting-period复用和新旧optional解码兼容，新增wire roundtrip/旧JSON断言。

lint-r6.log全树exit0：portable/JS/SwiftFormat/SwiftLint/i18n/parser-version均通过；随后modelsUsed细化的三份文件定向SwiftLint零违规。桥接r1因Core内部makeSection在app不可见失败，改为过滤已经映射的SyncProviderDetailSection；r2构建和11 tests/4 suites通过，之后集成与models测试扩展仍待最新r4。

## 最新 Mac 验收 checkpoint

2026-10-01 `mac-full-r5.log`终态exit0，1520 selections /137组全部首轮成功、无重试/timeout；运行源码checkpoint `bc26b3512`，后续HEAD至`07080d7d2`只改Research，Sources/Tests/Shared/Package/WidgetExtension/version.env输入diff为空。最新lint-r9通过；独立组合review `07080d7d2` clean（未发现代码阻塞）。先前三轮失败均在03记录，已逐项修正并在本轮完整运行通过。

Mac universal Release compiler与dSYM/minOS预检、iOS现有consumer基线编译/定向153tests通过，均有03证据。Mac签名、公证、Production packaged entitlements、真实ZIP/dSYM资产和tagless draft仍未执行，凭据使用需Goal要求的用户确认。iOS2.4.0功能/版本/说明/最终测试与本轮16矩阵仍未完成。

## iOS consumer 实施 checkpoint（未完成验收）

iOS 已实现真实 capturedAt 的额度趋势、Kimi monthly blocking 原始消耗说明及过期等待状态、native Claude 旧库存过滤、观察模型名贯穿多 Mac merger/TokenActivity/本地 ledger、16 个上游品牌色浅深色适配和 Antigravity 分组周期标签。所有 target 开发版本为 2.4.0 (227)，CHANGELOG 与同版本单一 in-app notes 已补四语言；没有上传或声明发行。

历史合并不再平均同小时百分比，保留真实采样和下降段；在 duration 选择前拒绝未来/非有限观察。单客户端历史图限制 gap 展开到最近 90 点，避免极端时间生成巨大数组。独立 review 修复 secondary/tertiary lane 映射、cost 日历边界时钟误用、亮色白底对比和 hyphen alias。

最新 review 又发现 publication metadata 在 SwiftData cold start 丢失，会使同 capture 的赢家在重启前后改变；已补 DeviceRecord optional publication JSON，正在补反向 writer clocks 的 disk reopen 测试。DailyCostPoint optional modelsUsedData 的 nil-field backfill 已测，但不等同于旧 schema 迁移；现增加冻结 pre-v0.70 entity 的真正磁盘升级测试，结果待验证。

用户更正顺序：先完成 iOS 与本地验证，再走 PR/CR，之后考虑 Mac draft。远端 push/merge 仍没有明确授权；不执行这些操作。
