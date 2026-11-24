import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/daily_open_reminder_state.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/national_focus_reminder_state.dart';
import 'package:pacta/src/notifications/windows_notification_adapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Windows 的 2204 / 2205 走系统通知中心：只有适配器不可用时才回退进程内 Timer。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('计划写入系统通知中心，不再创建进程内计时器', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
    );
    addTearDown(fixture.dispose);

    await fixture.enableDaily();

    final scheduled = fixture.adapter.scheduled
        .where((entry) => entry.id == 2205)
        .toList();
    expect(scheduled, hasLength(1));
    expect(scheduled.single.at.toLocal(), DateTime(2026, 11, 13, 8));
    expect(scheduled.single.title, '打开 Pacta');
    expect(scheduled.single.payload, 'daily-open-reminder:2026-11-13');
    expect(
      fixture.pendingTimers,
      isEmpty,
      reason: '系统通知中心接管投递后，进程内计时器只会造成重复提醒',
    );
    expect(fixture.adapter.pending, contains(2205));
  }, skip: !Platform.isWindows);

  test('关闭每日提醒会在系统队列里撤掉 2205', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
    );
    addTearDown(fixture.dispose);
    await fixture.enableDaily();

    await fixture.disableDaily();

    expect(fixture.adapter.cancelled, contains(2205));
    expect(fixture.adapter.pending, isNot(contains(2205)));
    expect(fixture.pendingTimers, isEmpty);
  }, skip: !Platform.isWindows);

  test('国策提醒的首次计划写进系统队列', () async {
    final fixture = await _Fixture.create(
      now: DateTime.utc(2026, 9, 26, 13, 59),
      minuteOfDay: 22 * 60,
      nationalEnabled: true,
    );
    addTearDown(fixture.dispose);

    await fixture.service.syncNationalFocusReminder(
      hasPendingConfirmations: true,
    );

    final scheduled = fixture.adapter.scheduled
        .where((entry) => entry.id == 2204)
        .toList();
    expect(scheduled, hasLength(1));
    expect(scheduled.single.at.toUtc(), DateTime.utc(2026, 9, 26, 14));
    expect(scheduled.single.title, '国策待确认');
    expect(scheduled.single.payload, 'national-focus-reminder:2026-09-26');
    expect(fixture.pendingTimers, isEmpty);
  }, skip: !Platform.isWindows);

  test('关闭期间 OS 已送达 2204 时，重新进入应用只推进到下一天', () async {
    final fixture = await _Fixture.create(
      now: DateTime.utc(2026, 9, 26, 15),
      minuteOfDay: 22 * 60,
      nationalEnabled: true,
    );
    addTearDown(fixture.dispose);
    // 进程关着的时候，系统已在 22:00（北京时区 14:00 UTC）替我们送达；本地只
    // 留下"已排程"标记，通知中心里已经没有这个 id。
    await fixture.nationalState.saveScheduled(
      NationalFocusReminderSchedule(
        dayKey: '2026-09-26',
        scheduledAt: DateTime.utc(2026, 9, 26, 14),
        repeatsDaily: false,
      ),
    );

    await fixture.service.syncNationalFocusReminder(
      hasPendingConfirmations: true,
    );

    expect(
      fixture.statusCalls.map((call) => call.method),
      isNot(contains('showNotification')),
      reason: 'OS 已经弹过这一次，重进应用不能再补一张即时 toast',
    );
    expect(fixture.nationalState.loadLastSentDayKey(), '2026-09-26');
    final scheduled = fixture.adapter.scheduled
        .where((entry) => entry.id == 2204)
        .toList();
    expect(scheduled, hasLength(1));
    expect(scheduled.single.at.toUtc(), DateTime.utc(2026, 9, 27, 14));
    expect(scheduled.single.payload, 'national-focus-reminder:2026-09-27');
    expect(fixture.pendingTimers, isEmpty);
  }, skip: !Platform.isWindows);

  test('确认完待确认国策会在系统队列里撤掉 2204', () async {
    final fixture = await _Fixture.create(
      now: DateTime.utc(2026, 9, 26, 13, 59),
      minuteOfDay: 22 * 60,
      nationalEnabled: true,
    );
    addTearDown(fixture.dispose);
    await fixture.service.syncNationalFocusReminder(
      hasPendingConfirmations: true,
    );

    await fixture.service.syncNationalFocusReminder(
      hasPendingConfirmations: false,
    );

    expect(fixture.adapter.cancelled, contains(2204));
    expect(fixture.adapter.pending, isNot(contains(2204)));
  }, skip: !Platform.isWindows);

  test('登出会把 2204 与 2205 一起从系统队列里撤掉', () async {
    final fixture = await _Fixture.create(
      now: DateTime.utc(2026, 9, 26, 13, 59),
      minuteOfDay: 22 * 60,
      nationalEnabled: true,
    );
    addTearDown(fixture.dispose);
    await fixture.service.setUserId('user-a');
    await fixture.service.syncNationalFocusReminder(
      hasPendingConfirmations: true,
    );
    await fixture.enableDaily();
    fixture.adapter.cancelled.clear();

    await fixture.service.setUserId(null);

    expect(fixture.adapter.cancelled, containsAll(<int>[2204, 2205]));
    expect(fixture.adapter.pending, isEmpty);
  }, skip: !Platform.isWindows);

  test('适配器不可用时回退到进程内计时器', () async {
    final fixture = await _Fixture.create(
      now: DateTime(2026, 11, 13, 7),
      minuteOfDay: 8 * 60,
      adapter: _FakeWindowsAdapter(ready: false),
    );
    addTearDown(fixture.dispose);

    await fixture.enableDaily();

    expect(fixture.adapter.scheduled, isEmpty, reason: '没有可用的 OS 注册就不该假装已经排程');
    expect(fixture.pendingTimers, hasLength(1));
    expect(fixture.pendingTimers.single.delay, const Duration(hours: 1));
  }, skip: !Platform.isWindows);
}

