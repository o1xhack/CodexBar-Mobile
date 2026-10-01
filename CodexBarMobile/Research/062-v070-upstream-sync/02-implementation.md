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
