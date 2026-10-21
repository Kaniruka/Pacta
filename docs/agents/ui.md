# UI 与技能规范

新增、修改、评审界面或按截图修正布局时读取。依据：任务 Issue、docs/product-design.md、ADR 0003/0004 及相关已接受 ADR、GLOSSARY.md；用户和项目已确认决策优先于技能建议。

## 流程与技能

先读验收条件、产品规则和相邻页面，明确主操作、层级、状态、返回路径；按下表读适用 SKILL.md 并执行，首次使用告知用户。路径从会话技能目录解析，仓库技能通常在 .agents/skills/；缺失时说明并继续可完成部分。仅组合命中技能，非 UI 任务不加载整套。

| 触发 | 技能/职责 |
| --- | --- |
| 页面、布局、交互、响应式、主题、可访问性设计/实现 | ui-ux-pro-max：查询相关 UX/Flutter 指导，新页面建议映射到现有主题 |
| UI/截图/原型/交互评审，含交付前自查 | apple-design：读适用参考并引用依据，转译为 Android/Windows Flutter 原则 |
| 外观/状态模型尚需试验 | prototype：可运行临时原型回答明确问题，记录问题/结果后落地；明确小改直接实现 |
| 共用 token、组件规格/状态体系调整 | design-system：扩展现有主题/组件，不逐页另建颜色、字体、间距 |
| 实际桌面窗口、控件、系统交互 | 会话 computer-use：先读技能再用桌面工具；Android 命令见环境文档 |
| 实现对照规范/Issue | code-review：明确比较基点，分别审查 Standards/Spec，独立保留设计和代码评审证据 |
| Codex MCP 配置、skill 安装、OpenAI 产品用法 | 会话 openai-docs：查官方文档，核验客户端/连接方式，App 引导与已验证行为一致 |
| 技能/AGENTS.md/代理指引编辑 | writing-for-agents |
| 领域词条/ADR 调整 | domain-modeling |
| 故障排查 | diagnosing-bugs |
| 用户要求测试先行/集成测试 | tdd：沿用已确认公开边界，已有授权不重复询问 |

查询示例（仓库根目录；脚本在技能目录内）：

```bash
python3 "$PWD/.agents/skills/ui-ux-pro-max/scripts/search.py" "focus order keyboard" --stack flutter
python3 "$PWD/.agents/skills/ui-ux-pro-max/scripts/search.py" "error recovery action" --domain ux
```

查询仅作建议，采用前核对 Flutter/Android/Windows 适用性及现有设计；--design-system 不自动替换已接受主题。Web/Tailwind/shadcn/Apple 专属习惯不能直接套用。

## UI 要求

- 导航：保留看板、国策树、专注链、我的四目的地及 ADR 0004 职责；主操作可见，次级入口合理，低频设置渐进展开。
- 主题：复用 Flutter Material 3、ThemeData/ColorScheme/TextTheme 和相邻组件；语义颜色区分操作/状态/错误，亮暗可读。新常量在共用主题/组件层有依据，页面不另建品牌。
- 文案：一组内容服务一个目的，沿用领域词汇，按钮直接说动作。常规流程简短；授权/覆盖确认保留后果与恢复路径；仅配置/排错展示技术细节。
- 状态：区分加载、正常空内容/数据、失败、离线、无权限；错误给下一步，重试不重复业务操作。状态不只靠颜色，图标有语义标签。
- 布局：适配窄屏、Windows 可调窗口、长中文和系统大字号。Android 主要命中区至少 48×48 逻辑像素；Windows 检查焦点顺序/可见性、鼠标反馈和滚动。字号沿用语义尺度，不套网页 px/Apple pt。
- 视觉：图标/间距/对齐沿用组件；动画服务反馈并考虑减少动态效果。装饰、玻璃和新图表须帮助任务。

## 验收

实现后做设计评审、行为测试、对应平台检查；逐项处理发现，记录未解决项及依据。仅为改动行为添加必要测试，覆盖受影响入口/操作/状态、窄宽屏、亮暗主题、大字号和可访问性；身份/授权/同步/数据库另做真实服务/RLS验证。

按任务在 Android 模拟器和 Windows 构建、安装或运行，命令与数据保留见 docs/development-environment.md。视觉/可用性靠截图及实际交互，状态/布局用 widget 测试；原生权限/通知/日历及真实桌面行为须对应平台证据。未打开/运行不算目视验收；交付列明改动、实测状态/设备及限制。
