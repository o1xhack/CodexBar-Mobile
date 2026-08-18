# v0.52.0 Upstream Sync 开发记录

Status: `done`
Date: 2026-08-17

本文件只记录可复核的实现与冲突决策；不把命令流水账当作完成证据。

## Phase A — 分支与调研

- [x] 从最新 `mobile-dev` (`32283fd0c...`) 建立
  `upstream-sync/v0.52.0-mobile.1.21.0`；
- [x] 读取 `AGENTS.md`、`version.env`、versioning、sync compatibility、CloudKit audit、
  release checklist/flow与CI policy；
- [x] 复核 open issues #82–#88、历史 closed issues #77–#81、上游 Releases与相关 PR/commits；
- [x] 选择 authoritative latest release `v0.52.0` 作为单一 train终点；
- [x] merge-tree预演并识别 fork冲突面；
- [x] merge `v0.52.0` 并逐项记录冲突解决；provenance merge commit
  `25f81f26f` 的第二 parent 为 upstream tag peel `dc3ea3206c...`。

## Phase B — Mac / fork integration

- [x] 完整保留上游功能、修复、性能与安全变化；
- [x] 保留 fork CI/release/appcast/composite version/CloudKit Production约束；
- [x] 合并 provider accent/workday tick/scoped quota/project cost语义；
- [x] parser logic version滚动至 `12`；review修复与provider-design marker落地后最终hash为
  `a5a0cf92c6361f6e`；
- [x] root changelog与 `version.env`更新为 Mac `0.52.0.1 (124.1)`、Mobile
  `1.21.0`、upstream `v0.52.0 / 2026-08-17`。

## Phase C — Shared / iOS

- [x] 审计 Mobile wire能否承载所有 iOS-relevant output；
- [x] 确认不需要新增 additive字段：复用 generic rate windows、`loginMethod`、
  `usageDataConfidence`与details；`providerPayloadVersion`保持 `1`；
- [x] 合并更新唯一的 1.21.0 notes block，不创建 1.22.0 block；
- [x] 将 iOS全部 targets build从 193增至194；
- [x] 完成四语言 localization、technical changelog与 provider/widget/display tests。

## Phase D — release candidate

- [x] Mac build/lint/test/regression；
- [x] CloudKit Production审计结论 `NO_DEPLOY`；
- [x] signed + notarized candidate、codesign/spctl/CLI/launch verification；
- [x] 创建GitHub draft release并上传ZIP/dSYM，不发布live、不推tag/appcast；
- [x] iOS build/tests与16-case compatibility substitution gate；
- [x] 循环 review至 blocker 0并回写全部 evidence。

## 冲突记录

正式 merge共处理14个 conflict path/type：

| 路径 | 决策 | 验证 |
|---|---|---|
| `AGENTS.md` | 保留 fork iOS/release/CloudKit/review policy | policy/link/lint gates |
| `CLAUDE.md` | 接受 upstream `./AGENTS.md` symlink，避免两套规则漂移 | symlink target + doc links |
| `README.md` | 接受 upstream当前功能说明 | doc links |
| `CHANGELOG.md` | fork release段置顶并保留已发布历史；追加upstream 0.49.3–0.52.0 | `changelog-to-html.sh` |
| `.github/workflows/release-cli.yml`与fork CI脚本 | 吸收checksum改进，保持fork trigger/Homebrew gate | CI policy/path/release tests |
| `CodexbarApp.swift` | 吸收upstream Settings/Mission Control生命周期；把Mobile observer移至AppDelegate | `AppDelegateTests` |
| `UsageStore+Refresh.swift` / `UsageStore.swift` | 同时保留fork snapshot publication与upstream token/cost刷新；拆出Observation/PathDebug extension | build、lint、UsageStore tests |
| Codex descriptor与pricing/scanner | 接受upstream project/session/caching，保留fork provider-qualified/fallback pricing | pricing/scanner suites + parser hash |
| parser hash generated file | 重生，不手工择边 | final hash audit `a5a0cf92c6361f6e` |
| Linux pipe test | 保留两边 teardown与determinism覆盖 | focused/full tests |
| `appcast.xml` | 保留published feed内容，仅补终止newline；candidate不写live entry | monotonic audit |
| `version.env` | 按fork四段/subdecimal规则设 `0.52.0.1 / 124.1 / 1.21.0` | version audit |

