# iOS原生回归、Research证据与Mac验包工具独立审查

Reviewer: /root/upstream_audit
Reviewed source HEAD: `c8f491f90bc4720b73d9d7f22bd55b64eceb3379`
Current tracked dirty documents SHA-256: `3297592dc80525390f8b2419d9975717f6f37fa05651b443827e3fc6bd7dd8ad`
源码结论：clean，无新增实质性源码finding。
验证记录结论：Duo/普通设备证据与替代矩阵边界准确；SpringBoard gate应适用且仍须完成后补证据，不能按现有豁免文字通过。

接续完整候选源码审查，重新读Research00/01/03、相关源/测试、XCResult摘要、截图来源manifest和verify_mac_artifacts.py；未修改source或操作设备。

## 原生iOS证据核对

实际读取汇总JSON：Duo fold1、inner landscape3、inner portrait2、outer landscape1、outer portrait最终2，最初错误姿态run另有1通过/1失败，总计10成功执行及1失败；失败未被覆盖或冒充通过。iPad26.5和SE26.5各3通过。普通17e最终汇总1374 passed/1 skipped，与1300 Swift Testing+75 XCTest（含1skip）的日志一致。

六张PNG逐项SHA全部匹配manifest，最大1711544 bytes；manifest保留test identifier、device、timestamp和failure关联。独立查看inner Summary截图：独立卡片网格、筛选和native chrome可见；查看folded share draft：Heatmap选择、范围/Provider、取消及Share Image控件可见，没有以产品设计图代替实际App。不能由PNG长宽判断Duo当前折叠/朝向，文档以实际viewport/assertion/原生Device Hub与后续action为依据，区分方式合理。

Duo bootstatus Data Migration Failed、错姿态失败和automation取消均明确保留；本报告没有把这些失败或setup状态当OS正常证明。全部数据为合成preview，不是实际CloudKit用户账本。

## SpringBoard门禁发现与处理

Research03原先认为只新增provider配色/label而没有布局/intent/mode实现变化即可豁免，范围判断不成立：project.yml第86行把ProviderColorPalette编入Widget extension，CodexBarWidgetView第1004/1643行及WidgetActivityView第111行实际调用；新增OpenDesign palette会改变WidgetKit渲染。

RELEASE-CHECKLIST第29行明确触发于“widget布局、配置intent、mode/color style **或 WidgetKit rendering**”，因此完整RenderMatrix通过后仍需真实SpringBoard编辑面板、确认配置选项、切换一个mode并截图。已通知主代理，主代理接受并开始在自有空闲SE26.5运行现有opt-in SpringBoard gate，计划移除豁免文字。该动作进行中，本报告不能提前标通过；完成后需实际结果/截图和source关系。

## iOS影响审查

未发现遗漏的必要wire变化。OpenDesign quotaLimit/quotaUnit/组织标签走既有optional字段与device record身份；Perplexity wire恢复native槽，组织池追加不破坏旧reader index；WorkBuddy奖励不与主额度重复累计、到期不伪作reset；MiniMax不可用/无限详情与Bedrock unavailable保留意义。Mac-only CLI/SSH/hook/menu布局、原始planObservation、本地alias/提醒均有明确消费者理由，不把Mac设置复制成手机交互。

旧iOS的OpenDesign通知订阅列表没有新zone，安装新3.5后才注册通知；旧reader的generic数据展示与新provider通知能力应在交接区分。这是正常客户端能力边界，不需更改wire或强造旧客户端订阅。

## 16组合替代路径

16个case全部列明substituted；writer为两个deviceID、reader是独立进程，64reads/32真实consumer merge来源/hashes留存。文档清楚说明不验证CloudKit写入、APNs、网络、SwiftData独立缓存收敛或实体2Mac/2iPhone，未把source/序列化检查当实体设备收敛。真实OpenDesignproducer另有key测试，未以手写wire身份替代生产映射。这些边界合理。

## verify_mac_artifacts.py审查

脚本hash：`88c054897fdeed2231d280ab4425127a3af4ca7766b0e99be743b3a063345e05`。

工具限定本轮SSD staging与预期ZIP/dSYM，检查ZIP内容前缀和路径、真实source Info字段与manifest、版本/companion/feed、双架构、App/dSYM UUID一致、四个executable的Developer ID team/runtime/minOS、codesign/stapler/distribution、Production entitlement与profile的应用ID/容器/环境/有效期、AppGroup声明及runtime选择一致；最后逐项重算输入manifest并记录ZIP/binary hashes和published=false。没有把draft占位target当source SHA。

App和CLI resource smoke在各自main的最早分支、普通Settings/provider/UI初始化之前执行；该脚本使用env-i、独立HOME/CFFIXED、禁网络/用户目录/Cloud/prefs sandbox和Keychain suppression标志，目的为resources/group诊断，不是live provider probe。runtimeGroup diagnostic只证明真实签名声明和运行时group选择一致，不能额外声称做了真实用户Group容器业务读写；目前Research没有这种声称。

脚本是验证逻辑审查，尚未执行/完成的Mac签名、公证、Sparkle候选校验、draft附件及最终artifact provenance仍须由实际输出记录确认；不能因为脚本assert存在就标为pass。当前Mac最终全量/签名构建仍进行中，本报告未等待或抢跑。

## 其他边界

