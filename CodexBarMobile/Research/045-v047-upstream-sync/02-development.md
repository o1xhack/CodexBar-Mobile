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
  snapshot：配置 diff 会写入 durable local deletion intent、立即 enqueue 该 provider 的本机
  records；离线/重启后继续执行，账号重新添加则取消 tombstone 与未发送 delete。
- PR #69 Final CI 的 x64/arm64 Linux jobs 同时暴露 `FileManager.replaceItemAt` 在 Linux
  上删除 destination 后失败的问题；cost cache 改用同目录 POSIX `rename(2)` 原子覆盖，
  与 repo 已有 credential atomic-publish contract 一致，避免 warm scan 第二次写入后
  `codex-v11.json` 消失；该 parser/cache source 变化同步重生成 hash
  `a32f8ff375500a19`。

Packaging preflight 发现 Xcode Widget extension 的 SwiftPM artifact resolver 即使处理公开
依赖也会尝试 macOS Keychain authorization。`package_app.sh` 的 Xcode 命令现固定使用
`-packageAuthorizationProvider netrc`，避免 headless release 进入交互式 Keychain prompt；
`test_package_signing.sh` 增加 contract guard。

最终从 clean HEAD `151a17ae43c3e1be9070d852efca2749e49ca719` 重新执行
`Scripts/sign-and-notarize.sh` 成功：Widget、CLI、watchdog 和主程序均打入 universal
candidate；Developer ID 签名通过；Apple notarization submission
`ad29f441-b170-422c-8cef-a440724156d2` 返回 `Accepted`；staple、Gatekeeper、distribution
和 direct-launch smoke 全部通过。生成 ZIP 与 dSYM ZIP，并以不创建 Git tag、不 push 的
方式上传到 GitHub draft。完整 hash、UUID、entitlement 与远端 readback 见
`03-testing.md`。
