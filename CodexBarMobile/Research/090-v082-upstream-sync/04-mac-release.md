# 候选产物与签名

状态：`done`。2026-10-29 已按授权合并 PR #225（及必要修复 #227/#228）、公开 Mac 0.82.0.1，并提交 iOS 3.3.0 (261) App Review（WAITING_FOR_REVIEW / AFTER_APPROVAL）。最新实际版本、产物 hash、CI 和状态见 [08-public-release.md](08-public-release.md)。下文保留 2026-10-28 候选阶段历史；其中未发布/未上传/placeholder/旧产物表述不代表当前状态。

## 固定版本（候选阶段历史）

Mac0.82.0.1 / BUILD175.1 / Mobile3.2.0 / Sparkle175.1.3.2.0；draft逻辑tag v0.82.0.1-mobile.3.2.0，不创建/推送tag。Mac companion使用ASC已交付3.2.0(260)，iOS待交付版本独立3.3.0(261)；正式发布前按versioning重新核对实际顺序，不制造多个用户版本。

## iOS本地Archive（完成）

- 源码：a36c6b110da3d994c8bba6bbcfa777627efa42ff，Archive前assert所有iOS/Shared输入与该commit一致。完整输入manifest与生成project hash见evidence/ios-archive-source-manifest.json和ios-archive-verified.json。
- 命令：xcodegen generate后，xcodebuild archive -project CodexBarMobile.xcodeproj -scheme CodexBarMobile -configuration Release -destination generic/platform=iOS -jobs2 -allowProvisioningUpdates -packageAuthorizationProvider netrc；derived data、archive、xcresult均在/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/Upstream082下。
- 产物：CodexBarMobile-3.3.0-261.xcarchive；ios-local-archive.log/xcresult，ARCHIVE SUCCEEDED。
- App、Push、WidgetOptions、Widgets、CodexBarSync.framework五bundle均3.3.0/261；codesign --verify --deep --strict通过，五者signature TeamIdentifier均3TUERHN53E。
- App、Push、Widgets签名CloudKit environment=Production；WidgetOptions仅本地AppGroup选项，无CloudKit调用；framework没有独立execution entitlements。不能把无CloudKit角色的空entitlement误写成Development。
- App/扩展四语言lproj均存在。App与dSYM UUID DF54F795-6609-3905-B631-FBBAD26A1839匹配。主App binary SHA256 5df57e470d2bcc3875e3f68991b0ecad983187e25d6703e7861154fc04eed456；完整archive逐文件manifest的解析后JSON序列化SHA256为1d58f444ffbe377fb4591f9b01bf5c43f8bc975d2c5984ce2d051f46d9801e0e；实际manifest文件SHA256为21fd11e0bd8a300751ba60b8d217cc6d50680fcfc77c894b625a8a57af467109，算法见verified JSON，避免将两种编码混称文件hash。
- 当前是Apple Development本地签名、get-task-allow=true；不是App Store/TestFlight分发包。未export/上传/提交审核；将来分发需获相应授权并按当时reviewed inputs及签名方式重新核对。

## Mac候选（历史过程）

最初sign-and-notarize在签名/公证前因lint纯排版修复取消，owned进程/编译孤儿已终止，private notarization temp副本无遗留；不把该次当成功。

后续从已冻结source重跑真实签名公证、ZIP/dSYM UUID、Production、Gatekeeper与isolated launch smoke；再用release.sh --draft-no-tag-push创建draft并核对附件digest，记录实际source SHA和placeholder target mobile-dev。候选appcast仅在scratch生成/签名验证，不修改/发布仓库feed。任何review修复改变artifact inputs就重建相应产物。


## 首个Mac实包：已hold，须替换

82a2adb47运行release.sh --draft-no-tag-push，首次Xcode缓存缺SweetCookieKit固定5b0提交/tree失败，按官方v0.5.9补齐本任务cache（全部8个锁定依赖复核可读），不改lock。第二次完整lint、双架构、Widget Xcode、Developer ID签名、公证62dab5c1-5190-4d35-a0c1-331dd89093f2、stapler、distribution policy、isolated CLI/资源/启动均通过，draft427366941创建。ZIP f408e157c96a80b908d335a17184edb112af666a31973ec7a73bf6b8c7dae1cc，dSYM23a0ee2ef91cb10a35fe8daa179df2fc5ee084efe77ff792ad753c4419b430a1。

后续更强实包验证发现真实Group错配，独立复审确认阻塞，故这些资产不是最终候选。draft正文已标hold，后续保留旧包证据并重签替换；没有live/tag/feed发布。链接：https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-780e47f927e739ed48a3 。具体修复设计见01。


## 最终候选验收（2026-10-28）

