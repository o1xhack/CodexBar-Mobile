# v0.47.0 Upstream Sync 开发证据

Status: `done`
Date: 2026-08-03
Branch: `upstream-sync/v0.47.0-mobile.1.20.0`

## Round 0 — Preflight / research

- clean `mobile-dev` at `9d9db632`，与 `origin/mobile-dev` 一致；
- 在任何 Research / implementation 写入前创建目标 upstream-sync branch；
- 已读 AGENTS、versioning、sync compatibility、CloudKit audit、release checklist 与必需
  Git/release/QA skills；
- 权威 release 范围冻结为 `v0.45.2..v0.47.0`，覆盖 issue #66 与尚未被 monitor
  建 issue 的当天正式版 v0.47.0；
- annotated tag `v0.47.0` peel 到 `6a16c233`，v0.45.2 ancestry 通过；
- merge-tree 预演：41 个 content conflicts；
- P0 架构审计确认 fork Mobile sync 与 upstream fleet sync 同名 property/key 冲突；
- CloudKit 初判 `DEPLOY_REQUIRED`，实际 deploy 延后到独立授权门。

## Round 1 — Provenance-preserving merge

- Research checkpoint：`fbe5c63ed`；
- semantic merge：`78aa2f06727defd794b010562cd61a4008ad221a`；
- merge parents：fork checkpoint `fbe5c63e` + upstream peeled release commit
  `6a16c23313a782dee6861735116a6c06ec1338fe`；
- 41 个 content conflicts 全部按 fork / upstream 责任边界逐项解决，最终无 unmerged
  path、无 conflict marker，`git merge-base --is-ancestor v0.45.2 v0.47.0` 通过；
- 保留 fork 的 PR Fast / merge-only Final CI、Production entitlements、package/signing、
  appcast、四语言 Mobile 资产与定价 cache fingerprint；吸收 upstream v0.46-v0.47 的
  Mac provider、性能、安全、菜单、widget、Keychain、session/config 修复。

## Round 2 — 双 sync 隔离与 CloudKit

- fork 原有 `iCloudSyncEnabled` 继续只控制 Mac→iPhone，默认 `true`；
- upstream fleet sync 改名为独立 `macFleetSync*` properties / UserDefaults keys，master
  toggle 默认 `false`，include-secrets 只有在新 master toggle 开启时才生效；
- 两条通道共享稳定 device ID key `com.codexbar.sync.deviceID`，但 record family、zone、
  persistence state 和 consumer 完全分离；iPhone 不读取 fleet `AccountSnapshot`；
- fleet container/team/state namespace 改为 `iCloud.com.o1xhack.codexbar` / `3TUERHN53E` /
  fork namespace；删除 upstream 提交的 Developer ID provisioning profile；
- `Scripts/cloudkit/schema.ckdb` 不是只含上游新类型的片段，而是 2026-08-03 Production
  只读 export 中既有 5 个类型、4 个 fleet 类型，以及已有 iOS linkage writer 使用但
  Production 缺失的 `ProviderAccountLinkage` 的 union，避免授权 import 时破坏或继续遗漏
  Mobile schema；Development `cktool validate-schema` 通过；
- Production 只读 export 确认尚无 `AccountSnapshot`、`Device`、`Preferences`、
  `ProviderIntent`、`ProviderAccountLinkage`，所以 audit 为 `DEPLOY_REQUIRED`；
  `deploy_schema.sh production` 的 dry refusal 在任何 cktool 调用前以 exit 2 硬停，实际
  Production promotion 只能在另行授权后由 CloudKit Console 完成；未 import、未 deploy、
  未写 live CloudKit。

## Round 3 — Shared / iOS bridge

- 新增 Qwen Cloud、ZoomMate、xAI、Notion provider IDs，tail-append 到 notification list；
- `ProviderUsageSnapshot` additive optional `accountOrganization`、`zoomMateCredits`，z.ai
  hourly payload additive optional 7/30-day axes/series，全部显式 `decodeIfPresent`；
