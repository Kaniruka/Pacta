import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/daily_open_reminder_state.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('the daily reminder is planned for the next local occurrence', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
    );
    addTearDown(fixture.dispose);

    await fixture.enable();

    expect(fixture.pendingTimers, hasLength(1));
    expect(fixture.pendingTimers.single.delay, const Duration(hours: 1));
    final scheduled = fixture.state.loadScheduled();
    expect(scheduled?.dayKey, '2026-11-13');
    expect(scheduled?.timeZoneId, 'Asia/Shanghai');
    expect(fixture.notifications, isEmpty);
  }, skip: !Platform.isWindows);

  test(
    'a due daily reminder notifies once and plans the next local day',
    () async {
      final fixture = await _Fixture.create(
        now: DateTime(2026, 11, 13, 7),
        minuteOfDay: 8 * 60,
      );
      addTearDown(fixture.dispose);
      await fixture.enable();

      fixture.setNow(DateTime(2026, 11, 13, 8));
      await fixture.fireLatestTimer();

      expect(fixture.notifications, hasLength(1));
      expect(fixture.notifications.single['title'], '打开 Pacta');
      expect(fixture.state.loadLastSentDayKey(), '2026-11-13');
      expect(fixture.pendingTimers, hasLength(1));
      expect(fixture.pendingTimers.single.delay, const Duration(hours: 24));
      expect(fixture.state.loadScheduled()?.dayKey, '2026-11-14');
    },
    skip: !Platform.isWindows,
  );

  test('repeating reconciliation keeps one pending daily timer', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
    );
    addTearDown(fixture.dispose);
    await fixture.enable();
    await fixture.service.syncDailyOpenReminder();
    await fixture.service.syncDailyOpenReminder();

    expect(fixture.pendingTimers, hasLength(1));
    expect(fixture.notifications, isEmpty);
  }, skip: !Platform.isWindows);

  test('changing the local time replaces the pending reminder once', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
    );
    addTearDown(fixture.dispose);
    await fixture.enable();

    await fixture.changeTime(9 * 60 + 15);

    expect(fixture.pendingTimers, hasLength(1));
    expect(
      fixture.state.loadScheduled()!.scheduledAt.toLocal(),
      DateTime(2026, 11, 13, 9, 15),
    );
    expect(fixture.notifications, isEmpty);
  }, skip: !Platform.isWindows);

  test('turning the daily reminder off cancels the pending reminder', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
    );
    addTearDown(fixture.dispose);
    await fixture.enable();

    await fixture.disable();

    expect(fixture.pendingTimers, isEmpty);
    expect(fixture.state.loadScheduled(), isNull);
    expect(fixture.notifications, isEmpty);
  }, skip: !Platform.isWindows);

  test(
    'a restart reuses the existing plan without a second reminder',
    () async {
      final fixture = await _Fixture.create(
        now: DateTime(2026, 11, 13, 7),
        minuteOfDay: 8 * 60,
      );
      addTearDown(fixture.dispose);
      await fixture.enable();
      // A restart ends the previous process, so only its stored plan survives.
      await fixture.service.dispose();
      fixture.paused = true;

      final restarted = await _Fixture.create(
        now: DateTime(2026, 11, 13, 7, 5),
        minuteOfDay: 8 * 60,
        sharedPreferences: fixture.preferences,
        timers: fixture.timers,
        seedPreferences: false,
        channelName: 'issue95/restarted_reminder_status',
      );
      addTearDown(restarted.dispose);
      await restarted.service.syncDailyOpenReminder();

      expect(fixture.pendingTimers, hasLength(1));
      expect(fixture.notifications, isEmpty);
      expect(fixture.state.loadScheduled()?.dayKey, '2026-11-13');
    },
    skip: !Platform.isWindows,
  );

  test('days closed while the app was off are never replayed', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
    );
    addTearDown(fixture.dispose);
    await fixture.enable();
    fixture.setNow(DateTime(2026, 11, 13, 8));
    await fixture.fireLatestTimer();
    expect(fixture.notifications, hasLength(1));
    await fixture.service.dispose();
    fixture.paused = true;

    final restarted = await _Fixture.create(
      now: DateTime(2026, 11, 16, 9),
      minuteOfDay: 8 * 60,
      sharedPreferences: fixture.preferences,
      timers: fixture.timers,
      seedPreferences: false,
      channelName: 'issue95/reopened_reminder_status',
    );
    addTearDown(restarted.dispose);
    await restarted.service.syncDailyOpenReminder();

    expect(
      fixture.notifications,
      hasLength(1),
      reason: 'Missed local days must not produce backlog notifications.',
    );
    expect(
      fixture.state.loadScheduled()!.scheduledAt.toLocal(),
      DateTime(2026, 11, 17, 8),
    );
  }, skip: !Platform.isWindows);

  test('a changed device time zone replans the reminder', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
    );
    addTearDown(fixture.dispose);
    await fixture.enable();
    expect(fixture.state.loadScheduled()?.timeZoneId, 'Asia/Shanghai');

    fixture.setTimeZone('Europe/Berlin');
    await fixture.service.syncDailyOpenReminder();

    expect(fixture.state.loadScheduled()?.timeZoneId, 'Europe/Berlin');
    expect(fixture.pendingTimers, hasLength(1));
  }, skip: !Platform.isWindows);

  test('a Windows tray click forwards the reminder payload', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
    );
    addTearDown(fixture.dispose);
    await fixture.service.initialize();

    final requests = <String>[];
    final subscription = fixture.service.openFlowRequests.listen(requests.add);
    addTearDown(subscription.cancel);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'issue95/daily_reminder_status',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall(
              'notificationClicked',
              'daily-open-reminder:2026-11-13',
            ),
          ),
          (_) {},
        );
    await Future<void>.delayed(Duration.zero);

    expect(requests, ['daily-open-reminder:2026-11-13']);
    expect(
      fixture.service.takePendingOpenRequest(),
      'daily-open-reminder:2026-11-13',
    );
  }, skip: !Platform.isWindows);

  test('the daily reminder payload opens the board', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
    );
    addTearDown(fixture.dispose);

    final requests = <String>[];
    final subscription = fixture.service.openFlowRequests.listen(requests.add);
    addTearDown(subscription.cancel);

    fixture.service.handleNotificationResponse(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 2205,
        payload: 'daily-open-reminder:2026-11-13',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(requests, ['daily-open-reminder:2026-11-13']);
    expect(
      fixture.service.takePendingOpenRequest(),
      'daily-open-reminder:2026-11-13',
    );
  }, skip: !Platform.isWindows);
}