class _Fixture {
  _Fixture._({
    required this.service,
    required this.store,
    required this.dailyState,
    required this.nationalState,
    required this.adapter,
    required this.timers,
    required this.statusCalls,
  });

  final FocusNotificationService service;
  final FocusDevicePreferencesStore store;
  final DailyOpenReminderStateStore dailyState;
  final NationalFocusReminderStateStore nationalState;
  final _FakeWindowsAdapter adapter;
  final List<_RecordedTimer> timers;

  /// 状态通道收到的调用：用来证明"没有补一张即时 toast"。
  final List<MethodCall> statusCalls;

  List<_RecordedTimer> get pendingTimers =>
      timers.where((recorded) => recorded.timer.isActive).toList();

  Future<void> enableDaily() async {
    final current = await store.load();
    await service.updatePreferences(
      current.copyWith(dailyOpenReminderEnabled: true),
    );
  }

  Future<void> disableDaily() async {
    final current = await store.load();
    await service.updatePreferences(
      current.copyWith(dailyOpenReminderEnabled: false),
    );
  }

  static Future<_Fixture> create({
    required DateTime now,
    required int minuteOfDay,
    bool nationalEnabled = false,
    _FakeWindowsAdapter? adapter,
  }) async {
    const channel = MethodChannel('windows_os_schedule/status');
    final preferences = await SharedPreferences.getInstance();
    final store = FocusDevicePreferencesStore(preferences);
    final dailyState = DailyOpenReminderStateStore(preferences);
    final nationalState = NationalFocusReminderStateStore(preferences);
    final timers = <_RecordedTimer>[];
    final resolvedAdapter = adapter ?? _FakeWindowsAdapter();
    await store.save(
      FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: false,
        nationalFocusReminderEnabled: nationalEnabled,
        nationalFocusReminderMinutesAfterMidnight: minuteOfDay,
        dailyOpenReminderMinutesAfterMidnight: minuteOfDay,
        dailyOpenReminderTimeChosen: true,
      ),
    );
    final service = FocusNotificationService(
      preferencesStore: store,
      dailyOpenReminderStateStore: dailyState,
      nationalFocusReminderStateStore: nationalState,
      windowsChannel: channel,
      windowsNotifications: resolvedAdapter,
      now: () => now,
      localTimeZone: () async => 'Asia/Shanghai',
      reminderTimers: (delay, callback) {
        final timer = Timer(delay, callback);
        timers.add(_RecordedTimer(delay, callback, timer));
        return timer;
      },
    );
    final statusCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          statusCalls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    return _Fixture._(
      service: service,
      store: store,
      dailyState: dailyState,
      nationalState: nationalState,
      adapter: resolvedAdapter,
      timers: timers,
      statusCalls: statusCalls,
    );
  }

  Future<void> dispose() async {
    for (final recorded in timers) {
      recorded.timer.cancel();
    }
    try {
      await service.clear();
    } catch (_) {
      // The removed test channel must not hide assertion results.
    }
    await service.dispose();
  }
}

class _RecordedTimer {
  _RecordedTimer(this.delay, this.callback, this.timer);

  final Duration delay;
  final void Function() callback;
  final Timer timer;
}

class _ScheduledEvent {
  const _ScheduledEvent({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime at;
  final String? payload;
}

/// 只记录调用：窗口侧真的把提醒写进系统通知中心才是"排程成功"。
class _FakeWindowsAdapter implements WindowsNotificationAdapter {
  _FakeWindowsAdapter({this.ready = true});

  final bool ready;
  final List<_ScheduledEvent> scheduled = [];
  final List<int> cancelled = [];
  final Set<int> pending = {};
  int initializeCalls = 0;
  bool disposed = false;

  @override
  Future<bool> initialize({
    DidReceiveNotificationResponseCallback? onResponse,
  }) async {
    initializeCalls++;
    return ready;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    scheduled.add(
      _ScheduledEvent(
        id: id,
        title: title,
        body: body,
        at: at,
        payload: payload,
      ),
    );
    pending.add(id);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pending.remove(id);
  }

  @override
  Future<List<int>> pendingIds() async => pending.toList();

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
