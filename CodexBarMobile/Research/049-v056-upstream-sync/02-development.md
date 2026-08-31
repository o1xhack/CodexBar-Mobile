# v0.56.0 Upstream Sync 开发记录

Status: `done`
Date: 2026-08-28

## Phase A — 调研与分支

- [x] 从最新 `origin/mobile-dev=c7f61ae60` 创建
  `upstream-sync/v0.56.0-mobile.1.23.0`；
- [x] 读取 `AGENTS.md`、versioning、compatibility、CloudKit 与 release docs；
- [x] 核对 open issues #102-#104、历史 closed issue #95 与上游四个 Releases；
- [x] 拉取 collision-safe upstream refs并核对 tag/version/build provenance；
- [x] 完成 merge-tree conflict、Shared/wire/schema 与 release-boundary审计；
- [x] 写入 Research 049 概览、设计、开发与测试计划。

## Phase B — Mac merge / integration

- [x] merge `v0.56.0`，merge `a7ab9f708` 保留 upstream second parent `fc1bd0d797`；
- [x] 逐一解决 20 个 conflict files / 112 hunks；
- [x] 语义合并 Claude slot-key migration 与 fork pending-delete ownership；
- [x] 保留 fork CI、release/appcast、Production entitlements 与 composite version；README 在保持 fork
  identity 后单独吸收 OpenCode Go 与 AI Usage Limits事实并更新 reviewed hash；
- [x] 吸收 cost scanner/cache、provider、CLI security 与 localization；
- [x] parser logic version升至 `14`，generated hash更新为 `c6ecfbe76f4248db`；
- [x] Mac focused/build/lint与修复后 full suite 通过：`10254 tests / 964 suites`、
  `0 failures`；最终 lint 为 2093 Swift files / 0 violations。

## Phase C — Shared / iOS

- [x] 最终审计 root `Shared/` 与 `CodexBarMobile/Shared` wire/parity；
- [x] 证明现有 generic lanes覆盖 Cursor/Kiro/Alibaba/Fireworks/Antigravity/z.ai/OpenCode；
- [x] 补 Kiro semantic labels 与四语言 localization；
- [x] 补 v0.56 producer/round-trip/reader fixtures与代表 PreviewData；
- [x] 更新 `version.env`、`project.yml`、root/iOS CHANGELOG、MobileReleaseNotesCatalog；
- [x] `xcodegen generate`，iOS 4 targets `1.23.0 (196)`，full tests 738/738，Release compile通过。

## Phase D — Compatibility / release candidate / review

- [x] 正式 CloudKit schema audit与 Production只读回看，verdict `NO_DEPLOY`；
- [x] 逐行填写 16-case matrix，全部如实标为 `substituted`并记录残余风险；
- [x] merge 与 bridge/iOS 两轮 self-review + agent review，已修复 README 适配、
  CloudKit terminal-delete 误清 ownership/cache 与 Codex OAuth 优先级回归；
- [x] release evidence 最终 self-review + agent review；
- [x] 生成并验证 signed/notarized ZIP+dSYM；
- [x] 创建 unpublished-tag GitHub draft并回读 assets/digest；
- [x] 临时 candidate appcast 生成、签名与单调性验证；
- [x] Research 状态与证据收口，blocker=0。

## Phase E — Merge / live release / App Store Connect closeout

- [x] PR #105 exact-current review gate通过后合并到 `mobile-dev`；
- [x] merge-only Final CI 33343515532 全绿；
- [x] 从 merge commit重建 Mac Universal artifact，完成 Developer ID签名、Apple notarization、
  staple、Gatekeeper与launch smoke，不复用旧 draft资产；
- [x] 公开 tag/release `v0.56.0.1-mobile.1.23.0`，生成、验签并推送 live appcast；
- [x] 创建 App Store iOS `1.23.0`，保存四语言 `What's New`；
- [x] Archive/upload build `196`，Apple处理为 `VALID` / `APP_STORE_ELIGIBLE`，绑定到版本页；
- [x] 完成 source/Archive/Apple CDN三层 icon验证与 Production entitlement回读；
- [x] #102-#104附证据 close，Todoist移至 Release，清理已合并 task branch；
- [x] 初始 closeout 保持 App Review/public iOS release 未执行；CloudKit verdict `NO_DEPLOY`，未 deploy；
- [x] 2026-08-30 获得追加授权后提交 App Review，回读 `WAITING_FOR_REVIEW`；保持 `MANUAL`，
  未执行 public iOS release。

## Conflict 决策记录

