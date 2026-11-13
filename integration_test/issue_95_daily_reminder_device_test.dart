// ignore_for_file: avoid_print

import 'dart:io' show Platform;

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
/// Run on Windows and Android; every observable fact is printed with an
/// ISSUE95_ prefix so the same run can be attached as evidence:
///
///   flutter test integration_test/issue_95_daily_reminder_device_test.dart -d windows
///   flutter test integration_test/issue_95_daily_reminder_device_test.dart -d DEVICE
///
/// The fixture never writes business data. It only touches this device's
/// reminder preferences, which are device-local by product definition.
const _userId = 'issue95-native-fixture';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the daily reminder plans on the device clock and opens the board',
    (tester) async {
      final zone = await _deviceZoneId();
      print(
        'ISSUE95_DEVICE_ZONE zone=$zone platform=${Platform.operatingSystem}',
      );

      final preferences = await SharedPreferences.getInstance();
      final store = FocusDevicePreferencesStore(preferences);
      // A time four minutes ahead keeps the arrival inside a short run.
      final now = DateTime.now();
      final targetMinutes = (now.minute + 4) % 60;
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

      final service = FocusNotificationService(now: () => DateTime.now());
      addTearDown(service.dispose);
      await service.initialize();
      final allowed = await service.notificationsAllowed();
      final exactAlarms = await service.exactAlarmsAllowed();
      print(
        'ISSUE95_PERMISSIONS notifications=$allowed '
        'exactAlarms=$exactAlarms platform=${Platform.operatingSystem}',
      );

      await service.syncDailyOpenReminder();
      final scheduled = DailyOpenReminderStateStore(preferences)
          .loadScheduled();
      expect(scheduled, isNotNull, reason: 'The reminder must be planned.');
      final plan = DailyOpenReminderPlan.next(
        now: DateTime.now(),
        minuteOfDay: minuteOfDay,
      );
      print(
        'ISSUE95_PLAN day=${scheduled!.dayKey} '
        'scheduledAt=${scheduled.scheduledAt.toLocal().toIso8601String()} '
        'timeZone=${scheduled.timeZoneId} nextPlan=${plan.scheduledAt.toIso8601String()}',
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
        final reminder = pending
            .where((request) => request.id == 2205)
            .toList();
        print(
          'ISSUE95_ANDROID_PENDING count=${reminder.length} '
          'ids=${pending.map((request) => request.id).join(',')}',
        );
        expect(
          reminder,
          isNotEmpty,
          reason: 'Android must hold one scheduled daily reminder.',
        );
      }

      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = _userId,
          focusNotificationService: service,
        ),
      );
      await _pumpFrames(tester);
      expect(find.byType(AppShell), findsOneWidget);

      await _openMyPage(tester);
      await tester.tap(find.text('提醒与通知'));
      await _pumpFrames(tester);
      expect(find.text('每天打开 Pacta'), findsOneWidget);
      print('ISSUE95_SETTINGS_OPENED');

      await tester.pageBack();
      await _pumpFrames(tester);

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
      print('ISSUE95_TAP_DESTINATION index=$destination');
      expect(destination, 0, reason: 'A reminder tap opens the board.');

      await store.save(
        (await store.load()).copyWith(dailyOpenReminderEnabled: false),
      );
      await service.syncDailyOpenReminder();
      final cleared =
          DailyOpenReminderStateStore(preferences).loadScheduled() == null;
      print('ISSUE95_DISABLED_CLEARED cleared=$cleared');
      expect(cleared, isTrue);
      print('ISSUE95_NATIVE_PASS platform=${Platform.operatingSystem}');
    },
    timeout: const Timeout(Duration(minutes: 6)),
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