## Bridge与iOS实现

- upstream删掉hidden SwiftUI keepalive window后，原 `SyncModifier`失去宿主。新增窄接口
  `MobileSyncCoordinating`，由AppDelegate在launch/termination启动和停止Mobile sync，并用
  `hasStartedMobileSync`防止重复观察；没有恢复不可见window。
- audit确认upstream `ProviderIntentPayload.accentColor`和
  `SyncedPreferences.workdayTickAppearance`只走opt-in Mac fleet channel，不进入Mobile payload。
- 新Mac producer语义通过既有Mobile envelope表达：Claude scoped window、Cursor三条lane、
  OpenCode Go estimated confidence、Grok plan/login label。新增bridge test时发现Grok primary仍被
  固定标成`Credits`，已改为调用`GrokProviderDescriptor.displayLabel(window:)`，现在输出
  `Weekly` / `On-demand`。
- iPhone对`Total`、`Third Party`、`On-demand`添加四语言canonical label；未知provider lane
  继续原样显示，避免未来Mac文案被错误隐藏。
- Codex Projects/Conversations仅存在于Mac local cost store/presentation；Mobile producer没有
  project path、conversation/session identity字段。本轮不把本地路径或会话标识写入CloudKit。
- iOS保持`MARKETING_VERSION=1.21.0`，四个target统一升build `194`；in-app notes只改写既有
  1.21.0 block，符合用户合并后一次public release的要求。

## Review修复

- CI-style grouped gate首次暴露fork基线与实现不一致：上一轮明确加入的Codex CLI
  `auto` dashboard fallback在merge中被upstream resolver覆盖。恢复普通CLI runtime的
  `web → OAuth → CLI`顺序，同时保留v0.52 managed workspace的OAuth-only边界；10个聚焦
  characterization tests通过。
- 第一轮全分支Codex review发现1个P2：provider-qualified Codex模型从models.dev精确命中时，
  Mobile cost summary仍只查本地OpenAI table并错误标成`isEstimated=true`。新增
  `hasExactCodexPricing`，仅接受bundled exact或模型自身route的models.dev exact hit，拒绝
  unlisted route与family fallback；pricing/sync 63 tests通过，并据此重生parser hash。
- 后续审查发现不能在aggregation完成后再查询可变的current catalog来覆盖pricing provenance；
  改为在cost计算时绑定immutable catalog并把`isEstimated`持久化到daily/model breakdown，
  Codex、Claude与Pi统一保持exact/fallback来源，legacy cache保持保守estimated。最终pricing/
  store/sync focused gate为184 tests、0 failed；实现提交`864e4df63`的复审无finding。
- full grouped gate随后稳定暴露provider architecture drift baseline：新增provider-specific pricing
  分支缺少设计marker，且upstream lifecycle合并改变了fingerprint。补充精确marker并更新预期
  drift count/fingerprint，architecture 38 tests两次独立通过，parser hash更新为
  `a5a0cf92c6361f6e`（提交`11026c86b`）。
- `11026c86b`提交级review发现comment-only hash bump未把父候选
  `1bd2d8ec2fd2dcf2`列为compatible predecessor，可能让候选构建升级时重建兼容SQLite历史。
  提交`c07a49caf`加入迁移白名单与test expectation；失败的writer-lock用例按与CI一致的
  `--no-parallel`条件隔离及整suite复跑后通过。该修复的commit review确认安全、0 finding。
