# CodexBar — Project Overview

CodexBar is a macOS menu bar app that tracks AI coding tool usage (Claude, Codex, Cursor, etc.). It has an iOS companion app that syncs data from Mac via iCloud.

- **We only work on the iOS app.** Mac-side code is maintained upstream — do not modify Mac-only files unless explicitly asked.
- iOS project lives in `CodexBarMobile/`.
- Shared sync layer lives in `CodexBarMobile/Shared/` (used by both Mac and iOS).

## Repositories

| Remote | Repo | Role |
|--------|------|------|
| `upstream` | steipete/CodexBar | Original open-source repo, read only |
| `origin` | o1xhack/CodexBar-Mobile | Our fork |
| Branch | `mobile-dev` | Main working branch |

## Workflow

**All development follows the 7-step workflow defined in [`AGENTS.md`](AGENTS.md).**

Quick summary:

> Research → Design → Implementation → Testing → Documentation → Commit → Todoist 同步 → Push & Release

8. **Todoist 同步**：Commit 之后，同步更新 Todoist 任务状态，详见下方「Todoist 同步规则」

### Post-Commit Checklist（每次 git commit 后必须立刻执行，无例外）

```
git commit → git push → Todoist comment (含 commit 链接) → 移到 Code Complete
```

四步必须连续完成，不能拆开、不能延后、不能"等会儿补"。
不管改动大小、不管是 bug fix 还是文档、不管用户有没有明确要求。
只要有 `git commit`，就跑这个 checklist。

### Definition of Done（release / upstream-sync 类任务的验收标准）

**"完成" = 已打包签名公证 + 发布到用户手里**（Mac Sparkle draft→notarize→appcast +
iOS TestFlight），**不是**"代码 commit / push 了"。CodexBar Sparkle key 等项目私有
release secret 在 `~/.codexbar-secrets/`；Apple App Manager / App Store Connect
凭据是全局 Apple release/signing 凭据，在
`~/.codex-secrets/apple/app-store-connect/`；Developer ID 证书在 keychain。
**直接在用户 Mac 上跑发布命令，别只把命令列出来让用户自己跑**。
完整验收清单（每个新 provider 要改的全部文件、parserLogicVersion bump、多账号/多设备
枚举验证、CloudKit 审计、Opus CR 闸门、发布步骤）见
**[`docs/RELEASE-CHECKLIST.md`](docs/RELEASE-CHECKLIST.md)** —— 每次 release 前自己过一遍，不用等用户提醒。

See `AGENTS.md` for the full process, rules, and checklists.

## Key File Locations

| Path | Purpose |
|------|---------|
| `AGENTS.md` | Complete development workflow and agent rules |
| `CodexBarMobile/Research/` | Feature research documents ([index](CodexBarMobile/Research/README.md)) |
| `CodexBarMobile/project.yml` | Build number (`CURRENT_PROJECT_VERSION`) and version (`MARKETING_VERSION`) |
| `CodexBarMobile/CHANGELOG.md` | iOS changelog (technical, Keep a Changelog format) |
| `CodexBarMobile/CodexBarMobile/ContentView.swift` | Main views, settings, in-app release notes (`MobileReleaseNotesCatalog`) |
| `CodexBarMobile/CodexBarMobile/Localizable.xcstrings` | All translations (JSON, 4 languages) |
| `CodexBarMobile/CodexBarMobile/Views/` | Feature views (provider detail, usage cards, onboarding) |
| `CodexBarMobile/CodexBarMobile/Models/` | Data models and formatters |
| `CodexBarMobile/CodexBarMobile/Preview Content/PreviewData.swift` | Demo / preview data |
| `CodexBarMobile/Shared/` | Shared iCloud sync layer |
| `version.env` | 当前 ship 版本 + 上游对齐版本（`UPSTREAM_VERSION` + `UPSTREAM_SYNC_DATE`）— routine/agent 查"对齐到上游哪个版本"必读此文件 |
| `docs/versioning.md` | **版本号命名规则** — 4 个版本变量 (`MARKETING_VERSION` / `BUILD_NUMBER` / `MOBILE_VERSION` / `UPSTREAM_VERSION`)、release tag / zip 名、Sparkle `sparkle:version` 5 段格式、什么时候 bump 哪个的决策树。改任何一个版本号前必读 |
| `docs/cloudkit-deploy-audit.md` | **CloudKit Production deploy 审计** — 每次发版前查表判断是否需要 deploy schema 到 prod；提供 grep 命令清单 + 历史 release 决策存档。Sparkle 老踩坑 |
| `docs/RELEASE-CHECKLIST.md` | **Definition of Done + 验收清单** — release/upstream-sync 类任务"做完"的定义（= 已签名公证 + TestFlight，不是 commit）+ 每个新 provider 要改的全部文件 + lint/parser/多设备/CloudKit/CR 闸门 + 发布步骤。每次 release 前过一遍 |

---

## 协作模式（iSparto）

本项目支持 Agent Teams 多角色协作。以下定义各角色职责和触发条件。

### 角色定义

