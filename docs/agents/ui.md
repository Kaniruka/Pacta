# UI 与技能规范

新增、修改、评审界面或按截图修正布局时，读取本页适用技能、UI 要求、验收及下表的受影响页面章节。用户和项目已确认决策优先于技能建议；文档职责及真实冲突按[领域指南](domain.md#文档职责与冲突)处理。

## 流程与技能

先读验收条件、产品规则和相邻页面，明确主操作、层级、状态、返回路径；按下表读适用 SKILL.md 并执行，首次使用告知用户。路径从会话技能目录解析，仓库技能通常在 .agents/skills/；缺失时说明并继续可完成部分。仅组合命中技能，非 UI 任务不加载整套。

| 触发 | 技能/职责 |
| --- | --- |
| 页面、布局、交互、响应式、主题设计/实现 | ui-ux-pro-max：查询相关 UX/Flutter 指导，新页面建议映射到现有主题 |
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
python3 "$PWD/.agents/skills/ui-ux-pro-max/scripts/search.py" "navigation list scroll" --stack flutter
python3 "$PWD/.agents/skills/ui-ux-pro-max/scripts/search.py" "error recovery action" --domain ux
```

查询仅作建议，采用前核对 Flutter/Android/Windows 适用性及现有设计；--design-system 不自动替换已接受主题。Web/Tailwind/shadcn/Apple 专属习惯不能直接套用。

## 页面章节入口

| 改动触发 | 必读章节 | 仅在涉及时扩读 |
| --- | --- | --- |
| 看板布局、文案、摘要 | [看板信息层级](../product-design.md#board-content-hierarchy--2026-10-07) | 折叠/描述/分类行为读[看板与描述](../spec-pacta-refinements-20261022.md#看板与描述)及矩阵 R22-01–03 |
| 国策树页面 | 产品设计「Other primary destinations」国策树段；国策画布设计「当前实施方案」 | 视图保存读改进规格「设备视图偏好」；结算行为转领域路由；旧评审只作历史证据 |
| 专注链选择与执行入口 | 改进规格「专注导航与模式」及相关 User Stories | 计时/暂停/结算改变转领域路由；链摘要读产品设计「Chain commitment actions and duration」 |
| 我的、同步卡片及更新提示 | 改进规格「云检查与元数据」及相关 User Stories | 替换/隔离契约转数据库路由 |

导航职责改变读 ADR 0004；平台/栈改变读 ADR 0003。UI 支持范围先读 [ADR 0007](../adr/0007-accessibility-out-of-product-scope.md) 与 [ADR 0008](../adr/0008-large-text-and-keyboard-out-of-product-scope.md)；后者部分替代前者保留的大字号和键盘条款。技能建议服从这些已确认决定，无需再次确认；已有实现、测试及历史证据保留。

## 页面实现与复用

按命中页面查下表符号，再读相邻组件；取得页面要求、实现边界及验收依据即可停止。行为变化另走[领域路由](domain.md#任务章节入口)，仅查对应行。

| 页面改动 | 已有入口与职责 | 验证入口 |
| --- | --- | --- |
| 看板与目标/任务展示 | [lib/main.dart](../../lib/main.dart) 的 `BoardPage` / `_BoardContent` 及目标任务控件；[国策摘要](../../lib/src/board/national_focus_summary_card.dart)已独立。沿用仓储进度投影、描述规范化与已有折叠状态，不在页面另建业务数据 | [看板集成](../../test/board/board_integration_test.dart)、[描述](../../test/board/goal_task_description_test.dart)、[布局](../../test/ui_layout_test.dart) |
| 专注选择/执行恢复 | [lib/main.dart](../../lib/main.dart) 的 `FocusChainPage` / `FocusTaskPickerPage` / `FocusSetupDialog` / `AppointmentPreparationPage` / `FocusSessionPage`；另查 `_TaskTile` 的看板入口和 `AppShell._openFocusFlow` 的通知恢复调度；业务操作复用[领域实现入口](domain.md#现有实现与复用) | [任务导航](../../test/focus/focus_task_navigation_test.dart)、[预约设置](../../test/focus/appointment_configuration_page_test.dart) |
| 国策画布与视图偏好 | [NationalFocusTreePage](../../lib/src/national_focus/national_focus_tree_page.dart) 与 [NationalFocusViewPreferences](../../lib/src/national_focus/national_focus_view_preferences.dart)；本机偏好与业务快照分开 | [国策页面测试目录](../../test/national_focus/)、[真实重启证据](../issue-68-device-validation.md) |
| 我的同步卡片与弹层 | [CloudSyncCard](../../lib/src/sync/cloud_sync_card.dart)复用共享检查和结果状态，跨入口刷新由 App 组合负责；操作面板含“今日确认后自动上传”开关与停止原因，历史页的云端备份和本机恢复点各自加载与重试；检查 `MyPage` 与 `_openAiManualSync` 两处接入参数及下载后刷新，保持受影响入口一致 | [卡片](../../test/sync/cloud_sync_card_test.dart)、[App 级同步](../../test/sync/manual_cloud_sync_app_test.dart)、[自动上传卡片](../../test/sync/cloud_auto_upload_card_test.dart) |
| 共用主题 | [lib/main.dart](../../lib/main.dart) 的 `_pactaTheme`；先取语义主题与现有相邻组件，再决定是否需要公共扩展 | [布局](../../test/ui_layout_test.dart)、[二级页面布局](../../test/ui_secondary_layout_test.dart) |

## UI 要求

- 导航：遵循 [ADR 0004](../adr/0004-core-screen-information-architecture.md) 的目的地及职责；主操作可见，次级入口合理，低频设置渐进展开。
- 主题：复用 Flutter Material 3、ThemeData/ColorScheme/TextTheme 和相邻组件；语义颜色区分操作/状态/错误，亮暗可读。新常量在共用主题/组件层有依据，页面不另建品牌。
- 文案：一组内容服务一个目的，沿用领域词汇，按钮直接说动作。常规流程简短；授权/覆盖确认保留后果与恢复路径；仅配置/排错展示技术细节。
- 状态：区分加载、正常空内容/数据、失败、离线、无权限；错误给下一步，重试不重复业务操作。状态不只靠颜色；图标操作通过可见文字或工具提示说明用途。
- 布局：保证正常字号可读性，适配窄屏、Windows 可调窗口和长中文。Android 主要命中区至少 48×48 逻辑像素；Windows 检查鼠标反馈和滚动。字号沿用语义尺度，不套网页 px/Apple pt。
- 视觉：图标/间距/对齐沿用组件；动画服务反馈并考虑减少动态效果。装饰、玻璃和新图表须帮助任务。

## 验收

- 设计与代码分轴：设计评审对照本页 UI 要求；实现对照规范/Issue 时按「流程与技能」的 code-review 行固定比较基点，分别给出 Standards 与 Spec 结论，各留独立证据。评审发现逐项处理，记录未解决项及依据，修复后用受影响状态的新图复查，不以旧图或差分比率代替。
- 测试只为改动行为补充，覆盖受影响入口/操作/状态、窄宽屏、正常字号可读性、亮暗主题及鼠标／触摸操作；涉及身份/授权/同步/数据库时执行根 AGENTS.md 的服务验证要求。
- 截图按[开发环境](../development-environment.md#工具与平台)的命令取得：一次运行一个独立目录，同名不覆盖，stdout/stderr 与退出码随图保存；前后对照须同 fixture、视口、字号、主题，旧图只作历史，不作最终通过依据。
- 状态/布局用 widget 测试；按任务在 Android 模拟器和 Windows 构建、安装或运行，原生权限/通知/日历及真实桌面行为须对应平台证据。未打开/运行不算目视验收；交付列明改动、实测状态/设备及限制。
- 人工轮的 driver 截图只截应用画面，可能不含系统弹窗、ANR 或输入法面板；原生 ADB／系统截图与 run 目录同源保存，实际打开判读后才算验收（#78 的 IME 图即 ADB 截图）。
- 复用既有截图前运行 `python scripts/run_focus_pilot.py --verify <run_dir>`：以 manifest 开跑前记录为基线，报告 match／missing／mismatch／unsafe／unverifiable；不一致须说明取舍，HEAD 不同不自动作废，未记录依赖不能视为未变更。
- DSH／子 Agent 通道预检失败时停止派工并报告，不自行换通道补设备取证。
