# 同周期额度观测点连线

状态：done（实现及本地验证完成，远端审查与TF以独立发布证据为准）。用户已确认方案并要求完整执行本地CR→PR→当前提交远端CR→合并→TestFlight260。

仅调整共享Chart的series分组：同一已解析账号/额度周期使用line.id连接真实端点，不再按采样gap的segment拆线。保留segment用于详情观测查询，缺采样区间不生成读数。投影层已有账号归属校验、resetDate和duration过滤、额度回补清除旧样本；不跨账号或重置连接，不在首末实际点之外补线，不改历史采集/持久化/同步schema。

摘要和详情共享同一图表，保留1.9pt默认与2.3pt聚焦线宽。同步四语说明，清理旧“长间隔断线”描述。增加真实Chart渲染回归，验证跨gap连接及端点外不外推；执行已有周期/账号/缺采样查询测试与完整iOS测试、lint和本地独立CR。

证据：/Volumes/StudioSSD/Developer/BuildScratch/CodexBar/QuotaConnections-3.2.0-260。旧发布证据保持不变。

## 验证结果

旧实现渲染红测失败（exit65，采样点之间缺红色连接像素）；恢复新实现后四种宽度/外观的端点连接与不外推像素断言通过，实际查看手机浅色和Duo宽度深色图像。完整iOS测试1,338通过、1条件跳过、0失败，含已有账号/周期/缺采样读数隔离测试。原生197点详情初次布局0.310秒，低于1秒回归门槛。portable lint和四语审计通过，独立本地CR无finding。未改变同步格式、存储或CloudKit schema，Production不需要schema部署。
