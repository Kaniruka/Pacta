# Issue 95 实施记录：集中提醒与动态权限

状态：代码、单元/组件测试完成；Android 与 Windows 的真实通知到达、点击与退出行为待主 agent 在共享设备执行 fixture 取证（见「平台验收」）。
票据：`docs/tickets-sync-profile-cards-20261113/05.md`；规格：`docs/spec-sync-profile-cards-20261113.md`。
分支：`impl/pacta95-reminders`（基线 `c76a59f`，`feat/sync-profile-cards-20261113`）。

## 实际改动

| 位置 | 内容 |
| --- | --- |
| `lib/src/notifications/daily_open_reminder_plan.dart` | 新增：按设备本地墙钟求下一次提醒；已过时刻只排下一次，绝不回放过去日期 |
| `lib/src/notifications/daily_open_reminder_state.dart` | 新增：本机持久化已计划日、时刻与时区标识、最近送达日 |
| `lib/src/notifications/device_permission_gateway.dart` | 新增：打开系统通知设置/应用设置；非 Android 为空实现 |
| `lib/src/notifications/device_settings_scope.dart` | 新增：设备设置按登录用户分键（`pacta.device.u.<userId>.<name>`）与一次性迁移；旧全局键只被升级后第一个登录用户继承，随后删除，其他用户从默认值开始 |
| `lib/src/notifications/focus_device_preferences.dart` | 新增每日提醒开关（默认关）、时间（默认 09:00，越界回落）、是否已选时间、是否已请求通知权限；按 `userId` 分键，全部留在本机 |
| `lib/src/notifications/focus_notification_service.dart` | 新增每日提醒标识 2205/通道 `pacta_daily_open_reminders`/payload `daily-open-reminder:<dayKey>`；Android 用 `zonedSchedule`+`DateTimeComponents.time` 每日重复，Windows 用进程内 Timer；reconcile 幂等，改时间/关闭/重启/换时区都收敛到一个待发提醒；与专注、国策提醒的标识互不覆盖 |
| `lib/src/notifications/focus_notification_settings_page.dart` | 页面改为「提醒与通知」：专注流程通知、国策待确认提醒、新增「每天打开 Pacta」；首次开启必须选时间；已拒绝状态常驻「去系统设置开启通知」；精确闹钟单独提示 |
| `lib/main.dart` | `daily-open-reminder:` payload 打开看板；启动与恢复时 reconcile 每日提醒；App 启动即按当前用户绑定提醒归属，退出/切换只释放本人调度；「我的」入口改为「提醒与通知」；开始专注/预约与国策确认时按需申请通知权限 |
| `lib/src/calendar/calendar_page.dart` | 日历权限被拒时提供「去系统设置开启日历权限」 |
| `android/.../MainActivity.kt` | 新增 `com.pacta/device_permissions` 通道：`openNotificationSettings`、`openAppSettings` |
| `windows/runner/flutter_window.cpp/.h` | 托盘气泡记录 payload；`NIN_BALLOONUSERCLICK` 复原窗口并经 `com.pacta/focus_status` 回调 `notificationClicked` |
| `test/notifications/*`, `integration_test/issue_95_daily_reminder_device_test.dart` | 计划、状态、服务、设置页、AppShell 路由测试与可重跑原生 fixture |

## 关键决定与核实

1. **Windows 退出后提醒**：读 `flutter_local_notifications_windows` 3.1.1 源码确认 `AddToSchedule`（WinRT 计划通知）存在，但 `plugin.cpp` 只在 HKCU 注册 AUMID 与 `CustomActivator`，未注册 `LocalServer32`；未打包应用退出后被点击无法唤起应用。本票因此沿用仓库既有托盘气泡 + 进程内 Timer，界面明示「仅在 Pacta 正在运行（含隐藏到托盘）时送达；完全退出后不会提醒」，不声称退出后可提醒。
2. **本机当地时间**：计划用本地 `DateTime` 墙钟；Android 用 `FlutterTimezone` 的 IANA 标识定位 `zonedSchedule` 并检测时区变化，未收录标识（如 Android 15 模拟器的 `GMT`）回退 `timezone.local`，最后才 `Etc/UTC`。旧基线截图中的「无法读取设备时区，回退 UTC」来自 `_FocusTimeZoneSettingsCard` 的 `FocusTimeZones` 白名单校验（`GMT` 不在白名单），属统计/展示时区模块，本票不改。
3. **权限**：通知权限与精确闹钟授权分别处理；重复拒绝后系统不再弹窗，因此被拒状态常驻系统设置入口。拒绝不阻断看板、专注、国策与日历缓冲展示。
4. **幂等与不补发**：设置变化、重启、跨日、时区变化都重算计划；已过时刻只排下一次，故关闭多日后重开不会补发多天；同一 id 的重复计划互相替换。
5. **本机设置与用户隔离**：设置键为 `pacta.device.u.<userId>.<name>`（未登录/测试沿用旧布局），不进业务快照、不跨设备复制。`FocusNotificationService.setUserId` 在切换/退出时同步失效先前归属（代数计数使在途 reconcile 与送达直接返回）、取消定时器与 Android 待发闹钟，并清掉离开者的瞬态计划标记；其已保存的开关与时间仍按用户键保留，回到该用户后重新计划。升级前的一次性全局键只迁移给首个登录用户并随即删除，后来用户不会继承别人的提醒。
6. **动态权限申请入口**：仅当用户真的使用依赖提醒的能力时才申请，且只申请一次（`notificationPermissionRequested` 持久化后不再重复弹窗，被拒后由设置页的系统设置入口接管）：
   - `lib/main.dart` 的 `_FocusSetupDialogState._startSession` / `_startAppointment`（用户开始专注或预约）；
   - `NationalFocusTreePage._confirmToday` 经 `onNotificationCapabilityUse`（用户确认国策节点）；
   - 设置页开关（用户主动开启提醒）。
   启动、恢复、后台同步都不弹窗；任一入口被拒不阻断对应操作。

