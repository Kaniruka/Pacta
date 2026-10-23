# 大字号与专门键盘操作范围同步（2026-10-23）

产品负责人的长期范围决定已记录为 accepted [ADR 0008](adr/0008-large-text-and-keyboard-out-of-product-scope.md)。它部分替代 ADR 0007 保留的大字号和 Windows 常规键盘条款，普通文本输入、正常字号可读性、响应式布局、鼠标／触摸及 Android 系统返回继续有效。

## 本地同步

- 根 AGENTS.md 与 UI／领域代理指南：将 UI 支持范围路由到 ADR 0007、0008；技能建议服从已确认范围，无需再次确认。CLAUDE.md 已引用 AGENTS.md，无需重复规则；通用技能文件保持原样。
- 核心规格、产品设计、国策画布当前方案和国策 AI 规格：替换现行大字号／键盘专项条件，保留普通使用要求。
- 改进专题规格：用户故事 12 标记撤销并保留编号；故事 40、50、标题控制、同步弹层和 Testing Decisions 更新为鼠标／触摸、正常字号和响应式边界。
- 验收矩阵的链场景、R22-01、R22-02、R22-08 与未完成本地票 T06、T09：移除同类专项条件，保留原功能验收。
- 较早需求访谈仅补充后续决定指针，原访谈内容保留；ADR 0007 仅添加部分替代说明，原始决定保留。

## GitHub 未完成 Issue

以下 8 张打开的 Issue 同步范围说明，状态、标签和依赖关系保持不变：

| Issue | 同步内容 |
| --- | --- |
| [#54](https://github.com/Kaniruka/Pacta/issues/54) | UI 改进票补充 ADR 0008 范围入口 |
| [#63](https://github.com/Kaniruka/Pacta/issues/63) | 更新故事 12、40、50、标题控制、同步弹层与 Testing Decisions；追加后续决定评论，明确替代早前评论保留的大字号／键盘条款，旧评论保留 |
| [#67](https://github.com/Kaniruka/Pacta/issues/67) | 模式记忆票补充范围入口 |
| [#68](https://github.com/Kaniruka/Pacta/issues/68) | 视图偏好票补充范围入口 |
| [#69](https://github.com/Kaniruka/Pacta/issues/69) | 同步卡片票替换 Escape／大字号／键盘验收条款并补充范围入口 |
| [#70](https://github.com/Kaniruka/Pacta/issues/70) | 设备型号票补充范围入口 |
| [#71](https://github.com/Kaniruka/Pacta/issues/71) | 云版本检查票补充范围入口 |
| [#72](https://github.com/Kaniruka/Pacta/issues/72) | 版本提醒票补充范围入口，关闭语义保留、移除 Escape 专项表述 |

## 保留与核验

#64、#65、#66 等已完成 Issue、本地已完成票、历史验收／审查文档及截图均未改写；用户选中的 #66 两端大字号／键盘实测记录原样保留。旧记录说明当时实际做过什么，不再成为后续任务的支持门槛。没有修改或删除应用代码、测试、既有能力；GLOSSARY 无需新增 UI 支持策略词条。

本轮只同步文档与票据，未执行 Flutter 测试或设备验收。核验包括改动文件范围、Markdown 相对链接、旧要求剩余位置归类及 GitHub 正文回读；现有测试可继续运行并如实记录，其退出范围的专项断言不再单独构成交付门槛。
