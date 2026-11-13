// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io' show File, FileMode, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/notifications/daily_open_reminder_plan.dart';
import 'package:pacta/src/notifications/daily_open_reminder_state.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fake_auth_repository.dart';

/// Rerunnable native fixture for the daily open-Pacta reminder.
///
///   flutter test integration_test/issue_95_daily_reminder_device_test.dart -d windows
///   flutter test integration_test/issue_95_daily_reminder_device_test.dart -d DEVICE
///
/// Optional real-arrival window (minutes of manual observation):
///
///   flutter test integration_test/issue_95_daily_reminder_device_test.dart \
///     -d DEVICE --dart-define=ISSUE95_HOLD_SECONDS=240
///
/// The fixture owns every side effect it creates:
/// - it signs in as a fixture user, so reminder keys are scoped to that user and
///   never touch the device owner's saved choices;
/// - it snapshots the whole preference store first and restores it afterwards;
/// - it cancels the reminder it scheduled before restoring.
///
/// Payload injection below only proves the in-app route. Native arrival and a
/// real notification tap must be observed by a human during the hold window;
/// the fixture prints lifecycle evidence and never claims the injection is a
/// native click.
const _fixtureUser = 'issue95-native-fixture';
const _holdSeconds = int.fromEnvironment('ISSUE95_HOLD_SECONDS');
const _leadMinutes = int.fromEnvironment(
  'ISSUE95_LEAD_MINUTES',
  defaultValue: 4,
);
const _evidenceFile = String.fromEnvironment('ISSUE95_EVIDENCE_FILE');
const _requestPermission = bool.fromEnvironment('ISSUE95_REQUEST_PERMISSION');
const _permissionOnly = bool.fromEnvironment('ISSUE95_PERMISSION_ONLY');
const _expectDenied = bool.fromEnvironment('ISSUE95_EXPECT_DENIED');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the daily reminder plans on the device clock and opens the board',
    (tester) async {
      final zone = await _deviceZoneId();
      _record(
        'ISSUE95_DEVICE_ZONE zone=$zone platform=${Platform.operatingSystem}',
      );

      // Keep fixture preferences outside the application's normal prefix, so
      // another running desktop instance cannot have its choices overwritten.
      SharedPreferences.setPrefix('pacta_issue95_acceptance.');
      final preferences = await SharedPreferences.getInstance();
      final snapshot = _PreferencesSnapshot.capture(preferences);
      final store = FocusDevicePreferencesStore(
        preferences,
        userId: _fixtureUser,
      );
      final state = DailyOpenReminderStateStore(
        preferences,
        userId: _fixtureUser,
      );
      final service = FocusNotificationService();
      final lifecycle = _LifecycleProbe();
      WidgetsBinding.instance.addObserver(lifecycle);

      addTearDown(() async {
        WidgetsBinding.instance.removeObserver(lifecycle);
        try {
          await service.setUserId(_fixtureUser);
          await store.save(
            (await store.load()).copyWith(dailyOpenReminderEnabled: false),
          );
          await service.syncDailyOpenReminder();
          await service.clear();
        } catch (error) {
          _record('ISSUE95_CLEANUP_ERROR $error');
        }
        await service.dispose();
        await snapshot.restore(preferences);
        _record('ISSUE95_PREFERENCES_RESTORED');
      });

      // A time four minutes ahead keeps the arrival inside a short run.
      final now = DateTime.now();
      expect(_leadMinutes, inInclusiveRange(1, 10));
      final targetMinutes = (now.minute + _leadMinutes) % 60;
      final targetHour = targetMinutes < now.minute
          ? (now.hour + 1) % 24
          : now.hour;
      final minuteOfDay = targetHour * 60 + targetMinutes;
      await store.save(
        FocusDevicePreferences(
          notificationsEnabled: true,
          backgroundRunningEnabled: true,
          dailyOpenReminderEnabled: true,
          dailyOpenReminderMinutesAfterMidnight: minuteOfDay,
          dailyOpenReminderTimeChosen: true,
        ),
      );

      await service.initialize();
      await service.setUserId(_fixtureUser);
      var allowed = await service.notificationsAllowed();
      if (Platform.isAndroid && _requestPermission && !allowed) {
        _record(
          'ISSUE95_PERMISSION_PROMPT respond in the Android system dialog',
        );
        allowed = await service.ensureNotificationPermissionForUse();
        _record('ISSUE95_PERMISSION_RESULT allowed=$allowed');
      }
      final exactAlarms = await service.exactAlarmsAllowed();
      _record(
        'ISSUE95_PERMISSIONS notifications=$allowed exactAlarms=$exactAlarms '
        'platform=${Platform.operatingSystem}',
      );

      if (_permissionOnly) {
        expect(allowed, !_expectDenied);
        await tester.pumpWidget(
          PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = _fixtureUser,
            focusNotificationService: service,
          ),
        );
        await _pumpFrames(tester);
        expect(find.byType(AppShell), findsOneWidget);
        expect(await service.ensureNotificationPermissionForUse(), allowed);
        await _openMyPage(tester);
        expect(find.text('提醒与通知'), findsOneWidget);
        _record('ISSUE95_PERMISSION_CORE_ACCESSIBLE repeated_prompt=false');
        return;
      }

      await service.syncDailyOpenReminder();
      final scheduled = state.loadScheduled();
      expect(scheduled, isNotNull, reason: 'The reminder must be planned.');
      final plan = DailyOpenReminderPlan.next(
        now: DateTime.now(),
        minuteOfDay: minuteOfDay,
      );
      _record(
        'ISSUE95_PLAN day=${scheduled!.dayKey} '
        'scheduledAt=${scheduled.scheduledAt.toLocal().toIso8601String()} '
        'timeZone=${scheduled.timeZoneId} '
        'nextPlan=${plan.scheduledAt.toIso8601String()}',
      );
      expect(
        scheduled.scheduledAt.isAtSameMomentAs(plan.scheduledAt) ||
            scheduled.dayKey == plan.dayKey,
        isTrue,
        reason: 'Planning must follow the device wall clock, not a fixed zone.',
      );

      if (Platform.isAndroid) {
        final plugin = FlutterLocalNotificationsPlugin();
        final pending = await plugin.pendingNotificationRequests();
        _record(
          'ISSUE95_ANDROID_PENDING ids='
          '${pending.map((request) => request.id).join(',')}',
        );
        expect(
          pending.where((request) => request.id == 2205),
          isNotEmpty,
          reason: 'Android must hold one scheduled daily reminder.',
        );
      }

      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = _fixtureUser,
          focusNotificationService: service,
        ),
      );
      await _pumpFrames(tester);
      expect(find.byType(AppShell), findsOneWidget);

      await _openMyPage(tester);
      await tester.tap(find.text('提醒与通知'));
      await _pumpFrames(tester);
      expect(find.text('每天打开 Pacta'), findsOneWidget);
      _record('ISSUE95_SETTINGS_OPENED');

      await tester.pageBack();
      await _pumpFrames(tester);

      if (_holdSeconds > 0) {
        lifecycle.arm();
        final nativeTap = Completer<void>();
        final tapSubscription = service.openFlowRequests.listen((payload) {
          if (payload == 'daily-open-reminder:${scheduled.dayKey}' &&
              !nativeTap.isCompleted) {
            nativeTap.complete();
          }
        });
        _record(
          'ISSUE95_HOLD_STARTED seconds=$_holdSeconds '
          'expectedAt=${plan.scheduledAt.toLocal().toIso8601String()} '
          'action=tap the system notification when it appears',
        );
        try {
          await tester.runAsync(
            () => nativeTap.future.timeout(Duration(seconds: _holdSeconds)),
          );
        } finally {
          await tapSubscription.cancel();
        }
        _record(
          'ISSUE95_HOLD_ENDED '
          'backgrounded=${lifecycle.backgrounded} '
          'resumedAfterBackground=${lifecycle.resumedAfterBackground} '
          'states=${lifecycle.states.join(',')}',
        );
        await _pumpFrames(tester);
        _record('ISSUE95_NATIVE_ROUTE index=${_selectedDestination(tester)}');
        expect(
          lifecycle.resumedAfterBackground,
          isTrue,
          reason: 'A native tap must return the app to the foreground.',
        );
        expect(
          _selectedDestination(tester),
          0,
          reason:
              'The real native notification, before injection, opens Board.',
        );
      }

      service.handleNotificationResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          id: 2205,
          payload: 'daily-open-reminder:${scheduled.dayKey}',
        ),
      );
      await _pumpFrames(tester);
      final destination = _selectedDestination(tester);
      _record(
        'ISSUE95_ROUTE_INJECTED index=$destination '
        'note=payload injection proves routing only, not a native tap',
      );
      expect(destination, 0, reason: 'A reminder payload opens the board.');

      await store.save(
        (await store.load()).copyWith(dailyOpenReminderEnabled: false),
      );
      await service.syncDailyOpenReminder();
      _record(
        'ISSUE95_DISABLED_CLEARED cleared=${state.loadScheduled() == null}',
      );
      expect(state.loadScheduled(), isNull);
      _record('ISSUE95_NATIVE_PASS platform=${Platform.operatingSystem}');
    },
    timeout: const Timeout(Duration(minutes: 8)),
    skip: !(Platform.isAndroid || Platform.isWindows),
  );
}

