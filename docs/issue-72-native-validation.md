# Issue #72 原生提醒验收

日期：2026-10-25（Asia/Shanghai）。入口：[issue_72_reminder_device_test.dart](../integration_test/issue_72_reminder_device_test.dart)。本记录仅登记真实 Android 15 / Windows 11 生命周期验收；App 级回归和隔离服务结果见[总验收记录](issue-72-validation.md)及对应服务验收材料。

## 验收边界与隔离

每个平台各用一个新的 8–48 位 run ID。入口在应用支持目录创建唯一 `issue72-<runId>.sqlite` 和 `issue72-<runId>-control.json`，只使用合成用户、本机 SQLite 和文件控制的 `CloudSnapshotRemote`；云快照 `dataUpdatedAt` 固定为 2025-01-01，业务内容检查不联网。SharedPreferences 使用该合成用户的独立 key，`exercise` 只清理这一测试用户的同步结果与忽略标记。脚本不会清理、卸载或重置 Pacta 用户数据；Android 命令带 `--no-uninstall`。

运行时控制仅绑定 loopback `30351`，`X-Issue72-Control` 必须匹配本轮短期随机 fixture token。Android 用 ADB forward 把该端口映射到宿主；Windows 端点只控制 PID 与运行时自身窗口 owner 一致的 Flutter runner。`/control` 可推进注入时钟或修改合成远端 revision；`/lifecycle` 在 Windows 最小化/恢复窗口。Android 后台/前台使用实际 ADB Home/启动命令。新进程阶段比较 PID，并复用原 SQLite、控制 JSON 与平台偏好存储。

## 命令与阶段

为 Android 与 Windows 分配不同 run ID。把同一个 run ID 用于该平台的两个阶段。令牌由受 ACL 保护的 `.dart_tool/issue72-native-control.json` 提供给 Flutter 和宿主驱动，不显示在命令行或日志中。

Windows 11：

```bat
cmd.exe /c flutter test integration_test/issue_72_reminder_device_test.dart -d windows --dart-define=ISSUE72_PHASE=exercise --dart-define=ISSUE72_RUN_ID=win20261025b --dart-define-from-file=.dart_tool/issue72-native-control.json
python .scratch/issue72/native_driver.py --platform windows --phase exercise
cmd.exe /c flutter test integration_test/issue_72_reminder_device_test.dart -d windows --dart-define=ISSUE72_PHASE=restart-verify --dart-define=ISSUE72_RUN_ID=win20261025b --dart-define-from-file=.dart_tool/issue72-native-control.json
python .scratch/issue72/native_driver.py --platform windows --phase restart-verify
```

Android 15 / API 35（既有 `PactaT24Secondary`，serial `emulator-5556`）：

```bat
cmd.exe /c flutter test integration_test/issue_72_reminder_device_test.dart -d emulator-5556 --no-uninstall --dart-define=ISSUE72_PHASE=exercise --dart-define=ISSUE72_RUN_ID=android20261025a --dart-define-from-file=.dart_tool/issue72-native-control.json
python .scratch/issue72/native_driver.py --platform android --phase exercise --serial emulator-5556
cmd.exe /c flutter test integration_test/issue_72_reminder_device_test.dart -d emulator-5556 --no-uninstall --dart-define=ISSUE72_PHASE=restart-verify --dart-define=ISSUE72_RUN_ID=android20261025a --dart-define-from-file=.dart_tool/issue72-native-control.json
python .scratch/issue72/native_driver.py --platform android --phase restart-verify --serial emulator-5556
```

`exercise` 启动后等真实首次云端选择弹层（合成云版本数据时间约为一年以前），关闭后报告 `ISSUE72_EXERCISE_READY` 并等待一次真实前后台循环。Android 宿主先建立转发，再推进五分钟测试时钟并执行 Home/恢复；Windows 宿主推进同一时钟，然后按顺序 POST `/lifecycle` 的 `minimize` 与 `restore`。检查同版再次弹出后选择忽略，再打开手动预览确认入口仍在；阶段自然退出。

`native_driver.py` 轮询真实 runner 的 `/status`。exercise 阶段只在 runner ready 后推进时钟、执行一次真实系统后台/前台；restart-verify 阶段按 control JSON 中实际 revision 2、3、4、5 逐阶段等待，且每次确认 `resumeCount` 和云检查数推进后才开始下一周期。它不会连续重复发送按键，也不需要明文令牌参数。driver 成功后仍需等待对应 Flutter 命令自然结束；未出现 `ISSUE72_NATIVE_PASS` 的阶段不记通过。