c8以来没有iOS shipping source变化，既有353输入等价证明仍适用；最后打包/文档source绑定应以最终记录为准。截图/XCResult要复制到项目长期证据目录，不能只依赖7日可清理Scratch；当前Research已明确完成时归档。最终PR review仍必须针对current head完成，所有本地clean报告不替代远端gate。

## 已读取证据指纹

```json
{
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/se-265-ui-summary.json": "e51d6c317c56f2eb83af0fc95cba6a453c62fa88645a64c81aabb1d1a7e7edbd",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-outer-portrait-final-summary.json": "5818dd4e40a693b9637019ff1529cd76d646d3bec92adcbb0ee19e1de2a2375d",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/final-source-review-e41a7b363.md": "3eabce9a73739f996bdfa8402ff502877492dbdbdecbb3d02a5433fef62780e6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/local-review-23ff6887d.md": "c608ff74cd7a36d2a0bd9a6240582c7a703cb65b0654530bc371405d500a7f3f",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/mac-full-summary.json": "fd4b84900dd529d5073b4a81c4fec876771f41beab34707295d6246b937b033e",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-outer-landscape.png": "edbb4f3e7d748c6c1a23987e40edd87204e65bbe82ba1259a06193a9a2f213ff",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-unit-final-summary.json": "20fe74bc34c814c660221e0aed55b319f2ca21f1a571bf323c997f03228c25e8",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.log": "07a7bce62401648e808c91dc9f0966a760202627282762ff060b401da0693ec5",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-outer-portrait-summary.json": "7126bcae8c80e11f384129255bae2677a872b765efae7f57329d79f4bd33fc0a",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-unfolded-draft.png": "9ca2b9483bc09f345927f0c41a2da4a3f66434b625dc57c991e9a3e768406e4c",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-inner-landscape-summary.json": "cdfaa2eff14ca3e6318cff0c09a35e54d7bddf59472d13a05e7e5560dd06eb0e",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-reviewed-archive-verified.json": "fbcbac8745f8e5f795ff414a074963cecde36503f88e158d9de0223300477412",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-folded-draft.png": "8959a16930c61c1343bf376a0b4cd3442cc3fb997521aaf0ba6e7054aa2bf7ed",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/upstream-commits.txt": "f59a632f55beca3e55391f3b260b9a89189868dce52c966b293922f4bfd144f7",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/mac-draft-source-manifest.json": "2c1953dccd3235fdba33931824482f105de876c43f0c25e6578e0dff1090fd81",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-source-manifest.json": "bfb760a7e802d3557f5cadb9c30f9a6384bae42ea01c0a2bc1c188a9d72bc377",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-inner-landscape.png": "3c0c59bc32ddb14608c59f9ecdfa580d3e5cddda693484dbf170e159b0de1dcf",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-inner-portrait-final-summary.json": "561db4a458a82b988729f9e45e97e44143124df57cda6c01e471601d26047532",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-screenshot-manifest.json": "d4ae7848a409ccae860bab9300aaa3745fafe3bd44bc43b61eca3bee94e601e7",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/fork-parser-diagnosis.md": "c492712ef1ccfdc8135a8494fd9b6b1b74f6e96c676fee6473acd9432449df9e",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-archive-zip.json": "9ca0d83cf527e6dcf286f01ef6c5021675cfa88652e7367b1f5e664de0517ce4",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/local-review-84410b519.md": "cdd990675cca01ce73eb725c261aa2397421c4d0129fc2b1e6a61d478380db58",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/cwl-dst-diagnosis.md": "e3c27fb96be220ef9b3cb5f149bdfee780414ba3c8d6c3ae6bc3dff187ef9e91",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/upstream-release.json": "61447f8c7f2fb33d50034f4c79416d80dd9e1c8d7ba63eba97eee594ee028094",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/upstream-files.txt": "3a0048cebcbf1f060ca93db391bea5d0427a4c4e87578b8192d8ef029bf0d7b2",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/upstream-checks.tsv": "f7e8a839afed8d5db42ef7be9a7522619b66b7f3efcfa4ce8c9fd69cc4c05d5c",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-reviewed-input-manifest.json": "cb6788fa994ac51cbbf3a1bbeaf8a23925bc81b255e952378471b7a8e7233d7c",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/scanner-extraction-review.md": "013e3ed30a12f4c5c5344ffec2d0e04f214f0a160add8b4ec2f732ebbd76bdce",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.json": "24293e2b57cef9ef120091ebb4d98ef826273376a884004a71965e925a7087d6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/gatekeeper-literal-review.md": "9ff051c3e7df28aafebb69abf1150249acfa4c3d7642f95f1f93de16aa57ecfe",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-inner-portrait.png": "f40b7f1ea71e44a5ba57968dc5839eab92b036ad7517eca7cd06acbd2b149ec4",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ipad-265-ui-summary.json": "7928820cb1baa00b6a32a7eee56f6bfb832a5b446dc20dd02668129add72feaf",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-outer-portrait.png": "85877e5f0928fcc2c18ed3a7416696df2c862c64a799670432de023590a2229b",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-fold-summary.json": "8d3845374aa2012473cc7c76a3dc0c2f8303a406285b1527326efbab09a5ae9b",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-outer-landscape-summary.json": "260c6d3a9b6362f44c361454a385af9a860d3848dbf39f33e897dd4443609bc3"
}
```