Future<String> _deviceZoneId() async {
  try {
    final zone = await FlutterTimezone.getLocalTimezone();
    return zone.identifier;
  } catch (error) {
    return 'unavailable:$error';
  }
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 30}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openMyPage(WidgetTester tester) async {
  final navigation = find.byWidgetPredicate(
    (widget) => widget is NavigationBar || widget is NavigationRail,
  );
  await tester.tap(
    find.descendant(of: navigation, matching: find.text('我的')).last,
  );
  await _pumpFrames(tester);
  await tester.scrollUntilVisible(
    find.text('提醒与通知'),
    250,
    scrollable: find
        .descendant(of: find.byType(MyPage), matching: find.byType(Scrollable))
        .first,
  );
  await _pumpFrames(tester);
}

int _selectedDestination(WidgetTester tester) {
  final bar = find.byType(NavigationBar);
  if (bar.evaluate().isNotEmpty) {
    return tester.widget<NavigationBar>(bar).selectedIndex;
  }
  return tester
          .widget<NavigationRail>(find.byType(NavigationRail))
          .selectedIndex ??
      0;
}

class _LifecycleProbe extends WidgetsBindingObserver {
  final List<AppLifecycleState> states = [];
  bool backgrounded = false;
  bool resumedAfterBackground = false;
  bool _armed = false;