class _RecordedTimer {
  _RecordedTimer(this.delay, this.callback, this.timer);

  final Duration delay;
  final void Function() callback;
  final Timer timer;
}

class _Fixture {
  _Fixture._({
    required this.service,
    required this.store,
    required this.state,
    required this.preferences,
    required this.timers,
    required this._setNow,
    required this._setTimeZone,
  });

  final FocusNotificationService service;
  final FocusDevicePreferencesStore store;
  final DailyOpenReminderStateStore state;
  final SharedPreferences preferences;
  final List<_RecordedTimer> timers;
  final void Function(DateTime) _setNow;
  final void Function(String) _setTimeZone;
  final List<Map<Object?, Object?>> notifications = [];

  List<_RecordedTimer> get pendingTimers =>
      timers.where((recorded) => recorded.timer.isActive).toList();

  void setNow(DateTime value) => _setNow(value);

  void setTimeZone(String value) => _setTimeZone(value);

  static Future<_Fixture> create({
    required DateTime now,
    required int minuteOfDay,
    SharedPreferences? sharedPreferences,
    List<_RecordedTimer>? timers,
    bool seedPreferences = true,
    String channelName = 'issue95/daily_reminder_status',
  }) async {
    final channel = MethodChannel(channelName);
    final preferences =
        sharedPreferences ?? await SharedPreferences.getInstance();
    final recordedTimers = timers ?? <_RecordedTimer>[];
    var clock = now;
    var zone = 'Asia/Shanghai';
    late final _Fixture fixture;

    final service = FocusNotificationService(
      preferencesStore: FocusDevicePreferencesStore(preferences),
      dailyOpenReminderStateStore: DailyOpenReminderStateStore(preferences),
      windowsChannel: channel,
      now: () => clock,
      localTimeZone: () async => zone,
      reminderTimers: (delay, callback) {
        final timer = Timer(delay, callback);
        recordedTimers.add(_RecordedTimer(delay, callback, timer));
        return timer;
      },
    );
    fixture = _Fixture._(
      service: service,
      store: FocusDevicePreferencesStore(preferences),
      state: DailyOpenReminderStateStore(preferences),
      preferences: preferences,
      timers: recordedTimers,
      setNow: (value) => clock = value,
      setTimeZone: (value) => zone = value,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'showNotification') {
            fixture.notifications.add(call.arguments as Map<Object?, Object?>);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    if (seedPreferences) {
      await fixture.store.save(
        FocusDevicePreferences(
          notificationsEnabled: false,
          backgroundRunningEnabled: false,
          dailyOpenReminderMinutesAfterMidnight: minuteOfDay,
          dailyOpenReminderTimeChosen: true,
        ),
      );
    }
    return fixture;
  }

  Future<void> enable() async {
    final current = await store.load();
    await service.updatePreferences(
      current.copyWith(dailyOpenReminderEnabled: true),
    );
  }

  Future<void> disable() async {
    final current = await store.load();
    await service.updatePreferences(
      current.copyWith(dailyOpenReminderEnabled: false),
    );
  }

  Future<void> changeTime(int minuteOfDay) async {
    final current = await store.load();
    await service.updatePreferences(
      current.copyWith(dailyOpenReminderMinutesAfterMidnight: minuteOfDay),
    );
  }

  Future<void> fireLatestTimer() async {
    timers.last.callback();
    await Future<void>.delayed(Duration.zero);
    await service.pendingDailyReminderWork;
  }

  bool paused = false;

  Future<void> dispose() async {
    for (final recorded in timers) {
      recorded.timer.cancel();
    }
    if (paused) return;
    try {
      await service.clear();
    } catch (_) {
      // A removed test channel must not hide the assertion results.
    }
    await service.dispose();
  }
}
