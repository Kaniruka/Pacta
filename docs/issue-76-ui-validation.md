# Issue 76 看板任务列验证

实施基点 `b0332493dd5b8184a036aab925e0ebdec0b3a71b`；设计基线 `ui-focus-pilot-accepted-20261112`。范围仅目标/任务呈现与既有离线取证入口，不修改支撑摘要、专注或数据规则。

## 基线与问题

- 开始时工作树干净。原有 `flutter test test/board/board_integration_test.dart test/board/goal_task_description_test.dart`：6 个通过。
- 在 AppShell + 真实内存仓储边界增加 320×800 正常字号测试，长任务含 120 分钟、已专注 13分00秒、待核对与 2026-11-15 18:30 截止。修改前 RenderParagraph 的 `didExceedMaxLines` 为 true，新增测试失败。
- Windows 546×682、DPR 1.25、正常字号、暗色实际运行截图中，元信息在待核对说明中途省略，截止完全隐藏。目标摘要强制两行。
- 基线首轮编译失败是 fixture 引入 FocusSession 的导入歧义，随后修复 hide；第二轮已取展开/折叠图，但后续鼠标开始入口步骤因 ensureVisible 后未等待布局失败。两轮日志保留，不计为通过。修复仅测试等待。

## 设计依据

读取项目 UI 指南、看板信息层级、改进规格看板与描述及 ADR0007/0008。沿用 Material 3 和语义文字尺度。ui-ux-pro-max 的 Essential Text Truncation 建议关键含义换行/堆叠；Flutter 指导按约束自适应。apple-design 转译为 Flutter 原则：`layout.md › Visual hierarchy / Adaptability` 以重要性排序并适应窗口，`lists-and-tables.md › Content` 保持窄表文字可辨识，`typography.md › Conveying hierarchy` 用现有字号与颜色区分层级，`labels.md › Best practices`、`dark-mode.md › Dark Mode colors` 使用语义文字颜色。Apple 平台专属样式不迁移，大字号/键盘/读屏要求按项目 ADR 不作为验收。

## 实施与最终验证

- 目标摘要由强制换行改为 `任务数 · 状态`，用现有 bodySmall / onSurfaceVariant；宽度不足仍自然换行。
- 元信息用 Wrap 按预计时长、已专注、待核对完整说明、截止四组自然换行；保留复选框、完成线、标题两行、描述一行、右侧开始入口与原事件处理。
- 新增 320×800 正常字号真实仓储测试，逐项检查可见文本不被截断、开始按钮位于视口内并进入设置/取消；新增 546×682 摘要与折叠高度测试。两条均先观察红灯，再作最小修正。现有摘要文字/语义字号断言同步更新。
- `dart format lib/main.dart test/board/board_integration_test.dart test/board/goal_task_description_test.dart integration_test/board_design_device_test.dart`：无待格式化文件。
- `flutter analyze --no-pub`：No issues found（10.0s）。
- `flutter test --no-pub test/board test/ui_layout_test.dart test/focus/focus_task_navigation_test.dart`：24/24 通过。
- `python -m unittest scripts.test_run_focus_pilot`：既有 runner 测试及新增 board target 测试共12/12通过。runner 新增 `--target board` 选择既有看板测试，默认 focus 路径不变；board 输出独立 board-pilot/runs；源码快照包含看板 fixture。使用既有 FOCUS_PILOT_* 参数/通用截图 driver，无新框架。

## Windows 前后图与交互

本机绝对证据根为 `C:/Users/Stray/.codex/worktrees/spec75-t76/Pacta/build/ui-layout-evidence/board-pilot/runs/`。每轮均保留 run.log、run.rc、manifest.json 与 PNG；清单含 HEAD、实参、源码起止 SHA256 和漂移结果。以以下 stable 前图为准：之前的成功取图因样例所有 updatedAt 相同，任务排序可能漂移，后续改用递增样例时钟后重取前图。未改真实仓储排序。

| 运行目录 | 条件 | 结果 |
| --- | --- | --- |
| t76-baseline-stable-narrow-long-narrow | 原 main，546×682、DPR1.25、正常字号、暗 | rc0，source_drift=[] |
| t76-baseline-stable-wide-long-wide-light | 原 main，1265×682、DPR1.25、正常字号、亮 | rc0，source_drift=[] |
| t76-final-narrow-long-narrow | 最终 main，与窄暗前图相同 fixture/视口/字号/主题 | rc0，source_drift=[] |
| t76-final-wide2-long-wide-light | 最终 main，与宽亮前图相同 fixture/视口/字号/主题 | rc0，source_drift=[] |
| t76-final-empty-zero-narrow-light | 最终 main，空看板，546×682、正常字号、亮 | rc0，source_drift=[] |

每个 long 目录的 `board-long-<view>-expanded.png` 为首屏，`collapsed.png` 为目标折叠后，`restored.png` 为编辑保存并恢复标题后。Windows 运行中采用 PointerDeviceKind.mouse 完成标题折叠/展开、目标编辑取消与删除取消（保持折叠）、任务编辑取消/保存/恢复、开始设置及取消；每一步有可见界面断言，未点击确认删除，不触碰用户库。该证据是 Windows 上 Flutter 鼠标事件自动化，不另宣称物理鼠标人工测试。

## 设计轴独立复核

主审实际打开同状态窄暗前后图：

- `t76-baseline-stable-narrow-long-narrow/board-long-narrow-expanded.png`
- `t76-final-narrow-long-narrow/board-long-narrow-expanded.png`

主审结论：目标摘要单行更紧凑；预计/已专注/待核对完整解释/截止均可见；开始按钮保持，符合父规格 US1–4，未见新增设计问题。实现者也实际打开窄暗展开/折叠图，确认目标标题及描述保留、折叠任务隐藏、元信息完整。折叠截图因测试将目标滚至顶部后操作，首屏滚动位置与展开图不同；折叠高度另以 widget 测试验证至少减少100逻辑像素，不把视口差异当作高度证据。

主审另实际打开 stable-wide-light 前图与 final-wide-light 展开图：主列/支撑列稳定，宽窗截止由隐藏变为可见，摘要收紧后无层级倒置；宽亮设计初审通过。实现者实际打开最终通过的 wide2 展开图及空态图：关键元信息完整、开始可见、空态保留新建主操作，无新增布局问题。

`t76-final-wide-long-wide-light` 已完成三图和所有交互，但测试收尾报 “A SemanticsHandle was active at the end of the test” 并 rc1；不能算通过。未关闭框架检查、未改源码，不变重跑的 wide2 为 rc0，原失败日志保留。仅单次不复现，原因未确定，不将其解释成已修复产品缺陷。

## 实现轴与边界

实现自查相对 b033249：Standards 使用现有 bodySmall、onSurfaceVariant 与 ListTile 默认语义样式；无品牌色/字体常量，无新导航/数据字段；仅目标摘要及任务元信息改变。Spec 对应 US1–4：主操作和任务优先位置保持，摘要紧凑且自然换行，关键事实完整，折叠和编辑/开始事件代码未变，并有真实仓储路径测试与 Windows 鼠标事件证据。独立 Standards / Spec 审查由主线程在实施提交上执行，尚未伪记通过。

Android 由主线程协调，实施者没有运行 Android，也没有接触物理设备。411×731 正常字号、触摸折叠/编辑取消/保存与截图需后续平台证据；同一 fixture 的 Android 分支已支持。320×800 为 widget 几何/可读性/操作测试，不提供 Ahem 默认测试字体下的视觉截图。Windows 运行和本地截图不替代 Android 验收。未改身份、同步、权限、数据库或原生能力，因此不报告相关真实服务验证。
