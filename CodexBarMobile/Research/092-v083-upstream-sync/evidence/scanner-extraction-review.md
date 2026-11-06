# parser复杂度提取、plugin测试拆分与精确架构指纹独立复审

Reviewer: /root/upstream_audit
Reviewed HEAD: `c8f491f90bc4720b73d9d7f22bd55b64eceb3379`
Result: clean（源码/测试已在审查期间提交为c8f491f90；当前dirty仅三份已审文档，没有未解决finding）
Base-to-worktree binary diff SHA-256: `937bab95cfa3e5ae55fea00957691b1ab4e95c9b43de040e9a13a6d9fe9072a4`
HEAD后dirty diff SHA-256: `c67e65c33e809f8dc9bdcb620290803d242bdb70d4c31a6cd7a1328bc1c6d3c4`
新Research文件指纹见末尾。已核对c8f491f90的五文件提交包含当前已审source/test及拆分新文件；剩余dirty为Research01、Research索引和CloudKit审计。后续提交必须包含相同已审内容，任何新实质性差异另审。

接续此前完整候选审查，重新核对当前候选文件清单和所有新增变化；重点读scanCodexFile原始与提取后控制流、测试拆分前后完整extension、架构allowlist与实际source锚点。Research01/索引/CloudKit审计修改也已读，当前验证仍in-progress，不能据此声称打包/UI/全量门禁完成。

## 首次提取的严重回归已修复

审查最初发现canReadCodexRecoverySource错误地只返回needsRecovery布尔值，而caller无条件guard：普通无recovery文件会被全部defer，需要recovery但不可读的文件反而放行。已即时通知主代理；主代理确认替换未命中并停止该6f2a17b6f981b2ad测试尝试，没有提交或打包。该错误版本的结果不能作为有效验证证据。

随后独立重新读当前精确源码，helper现为：

```swift
let needsRecovery = context.sourceRowRecoveryPathKeys.contains(self.codexPathKey(fileURL))
    || cache.files[metadata.path]?.codexPendingSourcePricing != nil
guard needsRecovery else { return true }
return metadata.fileId != nil && FileManager.default.isReadableFile(atPath: metadata.path)
```

这与原始“只在需要recovery时guard fileId/readability”精确等价：正常文件直接放行，不增加readability调用；只有needsRecovery且fileId非nil才检查readability，短路顺序一致；caller失败时仍把同一metadata.path加入deferredCachePaths并return deferred。archived提前返回、metadata采样、cancellation、后续defer/alias/history更新时点均未移动。

独立16组布尔组合校验originalDeferred == !helperAllow全部成立。该检查是提取控制流等价证据，不替代实际scanner回归。当前新hash为c546274ea6111fa7，`regenerate-codex-parser-hash.sh --check`实际通过。parserLogicVersion仍25，相对已发布24已递增；本次未发布候选内行为等价重构无需再升26，最终产物必须使用c546而非旧6f2a。

## Plugin测试拆分

新UserProviderPluginRecoveryAndCLITests.swift的两个extension body（恢复opaque settings/secrets、CLI窗口标题和JSON）与原文件被移走的body逐字一致。两文件合计@Test标记仍37，无测试删除。JavaScriptCore条件编译保留，extension属于原UserProviderPluginTests类型，所以原@Suite(.serialized)语义继续生效。

javaScriptPlugin helper仅在测试target内从private放宽为internal，以便另一文件extension调用，不改变生产API或凭据行为。原Fixture/RecordingTransport复用仍是隔离合成数据。此次拆分合理解决严格file-length gate。

## Architecture精确合同更新

- AccountIdentityComputer case锚点以codex为0，新增opendesign在+8行；expectedProviderIDs增加该单一ID、referenceCount59→60、fingerprint opendesign@8，吻合实际非TierA分支。
- SyncCoordinator source key以case wayfinder为0，新增opendesign在+11行；count8→9、fingerprint opendesign@11，reason明确不同Mac来源隔离。真实producer key回归仍存在。
- 没有改变scanner/cluster阈值、跳过规则或用通配例外弱化生产约束。属于对已实现且已审source形状的有意精确更新，合理。

## 文档/打包边界

Research影响表把CLI inventory、Dashboard授权URL、HTTP serve、Commander、Sparkle等Mac-only理由改为具体实际消费者路径，比模板化hook说明更准确。新增CloudKit审计仍NO_DEPLOY且明确没有实库schema/export/收敛验证，符合最终代码无schema变化。

iOS shipped source不涉及这次Mac scanner及测试修改，之前Archive353项输入等价仍适用。Mac成本parser源和hash已变，旧Mac测试/签名来源不能冒充当前产物；完整测试及打包应使用修正后c546来源。此前完整候选finding（OpenDesign、Perplexity旧reader、DST、home/revision14、cleanup、英文notes）仍已解决。

## 本次实际核对

- parser hash --check：通过，c546274ea6111fa7。
- git diff --check origin/mobile-dev：通过。
- 两段移动测试body原文一致；@Test计数37→37。
- guard16组布尔控制流等价；具体读取时点/短路路径已源码审查。

未再起xcodebuild或真实provider/cookie/Keychain探测。尚在执行的focused lint/tests、最终Mac完整binary全量、签名公证/draft、Duo/UI及远端当前head review不能由本报告clean推断通过。

## 审查时新文件指纹

```json
{
  "CodexBarMobile/Research/092-v083-upstream-sync/03-testing.md": "74b803b3c6c388476e291e8221dab89009b550b1bc4f40eea14450ba2459af5b",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/cwl-dst-diagnosis.md": "e3c27fb96be220ef9b3cb5f149bdfee780414ba3c8d6c3ae6bc3dff187ef9e91",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/fork-parser-diagnosis.md": "c492712ef1ccfdc8135a8494fd9b6b1b74f6e96c676fee6473acd9432449df9e",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-archive-zip.json": "9ca0d83cf527e6dcf286f01ef6c5021675cfa88652e7367b1f5e664de0517ce4",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-reviewed-archive-verified.json": "fbcbac8745f8e5f795ff414a074963cecde36503f88e158d9de0223300477412",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/ios-reviewed-input-manifest.json": "cb6788fa994ac51cbbf3a1bbeaf8a23925bc81b255e952378471b7a8e7233d7c",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/local-review-23ff6887d.md": "c608ff74cd7a36d2a0bd9a6240582c7a703cb65b0654530bc371405d500a7f3f",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/local-review-84410b519.md": "cdd990675cca01ce73eb725c261aa2397421c4d0129fc2b1e6a61d478380db58",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.json": "24293e2b57cef9ef120091ebb4d98ef826273376a884004a71965e925a7087d6",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-matrix-wire.log": "07a7bce62401648e808c91dc9f0966a760202627282762ff060b401da0693ec5",
  "CodexBarMobile/Research/092-v083-upstream-sync/evidence/wire-source-manifest.json": "bfb760a7e802d3557f5cadb9c30f9a6384bae42ea01c0a2bc1c188a9d72bc377"
}
```
