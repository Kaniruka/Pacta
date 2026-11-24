import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/device_permission_gateway.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/focus_notification_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 渠道被降级（弹出/锁屏被系统抑制）时，权限组必须给出直达渠道设置的整行入口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('降级渠道渲染一行直达入口，修好之后整行消失', (tester) async {
    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsChannel: const MethodChannel('channel_health_page/status'),
    );
    addTearDown(service.dispose);
    final health = _RecordingChannelHealthGateway(
      const NotificationChannelHealth(
        healthy: false,
        degradedChannelIds: [
          'pacta_focus_events_v2',
          'pacta_daily_open_reminders_v2',
        ],
      ),
    );

    await _pumpPage(
      tester,
      FocusNotificationSettingsPage(
        service: service,
        isAndroid: true,
        permissionGateway: _RecordingPermissionGateway(),
        batteryOptimizationGateway: _RecordingBatteryGateway(),
        channelHealthGateway: health,
      ),
    );

    expect(
      find.byKey(const Key('open-notification-channel-health')),
      findsOneWidget,
    );
    expect(find.text('弹出与锁屏提醒'), findsOneWidget);
    expect(find.text('需开启'), findsOneWidget);
    expect(find.textContaining('系统可能抑制弹窗或锁屏通知'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('open-notification-channel-health')),
    );
    await tester.tap(find.byKey(const Key('open-notification-channel-health')));
    await tester.pumpAndSettle();

    expect(health.opened, ['pacta_focus_events_v2']);
    expect(
      find.byKey(const Key('open-notification-channel-health')),
      findsNothing,
      reason: '用户在系统里修好之后，这一行不应继续挂着',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('渠道健康时权限组不出现这一行', (tester) async {
    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsChannel: const MethodChannel('channel_health_page/healthy'),
    );
    addTearDown(service.dispose);
    final health = _RecordingChannelHealthGateway(
      const NotificationChannelHealth.healthy(),
    );

    await _pumpPage(
      tester,
      FocusNotificationSettingsPage(
        service: service,
        isAndroid: true,
        permissionGateway: _RecordingPermissionGateway(),
        batteryOptimizationGateway: _RecordingBatteryGateway(),
        channelHealthGateway: health,
      ),
    );

    expect(
      find.byKey(const Key('open-notification-channel-health')),
      findsNothing,
    );
    expect(health.inspections, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有通知权限时不提示渠道降级，先解决权限本身', (tester) async {
    final service = _DeniedPermissionService();
    final health = _RecordingChannelHealthGateway(
      const NotificationChannelHealth(
        healthy: false,
        degradedChannelIds: ['pacta_focus_events_v2'],
      ),
    );

    await _pumpPage(
      tester,
      FocusNotificationSettingsPage(
        service: service,
        isAndroid: true,
        permissionGateway: _RecordingPermissionGateway(),
        batteryOptimizationGateway: _RecordingBatteryGateway(),
        channelHealthGateway: health,
      ),
    );

    expect(
      find.byKey(const Key('open-notification-channel-health')),
      findsNothing,
    );
    expect(find.textContaining('未授予通知权限'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 合并后的页面更长：用高视口让三组设置同时参与布局。
Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

class _RecordingChannelHealthGateway
    implements NotificationChannelHealthGateway {
  _RecordingChannelHealthGateway(this.health);

  NotificationChannelHealth health;
  final List<String> opened = [];
  int inspections = 0;

  @override
  Future<NotificationChannelHealth> inspectChannelHealth() async {
    inspections++;
    return health;
  }

  @override
  Future<void> openChannelSettings(String channelId) async {
    opened.add(channelId);
    // 用户在系统设置里把渠道重要性调回来之后返回应用。
    health = const NotificationChannelHealth.healthy();
  }
}

class _RecordingPermissionGateway implements DevicePermissionGateway {
  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<void> openAppSettings() async {}
}

class _RecordingBatteryGateway implements BatteryOptimizationGateway {
  @override
  Future<bool> isIgnoringBatteryOptimizations() async => true;

  @override
  Future<void> openBatteryOptimizationSettings() async {}
}

/// 通知权限被拒：降级提示不该盖过更根本的权限问题。
class _DeniedPermissionService extends FocusNotificationService {
  _DeniedPermissionService()
    : super(windowsChannel: const MethodChannel('channel_health_page/denied'));

  @override
  Future<FocusDevicePreferences> getPreferences() async =>
      const FocusDevicePreferences(
        notificationsEnabled: false,
        backgroundRunningEnabled: false,
        dailyOpenReminderMinutesAfterMidnight: 9 * 60,
        dailyOpenReminderTimeChosen: true,
      );

  @override
  Future<bool> notificationsAllowed() async => false;

  @override
  Future<bool> exactAlarmsAllowed() async => false;

  @override
  Future<void> dispose() async {}
}
