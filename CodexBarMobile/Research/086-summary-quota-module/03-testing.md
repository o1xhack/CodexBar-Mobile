# 验证与发布证据

状态：done（实现与本地验证完成；线上审查、上传回执独立记录）。证据目录：`/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/SummaryQuotaModule-3.2.0-256`。

## 实际渲染

用户要求普通 iPhone / 展开 Duo × 横 / 竖 × 浅 / 深分别验证，不能把 Duo 深色结果推广到其他组合。截图使用原生 App、Tab Bar、导航栏；UI fixture 为合成数据，Air 实机另验真实同步历史。

| 设备 | 方向 | 浅色 | 深色 |
|---|---|---|---|
| 普通 iPhone | 竖屏 | PASS `final-phone-light.xcresult` | PASS `final-phone-dark-v2.xcresult` rotation case 的显式 portrait 截图；Air 深色真实 Usage 另验 |
| 普通 iPhone | 横屏 | PASS `final-phone-light.xcresult` | PASS `final-phone-dark-v2.xcresult` |
| Duo 展开 | 竖屏 | PASS `final-duo-light-portrait.xcresult` | PASS `final-duo-dark-portrait.xcresult` |
| Duo 展开 | 横屏 | PASS `final-duo-light-landscape.xcresult` | PASS `final-duo-dark-landscape.xcresult` |

## 已发现与修正

- Duo 深色 Usage sidebar 原先继承系统灰表面；显式填充与 Cost 一致的 pageBackground 后，实际截图侧栏呈黑色。其他组合继续独立验证。
- 图表新增时嵌套 TimelineView 更新反馈造成主线程高 CPU：模块复用 Summary 的同一个时间值，并固定调度起点；重跑已能完成添加与原生排序。
- Custom Layout 上的 accessibilityIdentifier 传播覆盖子卡标识，已移至现有计数文本；保留模块与每张指标卡自己的 AX 身份。
- 四格排版按单调顺序放置，不回填此前空格，视觉顺序与排序设置一致。
- 普通手机矮横屏中固定的演示提示/筛选条挤占图表完整高度：改为随 Summary 内容滚动，保留四格高度与文字大小。
- Duo 竖屏列数原先受 split-view 760pt 阈值限制；改为按可用宽度排列，668pt 三列，952pt 四列，普通手机矮横屏两列，辅助大字单列。
- UI 测试曾将 Summary 标题识别为 Tab，误算遮挡；已限制为真实 Button，不降低几何断言。弹层图例只计算自身导航栏，不能把被遮住的底层 Tab Bar 算作障碍；选线 push 页面按实际 Form 路由滚动。

## 模型、交互与真机

- `final-units.xcresult`：1325通过、1既有条件跳过。随后列数规则调整以 `layout-units.xcresult` 的 SummaryCardTests 复核通过。
- `quota-regressions-v2.xcresult`：选线数量上限、增删/颜色/排序重入与最大辅助字号图例滚动通过；隐私隐藏另由 `quota-regressions.xcresult` 对应用例通过。
- `phone-focused-v2.xcresult`：模块增删/重入、日文最大标准字号通过。
- `final-i18n.log`：四语齐全，517个源码key均存在；`final-lint.log`：0 violations。
- `air-final-install.json`：Release开发签名256安装到Air。`air-final-summary-dark-real.jpg` 与 `air-final-usage-dark-real.jpg` 是最终产品源码的真实手机/真实同步数据，图表读取此前20日至今历史；非demo，不上传公开PR截图。

## 多设备兼容性

本次未改 Mac、Shared payload、CloudKit schema 或同步写入，保持 Production。改变的是 iOS 本地 Summary 可选配置及额度记录的视图生命周期归属。两台 Mac / 两台 iPhone 的全部实体旧新组合不具备可重现硬件条件，不能声称实跑通过。下表以本地迁移/采样/合并回归和实机读取替代；剩余风险是跨机推送时序未在16种硬件组合逐项观察。

| Case | Mac A | Mac B | iPhone A | iPhone B | Result | Evidence |
|---:|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 2 | old | old | old | new | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 3 | old | old | new | old | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 4 | old | old | new | new | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 5 | old | new | old | old | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 6 | old | new | old | new | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 7 | old | new | new | old | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 8 | old | new | new | new | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 9 | new | old | old | old | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 10 | new | old | old | new | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 11 | new | old | new | old | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 12 | new | old | new | new | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 13 | new | new | old | old | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 14 | new | new | old | new | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 15 | new | new | new | old | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |
| 16 | new | new | new | new | substituted | `final-units.xcresult`、`layout-units.xcresult` 与 `air-final-summary-dark-real.jpg`；非该硬件组合实跑 |

## 发布

3.2.0 (256)，四语说明仍属于同一3.2版本。独立本地 CR 与八种姿态/配色检查已通过。线上 CR、合并、Archive/IPA 与 ASC 的实际回执保存在本次证据目录 `review-proof.json` / `provenance.json`，这些文件须由对应操作成功后生成；本地验证通过不代表已经上传。之前255的证据不用于本轮证明。

完整截图索引：证据目录的 `screenshots.html`。Duo竖屏原始文件按当时设备方向倒置，在索引中仅旋转显示；原始截图未修改。
