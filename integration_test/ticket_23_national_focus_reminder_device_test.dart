import 'dart:io' show Platform;

import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _reminderId = 2204;
const _userId = 'ticket-23-android-device-user';
const _preferenceKeys = [
  'pacta.device.national_focus_reminder_enabled',
  'pacta.device.national_focus_reminder_minute',
  'pacta.device.national_focus_reminder_last_sent_day',
  'pacta.device.national_focus_reminder_scheduled_day',
  'pacta.device.national_focus_reminder_scheduled_at_utc_ms',
  'pacta.device.national_focus_reminder_repeats_daily',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T23 Android reminder delivery and denied-permission behavior', (
    tester,
  ) async {
    final database = PactaDatabase(NativeDatabase.memory());
    var nationalFocusNow = DateTime.utc(2026, 9, 26, 19, 59);
    final nationalFocus = LocalNationalFocusRepository(
      database: database,
      userId: _userId,
      remote: InMemoryNationalFocusRemoteDataSource(),
      now: () => nationalFocusNow,
    );
    final preferences = await SharedPreferences.getInstance();
    final previousValues = <String, Object?>{
      for (final key in _preferenceKeys) key: preferences.get(key),
    };
    final preferencesStore = FocusDevicePreferencesStore(preferences);
    final oldPreferences = await preferencesStore.load();
    final notifications = FlutterLocalNotificationsPlugin();
    final service = FocusNotificationService(
      preferencesStore: preferencesStore,
      androidNotifications: notifications,
      now: () => DateTime.utc(2037, 1, 2, 12),
    );

    try {
      await service.initialize();
      final beforeActive = await notifications.getActiveNotifications();
      final beforePending = await notifications.pendingNotificationRequests();
      expect(
        beforeActive.any((notification) => notification.id == _reminderId),
        isFalse,
        reason: 'The device must not have an existing T23 reminder to replace.',
      );
      expect(
        beforePending.any((notification) => notification.id == _reminderId),
        isFalse,
        reason: 'The device must not have an existing T23 alarm to replace.',
      );

      final card = await nationalFocus.createCard(
        const NationalFocusCardDraft(
          triggerCondition: '开始工作前',
          action: '写下第一步',
        ),
      );
      await nationalFocus.placeCard(cardId: card.id, parentId: null);
      await nationalFocus.lightCard(card.id);
      nationalFocusNow = DateTime.utc(2026, 9, 26, 20);
      await nationalFocus.settleDueCheckpoints();
      expect(
        (await nationalFocus.getTreeCards()).single.state,
        NationalFocusCardState.pendingTodayConfirmation,
      );

      await preferencesStore.save(
        oldPreferences.copyWith(
          nationalFocusReminderEnabled: true,
          nationalFocusReminderMinutesAfterMidnight: 0,
        ),
      );
      await preferences.remove(
        'pacta.device.national_focus_reminder_last_sent_day',
      );

      final permissionAllowed = await service.notificationsAllowed();
      await service.syncNationalFocusReminder(hasPendingConfirmations: true);

      if (permissionAllowed) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        var active = await notifications.getActiveNotifications();
        expect(
          active.where((notification) => notification.id == _reminderId),
          hasLength(1),
          reason: 'An allowed Android device must display the due reminder.',
        );
        await service.syncNationalFocusReminder(hasPendingConfirmations: true);
        active = await notifications.getActiveNotifications();
        expect(
          active.where((notification) => notification.id == _reminderId),
          hasLength(1),
          reason: 'Repeated reconciliation must not duplicate the reminder.',
        );
        expect(
          (await notifications.pendingNotificationRequests()).where(
            (notification) => notification.id == _reminderId,
          ),
          hasLength(1),
          reason: 'Only one next-day reminder alarm should remain scheduled.',
        );
        expect(
          preferences.getString(
            'pacta.device.national_focus_reminder_last_sent_day',
          ),
          '2037-01-02',
        );
      } else {
        expect(
          (await notifications.getActiveNotifications()).any(
            (notification) => notification.id == _reminderId,
          ),
          isFalse,
        );
        expect(
          (await notifications.pendingNotificationRequests()).any(
            (notification) => notification.id == _reminderId,
          ),
          isFalse,
        );
        await nationalFocus.confirmToday();
        expect(
          (await nationalFocus.getTreeCards()).single.state,
          isNot(NationalFocusCardState.pendingTodayConfirmation),
          reason: 'Denied notifications must not block normal confirmation.',
        );
      }
    } finally {
      await notifications.cancel(id: _reminderId);
      await service.dispose();
      await _restorePreferences(preferences, previousValues);
      await nationalFocus.dispose();
      await database.close();
    }
  }, skip: !Platform.isAndroid);
}

Future<void> _restorePreferences(
  SharedPreferences preferences,
  Map<String, Object?> previousValues,
) async {
  for (final entry in previousValues.entries) {
    final value = entry.value;
    if (value == null) {
      await preferences.remove(entry.key);
    } else if (value is bool) {
      await preferences.setBool(entry.key, value);
    } else if (value is int) {
      await preferences.setInt(entry.key, value);
    } else if (value is String) {
      await preferences.setString(entry.key, value);
    }
  }
}
