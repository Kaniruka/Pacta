import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/schedule_reminder_plan.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_windows_notifications.dart';

Schedule schedule({
  required String id,
  required DateTime startsAt,
  int? reminderMinutesBefore,
  bool isCompleted = false,
}) => Schedule(
  id: id,
  title: '取快递',
  startsAt: startsAt,
  endsAt: startsAt.add(const Duration(hours: 1)),
  createdAt: DateTime.utc(2026, 11, 1),
  updatedAt: DateTime.utc(2026, 11, 1),
  reminderMinutesBefore: reminderMinutesBefore,
  isCompleted: isCompleted,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeWindowsNotificationAdapter fake;
  late FocusNotificationService service;
  final now = DateTime.utc(2026, 11, 15, 1);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('com.pacta/focus_status');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    fake = FakeWindowsNotificationAdapter();
    service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsNotifications: fake,
      now: () => now,
    );
    await service.updatePreferences(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: true,
      ),
    );
  });

  tearDown(() async {
    await service.dispose();
  });

  test('a future schedule reminder is registered with the OS at its stored instant', () async {
    final target = schedule(
      id: 's-1',
      startsAt: DateTime.utc(2026, 11, 16, 10),
      reminderMinutesBefore: 30,
    );

    await service.syncScheduleReminders(
      schedules: [target],
      timeZoneId: 'Asia/Tokyo',
    );

    final registered = fake.scheduled.values.single;
    expect(registered.at, DateTime.utc(2026, 11, 16, 9, 30));
    expect(ScheduleReminderPlanner.ownsNotificationId(registered.id), isTrue);
    expect(
      registered.payload,
      startsWith(ScheduleReminderRequest.payloadPrefix),
    );
    expect(registered.title, '日程提醒');
  }, skip: !Platform.isWindows);

  test('turning the reminder off cancels the pending OS item', () async {
    await service.syncScheduleReminders(
      schedules: [
        schedule(
          id: 's-2',
          startsAt: DateTime.utc(2026, 11, 16, 10),
          reminderMinutesBefore: 10,
        ),
      ],
      timeZoneId: 'Asia/Tokyo',
    );
    final id = fake.scheduled.keys.single;

    await service.syncScheduleReminders(
      schedules: [
        schedule(id: 's-2', startsAt: DateTime.utc(2026, 11, 16, 10)),
      ],
      timeZoneId: 'Asia/Tokyo',
    );

    expect(fake.cancelled, contains(id));
    expect(fake.scheduled, isEmpty);
  }, skip: !Platform.isWindows);

  test(
    'items left by an earlier run are cancelled when they no longer apply',
    () async {
      fake.initialPending.add(230456);

      await service.syncScheduleReminders(
        schedules: const [],
        timeZoneId: 'Asia/Tokyo',
      );

      expect(fake.cancelled, contains(230456));
    },
    skip: !Platform.isWindows,
  );

  test('past reminders are skipped without touching the OS queue', () async {
    await service.syncScheduleReminders(
      schedules: [
        schedule(
          id: 'past',
          startsAt: DateTime.utc(2026, 11, 14, 10),
          reminderMinutesBefore: 5,
        ),
        schedule(
          id: 'completed',
          startsAt: DateTime.utc(2026, 11, 16, 10),
          reminderMinutesBefore: 5,
          isCompleted: true,
        ),
      ],
      timeZoneId: 'Asia/Tokyo',
    );

    expect(fake.scheduleCalls, isEmpty);
    expect(fake.cancelled, isEmpty);
  }, skip: !Platform.isWindows);

  test('disabling device reminders leaves the schedules untouched and cancels delivery', () async {
    await service.syncScheduleReminders(
      schedules: [
        schedule(
          id: 's-3',
          startsAt: DateTime.utc(2026, 11, 16, 10),
          reminderMinutesBefore: 10,
        ),
      ],
      timeZoneId: 'Asia/Tokyo',
    );
    final id = fake.scheduled.keys.single;

    await service.updatePreferences(
      const FocusDevicePreferences(
        notificationsEnabled: false,
        backgroundRunningEnabled: true,
      ),
    );
    await service.syncScheduleReminders(
      schedules: [
        schedule(
          id: 's-3',
          startsAt: DateTime.utc(2026, 11, 16, 10),
          reminderMinutesBefore: 10,
        ),
      ],
      timeZoneId: 'Asia/Tokyo',
    );

    expect(fake.cancelled, contains(id));
    expect(fake.scheduled, isEmpty);
  }, skip: !Platform.isWindows);

  test('a normal process detach keeps the OS queue, an explicit release cancels it', () async {
    await service.setUserId('user-a');
    await service.syncScheduleReminders(
      schedules: [
        schedule(
          id: 's-4',
          startsAt: DateTime.utc(2026, 11, 16, 10),
          reminderMinutesBefore: 10,
        ),
      ],
      timeZoneId: 'Asia/Tokyo',
    );
    final id = fake.scheduled.keys.single;
    fake.cancelled.clear();

    await service.detachForProcessExit();
    expect(fake.cancelled, isEmpty);
    expect(fake.scheduled, contains(id));

    await service.releaseUser('user-a');
    expect(fake.cancelled, contains(id));
    expect(fake.scheduled, isEmpty);
  }, skip: !Platform.isWindows);

  test(
    'a registration that finishes after the account changed is revoked',
    () async {
      final entered = Completer<void>();
      final gate = Completer<void>();
      fake.beforeSchedule = () async {
        entered.complete();
        await gate.future;
      };

      await service.setUserId('user-a');
      final pending = service.syncScheduleReminders(
        schedules: [
          schedule(
            id: 'late',
            startsAt: DateTime.utc(2026, 11, 16, 10),
            reminderMinutesBefore: 10,
          ),
        ],
        timeZoneId: 'Asia/Tokyo',
      );
      await entered.future;

      await service.setUserId('user-b');
      gate.complete();
      await pending;

      expect(fake.cancelled, isNotEmpty);
      expect(fake.scheduled, isEmpty);
    },
    skip: !Platform.isWindows,
  );

  test(
    'a schedule reminder click is routed separately from the focus flow',
    () async {
      final scheduleClicks = <ScheduleReminderRequest>[];
      final focusClicks = <String>[];
      final scheduleSub = service.openScheduleRequests.listen(
        scheduleClicks.add,
      );
      final focusSub = service.openFlowRequests.listen(focusClicks.add);
      addTearDown(scheduleSub.cancel);
      addTearDown(focusSub.cancel);

      service.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          id: 230123,
          payload: 'schedule-reminder:s-9:2026-11-16',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(scheduleClicks.single.scheduleId, 's-9');
      expect(scheduleClicks.single.dateKey, '2026-11-16');
      expect(service.takePendingScheduleRequest()?.scheduleId, 's-9');
      expect(service.takePendingOpenRequest(), isNull);
      expect(focusClicks, isEmpty);
    },
    skip: !Platform.isWindows,
  );

  test(
    'appointment transition and focus end are registered at persisted times',
    () async {
      final startsAt = DateTime.utc(2026, 11, 15, 2);
      final appointment = AppointmentPreparation(
        id: 'appointment-1',
        taskId: 'task-1',
        mode: FocusChainMode.regular,
        durationSeconds: 600,
        startedAt: startsAt,
        endsAt: startsAt.add(const Duration(minutes: 10)),
        status: AppointmentPreparationStatus.active,
        settledAt: null,
        updatedAt: startsAt,
      );
      await service.sync(appointment: appointment, taskTitle: '写报告');

      expect(fake.scheduled[2202]?.at, appointment.endsAt);

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
      await service.sync(session: session, taskTitle: '写报告');

      expect(fake.cancelled, contains(2202));
      expect(fake.scheduled[2203]?.at, session.endsAt);

      final registrations = fake.scheduleCalls.where((id) => id == 2203).length;
      await service.sync(session: session, taskTitle: '写报告');
      expect(
        fake.scheduleCalls.where((id) => id == 2203).length,
        registrations,
      );
    },
    skip: !Platform.isWindows,
  );
}
