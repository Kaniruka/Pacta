import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/device_permission_gateway.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/focus_notification_settings_page.dart';
import 'package:pacta/src/ui/pacta_grouped_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('三个分组覆盖后台权限、专注通知与定时提醒', (tester) async {
    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsChannel: const MethodChannel('sections_test/notifications'),
    );
    addTearDown(service.dispose);
    final permissions = _RecordingPermissionGateway();
    final battery = _RecordingBatteryGateway();

    await _pumpPage(
      tester,
      FocusNotificationSettingsPage(
        service: service,
        isAndroid: true,
        permissionGateway: permissions,
        batteryOptimizationGateway: battery,
        calendarSourcesBuilder: (_) => Scaffold(
          appBar: AppBar(title: const Text('日历来源占位页')),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    // 分组标题就是合并后页面的大纲：三个蓝色标题，各带一块分组列表。
    for (final section in ['后台运行与系统权限', '后台倒计时与专注通知', '定时提醒']) {
      expect(find.text(section), findsOneWidget, reason: section);
    }
    expect(find.byType(PactaSectionHeader), findsNWidgets(3));
    expect(find.byType(PactaGroupedList), findsNWidgets(3));

    // 第一组：通知、精确闹钟、后台运行白名单与系统日历只读导入。
    for (final row in ['系统通知权限', '精确提醒（闹钟）', '后台运行', '系统日历只读导入']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.byKey(const Key('open-notification-settings')), findsOneWidget);
    expect(
      find.byKey(const Key('open-battery-optimization-settings')),
      findsOneWidget,
    );

    // 权限状态是行尾胶囊，入口是整行点击：副标题里不再内嵌任何按钮。
    expect(find.text('已开启'), findsOneWidget);
    expect(find.text('已允许'), findsOneWidget);
    expect(find.text('建议开启'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(TextButton),
      ),
      findsNothing,
      reason: '整行可点后，ListTile.subtitle 不得再放跳转按钮',
    );
    final dividers = tester.widgetList<Divider>(find.byType(Divider));
    expect(dividers, isNotEmpty, reason: '同组相邻行之间仍有 1dp 细分隔线');
    for (final divider in dividers) {
      expect(divider.indent, isNull, reason: '不再用缩进分割线把卡片割裂成碎片');
      expect(divider.endIndent, isNull);
      expect(divider.thickness, 1);
    }

    // 第二组：后台倒计时与专注流程通知。
    expect(find.text('显示后台倒计时'), findsOneWidget);
    expect(find.text('专注流程通知'), findsOneWidget);

    // 第三组：国策待确认提醒与每天打开 Pacta 及各自时间。
    expect(find.text('国策待确认提醒'), findsOneWidget);
    expect(
      find.byKey(const Key('national-focus-reminder-time')),
      findsOneWidget,
    );
    expect(find.text('每天打开 Pacta'), findsOneWidget);
    expect(find.byKey(const Key('daily-open-reminder-time')), findsOneWidget);

    // 分组之间必须留出至少 8dp，避免两块白卡粘连。
    final groups = find.byType(PactaGroupedList);
    final rects = [
      for (var index = 0; index < groups.evaluate().length; index++)
        tester.getRect(groups.at(index)),
    ];
    for (var index = 1; index < rects.length; index++) {
      expect(
        rects[index].top - rects[index - 1].bottom,
        greaterThanOrEqualTo(8 - 0.01),
        reason: '第 $index 与第 ${index + 1} 组分房间距',
      );
    }

    // 系统日历入口把用户送到既有来源勾选页。
    await tester.ensureVisible(find.byKey(const Key('open-calendar-sources')));
    await tester.tap(find.byKey(const Key('open-calendar-sources')));
    await tester.pumpAndSettle();
    expect(find.text('日历来源占位页'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 电池优化入口会重新读取状态：用户放行后页面立刻反映新值。
    await tester.ensureVisible(
      find.byKey(const Key('open-battery-optimization-settings')),
    );
    await tester.tap(
      find.byKey(const Key('open-battery-optimization-settings')),
    );
    await tester.pumpAndSettle();
    expect(battery.opens, 1);
    expect(find.textContaining('已加入电池优化白名单'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('注入 isAndroid 时开关走 Android 权限申请分支', (tester) async {
    final service = _StubNotificationService(
      const FocusDevicePreferences(
        notificationsEnabled: false,
        backgroundRunningEnabled: false,
        dailyOpenReminderMinutesAfterMidnight: 9 * 60,
        dailyOpenReminderTimeChosen: true,
      ),
    );
    await _pumpPage(
      tester,
      FocusNotificationSettingsPage(
        service: service,
        isAndroid: true,
        permissionGateway: _RecordingPermissionGateway(),
        batteryOptimizationGateway: _RecordingBatteryGateway(),
      ),
    );

    // 专注流程通知：桌面宿主也按注入的 Android 平台走申请分支。
    await tester.ensureVisible(find.text('专注流程通知'));
    await tester.tap(find.text('专注流程通知'));
    await tester.pumpAndSettle();
    expect(service.permissionRequests, 1);
    expect(
      service.preferences.notificationPermissionRequested,
      isTrue,
      reason: '只有 Android 分支才记录已请求系统通知权限',
    );
    expect(find.textContaining('未授予通知权限'), findsWidgets);

    // 每日打开提醒：首次开启同样先申请通知权限。
    await tester.ensureVisible(find.text('每天打开 Pacta'));
    await tester.tap(find.text('每天打开 Pacta'));
    await tester.pumpAndSettle();
    expect(service.permissionRequests, 2);
    expect(find.textContaining('系统未授予通知权限'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面端在权限组内说明无需电池优化白名单', (tester) async {
    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsChannel: const MethodChannel('sections_test/desktop'),
    );
    addTearDown(service.dispose);

    await _pumpPage(
      tester,
      FocusNotificationSettingsPage(
        service: service,
        isAndroid: false,
        permissionGateway: _RecordingPermissionGateway(),
        batteryOptimizationGateway: _RecordingBatteryGateway(),
      ),
    );

    expect(find.text('后台运行与系统权限'), findsOneWidget);
    expect(find.text('桌面端保活运行，无需电池优化'), findsOneWidget);
    expect(find.text('精确提醒（闹钟）'), findsNothing, reason: 'Android 专属能力');
    expect(
      find.byKey(const Key('open-battery-optimization-settings')),
      findsNothing,
    );
    // 没有注入来源页构建器时入口保留但整行禁用，不会假装已接入。
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('open-calendar-sources')))
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  test('电池优化网关透传方法名，读取失败按未放行处理', () async {
    const channel = MethodChannel('sections_test/device_permissions');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'isIgnoringBatteryOptimizations') return true;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    const gateway = MethodChannelDevicePermissionGateway(channel: channel);
    expect(await gateway.isIgnoringBatteryOptimizations(), isTrue);
    await gateway.openBatteryOptimizationSettings();
    expect(calls, [
      'isIgnoringBatteryOptimizations',
      'openBatteryOptimizationSettings',
    ]);

    // 宿主没有实现该能力时不得抛出，也不能谎称已经放行。
    const missing = MethodChannel('sections_test/missing_permissions');
    const missingGateway = MethodChannelDevicePermissionGateway(
      channel: missing,
    );
    expect(await missingGateway.isIgnoringBatteryOptimizations(), isFalse);
  });

  test('非 Android 平台的默认网关声明无需放行', () async {
    const gateway = UnsupportedDevicePermissionGateway();
    expect(await gateway.isIgnoringBatteryOptimizations(), isTrue);
    await gateway.openBatteryOptimizationSettings();
    expect(Platform.isAndroid, isFalse, reason: '测试运行在桌面宿主');
  });
}

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// 只记录权限申请次数：让注入 isAndroid 的分支在桌面宿主上真实执行。
class _StubNotificationService extends FocusNotificationService {
  _StubNotificationService(this.preferences)
    : super(windowsChannel: const MethodChannel('sections_test/stub'));

  FocusDevicePreferences preferences;
  int permissionRequests = 0;

  @override
  Future<FocusDevicePreferences> getPreferences() async => preferences;

  @override
  Future<void> updatePreferences(FocusDevicePreferences value) async {
    preferences = value;
  }

  @override
  Future<bool> notificationsAllowed() async => false;

  @override
  Future<bool> exactAlarmsAllowed() async => true;

  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequests++;
    return false;
  }

  @override
  Future<bool> requestExactAlarmPermission() async => false;

  @override
  Future<void> dispose() async {}
}

class _RecordingPermissionGateway implements DevicePermissionGateway {
  int settingsOpened = 0;
  int appSettingsOpened = 0;

  @override
  Future<void> openNotificationSettings() async {
    settingsOpened++;
  }

  @override
  Future<void> openAppSettings() async {
    appSettingsOpened++;
  }
}

class _RecordingBatteryGateway implements BatteryOptimizationGateway {
  bool ignoring = false;
  int opens = 0;

  @override
  Future<bool> isIgnoringBatteryOptimizations() async => ignoring;

  @override
  Future<void> openBatteryOptimizationSettings() async {
    opens++;
    // 模拟用户在系统白名单里放行后返回应用。
    ignoring = true;
  }
}