| Path / area | Upstream intent | Fork invariant | Resolution | Verification |
|---|---|---|---|---|
| `.github/workflows/ci.yml` | 新测试平台与 runner hardening | PR Fast Checks + merge-only heavy CI | semantic union：glibc+musl都服从 final path gate | CI policy/path/reuse gates pass |
| `CHANGELOG.md` / `version.env` | upstream 0.56 / build 131 | fork mobile-first changelog + composite version | 单一 `0.56.0.1 / 131.1 / 1.23.0` train并补齐四个upstream段 | version/changelog extraction pass |
| `appcast.xml` | upstream public feed | fork live feed不可在 candidate改写 | 保持 published fork feed；candidate只在临时位置生成 | pre-draft byte/hash clean |
| `CloudSyncEngine.swift` | Claude slot replacement/delete | fork pending delete ownership/retry | save-confirmed-delete + durable cancellation；review后限制unknownItem才清cache | migration/delete classification tests pass |
| cost scanner/store/hash | read-view/fair scheduling/estimated cost | coverage/provenance/cache compatibility | parser v14 + predecessor union + fair scheduling/read-view union | focused/lint/hash gates pass |
| Alibaba/OpenRouter | CLI-first/parser/plugin fixes | fork bridge/parser hash | CLI-first和cookie fallback兼容；OpenRouter日期trim/replace union | provider/plugin tests pass |
| Codex CLI auto source order | 上游有效OAuth expiry/model windows必须优先 | fork CLI dashboard fallback仍需保留 | `PAT -> OAuth -> web -> CLI`，managed保持`PAT -> OAuth` | OAuth/baseline focused 57-test set pass |
| CI/test scripts | upstream shards/aggregates | fork path gate/policy | 6 Mac shards + glibc/musl aggregate + cleanup hardening | 62 cleanup tests及所有policy scripts pass |

## Review 记录