- `SyncCoordinator` 映射 Claude prepaid balance、xAI balance/cost daily、ZoomMate credits
  history、Notion workspace 与 z.ai hourly/daily series；不 bump `providerPayloadVersion`；
- iOS 增加四个 provider 的颜色、列表、detail routing、mock 和 identity 展示；ZoomMate
  专用 credit card，z.ai 24h/7d/30d segmented chart；xAI 复用 balance + cost history；
- `QuotaProviderList` 65→69，subscription 195→207，mock 77→81 / unique IDs 67→71；
- `CKRecordReservedKeyAuditTests` 纳入新的 Mac `CloudSyncEngine.swift` 写入面；
- ZoomMate structured credit status 不再依赖 history endpoint 成功：history 失败时仍同步
  balance/cycle/quota status，daily/today 仅在 history 可用时补齐；
- `Localizable.xcstrings` 的新增用户文案全部具备 `en`、`zh-Hans`、`zh-Hant`、`ja`，
  无 `state: new` 或缺失 key。

## Round 4 — 版本、文档与 parser

- `version.env`：Mac `0.47.0.1`、build `111.1`、Mobile `1.20.0`、upstream
  `v0.47.0 / 2026-08-03`；Sparkle 比较版本 `111.1.1.20.0`；
- `project.yml` 四个 iOS targets 均为 `1.20.0 (192)`，随后运行 `xcodegen generate`；
- root CHANGELOG 的 fork 段已定稿为 `2026-08-03`，HTML extraction 只包含 fork 段；
- iOS CHANGELOG 与 `MobileReleaseNotesCatalog` 更新，1.20.0 是唯一新用户版本；
- parser/cache 改动使 `parserLogicVersion` 9→10；post-merge Linux atomic-cache correction
  后最终生成 hash 为 `a32f8ff375500a19`，lint audit 通过。

## Round 5 — Test / review / draft ledger

完整命令、结果、xcresult、16-case matrix、CloudKit audit、review findings 和 draft
release 证据统一记录在 `03-testing.md`，避免本文件复制同一批长日志。

## Round 6 — Post-merge review correction

- PR #69 的自动 review 在 merge 后补报 P1：fleet snapshot writer 只有 upsert，没有
  reconcile/delete；本机账号移除、provider 禁用或全部 snapshot 清空后，其他 Mac 会持续
  读取旧 `AccountSnapshot`；
- 新增本机范围的 reconciliation：以稳定 `macFleetSyncDeviceID` 限定 ownership，比较本轮
  record-name set 与持久化 fleet snapshot set，只 enqueue 本机 stale record deletes，其他
  Mac 的快照不受影响；
- 空 snapshot batch 现在也会执行 reconcile；删除只有在 CloudKit success（或
  `unknownItem`，即服务端已不存在）后才清理持久化 cache，失败路径保留证据供后续重试；
- server/fetch deletion 同步清除 snapshot hash，避免服务端删除后当前有效 snapshot 因旧
  hash 被错误抑制、无法重建。
- PR #71 第二轮 review 将删除条件收紧为 authoritative snapshot set：provider 被明确禁用，
  或完整成功的 provider/account refresh 才能根据 absence 删除；启动期网络/鉴权失败、
  settings/cost/invalidation 等 partial publication 只更新已有记录，不删除 last-good fleet data；
- 每个本轮仍存在的 record 都会先取消同名 pending delete，再进入 payload hash shortcut，
  避免账号短暂消失后恢复、但旧 delete 仍在队列里最终删掉有效记录。
- self-review 进一步确保 enabled provider set 优先于残留 UI state：已禁用 provider 即使内存中
  仍有旧 snapshot，也不会抵消 delete 或被重新 save。
