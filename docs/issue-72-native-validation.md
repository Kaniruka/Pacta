# Issue #72 原生提醒验收

日期：待实际运行后填写。入口：[issue_72_reminder_device_test.dart](../integration_test/issue_72_reminder_device_test.dart)。本记录仅登记真实 Android 15 / Windows 11 生命周期验收；App 级回归和隔离服务结果见[总验收记录](issue-72-validation.md)及对应服务验收材料。

## 验收边界与隔离

每个平台各用一个新的 8–48 位 run ID。入口在应用支持目录创建唯一 `issue72-<runId>.sqlite` 和 `issue72-<runId>-control.json`，只使用合成用户、本机 SQLite 和文件控制的 `CloudSnapshotRemote`；云快照 `dataUpdatedAt` 固定为 2025-01-01，业务内容检查不联网。SharedPreferences 使用该合成用户的独立 key，`exercise` 只清理这一测试用户的同步结果与忽略标记。脚本不会清理、卸载或重置 Pacta 用户数据；Android 命令带 `--no-uninstall`。

运行时控制仅绑定 loopback `30351`，`X-Issue72-Control` 必须匹配本轮短期随机 fixture token。Android 用 ADB forward 把该端口映射到宿主；Windows 端点只控制 PID 与运行时自身窗口 owner 一致的 Flutter runner。`/control` 可推进注入时钟或修改合成远端 revision；`/lifecycle` 在 Windows 最小化/恢复窗口。Android 后台/前台使用实际 ADB Home/启动命令。新进程阶段比较 PID，并复用原 SQLite、控制 JSON 与平台偏好存储。

## 命令与阶段

为 Android 与 Windows 分配不同 run ID。把同一个 run ID 用于该平台的两个阶段。令牌由受 ACL 保护的 `.dart_tool/issue72-native-control.json` 提供给 Flutter 和宿主驱动，不显示在命令行或日志中。

Windows 11：

```bat
cmd.exe /c flutter test integration_test/issue_72_reminder_device_test.dart -d windows --dart-define=ISSUE72_PHASE=exercise --dart-define=ISSUE72_RUN_ID=win20261025a --dart-define-from-file=.dart_tool/issue72-native-control.json
python .scratch/issue72/native_driver.py --platform windows --phase exercise
cmd.exe /c flutter test integration_test/issue_72_reminder_device_test.dart -d windows --dart-define=ISSUE72_PHASE=restart-verify --dart-define=ISSUE72_RUN_ID=win20261025a --dart-define-from-file=.dart_tool/issue72-native-control.json
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

尚未运行设备验收。待主代理按设备队列执行后记录实际命令、平台版本、runner PID、检查次数、业务传输数、截图路径及失败尝试；工具可用和入口已准备不算验收通过。