- 最终upgrade-path审计继续以实际published tag而非版本名推断迁移来源，确认
  `v0.49.2.1-mobile.1.21.0`内嵌parser hash为`834522608c1b0457`，而既有白名单中的
  `b975eb705f905b9a`只是pre-release 0.49.x producer。提交`34857a41c`加入真实公开hash，
  并把release-upgrade test固定到tag中的generated value；parser check、75项serial store tests、
  97项pricing/store/sync联合tests与完整lint通过。commit级review复核schema未变、adoption仍受
  integrity/version gate约束，0 finding。
- 最终全分支review继续发现1个P2：Projects dashboard只用`sourceID + projectName`聚合，
  同一source下两个不同canonical path但同名的repository会被合并。提交`dddcd4fa3`把path纳入
  aggregation key，并用length-prefixed `sourceID + path + name`生成collision-safe SwiftUI ID；
  同名冲突时UI才显示中间截断的tilde path与完整hover文本。review随后指出两个split row仍会
  视觉同名、以及test把`/Users/example`误当作固定非HOME路径；两项均在同一提交中修复，普通与
  `CFFIXED_USER_HOME=/Users/example`两种环境各40项`SpendDashboardModelTests`通过，最终
  commit review为0 finding。
- 后续whole-branch review继续发现1个P2：同一repository分属两个Codex账号时，Projects row
  虽然identity已分开，但仍都显示generic `Codex`，用户无法判断归属。提交`1ae439e46`让row使用
  account-aware `displayName`，同时把test输入固定为generic model provider name，证明显示结果
  仍为`Codex · #1/#2`；focused 40 tests与该commit review均clean。
- 最终完整gate在第56/77组稳定失败，确认不是产品回归，而是上游/本轮插入分支后大量
  provider architecture exact anchor仍指向旧行号，过去被混入261项fork drift整体hash。没有
  直接接受新hash：先机械重定位63个唯一文本anchor，再按局部结构定位重复文本anchor，并把
  Factory/Alibaba、Cursor等实际已分裂的cluster拆成独立精确条目。最终reviewed fork-only drift
  从261项收敛为83项并锁定新排序fingerprint；提交`90c687939`后architecture 38项通过，完整
  lint通过，再从头跑923 selections / 77 groups，全部first-pass通过，0 retry / 0 timeout。
- 最终`codex review --base mobile-dev`重新审计完整branch diff与fork lifecycle、sync、pricing、
  cache、project aggregation路径，并运行focused checks；正式verdict为
  `No actionable regressions were identified in the diff`，blocker保持0。

## Draft release工件

- build commit：`90c687939`；notary submission：
  `da55b536-c3ea-4d45-a6cc-cdb7a4a71507`，status `Accepted`；
- app：`0.52.0.1`，Sparkle/CFBundleVersion `124.1.1.21.0`，universal
  `arm64 + x86_64`，stapled ticket、`codesign --deep --strict`、`spctl`均通过；
- ZIP为`69578142` bytes，SHA-256：
  `15fdd2ea501c5d16bc7aa60b5ce8e3b91bbc00a3c59b279cd09ceedaeb500976`；dSYM为
  `53855298` bytes，SHA-256：
  `7ac90a4a9b9ea057466aa5512fc0f26ea0f1e8963d43a03269c48e4c24a70d8d`；
- app/dSYM UUID一致：x86_64 `31392159-0BB9-379E-8035-037FB7F7981C`，arm64
  `353F365B-21A7-32AE-90FA-B80802CE8529`；
- draft release ID `372056029`，两个asset均为`uploaded`且GitHub digest/size回读与本地一致；
  readback后remote branch/tag仍不存在；
- candidate appcast在detached `90c687939`临时worktree生成并在验证后移除；完整candidate tag
  URL、length `69578142`、Sparkle version `124.1.1.21.0`与`sign_update`重算EdDSA signature
  验证通过；repo
  `appcast.xml` hash仍为`e5c21552739f2d6f12a919db7b3a24cd3d7ee889bc37b7c14cb7cc69ba08f779`，
  未执行publication。
