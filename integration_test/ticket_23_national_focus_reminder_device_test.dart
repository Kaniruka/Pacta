import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:drift/native.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/national_focus_reminder_state.dart';
import 'package:pacta/src/tasks/task_database.dart' hide FocusSession;
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
      now: () => DateTime.utc(2037, 1, 2, 14),
    );
    FocusNotificationService? flowServiceForCleanup;

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
          nationalFocusReminderMinutesAfterMidnight: 22 * 60,
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

        // Simulate the next Beijing 22:00 while exercising the actual Android
        // notification plugin and durable schedule state.
        var reminderNow = DateTime.utc(2037, 1, 3, 13, 59);
        final flowService = FocusNotificationService(
          preferencesStore: preferencesStore,
          androidNotifications: notifications,
          now: () => reminderNow,
        );
        flowServiceForCleanup = flowService;
        await flowService.initialize();
        await flowService.syncNationalFocusReminder(
          hasPendingConfirmations: true,
        );
        final appointmentEndsAt = DateTime.utc(2037, 1, 3, 14);
        await flowService.sync(
          appointment: _appointment(appointmentEndsAt),
          taskTitle: 'T23 appointment',
        );
        final activeSessionEndsAt = appointmentEndsAt.add(
          const Duration(minutes: 30),
        );
        await flowService.sync(
          session: _session(
            endsAt: activeSessionEndsAt,
            status: FocusSessionStatus.active,
          ),
          taskTitle: 'T23 active focus',
        );
        final reminderState = NationalFocusReminderStateStore(preferences);
        final scheduled = reminderState.loadScheduled();
        expect(scheduled, isNotNull);
        expect(scheduled!.scheduledAt, DateTime.utc(2037, 1, 3, 14, 30));

        await flowService.sync(
          session: _session(
            endsAt: activeSessionEndsAt,
            status: FocusSessionStatus.paused,
            pausedAt: DateTime.utc(2037, 1, 3, 14, 5),
          ),
          taskTitle: 'T23 paused focus',
        );
        expect(
          (await notifications.pendingNotificationRequests()).where(
            (notification) => notification.id == _reminderId,
          ),
          isEmpty,
          reason: 'Pausing an active focus flow must hold the reminder.',
        );

        final continuedEndsAt = DateTime.utc(2037, 1, 3, 14, 45);
        await flowService.sync(
          session: _session(
            endsAt: continuedEndsAt,
            status: FocusSessionStatus.active,
          ),
          taskTitle: 'T23 continued focus',
        );
        reminderNow = DateTime.utc(2037, 1, 3, 14, 46);
        await flowService.sync(taskTitle: 'T23 completed focus');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        final activeAfterCompletion = await notifications
            .getActiveNotifications();
        if (!activeAfterCompletion.any(
          (notification) => notification.id == _reminderId,
        )) {
          final pendingAfterCompletion = await notifications
              .pendingNotificationRequests();
          debugPrint(
            'T23 completion diagnostics: '
            'lastSent=${reminderState.loadLastSentDayKey()} '
            'scheduled=${reminderState.loadScheduled()?.scheduledAt} '
            'activeIds=${activeAfterCompletion.map((item) => item.id).toList()} '
            'pendingIds=${pendingAfterCompletion.map((item) => item.id).toList()} '
            'allowed=${await flowService.notificationsAllowed()}',
          );
        }
        expect(
          activeAfterCompletion.where(
            (notification) => notification.id == _reminderId,
          ),
          hasLength(1),
          reason: 'Completion releases one reminder when confirmation remains.',
        );
        expect(
          preferences.getString(
            'pacta.device.national_focus_reminder_last_sent_day',
          ),
          '2037-01-03',
        );

        reminderNow = DateTime.utc(2037, 1, 4, 13, 59);
        await flowService.syncNationalFocusReminder(
          hasPendingConfirmations: true,
        );
        await preferencesStore.save(
          (await preferencesStore.load()).copyWith(
            nationalFocusReminderEnabled: false,
          ),
        );
        await flowService.updatePreferences(await preferencesStore.load());
        expect(
          (await notifications.pendingNotificationRequests()).where(
            (notification) => notification.id == _reminderId,
          ),
          isEmpty,
          reason: 'Disabling the reminder must cancel its Android alarm.',
        );

        await preferencesStore.save(
          (await preferencesStore.load()).copyWith(
            nationalFocusReminderEnabled: true,
          ),
        );
        await nationalFocus.confirmToday();
        final confirmedCards = await nationalFocus.getTreeCards();
        await flowService.syncNationalFocusReminder(
          hasPendingConfirmations: confirmedCards.any(
            (card) =>
                card.state == NationalFocusCardState.pendingTodayConfirmation,
          ),
        );
        expect(
          (await notifications.pendingNotificationRequests()).where(
            (notification) => notification.id == _reminderId,
          ),
          isEmpty,
          reason: 'Clearing all confirmations must cancel the next alarm.',
        );
        expect(
          (await notifications.getActiveNotifications()).where(
            (notification) => notification.id == _reminderId,
          ),
          isEmpty,
          reason: 'Clearing all confirmations must dismiss an active reminder.',
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
      await flowServiceForCleanup?.dispose();
      await service.dispose();
      await _restorePreferences(preferences, previousValues);
      await nationalFocus.dispose();
      await database.close();
    }
  }, skip: !Platform.isAndroid);
}

AppointmentPreparation _appointment(DateTime endsAt) => AppointmentPreparation(
  id: 'ticket-23-appointment',
  taskId: 'ticket-23-task',
  mode: FocusChainMode.regular,
  durationSeconds: 30 * 60,
  startedAt: endsAt.subtract(const Duration(minutes: 15)),
  endsAt: endsAt,
  status: AppointmentPreparationStatus.active,
  settledAt: null,
  updatedAt: endsAt.subtract(const Duration(minutes: 15)),
);

FocusSession _session({
  required DateTime endsAt,
  required FocusSessionStatus status,
  DateTime? pausedAt,
}) => FocusSession(
  id: 'ticket-23-session',
  taskId: 'ticket-23-task',
  mode: FocusChainMode.regular,
  durationSeconds: 30 * 60,
  startedAt: endsAt.subtract(const Duration(minutes: 30)),
  endsAt: endsAt,
  status: status,
  completedAt: null,
  effectiveSeconds: 0,
  pausedAt: pausedAt,
);

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
