# Provider Overview 多选与自适应布局

Status: `done`
Date: 2026-09-30

## 用户确认与发布边界

用户要求在 iOS 2.3.0 加入此功能，暂不上传、提交审核或发布。分支 feature/widget-provider-overview 从最新 mobile-dev 652904546 创建；保留用户自己的 workflow skill 修改。

## 设计

- Overview 以 Provider 卡片替换单一总用量 hero。小默认 2，中默认 4，大默认 4，超大默认 4；用户显式选 1–4 时精确显示所选，不自动补其他 Provider。
- 小尺寸 1/2/3/4 项分别为 hero/两行/2×2（空一格）/2×2；中尺寸 1/2/3/4 为单卡/双列/三列/2×2；大 1–4 为舒展单列或2×2，超大 1–4 为宽列。复用既有颜色、provider mark、进度及 unknown/error 语义。
- 原生 Widget 编辑页 Providers 参数为 AppEntity 数组多选。候选源来自 app 正常同步后的 App Group 本地 catalogue，不在 picker 做额外 CloudKit/凭证读取。最多4项，无选择时自动按各尺寸默认；失去数据的选项保留 unavailable 卡片，不回退到别的账户。
- 按 providerID 选择品牌；同品牌多个账户以既有排序选最高 usage 的代表，避免混算。完整 snapshot 不再截断前6，保证低排名 Provider 可选。
- 现有 AppIntent widget kind 保留，新增 optional parameter，旧已放置实例走自动默认；Token Activity SiriKit intent 和其他模式保持原有行为。
- 四语言参数/说明/release notes，2.3.0 同一 notes block，build统一递增至224。Mac版本不变。

## 刷新倒计时追加需求

用户要求百分比旁标注短数字刷新时间。使用该最高有效 quota / budget 百分比对应的 resetsAt；未知/placeholder 不伪造0%，刷新缺省不猜测。英文3.7d、简繁中文3.7天、日文3.7日；不足0.1天显示<0.1，已到时显示本地化 Now。时间以 timeline entry date 为锚，与原有15分钟刷新一致，不额外发起实时CloudKit请求。

## 验证计划

检查 selection 去重、顺序、上限、缺失、同品牌多账户；实际生产 View 1–4 ×四尺寸渲染与图片检查；配置 picker 保存与 timeline 接收需 SpringBoard 实测，不以单元赋值代替。Simulator build / focused tests / lint。无 CloudKit wire/schema变化；记录本地 projection/cache 影响及兼容替代证据。

## 当前结果

最终代码871项unit通过，完整UI10通过/6条件跳过/0失败，64组合渲染人工检查通过。iOS27原生配置保存、timeline count与桌面1/2/3/4项完成，中尺寸四项与iPad超大四项实际显示通过。App内四选checkbox上限验证通过；四语言/2.3.0(224)文档齐备。Release Simulator与真机Debug构建通过，已按用户指定安装this phone has no air，随后通过iPhone镜像完成真机默认四项与原生选择两项的桌面验收。详见 [03-testing](060-widget-provider-overview/03-testing.md)。未上传、发布或push。

原26.5异常实例原地升级27后保留三项配置，成功传入timeline与桌面显示；默认测试实例已升级27。26.5真机及真实Production两Mac两iPhone兼容矩阵仍为明确替代验证，不从Simulator结果推断实机同步通过。