Android 的 `exercise` 结束后以 `adb shell am force-stop com.pacta.pacta` 结束 App 进程，不清数据、不卸载，然后运行 `restart-verify`。Windows 等 `exercise` 命令退出后运行同一 run ID 的 `restart-verify`。日志必须显示 `priorPid` 与新 `pid` 不同。此阶段先断言同版本在冷启动检查后保持安静，再改成 revision 2，并进行真实前后台循环确认新版本重新提醒。其后在真实本地仓储中建立预约、活动专注和暂停专注：流程内分别将远端推进到 revision 3、4、5，并实测前后台检查；均应只显示非阻断提示。结束预约与暂停专注后应分别选择最新版本；最终弹层明确显示 revision 5 的设备来源，确认没有弹出已过期的 revision 4。

截图由测试从真实 runner 的 `RepaintBoundary` 写入应用支持目录，runner 日志包含 `ISSUE72_SCREENSHOT stage=… path=…`。完成后将首次旧快照、关闭后再次提醒、忽略后手动预览、重启静默/新版提醒、预约期间非阻断和 revision 5 结束提醒的截图复制到 `docs/evidence/issue-72/`，并在结果表中链接；不要用 widget 测试截图代替原生证据。

## 实际结果

Windows 11 两阶段均 **1 passed**。正式 run ID `win20261025b`，`exercise` PID **37632**、`restart-verify` PID **35928**，新进程复用同一独立 SQLite 和用户偏好。首阶段最终检查次数 4，忽略版本 1；新进程冷检查次数到 5，同版保持静默；真实最小化／恢复后，新版、预约、专注及暂停检查完成，最终 revision **5**、检查次数 **12**、业务传输 **0**。宿主 driver 每轮观察 `hidden → inactive → resumed`，并使用测试入口的窗口 owner PID guard。

Windows 以 `PointerDeviceKind.mouse` 注入点击；Android 以 `touch` 注入。Windows exercise 在原始宽窗口截图后，仅对 PID 匹配的测试窗口调用 Win32 `SetWindowPos` 调整外框到 640×720，再进行关闭后前台恢复及手动预览。截图证据：[首次旧快照](evidence/issue-72/windows-first-reminder-old-cloud.png)、[窄窗口关闭后重提醒](evidence/issue-72/windows-closed-then-foreground-reminder.png)、[忽略后手动预览](evidence/issue-72/windows-manual-preview-after-ignore.png)、[新进程新版提醒](evidence/issue-72/windows-new-version-after-restart.png)、[预约非阻断](evidence/issue-72/windows-appointment-nonblocking.png)、[预约结束](evidence/issue-72/windows-appointment-ended-latest-reminder.png)、[暂停非阻断](evidence/issue-72/windows-paused-nonblocking-latest-revision.png)、[专注结束仅最新版本](evidence/issue-72/windows-focus-ended-latest-reminder.png)。

Windows 首次 `win20261025a` 两阶段均不计通过：exercise 在上传确认取消后多点了一次不存在的取消；restart 把“结束后版本5来源”断言放在暂停期间，和“不弹层”断言矛盾。主代理修复夹具后，以新 run ID 完整重跑上述两阶段通过，未调整产品规则或清除旧库。初次 WSL Python 不能访问 Windows loopback，改用 Windows Python 运行同一宿主 driver，未改产品或服务绑定。

Android 15/API35 两阶段均 **1 passed**，serial `emulator-5556`，run ID `android20261025a`。exercise PID **3819** 在关闭首见选择后经真实 ADB Home/monkey 恢复同版重提醒，忽略后仍可进入手动预览及上传/下载二次确认并取消，业务指纹保持不变，最终检查次数 4、传输 0。随后主代理执行 `adb -s emulator-5556 shell am force-stop com.pacta.pacta`，未清数据或卸载；restart-verify PID **4160** 打开原库，启动检查次数到 5，同版静默；四轮原生前后台后完成新版、预约、专注和暂停检查，结束仅显示 revision **5**，最终检查次数 **12**、传输 **0**。本次两阶段没有 VM 连接失败。原有 Gradle/KGP 未来兼容及 SDK XML 警告保留，但构建与断言均通过。

Android 原生场景保留设备自动旋转和暗色设置：首次截图为横屏，原生前后台后的结束提醒截图为竖屏；鼠标／触摸通过 Flutter 集成 tester 在真实平台注入，原生前后台由 ADB/Win32 驱动。截图：[首见](evidence/issue-72/android-first-reminder-old-cloud.png)、[关闭后重提醒](evidence/issue-72/android-closed-then-foreground-reminder.png)、[忽略后手动查看](evidence/issue-72/android-manual-preview-after-ignore.png)、[重启后新版](evidence/issue-72/android-new-version-after-restart.png)、[预约非阻断](evidence/issue-72/android-appointment-nonblocking.png)、[预约结束](evidence/issue-72/android-appointment-ended-latest-reminder.png)、[暂停非阻断](evidence/issue-72/android-paused-nonblocking-latest-revision.png)、[专注结束最新版本](evidence/issue-72/android-focus-ended-latest-reminder.png)。四个通过阶段的 PID、版本、传输数和真实生命周期摘要见 [native-results.json](evidence/issue-72/native-results.json)。Android 竖屏浅色和真实系统返回另在隔离服务验收中取证。
