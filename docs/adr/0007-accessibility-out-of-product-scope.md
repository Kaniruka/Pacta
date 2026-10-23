---
status: accepted
date: 2026-10-23
---

# 无障碍支持退出产品范围

> 后续决定：[ADR 0008](0008-large-text-and-keyboard-out-of-product-scope.md) 部分替代下文继续保留的大字号与 Windows 常规键盘条款；本 ADR 其余决定继续有效，原始决定内容保留供追溯。

2026-10-23，产品负责人明确决定：Pacta 长期不再将无障碍支持列入产品范围，也不将其作为实现、评审或发布验收条件。这是已确认的范围取舍，不是暂缓交付；未来如需恢复，须另行确认产品范围。

自本日起，取消读屏（含 Android TalkBack、Windows Narrator）、专用 Semantics、辅助技术适配及无障碍专项测试的强制要求。UI 技能中的相关建议服从此范围，后续 Agent 不得仅据此新增工作、报告范围内缺陷或判定交付阻塞。普通使用所需的可读性、状态文字/图标、亮暗主题、大字号、响应式布局、鼠标/触摸操作以及 Windows 常规键盘操作（Tab、Enter/Space、可见焦点和合理焦点顺序）继续保留。

## 被替代的要求

- `docs/product-design.md` 的目标折叠 accessibility state support；`docs/agents/ui.md` 的可访问性专项覆盖及由技能引入的同类强制要求。
- `docs/spec-pacta-refinements-20261022.md` 用户故事 13 和读屏平台验收；`docs/requirements-refinement-20261022.md`、`docs/tickets-pacta-refinements-20261022/02.md` 中对应要求；`docs/acceptance-matrix-20260914.md` R22-02 的读屏/展开状态朗读验收。
- `docs/national-focus-canvas-design.md` 当前方案中的可访问性文字及辅助技术标签强制要求。
- GitHub #63/#65 等关联需求中仍被引用的同类验收项；同步结果见 [范围核查记录](../accessibility-scope-change-20261023.md)。

## 兼容与追溯

ADR 0001–0006 均已检查，没有明确要求无障碍支持；本决策补充 ADR 0003 的交付范围与 ADR 0004 的界面职责边界，二者继续 accepted，无须整体替代。已有实现、测试及证据保留，本次不修改应用代码或删除测试。历史验收、曾发现的缺陷和当时的豁免只描述其记录时期；过去未执行的读屏检查不再成为未来交付欠项，也不追溯改写为已通过。
