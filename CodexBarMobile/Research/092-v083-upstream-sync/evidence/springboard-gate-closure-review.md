# SpringBoard原生门禁关闭与iOS候选复审

Reviewer: /root/upstream_audit
Reviewed source: `c8f491f90bc4720b73d9d7f22bd55b64eceb3379`
Tracked Research/docs dirty diff SHA-256: `fcb1b435351617a608aaba46c27fb8522469cce733cd956185b942ff6efd36b0`
Result: source + iOS gates clean；前次SpringBoard验证finding已关闭。Mac最终签名/公证/draft附件和远端PR审查仍pending。

## 真实SpringBoard行为

独立打开并目视检查5个关键原始PNG：系统编辑面板before显示“概览”，picker含概览/服务商详情/今日费用/同步状态四种mode，selected显示“今日费用”，真实Home Screen上的CodexBar widget显示今日$19.42和822.0K tokens，关闭并重开editor仍读回今日费用。系统SpringBoard背景/status bar可见，是原生widget配置，不是App内Settings preview。另有第6张Home原图；全部6张文件的SHA重算与manifest匹配。

这个证据满足RELEASE-CHECKLIST要求的打开编辑面板、确认配置项、切换mode并截图。之前完整WidgetRenderMatrix/WidgetSnapshotBuilder通过继续有效；共享palette的原免测理由已移除。

XCTest初始setup因gallery StaticText非hittable失败，第二次因等待SpringBoard idle卡住被取消；文档正确保留为失败/取消，没有用native操作成功伪造自动测试pass。当前结果应称native/manual gate PASS。

## 已安装Widget来源

manifest目前记录8个Debug二进制（App/Push/Widget/WidgetOptions各exe与debug dylib）与最终ios-derived产品一致。独立在Shutdown设备423B1FAB-7B97-44F4-A865-B0A49B4F3866的Bundle/Application目录中按Info.plist bundleID定位唯一已安装App；没有重新启动设备或修改容器。对与本门禁直接相关的四个extension文件重新计算SHA并与ios-derived读取结果比较，全部相等：

| 角色 | 文件 | SHA-256 |
|---|---|---|
| Widget | executable | 21139bfc1996da774fcbd6d67e11fa671b66a3f7be1450f5bd13622aeeb99346 |
| Widget | debug dylib | 16dd372a688b4c2277e64d26818a659631d2efb160ba2567503a14cfddf75233 |
| WidgetOptions | executable | 1acbc3bd21fbfd33ebd264edd936492332ae066abb6af1ff4cbaf4f52935cfb2 |
| WidgetOptions | debug dylib | 8a1305e7e3e5ceee4aedc471588da03fc1cfe11874c6c24688669cbc973cb3dd |

这补齐了只hash主App不足以绑定实际Widget运行代码的证据缺口。App/Push其余hash由主代理记录，未把本人未单独重算的项描述为本人执行。

## 当前Research03/04复审

03记录Mac最终1869/89 exit0、iOS1300 Swift Testing+75 XCTest、Duo10成功+1错姿态失败、SE/iPad各3、SpringBoard native成功及所有失败保留，并将16组合严格标substituted；源代码没有新增变动。04正确区分Mac c8 source、iOS实际23ff Archive与353输入等价、Development签名本地Archive、未上传ASC/未正式发布。Mac初次缺gitignored provisioning导致的停步不等于签名成功，最终重跑产物仍须单独验收。

未见其他缺失material iOS影响或当前源码finding。旧iOS只能在升级新通知清单后订阅OpenDesign zone属于正常版本能力边界；Perplexity旧reader native槽兼容修复持续有效。真实provider/cookie/Keychain probe、实库CloudKit/APNs/2Mac2iPhone收敛未验证，现有文本没有冒称。

当前source+iOS验证已可判clean。签名Mac artifact、draftID/target/附件大小与hash/Sparkle、公证及最后全候选/PR当前head审查尚需补齐；此报告不是整个Goal完成或merge/live授权。

## 新证据指纹

SpringBoard manifest SHA-256: `0f732efb6ffd7bd1c3b1b2bb16d0ae0a1b8387eda3c17f299ec3979412144196`

