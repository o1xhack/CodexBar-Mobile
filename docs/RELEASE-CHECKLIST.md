# Release Acceptance Checklist — "Definition of Done"

> **给 agent（必读，别等用户提醒）**：upstream-sync / release 类任务，"完成" =
> **已经打包签名公证 + 发布到用户手里**（Mac Sparkle draft→notarize→appcast +
> iOS TestFlight），**不是**"代码 commit 了 / push 了"。
>
> 凭证都在用户 Mac 上：`~/.codexbar-secrets/`（Sparkle key + App Store Connect
> key）+ keychain 里的 `Developer ID Application: Yuxiao Wang (3TUERHN53E)`。
> **直接在用户的 Mac 上跑这些命令，不要只把命令列给用户让他自己跑。**

## 0. 什么叫"做完"
- ❌ "代码写完 + 测试过 + push 了" — **不算**完成。
- ✅ Mac：`./Scripts/release.sh`（build+sign+notarize+draft），验收后 `--finalize`（publish + appcast push 到 mobile-dev）。
- ✅ iOS：Archive + 上传 TestFlight。
- ✅ Todoist 移到 Release，附 release URL。

## 1. 代码 & 测试闸门（`release.sh` phase1 会强制跑，先自己过一遍）
- [ ] `swift build` 干净
- [ ] `bash Scripts/lint.sh lint` 全过 = swiftformat --lint + swiftlint --strict + `audit_xcstrings` + `audit_parser_version` + `check_codex_parser_hash`
- [ ] 全量 `swift test` 绿。**已知 flake**：`SyncCoordinatorTests` 的「L1 retry test flake」在全套件并行下偶发（Todoist 有立项 P3），独立 / filter 运行能过 → **不算回归**，别为它阻塞
- [ ] 多账号 / 多设备枚举：`swift test --filter 'AccountIdentity|MultiAccount|DualZoneReader'` 全过（用户最在意这块）
- [ ] 如果本轮改动触及 iOS widgets、Cost dashboard、provider display data、CloudKit/KVS fallback 或多设备费用聚合：必须跑 `CodexBarMobileTests/WidgetSnapshotBuilderTests`，确认 widget Today totals、tokens、top provider rows 与 Cost dashboard 同一批 synced snapshots 一致；不能靠 TestFlight 截图兜底
- [ ] 如果本轮改动触及 widget 布局、配置 intent、mode/color style 或 WidgetKit rendering：必须跑 `CodexBarMobileTests/CodexBarWidgetRenderMatrixTests`，覆盖 mode × family × color style × Light/Dark 的渲染分支，并断言渲染图像存在明暗对比、Colorful 分支有可见色彩；还必须跑真实 SpringBoard widget gate（至少打开系统编辑面板、确认可配置选项、实际切换一个 mode 并截图）；Settings preview 不能代替真实 Home Screen widget
- [ ] 如果本轮改动触及 Mac→CloudKit→iOS sync、Shared payload、CloudKit schema、provider 显示数据、缓存或跨版本渲染：按 `docs/ios-sync-compatibility-testing.md` 执行 2 Mac × 2 iPhone old/new 兼容矩阵，并把本轮证据写入 `CodexBarMobile/Research/NNN-*/03-testing.md`

## 2. 上游 merge 特有
- [ ] Codex/Claude parser 文件（`CostUsageScanner*.swift` / `CostUsageJsonl.swift`）只要动了 → **bump `parserLogicVersion`**（`CostUsagePricing.swift`）+ **重生成** `CodexParserHash`（`bash Scripts/regenerate-codex-parser-hash.sh`）。两个失效轴都要滚。
- [ ] 新 `UsageProvider` case → 补齐 fork 端**所有** `switch`（`AccountIdentityComputer` / `SyncCoordinator.isModelEstimated` / `UsageStore` …）；`swift build` 的 non-exhaustive 报错会逐个点出来
- [ ] 冲突解决里 fork 自定义的 release 脚本（`release.sh` / `make_appcast.sh` / `sign-and-notarize.sh` …）保 fork 版（上游把它们改成了 `exec mac-release` wrapper，会打断 fork pipeline）

## 3. iOS 端新 provider 全套（缺一不可）
- [ ] `Shared/Notifications/QuotaProviderList.swift`（**tail 追加**，保 CK 订阅 ID 稳定）
- [ ] `MockProviderInjector.swift`：`realProviderIDsBorrowedByMocks` **和** `simpleProviderProfiles` 两处同步 + 所有 test 计数断言（allMocks / uniqueIDs / realBorrowedMocks / mockEnvelopes / QuotaProviderList count×3）
- [ ] `ProviderColorPalette.swift`：注意 **substring 匹配顺序**（如 `azureopenai` 必须在 generic `openai`→green 之前）
- [ ] `MobileReleaseNotesCatalog`（ContentView）新版本条目 + 旧版本降级 "Latest" + **4 语言** `Localizable.xcstrings`（`bash Scripts/lint.sh audit-i18n` 必过）
- [ ] mock 描述文案 `mobile_toggle_mock_subtitle`（en + zh-Hans 的计数）
- [ ] `PreviewData.swift`：**按卡片类型**收录（不是每 provider 都加）；新的 generic provider 若已有同类样例可不加 —— 但**每次主动确认一次**，别默认跳过

## 4. 版本号（决策树见 `docs/versioning.md`）
- [ ] `version.env`（MARKETING / BUILD / MOBILE / UPSTREAM）
- [ ] `CodexBarMobile/project.yml`（×3 target 的 MARKETING + CURRENT_PROJECT_VERSION）+ `xcodegen generate`
- [ ] iOS `CHANGELOG.md`（技术）+ 根 `CHANGELOG.md` fork 叙述段（= Sparkle 用户文案，用 `bash Scripts/changelog-to-html.sh <MARKETING>` 验证提取的是 fork 段不是上游技术段）

## 5. CloudKit
- [ ] 跑 `docs/cloudkit-deploy-audit.md` 审计 → 判断是否要 Dashboard deploy 到 Production。新 provider = runtime zone 复用 `QuotaTransition` record type → 通常**不**需要；新 record type / field / index → **需要**

## 6. CR（每一大轮）
- [ ] merge 轮 / bridge 轮 / iOS 轮 各跑一次 **Opus 4.7 agent CR**，循环到 clean，findings 全修（含 stale 注释 / @Test 标题）

## 7. 发布（在用户 Mac 上实跑）
- [ ] merge sync 分支 → `mobile-dev`（release + appcast 都从 mobile-dev 出）
- [ ] Sparkle 工具加进 PATH：`export PATH="$PWD/.build/artifacts/sparkle/Sparkle/bin:$PATH"`
- [ ] `./Scripts/release.sh`（phase1：build + sign + notarize + draft GitHub release）
- [ ] iOS：`xcodegen generate` → Archive（`-allowProvisioningUpdates`）→ export/upload 到 App Store Connect（TestFlight）
- [ ] 用户 QA 通过后 → `./Scripts/release.sh --finalize`（publish draft + 生成签名 appcast + push 到 mobile-dev）
- [ ] Todoist：任务移到 **Release**，附 release URL + TestFlight build 号
