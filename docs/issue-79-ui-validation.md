# Issue #79 同步呈现验证

## 范围与基点

- 产品设计基线：`ui-focus-pilot-accepted-20261112`；实施比较基点：`b0332493dd5b8184a036aab925e0ebdec0b3a71b`。
- 仅修改 `CloudSyncCard` 呈现、既有同步测试及 Issue69 设备入口；快照、指纹、RLS、同步事务、主导航均不变。
- 使用 ui-ux-pro-max、apple-design 与 TDD。测试边界按 #75 已确认的 AppShell + 真实本地仓储；只替换认证与外部云端，不测试私有状态或调用顺序。技能目录在主仓 `.agents/skills`，本工作树未复制技能。
- ADR0007/0008 适用：正常字号、亮暗主题、鼠标/触摸及系统返回保留；既有 200% 测试保留执行，不新增无障碍/键盘专项。

## 观察与局部修改

基线 320×800、正常字号、亮主题的 AppShell 截图中，成功时间被右侧半宽约束拆成日期与时分秒两行；标题及入口可达，没有宣称溢出。字体未加载的常规 widget 测试测得状态高 64，而单行上限 20。局部修改依据是本票单行状态职责：实际卡片内部可用宽度小于 400 时，标题/图标/箭头保持一行，完整状态独占下一行；宽端保持原并列布局。未裁切时间、未缩字，状态优先级与文字集中到同一 getter。

基线选择层的覆盖说明是按钮上方通段，下载、上传与忽略、取消并列，窄端会换排。将下载和上传分别移入既有内部滚动区，每行用明确覆盖目标和独有记录丢弃后果紧邻方向按钮；忽略/取消仍固定在页脚。未结束流程原因紧邻下载区域，下载保持禁用；两个方向仍须分别选择、二次确认。后续设计复查移除重复通用覆盖句，仅保留“设备设置和登录状态不变。”，完整警告仍在对应方向与二次确认中。

设计依据（从技能本地参考读取，转译为 Flutter Android/Windows 原则）：

- `layout.md › Visual hierarchy`：“Group related items to clearly express related information or functions.” 后果按方向成组；不借用 Apple 专属尺寸。
- `layout.md › Adaptability`：布局适应可用空间，窄端保持相同功能；本票仅按组件实际约束改变摘要排列。
- `modality.md › Best practices`：“Always give people an obvious way to dismiss a modal view.” 取消/忽略分离，退出一直可见。
- ui-ux-pro-max Flutter 查询 `dialog scroll responsive` 命中 LayoutBuilder/约束响应式建议；`compact status wrapping` 的 Web 长词建议只作参考，未套 CSS 或网页字号。

## TDD 与回归

依次完成两个 red→green 切片：

1. AppShell 320 正常字号成功状态单行断言先失败（实测 64 > 20），仅调整摘要约束后通过。
2. 同一公开入口的方向后果断言先失败（找不到“覆盖云端，丢弃云端独有记录。”），将方向与后果成组后通过；验证上传按钮与对应后果垂直距离小于 60，滚动后可达。

受影响既有同步测试对位于内部滚动区的方向先 `ensureVisible` 再点击，继续验证真实仓储效果，而非控件嵌套。既有首次上传、下载覆盖、只读检查时间不变、跨入口结果刷新、取消不忽略、当前版本忽略、未结束流程禁下载、失败重试与用户隔离测试保留。

已执行：

- `dart format` 受影响六个 Dart 文件。
- `flutter test --no-pub test/sync`：64 项通过（最终日志 `build/issue79/sync-tests-final.log`，rc 0）。
- `flutter analyze --no-pub`：首次发现新增截图辅助函数 if 缺花括号，已修正；最终 `No issues found!`、rc 0（`build/issue79/analyze-final.log`）。

## 同 fixture 截图与设备

Windows 工作树根：`C:/Users/Stray/.codex/worktrees/spec75-t79/Pacta`。

Widget 证据另存主仓 `F:/Workspace/Release/Flutter/Pacta/build/spec75/issue79/`：

- `baseline-widget-fixed/{summary-320,choice-320}.png`
- `final-widget-dedup/{summary-320,choice-320,directions-320}.png`（最终去重后版本，widget-final-dedup.log/rc 均保存，rc 0）
- 同一离线真实仓储 fixture、320×800、正常字号、亮主题；显式加载本机微软雅黑与 MaterialIcons 字体。早期 `baseline-widget` 未冻结时钟且图标方框，仅作调查记录，不作为最终比较。
- 截图命令：`flutter test --no-pub test/sync/issue_79_sync_presentation_test.dart --dart-define=ISSUE79_CAPTURE=<唯一绝对目录>`；基线源另加 `--dart-define=ISSUE79_BASELINE=true`。同名图片拒绝覆盖。

Android：AVD `PactaFocusPilot20261112` / `emulator-5554`，1080×1920 / density420，约411×731逻辑像素，正常字号，亮主题。既有 Issue69 设备入口 `ISSUE69_PHASE=ui79` 使用独立内存数据库，固定用户名 `issue79-ui-fixture`、任务/树时间 2026-11-12 10:00、本机成功/云上传时间 10:30，云端为内存适配器。

