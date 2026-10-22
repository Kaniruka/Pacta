# 无障碍产品范围调整核查（2026-10-23）

依据：产品负责人本日明确的长期范围决策，以及已接受的 [ADR 0007](adr/0007-accessibility-out-of-product-scope.md)。本次仅调整文档与 GitHub Issue 要求，未修改应用、平台、测试代码或既有证据。

## 取消与保留

取消读屏（TalkBack/Narrator）、专用 Semantics、辅助技术适配及无障碍专项测试的强制要求；实现、评审和发布验收均不以这些内容为条件。UI 技能的同类建议服从本项目范围，不能自动引入任务或阻塞。

保留普通可读性、亮暗主题、系统大字号、状态文字与图标、工具提示、响应式布局、鼠标/触摸，以及 Windows 常规键盘（Tab、Enter/Space、Escape、可见焦点及合理顺序）。已有实现和测试保留，不因退出范围而删除。

## 检查覆盖与冲突

- 全仓 Markdown 关键词检查包括：无障碍、可访问性、读屏、辅助技术、TalkBack、Semantics、accessibility、a11y、screen-reader、Narrator、WCAG 等；技能目录作为通用建议来源，由 `docs/agents/ui.md` 明确项目适用边界，未改写通用技能。
- 已检查全部 ADR 0001–0006，无明确无障碍强制条款；新 ADR 补充交付范围，未废弃既有技术栈与导航职责。
- 现行设计、规格、需求细化、票据模板和验收矩阵均已同步。核心规格与 MCP 规格增加现行范围指针。
- 历史设计审查、验收记录、过去未完成项及 Windows 当时的单端豁免原文保留，并加注调整前的适用时期；不将过去未测项改写为已通过。
- 未发现尚未解决的现行要求冲突。历史文本和通用技能仍可能出现无障碍要求，但有明确的时间/适用范围说明，不再形成当前交付义务。
- 既有规格/票据中的旧实施状态快照不属于本次状态整顿范围；本次不据此推定实现进展或重新验收。

## GitHub Issues

使用 Windows `gh.exe` 检查全部状态的 51 条 Issues 及评论。开放规格 [#63](https://github.com/Kaniruka/Pacta/issues/63) 的现行要求按本决策调整，并[追加依据说明](https://github.com/Kaniruka/Pacta/issues/63#issuecomment-6345635145)。已关闭 [#65](https://github.com/Kaniruka/Pacta/issues/65) 仅[追加范围说明](https://github.com/Kaniruka/Pacta/issues/65#issuecomment-6345636493)，保留已完成的 Android TalkBack 修复、测试和历史验收事实。#66–#72 的布局和普通操作标准保留；#64、#50、#51、#60、#37 中仅历史事实，无待取消的专项验收要求。

## 修改文件

- [docs/acceptance-matrix-20260914.md](acceptance-matrix-20260914.md)
- [docs/agents/ui.md](agents/ui.md)
- [docs/chain-signals-validation-20261007.md](chain-signals-validation-20261007.md)
- [docs/focus-chain-design-20261007.md](focus-chain-design-20261007.md)
- [docs/issue-59-validation.md](issue-59-validation.md)
- [docs/issue-60-validation.md](issue-60-validation.md)
- [docs/issue-61-validation.md](issue-61-validation.md)
- [docs/issue-62-validation.md](issue-62-validation.md)
- [docs/issue-64-validation.md](issue-64-validation.md)
- [docs/issue-65-android-reacceptance.md](issue-65-android-reacceptance.md)
- [docs/issue-65-validation.md](issue-65-validation.md)
- [docs/issue-65-windows-reacceptance.md](issue-65-windows-reacceptance.md)
- [docs/national-focus-canvas-design.md](national-focus-canvas-design.md)
- [docs/national-focus-code-review-20261006.md](national-focus-code-review-20261006.md)
- [docs/national-focus-design-review-20261005.md](national-focus-design-review-20261005.md)
- [docs/national-focus-ui-polish-20261006.md](national-focus-ui-polish-20261006.md)
- [docs/product-design.md](product-design.md)
- [docs/requirements-refinement-20261022.md](requirements-refinement-20261022.md)
- [docs/spec-focus-loop-and-core-shell.md](spec-focus-loop-and-core-shell.md)
- [docs/spec-national-focus-ai-mcp.md](spec-national-focus-ai-mcp.md)
- [docs/spec-pacta-refinements-20261022.md](spec-pacta-refinements-20261022.md)
- [docs/tickets-pacta-refinements-20261022/01.md](tickets-pacta-refinements-20261022/01.md)
- [docs/tickets-pacta-refinements-20261022/02.md](tickets-pacta-refinements-20261022/02.md)
- [docs/ui-layout-audit-20261004.md](ui-layout-audit-20261004.md)
- [docs/adr/0007-accessibility-out-of-product-scope.md](adr/0007-accessibility-out-of-product-scope.md)
- [docs/accessibility-scope-change-20261023.md](accessibility-scope-change-20261023.md)

## 验证

执行 `git diff --check`，通过。复核新增 ADR 链接、修改文件范围及现行要求的关键词残留；只改 Markdown，未运行 Flutter/Dart 测试，也未重新执行设备或辅助技术验收。
