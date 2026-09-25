import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'automatic appointment handoff and session end notify only once',
    () async {
      const channel = MethodChannel('ticket_22/focus_status');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final preferences = await SharedPreferences.getInstance();
      final service = FocusNotificationService(
        preferencesStore: FocusDevicePreferencesStore(preferences),
        windowsChannel: channel,
      );
      addTearDown(() async {
        await service.clear();
        await service.dispose();
      });

      await service.updatePreferences(
        const FocusDevicePreferences(
          notificationsEnabled: true,
          backgroundRunningEnabled: true,
        ),
      );

      final now = DateTime.now();
      final appointment = AppointmentPreparation(
        id: 'appointment-1',
        taskId: 'task-1',
        mode: FocusChainMode.regular,
        durationSeconds: 600,
        startedAt: now,
        endsAt: now.add(const Duration(minutes: 10)),
        status: AppointmentPreparationStatus.active,
        settledAt: null,
        updatedAt: now,
      );
      await service.sync(appointment: appointment, taskTitle: 'Write a report');

      final session = FocusSession(
        id: 'session-1',
        appointmentId: appointment.id,
        taskId: appointment.taskId,
        mode: appointment.mode,
        durationSeconds: appointment.durationSeconds,
        startedAt: appointment.endsAt,
        endsAt: appointment.endsAt.add(
          Duration(seconds: appointment.durationSeconds),
        ),
        status: FocusSessionStatus.active,
        completedAt: null,
        effectiveSeconds: 0,
      );
      await service.sync(session: session, taskTitle: 'Write a report');
      await service.appointmentEnteredFocus(
        appointmentId: appointment.id,
        taskTitle: 'Write a report',
      );
      await service.sessionEnded(
        sessionId: session.id,
        appointmentId: appointment.id,
        taskTitle: 'Write a report',
        status: FocusSessionStatus.completed,
      );
      await service.sessionEnded(
        sessionId: session.id,
        appointmentId: appointment.id,
        taskTitle: 'Write a report',
        status: FocusSessionStatus.completed,
      );

      final notifications = calls
          .where((call) => call.method == 'showNotification')
          .map((call) => call.arguments as Map<Object?, Object?>)
          .toList();
      expect(notifications, hasLength(2));
      expect(notifications[0]['title'], '已进入专注');
      expect(notifications[1]['title'], '专注已完成');
    },
    skip: !Platform.isWindows,
  );

  test('opening a scheduled event does not show it again after sync', () async {
    const channel = MethodChannel('ticket_22/tapped_event_status');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final preferences = await SharedPreferences.getInstance();
    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(preferences),
      windowsChannel: channel,
    );
    addTearDown(() async {
      await service.clear();
      await service.dispose();
    });
    await service.updatePreferences(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: true,
      ),
    );

    service.handleNotificationResponse(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 2202,
        payload: 'appointment:appointment-tapped',
      ),
    );
    expect(service.takePendingOpenRequest(), 'appointment:appointment-tapped');
    await service.appointmentEnteredFocus(
      appointmentId: 'appointment-tapped',
      taskTitle: 'Tapped appointment',
    );

    service.handleNotificationResponse(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 2203,
        payload: 'appointment:appointment-tapped',
      ),
    );
    expect(service.takePendingOpenRequest(), 'appointment:appointment-tapped');
    await service.sessionEnded(
      sessionId: 'session-tapped',
      appointmentId: 'appointment-tapped',
      taskTitle: 'Tapped appointment',
      status: FocusSessionStatus.completed,
    );

    service.handleNotificationResponse(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 2203,
        payload: 'session:session-without-appointment',
      ),
    );
    await service.sessionEnded(
      sessionId: 'session-without-appointment',
      taskTitle: 'Standalone session',
      status: FocusSessionStatus.completed,
    );

    expect(calls.where((call) => call.method == 'showNotification'), isEmpty);
  }, skip: !Platform.isWindows);
}
