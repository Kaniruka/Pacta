import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
    'a due National Focus reminder is sent once and remains sent after restart',
    () async {
      const channel = MethodChannel('ticket_23/reminder_status');
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

      var now = DateTime.utc(2026, 9, 26, 14, 5);
      final preferences = await SharedPreferences.getInstance();
      final store = FocusDevicePreferencesStore(preferences);
      await store.save(
        const FocusDevicePreferences(
          notificationsEnabled: false,
          backgroundRunningEnabled: false,
        ),
      );
      final firstService = FocusNotificationService(
        preferencesStore: store,
        windowsChannel: channel,
        now: () => now,
      );
      addTearDown(() async {
        await firstService.clear();
        await firstService.dispose();
      });

      await firstService.syncNationalFocusReminder(
        hasPendingConfirmations: true,
      );
      await firstService.syncNationalFocusReminder(
        hasPendingConfirmations: true,
      );

      final sent = calls
          .where((call) => call.method == 'showNotification')
          .toList();
      expect(sent, hasLength(1));
      expect(
        (sent.single.arguments as Map<Object?, Object?>)['title'],
        '国策待确认',
      );

      final restoredService = FocusNotificationService(
        preferencesStore: store,
        windowsChannel: channel,
        now: () => now,
      );
      addTearDown(() async {
        await restoredService.clear();
        await restoredService.dispose();
      });
      await restoredService.syncNationalFocusReminder(
        hasPendingConfirmations: true,
      );

      expect(
        calls.where((call) => call.method == 'showNotification'),
        hasLength(1),
      );
    },
    skip: !Platform.isWindows,
  );

  test('a pending reminder waits until an active flow ends', () async {
    const channel = MethodChannel('ticket_23/deferred_reminder_status');
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

    var now = DateTime.utc(2026, 9, 26, 13, 59);
    final preferences = await SharedPreferences.getInstance();
    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(preferences),
      windowsChannel: channel,
      now: () => now,
    );
    addTearDown(() async {
      await service.clear();
      await service.dispose();
    });

    await service.syncNationalFocusReminder(hasPendingConfirmations: true);
    await service.sync(
      session: _activeSession(DateTime.utc(2026, 9, 26, 15)),
      taskTitle: 'Write a report',
    );
    await service.syncNationalFocusReminder(hasPendingConfirmations: true);
    now = DateTime.utc(2026, 9, 26, 14, 5);
    await service.sync(
      session: _activeSession(DateTime.utc(2026, 9, 26, 15)),
      taskTitle: 'Write a report',
    );
    expect(calls.where((call) => call.method == 'showNotification'), isEmpty);

    now = DateTime.utc(2026, 9, 26, 15);
    await service.sync(taskTitle: '当前任务');
    expect(
      calls.where((call) => call.method == 'showNotification'),
      hasLength(1),
    );
  }, skip: !Platform.isWindows);

  test('confirming every pending node cancels a waiting reminder', () async {
    const channel = MethodChannel('ticket_23/cancelled_reminder_status');
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

    var now = DateTime.utc(2026, 9, 26, 13, 59);
    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(
        await SharedPreferences.getInstance(),
      ),
      windowsChannel: channel,
      now: () => now,
    );
    addTearDown(() async {
      await service.clear();
      await service.dispose();
    });

    await service.syncNationalFocusReminder(hasPendingConfirmations: true);
    await service.syncNationalFocusReminder(hasPendingConfirmations: false);
    now = DateTime.utc(2026, 9, 26, 14, 5);
    await service.syncNationalFocusReminder(hasPendingConfirmations: false);

    expect(calls.where((call) => call.method == 'showNotification'), isEmpty);
  }, skip: !Platform.isWindows);
}

FocusSession _activeSession(DateTime endsAt) => FocusSession(
  id: 'session-1',
  taskId: 'task-1',
  mode: FocusChainMode.regular,
  durationSeconds: 30 * 60,
  startedAt: endsAt.subtract(const Duration(minutes: 30)),
  endsAt: endsAt,
  status: FocusSessionStatus.active,
  completedAt: null,
  effectiveSeconds: 0,
);
