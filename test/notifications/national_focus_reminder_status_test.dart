import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 常驻倒计时状态通知必须满足 Android 的渲染条件：只有 `showWhen: true`
/// 才会显示 `usesChronometer` 的倒计时；同时它必须与事件提醒开关解耦。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('倒计时状态通知开启 showWhen 与 usesChronometer', () {
    final endAt = DateTime.utc(2026, 9, 26, 14);
    final service = FocusNotificationService(
      now: () => DateTime.utc(2026, 9, 26, 13),
    );
    addTearDown(service.dispose);

    final android = service
        .statusNotificationDetails(endAt: endAt, timeoutAt: endAt)
        .android!;
    expect(android.importance, Importance.defaultImportance);
    expect(android.priority, Priority.defaultPriority);
    expect(android.silent, isTrue);
    expect(android.playSound, isFalse);
    expect(android.enableVibration, isFalse);
    expect(android.ongoing, isTrue);
    expect(android.autoCancel, isFalse);
    expect(android.onlyAlertOnce, isTrue);
    expect(android.showWhen, isTrue);
    expect(android.usesChronometer, isTrue);
    expect(android.chronometerCountDown, isTrue);
    expect(android.when, endAt.millisecondsSinceEpoch);
    expect(android.timeoutAfter, 60 * 60 * 1000);
  });

  test('暂停状态没有结束时刻时不显示计时器', () {
    final service = FocusNotificationService(
      now: () => DateTime.utc(2026, 9, 26, 13),
    );
    addTearDown(service.dispose);

    final android = service.statusNotificationDetails().android!;
    expect(android.showWhen, isFalse);
    expect(android.usesChronometer, isFalse);
    expect(android.chronometerCountDown, isFalse);
    expect(android.when, isNull);
    expect(android.timeoutAfter, isNull);
  });

  test('只开后台运行开关也会为常驻通知申请权限', () async {
    final store = FocusDevicePreferencesStore(
      await SharedPreferences.getInstance(),
    );
    await store.save(
      const FocusDevicePreferences(
        notificationsEnabled: false,
        backgroundRunningEnabled: true,
      ),
    );
    final service = FocusNotificationService(preferencesStore: store);
    addTearDown(service.dispose);

    // Windows 上系统始终允许通知，因此这里验证的是"不再被事件提醒开关挡住"。
    expect(await service.ensureNotificationPermissionForUse(), isTrue);

    await store.save(
      const FocusDevicePreferences(
        notificationsEnabled: false,
        backgroundRunningEnabled: false,
      ),
    );
    expect(await service.ensureNotificationPermissionForUse(), isFalse);
  }, skip: !Platform.isWindows);
}
