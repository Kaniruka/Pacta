import 'dart:async';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PactaDatabase database;
  late LocalScheduleRepository repository;
  late FakeWindowsNotificationAdapter fake;
  late FocusNotificationService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('ticket06/sync_race');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalScheduleRepository(
      database: database,
      userId: 'sync-user',
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    fake = FakeWindowsNotificationAdapter();
    service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsNotifications: fake,
      windowsChannel: channel,
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    await service.updatePreferences(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: false,
      ),
    );
    await service.setUserId('sync-user');
    addTearDown(() async {
      await service.dispose();
      await repository.dispose();
      await database.close();
    });
  });

  test('a push invalidated by detach never reaches the service', () async {
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

    final zoneEntered = Completer<void>();
    final zoneGate = Completer<void>();
    final sync = ScheduleReminderSync(
      notificationService: service,
      accountTimeZoneId: () async {
        if (!zoneEntered.isCompleted) zoneEntered.complete();
        await zoneGate.future;
        return 'Etc/UTC';
      },
      now: () => DateTime.utc(2026, 11, 15, 1),
    );
    addTearDown(sync.detach);

    await sync.attach(repository);
    await zoneEntered.future;
    await sync.detach();
    zoneGate.complete();
    await sync.settled;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(fake.scheduleCalls, isEmpty);
  }, skip: !Platform.isWindows);

  test(
    'a resumed window re-reads rows that were outside the old horizon',
    () async {
      var clock = DateTime.utc(2026, 11, 15, 1);
      final created = await repository.createSchedule(
        ScheduleDraft(
          title: '远期取快递',
          window: ScheduleWindow.timed(
            startsAt: clock.add(const Duration(days: 10)),
            endsAt: clock.add(const Duration(days: 10, hours: 1)),
          ),
        ),
      );
      await repository.setScheduleReminder(created.id, minutesBefore: 30);

      final sync = ScheduleReminderSync(
        notificationService: service,
        accountTimeZoneId: () async => 'Etc/UTC',
        now: () => clock,
        window: const Duration(days: 1),
      );
      addTearDown(sync.detach);

      await sync.attach(repository);
      await sync.reconcileOnce();
      expect(fake.scheduled, isEmpty);

      clock = clock.add(const Duration(days: 8));
      // reconcileOnce reads the new window itself; the returned future is the
      // completion condition, not the subscription's first event.
      await sync.reconcileOnce();

      expect(
        fake.scheduled.values.where(
          (item) => ScheduleReminderPlanner.ownsNotificationId(item.id),
        ),
        hasLength(1),
      );
    },
    skip: !Platform.isWindows,
  );
}
