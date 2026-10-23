# Issue #66：专注链二级任务选择与执行恢复

日期：2026-10-23。实施基点 `337caa4ea980457fc53f40eb2bc92d2d8d9189c1`，分支 `master`；开始时工作区干净。范围为 [Issue #66](https://github.com/Kaniruka/Pacta/issues/66)，沿用专题规格 Testing Decisions 的真实 AppShell＋本地仓储/Drift 边界。验收完成；跨重启的统一模式记忆仍由 #67 承担。

## 实现

专注主页只显示未删除且未完成任务数量、任务选择入口、已有流程恢复、链摘要与历史。独立任务选择页提供全部/精锐/普通筛选和目标、分类、预计时长、专注进度；两者分类进入两个模式，未设置预计时长如实显示。设置取消及返回保留筛选和列表位置。启动后由主页进入执行页，执行页返回主页，流程继续。主页入口和任务选择均先恢复现有活动/暂停/预约，不因原任务完成或删除而另建流程。

保留主页生存期的成功启动模式记忆，入口防止重复打开。未改仓储计时、暂停依据、失败结算、15分钟预约自动交接及云端数据协议。测试数据库与现有用户数据隔离，无 Supabase 写入。样例数据和参数仅在独立验收入口，不进入产品流程。

## 自动化验证

所有 Flutter/Dart 命令由 WSL 通过 `cmd.exe /c` 调用 Windows SDK。

| 命令/边界 | 实际结果 |
| --- | --- |
| `dart format` 所有改动 Dart 文件 | 完成 |
| `flutter analyze` | No issues found |
| `flutter test test/focus/focus_task_navigation_test.dart` | 7 passed |
| `flutter test` | 279 passed |
| `flutter test integration_test/issue_66_focus_navigation_device_test.dart -d emulator-5554 --no-uninstall` | 1 passed |
| 同一原生设备测试 `-d windows` | 1 passed |
| `git -c core.whitespace=cr-at-eol diff --check` | 通过；保留已有 CRLF 文件行尾 |

初始 App 红测试在旧实现上因主页仍展示任务失败。新增回归覆盖 60 项任务、360×800、2 倍字号/暗色、取消与返回保留可见位置、启动后返回主页，以及原任务完成并删除后恢复三类原流程身份。实际 Android 预约准备页发现长标题下拉项横向溢出，新增 App 回归先报 RenderFlex overflow 379px；修复下拉项宽度与单行省略后通过，完整任务名仍在页首。

原生测试使用隔离文件 SQLite、80 项任务、实际累计进度及完成/删除任务；覆盖两个启动路径、恢复不重复创建、暂停和预约分别复开数据库后的原 ID、预约进入专注的关联 ID。数据库复开是仓储/应用重建证据，不声称是真实进程冷启动。

首轮设备用例暴露测试夹具排序/滚动方向及对话框返回操作问题：改为递增时钟建立稳定任务顺序、按正确方向滚动、从返回事件关闭设置并明确断言消失。最终结果只采用修正后运行；未静默忽略命中警告。

## 平台与设计验收

- [Android 15 实际触摸和系统返回](issue-66-android-validation.md)：API35，80 项任务、2 倍 fixture 字号；实际 ADB tap/swipe/KEYCODE_BACK 验浏览、取消、启动、活动/暂停/预约恢复与原任务完成/删除。准备页溢出修复前后都有截图，复测通过。
- [Windows 11 实际键鼠及窗口缩放](issue-66-windows-validation.md)：普通应用进程、80 项任务、2 倍 fixture 字号；窗口从约1267px实际缩到约405px，鼠标滚轮/点击与 Tab、Enter、Space、Esc 验证筛选、取消、直接启动、返回与恢复，另验删除任务的预约/暂停恢复及窄窗口准备配置。

主代理复核两端关键截图与操作结果。亮色 Android、暗色 Windows，以及 App 的窄屏暗色/大字号均保留证据。设计依据 apple-design 的 `layout.md › Visual hierarchy / Adaptability`、`typography.md › Ensuring legibility`、`buttons.md › Content` 转译为 Flutter Material 3：复用主题、任务选择渐进展开、元数据允许换行、执行与返回职责明确；ui-ux-pro-max Flutter 列表/状态指导用于懒加载及状态保留。ADR0007 已排除辅助技术专项验收。

## Standards

独立审查及必要修复后的增量复核：0 项明确违规，0 项需报告的判断性 smell。二级任务页符合 ADR0004，复用现有主题、提供加载/失败/空状态；App 与真实仓储测试符合已确认边界。下拉框限宽修复与独立离线夹具均在本票验收范围内。

## Spec

独立审查及增量复核：0 项发现。User Stories21–31 与 #66 的主页计数、二级筛选、上下文、取消保留、执行返回和原身份恢复均有实现与证据；未改计时/失败/暂停/交接规则，未把 #67 的工作扩入本票。

两轴合计：Standards 0，Spec 0，无未解决发现。

## 完成记录

最终 Windows 设备测试 1 项通过（26 秒），Android 1 项通过（38 秒），均无首轮弹窗返回命中警告。最终 `flutter analyze` 无问题、全量 `flutter test` 279 项通过。

普通入口 `flutter build windows --debug` 和 `flutter build apk --debug` 均通过（仅传公开客户端配置）；Android 以 `adb install -r` 覆盖安装普通 APK，保留用户数据且不启动真实用户应用。Windows 测试窗口和临时 MCP 连接已关闭，普通 Debug 产物已恢复；临时客户端配置删除。

按用户要求提交到当前 master 并推送 origin/master，清理 #66 标签与阻塞关系，保留与 #63 的父子关系。实施前后 blocked_by / blocking 均为空，无须删除其他票据关系；Issue 验收清单与本地票据同步完成状态。
