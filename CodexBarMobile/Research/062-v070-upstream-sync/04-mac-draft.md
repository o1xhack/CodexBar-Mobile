# Mac 0.70 签名与 Draft 交付

Status: `done`
Date: 2026-10-03

## 来源与执行顺序

用户明确授权 PR/CR 后合并、iOS TestFlight/ASC 准备及 Mac Draft；iOS 230 处理成功并准备好 ASC 后，才调用 `Scripts/release.sh` 默认 Phase 1。未运行 `--finalize`，未公开 Release，未更新 appcast，未关闭 #166。

源码为 clean mobile-dev `afdb6a23095d37a15638cc10e981791726d9f1d0`；PR170 审查 head `99e9c6622bda6d6264ff64d7c57ef58cbc85ac7f`，远端 clean CR、0 unresolved、review gate 与 Fast Checks 通过后合并。实际包 Info.plist `CodexGitCommit=afdb6a230`，与发行来源一致。

## 最终版本与资产

- Mac `0.70.0.1` / `161.1` / Mobile `2.4.0`，CFBundleVersion `161.1.2.4.0`。
- Tag `v0.70.0.1-mobile.2.4.0`。
- [GitHub Draft](https://github.com/o1xhack/CodexBar-Mobile/releases/tag/untagged-5bbed0e900853af5f243)，API 回读 `isDraft=true`；tag 已由授权的默认 Phase 1 推送。
- App ZIP `CodexBar-0.70.0.1-mobile.2.4.0.zip`：80,734,318 bytes，SHA256 `e0755a8b25bf72ae1b6a02c9995f397796b814a6a0438c55ebca1fcc0c84705c`。
- dSYM ZIP `CodexBar-0.70.0.1-mobile.2.4.0.dSYM.zip`：66,393,800 bytes，SHA256 `38525f294cb5fbda72768e20276e739f99ff4c4665814a6c8c4562ff7021a5fb`。
- 本地 SHA256 与两份 GitHub asset digest 完全匹配；发布脚本完成 dSYM 打包及来源验证。

## 实际包验证

从发行 ZIP 解包复查：arm64+x86_64、Developer ID 深层严格签名通过、Gatekeeper `accepted / Notarized Developer ID`、notary `Accepted`、stapler validate 成功、CloudKit entitlement `Production`。无新 Shared/schema 字段，沿用 `NO_DEPLOY` 审计判定。独立 checkout 不可读情况下的资源/CLI/启动 smoke 全通过。

Studio `/Applications/CodexBar.app` 已替换为该最终包；原安装包保留在 SSD scratch `installed-backup-070-pre170/CodexBar.app`，旧 0.68 备份也保留。最终窗口复查另记 11-final-delivery.md，未把之前源码 ddbfe464 的 UI 观察倒推为最终包实测。

所有大体积构建、签名、公证 staging 和 QA 证据位于 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/upstream-v070`，卷 UUID 和实际路径已验证。日志 `mac070-ios240-draft-release.log` 终态 exit0。

## 公开发布仍须核对

当前合并后 Final CI 尚在运行，见 11。公开发布/appcast 不在本次授权范围，日后必须检查 Final CI、发行来源及完整发布 gate。实体四设备兼容矩阵和人工 VoiceOver 的未验证边界仍保留，不能用 Draft 或本地编译覆盖这些限制。
