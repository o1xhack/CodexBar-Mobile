# 测试与兼容证据

Status: `done`
Date: 2026-09-30
Branch: `fix/ios-230-legacy-mac-compatibility`
Version: iOS 2.3.0 (225)

## 实机与构建

- Air 本地 Debug 225，CloudKit entitlement 实际读取为 Production；两台真实 Mac 保持0.58.0.1。
- iPhone镜像确认原始设置（CWL关闭）已知历史/Top Driver/两 Provider 占比恢复，重启后仍有数据，新同步费用继续更新。
- 通过 devicectl 临时 launch arguments `-cwlEnabled YES -cwlWindowDays 365` 验证原手机数据库的365天路径：Overview 显示带 ≥ 的非空历史金额、Top Driver 和占比，历史不完整提示保留。
- 无参数 terminate-existing 重启后，镜像确认恢复原设置的 Known history 标题；未改用户的持久窗口设置、未清缓存/账本/CloudKit。
- 关于与同步页面确认2.3.0 (225)、两Mac0.58.0.1、刚刚同步。只验证Air，未替换另一手机或升级Mac。
- 真机证据为本会话 CUA iPhone镜像当前截图（21:42、21:51、21:54）；不保存含账号信息的截图到仓库。

## 自动验证

- 完整 iOS unit：53 XCTest + 825 Swift Testing，0失败（runner计数；参数化组合单列），`legacy-history-complete-unit.log`。
- 4 writer masks（0.58旧形状/0.68现代period-summary形状）wire round-trip→Merger→独立reader模型，4/4通过；不是两台物理iPhone。
- 既有完整snapshot/双区cache/新旧reader兼容mask：16/16通过。
- 稀疏365天、不同50/200扫描、same-account双Mac、unknown金额不混入小计、现代/旧格式混合均覆盖。
- Cost页与分享编辑器 focused UI：3/3通过，`legacy-history-ui-smoke.log`；截图保存在xcresult。
- 全仓 lint 2724文件0violations，4语言全部translated、367 source keys齐全，`legacy-history-final-lint.log`。
- Debug真机构建通过，`legacy-history-device-release-build.log`；Release Simulator构建通过，`legacy-history-release-build.log`。

日志统一位于 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/`。完整unit结果：
`LegacyHistoryFix/Logs/Test/Test-CodexBarMobile-2026.09.30_21-50-54--0700.xcresult`（具体名称以log末尾为准）。

## 首轮失败与修复

最初独立review无阻塞，但实机暴露CWL关闭路径仍空，因此继续修复，不能仅以57项focused pass结束。
完整测试曾报告24条旧显示预期失败：16-mask要求modern mixed period的排行为空。
已改为Known history+明确≥日期小计，仍断言原始period总额unknown、月度Share不混加、旧reader与Today行为不变。
另修复SwiftFormat把既有allSatisfy闭包改成keypath后触发Swift Testing宏编译问题，最终整套重跑通过。

## CloudKit 审计

NO_DEPLOY。diff只改iOS projection/view/诊断、版本/资源/测试/文档；Shared wire、CloudConstants、CKRecord types/fields/indexes/zones/subscriptions均未改。
实际签名环境Production已读取确认；没有执行schema deploy。

## Canonical 16-case gate

本次是cross-version rendering，gate适用。旧iPhone=2.2 reader投影，新iPhone=225当前reader。
16-mask完整snapshot fixture使用旧Mac0.66与新Mac0.68；另有4-mask专门覆盖实际0.58旧形状及0.68。
真实两Mac始终旧版本；只有Air安装225。不能为了矩阵擅自升级/降级另一手机与Mac，所以以下16项都是substituted。
证据E1：`CloudKitMergeTests` 16-mask（wire/cache/legacy reader/current reader），E2：`CostShareServiceTests`4-mask及稀疏365回归。
Air真实old/old→new的CWL关闭、临时365、重启及fresh sync补充验证，不替代另一iPhone的独立缓存/后台推送。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence | 风险 |
|---:|---|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | E1 mask 0, E2 | 未实测完整四设备组合/后台推送 |
| 2 | old | old | old | new | substituted | E1 mask 1, E2 | 未实测完整四设备组合/后台推送 |
| 3 | old | old | new | old | substituted | E1 mask 2, E2 | 未实测完整四设备组合/后台推送 |
| 4 | old | old | new | new | substituted | E1 mask 3, E2 | 未实测完整四设备组合/后台推送 |
| 5 | old | new | old | old | substituted | E1 mask 4, E2 | 未实测完整四设备组合/后台推送 |
| 6 | old | new | old | new | substituted | E1 mask 5, E2 | 未实测完整四设备组合/后台推送 |
| 7 | old | new | new | old | substituted | E1 mask 6, E2 | 未实测完整四设备组合/后台推送 |
| 8 | old | new | new | new | substituted | E1 mask 7, E2 | 未实测完整四设备组合/后台推送 |
| 9 | new | old | old | old | substituted | E1 mask 8, E2 | 未实测完整四设备组合/后台推送 |
| 10 | new | old | old | new | substituted | E1 mask 9, E2 | 未实测完整四设备组合/后台推送 |
| 11 | new | old | new | old | substituted | E1 mask 10, E2 | 未实测完整四设备组合/后台推送 |
| 12 | new | old | new | new | substituted | E1 mask 11, E2 | 未实测完整四设备组合/后台推送 |
| 13 | new | new | old | old | substituted | E1 mask 12, E2 | 未实测完整四设备组合/后台推送 |
| 14 | new | new | old | new | substituted | E1 mask 13, E2 | 未实测完整四设备组合/后台推送 |
| 15 | new | new | new | old | substituted | E1 mask 14, E2 | 未实测完整四设备组合/后台推送 |
| 16 | new | new | new | new | substituted | E1 mask 15, E2 | 未实测完整四设备组合/后台推送 |

## Review与发布边界

主代理自查、独立agent多轮审查：当前功能diff无阻塞；特别审查原始周期总额与日期小计的区分、金额过滤、排行榜一致性及16-mask预期更新。
剩余风险：真实全矩阵、旧iOS物理客户端及后台推送仍为替代验证；不能宣称这次覆盖全部真实fleet。
225已完成Release Archive/export/upload，Apple VALID、内测IN_BETA_TESTING、原内测组包含225；App Store草稿绑定225且保持PREPARE_FOR_SUBMISSION。四语言What’s New/测试说明回读通过；见04-testflight.md。没有提交审核、push、merge或tag。