| Round | Exact head | Scope | Findings | Fix / retest | Result |
|---:|---|---|---|---|---|
| 1 | `a7ab9f708` + worktree | merge + fork seams | README事实适配遗漏；其余CI/provenance/version clean | 更新README OpenCode Go/AI Usage Limits与reviewed hash；guards pass | fixed |
| 2 | `a7ab9f708` + worktree | Shared/iOS + localization | terminal permission/auth delete误清cache/ownership；evidence pending | 仅unknownItem清cache；test/re-review clean；03-testing补齐 | fixed |
| 3 | `b9ae71f8f` + draft/body closeout diff | release diff + evidence | draft body缺 root CHANGELOG 用户可见正文 | 回写 Added/Changed/Fixed/Upstream range，API exact-match 回读；三路 agent 复核 | fixed; blocker=0 |
| 4 | PR #105 / `62abb00ef` | exact-head Codex Code Review | Kiro API enabled未覆盖stale CLI disabled；iOS Kiro稳定值片段未本地化 | API状态改为authoritative；iOS展示边界本地化`Enabled/Disabled`、`N credits`、`of N`；Mac 20/20、iOS 4/4、full lint pass | fixed; next head reviewed |
| 5 | PR #105 / `64c7669c4` | exact-head Codex Code Review | API `ENABLED`但缺cap时被降为unknown，组织账号无CLI fallback会隐藏overage usage/charges | enabled与cap解耦；cap仅控制gauge/remaining/cost limit；组织账号fixture不含CLI overage仍显示API usage/cost；Kiro 20/20 | fixed; next head reviewed |
| 6 | PR #105 / `84d51b643` | exact-head Codex Code Review | bonus secondary value的`expires in 19d`后缀在中/日文iOS仍为英文 | 拆分`of N`与expiry片段，复用既有4语言Kiro expiry key，覆盖19/1/0天；iOS 4/4 | fixed; re-review pending |
| 7 | PR #105 / `6b8e9f768` | ready-triggered第5轮Code Review | Kiro `Overage` window与Antigravity `Offline · N conversation(s)`仍为英文 | 按第6轮前置architecture audit统一改造provider-aware window展示边界；固定Kiro语义、结构化Antigravity count、unknown/custom原样；4语言fixture；iOS 8/8；full lint pass | fixed; round 6 pending |
| 8 | PR #105 / `78568bf34` | exact-head第6轮Code Review | 无email Claude Swap旧版以`Account N`作CloudKit key，slot迁移未保护旧record，save失败时可能先删后丢 | 从durable slot重建旧`Account N` predecessor key；复用save-confirmed delete队列；覆盖reconciliation、未确认save不删、确认后删除；focused sync migration 33/33；full lint pass | fixed; round 7 pending |
| 9 | PR #105 / `f189e2247` | 第7轮完成后的unresolved-thread audit | 第5轮另有OpenRouter `API key limit`稳定值与z.ai `Account balance` breakdown两条P2未被纳入前次修复/resolve | 扩展provider-aware detail边界：OpenRouter固定状态、HTTP/rate格式与z.ai余额片段4语言本地化；dynamic/custom原样；iOS 5/5；full lint pass | fixed; round 8 pending |
| 10 | PR #105 / `4e7af68e0` | exact-head第8轮Code Review | 无rate window时首页走`ProviderDetailsTeaserView`，仍直接渲染raw `row.value`，绕过详情页的新本地化边界 | teaser value统一调用同一provider-aware formatter；覆盖OpenRouter中/自定义provider fallback；iOS 5/5；full lint pass | fixed; round 9 pending |
| 11 | PR #105 / `1801b4db6` | 第9轮clean后的review gate | gate错误要求audit `Head`等于重构后的第六个distinct reviewed commit，与skill规定“先按当时head audit、再重构”矛盾，合规audit无法通过 | audit改为匹配评论时点最近一次已review head且必须早于第六轮；stale checkpoint fixture必须失败；gate tests、PR #105 live gate、full lint通过 | fixed; round 10 pending |
| 12 | PR #105 / `caa1f6dd3` | exact-head第10轮Code Review | 两个Claude Swap slot共享旧email predecessor时，一个replacement已确认、另一个terminal skip；旧流程可能先移除skip sibling映射，再让confirmed sibling在下一次refresh删掉仍需保护的predecessor | 每轮push在任何confirmed migration完成前统一stage所有sibling predecessor；terminal skip只停止相同payload重试，不再丢弃durable predecessor保护；覆盖旧错误持久化状态的修复、shared-predecessor确认/skip顺序；focused migration 33/33；full lint 2093/0 | fixed; round 11 pending |
| 13 | PR #105 / `014c1b31d` | exact-head第11轮Code Review | terminal-failed Claude Swap slot在从authoritative refresh移除后仍保留predecessor guard，导致成功sibling永远无法清除旧email-keyed record | authoritative reconciliation先stage所有当前sibling，再按`recordNamesToDelete`剪除removed replacement guards；只有无当前引用的predecessor才立即释放，仍有sibling则等confirmed save；focused migration 34/34；full lint 2093/0 | fixed; round 12 pending |
| 14 | PR #105 / `98c4da26b` | exact-head第12轮Code Review | Linux cleanup delayed-readiness fixture用1秒delay加2秒总deadline，完整startup/observation/0.5秒poll在Ubuntu调度下会误报124并阻塞sharding gate | delayed case总deadline改为4秒；同时patch parent runner sleep并断言单次不超过0.5秒，以确定性守住旧1.2秒ancestry sleep回归；focused case pass（实际2.387秒）；full sharding + 62 cleanup tests pass；full lint 2093/0 | fixed; round 13 pending |
| 15 | PR #105 / `f313b17af` | exact-head第13轮Code Review | removed Swap guard释放的旧email-keyed predecessor可能已重新成为live普通Claude snapshot；直接并入delete set会短暂删除当前账号record | `releasePredecessors`显式接收`liveNames`并从released candidates中排除；覆盖关闭Swap回到普通账号的live-predecessor场景；focused migration 35/35；full lint 2093/0 | fixed; round 14 pending |
| 16 | PR #105 / `e9c5c2337` + worktree | exact-head第14轮finding + 第二次整体architecture audit | Kiro `budget.period=Overage`绕过provider-aware formatter；连续同类finding说明缺少“所有生产展示sink必须经过provider context”的架构约束。CloudKit复查还发现save callback可晚于后续topology变化，最终`takeDeletes`只检查pending引用、未在真正删除边界重验最新live topology | `BudgetProgressView`强制传入`providerID`并复用统一semantic formatter；加入生产sink源码守卫，Raw Sync Data则显式标记为canonical wire text例外。CloudKit按provider保存latest accepted live record names，并在最终predecessor delete边界再次排除live names；加入startup未对账/shared sibling未确认/live-again/all-confirmed四态矩阵。Mac focused 36/36、iOS v0.56 6/6、62 cleanup tests、CI policy/path/review-gate与full lint 2093/0均通过 | fixed in `e4a0bb2d3` |
| 17 | PR #105 / `e4a0bb2d3` | 第二次整体architecture audit后的exact-head第15轮Code Review | 无新finding；Codex结论为`Didn't find any major issues`，reviewed commit精确匹配`e4a0bb2d35`，unresolved thread=0 | GitHub review结论：`https://github.com/o1xhack/CodexBar-Mobile/pull/105#issuecomment-5472035579`；随后仅补本行Research证据，不再改产品代码 | clean; docs-only closeout head需最终review gate |

### 第二次整体架构审计（第14轮后）

- **Mac→iOS display sinks：**逐项盘点`rateWindows.label`、generic detail title/label/value、
  `budget.period`与amount period。正常Usage、detail、teaser、budget全部要求provider-aware
  formatter；Raw Sync Data作为开发诊断页保留canonical payload，但改为显式`Text(verbatim:)`
  并由源码守卫记录该例外，避免“遗漏”和“故意raw”继续混淆。
