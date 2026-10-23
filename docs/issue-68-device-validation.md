# Issue #68 国策树视图偏好设备验收

日期：2026-10-23。设备入口为 `integration_test/issue_68_view_memory_device_test.dart`，基于真实 `PactaApp`、文件 Drift 数据库和 `LocalNationalFocusRepository`；认证由 `FakeAuthRepository` 替代，专注通知禁用，云同步关闭。数据库和身份分别使用 `baseline20261023` 与 `postfix20261023` 专用隔离值，正常用户数据未打开、清除或改写。

## 修复前基线

先在应用内确认首次为简洁，选择详细；待该测试进程结束后，再单独启动新进程检查页面。两阶段使用相同平台文件数据库及身份。测试断言和输出中的 PID 可证明第二次是新的原生应用进程，不是 widget 重建或热重载。

```bash
cmd.exe /c flutter test integration_test/issue_68_view_memory_device_test.dart -d emulator-5554 --no-uninstall --dart-define=ISSUE68_PHASE=seed --dart-define=ISSUE68_RUN_ID=baseline20261023
cmd.exe /c flutter test integration_test/issue_68_view_memory_device_test.dart -d emulator-5554 --no-uninstall --dart-define=ISSUE68_PHASE=baseline-restart --dart-define=ISSUE68_RUN_ID=baseline20261023
cmd.exe /c flutter test integration_test/issue_68_view_memory_device_test.dart -d windows --dart-define=ISSUE68_PHASE=seed --dart-define=ISSUE68_RUN_ID=baseline20261023
cmd.exe /c flutter test integration_test/issue_68_view_memory_device_test.dart -d windows --dart-define=ISSUE68_PHASE=baseline-restart --dart-define=ISSUE68_RUN_ID=baseline20261023
```

| 平台 | seed：首次简洁后选择详细 | 新进程启动后的基线 | 文件数据库 |
| --- | --- | --- | --- |
| Android 15 / API 35，`emulator-5554` | 通过；PID 16475；选择后显示详细 | 通过；PID 16590；显示简洁 | `/data/user/0/com.pacta.pacta/files/issue68-native-baseline20261023.sqlite` |
| Windows 11，版本 `10.0.22631.2506` | 通过；PID 29020；选择后显示详细 | 通过；PID 21652；显示简洁 | `C:\Users\Stray\AppData\Roaming\com.pacta\pacta\issue68-native-baseline20261023.sqlite` |

两端四个阶段均为 `All tests passed!`。Android 每次测试命令退出后，原生进程已结束；两次输出 PID 不同。完成第二阶段后另外执行 `adb shell am force-stop com.pacta.pacta`，随后 `adb shell pidof com.pacta.pacta` 无 PID 输出（退出码 1）。Windows 在 seed 命令返回后、重启命令前，`Get-Process -Name pacta` 无 PID；重启阶段另报告 PID 21652。命令由 WSL 中的 `cmd.exe /c` 启动 Windows Flutter；Android 使用 `--no-uninstall`，没有清数据或卸载。

旧页面仅在 widget 状态中保存 `_detailed`。同平台相同本机数据库和用户在进程结束后重新启动，视图都回到简洁，复现了 Issue #68 的修复前现象。测试输出来自真实原生应用中的自动鼠标／触摸驱动，不代表人工触屏操作。隔离数据库及截图路径：

- Android：`/data/user/0/com.pacta.pacta/files/issue68-seed.png`、`issue68-baseline-restart.png`。
- Windows：`C:\Users\Stray\AppData\Roaming\com.pacta\pacta\issue68-seed.png`、`issue68-baseline-restart.png`。

## 修复后跨进程验收

修复后使用新身份 `issue68-native-postfix20261023`，避免继承修复前状态。seed 只删除这个验收专用的 SQLite 文件，创建并放置一张 `I68 preserved card`，确认首次简洁后选详细；两个后续 phase 使用同一身份和文件，在新进程检查偏好及卡片仍在。`restored-detailed` 先断言恢复详细，再切回简洁并等待保存；`restored-simple` 是第三个进程，断言简洁恢复。三阶段分别启动 Flutter 测试命令，PID 均不同。

