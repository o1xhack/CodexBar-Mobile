# Mac 草稿准备与凭证边界

Status: `in-progress`

## 候选

- 仅一个上游train：v0.69.0–v0.70.0，关联open issue #166。
- MARKETING_VERSION `0.70.0.1`；BUILD_NUMBER `161.1`；MOBILE_VERSION `2.3.0`（最新已发布配套iOS；2.4.0尚未ship）。
- Sparkle `161.1.2.3.0`；tag候选`v0.70.0.1-mobile.2.3.0`。
- artifacts：`CodexBar-0.70.0.1-mobile.2.3.0.zip`与同名`.dSYM.zip`。
- 已有Mac/Shared源码checkpoint `392f794a6`。最终打包source应为草稿说明整理后clean HEAD，记录Info.plist embedded commit与输入路径diff、ZIP SHA256及dSYM UUID。

## 已验证

`Scripts/validate_changelog.sh 0.70.0.1`通过。`changelog-to-html.sh`输出当前fork说明（包含两版上游主要用户变化，避免只提桥接）。`ensure_appcast_monotonic appcast.xml 0.70.0.1 161.1`通过。Markdown/HTML预览位于BuildScratch/upstream-v070/mac-draft-notes.*。

当前release.sh `--draft-no-tag-push`设置DRAFT_NO_TAG_PUSH=1，跳过tag创建/推送和orphan draft删除；GitHub target暂用mobile-dev，仅作为placeholder，notes记录本地source commit。该target不能作为源码来源证据，live前必须另行授权merge/push/tag并retarget reviewed commit。

2026-10-01读取fork最新8个releases均为正式发布，最新v0.68.0.1-mobile.2.3.0。正式调用前仍需查询候选同tag draft，避免重复创建。未执行GitHub draft写入。

## 执行时设置

PATH使用Homebrew Python3.14；TMPDIR与CODEXBAR_RELEASE_STAGE_BASE均位于`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070`。不运行`--finalize`，不设置RUN_SWIFT_TEST=1重跑裸swift test；本轮完整测试通过repo安全test_environment与suite runner验证。

脚本顶部会加载本地Sparkle/全局ASC凭证，并使用Developer ID签名、公证。Goal要求遇到发布凭证先询问，因此当前未调用release.sh或sign-and-notarize.sh，也未读取凭证内容。完成当前Mac测试、草稿说明和发布输入核对后，再请求这一具体凭证使用范围。独立review与GitHub PR gate不同，draft不是公开release，issue保持open。

## 仍待证明

完整Mac回归终态；universal Release构建；签名/公证/Production entitlements与Gatekeeper验收；ZIP/dSYM对应及SHA256；tagless GitHub draft URL、asset digest/size回读；candidate appcast签名/URL/length验证（不发布现有feed）。

## 发布配置预检

2026-10-01 universal Release compiler预检通过，source `c0343b3a2`；三个实际product均arm64+x86_64/minOS14.0且dSYM UUID匹配（详情见03-testing与BuildScratch/mac-release-preflight-artifacts.json）。尚未生成可安装签名bundle或draft，不把预检当作发布完成；正式脚本仍需完整Mac回归通过与Goal规定的凭据使用确认。