| 角色 | 职责 | 说明 |
|------|------|------|
| **PM（产品经理）** | 需求分析、功能优先级、验收标准 | 由用户担任 |
| **Architect（架构师）** | 技术方案设计、调研文档 | 对应 Step 1–2（Research + Design） |
| **Developer（开发者）** | 编码实现、测试 | 对应 Step 3–4（Implementation + Testing） |
| **Release Engineer** | 文档更新、版本管理、发布 | 对应 Step 5–7（Documentation + Commit + Push） |

### 触发条件表

| 用户指令 | 触发角色 | 执行动作 |
|----------|----------|----------|
| 调研 / research | Architect | 执行 Step 1–2，输出 Research/ 文档 |
| 开发 / implement | Developer | 执行 Step 3–4，编码 + 测试 |
| 提交 | Release Engineer | 执行 Step 6a–6c（bump + changelog + jj commit） |
| 提交推送 | Release Engineer | 执行 Step 6a–6d（+ push） |
| 上传 / Archive | Release Engineer | 执行 Step 7（archive + TestFlight） |
| 安装到手机 | Release Engineer | xcodebuild 直连真机安装 |

### 分支策略

| 分支 | 用途 |
|------|------|
| `mobile-dev` | 主开发分支，所有 iOS 开发在此进行 |
| `main` | 上游同步分支，不直接修改 |

使用 jj bookmark 管理分支指针，详见 `AGENTS.md`。

### 操作护栏

- **不修改 Mac 端代码**：`Sources/`、`Tests/` 下的文件属于上游，只读
- **不推送到 upstream**：只推送到 `origin`（o1xhack/CodexBar-Mobile）
- **不跳过本地化**：所有用户可见文本必须包含 4 种语言
- **不跳过版本号**：每次提交必须 bump `CURRENT_PROJECT_VERSION`
- **不手动编辑 .xcodeproj**：通过 `xcodegen generate` 从 `project.yml` 生成

### Todoist 同步规则
项目使用 Todoist（Dev 项目，Board 视图）进行任务管理。每次开发活动必须与 Todoist 保持同步。

#### 看板栏目
| 栏目 | 含义 |
|------|------|
| **Backlog** | 待规划/排期 |
| **In Progress** | 正在开发中 |
| **Code Complete** | 代码完成，等待人工验证 |
| **QA** | 人工验证：真机测试、TestFlight 内测 |
| **Release** | 确认通过，可发布或已发布 |

#### 标签体系

**必打标签：**
- `CodexBar-Mobile` — 项目标签，所有任务必须打上

**按性质叠加：**
- `Bug` — Bug 修复任务
- `商业化` — 将来纳入会员收费的功能

**标签管理：**
- 创建前必须先搜索已有标签（`find-labels`），存在则复用，不存在才新建
- 多个标签可叠加

**自动判断规则（创建任务时）：**
- 修复类（"修复"、"bug"、"crash"、"闪退"）→ 打 `Bug`
- 涉及付费/会员功能 → 打 `商业化`

#### 任务创建规范

**必填字段：** content、description、labels（项目标签+性质标签）、priority（p1-p4）
**子任务：** 预计 >1 天或 >1 PR 的任务必须拆分子任务
**Bug 入栏：** P1 线上故障 → In Progress；P2+ 非紧急 → Backlog

#### 开发流程中的 Todoist 操作

**开始工作时：**
1. 在 Todoist 搜索对应任务（按标签 `CodexBar-Mobile` + 关键词）
2. **如果没有对应任务**：自动创建新任务，根据任务性质打上对应标签，填写所有必填字段
3. 将任务移到 **In Progress** 栏目

**每次 Commit 后：**
4. 在对应任务下添加 comment，包含：
   - 日期标记：`[YYYY-MM-DD]`
   - 简要描述本次进展
   - Commit 链接：`https://github.com/o1xhack/CodexBar-Mobile/commit/<sha>`

**代码完成时：**
5. 将任务移到 **Code Complete** 栏目（不直接标记完成）
6. 添加 comment 说明代码已完成，等待人工验证；如有 PR 附上链接

**人工验证通过后：**
7. 经过 QA（真机测试/TestFlight/用户验收）后，移到 **Release**
8. 添加最终 comment（验证结论）
9. **由用户确认后**才标记任务为完成（勾选）

**任务阻塞时：**
10. 在 comment 记录阻塞原因和依赖项，标题加 `[Blocked]`

**会话结束时（跨会话交接）：**
11. 未完成任务在 comment 记录：当前状态、下一步、阻塞点

#### 职责边界
- **Todoist**：任务状态流转 + 进度日志（摘要 + commit 链接）
- **CHANGELOG.md**：面向开发者的变更记录
- **version.env**：当前 ship 版本 + 上游对齐版本
- Todoist comment 不重复写完整变更内容，指向 CHANGELOG 即可

#### 注意事项
- **不要直接标记完成**：代码完成 ≠ 任务完成，必须经过 QA 人工验证
- **状态变动必须移栏**：任务状态变化时，同步移动到对应栏目
- **新发现的 Bug**：立即创建任务，打 `Bug` 标签，P1 放 In Progress，P2+ 放 Backlog
- **QA 发现问题**：任务移回 In Progress，comment 说明问题