```json
{
  "CodexBarMobile/Research/092-v083-upstream-sync/03-testing.md": "c59767d98ba428a2e4267115d118ce9768aa32f9ff388c0d88d4b8e105926975",
  "CodexBarMobile/Research/092-v083-upstream-sync/04-candidate-handoff.md": "0a3057ffd207dad6062ecfd8893ae052629ea0daab1a99c46d818178dca7965b",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/cwl-dst-diagnosis.md": "e3c27fb96be220ef9b3cb5f149bdfee780414ba3c8d6c3ae6bc3dff187ef9e91",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-fold-summary.json": "8d3845374aa2012473cc7c76a3dc0c2f8303a406285b1527326efbab09a5ae9b",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-folded-draft.png": "8959a16930c61c1343bf376a0b4cd3442cc3fb997521aaf0ba6e7054aa2bf7ed",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-inner-landscape-summary.json": "cdfaa2eff14ca3e6318cff0c09a35e54d7bddf59472d13a05e7e5560dd06eb0e",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-inner-landscape.png": "3c0c59bc32ddb14608c59f9ecdfa580d3e5cddda693484dbf170e159b0de1dcf",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-inner-portrait-final-summary.json": "561db4a458a82b988729f9e45e97e44143124df57cda6c01e471601d26047532",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-inner-portrait.png": "f40b7f1ea71e44a5ba57968dc5839eab92b036ad7517eca7cd06acbd2b149ec4",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-outer-landscape-summary.json": "260c6d3a9b6362f44c361454a385af9a860d3848dbf39f33e897dd4443609bc3",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-outer-landscape.png": "edbb4f3e7d748c6c1a23987e40edd87204e65bbe82ba1259a06193a9a2f213ff",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-outer-portrait-final-summary.json": "5818dd4e40a693b9637019ff1529cd76d646d3bec92adcbb0ee19e1de2a2375d",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-outer-portrait-summary.json": "7126bcae8c80e11f384129255bae2677a872b765efae7f57329d79f4bd33fc0a",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-outer-portrait.png": "85877e5f0928fcc2c18ed3a7416696df2c862c64a799670432de023590a2229b",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-screenshot-manifest.json": "d4ae7848a409ccae860bab9300aaa3745fafe3bd44bc43b61eca3bee94e601e7",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/duo-unfolded-draft.png": "9ca2b9483bc09f345927f0c41a2da4a3f66434b625dc57c991e9a3e768406e4c",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/final-source-review-e41a7b363.md": "3eabce9a73739f996bdfa8402ff502877492dbdbdecbb3d02a5433fef62780e6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/fork-parser-diagnosis.md": "c492712ef1ccfdc8135a8494fd9b6b1b74f6e96c676fee6473acd9432449df9e",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/gatekeeper-literal-review.md": "9ff051c3e7df28aafebb69abf1150249acfa4c3d7642f95f1f93de16aa57ecfe",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-archive-zip.json": "9ca0d83cf527e6dcf286f01ef6c5021675cfa88652e7367b1f5e664de0517ce4",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-regression-evidence-review.md": "0d48d8f1207edda1d11ebd503163ff3384a7e438d6ca56ef9fa0101d5062b574",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-reviewed-archive-verified.json": "fbcbac8745f8e5f795ff414a074963cecde36503f88e158d9de0223300477412",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-reviewed-input-manifest.json": "cb6788fa994ac51cbbf3a1bbeaf8a23925bc81b255e952378471b7a8e7233d7c",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-unit-final-summary.json": "20fe74bc34c814c660221e0aed55b319f2ca21f1a571bf323c997f03228c25e8",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ipad-265-ui-summary.json": "7928820cb1baa00b6a32a7eee56f6bfb832a5b446dc20dd02668129add72feaf",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/local-review-23ff6887d.md": "c608ff74cd7a36d2a0bd9a6240582c7a703cb65b0654530bc371405d500a7f3f",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/local-review-84410b519.md": "cdd990675cca01ce73eb725c261aa2397421c4d0129fc2b1e6a61d478380db58",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/mac-draft-source-manifest.json": "2c1953dccd3235fdba33931824482f105de876c43f0c25e6578e0dff1090fd81",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/mac-full-summary.json": "fd4b84900dd529d5073b4a81c4fec876771f41beab34707295d6246b937b033e",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/scanner-extraction-review.md": "013e3ed30a12f4c5c5344ffec2d0e04f214f0a160add8b4ec2f732ebbd76bdce",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/se-265-ui-summary.json": "e51d6c317c56f2eb83af0fc95cba6a453c62fa88645a64c81aabb1d1a7e7edbd",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/springboard-native-gate.json": "0f732efb6ffd7bd1c3b1b2bb16d0ae0a1b8387eda3c17f299ec3979412144196",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/widget-editor-before.png": "3a58ac0a3fef8d41f47da7bb800ac764698bb7b81c40e91bff65d1e0ffc751d6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/widget-editor-reopened.png": "ba7c4b977328da7618f65ea139e640a7d2c88a95656d938535a0caaf0faa8360",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/widget-editor-selected-final.png": "4fe8210f7e1830d3f1732aa626d2934c089c12a497a775c466afb35d2cf9876c",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/widget-home-today-cost.png": "ff393c4309331b13a7038766213a15c909f281ee256a80d9488594e3b250b350",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/widget-home.png": "543f633baf25707b03a98a7a709b05ea12d3cbf6b84fe341a84a98e3d6153e7d",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/widget-mode-picker.png": "c273d76c3a60d37026c76e3a6bbdd6643e5ba5cd2766dd6dc0f73a51a1f1bb0e",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.json": "24293e2b57cef9ef120091ebb4d98ef826273376a884004a71965e925a7087d6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.log": "07a7bce62401648e808c91dc9f0966a760202627282762ff060b401da0693ec5",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-source-manifest.json": "bfb760a7e802d3557f5cadb9c30f9a6384bae42ea01c0a2bc1c188a9d72bc377",
  "CodexBarMobile/Research/092-v083-upstream-sync/tools/verify_mac_artifacts.py": "88c054897fdeed2231d280ab4425127a3af4ca7766b0e99be743b3a063345e05"
}
```
