# 授权正式交付（2026-10-29）

状态：`done`（授权的 PR 合并、Mac 公开及 iOS 送审已执行，六平台 CLI 公开下载已验证；本收尾文档 PR 的最终审查/合并另以 PR 回执为准）。Apple 审核与 iOS 真正上架属于后续外部状态，不能把送审写成已公开。

## 授权、版本与源码

用户明确授权依次合并 PR #225、发布 Mac Release、创建 iOS 版本送审并审核后自动公开。必要的发布阻塞修复继续在独立任务分支完成；未在 mobile-dev 直接实现。

| 项目 | 实际结果 |
| --- | --- |
| PR #225 | 合并 `03f4e96f1493b61b067fbe4e2c2c8eb692222ab4` |
| Swift 6.2 编译修复 [#227](https://github.com/o1xhack/CodexBar-Mobile/pull/227) | 合并 `3802170c1c53d4e81a6fed50c2bd9fe214e3aca4` |
| macOS 26 侧栏测试坐标修复 [#228](https://github.com/o1xhack/CodexBar-Mobile/pull/228) | 合并 `c6cbe728b9161cac0f816071e270669efd1229c1` |
| Mac | `0.82.0.1` / BUILD `175.1` / MOBILE `3.2.0` / Sparkle `175.1.3.2.0` |
| 公开 tag | `v0.82.0.1-mobile.3.2.0` → `c6cbe728b9161cac0f816071e270669efd1229c1` |
| iOS | `3.3.0 (261)`，`WAITING_FOR_REVIEW`，`AFTER_APPROVAL` |

三项代码 PR 均完成独立本地审查、当前 head 的 GitHub Codex clean review、Fast Checks 和零 unresolved 线程门禁。Mac 实际签名源码 `eca34f3d38a1aef676c7c01290eb360e4833e9d9` 的 1826 项构建输入与最终 release 源码 c6c 逐项相等。PR #228 仅改测试和 Research，无须重新签名相同生产输入。

iOS Archive 来源 `a36c6b110da3d994c8bba6bbcfa777627efa42ff`，353 项输入与 PR #225 reviewed `33cc5607bf5897c4e77a31b130a08e3c1688a463`、合并 03f 及最终 release 输入逐项相等。后续修复未改变 iOS 输入；没有以较晚的 clean PR 替代旧 binary 的输入验证。

## CI 失败、修复与最终通过

原 Final CI `40925158735` 在 Xcode 26.3 / Swift 6.2.4 的 fresh 编译中，UserPlugin fingerprint 复杂表达式 type-check 超时。PR #227 拆出显式 String 错误提示和八项 String 字段，再按原顺序拼接 resets，语义不变。本地 22 tests / 2 suites、build、完整 lint 通过；签名夹具同时验证 TMPDIR 带/不带尾斜线的路径等价和原始重试参数。

后续 `40931175535` 的兼容构建通过，但 shard 1 的侧栏测试两次失败：外层 pane 328 对应内容 320，divider 300 对应内容 292。PR #228 使用真实 sidebar controller 内容 frame，按 `outer.maxX + (300 - content.width)` 换算拖动坐标，并严格检查 initial / drag / restore / collapse / expand 的内容和 binding。没有硬编码 8、增加容差、skip 或系统分支。最终本地 2 tests / 1 suite 通过（0.972s，build 104.14s），完整 lint 3211 文件零违规、四语 533 keys 通过。

最终 [Final CI 40940572500](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/40940572500) **六个 Mac 分片、Swift 6.2.4 兼容构建和 aggregate 全部成功**；六个分片首遍失败组均为 0。兼容日志明确 validated source c6c，build 1768.20s。真实 macOS 26.6.2 / Xcode 26.3 的侧栏两项测试通过（2.009s），严格断言实际执行。

旧 `40931175535` 的失败日志保留；确认新 run 覆盖相同六分片与兼容构建，且 380→c6 仅三个 test/docs 路径后，取消旧剩余重复分片释放 runner。cancelled 不算 PASS。原 03f 的三个 Linux CLI jobs 和 [Linux desktop 40925167440](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/40925167440) 成功保留；03f→c6 六个路径均为 Mac/test/docs，没有改变其生产输入。

## Mac 公开交付

[正式 Release](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.82.0.1-mobile.3.2.0)，固定 release ID `427366941`，公开时间 **2026-10-29T20:52:57Z**。仓库 appcast 由正式 finalize 流程发布为 commit `26fee94a1393661022c8b5e35dd69cec257b2e88`。Mac 签名时及公开前 ASC 当前已交付 companion 均为 3.2.0，故包/tag/Sparkle 保持 3.2.0；未把随后送审的 3.3.0 记成已交付。

公证 `2e24e778-7e51-42a7-bc82-ef87683f5446` Accepted，stapler、distribution policy、deep strict 签名和隔离启动通过。App / CLI / Watchdog / Widget 四角色均 arm64 + x86_64、min macOS 14、Developer ID Team 3TUERHN53E / hardened runtime。App 签名 Production profile 有效；CLI / Widget 为 AppGroup-only，实际 runtime group 与 signed group 一致。dSYM UUID：arm64 `769FBC5E-6892-3E84-A58B-4AC6800CB4A9`，x86_64 `5C9A5C14-16DB-3624-8E91-18B9A9143ABB`。

| 资产 | 字节数 | SHA256 |
| --- | --- | --- |
| `CodexBar-0.82.0.1-mobile.3.2.0.zip` | 92810579 | `7bd3eb40b2bbbe0c99816eb1211f762fc1932bb8d4acccedec0daaeff008c2c3` |
| `CodexBar-0.82.0.1-mobile.3.2.0.dSYM.zip` | 74087787 | `1d62ad2dfba238bc8a230e8617ab174a15d9b4dcb3fe57a2b8f7fd2e1add5589` |

2026-10-29T20:53:41Z 已匿名下载公开 ZIP，长度/hash 匹配；公开 raw appcast 的 URL、Sparkle version、short version、长度正确，并使用真实 signed App 的 SUPublicEDKey 验证 Ed25519 成功。`releases/latest` 指向同一 release。 tag push 的 Mac Release Verify `40952337377`、release 事件的 Mac Release Verify `40952939644` 均成功；同 tag/c6c 的 Release Linux desktop `40952939598` 也成功并附加双架构资产。

[CLI 工作流 40952939597](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/40952939597) 已成功，六个 build 的编译、smoke、package、upload 步骤均成功，source/tag 精确为 c6c / v0.82.0.1-mobile.3.2.0；fork 按条件跳过 upstream-only Homebrew tap。2026-10-29T21:10:42Z 已匿名下载 macOS arm64/x86_64、Linux aarch64/x86_64、musl aarch64/x86_64 六个 tarball 及 checksum，逐项 SHA256/长度/文件类型/CPU 一致；包内 VERSION、常规 CodexBarCLI、codexbar→CodexBarCLI 符号链接、资源与 notices 均验证，musl 静态链接通过。真实运行时 smoke 由同源码工作流执行，下载校验没有运行缺失资源的裸 binary。`Scripts/check-release-assets.sh v0.82.0.1-mobile.3.2.0` 的 App/dSYM 及四个主平台 CLI/checksum 合同检查也通过；另外两个 musl 目标由上述六平台核验覆盖。原用户 `error.log` / `work/` 未纳入、清理或覆盖，global git excludes 未改。

## iOS 送审与自动公开

App `6760216772`，version ID `b0ab6af8-64dd-45a4-bef3-03f14051a471`，精确 build/upload ID `2bb3773f-28d9-4320-9dc5-94fea868add2`。Distribution IPA 12370265 bytes，SHA256 `8eb326cd2016016508f1ed52d8f5b6d0c7af8a401f27de0fa4b7272c72c726e3`。五个 bundles 的版本、签名与 UUID 均和 Archive 核对；App / Push / Widgets 为 Production，WidgetOptions 和 Sync framework 按各自角色检查。

四语 What's New 来自已 reviewed 的 release notes catalog，其余 canonical 字段沿用 3.2；apply 后 fresh 远端 diff 为 0。Apple 处理结果 VALID / APP_STORE_ELIGIBLE，非豁免加密为 false，精确绑定 261。source / compiled / Apple CDN 三层图标均实际查看正确。带 IPA 的 asc validate 为零 blockers；六条既有 subtitle / keyword ASO 建议未扩大本轮范围。已确认现有公开 App Privacy 信息。

送审命令 `asc review submit --app 6760216772 --version-id b0ab6af8-64dd-45a4-bef3-03f14051a471 --build-id 2bb3773f-28d9-4320-9dc5-94fea868add2 --confirm --output json` 成功。实际 submission **`833ec952-a59f-4e74-8323-08066aa2cd6b`**，提交时间 **2026-10-29T20:55:36.54Z**；20:56:37Z 回读 version 和 submission 均为 **WAITING_FOR_REVIEW**，releaseType **AFTER_APPROVAL**，无 phased release 或 future earliestReleaseDate。

Apple 批准后自动公开；该回执不是已批准或已上架。没有执行 TestFlight 测试组分发命令，送审前 build 的 betaGroups 为空。[公开商店链接](https://apps.apple.com/us/app/codexbar-usage-of-ai/id6760216772) 展示届时实际可用版本。

## CloudKit、兼容与未覆盖风险

2026-10-29 对 published v0.79.0.1-mobile.3.1.0→c6c 的最终代码审计为 **NO_DEPLOY**。Shared/iCloud、Scripts/cloudkit、CloudSyncEngine、SyncModels 无 diff，providerPayloadVersion=1。新增 quotaLimit / quotaUnit / expectedUsed / expiresAt 都在现有 optional JSON payload 内，sourceRecorded 为既有 costProvenance 的容错 raw value。QuotaProviderList 仅 append 四个 provider ID，使用已部署 QuotaTransition 类型的运行时 zone/subscription；SyncCoordinator 仅改 JSON 映射，没有新增 CKRecord type / field / index / query / predicate。

未执行 Production schema export、deploy 或数据库读写。真实签名 Mac/iOS 的 Production entitlements 单独验证；代码审计不能证明服务器 schema 或实体同步已实测。

[03-testing.md](03-testing.md) 的 16 组合仍全部 **substituted**（64 reads / 32 冻结 consumer merges），未实测实体双 Mac × 双 iPhone 的 CloudKit / APNs / cache 收敛，也未下载商店旧 binary 核对精确旧版输入。Duo 原生内外屏横竖、partial 和跨姿态操作、普通 iPhone/iPad、严格 SpringBoard Widget、四语渲染证据继续有效。原 Mac 合并覆盖 1845 selections / 16194 method identifiers，以及 123 条件 XCTest skip / Swift Testing opt-in body 限制均保留，不能表述为单一最终 binary 全量 body 通过。没有运行未授权的真实 provider / Keychain / cookie 探测。

## 收尾文档验证

收尾分支 `review/v082-release-closeout` 从 appcast commit 26fee 创建，仅更新 Research 和 schema 审计记录，不改变版本、App 源码、资源、构建配置或已上传的 binary。自查覆盖完整 diff、新增文件、相对链接、JSON 交付边界、原始证据 SHA256 和凭据泄漏模式；`git diff --check`、`Scripts/check_ci_policy.sh`、`Scripts/check_fork_readme.sh` 已通过。文档不触发重打相同 App 或新的设备矩阵。

首次 portable lint 在文档链接合同失败：docs 内新增相对链接跨出 checker 的允许根目录。已改为仓库 Research 的 GitHub 绝对链接，未放宽 checker 或影响 App 输入；失败日志保留 `closeout-portable-lint.log`。修复后的同一完整 gate 重跑结果如下。

`PARSER_LINT_BASE=origin/mobile-dev TMPDIR=/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/Release082-20261029/tmp bash Scripts/lint.sh lint-linux` 修复后完整重跑 exit 0：3211 Swift 文件零违规、文档链接 443 项、格式、脚本合同、CI/fork guards、parser 审计均通过（`closeout-portable-lint-2.log`）。冻结提交的独立本地审查、GitHub 当前 head review 和 Fast Checks 以本次收尾 PR 的记录为准，不能把代码 PR 的结果冒充文档 PR 已通过。

## Issue 与执行状态

[#221](https://github.com/o1xhack/CodexBar-Mobile/issues/221#issuecomment-6508190661) / [#222](https://github.com/o1xhack/CodexBar-Mobile/issues/222#issuecomment-6508191529) 已在 Mac 公开且 iOS 送审回读后回帖，并以 completed 关闭（20:59:22Z / 20:59:25Z）。只关闭冻结 v0.80–v0.82 对应的这两个 issue，没有追逐运行中新 release。

Todoist Dev 任务 `6hrVCGRx5hMf69h2` 已移到 Release，保持未完成以反映 Apple 审核/公开仍待外部结果。本文件和 evidence/authorized-public-delivery.json 记录实际交付；本收尾分支仍按独立本地审查 → push/PR → GitHub 当前 head review → Fast Checks → 门禁合并执行，不跳过文档 PR review。
