import 'dart:io' show Platform;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/schedule_reminder_plan.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';
import '../support/fake_windows_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PactaDatabase database;
  late LocalScheduleRepository repository;
  late FakeWindowsNotificationAdapter fake;
  late FocusNotificationService service;
  final now = DateTime.utc(2026, 11, 15, 1);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
    const channel = MethodChannel('ticket06/focus_status');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(
              'dev.fluttercommunity.plus/connectivity_status',
            ),
            null,
          );
    });

    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalScheduleRepository(
      database: database,
      userId: 'schedule-user',
      now: () => now,
    );
    fake = FakeWindowsNotificationAdapter();
    service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsNotifications: fake,
      windowsChannel: channel,
      now: () => now,
    );
    await service.updatePreferences(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: true,
      ),
    );
    addTearDown(() async {
      await service.dispose();
      await repository.dispose();
      await database.close();
    });
  });

  testWidgets(
    'schedule changes reach the OS queue and clicks wait for the Plan destination',
    (tester) async {
      late Schedule created;
      await tester.runAsync(() async {
        created = await repository.createSchedule(
          ScheduleDraft(
            title: '取快递',
            window: ScheduleWindow.timed(
              startsAt: DateTime.utc(2026, 11, 16, 10),
              endsAt: DateTime.utc(2026, 11, 16, 11),
            ),
          ),
        );
        await repository.setScheduleReminder(created.id, minutesBefore: 30);
      });

      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = 'schedule-user',
          focusNotificationService: service,
          scheduleRepositoryFactory: (_) => repository,
        ),
      );
      await _settle(tester);

      final reminder = fake.scheduled.values.singleWhere(
        (item) => ScheduleReminderPlanner.ownsNotificationId(item.id),
      );
      expect(reminder.at, DateTime.utc(2026, 11, 16, 9, 30));

      await tester.runAsync(() async {
        await repository.setScheduleReminder(created.id);
      });
      await _settle(tester);
      expect(fake.scheduled.containsKey(reminder.id), isFalse);

      await tester.runAsync(() async {
        await repository.setScheduleReminder(created.id, minutesBefore: 30);
      });
      await _settle(tester);
      final rescheduled = fake.scheduled.values.singleWhere(
        (item) => ScheduleReminderPlanner.ownsNotificationId(item.id),
      );

      service.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          id: 230001,
          payload: 'schedule-reminder:s-1:2026-11-16',
        ),
      );
      await _settle(tester);

      expect(find.byType(AppShell), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(rescheduled.payload, startsWith('schedule-reminder:'));
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'leaving the shell keeps future OS reminders queued',
    (tester) async {
      await tester.runAsync(() async {
        final created = await repository.createSchedule(
          ScheduleDraft(
            title: '取快递',
            window: ScheduleWindow.timed(
              startsAt: DateTime.utc(2026, 11, 16, 10),
              endsAt: DateTime.utc(2026, 11, 16, 11),
            ),
          ),
        );
        await repository.setScheduleReminder(created.id, minutesBefore: 10);
      });

      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = 'schedule-user',
          focusNotificationService: service,
          scheduleRepositoryFactory: (_) => repository,
        ),
      );
      await _settle(tester);
      final id = fake.scheduled.keys.singleWhere(
        ScheduleReminderPlanner.ownsNotificationId,
      );
      fake.cancelled.clear();

      await tester.pumpWidget(const SizedBox());
      await _settle(tester);

      expect(fake.cancelled, isEmpty);
      expect(fake.scheduled, contains(id));
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}