  void arm() {
    _armed = true;
    backgrounded = false;
    resumedAfterBackground = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_armed) return;
    states.add(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      backgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed && backgrounded) {
      resumedAfterBackground = true;
    }
  }
}

/// Restores the whole preference store so the device owner keeps their choices.
class _PreferencesSnapshot {
  _PreferencesSnapshot._(this._values);

  final Map<String, Object?> _values;

  static _PreferencesSnapshot capture(SharedPreferences preferences) =>
      _PreferencesSnapshot._({
        for (final key in preferences.getKeys()) key: preferences.get(key),
      });

  Future<void> restore(SharedPreferences preferences) async {
    for (final key in preferences.getKeys().toList()) {
      if (!_values.containsKey(key)) await preferences.remove(key);
    }
    for (final entry in _values.entries) {
      final value = entry.value;
      if (value is bool) {
        await preferences.setBool(entry.key, value);
      } else if (value is int) {
        await preferences.setInt(entry.key, value);
      } else if (value is double) {
        await preferences.setDouble(entry.key, value);
      } else if (value is String) {
        await preferences.setString(entry.key, value);
      } else if (value is List<String>) {
        await preferences.setStringList(entry.key, value);
      }
    }
  }
}

void _record(String message) {
  print(message);
  if (_evidenceFile.isEmpty) return;
  final file = File(_evidenceFile);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${DateTime.now().toIso8601String()} $message\n',
    mode: FileMode.append,
    flush: true,
  );
}
