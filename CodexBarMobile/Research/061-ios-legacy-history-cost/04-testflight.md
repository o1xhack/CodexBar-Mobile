# 2.3.0 (225) 上传与草稿记录

Status: `done`
Date: 2026-09-30

## 授权与代码来源

沿用用户明确要求上传2.3.0、填写全部说明、不要提交审核的范围。
功能修复、四语言资源、版本配置均来自本地修复分支；只有纯文档在上传后继续回写。
未push/merge/tag，用户自己的workflow skill修改未纳入提交或打包输入。

- Branch: `fix/ios-230-legacy-mac-compatibility`
- Source commit: `90805d80003a494247365b8fdf87a1b2da072794`
- Source tree: `2b3862e90e2f92a9ee52a6fa7a3ec6424b45fd16`
- Archive contents SHA256: `56604a90418aba3cd229bcf0aec0098cb2f0a646efc9ac2b8c047bba31bc69d2`
- Uploaded IPA SHA256: `26672f3072dab1443b4326299bdb037d0d191a7f11b609c112363e85c978b399`

## 构建与上传证据

产物路径：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-2.3.0-225/`。
Archive DerivedData：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/LegacyHistory225Archive`。

- `xcodebuild ... -configuration Release -destination generic/platform=iOS -archivePath ... -allowProvisioningUpdates -packageAuthorizationProvider netrc archive`：ARCHIVE SUCCEEDED。
- `xcodebuild -exportArchive ... -exportPath ... -allowProvisioningUpdates -packageAuthorizationProvider netrc`：Upload succeeded / EXPORT SUCCEEDED。
- 主App与两个extension，Archive及实际上传IPA均为2.3.0 (225)、CloudKit Production。
- 三层图标人工查看完成：1024源图、Archive编译120图、altool iconAssetToken对应Apple CDN152图；前两层无Alpha。
- 完整单测878项、UI3项、lint、Release Simulator、实机证据和替代矩阵见03-testing.md。

## ASC 回读

- Build/delivery ID: `c05fa7bd-d448-480d-9570-4e561d08ce71`。
- Processing: `VALID`；internalBuildState: `IN_BETA_TESTING`。
- 原内测组 `eb0df43e-af6b-42ad-a429-efe2f5478702` 的build relationship已包含225。
- 尝试POST内测组关系返回422（该组不允许手动添加），随后readback确认自动分发已经包含225；无须改组或请求外测审核。
- App Store 2.3.0 version ID: `d8de1fef-2139-44c7-837d-7433b3aa0fa6`。
- Build relationship回读225；state仍为`PREPARE_FOR_SUBMISSION`，manual release保持。
- en-US/zh-Hans/zh-Hant/ja的What’s New与仓库release_notes.txt逐字回读匹配。
- 四语言beta测试说明包含本次旧Mac/365天回归测试重点，逐字回读匹配。
- 未提交App Review或外测审核，未发布live release；224保留。

## 已知验证范围

Air真实旧双Mac同步已验证；另一物理iPhone、完整四设备升级组合和后台push仍为替代模型测试。
内测上传按独立beta流程进行，本地多轮agent review无阻塞，不声称已有GitHub exact-head PR review。
后续公开发布须按repo review/provenance gate执行；本次上传不能替代该gate。
