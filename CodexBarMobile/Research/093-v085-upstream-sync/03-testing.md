# 候选测试记录

状态：in-progress

- Xcode 27.2 (27B52)，StudioSSD 已核实 UUID、可写与项目和 scratch 的实际路径。
- 本地测试隔离外部 provider 凭据和账号数据。没有运行 live provider probe。
- 离线矩阵使用已发布 fork 与候选的 Shared/merge 源码分别编译，执行 64 次独立 reader 解码与 32 次双 writer 合并。未具备两台 Mac 与两台 iPhone 的独立旧/新实机组合，故以下记录为替代证据。未验证生产 CloudKit 网络、APNs、前后台收敛或 SwiftData 迁移，实机有残余风险。

| 组合 | Mac A | Mac B | iPhone A | iPhone B | 结果 | 验证 |
|---:|---|---|---|---|---|---|
| 1 | old | old | old | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 2 | old | old | old | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 3 | old | old | new | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 4 | old | old | new | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 5 | old | new | old | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 6 | old | new | old | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 7 | old | new | new | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 8 | old | new | new | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 9 | new | old | old | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 10 | new | old | old | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 11 | new | old | new | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 12 | new | old | new | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 13 | new | new | old | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 14 | new | new | old | new | substituted | 双 writer 分别解码并按两种顺序合并 |
| 15 | new | new | new | old | substituted | 双 writer 分别解码并按两种顺序合并 |
| 16 | new | new | new | new | substituted | 双 writer 分别解码并按两种顺序合并 |
