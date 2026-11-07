# v0.83.0 候选本地独立复审（后续修复）

Reviewer: /root/upstream_audit
Reviewed commit: `23ff6887da5ef996c47dcfc967d7b369e78b7cd7`
Base: `origin/mobile-dev` / `0d3099448c73f0e7274b487be2d0775ab56a90be`
Result: clean（当前代码与文档无未解决 finding；不是测试/打包/远端review终态）
Base-to-candidate binary diff SHA-256: `8adbbe56d90f8118fcd7e5f0bc899a06c762b8059aa803d722198c59136830f6`
HEAD后tracked dirty diff SHA-256: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`（空diff）

本报告接续`final-local-review.md`（84410b519完整候选审查），复读完整候选清单、所有后续实质性diff与调用者；包括尚未跟踪的Research03、wire/Archive证据和resume_mac_gate.py。原有error.log/work不属于任务，未审查或修改。

## 已发现并修复的问题

- 前次4项finding（OpenDesign producer跨Mac身份、Perplexity marker lane、固定计数、影响表/Changelog）在当前候选仍已修复。
- 全量iOS测试暴露的UTC逻辑日期漏DST日问题已独立诊断为生产缺陷；486be990f为DateFormatter内部Gregorian calendar显式设置GMT，复审正确。固定三日测试同步@MainActor临时设置默认timezone=America/Los_Angeles并defer恢复，避免UTC CI漏检。365天性能fixture固定2026-11-06，保留365个日期/14600成本/1460000tokens预期和原2秒阈值。
- 本轮发现486be的英文release-note翻译value未随key更新，遗漏DST修复说明。23ff现已让en value完整等于新key，其他三语继续有对应说明。

## fork parser revision合同复审

`CostUsageForkParserRevisionTests`所有read/replace/reopen均改用`env.codexStoreHome`，与scanner options来源一致，未恢复无scope读全库行为。测试的历史12→13 metadata-only假设改为12→14的bounded reparse合同：1-byte阶段明确catchup pending，放开预算后校验clean-reference data、token总量、creator flag、snapshots/checkpoints和父子fork baseline完整性。

生产`codexCreatorAccountParserRevision=13`以及current==13守卫没有放宽；当前14仍必须重读resumed service_tier，未用元数据盖章跳过计费重算。helper单测对rev12/13/当前/旧文件均明确返回nil，而不是skip。原上游resumed-tier回归新增previousRevision12/13参数，并继续故意篡改pricingMode后验证standard/priority/standard与0.00592成本，从真实语义层防止过度采用旧行。未发现这组测试调整削弱必要的最终历史保证。

## cleanup工具安全性复审

新增KILL重试移到较慢process enumeration之前，但仍调用原`send(self.root, SIGKILL)`。该函数只对Popen的未reap直接子进程使用wait ownership；PID在未reap期间不能被重用，且`unreaped_exit_code`确认未退出才实际kill。若已reap则抛错，不会继续误发信号。其他后代仍逐次验证birth/session，native Darwin信号路径与Linux pidfd限制未变。3秒TERM grace和5秒排空失败门槛没有放宽，未新增全局kill或按名称杀进程。

慢枚举synthetic test令每次refresh消耗1秒、前两次SIGKILL无效，证明重试不会被昂贵枚举挤到deadline之后。此测试单独执行通过（1 test，0.001s）；旧实现在该场景无法排空。两处fixture ready等待由3/10秒改到既有30秒常量，只影响子进程启动setup，不改command timeout、cleanup grace/deadline或成功判定，范围适当。

已读取主代理完整cleanup-final.log：103 tests，OK，1平台skip。日志中2秒timeout/PermissionError是负控fixture预期；不能把这些文本单独解释为本轮cleanup失败。完整日志是主代理执行的验证，本审查没有另跑第二份全工具矩阵。

## Research工具和证据边界

- FrozenWireHarness/check_frozen_wire使用冻结old/new生产Shared与consumer代码、独立writer/reader进程，16组合64reads/32merge；明确标注不包含CloudKit/APNs/SwiftData/UI/实体设备。OpenDesign手写wire身份不能代替producer，当前另有真实sync key测试已补齐。
- resume_mac_gate对本轮原log的69完整通过groups与1失败group进行数量核对；根据新完整inventory保留未受影响selection，显式重跑SyncCoordinator、QuotaProviderList、MockProvider、AccountIdentity/MultiAccount/DualZoneReader及两个parser语义测试。集合union完整性断言、prior log hash、保留与重跑名单和exitCode均留存。就本轮已知改动范围，未发现遗漏受影响Mac suite的证据。
- 该工具的结果只能称覆盖并集，不能说单一最终binary完成全量。当前Research03仍in-progress，测试、UI、打包状态无提前通过声明。
- `ios-archive-verified.json`与`ios-final-input-manifest.json`仍记录486be来源；23ff更新英文资源后旧Archive不能直接当最终reviewed产物。最终须重建或提供符合规范的新产物/完整输入等价验证，主代理已在执行打包阶段。

## 独立核对

`git diff --check origin/mobile-dev`通过；`check_fork_readme.sh`通过；新增慢枚举合成测试单独通过；English key/value精确核对为true。未运行真实provider/浏览器cookie/Keychain probe，未争用xcodebuild的DerivedData。

全量Mac/iOS、Duo姿态动作、Mac公证/draft和iOS最终Archive/签名、GitHub当前head审查仍由各自真实日志与门禁确认。本报告不将任何运行中/未执行项标为pass，也不授权merge/tag/live release/TestFlight/schema deploy。

## 审查时未跟踪Research文件指纹

```json
{
  "CodexBarMobile/Research/092-v083-upstream-sync/03-testing.md": "8692e9ab9a144801b99f97e7a7dbc7b506bfd0d6be0488bc8bab6dd258d8f650",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-archive-source-manifest.json": "66a0cad84b1ff9a98e59de46a75e4a516d848d8ff73bf14f5d1ed956ab57f0a6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-archive-verified.json": "3037e84087e429dc190cd168eb70fd009bf58490f9a9544ab84d41c8438ec1af",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-final-input-manifest.json": "3261c5892cad788de3262516ac04a143b2b24de81174d493899fba1143547a3f",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/local-review-84410b519.md": "cdd990675cca01ce73eb725c261aa2397421c4d0129fc2b1e6a61d478380db58",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.json": "24293e2b57cef9ef120091ebb4d98ef826273376a884004a71965e925a7087d6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.log": "07a7bce62401648e808c91dc9f0966a760202627282762ff060b401da0693ec5",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-source-manifest.json": "bfb760a7e802d3557f5cadb9c30f9a6384bae42ea01c0a2bc1c188a9d72bc377"
}
```
