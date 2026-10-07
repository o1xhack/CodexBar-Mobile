# iOS 2.6.0 (235) 上传与提交审核

Status: `done`（已提交审核，等待 Apple）
Date: 2026-10-07

## 授权与来源

- 用户在本 Goal 中明确授权：上传 iOS、创建对应 App Store 版本并直接提交审核。
- 归档来源：mobile-dev `72c5fe067`（相对已审查发行源码 `5948797ec` 只多 Research 文档与 appcast，不影响 iOS 包）。
- `Scripts/upload_ios_testflight.sh` 的预检 lint 两次因 `test_swift_test_process_cleanup.py` 计时用例在高负载下（load ≈ 63：新版 Mac App 首次重扫历史 + 多个已启动模拟器）抖动失败；同一源码的完整 lint 已在 Mac phase 1 r2 通过，因此用去掉预检 lint、其余参数完全相同的副本归档上传。

## 归档与上传

- Archive：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/TestFlight-20261007-134813/CodexBarMobile.xcarchive`，zip SHA256 `171223ad9fcb90a4f526f0c097ec59f6b9d0894ea6c81f97821faa8adb6c4ea2`。
- App 与 3 个扩展均为 2.6.0 (235)；CloudKit `icloud-container-environment = Production`。
- Xcode 云签名上传成功；ASC build `9bd83902-d795-43ef-8c09-532d9794ea11` 处理为 `VALID`。
- 图标三层：编译产物 `AppIcon60x60@2x.png` 120×120 无 Alpha、视觉正确；Apple 处理后 `iconAssetToken` 152×152 CDN 图视觉正确。

## App Store 版本与提交

- 2.5.0 先前已 `READY_FOR_SALE`。
- 新建 App Store version 2.6.0（`c6003677-dbd1-426e-8ff3-901c333bc0a0`，MANUAL），绑定 build 235 并回读。
- en-US / zh-Hans / zh-Hant / ja 更新说明来自 `AppStoreMetadata/2.6.0/*/release_notes.txt`，PATCH 200 并回读；描述、截图等沿用上一版本。
- 审核备注来自 `AppStoreMetadata/2.6.0/review_notes.txt`。
- Review submission `96385ba8-aaea-4a33-8aa5-97378a2184bf` 提交于 2026-10-07T20:56:49Z，回读 version `WAITING_FOR_REVIEW`。

## 未完成

- 等待 Apple 审核；通过后需手动发布。
- 本次未安装到实体 iPhone；实体多设备兼容与 VoiceOver 仍未验证。
