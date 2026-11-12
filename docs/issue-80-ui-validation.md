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

后续取证健全性修正：写入前遇同名文件明确失败，PNG 编码为空也明确失败；未指定目录的 reference 截图使用时间戳子目录。相同两文件在唯一目录 `build/issue80-widget-20261112-04/` 重跑 8 项通过、退出码 0，分析再次无问题（`build/issue80-analyze-capture-guard.log` / `.rc`）。故意重复该目录运行少量节点用例，退出码 1，日志 `build/issue80-capture-overwrite-guard.log` 出现 `Refusing to overwrite`，既有图片 SHA256 前后相同。这一预期失败只用于核验保护生效。

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

## 主线程原生补验（2026-11-13）

主线程独立运行本票三个 widget 测试文件：28 项通过。全规格集成分支另有完整 354 项通过，日志位于主树 `build/spec75/root-checks/`。

现有 `integration_test/issue_68_view_memory_device_test.dart` 补充隔离取证保护：seed 遇到已有同名数据库拒绝替换，要求新 RUN_ID；截图文件包含 RUN_ID、拒绝覆盖及空编码；可选 `ISSUE68_VIEW=narrow` 只在 Windows 设置 546×682 逻辑渲染视口并记录 native/render 两种尺寸。Android 不覆盖原生尺寸。没有改变产品偏好代码或用户数据。

两平台均以同一平台内相同 RUN_ID 顺序执行 `seed` 与 `restored-detailed`，每阶段单独启动进程，均为退出码0、1完整场景通过。命令使用 `flutter test --no-pub --no-uninstall integration_test/issue_68_view_memory_device_test.dart -d <device> --dart-define=ISSUE68_PHASE=<phase> --dart-define=ISSUE68_RUN_ID=<run>`。

| 平台 | RUN_ID | seed PID → restored PID | 结果 |
| --- | --- | --- | --- |
| Windows | spec75_20261113_w1 | 45612 → 55220 | 保存详细，新进程恢复详细，再切回简洁；同一隔离SQLite卡片保留 |
| Android emulator-5554 | spec75_20261113_a1 | 10091 → 10210 | 同上；1080×1920、density420，约411×731 |

`restored-detailed` 在断言恢复详细后会切回简洁再截图，因此该PNG显示简洁；恢复详细依据是不同PID与该阶段已通过的真实持久化断言，不把截图误读为详细。

Windows 另以 `spec75_20261113_wn1` 的新隔离seed通过窄视口：日志记录 native1265.6×682.4、render546×682，未声称原生拖窗。主线程实际打开窄暗图及Android亮色seed/恢复图：页头、次级入口、适应屏幕和视图模式可读，无新增布局问题。

本工作树原始证据目录：`build/issue80-native-windows-20261113/`、`build/issue80-native-android-20261113/`，每个阶段 `.log/.rc/.png`。Windows纯内存四节点demo也由主线程实际打开，通过sky鼠标切换详细及适应屏幕；截图保存在主树 `build/spec75/issue80-native-ui/windows-wide-{simple,detailed}.png`。桌面出现用户操作后停止窗口抢占，其余验证采用隔离设备测试，未控制Codex界面。

Android画布手势及节点操作续验结果另补；首轮手势入口在测试开始前因debug log reader中断退出，未把未启动的场景记为功能通过。

Android手势补验最终通过：`canvas-final.log/.exitcode` 为1测试、rc0；`tree-actions-final.log/.exitcode` 为1测试、rc0。主线程核对原始日志与最终diff。首个真正执行的画布轮失败源于样例页面在当前原生高度恰好无溢出（maxScrollExtent=0），不是单指被画布抢占。仅给测试页面500逻辑像素短高约束并增加maxScrollExtent>0前提；原单指滚动不平移画布、双指缩放/平移断言全部保留。诊断中实测maxExtent139.43、viewport500，最终去除debug日志后仍通过。节点操作原入口未修改，原生进入库、添加子节点和更多记录路径通过。

归档后的稳定本地证据根为主树 `build/spec75/evidence/80/`，保留原工作树相对路径；PNG和日志逐文件SHA256校验。上文原路径保留作取证来源，不依赖工作树继续存在。Windows手动预览图另留主树 `build/spec75/issue80-native-ui/`。没有把Android测试边界/PNG当作真实云服务证据。
