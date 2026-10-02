# 明确授权的 Codex 独立子线程审查

默认继续使用 GitHub Codex connector 的审查。只有用户明确要求独立 Codex 子线程执行 PR Code Review 时，才能使用本替代流程；额度耗尽、CI 通过或主代理自查本身都不构成授权。

独立子线程必须审查完整 PR diff 以及相关调用、配置、测试和发布输入，返回完整报告。所有 finding 必须修复、测试，并在每次 push 后重新审查新的完整 head。主代理不能把自己的结论写成子线程报告，也不能伪造 connector 的 clean 文案。

完成审查后，保存真实报告到可追溯的文件，计算该文件的 SHA-256，核对报告中的审查 commit 与 GitHub 当前 `headRefOid` 完全相同。通过 GitHub PR review API，以仓库所有者 `o1xhack` 的身份发布 `COMMENT` review；这是所有者记录子线程实际审查结果，并非 GitHub 的独立账户 approval。不能用普通 PR comment 代替，也不能在子线程报告完成前发布。

clean review 的正文采用以下结构，各字段必须恰好出现一次：

```text
Codex independent subthread review
Reviewed commit: `<完整 40 位 head SHA>`
Reviewer: /root/<实际审查子线程的 canonical ID>
Result: clean
Report: <实际完整报告的路径>
Report SHA256: <报告文件的 64 位 SHA-256>
```

存在 finding 时记录 `Result: findings`，保留报告和逐条问题，不得发布 clean。clean review 不能带任何 inline finding。报告路径和 hash 用于核对实际留存的审查证据；脚本并不读取远程文件，也不以格式检查证明报告真实存在，因此发布者仍必须完成上面的实际核验。

`Scripts/check_pr_review_gate.sh` 仅接受 GitHub 返回的 owner-authored PR review，要求 review 的 commit 与正文完整 SHA 一致。普通评论、其他作者、短 SHA、缺字段、重复字段、未提交 review 和 inline finding 均不能作为 clean。新的 head 自动使旧 clean 失效；同一 head 后续 connector finding 或独立审查 finding 会使 clean 失效。

替代流程与 connector 共用 review 事件顺序、超过五轮的第六轮前架构审计、所有 review thread 显式解决、draft/open 状态和分页截断检查。正在等待的 `@codex review` 请求仍会阻挡 gate，不能借此绕过待完成的审查。合并前仍须运行 gate 并核对 CI；GitHub 本身要求的账户 approval 或分支保护不会被该脚本替代。
