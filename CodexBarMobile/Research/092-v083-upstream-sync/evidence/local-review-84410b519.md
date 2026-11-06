# v0.83.0 同步候选独立本地完整复审

Reviewer: /root/upstream_audit
Reviewed commit: `84410b51995415978b16f0a00fe23a4f678e9166`
Reviewed tree: `6645b5547ef42d70852d3782879a290dc6a86bf6`
Base commit: `0d3099448c73f0e7274b487be2d0775ab56a90be` (origin/mobile-dev)
Result: clean（代码与当前文档审查，无未解决 finding）
完整 base-to-candidate binary diff SHA-256: `d734c193883f4f21385ded6cd549089420a82d67dd347faf82c7f12c104b7147`
HEAD 后 tracked dirty diff SHA-256: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`（空diff）
受影响代码/测试/构建输入manifest fingerprint: `e3a940f9840a36f98502fffbca0b11ec802355a7b7d23dc1171a60d948988a7b`

## 审查范围与方法

独立读取完整候选文件清单、上游v0.82→v0.83变更与fork差异，重点阅读merge冲突、成本迁移、Shared映射、iOS调用者、通知配置、provider注册及测试、版本输入、README/guard和Research逐项影响表。当前代码已提交；未跟踪error.log/work属于用户原有内容，未纳入候选。新wire证据与Archive源manifest亦读取并记录下方hash；这些记录不代替实际产物验收。

## 本轮发现并已修复的问题

1. **OpenDesign跨Mac工作区误归并（P1）**：最初producer未设置accountRecordKey；AccountIdentityComputer对该provider返回nil且快照无email，会落入`opendesign:legacy-no-identity`。不同Mac的不同工作区因此被consumer合并。`bfc4eb8ecd914c8ca2bc763f64e9284e1f5b800f`将OpenDesign加入device-scoped分支；真实key→identities测试使用两Mac同显示名/不同workspaceID并断言身份集合相斥。最终实现符合source-scoped设计。
2. **Perplexity窗口排序错配通知marker（P2）**：组织池移至index0后，旧consumer按index选session marker，原primary移到末尾后marker反而丢失。最终`ProviderUsageSnapshot+QuotaWarnings`仅对Perplexity按稳定primary/secondary ID取原通知lane，组织/tertiary关闭marker；新增测试覆盖重排后的四个ID，修复包含在 `84410b51995415978b16f0a00fe23a4f678e9166`。
3. **新provider导致两个固定计数断言失败（P1/测试阻断）**：QuotaProviderList suffix(4)与realBorrowedMocks120遗漏新provider。最终suffix(5)包括OpenDesign、总数95/285、mock126、distinct116、current-borrowed121已对齐。
4. **影响表与源码不符及Changelog残行（P2/文档）**：z.ai CN余额实际走`Quota details/Account balance` details/CNY展示，而非providerCost.balance金额卡；最终Research已纠正。Changelog完整H1已恢复，孤立残行删除。

## 最终重点结论

- **上游完整性与fork保护**：v0.83 tag已合并；README在merge阶段保留fork，之后三处有意适配（111 provider数、WorkBuddy奖励、OpenDesign条目）与guard hash一起审查，未替换fork身份/下载入口。CI触发模型、fork发布脚本、appcast和Production容器定义没有被上游覆盖。
- **缓存与计费**：已发布fork hash `2d777571778d8f12`和历史兼容hash保留；schema3→4 home迁移保留file IDs和原生行/检查点。旧retained report因Fast重新定价需要清空，原始账本仍可用。parserLogicVersion25与生成hash双失效轴均变化；fork已存在的source-recorded/estimated语义保留。
- **Perplexity**：org-credits作为独立额外窗口；个人余额和组织余额不叠加重复算总额，组织可用时排序到耗尽个人池之前。新桥接保留稳定IDs及全部窗口，iOS摘要/列表可读取组织额度。排序与通知阈值解耦，个人primary/secondary配置不因显示位置变化而切换。
- **OpenDesign**：追加QuotaProviderList尾部保持既有订阅ID；AccountIdentityComputer非TierA，实际producer显式使用device record identity；mock两窗口、颜色、四语notes和build263均补齐。无历史接口，不制造历史；同Mac切工作区更新来源快照，跨Mac不按可编辑workspaceName自动归并。
- **其他数据变化**：WorkBuddy奖励为总额子集且到期不是reset；MiniMax无限窗口走既有详情/无reset通道；LiteLLM团队预算/余额等沿既有窗口和details；Bedrock不可用状态不写真实零。Shared wire/schema未新增field，NO_DEPLOY代码结论合理。此结论没有冒充Production export或实库收敛。
- **Mac-only决策**：Mac菜单layout/separators/compact logo、CLI SSH聚合、hooks原始planObservation、本机账号alias/提醒不直接复制为iOS交互；iOS保留独立布局、alias/通知设置和既有quota/details。选择合理，未发现必须新增wire的缺口；plugin动态logo不改变quota/provider身份。
- **版本与发布输入**：Mac0.83.0.1/176.1配已交付iOS3.3.0，iOS候选3.5.0(263)营销版本单独保持，五个target build一致。未发现越权merge/tag/live/TestFlight/schema动作的代码变化。

## 独立执行的验证

- `git diff --check origin/mobile-dev`：通过。
- `bash Scripts/check_fork_readme.sh`：通过。
- `bash Scripts/check_ci_policy.sh`：通过（Ruby ffi环境提示未影响结果）。
- `TMPDIR=<SSD Scratch> python3 Scripts/test_direct_swift_test_groups.py`：29 tests，OK。日志`reviewer-direct-groups.log`。
- `node --test Scripts/test_localization_formats.mjs`：8 tests，0 failures。日志`reviewer-localization.log`。
- 对新增通知列表和mock计数通过实际源码/断言逐项核对；未运行真实provider/cookie/Keychain读取。

## 不能由本报告声称通过的门禁

全量Mac/iOS测试、最终受影响复测、Duo姿态动作、Mac签名公证与draft附件、iOS重建Archive和Production签名校验由主代理继续执行；本报告只确认代码审查clean，不将进行中的这些动作记为pass。最初Archive source manifest标记834c，而之后iOS通知源码在84410变化，因此最终iOS候选必须用新来源重建或提供符合规范的新产物证据；主代理已知需重打。本地审查不代替GitHub当前head独立review及线程/CI gate。

## 已读取的新证据文件hash

```json
{
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.log": "07a7bce62401648e808c91dc9f0966a760202627282762ff060b401da0693ec5",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/upstream-commits.txt": "f59a632f55beca3e55391f3b260b9a89189868dce52c966b293922f4bfd144f7",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-source-manifest.json": "bfb760a7e802d3557f5cadb9c30f9a6384bae42ea01c0a2bc1c188a9d72bc377",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-archive-source-manifest.json": "66a0cad84b1ff9a98e59de46a75e4a516d848d8ff73bf14f5d1ed956ab57f0a6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/upstream-release.json": "61447f8c7f2fb33d50034f4c79416d80dd9e1c8d7ba63eba97eee594ee028094",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/upstream-files.txt": "3a0048cebcbf1f060ca93db391bea5d0427a4c4e87578b8192d8ef029bf0d7b2",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/upstream-checks.tsv": "f7e8a839afed8d5db42ef7be9a7522619b66b7f3efcfa4ce8c9fd69cc4c05d5c",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.json": "24293e2b57cef9ef120091ebb4d98ef826273376a884004a71965e925a7087d6"
}
```
