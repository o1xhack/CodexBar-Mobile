# 候选产物与审查交接

状态：本地候选产物与门禁完成；PR审查交接阶段。未经用户另行授权不合并或正式发布。

## 版本与来源

| 项 | 值 |
|---|---|
| 上游冻结 | v0.83.0 / 348e2fa8d36ae8e452739ca07a79e83ab9d25e98 |
| Mac候选 | 0.83.0.1 / Sparkle176.1.3.3.0 |
| Mac实际source commit | c8f491f90bc4720b73d9d7f22bd55b64eceb3379 |
| Mac shipping输入 | evidence/mac-draft-source-manifest.json，1835项 |
| 配套已交付iOS | ASC本轮确认3.3.0 READY_FOR_DISTRIBUTION，MOBILE_VERSION=3.3.0 |
| iOS本地候选 | 3.5.0 (263)，不代表已上传或发布 |
| iOS Archive实际source | 23ff6887da5ef996c47dcfc967d7b369e78b7cd7 |
| iOS shipping输入 | evidence/ios-reviewed-input-manifest.json，353项与当前源码一致 |
| iOS Archive ZIP SHA256 | 10945e62216b4902fcdcc19fe1fab2249bb812e16349c522c5d23f08eced8ed2 |

本地iOS产物：`CodexBarMobile/build/upstream-v083/CodexBarMobile-3.5.0-263.xcarchive`及同名`.xcarchive.zip`。四角色版本/签名及CloudKit Production验证在evidence/ios-reviewed-archive-verified.json；Apple Development签名，本轮未导出IPA/上传ASC。旧scratch Archive已被该最终产物取代，不作为交付候选。

## Mac no-tag draft

[GitHub draft](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-63e998e5e7fd7aeec74e)，release ID `437184008`；draft=true / published_at=null。逻辑tag `v0.83.0.1-mobile.3.3.0` 没有对应远端Git ref。`target_commitish=mobile-dev`仅为占位目标，实际source为上述c8f491f90。

| 附件 | Bytes | SHA-256 |
|---|---:|---|
| CodexBar-0.83.0.1-mobile.3.3.0.dSYM.zip | 74645383 | 4bfc96a54e531ce095ebf67f4abf4b640627089f97046937d777b527ee63f551 |
| CodexBar-0.83.0.1-mobile.3.3.0.zip | 93697736 | 68b25748ca88838f260c031e6ac8b4e458fa0c31c9ab8a488c6e9ad60f895c6c |

本地副本位于`CodexBarMobile/build/upstream-v083/`。双架构App/dSYM UUID：arm64 `8AFEECD8-6A40-3F92-B441-6CA02BB0B9F9`，x86_64 `57E5BC47-E461-3185-921C-024ABA22F3FE`。App、CLI、Watchdog、Widget均签名/hardened runtime且minimum14.0；公证staple/分发策略和隔离启动/资源/实际App Group验证通过。实际ZIP的Sparkle签名匹配包内公钥；GitHub附件digest/size匹配本地。

详细来源与签名证据：`evidence/mac-draft-source-manifest.json`、`mac-artifacts-verified.json`、`mac-draft-verified.json`。后续仅文档差异不重打相同二进制；若review修复改变shipping输入，必须重建并更新该draft附件与证据。


## 授权边界

本轮只创建/更新Mac draft、上传其附件，完成本地iOS Archive、任务分支push/PR和审查。draft target `mobile-dev`为占位目标，不是实际二进制来源；正式发布前需对准已审查并合并的release commit。未merge/auto-merge，未推送tag/live release/appcast，未上传TestFlight/提交App Review，未deploy CloudKit，也未关闭[#231](https://github.com/o1xhack/CodexBar-Mobile/issues/231)。

16组合为独立进程wire/merger替代验证，不能冒充实体CloudKit/APNs/缓存收敛。真实provider/浏览器Cookie/Keychain读取探测未运行。合并后Final CI仍需在公开发布前确认；PR Fast Checks不会运行该重型矩阵。

[PR #232](https://github.com/o1xhack/CodexBar-Mobile/pull/232)，base `mobile-dev`，head branch `upstream-sync/v0.83.0-mobile.3.3.0`；关联但不关闭#231。本地完整候选review覆盖 `66542a1d713016c26411c9bdd38a5522de4aff05`，结果clean / zero findings，实际报告已保留在项目build/upstream-v083/qa/final-local-review-66542a1d7.md，SHA256 `a863a5d411e3aed11cbe563dd1a30f148161ee387d29387494140e36c5157268`；此后只增加本PR对应记录，不改变shipping输入。最终handoff必须以该PR当前head的clean Codex review、zero unresolved threads、PR Fast Checks及`Scripts/check_pr_review_gate.sh <pr>`为准，不能把本地review当远端通过。Todoist保持真实候选阶段，不提前标记Release或done。
