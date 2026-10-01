# iOS 2.3.0（224）App Store 草稿与 TestFlight

日期：2026-09-30（America/Los_Angeles）
状态：done（用户要求不提交审核）

## 授权及来源

用户授权创建2.3.0 App Store版本、填写全部资料、上传当前版本供TF测试，明确禁止提交审核。本次从feature/widget-provider-overview归档；源码commit `6e25a7264a691d4e56f0817f7d83eb1e4e1bea57`，tree `4a2a9359dc9914596f5c88c1b1a6d14132638487`。用户workflow skill修改未纳入commit或归档输入；没有push/merge/tag/public release。

## 上传证据

- 最终本地验证：871 unit通过；完整UI10通过/6按运行条件跳过/0失败；64渲染及真机镜像默认四项/选择两项通过，详见03-testing.md。
- 本轮 `bash Scripts/lint.sh lint` exit0，2724文件0violations；四语言translated，366源key齐备。
- xcodegen从project.yml生成，四targets 2.3.0/224。Release archive成功，App/Widget/Push签名CloudKit均Production；分发IPA主App Production且get-task-allow=false，ITSAppUsesNonExemptEncryption=false。
- CloudKit代码审计NO_DEPLOY：Shared CloudConstants/UsageSnapshot相对最新Mac正式tag无schema差异；Widget catalogue仅AppGroup本地文件。兼容16组合为明确substituted，不声称真实双Mac双iPhone推送已通过。
- Apple upload日志`Upload succeeded`/`EXPORT SUCCEEDED`；delivery/build `851f3485-20fa-4fa9-b6ea-5fccc7c322ec`，processing VALID，preReleaseVersion2.3.0，internalBuildState IN_BETA_TESTING，Internal组读回包含224。
- 原图1024无Alpha，archive图标120无Alpha且人工查看正常。
- Archive contents SHA256 `66ee10c001ebd34bfdfe965aa5cb655f26ba49017cd23e7c3293543ab38a6cb4`；上传IPA SHA256 `27753fea6f5a7b79779ca882a4c1235bb4dd118d2f24877bee7517dad990d04d`。
- 证据目录 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-2.3.0-224`（archive/upload日志、Archive、IPA、provenance、分发包检查）；ASC回读与lint日志在其父目录asc-230-* /ios230-upload-lint.log。

## App Store Connect资料

App ID6760216772，版本ID `d8de1fef-2139-44c7-837d-7433b3aa0fa6`；状态PREPARE_FOR_SUBMISSION，releaseType MANUAL，绑定224已API读回。4语言What's New及TF测试说明均已填，涵盖本轮上游成本周期/provider/警告修复及Widget多选/布局/倒计时。4语言描述/关键词/支持与营销网址保留并补齐；日语原英文描述/关键词已翻译，英文menu bar拼写修正，4语言推广文本已填，metadata存入AppStoreMetadata/2.3.0/。

现有已发布截图继承：iPhone5张，iPad3张，未伪造新截图；无预览视频（可选）。版权©2026 Yuxiao Wang；审核联系方式继承，登录要求false，备注补充Setup Guide演示路径及Mac下载/本轮功能。浏览器只读检查无红色必填错误；不点击Add for Review执行完整提交校验。

## 后续公开发布边界

当前用户TF测试。未创建App Review或external beta review submission。正式提交前仍应将上述archive源与最终clean-reviewed发布输入比对；若影响代码/资源/config/version的review修复发生，需新build，不能用之后干净review证明旧包已包含修复。

## 最终页面复核

Aside只读打开224构建及2.3.0版本页：构建页Apple处理后的图标是蓝底白色代码符号/两条横线，已人工查看构建页截图；版本页绑定224且Save灰色、无未保存修改、无红色错误，状态仍Prepare for Submission。截图 `/Users/yuxiao/.aside/u/0/sessions/2026-09-30_zfKuTX3z47ThujTu/tmp/build224_page.png`；审计日志BuildScratch `asc-230-browser-final.log`。服务器iconAssetToken由altool VALID回读，与构建页展示共同完成第三层图标检查。四语言TestFlight说明通过API全部回读（浏览器仅查看英文）；Internal组已有224，不触发external beta审核。
