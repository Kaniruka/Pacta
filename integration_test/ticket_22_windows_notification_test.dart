import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T22 Windows tray status and focus transition notifications', (
    tester,
  ) async {
    const trayChannel = MethodChannel('com.pacta/focus_status');
    const eventProbeChannel = MethodChannel('ticket_22/windows_event_probe');
    final eventCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventProbeChannel, (call) async {
          eventCalls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(eventProbeChannel, null),
    );
    final preferencesStore = FocusDevicePreferencesStore(
      await SharedPreferences.getInstance(),
    );
    final service = FocusNotificationService(
      preferencesStore: preferencesStore,
    );
    final eventProbeService = FocusNotificationService(
      preferencesStore: preferencesStore,
      windowsChannel: eventProbeChannel,
    );
    addTearDown(() async {
      await service.clear();
      await service.dispose();
      await eventProbeService.clear();
      await eventProbeService.dispose();
    });

    await service.initialize();
    await service.updatePreferences(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: true,
      ),
    );

    final now = DateTime.now();
    final appointment = AppointmentPreparation(
      id: 'ticket-22-windows-appointment',
      taskId: 'ticket-22-windows-task',
      mode: FocusChainMode.regular,
      durationSeconds: 30,
      startedAt: now,
      endsAt: now.add(const Duration(seconds: 4)),
      status: AppointmentPreparationStatus.active,
      settledAt: null,
      updatedAt: now,
    );
    await service.sync(
      appointment: appointment,
      taskTitle: 'T22 Windows 后台验收任务',
    );
    await eventProbeService.sync(
      appointment: appointment,
      taskTitle: 'T22 Windows 后台验收任务',
    );
    await expectLater(
      trayChannel.invokeMethod<void>('updateStatus', {
        'text': 'T22 Windows 专注中 · 00:30',
        'active': true,
      }),
      completes,
    );
    debugPrint('T22_WINDOWS_TRAY_STATUS_UPDATED');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 40)),
    );
    final timerNotifications = eventCalls
        .where((call) => call.method == 'showNotification')
        .map((call) => call.arguments as Map<Object?, Object?>)
        .toList();
    expect(timerNotifications, hasLength(2));
    expect(timerNotifications[0]['title'], '已进入专注');
    expect(timerNotifications[1]['title'], '专注已完成');
    await expectLater(
      trayChannel.invokeMethod<void>('showNotification', {
        'title': 'T22 托盘通知验收',
        'body': 'Windows 托盘通知通道已响应。',
      }),
      completes,
    );
    debugPrint('T22_WINDOWS_TRANSITION_AND_END_NOTIFICATIONS_SENT');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
