# Issue #67 原生模式记忆验收

日期：2026-10-23。边界为真实 `PactaApp` / AppShell＋真实本地仓储＋文件 Drift，替换认证、云端和通知。测试入口为 `integration_test/issue_67_mode_memory_device_test.dart`；正常字号，未扩展 ADR0007/0008 已排除的辅助技术、大字号或键盘专项。

## 平台与执行

- Android 模拟器 `emulator-5554`：实际 `getprop ro.build.version.release` 为 15，SDK 为 35。
- Windows 11：Flutter 实查 `Microsoft Windows [版本 10.0.22631.2506]`。
- 所有 Flutter / Dart 命令由 WSL 调用 Windows `cmd.exe /c`。以下每个平台的三个命令分别构建并启动独立进程；没有热重载、清除应用数据或卸载。

```bash
cmd.exe /c flutter test integration_test/issue_67_mode_memory_device_test.dart -d emulator-5554 --no-uninstall --dart-define=ISSUE67_PHASE=seed
cmd.exe /c flutter test integration_test/issue_67_mode_memory_device_test.dart -d emulator-5554 --no-uninstall --dart-define=ISSUE67_PHASE=direct-restart
cmd.exe /c flutter test integration_test/issue_67_mode_memory_device_test.dart -d emulator-5554 --no-uninstall --dart-define=ISSUE67_PHASE=appointment-restart
cmd.exe /c flutter test integration_test/issue_67_mode_memory_device_test.dart -d windows --dart-define=ISSUE67_PHASE=seed
cmd.exe /c flutter test integration_test/issue_67_mode_memory_device_test.dart -d windows --dart-define=ISSUE67_PHASE=direct-restart
cmd.exe /c flutter test integration_test/issue_67_mode_memory_device_test.dart -d windows --dart-define=ISSUE67_PHASE=appointment-restart
```

| 平台 | seed | direct-restart | appointment-restart |
| --- | --- | --- | --- |
| Android15 | 1 passed；PID15857；12秒 | 1 passed；PID15993；9秒 | 1 passed；PID16089；10秒 |
| Windows11 | 1 passed；PID30340；8秒 | 1 passed；PID10148；6秒 | 1 passed；PID11168；6秒 |

时间为测试执行时间，不含构建。`dart format` 完成；`flutter analyze integration_test/issue_67_mode_memory_device_test.dart` 报告 No issues found。

## 行为与保留数据证据

1. 首次普通；切换精锐后取消保持普通。精锐筛选预选精锐，用户能切为普通再切回精锐。直接启动精锐成功，持久模式为精锐；同数据库另一个用户首次仍为普通。
2. 首个进程退出后，新进程读取同文件的精锐及原活动会话；专注入口恢复原会话 ID，恢复不更新记忆。结束隔离会话后，全部筛选设置仍为精锐；改成普通成功预约，记忆变为普通。
3. 第三个进程读取同文件的普通及原预约，恢复原预约 ID。取消预约后记忆仍为普通；精锐筛选设置下以 SQLite UPDATE 触发器真实拒绝 `focus_preferences` 写入，两条启动操作均显示错误，数据库无新会话/预约，记忆仍为普通，证明事务回滚。

Android 使用 `/data/user/0/com.pacta.pacta/files/issue67-native.sqlite`；Windows 使用 `C:\Users\Stray\AppData\Roaming\com.pacta\pacta\issue67-native.sqlite`。这两个专用文件和测试用户与正常数据库隔离；仅 seed 重置该专用文件。三个 phase 保留该文件，并由不同 PID 读取，属于实际进程退出后重开证据。未连接 Supabase，未读写真实账号业务数据。

## 可复核画面与限制

自动截图来自实际原生 Flutter 画面（正常字号），设置精锐预选、预约恢复和 SQL 错误态：

- Android：`/tmp/pacta-issue67-screenshots/android-setup.png`、`android-restored-appointment.png`、`android-error.png`。
- Windows：`/mnt/c/Users/Stray/AppData/Roaming/com.pacta/pacta/issue67-setup-精锐.png`、`issue67-restored-appointment.png`、`issue67-error.png`。

操作由 Flutter 设备集成测试通过原生应用命中测试驱动，并非人工触摸/鼠标操作证据。设备测试覆盖专注链入口，其余入口的默认模式一致性由 App 级回归补充；不把设备测试扩充为全部入口的人工验收。失败为本地真实 SQLite 事务写入拒绝，不声称磁盘硬件故障或真实云服务验证。

Android 构建报告已有 `flutter_timezone` Kotlin Gradle Plugin 未来兼容性警告；首次构建还报告 SDK XML 工具版本警告，未影响测试通过。Windows 首轮 direct-restart 出现 Flutter finder 建议输出；最终三 phase 结果均无命中警告。

主代理已目视复核上述六张画面：模式预选、预约原任务恢复和错误反馈均可见，无溢出。完成后使用仅包含公开 URL/publishable key 的 gitignored 临时配置分别执行 `flutter build apk --debug` 和 `flutter build windows --debug`，均通过；`adb install -r` 返回 Success，保留用户数据且未启动真实账号应用。临时公开配置已删除。