当前产品源码：`18ebb97272a68853473b3c3c565fc56f719901e2`，后续仅补文档/证据。Mac Group/CLI 修复后重新构建、公证与校验；旧草稿包已hold，最终附件替换结果见04。iOS原353项Archive输入重新逐项SHA256核对不变（evidence/ios-archive-final-input-equivalence.json），保留a36来源Archive。

- 最终Mac受影响128 selections/43组全部首遍PASS，0fail/timeout/retry；与成本修复97项及原完整gate1620项去重，覆盖1845 selections/16194 method identifiers。123个条件XCTest skip及Swift Testing opt-in early-return限制保留；不是单一最终binary全量body通过。见evidence/mac-appgroup-final-coverage-review.md与proof。
- `mac-appgroup-full-lint.log`完整lint与`mac-appgroup-final-build.log`的swift build --jobs4通过；SwiftLint 3211文件0违规，4语言533keys、parser24/hash、CI/fork guards通过。16个打包合同及timestamp retry stub通过。
- 真实Developer ID签名QA正负控：独立nonce group的声明成员可open，无成员EPERM；containerURL非nil不能证明授权。未操作用户业务容器，任务QA容器已清理。最终App/CLI runtime group均与Widget签名Group一致，生产包本身单独验证。
- Mac最终双架构App/CLI/Watchdog/Widget均Developer ID、hardened runtime、minOS14.0；App与dSYM双架构UUID一致。公证`343e9fc0-4ac2-4f2e-9300-c0492953d430` Accepted，stapler、distribution policy、隔离启动通过。
- Sparkle175.1.3.2.0单调递增；最终ZIP长度92810809、Ed25519以及实际App内SUPublicEDKey客户端校验均通过。仅scratch候选appcast，仓库feed无修改。
- iOS全量1278 Swift Testing/85 suites +75 XCTest及后续150 tests/6 suites通过；普通iPhone/iPad、Duo实际内外屏横竖、partial和跨折叠操作、严格SpringBoard Widget及四语原生渲染证据继续有效。
- 16组合全部为 **substituted**（64 reads/32真实冻结consumer merges），没有实体双Mac/双iPhone CloudKit/APNs/缓存收敛实测。CloudKit结论 **NO_DEPLOY**；本轮Group仅Mac本地共享容器，iOS/Shared wire不变。
- GitHub已对7f6bdc416返回clean，Fast Checks通过；最终收尾文档仍需current-head复核，动态结果以PR225为准。未merge/tag/live/feed发布或iOS上传。Final CI在授权合并后执行。

### 2026-10-28 候选资产身份（已被正式重签包替代）

| 文件 | SHA256 |
| --- | --- |
| CodexBar-0.82.0.1-mobile.3.2.0.zip | 06dcb2492cc1bdeac809650deceb4d1a4388c0170f167b866ec57bdb23473aa1 |
| CodexBar-0.82.0.1-mobile.3.2.0.dSYM.zip | d0d3be366d0d243c562b44a1d8df904aecdf16db860fedd86d45185199c00162 |

mac-artifacts-verified.json记录实际App、CLI、Widget签名/运行Group及每个角色的Production要求。Widget/CLI为AppGroup-only，不要求CloudKit profile。draft固定ID427366941；服务端实际tag_name为untagged-780e47f927e739ed48a3，逻辑未来发布tag为v0.82.0.1-mobile.3.2.0，未创建Git tag。target_commitish=mobile-dev是placeholder，artifact source是18ebb；发布前须按授权retarget并核对正式feed/交付顺序。

### Draft附件替换完成

固定ID427366941的两项旧资产已逐一验证原ID/digest及保留副本hash后替换。远端新ZIP/dSYM的size、SHA256与上述最终实包一致，正文hold已更新为真实source与placeholder说明；fresh API回读draft=true。原始logicaltag查询404的失败尝试停在只读断言，未产生mutation；随后绑定实际server draftTag，全部上传仍使用固定releaseID的upload_url。证据evidence/mac-draft-final-assets.json。未创建Git tag或发布feed。

## 正式交付覆盖记录（2026-10-29）

Swift 6.2 编译修复后重新签名/公证，正式 ZIP SHA256 为 `7bd3eb40b2bbbe0c99816eb1211f762fc1932bb8d4acccedec0daaeff008c2c3`（92810579 bytes）；dSYM 为 `1d62ad2dfba238bc8a230e8617ab174a15d9b4dcb3fe57a2b8f7fd2e1add5589`。上文 18ebb/343e9fc0 公证及 06dcb/d0d3 候选资产均为历史，未作为正式发布产物。正式源码、tag、Production 签名、公开 feed、匿名下载验签，以及 iOS Distribution 导出/上传/送审回执统一见 [08](08-public-release.md) 和 [实际交付证据](evidence/authorized-public-delivery.json)。