- **CloudKit migration/destructive boundary：**不再只靠stage/release时的topology快照；
  confirmed-save callback真正生成delete set时，再检查每个provider最新接受的live record names。
  四态矩阵证明startup、shared sibling、live-again和all-confirmed分支分别保持/删除正确。
- **fork CI/release seams：**复查PR仅跑Fast Checks、heavy CI仅merge/manual、README hash、
  PR review gate和release脚本边界；`check_ci_policy`、final path gate、review-gate fixtures、
  full lint/release guards全部通过，无新增版本、appcast、tag或CloudKit schema变更。
- PR evidence：第二次四字段architecture audit已写入
  `https://github.com/o1xhack/CodexBar-Mobile/pull/105#issuecomment-5471982473`。

## Draft artifact 记录

| Evidence | Value |
|---|---|
| candidate tag name | `v0.56.0.1-mobile.1.23.0` |
| ZIP | `CodexBar-0.56.0.1-mobile.1.23.0.zip` |
| dSYM | `CodexBar-0.56.0.1-mobile.1.23.0.dSYM.zip` |
| artifact source commit | `0d7db66a68ce341ddf5fc404048407500bddd944` |
| app UUID / dSYM UUID | x86_64 `BDD23A54-0136-3971-BF58-4FF48A85F382`; arm64 `6AE7CA97-6A0B-31C0-AA9D-EE26B35F6FDF`; exact match |
| ZIP SHA-256 / bytes | `1764e11669bab7439c3d283ca60279a189bb1711a5f4a75e3a07f728c24bd5ed` / `74879194` |
| dSYM SHA-256 / bytes | `ebf84fd9281cfb13ac9983a858689686c30c0ecaf3f73a235d0701891d248e6a` / `57059595` |
| notary / stapler / Gatekeeper | submission `2e926c37-a720-4c37-b6e0-a83d12b80e24` `Accepted`; stapler valid; `spctl` Notarized Developer ID; `syspolicy_check` ready for distribution |
| Production entitlement | extracted app entitlement = `Production` |
| GitHub draft URL / `draft=true` | `https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-f119f55a105dc5efcac0` / database `378828305` / `true` / target `mobile-dev` |
| draft body / asset readback | root CHANGELOG `Added/Changed/Fixed/Upstream release range` + provenance/no-publish gate API readback pass; both assets `uploaded`; GitHub SHA-256 digests and byte sizes exactly match local artifacts |
| candidate appcast | XML valid; `131.1.1.23.0`; enclosure length `74879194`; EdDSA verified; candidate kept only in detached `/tmp` worktree |
| remote task branch / tag | draft创建时两者均不存在；用户于2026-08-30授权PR后push branch，初始remote head `62abb00efb319affada9df0029532b1e151b71ab`；candidate tag仍不存在 |
| live appcast unchanged | working and `origin/mobile-dev` SHA-256 both `7a0078d8ab90af5be5d19e343c3054e2df45d9d94d584950491a77907eb03267` |

## Published release 记录

| Evidence | Value |
|---|---|
| PR / merge | [#105](https://github.com/o1xhack/CodexBar-Mobile/pull/105) / `9f3b28746ca74222e08bd8a2703d96c305546a26` |
| Final CI | [33343515532](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/33343515532) / success |
| Mac notary | `f19497f4-fc65-4295-af1d-2e54ef67480f` / `Accepted` / staple + Gatekeeper + launch pass |
| live release | [v0.56.0.1-mobile.1.23.0](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/v0.56.0.1-mobile.1.23.0) / published 2026-08-30 PDT (2026-08-31 UTC) |
| published ZIP | `9ac9007b0a05530eccaff54b2a9b154fd61b1bd43cf9212535e057b8b1104d30` / `74,884,775` bytes / embedded `9f3b28746` |
| published dSYM | `6382c774b1a08af41ab55f788f54fb07a829660917a5e56eb842685b3c93ec40` / `57,062,195` bytes |
| appcast | `131.1.1.23.0` / enclosure `74,884,775` / EdDSA verified / commit `d3b30a48a` |
| ASC version | `1.23.0` / `WAITING_FOR_REVIEW` / `MANUAL` / four `What's New` locales |
| ASC build | `196` / `VALID` / `APP_STORE_ELIGIBLE` / bound to `1.23.0` |
| App Review submission | `3d68c4ed-ad43-4ec1-b066-d945e01d019e` / submitted `2026-08-31T03:19:07.901Z` / `WAITING_FOR_REVIEW` |
| iOS archive | `/tmp/CodexBarMobile-20260830-181907.xcarchive` / bundle `1.23.0 (196)` / Production CloudKit |
| remaining authorization boundary | public iOS release not performed; `MANUAL` release remains in force |