- 后续 review 的“最后一个 token account 被删除但 provider 仍启用”场景不再依赖 replacement
  snapshot：publication 会在本地持久化 record→token-account ownership，配置 diff 只为明确
  移除账号对应的 record 写入 durable local tombstone 并 enqueue delete；同 provider 的
  OAuth/cookie/env/claude-swap fallback records 不受影响。旧 persistence 没有 ownership index
  时只在 account key 与 token account UUID 或 external identifier 唯一匹配时回填；配置变更时把
  120 秒 throttle 中尚未入 `fleetSnapshots` 的 queued snapshots 与其 ownership 一并纳入
  tombstone 计算，避免“先排队、后删账号、timer 再上传”的 ghost record。离线/重启后继续
  删除，账号恢复或 authoritative fallback 接管同一 record 时取消 tombstone 与未发送 delete。
  配置删除同时撤销受影响 provider 的旧 queued authority，避免被裁掉的旧 batch 在 timer
  触发时把“空集”误解释成整个 provider 的 authoritative absence；下一次成功 refresh 再授予。
  snapshot publication 额外携带生成时的 per-provider `configRevision`；engine 消费时只接受
  revision 仍与当前配置相等的 provider snapshots/authority，并现场读取当前 enabled
  providers。这样删除/禁用前已生成但延迟到达的 notification 既不能重存旧 snapshot，
  也不能恢复旧 authority 或重发已禁用 provider。pending queue 按 provider slice 合并：
  被 revision gate 拒绝的旧 event 不覆盖已排队的新数据；真正过期的 pending slice 在 push
  前再次校验并丢弃。publication 若仍包含已 tombstone 账号，则该 provider 继续没有
  authoritative absence 权限，直到不含旧账号的成功 refresh。
  旧 cache 的 ownership 回填只接受稳定 account key（token account UUID 或 provider
  external identifier），不再用可编辑 display label 猜测归属，避免同名 OAuth/cookie
  fallback 被错误 tombstone。
  最后一轮 review 又补出三类 publication provenance 缺口：可被 UI failure gate 隐藏的
  refresh failure 不能仅凭 `errors[provider] == nil` 获得删除权；publication 必须保留 fetch
  开始时的 config revision；同 revision 的旧 partial event 也不能晚到覆盖新 pending slice。
  修复后，只有完整 apply 成功且 generation 仍为 current 的 refresh 才返回
  `ProviderSnapshotPublicationSource` receipt；receipt 固定携带 fetch-start revision，所有
  provider publication 另带进程内单调 generation，engine 在 MainActor suspension 之后先做
  revision + generation 双 gate，再进入 pending reconciliation。多账号 provider 只有全部
  当前账号都实际成功且有有效 snapshot 时才取得 receipt；错误被抑制、enrichment、cost、
  settings display 等 publication 仍可更新 last-good data，但绝无 destructive authority。
  以上 provenance/tombstone 仅在 Mac 本地 persistence，不改变 CloudKit wire/schema。
- `6cf207c4041f86c3a034c9c6f250d3471c35a209` 是 publication provenance 阶段的 clean
  checkpoint：focused 29/29、local full 8356 tests / 812 suites / 0 failure；后续仍继续按
  exact-SHA review 循环，不把该中间结论当作最终关闭。
- PR #69 Final CI 的 x64/arm64 Linux jobs 同时暴露 `FileManager.replaceItemAt` 在 Linux
  上删除 destination 后失败的问题；cost cache 改用同目录 POSIX `rename(2)` 原子覆盖，
  与 repo 已有 credential atomic-publish contract 一致，避免 warm scan 第二次写入后
  `codex-v11.json` 消失；该 parser/cache source 变化同步重生成 hash
  `a32f8ff375500a19`。

Packaging preflight 发现 Xcode Widget extension 的 SwiftPM artifact resolver 即使处理公开
依赖也会尝试 macOS Keychain authorization。`package_app.sh` 的 Xcode 命令现固定使用
`-packageAuthorizationProvider netrc`，避免 headless release 进入交互式 Keychain prompt；
`test_package_signing.sh` 增加 contract guard。

## Round 7 — Exact-SHA review continuation

- 文档一致性 review 先修正了 legacy ownership 只允许稳定 `accountKey`（token account
  UUID / external identifier）回填、绝不以可编辑 `displayLabel` 猜测的证据描述；
