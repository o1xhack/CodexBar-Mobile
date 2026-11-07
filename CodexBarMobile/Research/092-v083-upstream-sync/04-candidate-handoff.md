# 候选产物与审查交接

状态：本地候选产物、P1修复与重建完成；远端当前head审查以PR实时状态为准。未经用户另行授权不合并或正式发布。

## 版本与来源

| 项 | 值 |
|---|---|
| 上游冻结 | v0.83.0 / 348e2fa8d36ae8e452739ca07a79e83ab9d25e98 |
| Mac候选 | 0.83.0.1 / Sparkle176.1.3.3.0 |
| Mac实际source commit | a6ab1035b56be911e64479feb3c90696ded4edcb |
| Mac shipping输入 | evidence/mac-draft-source-manifest.json，1835项 |
| 配套已交付iOS | ASC本轮确认3.3.0 READY_FOR_DISTRIBUTION，MOBILE_VERSION=3.3.0 |
| iOS本地候选 | 3.5.0 (263)，不代表已上传或发布 |
| iOS Archive实际source | 23ff6887da5ef996c47dcfc967d7b369e78b7cd7 |
| iOS shipping输入 | evidence/ios-reviewed-input-manifest.json，353项与最终源码一致 |
| iOS Archive ZIP SHA256 | 10945e62216b4902fcdcc19fe1fab2249bb812e16349c522c5d23f08eced8ed2 |

本地iOS产物：`CodexBarMobile/build/upstream-v083/CodexBarMobile-3.5.0-263.xcarchive`及同名`.xcarchive.zip`。四角色版本/签名及CloudKit Production验证在evidence/ios-reviewed-archive-verified.json；Apple Development签名，本轮未导出IPA/上传ASC。Review P1只改变Mac确认路径，iOS输入未变。

## Mac no-tag draft

[GitHub draft](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-63e998e5e7fd7aeec74e)，release ID `437184008`；draft=true / published_at=null。

GitHub实际draft `tag_name`为`untagged-63e998e5e7fd7aeec74e`，预期正式tag为`v0.83.0.1-mobile.3.3.0`；两者均没有远端Git ref。后续更新按实际release ID定位，不重建重复draft。`target_commitish=mobile-dev`仅为占位目标，实际source为a6ab1035b。正式发布前另行授权后校正tag/target与已审查合并来源。

| 附件 | Bytes | SHA-256 |
|---|---:|---|
| CodexBar-0.83.0.1-mobile.3.3.0.dSYM.zip | 74666544 | fd39aaabe3f6494402d09ee7d2b2645aeaee21a8772ac12bcc5fa08ad6b1ffa7 |
| CodexBar-0.83.0.1-mobile.3.3.0.zip | 93704893 | 5144b088ae5844d61ece3d6cfc0a32a50f2bd0e2b20701e4ad24382560533469 |

本地副本位于`CodexBarMobile/build/upstream-v083/`。双架构App/dSYM UUID：arm64 `8B90D443-D580-31F7-883A-CD4BD3797003`，x86_64 `B23BFDCE-AE77-340F-8892-D349C2B09C33`。App/CLI/Watchdog/Widget均签名、hardened runtime、minimum14.0；公证staple/分发策略和隔离启动/资源/实际App Group验证通过。实际ZIP的Sparkle签名匹配包内公钥，GitHub附件digest/size匹配本地。

旧c8f候选已由本包替换，历史副本在本地`build/upstream-v083/superseded-c8f491f90/`，不可作为最终候选。当前证据为evidence/mac-draft-source-manifest.json、mac-artifacts-verified.json、mac-draft-verified.json。若后续review改变shipping输入，继续重建并更新同一draft。

## PR与交接准入

[PR #232](https://github.com/o1xhack/CodexBar-Mobile/pull/232)，base `mobile-dev`，head branch `upstream-sync/v0.83.0-mobile.3.3.0`；关联但不关闭[#231](https://github.com/o1xhack/CodexBar-Mobile/issues/231)。手动clean后ready事件追加审查发现P1，修复及回归见05；先前clean回执仅为历史，不验证新head。

本地独立源码/测试复审覆盖a6ab1035b，报告保留于项目`build/upstream-v083/qa/final-local-review-a6ab1035b.md`，SHA256 `caf47d1c40d8a8bae98ec50bf62ec8634d78fad21eaecfc898df6561d2c31a80`。最终完整候选的实际本地review报告、GitHub当前head review/threads/checks及gate日志也保存在本地QA目录；PR保留真实回执和线程回复。当前head必须clean、零未解决线程、无正在进行的追加审查、所有PR Fast Checks通过，再运行`Scripts/check_pr_review_gate.sh 232`后交接。实时Summary若Running，即使旧receipt使legacy gate通过也不能交接。

16组合是独立进程wire/merger替代验证，不能冒充实体CloudKit/APNs/缓存收敛；真实provider/Cookie/Keychain读取探测未运行。CloudKit代码审计NO_DEPLOY。新OpenDesign通知订阅须安装3.5客户端；旧客户端可generic展示。

未merge/auto-merge、未推Git tag/live release/appcast、未上传TestFlight/App Review、未deploy CloudKit，也未关闭#231。合并后Final CI仍须在公开发布前确认。Todoist按真实代码/审查状态流转，不提前Release/done。主打包worktree被应用视为primary checkout不能自动归档，保留并在交接时对齐最终head；本任务启动的模拟器均已关闭。