```bash
cmd.exe /c flutter test integration_test/issue_68_view_memory_device_test.dart -d emulator-5554 --no-uninstall --dart-define=ISSUE68_PHASE=seed --dart-define=ISSUE68_RUN_ID=postfix20261023
cmd.exe /c flutter test integration_test/issue_68_view_memory_device_test.dart -d emulator-5554 --no-uninstall --dart-define=ISSUE68_PHASE=restored-detailed --dart-define=ISSUE68_RUN_ID=postfix20261023
cmd.exe /c flutter test integration_test/issue_68_view_memory_device_test.dart -d emulator-5554 --no-uninstall --dart-define=ISSUE68_PHASE=restored-simple --dart-define=ISSUE68_RUN_ID=postfix20261023
cmd.exe /c flutter test integration_test/issue_68_view_memory_device_test.dart -d windows --dart-define=ISSUE68_PHASE=seed --dart-define=ISSUE68_RUN_ID=postfix20261023
cmd.exe /c flutter test integration_test/issue_68_view_memory_device_test.dart -d windows --dart-define=ISSUE68_PHASE=restored-detailed --dart-define=ISSUE68_RUN_ID=postfix20261023
cmd.exe /c flutter test integration_test/issue_68_view_memory_device_test.dart -d windows --dart-define=ISSUE68_PHASE=restored-simple --dart-define=ISSUE68_RUN_ID=postfix20261023
```

| 平台 | seed：首次简洁→详细 | 第二进程：恢复详细→改简洁 | 第三进程：恢复简洁 | 相同文件数据库 |
| --- | --- | --- | --- | --- |
| Android 15 / API 35，`emulator-5554` | 通过；PID 16759 | 通过；PID 16881 | 通过；PID 17030 | `/data/user/0/com.pacta.pacta/files/issue68-native-postfix20261023.sqlite` |
| Windows 11，版本 `10.0.22631.2506` | 通过；PID 26860 | 通过；PID 26824 | 通过；PID 33336 | `C:\Users\Stray\AppData\Roaming\com.pacta\pacta\issue68-native-postfix20261023.sqlite` |

六个 phase 均报告 `All tests passed!`，且每阶段都读取并断言唯一的 `I68 preserved card` 存在。Android seed 和 `restored-detailed` 命令返回后、下一阶段启动前，`pidof com.pacta.pacta` 均无 PID；各阶段间均执行 `am force-stop` 并再次确认无 PID。`restored-simple` 后执行相同 force-stop 和无 PID 检查。Windows 每阶段命令返回后运行 `Get-Process -Name pacta` 均无旧 PID。`--no-uninstall` 保留 Android 应用数据；全程不清除应用数据或擦除模拟器。

设备截图由测试在屏幕正常尺寸下保存。Android seed 图显示详细选择和行动摘要，`restored-simple` 图显示简洁选择且没有摘要。`restored-detailed` phase 的截图是在断言恢复详细后、切回简洁后拍摄，因此它也显示简洁；恢复详细的证据是该阶段在截图前通过的断言和新 PID。Windows 截图遵循相同顺序，且当前 Windows 桌面主题为暗色。Android 原始截图保存在 `/data/user/0/com.pacta.pacta/files/issue68-{seed,restored-detailed,restored-simple}.png`；Windows 在 `C:\Users\Stray\AppData\Roaming\com.pacta\pacta\issue68-{seed,restored-detailed,restored-simple}.png`。供本机会话目视复核的副本位于 `/tmp/issue68/` 与 `/mnt/c/Users/Stray/AppData/Roaming/com.pacta/pacta/`。

## 普通应用产物恢复

设备测试后从 gitignored `.env` 仅筛选 `SUPABASE_URL` 和 `SUPABASE_PUBLISHABLE_KEY` 到临时 `build/issue68-public.env`，没有传递 `TEST_*` 或服务端密钥；临时文件已删除。普通 `flutter build apk --debug`、`flutter build windows --debug` 均成功，Android `adb install -r` 返回 `Success`。安装后验收 SQLite 仍存在，`pidof com.pacta.pacta` 无输出；未启动应用或真实账号。普通 APK 覆盖了 integration test 产生的 APK 产物。Android 构建报告 `flutter_timezone` 使用 Kotlin Gradle Plugin 的未来兼容性警告，未影响构建和测试。

## 复核与日志边界

主代理已目视复核两端六张画面，并独立查询 Android 系统版本为15、两端专用SQLite均为188416字节，普通构建后的文件仍在。`/tmp/issue68/device-command-output.log` 和 `process-exit-checks.log` 是代理按工具返回的关键输出整理的转录，不是完整stdout原始日志；完整执行结果保留在会话工具记录中。页面故障重试、用户切换与快照隔离由页面级回归覆盖，未将设备脚本扩充为真实云服务或人工输入验收。再次运行seed请更换新的ISSUE68_RUN_ID，避免复用上轮本机偏好；三个修复后阶段必须使用相同RUN_ID。
