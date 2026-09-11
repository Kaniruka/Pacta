# App 设计参考

本目录收录 Pacta 当前的 App 概念设计图，已确认为后续设计讨论与原型探索的参考资料。**这些图只提供大概方向，不是唯一标准，也不是定稿、完整功能规格或像素级验收依据。不要照搬图中的布局和 UI 风格。**

## 如何使用

- 参考页面想解决的问题、主要信息和操作之间的关系；结合实际使用场景重新组织界面。
- 布局、组件形态、配色、字体、图标、间距、装饰效果与动效均可重新设计。浅色绿色界面和深色金色国策树不构成必须沿用的主题组合。
- 根据手机与桌面尺寸、可读性、无障碍和操作效率调整信息密度与导航呈现，不按图片比例还原页面。
- 图中的姓名、任务、日期、时长、记录、百分比及提醒时间是示例，不作为默认值、计算规则或新增需求。
- 以用户能否理解信息并完成关键操作评估设计，不以与参考图的相似程度验收。

## 与产品文档的关系

领域术语和业务边界见 [CONTEXT.md](../../CONTEXT.md)，产品行为见 [产品设计文档](../product-design.md)，已接受的技术与信息架构决策见 [ADR 0003](../adr/0003-flutter-dart-client-stack.md) 和 [ADR 0004](../adr/0004-core-screen-information-architecture.md)。设计图补充这些文字说明，不替代它们；图片与文字规则冲突时，以相应的文字规则为准。图片未覆盖的流程与状态也不能据此省略。

四个主要目的地、任务完成与专注进度的区别、例外规则和国策日确认等已明确的产品行为，仍按现有文档执行。调整视觉与布局无需复刻参考图；若要改变已确认的业务行为，应先更新对应的产品文档。

## 图片索引

| 页面 / 流程 | 参考图 | 可参考的方向 |
| --- | --- | --- |
| 看板（Board） | [board-reference.png](board-reference.png) | 以任务为首要内容，汇集专注链、国策状态与近期专注活动 |
| 专注链（Focus Chain） | [focus-chain-reference.png](focus-chain-reference.png) | 准备专注、选择任务、进入独立专注会话的流程关系 |
| 我的（My） | [my-reference.png](my-reference.png) | 个人记录、个人资料与全局设置的组织方向 |
| 国策卡片详情与强化等级 | [national-focus-card-reference.png](national-focus-card-reference.png) | 基础规则、具体强化要求与内化进度的区分；原图主要展示详情与强化管理，并非完整卡片库设计 |
| 国策树（National Focus Tree） | [national-focus-tree-reference.png](national-focus-tree-reference.png) | 父子结构、点亮状态、简洁 / 详细视图及日确认入口 |

## 阅读图片时的具体边界

- “我的”图中的“例外规则”入口不代表已确认的信息架构变更；按产品设计文档，Precedent Rule 管理由专注链的扩展菜单进入。
- 专注中的“暂停”和“提前结束”必须进入例外规则流程，不是无条件操作；正常完成仍以倒计时归零为准。
- 看板上的任务专注进度不代表任务自动完成；近期专注活动与只统计已完成会话的专注进度采用不同口径。
- 国策树的连线、颜色、火焰和百分比仅为表达示例，不能用来推导额外的失败、强化或内化规则。相关计算及 04:00 日边界遵循文字定义。

## 命名约定

设计参考资料统一存放于 `docs/design-reference/`。图片使用小写英文和连字符，格式为 `<页面或流程>-reference.png`；目录入口为 `README.md`。避免使用 `final`、`最终版` 等暗示约束力的名称；需要并存多个方案时，使用能说明差异的后缀，并在本索引解释用途。

本次归档保留原始图片内容，路径对应如下：

| 原路径 | 当前文件 |
| --- | --- |
| `design/board-design.png` | `board-reference.png` |
| `design/focus-chain-concept-v2.png` | `focus-chain-reference.png` |
| `design/my-page-concept.png` | `my-reference.png` |
| `design/national-focus-library-final.png` | `national-focus-card-reference.png` |
| `design/national-focus-tree-main-concept.png` | `national-focus-tree-reference.png` |