- 基线：`build/ui-layout-evidence/issue79/android-baseline-fixed-20261112/` 中 `ui79-79-baseline-fixed-20261112-{summary,choice}.png`。
- 最终去重后：`build/ui-layout-evidence/issue79/android-final-dedup-20261112/` 中 `ui79-79-final-dedup-20261112-{summary,choice,unfinished}.png`。`android-final-fixed-20261112` 是去重前中间证据，不作为最终图。
- 这两组 initial summary/choice 同 fixture/主题/视口/时钟，设备实际运行、打开、系统返回、再次打开及取消均通过。unfinished 为之后创建的真实本地流程，运行时开始时间不同，仅作为下载禁用与原因可见的状态证据，不作像素前后比较。
- 命令：`flutter drive --no-pub --driver=test_driver/ui_layout_acceptance_test.dart --target=integration_test/issue_69_sync_result_device_test.dart -d emulator-5554 --dart-define=ISSUE69_PHASE=ui79 --dart-define=ISSUE69_RUN=<唯一run>`，driver 环境 `UI_EVIDENCE_SUBDIR=issue79/<唯一目录>`、`UI_EVIDENCE_FAIL_ON_EXIST=1`。stdout/stderr 与退出码见 `build/issue79/android-baseline-fixed.{log,rc}` 与 `android-final-dedup-supported.{log,rc}`，两者 rc 0。driver 不支持 `--no-uninstall`（选项错误日志保留为 `android-final-dedup.log`），实际运行去除该选项，没有另行卸载或清数据。Windows `flutter test` 均使用 `--no-uninstall`。
- 已目视打开两组 choice、最终 summary 与 unfinished：原生 Material 图标正常，来源和时间可读，后果与方向对应，禁用原因可见，取消/忽略可辨。截图成功或无 overflow 不单独作为视觉通过理由。

Windows 实际窗口、正常字号、系统暗主题，DPR 1.25。未设 `physicalSize` override。已运行并目视打开宽窄最终 choice 图及窄基线 choice，方向与后果对应、来源时间可读、居中边界清楚。

| 轮次 | 实测 logical | 截图目录（工作树 build/ui-layout-evidence/issue79/） | 日志/rc（build/issue79/） |
| --- | --- | --- | --- |
| 宽基线 | 1265.6×682.4 | windows-baseline-wide | windows-baseline-wide，0 |
| 宽最终 | 1265.6×682.4 | windows-final-wide | windows-final-wide，0 |
| 窄基线 | 536.8×682.4 | windows-baseline-narrow2 | windows-baseline-narrow2，0 |
| 窄最终 | 536.8×682.4 | windows-final-narrow | windows-final-narrow，0 |

各目录含 `ui79-<ISSUE69_RUN>-{summary,choice,unfinished}.png`。initial summary/choice 的前后图同 fixture、主题及实际视口；窄端比规格546宽小9.2逻辑像素，按实际值报告，不声称精确546通过。原生窗口缩窄后仍完整显示同步内容与可达操作。

命令沿用 `flutter test --no-pub --no-uninstall integration_test/issue_69_sync_result_device_test.dart -d windows --dart-define=ISSUE69_PHASE=ui79 --dart-define=ISSUE69_RUN=<唯一run> --dart-define=ISSUE79_CAPTURE_DIR=<唯一目录>`；需要真实调整时加 `--dart-define=ISSUE79_HOLD_SECONDS=45`（基线成功轮为90），出现 `ISSUE79_RESIZE_READY` 后用 Computer Use / sky 操作。方法为原生系统菜单 `Alt_L+space` → `s`（大小）→ `Right`（右边界）→ 按最新截图右缘 `drag(1265,400 → 545,400)`。每步刷新观察；测量依据为 `ISSUE79_SCREENSHOT ... logical=... dpr=...` 日志，不按截图文件名推断。上述键序列只是窗体取证辅助，不是产品专门键盘验收。

首次 `windows-baseline-narrow` 直接拖截图最右内容边缘，触发了 Flutter 内容点击且未缩窗，运行未完成；该目录和日志保留为无效调查记录，不作通过证据。系统菜单成功轮才作为窄窗比较。

## 分轴复查与限制

- Standards 自查：平台分支仍只在 `_showModal`；状态优先级/文案未分叉；使用既有主题角色、按钮、间距与内部滚动，没有页面新主题。
- Spec 自查：方向无默认、两次确认、只读检查不更新成功时间、忽略只针对当前版本、取消/返回不写忽略、未结束流程禁下载均沿用原业务实现和回归测试。
- 独立设计/Standards/Spec 评审由主线程汇总；本记录不将自查冒充独立评审。
- 未执行真实云服务往返/RLS：本票没有业务/同步权限边界变化，按 #75/#79 不作为视觉门槛。


## 最终产物校验

`cloud_sync_card.dart` SHA256：`3E8E5C44136CC91BA0235530652A830141690A78298E325E0E77D7A24EFC7B72`。去重后 Android 源 hash 保存在 `build/issue79/android-final-dedup-sourcehash.txt`，最终格式化为 0 changes；`git diff --check` 通过。设备初始两图基线生产源来自比较基点，最终两端生产源为上述 hash。

集成复核：将 incoming integration/spec-75-ui 合入本票分支（merge 65d553f）后，再次执行 flutter analyze --no-pub（No issues found，rc 0）与 flutter test --no-pub test/sync（64项通过，rc 0）。日志为 build/issue79/analyze-after-merge.log 和 sync-tests-after-merge.log。未push、未创建PR、未关闭Issue。

## 证据归档定位

原工作树路径和原 manifest 保留作历史溯源；本票图片及日志已保全到主树稳定根 `F:/Workspace/Release/Flutter/Pacta/build/spec75/evidence/79/`，下接本文所列原工作树相对路径（包括 `build/`）。归档不改写证据记录的提交、源码哈希、设备或视口；Windows 实际536.8×682.4等实测值及原失败限制继续适用。
