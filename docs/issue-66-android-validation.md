# Issue #66 Android 15 真实触摸验收

日期：2026-10-23。设备：Android 15 / API 35 模拟器 `emulator-5554`（`sdk gphone64 x86 64`）。ADB 读数为 `1080x2340`、density `420`（约 `411x891 dp`）。验收使用 fixture 的 `ISSUE66_TEXT_SCALE=200` 应用内字号，没有改动系统显示设置。

fixture 是 [tool/issue_66_focus_navigation_demo.dart](../tool/issue_66_focus_navigation_demo.dart)：每次启动建立独立 SQLite 临时目录，使用本地仓储和假身份，云同步关闭。运行日志给出的数据库位置均在应用私有 `code_cache/pacta-issue66-demo-*/issue66.sqlite` 下；通过 Flutter `q` 退出时 fixture 关闭仓储并删除临时目录。未卸载应用、清除应用数据或改动设备设置。

## 实际命令

主线程先执行了设备集成测试，日志为 `/tmp/issue66-android.log`：

```bash
cmd.exe /c flutter test integration_test/issue_66_focus_navigation_device_test.dart -d emulator-5554 --no-uninstall
```

结果为 `All tests passed`。运行时出现一次 `WidgetTester.pageBack` 的 hit-test warning：它点到了被对话框遮挡的 AppBar 返回控件。该测试随后改为返回事件并断言设置消失，最终两端重跑通过且没有该警告；此处的首轮合成返回操作不作为系统返回证据；下述验收另用 ADB `KEYCODE_BACK` 实际验证。

普通 fixture 分别以以下命令启动；`ISSUE66_FLOW` 取 `none`、`paused`、`appointment`、`active`，每次退出后再启动下一种状态：

```bash
cmd.exe /c flutter run --no-pub -d emulator-5554 --target=tool/issue_66_focus_navigation_demo.dart --dart-define=ISSUE66_FLOW=none --dart-define=ISSUE66_TEXT_SCALE=200
cmd.exe /c flutter run --no-pub -d emulator-5554 --target=tool/issue_66_focus_navigation_demo.dart --dart-define=ISSUE66_FLOW=paused --dart-define=ISSUE66_TEXT_SCALE=200
cmd.exe /c flutter run --no-pub -d emulator-5554 --target=tool/issue_66_focus_navigation_demo.dart --dart-define=ISSUE66_FLOW=appointment --dart-define=ISSUE66_TEXT_SCALE=200
cmd.exe /c flutter run --no-pub -d emulator-5554 --target=tool/issue_66_focus_navigation_demo.dart --dart-define=ISSUE66_FLOW=active --dart-define=ISSUE66_TEXT_SCALE=200
```

实际触摸使用 `adb -s emulator-5554 shell input tap ...` 和 `input swipe ...`；实际系统返回使用 `adb -s emulator-5554 shell input keyevent 4`。每次操作后通过 `adb -s emulator-5554 exec-out screencap -p` 保存截图到 `docs/evidence/issue66-android-*.png`，并据当前屏幕内容选择下一次触摸坐标。

## 结果

