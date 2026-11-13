import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/focus_notification_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the daily reminder is off by default and shows its local time', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    await tester.pumpWidget(fixture.page());
    await tester.pumpAndSettle();

    expect(find.text('每天打开 Pacta'), findsOneWidget);
    expect(find.text('提醒时间（本机时间）'), findsOneWidget);
    expect(find.text('09:00'), findsOneWidget);
    expect(fixture.switchValue(tester), isFalse);
    expect(find.text('仅在 Pacta 正在运行（含隐藏到托盘）时送达；完全退出后不会提醒。'), findsOneWidget);
  }, skip: !Platform.isWindows);

  testWidgets('the first enable asks for a time and keeps the choice', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    fixture.nextPick = const TimeOfDay(hour: 7, minute: 40);

    await tester.pumpWidget(fixture.page());
    await tester.pumpAndSettle();

    await tester.tap(find.text('每天打开 Pacta'));
    await tester.pumpAndSettle();

    expect(fixture.pickRequests, ['选择每日提醒时间（本机时间）']);
    final preferences = await fixture.service.getPreferences();
    expect(preferences.dailyOpenReminderEnabled, isTrue);
    expect(preferences.dailyOpenReminderMinutesAfterMidnight, 7 * 60 + 40);
    expect(preferences.dailyOpenReminderTimeChosen, isTrue);
    expect(find.text('07:40'), findsOneWidget);
    expect(fixture.switchValue(tester), isTrue);
  }, skip: !Platform.isWindows);

  testWidgets('cancelling the first time choice leaves the reminder off', (
    tester,
  ) async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    fixture.nextPick = null;

    await tester.pumpWidget(fixture.page());
    await tester.pumpAndSettle();

    await tester.tap(find.text('每天打开 Pacta'));
    await tester.pumpAndSettle();

    expect(fixture.pickRequests, hasLength(1));
    expect(
      (await fixture.service.getPreferences()).dailyOpenReminderEnabled,
      isFalse,
    );
    expect(fixture.switchValue(tester), isFalse);
    expect(fixture.notifications, isEmpty);
  }, skip: !Platform.isWindows);

  testWidgets('a chosen time enables without asking again', (tester) async {
    final fixture = await _Fixture.create(
      initial: const FocusDevicePreferences(
        notificationsEnabled: false,
        backgroundRunningEnabled: true,
        dailyOpenReminderMinutesAfterMidnight: 6 * 60 + 5,
        dailyOpenReminderTimeChosen: true,
      ),
    );
    addTearDown(fixture.dispose);
    fixture.nextPick = const TimeOfDay(hour: 23, minute: 0);

    await tester.pumpWidget(fixture.page());
    await tester.pumpAndSettle();

    await tester.tap(find.text('每天打开 Pacta'));
    await tester.pumpAndSettle();

    expect(fixture.pickRequests, isEmpty);
    expect(
      (await fixture.service.getPreferences()).dailyOpenReminderEnabled,
      isTrue,
    );
    expect(find.text('06:05'), findsOneWidget);
  }, skip: !Platform.isWindows);

  testWidgets('changing the time keeps the reminder enabled', (tester) async {
    final fixture = await _Fixture.create(
      initial: const FocusDevicePreferences(
        notificationsEnabled: false,
        backgroundRunningEnabled: true,
        dailyOpenReminderEnabled: true,
        dailyOpenReminderMinutesAfterMidnight: 8 * 60,
        dailyOpenReminderTimeChosen: true,
      ),
    );
    addTearDown(fixture.dispose);
    fixture.nextPick = const TimeOfDay(hour: 21, minute: 15);

    await tester.pumpWidget(fixture.page());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('daily-open-reminder-time')));
    await tester.pumpAndSettle();

    final preferences = await fixture.service.getPreferences();
    expect(preferences.dailyOpenReminderMinutesAfterMidnight, 21 * 60 + 15);
    expect(preferences.dailyOpenReminderEnabled, isTrue);
    expect(find.text('21:15'), findsOneWidget);
  }, skip: !Platform.isWindows);

  testWidgets('turning the reminder off stops scheduling it', (tester) async {
    final fixture = await _Fixture.create(
      initial: const FocusDevicePreferences(
        notificationsEnabled: false,
        backgroundRunningEnabled: true,
        dailyOpenReminderEnabled: true,
        dailyOpenReminderMinutesAfterMidnight: 8 * 60,
        dailyOpenReminderTimeChosen: true,
      ),
    );
    addTearDown(fixture.dispose);

    await fixture.service.syncDailyOpenReminder();
    await tester.pumpWidget(fixture.page());
    await tester.pumpAndSettle();
    expect(fixture.timers.where((timer) => timer.timer.isActive), hasLength(1));

    await tester.tap(find.text('每天打开 Pacta'));
    await tester.pumpAndSettle();

    expect(
      (await fixture.service.getPreferences()).dailyOpenReminderEnabled,
      isFalse,
    );
    expect(fixture.timers.where((timer) => timer.timer.isActive), isEmpty);
    expect(fixture.switchValue(tester), isFalse);
  }, skip: !Platform.isWindows);
}

class _Fixture {
  _Fixture._({
    required this.service,
    required this.notifications,
    required this.timers,
  });

  final FocusNotificationService service;
  final List<Map<Object?, Object?>> notifications;
  final List<TestTimerRecord> timers;
  final List<String> pickRequests = [];
  TimeOfDay? nextPick;

  bool switchValue(WidgetTester tester) => tester
      .widget<SwitchListTile>(
        find.byKey(const Key('daily-open-reminder-enabled')),
      )
      .value;

  Widget page() => MaterialApp(
    home: FocusNotificationSettingsPage(
      service: service,
      timePicker: (minutes, helpText) async {
        pickRequests.add(helpText);
        return nextPick;
      },
    ),
  );

  static Future<_Fixture> create({FocusDevicePreferences? initial}) async {
    const channel = MethodChannel('issue95/reminder_settings_page');
    final preferences = await SharedPreferences.getInstance();
    final store = FocusDevicePreferencesStore(preferences);
    if (initial != null) await store.save(initial);
    final notifications = <Map<Object?, Object?>>[];
    final timers = <TestTimerRecord>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'showNotification') {
            notifications.add(call.arguments as Map<Object?, Object?>);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    return _Fixture._(
      service: FocusNotificationService(
        preferencesStore: store,
        windowsChannel: channel,
        localTimeZone: () async => 'Asia/Shanghai',
        reminderTimers: (delay, callback) {
          // Timers are created outside the widget-test fake zone so an hours
          // long reminder does not count as a leaked pending timer.
          final timer = Zone.root.createTimer(delay, callback);
          timers.add(TestTimerRecord(delay, callback, timer));
          return timer;
        },
      ),
      notifications: notifications,
      timers: timers,
    );
  }

  Future<void> dispose() async {
    for (final timer in timers) {
      timer.timer.cancel();
    }
    try {
      await service.clear();
    } catch (_) {
      // The removed test channel must not hide assertion results.
    }
    await service.dispose();
  }
}

class TestTimerRecord {
  TestTimerRecord(this.delay, this.callback, this.timer);

  final Duration delay;
  final void Function() callback;
  final Timer timer;
}
