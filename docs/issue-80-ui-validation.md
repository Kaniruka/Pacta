# #80 国策树页头与画布核验

2026-11-12。开始实施 HEAD / 实现审查比较基点：`b0332493dd5b8184a036aab925e0ebdec0b3a71b`；设计基线：`ui-focus-pilot-accepted-20261112`。规格为 #75 用户故事 10 和 #80。

## 结论与边界

本轮没有复现需要修改生产页面的呈现缺陷，保留现有实现，不改领域、偏好契约或节点几何。标题与“全部确认”同组，其下是视图、卡片库、更多；320 正常字号仍可点。放置时已有带卡片名的“选择位置：点顶层或一个节点”说明、顶层目标及取消入口，视图与卡片库禁用；这满足可见状态说明要求，不额外扩写文案。

546×400 的画布会超出首屏，但可用页面滚动访问；这属于已确认的页面滚动与画布手势分工，不因不能一次展示全画布而判缺陷。50 节点整树适应后文字很小，放大阅读仍由现有手势支持。

这是 widget 取证结果，不能替代 AppShell 中实际 Android/Windows 字体、窗口、鼠标/触摸与系统边距验证。设备未启动，也未声称完成设备验收、真实进程重启或独立双轴评审。

## 实际命令与证据

工作树：`C:/Users/Stray/.codex/worktrees/spec75-t80/Pacta`。初始三文件测试 27 项通过，日志 `build-issue80-baseline.log`。生产源码从初始基点起未修改，因此最终截图也可核验同一页面实现。

```powershell
$env:PACTA_UI_FONT='C:/Windows/Fonts/msyh.ttc'
$env:PACTA_UI_EVIDENCE_DIR='build/issue80-widget-20261112-03'
flutter test --no-pub test/national_focus/national_focus_tree_page_test.dart test/national_focus/national_focus_view_preferences_test.dart test/national_focus/national_focus_reference_canvas_test.dart --reporter expanded
flutter analyze --no-pub
```

最终测试 28 项通过，合并 stdout/stderr：`build/issue80-widget-20261112-03.log`，退出码：同名 `.rc`，值 0。改动 Dart 文件已执行 `dart format`。`flutter analyze --no-pub` 为 No issues found，退出码 0，见 `build/issue80-analyze.log` 和 `.rc`。清空上述可选环境变量的默认字库回归 `flutter test --no-pub test/national_focus/national_focus_reference_canvas_test.dart test/national_focus/national_focus_view_preferences_test.dart --reporter expanded` 也为 8 项通过、退出码 0（`build/issue80-default-tests.log` / `.rc`）。

截图目录 `build/issue80-widget-20261112-03/`（本机忽略资产）：

- `small-320-pending.png`：三棵树内卡、一个库卡，320×800、正常字号、绿色亮主题、待确认。
- `small-320-placement.png`：同一 fixture，确认后打开卡片库进入放置模式；验证禁用入口不会导航/打开菜单、取消恢复。
- `small-short.png`：同一 fixture，546×400，取消放置后；更多仍可进入记录页。
- `wide.png` / `narrow.png` / `compact.png` / `short.png`：50 节点，1265×682 / 546×682 / 320×800 / 546×400，适应后双指平移。
- 对应 `*-detailed.png`：同一 fixture 切换详细并重新适应屏幕。
- `preferences-read-failure-dark-320.png`：320×800 暗主题读取失败及重试入口。
- `preferences-save-failure-320.png`：320×800 亮主题保存失败及重试入口；现有测试继续验证重试后页面重建恢复详细视图。

取证可通过两个可选进程环境变量复跑：`PACTA_UI_FONT` 加载本机中文字库（不提交字体），`PACTA_UI_EVIDENCE_DIR` 指定本次唯一输出目录。默认测试不依赖 Windows 字体。截图加载 MaterialIcons，并包含 Scaffold 底色。首次扩展跑次 `01` 因测试清理计时器及短窗滚动等待不足失败，修正测试清理与 `pumpAndSettle` 后 `02`、最终 `03` 通过；没有为此修改产品代码。

## 设计自查与实现自查（非独立评审）

设计依据为 UI 指南及 apple-design 的 `layout.md › Visual hierarchy / Adaptability`（相关动作分组、按可用空间布局）、`menus.md › Labels`（次级动作渐进披露）与 `scroll-views.md › Best practices`（滚动和缩放边界）。转译为 Flutter Material/Android/Windows 原则，不套 Apple 导航或材质。ui-ux-pro-max 查询 `responsive scroll constraints --stack flutter` 返回 LayoutBuilder 与 CustomScrollView 建议；现有布局与其一致。ADR 0007/0008 的读屏、大字号与专门键盘排除继续适用。

Standards 自查：只扩展现有页面/偏好测试；生产页头组件、集中禁用条件和本机偏好实现未动。Spec 自查：补正常字号窄窗、短窗和放置操作；50 节点沿用唯一 reference fixture，保留现有手势、恢复视图、错误重试与隔离回归。没有以半径或间距偏好创建改动。主 Agent 需完成独立设计评审与 Standards/Spec 审查后填写最终结论。

## 设备续验入口

主 Agent 统一协调设备，使用已有内存预览，不加载 `.env`、不连接云、不改用户数据：

```powershell
flutter run -d windows -t tool/national_focus_ui_review_demo.dart
flutter run -d <android-device-id> -t tool/national_focus_ui_review_demo.dart
flutter run -d <device-id> -t tool/national_focus_reference_demo.dart
flutter test integration_test/national_focus_tree_actions_device_test.dart -d <device-id>
flutter test integration_test/national_focus_canvas_gestures_test.dart -d <device-id>
```

少量节点预览已有三态，50 节点入口已有完整树与手势。Android 411×731，Windows 1265×682 / 546×682；另手调短高窗口。先截打开页头，切详细后 fit，放大阅读、平移及普通页面滚动，再进入库发起放置并截禁用/取消状态，最后核验更多记录页。每次独立目录保存截图、命令输出及退出码；本轮未运行以上设备命令。保存中和实际进程重启沿用视图偏好设备验证边界，由主 Agent 取证，不把 widget 页面重建记作真实重启。