- **通过：主页与任务浏览。** 进入“专注链”主页显示 80 个可选任务计数，没有任务预览条目。实际触摸打开列表后，全部、精锐、普通三个筛选都能切换；列表可上下滚动。200%字号下任务标题、目标、分类、预计时长与专注进度可以阅读，未设置时显示“未设置”。截图：[专注主页](evidence/issue66-android-none-focus-home-200.png)、[任务列表](evidence/issue66-android-none-picker-200.png)、[精锐筛选](evidence/issue66-android-none-filter-elite-200.png)、[普通筛选](evidence/issue66-android-none-filter-regular-200.png)、[滚动后列表](evidence/issue66-android-none-picker-scroll-2-200.png)。
- **通过：取消与系统返回保留筛选和位置。** 在精锐筛选的已滚动列表里触摸任务进入设置页，再触摸“取消”；返回后精锐筛选仍选中，原来的 I66-61 / I66-62 项仍在原位置。再次打开设置页并发送 `KEYCODE_BACK`，同样回到该筛选和位置。截图：[设置页](evidence/issue66-android-none-setup-filtered-200.png)、[取消返回](evidence/issue66-android-none-cancel-filter-restored-200.png)、[系统返回前](evidence/issue66-android-none-setup-for-systemback-200.png)、[系统返回后](evidence/issue66-android-none-system-back-restored-200.png)。
- **通过：直接启动和返回。** 从任务设置触摸“开始倒计时”进入执行页，页面显示选中任务和倒计时。发送 `KEYCODE_BACK` 后回到专注主页，原活动流程显示在主页；再次触摸任务入口恢复同一执行页。截图：[直接执行](evidence/issue66-android-none-direct-execution-200.png)、[返回主页](evidence/issue66-android-none-direct-return-home-200.png)、[恢复执行](evidence/issue66-android-none-active-reentry-200.png)。
- **通过：暂停流程和已删除任务恢复。** `paused` fixture 预置暂停会话并删除原目标。主页仍显示“已有进行中的专注”和“任务（已删除）”；返回专注后显示“本次专注已暂停”。系统返回后主页仍保留该暂停流程，任务入口再次打开同一暂停执行页。截图：[暂停主页](evidence/issue66-android-paused-focus-home-200.png)、[暂停执行](evidence/issue66-android-paused-execution-200.png)、[返回主页](evidence/issue66-android-paused-return-home-200.png)、[恢复执行](evidence/issue66-android-paused-reentry-200.png)。
- **通过：预约流程和已删除任务恢复。** `appointment` fixture 预置预约并删除原目标。主页显示预约准备和“任务（已删除）”；触摸“返回准备”进入预约倒计时页，发送 `KEYCODE_BACK` 回主页后预约仍在。触摸“提前进入专注”进入该预约关联的专注，再系统返回主页并重新进入，执行流程仍可恢复。截图：[预约主页](evidence/issue66-android-appointment-focus-home-200.png)、[预约准备](evidence/issue66-android-appointment-preparation-200.png)、[返回主页](evidence/issue66-android-appointment-return-home-200.png)、[提前进入专注](evidence/issue66-android-appointment-early-entry-200.png)、[预约关联流程恢复](evidence/issue66-android-appointment-session-reentry-200.png)。
- **通过：活动会话对应任务已完成时恢复。** `active` fixture 在创建活动会话后将原任务标记完成。主页仍可返回该会话，系统返回后仍显示原活动流程，任务入口再次恢复执行页。截图：[已完成任务的主页恢复](evidence/issue66-android-active-completed-home-200.png)、[执行页](evidence/issue66-android-active-completed-execution-200.png)、[再次进入](evidence/issue66-android-active-completed-reentry-200.png)。
- **已修复并在设备复测通过：200%字号下预约准备页。** 初次验收时“任务”下拉项的长标题溢出 7.9 px，见[修复前截图](evidence/issue66-android-appointment-preparation-200.png)。主线程将该下拉项设为可扩展宽度并对项内标题单行省略后，我用相同 Android 15 模拟器、`ISSUE66_FLOW=appointment` 和 `ISSUE66_TEXT_SCALE=200` 重新构建运行普通 fixture，再通过预约卡片实际触摸进入准备页。复测截图中没有 Flutter overflow 警示；下拉框内长标题以省略号显示，页面标题仍显示完整“Issue 66 原流程任务（已删除）”。见[修复后截图](evidence/issue66-android-appointment-preparation-fixed-200.png)。复测后已退出 fixture，临时 SQLite 目录清理完成。

本次未覆盖横屏、系统级字号调整或辅助技术；Issue #66 本次委派范围为 Android 触摸和系统返回，辅助技术不在本次要求内。
