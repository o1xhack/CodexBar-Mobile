# 候选产物与审查交接

状态：in-progress；尚未达到PR决策交接点。

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

Mac签名、公证、app/dSYM ZIP与no-tag draft正在生成；完成后记录实际release ID/URL、占位target、附件大小/hash、双架构UUID与签名验证。

## 授权边界

本轮只创建/更新Mac draft、上传其附件，完成本地iOS Archive、任务分支push/PR和审查。draft target `mobile-dev`为占位目标，不是实际二进制来源；正式发布前需对准已审查并合并的release commit。未merge/auto-merge，未推送tag/live release/appcast，未上传TestFlight/提交App Review，未deploy CloudKit，也未关闭[#231](https://github.com/o1xhack/CodexBar-Mobile/issues/231)。

16组合为独立进程wire/merger替代验证，不能冒充实体CloudKit/APNs/缓存收敛。真实provider/浏览器Cookie/Keychain读取探测未运行。合并后Final CI仍需在公开发布前确认；PR Fast Checks不会运行该重型矩阵。

PR与当前head review/check/thread状态待最终门禁后记录。Todoist保持真实候选阶段，不提前标记Release或done。
