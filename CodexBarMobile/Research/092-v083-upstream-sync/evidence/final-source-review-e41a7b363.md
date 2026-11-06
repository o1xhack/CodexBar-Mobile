# v0.83.0 最终源码独立复审

Reviewer: /root/upstream_audit
Reviewed commit: `e41a7b363f6e33f5da0b096b3b646a7e1e61b458`
Reviewed tree: `91e8f6b3ac2a9d63408dc7bdfee4bf068c8a9d79`
Base: `0d3099448c73f0e7274b487be2d0775ab56a90be` (origin/mobile-dev)
Result: clean（当前完整候选源码与已提交文档无未解决 finding）
完整base-to-candidate binary diff SHA-256: `5459743d78dfd8d4c5a0df76b25d3d611e32bb33799c4f14c730c9548f02af03`
HEAD后tracked dirty diff SHA-256: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`（空diff）

## 审查范围

接续84410b519完整初次复审与23ff6887d后续完整复审，重新核对完整候选差异/调用者与本轮后续源码、测试、README/guard和未跟踪Research证据。该报告覆盖当前完整候选，不只覆盖两个修复hunk；前次报告保留为历史，当前结果以本报告为准。原有error.log/work不属于候选，未修改或审查。

## 之前发现的全部问题现状

- OpenDesign不同Mac工作区误用legacy-no-identity：已用真实producer device record identity隔离，静态ID与实际key→identities测试均保留。
- 新provider测试计数/订阅尾部断言：已统一95/285订阅、126 mocks、121 current借用，已补对应assertion。
- Perplexity新iOS warning marker稳定ID：已修，组织/tertiary不误套native primary/secondary通知配置。
- UTC日历DST漏日：486be显式为Gregorian calendar设GMT；固定UTC三日回归设系统LA并defer恢复，性能365日fixture固定时点；不缩减预期。
- fork parser历史12→13采用合同过期与home错读：测试明确使用fixture home；当前14走语义重扫，保留最终clean scan、tokens、snapshots/checkpoints及fork baseline校验。上游resumed-tier负控涵盖12和13，未放宽metadata-only生产守卫。
- cleanup重试挤占deadline：只对未reap的wait-owned直接child提前执行已有send(SIGKILL)，其他后代birth/session/native保护不变；3s/5s门槛未放宽，fixture setup等待单独使用30s。慢枚举合成测试及103工具测试结果已读取。
- 英文release-note value落后key、Research误述z.ai金额通道、Changelog残行：均已纠正。

## 本轮追加的旧reader兼容 finding 已解决

旧公开iOS3.3按rateWindows索引绑定通知marker；曾新增的org-first producer排序会让旧reader把组织池当session lane，确属本候选引入的向后兼容回归。35ecfba43删除producer排序，保留native primary/secondary/tertiary顺序、组织池尾部追加；旧legacy字段也恢复原对应语义。Mac自身automaticPerplexityWindow仍选可用组织池，iOS展示独立池并允许显式选择，不新增wire。

新增`SyncCoordinatorMobileBridgeTests`从真实Settings/UsageStore注入合成usage、走真实pushCurrentSnapshot到MockSyncPusher，断言payload四个稳定ID顺序、primary仍100、组织20并且Mac自动窗口确实是组织池。该路径没有用手写wire快照代替producer。现有SettingsStore测试隔离分支禁止普通test发现shared defaults/执行app-group migration，测试不进行真实CloudKit/provider/cookie/Keychain操作。

此修复解决此前`perplexity-old-reader-compatibility.md`的新finding，未靠禁用个人通知配置或伪造period来掩盖旧reader限制。新iOS稳定ID容错保留，合理。

## README与fork保护

merge阶段保留fork README；之后有意审查的provider事实与social图token变更未动fork身份/下载入口。e41a7b363仅把cache token更新为实际`docs/social.png` SHA-256首16`34c94fe9dd95be54`，独立hash读取确认完整SHA为`34c94fe9dd95be5434f4b3224bb35536312b0d513fc8b4d1866dadca18910db2`。guard hash与有意README改动一起审查并通过；不是接受上游README整体。

CI触发模型、发布脚本、appcast、CloudKit Production定义和schema边界继续保持。动态plugin logo不改变provider/account/cost归属；Mac-only菜单、SSH/hook、本机别名/提醒决策与iOS独立展示边界继续合理。

## 当前验证证据的独立核对

- `git diff --check origin/mobile-dev`：通过。
- `bash Scripts/check_fork_readme.sh`：通过。
- `ios-unit-final.log`：实际读取到Swift Testing 1300/87 suites通过、75 XCTest零失败及TEST SUCCEEDED。这是主代理执行的测试，本审查没有另起xcodebuild。
- `ios-reviewed-input-manifest.json`：独立对全部353个记录逐项重新读取23ff Git source与e41工作树、计算SHA，均与manifest一致，mismatches=[]。
- `ios-reviewed-archive-verified.json`：独立对本地Archive四角色可执行文件重新计算SHA，全部与记录一致；记录明确local development-signed archive only、未上传/导出、get-task-allow=true。3个使用CloudKit的角色记录Production，配置options extension无CloudKit entitlement而有app-group，符合角色用途；本审查未把development签名称为distribution/TestFlight。
- Archive真实来源仍为23ff；35ec/e41只改Mac SyncCoordinator/测试/README/guard/Research，不改353个iOS shipped inputs，来源与当前iOS输入等价证据成立，不把Archive原SHA改写为e41。
- 旧resume_mac_gate.py已移除，本轮最终Mac全量正在对e41 binary完整重跑；不再采用历史groups并集作为最终全量结论。

## 剩余门禁与边界

当前Research03仍in-progress，部分旧进度尚待主代理用最终事实更新；没有将其当完成证据。Mac最终1869 selections/89groups全量、最终lint、Mac签名公证/draft附件以及Duo/普通设备实际姿态动作仍以完成后的真实日志验证，不能从本报告clean推断已通过。16组合wire/consumer验证只允许标substituted，不是实体CloudKit/APNs/独立缓存收敛。

本地源码review不代替GitHub当前head Codex review、线程清零、PR checks与合并门禁。本报告没有授权merge/tag/live release/appcast/TestFlight/App Review/schema deploy或关闭issues。

## 当前未跟踪Research证据指纹

```json
{
  "CodexBarMobile/Research/092-v083-upstream-sync/03-testing.md": "8692e9ab9a144801b99f97e7a7dbc7b506bfd0d6be0488bc8bab6dd258d8f650",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/cwl-dst-diagnosis.md": "e3c27fb96be220ef9b3cb5f149bdfee780414ba3c8d6c3ae6bc3dff187ef9e91",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/fork-parser-diagnosis.md": "c492712ef1ccfdc8135a8494fd9b6b1b74f6e96c676fee6473acd9432449df9e",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-archive-source-manifest.json": "66a0cad84b1ff9a98e59de46a75e4a516d848d8ff73bf14f5d1ed956ab57f0a6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-archive-verified.json": "3037e84087e429dc190cd168eb70fd009bf58490f9a9544ab84d41c8438ec1af",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-archive-zip.json": "9ca0d83cf527e6dcf286f01ef6c5021675cfa88652e7367b1f5e664de0517ce4",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-final-input-manifest.json": "3261c5892cad788de3262516ac04a143b2b24de81174d493899fba1143547a3f",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-reviewed-archive-verified.json": "fbcbac8745f8e5f795ff414a074963cecde36503f88e158d9de0223300477412",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-reviewed-input-manifest.json": "cb6788fa994ac51cbbf3a1bbeaf8a23925bc81b255e952378471b7a8e7233d7c",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/local-review-23ff6887d.md": "c608ff74cd7a36d2a0bd9a6240582c7a703cb65b0654530bc371405d500a7f3f",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/local-review-84410b519.md": "cdd990675cca01ce73eb725c261aa2397421c4d0129fc2b1e6a61d478380db58",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.json": "24293e2b57cef9ef120091ebb4d98ef826273376a884004a71965e925a7087d6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.log": "07a7bce62401648e808c91dc9f0966a760202627282762ff060b401da0693ec5",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-source-manifest.json": "bfb760a7e802d3557f5cadb9c30f9a6384bae42ea01c0a2bc1c188a9d72bc377"
}
```