- 外部 CloudKit intent / config-file reload 现在都携带 exact previous/current config 与 revision，
  在覆盖 baseline 前执行同一套 record-scoped reconciliation；离线期间的 removal 由启动 repair
  补齐；
- 启动期 destructive authority 只来自成功 decode 且与当前内存配置 encode-identical 的磁盘
  config；malformed、不可读或仍处于 350ms debounce 的旧磁盘配置均不能授权删除；
- 较新的 external revision 在吞掉较早 local notification 前，会先把其 previousConfig 相对当前
  baseline 的本地 delta 标记 dirty；overtaken local plan 与 external plan 的 cancellation 取 union，
  避免恢复账号仍被旧 pending delete 删除；
- snapshot delete cancellation 新增 local-only durable persistence：清 tombstone 前先落盘 cancellation，
  CKSyncEngine 初始化后立即重放；初始化、fetch、queue 或 `needsAppUpdate` 提前退出均不会丢失，
  后续 authoritative delete 会显式覆盖旧 cancellation；不改变 CloudKit wire/schema；
- review-fix commits 依次为 `a948cb99e`、`a98cac24f`、`57351687a`、`c2622aafd`；最后一轮
  `CloudSyncSettingsTests` 36/36、lint 0 violations、local full 8363 tests / 812 suites /
  0 failure（339.093s）；Codex 对 exact SHA `c2622aafd9` 明确返回
  “Didn't find any major issues”，unresolved threads 为 0。
- 随后的 manual Final CI 在 Linux arm64 通过、x64 暴露 test-only FD reuse race：测试以
  `fcntl(F_GETFD) == -1` 断言刚关闭的 descriptor number 保持空闲，但并发 suite 已合法复用
  该数字。`71772e15e` 改为比较 `/proc/self/fd/<n>` symlink 是否仍指向原 pipe，继续验证旧
  read end 已关闭，同时允许 descriptor number 被复用；双架构 Linux 重跑均通过；
- 同轮 macOS shard 2 在 build 后的 `swift test list` 成功退出，但只返回一行损坏的 discovery
  output，原 runner 因无法识别而在 0 个测试已执行时失败。`50277b4d9` 先加入 malformed/empty
  retry；后续 exact-SHA review 继续指出 syntactically valid truncation 仍可能漏过 parser，且“两次
  相同”不能排除前两次稳定截断。`29f2da8fb`、`15a77b70f` 最终收紧为固定执行 4 次 discovery：
  最多容忍 1 次完全无法解析的瞬时输出，但任何两次有效 selection set 不一致都立即 hard fail，
  并要求至少 3 次有效结果；harness 覆盖 malformed-once 与“前两次稳定截断、第三次完整”。当前
  release code SHA `15a77b70f` 已重跑 `CloudSyncSettingsTests` 36/36 与 full 8363 tests /
  812 suites / 0 failure（336.143s）。最终 PR head `a17ed979f` 的 exact-SHA Codex review
  明确返回 “Didn't find any major issues”，unresolved threads 为 0；manual Final CI run
  [`31239327715`](https://github.com/o1xhack/CodexBar-Mobile/actions/runs/31239327715)
  的 x64/arm64 Linux、6/6 macOS shards、lint 与 aggregate gate 全部通过。

当时从 clean HEAD `151a17ae43c3e1be9070d852efca2749e49ca719` 执行
`Scripts/sign-and-notarize.sh` 成功：Widget、CLI、watchdog 和主程序均打入 universal
candidate；Developer ID 签名通过；Apple notarization submission
`ad29f441-b170-422c-8cef-a440724156d2` 返回 `Accepted`；staple、Gatekeeper、distribution
和 direct-launch smoke 全部通过。生成 ZIP 与 dSYM ZIP，并以不创建 Git tag、不 push 的
方式上传到 GitHub draft。完整 hash、UUID、entitlement 与远端 readback 见
`03-testing.md`。该 draft 早于 Round 7 review fixes，live 前必须从最终 merged commit
重新签名、公证、生成 appcast/资产并替换旧 draft assets，不能直接发布旧 candidate。
