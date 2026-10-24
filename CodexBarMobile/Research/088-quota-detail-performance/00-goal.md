# Remaining Quota 详情交互性能修复

状态：done（实现与本地验收完成；远端审查与 TestFlight 以发布证据为准）。用户报告 build 257 在 Duo 从四格卡片进入详情、点击按钮和纵向滚动严重卡顿；继续已授权的修复、测试、本地与远端 CR、TestFlight 工作。

## 根因与修复

sliderDate 在每个历史点的过滤闭包内访问 self.overview.start/end，每次会再次进行全量身份解析、历史合并和排序；两个滑块读取路径使 idle 渲染约有 4N 次完整投影。修复为输入层只生成一次不可变快照，交互状态放入独立子 View，滑块最新日期预先计算；同步、配置、账户、时间变化重新构造快照，不使用仅 onAppear 缓存。保留全部真实历史、精确时间、缺口、颜色、账户绑定以及最近 Weekly reset 的全局144小时域。

## 验收

同配置旧新版本对比首次详情布局及按钮/横拖/纵滚；使用真实历史量和大型虚构数据。已有 baseline 原生 UIHostingController 在768pt Duo宽度下初始布局3.784963209秒（总197个实际显示点）；原fixture对所有provider均支持同步历史的假设失败，不伪装为完整通过。修复fixture计数断言，同时保留该旧版延迟证据。性能通过不能由截图和自动点击通过替代。

证据：/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/QuotaDetailPerformance-3.2.0-258。原始 baseline 位于相邻 QuotaDetailPerformance-2026-10-24。