## 测试（实际执行，2026-11-13，Windows 11 / Flutter 3.47.2 / Dart 3.13.2）

| 命令 | 结果 |
| --- | --- |
| `dart format lib/main.dart lib/src/notifications lib/src/calendar/calendar_page.dart test/notifications integration_test/issue_95_daily_reminder_device_test.dart` | 23 files formatted（13 变更） |
| `flutter analyze` | No issues found |
| `flutter test` | All tests passed（451，当前分支合并本地最新 integration 后） |
| `git merge feat/sync-profile-cards-20261113` 后 `flutter analyze` | No issues found |
| `flutter test test/calendar test/notifications` | All tests passed（64） |
| `flutter build windows --debug` | √ Built build\windows\x64\runner\Debug\pacta.exe |
| `flutter build apk --debug` | √ Built build\app\outputs\flutter-apk\app-debug.apk |

首轮 Windows 构建暴露了本票 C++ 的编译错误（`StandardMethodCodec::GetInstance()` 返回引用、`MethodCall` 需要 `std::unique_ptr` 参数、`BinaryMessenger::Send` 为三参数），已修正后重建通过。

覆盖的自动化行为：

- 计划：当天未到点、已过点顺延、跨月、跨多日只排下一次、非法分钟报错。
- 服务：按时送达一次并排次日；重复 reconcile 仍只有一个待发；改时间替换；关闭取消并清空；重启复用计划；关闭多日不补发；时区标识变化重排；点击 payload 进入看板；Windows 托盘点击回传 payload。
- 设置页：默认关闭并显示 09:00；首次开启必须选时间（取消保持关闭）；已选时间不再询问；改时间保持开启；关闭后不再有待发定时器。
- 用户隔离：A 开启 → B 读取仍为默认关闭且无待发 → 回到 A 仍保留 A 的时间；退出登录取消 A 的定时器并清空其瞬态计划；切换瞬间在途的 reconcile 不会给旧用户重新排程；升级前的全局键只迁移给首个用户、瞬态标记不迁移。
- AppShell：`daily-open-reminder:` payload 使导航回到看板。
- 日历：权限被拒时系统设置入口可打开（记录调用次数）。

单元与组件测试不替代设备证据。Windows 构建（`flutter build windows --debug`）与 Android 构建（`flutter build apk --debug`）在本轮原生改动后各通过一次；此后仅 Dart/文档改动，未再构建。

## 平台验收（fixture 已备，待设备执行）

```bash
flutter test integration_test/issue_95_daily_reminder_device_test.dart -d windows
flutter test integration_test/issue_95_daily_reminder_device_test.dart -d <android-device>
```

如需留出真实到达/点击的观察窗口（分钟数由运行者决定）：

```bash
flutter test integration_test/issue_95_daily_reminder_device_test.dart \
  -d <android-device> --dart-define=ISSUE95_HOLD_SECONDS=240
```

fixture 打印 `ISSUE95_DEVICE_ZONE`（设备 IANA 时区）、`ISSUE95_PERMISSIONS`、`ISSUE95_PLAN`、`ISSUE95_ANDROID_PENDING`、`ISSUE95_SETTINGS_OPENED`、`ISSUE95_HOLD_STARTED/ENDED`、`ISSUE95_ROUTE_INJECTED`、`ISSUE95_DISABLED_CLEARED`、`ISSUE95_PREFERENCES_RESTORED`、`ISSUE95_NATIVE_PASS`。

隔离与数据保留：fixture 以独立 fixture 用户登录，提醒键落在该用户作用域；开跑前快照整份 SharedPreferences，结束时取消自己排的提醒、关闭开关、再整份还原并打印 `ISSUE95_PREFERENCES_RESTORED`。它不写业务数据，也不留改过的偏好。

证据边界：`ISSUE95_ROUTE_INJECTED` 是人工注入 payload，只证明「点击后进入看板」的路由；原生到达与真实点击必须由人在 hold 窗口观察，fixture 只补充 `ISSUE95_HOLD_ENDED` 的后台/回前台生命周期事实，不把注入当原生点击证据。

到达与点击的系统侧取证（需人工观察，不能用单元测试替代）：

```bash
# Android：计划中的提醒与通知栏实际出现
"$ADB" shell dumpsys alarm | grep -i -A4 pacta
"$ADB" shell dumpsys notification --noredact | grep -i -A6 pacta
# 点击系统通知后确认进入看板（配合 fixture 的 ISSUE95_TAP_DESTINATION 或人工观察）
```

Windows：运行 `build/windows/x64/runner/Debug/pacta.exe`，在「提醒与通知」开启每日提醒并选择 1 分钟后；到时观察托盘气泡，点击后应回到看板。完全退出进程后不再提醒（界面已明示）。

待确认项：

- Android 真机（含重复拒绝）通知到达、点击跳转、应用在后台与进程被杀后的行为。
- Windows 气泡到达与点击复原窗口。
- 精确闹钟被拒（inexact）场景的到达时延。

## 备注

- 截图 fixture 使用 `PactaApp` 的真实主题与 MiSans；Android 截图须走 `binding.takeScreenshot` + host driver，不能直接写设备相对路径。
- 本票未改动统计/展示时区模块、业务快照与云同步。