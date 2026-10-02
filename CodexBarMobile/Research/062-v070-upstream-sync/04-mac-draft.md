# Mac 草稿前置条件与凭证边界

Status: `in-progress`

## 当前执行顺序

按用户纠正后的顺序：iOS 实现、本地测试与兼容验收 → GitHub PR + 当前 head 的 Codex CR → 修复、复测并通过 review gate / PR Fast Checks → 获准合并到 mobile-dev → Mac 签名、公证和 draft。不得先创建一个 placeholder-source draft 再用后续 review 补源码来源。

Goal 明确禁止未经授权的 push、merge、tag publish。此前 push/PR 授权问题尚无明确回复；自动目标继续运行不是授权。凭证使用另外按 Goal 确认。当前只做本地准备，没有 GitHub draft URL、签名资产或公证结果。

## 单版本候选

- 上游 train：v0.69.0–v0.70.0，关联 open issue #166，draft 不关闭 issue。
- Mac MARKETING_VERSION `0.70.0.1` / BUILD_NUMBER `161.1` / MOBILE_VERSION `2.3.0`（已发布配套；iOS 2.4.0尚未ship）。
- Sparkle `161.1.2.3.0`，候选 tag `v0.70.0.1-mobile.2.3.0`。
- ZIP `CodexBar-0.70.0.1-mobile.2.3.0.zip`，同名 `.dSYM.zip`。
- 正式打包必须记录经过 PR/CR 后合并的 source commit、嵌入 commit、输入路径 diff、ZIP SHA256 和 dSYM UUID。当前任务 HEAD 不能提前充当尚不存在的合并来源证据。

## 已有本地预检

Changelog validator、fork release Markdown/HTML、appcast monotonic 预检通过；scratch 为 BuildScratch/CodexBar/upstream-v070/mac-draft-notes.*。完整 Mac 回归 mac-full-r5 exit0：1520 selections、137组首轮通过、0 retries/timeouts；root lint-r12通过。unsigned universal Release compiler 预检 source c0343b3a2：arm64+x86_64/minOS14.0，dSYM UUID 匹配，见 mac-release-preflight-artifacts.json。后续 iOS/文档检查点不能取代正式签名时的来源核对。

2026-10-01此前读取 fork 最新8 releases均为正式发布、最新为v0.68.0.1-mobile.2.3.0；这是历史查询，正式创建前须重新查询同 tag，避免重复创建。

## 仍待证明

iOS/Widget 剩余验收见07-acceptance-audit.md。GitHub exact-head CR 与全部 thread resolved、PR gate、合并和适用的 Final CI 均无完成证据。上游 v0.70 的 heavy checks cancelled，不能据发布成功复用为 heavy CI 通过；按 fork verifier 回退适用 Final CI。

签名 universal app、Production entitlements、公证/Gatekeeper、ZIP/dSYM hash、GitHub draft URL 与资产 digest/size、候选 appcast signature/URL/length 都尚未生成或验证。不得据 compiler 预检宣布用户可安装。

## 正式执行边界

TMPDIR、CODEXBAR_RELEASE_STAGE_BASE、所有 archive/export/temp 使用 StudioSSD BuildScratch，执行前重验挂载 UUID 与可写。release.sh 顶部会加载 Sparkle/全局ASC凭证；目前未调用，也未读取凭据内容。获准后仅执行已审定的本轮签名、公证/draft 范围，不运行 --finalize，不发布 live/feed，不上传 TestFlight。脚本可能创建/推送 tag，必须在调用前单独核对授权和所选模式。

此前研究的 --draft-no-tag-push / mobile-dev placeholder 路径只属于历史方案，已不作为当前执行计划。发布清单要求从 reviewed/merged mobile-dev 出 Mac release；应以真实来源取代 placeholder。
