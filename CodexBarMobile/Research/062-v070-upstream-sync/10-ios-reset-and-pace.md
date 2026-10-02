# iOS 重置时刻与节奏文案修正

状态：done（本次两项本地修正；整个发布Goal仍in-progress）；用户2026-10-02明确要求修正两项，作为本分支iOS范围补充。

- 重置倒计时右侧增加`M.d HH:mm`小字；固定Gregorian、24小时制，按iPhone本地时区转换真实resetsAt。没有真实时间戳时不从描述猜测日期；月额度blocking仍使用有效月池重置时间，过期观察维持等待新Mac数据。
- CodexWorkspaceBadge目前直接Text(context.weeklyPaceLabel)，该文字由Mac的UsagePaceText.weeklySummary按Mac语言生成，导致英文iPhone显示中文。iOS改用weeklyPaceDelta数值生成四语言文案；工作区名称仍作为用户数据原样显示，不修改wire/schema或Mac代码。
- weeklyPaceDelta实际上是`(actualUsedPercent - expectedUsedPercent)/100`，15是百分点差，不是未来15%消耗预测；headroom是`remainingCapacity/projectedRemainingUsage >= 1.5`且delta<-15时的固定阈值提示，非精确倍数。未来预测假设本周期平均速率不变，用同步窗口及Mac观察时刻计算，重置过期/未知/blocked/合成窗口不产生forecast。新增说明入口解释百分点与假设。
- 验证：固定时区/日期边界与四语言文案、跨Mac/iPhone语言、未知和过期观察单元测试；真实App demo四语言打开Codex检查日期同行及说明入口，保留截图。设备验证限专用Simulator，未授权push/PR/merge/upload/release。

## 验证结果

- r20、最终源码r21均标准xcodebuild test exit0：19项单元测试/2 suites及1项遍历四语言的真实App UI测试通过。包含故意中文producer文案的英文reader回归、日期边界、预测阈值、过期/未知观察。r21在周期时钟修正后执行。
- r20八张界面/说明附件保存在BuildScratch/upstream-v070/ios-reset-pace-r20-attachments；英文及简体截图人工核对，日期在右侧小字，英文没有中文泄漏。窄布局代码提供换行fallback，未声称完整Dynamic Type矩阵或人工VoiceOver验证。
- focused strict SwiftLint及六文件SwiftFormat lint通过；i18n-r21 audit通过，385 source keys齐全、四语言全部translated；git diff --check通过。
- 本地只读review发现并修正跨重置时间不刷新的问题：Detail独立60秒TimelineView传referenceDate；demo冻结参考时间；无工作区及有效pace时不画空Badge。最终diff review clean。
- r21-inputs.json冻结107项App/Shared源码资源，仅此范围，不是完整发布provenance。旧r19通用iPhoneOS Release未包含本次改动；没有新的Archive、签名、上传、实体安装或远端PR/CR证据。
- 发布顺序及远端授权边界保持不变，不能把本地修正完成视作整个发布Goal完成。
