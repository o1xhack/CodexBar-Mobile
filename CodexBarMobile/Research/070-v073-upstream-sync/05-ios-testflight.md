# iOS 2.6.0 (237 / 238) TestFlight

Status: `in-progress`（待用户真机验证后再送审）
Date: 2026-10-08

## 构建

| Build | 内容 | 源码 | ASC build id | 状态 |
|---|---|---|---|---|
| 237 | 账本保护（#184，Research 069）+ v0.73 同步的 iOS 部分（#186） | `273b23344`（detached worktree `ios237-src`） | `ee86c70f-9f20-430f-92ff-257fbb1dc819` | `VALID` |
| 238 | 237 + 额度消耗趋势小组件的窗口选择（#187，Research 071） | `ff49aec70`（detached worktree `ios238-src`） | `168ea2e6-73c7-49ae-95d1-d0b90f997ace` | `VALID` |

- 两个 build 都通过 Xcode 已登录会话上传（`upload_ios_nolint_237.sh` / `_238.sh`，ROOT 指向对应 worktree）。
- lint 在上传前另外跑过（跳过受负载影响的 sharding 检查，单独补跑）。
- 只上 TestFlight；App Review 未提交。

## 图标三层验收

- 源 1024 图与上次发布一致。
- 编译产物 `AppIcon60x60@2x.png` 已从 IPA 解出并还原：120×120，11,215 bytes。237 和 238 字节相同，目视正确。
- Apple CDN（`iconAssetToken`）图标：152×152，25,259 bytes。237 和 238 相同，目视为正确的 `</>` 蓝色图标。
- 证据在 `/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/icon23{7,8}-{plain,cdn}.png`。

## ASC 版本状态与后续

- 2.6.0 版本（`c6003677-dbd1-426e-8ff3-901c333bc0a0`）目前状态为 `DEVELOPER_REJECTED`（已撤回），仍绑定 236。
- 用户在 TestFlight 真机确认以下几项后，改绑 238，从 `AppStoreMetadata/2.6.0` 同步 whatsNew，并且只在用户要求时重新送审：
  - 成本历史；
  - 今天的数据；
  - provider 数量；
  - 同步时间；
  - 小组件窗口选择。
- 两台 Mac 都升级到 0.73.0.1 后，用 Air 备份（`diag-236/air`）和新的手机 DB 拷贝核对账本。写回前先把对账表给用户确认。
