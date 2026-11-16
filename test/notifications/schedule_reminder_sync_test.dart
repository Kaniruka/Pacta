import 'dart:io' show Platform;

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/schedule_reminder_plan.dart';
import 'package:pacta/src/notifications/schedule_reminder_sync.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_windows_notifications.dart';

Future<void> _settle(ScheduleReminderSync sync) async {
  await Future<void>.delayed(const Duration(milliseconds: 40));
  await sync.settled;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repository changes reconcile the OS queue once per sync', () async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('ticket06/sync_status');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final clock = DateTime.utc(2026, 11, 15, 1);
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalScheduleRepository(
      database: database,
      userId: 'sync-user',
      now: () => clock,
    );
    final fake = FakeWindowsNotificationAdapter();
    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsNotifications: fake,
      windowsChannel: channel,
      now: () => clock,
    );
    await service.updatePreferences(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: false,
      ),
    );
    await service.setUserId('sync-user');
    final sync = ScheduleReminderSync(
      notificationService: service,
      accountTimeZoneId: () async => 'Etc/UTC',
      now: () => clock,
    );
    addTearDown(() async {
      await sync.detach();
      await service.dispose();
      await repository.dispose();
      await database.close();
    });

    final created = await repository.createSchedule(
      ScheduleDraft(
        title: '取快递',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 16, 10),
          endsAt: DateTime.utc(2026, 11, 16, 11),
        ),
      ),
    );
    await repository.setScheduleReminder(created.id, minutesBefore: 30);

    await sync.attach(repository);
    await _settle(sync);

    expect(
      fake.scheduled.values
          .singleWhere(
            (item) => ScheduleReminderPlanner.ownsNotificationId(item.id),
          )
          .at,
      DateTime.utc(2026, 11, 16, 9, 30),
    );

    await repository.setScheduleReminder(created.id);
    await _settle(sync);
    expect(
      fake.scheduled.keys.where(ScheduleReminderPlanner.ownsNotificationId),
      isEmpty,
    );

    await sync.detach();
    await repository.setScheduleReminder(created.id, minutesBefore: 5);
    await _settle(sync);
    expect(
      fake.scheduled.keys.where(ScheduleReminderPlanner.ownsNotificationId),
      isEmpty,
    );
  }, skip: !Platform.isWindows);
}
