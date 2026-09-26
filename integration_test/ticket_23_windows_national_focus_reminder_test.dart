import 'package:drift/native.dart';
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

const _preferenceKeys = [
  'pacta.device.focus_notifications_enabled',
  'pacta.device.background_running_enabled',
  'pacta.device.national_focus_reminder_enabled',
  'pacta.device.national_focus_reminder_minute',
  'pacta.device.national_focus_reminder_last_sent_day',
  'pacta.device.national_focus_reminder_scheduled_day',
  'pacta.device.national_focus_reminder_scheduled_at_utc_ms',
  'pacta.device.national_focus_reminder_repeats_daily',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T23 Windows tray reminder covers the full focus flow', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final previousValues = <String, Object?>{
      for (final key in _preferenceKeys) key: preferences.get(key),
    };
    final preferencesStore = FocusDevicePreferencesStore(preferences);
    final oldPreferences = await preferencesStore.load();
    var now = DateTime.utc(2037, 1, 2, 14);
    var repositoryNow = DateTime.utc(2037, 1, 1, 19, 59);
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalNationalFocusRepository(
      database: database,
      userId: 'ticket-23-windows-user',
      now: () => repositoryNow,
    );
    final card = await repository.createCard(
      const NationalFocusCardDraft(
        triggerCondition: 'Ticket-23 Windows acceptance',
        action: '确认待办国策',
      ),
    );
    await repository.placeCard(cardId: card.id, parentId: null);
    await repository.lightCard(card.id);
    repositoryNow = DateTime.utc(2037, 1, 1, 20);
    await repository.settleDueCheckpoints();
    expect(await _hasPendingConfirmations(repository), isTrue);
    final service = FocusNotificationService(
      preferencesStore: preferencesStore,
      now: () => now,
    );
    final stateStore = NationalFocusReminderStateStore(preferences);

    try {
      await service.initialize();
      await service.updatePreferences(
        oldPreferences.copyWith(
          notificationsEnabled: true,
          backgroundRunningEnabled: true,
          nationalFocusReminderEnabled: true,
          nationalFocusReminderMinutesAfterMidnight: 22 * 60,
        ),
      );
      await service.syncNationalFocusReminder(
        hasPendingConfirmations: await _hasPendingConfirmations(repository),
      );
      expect(stateStore.loadLastSentDayKey(), '2037-01-02');

      repositoryNow = DateTime.utc(2037, 1, 2, 14);
      expect(await repository.confirmToday(), 1);
      repositoryNow = DateTime.utc(2037, 1, 2, 20);
      await repository.settleDueCheckpoints();
      expect(await _hasPendingConfirmations(repository), isTrue);

      now = DateTime.utc(2037, 1, 3, 13, 59);
      await service.syncNationalFocusReminder(
        hasPendingConfirmations: await _hasPendingConfirmations(repository),
      );
      final preparationEndsAt = DateTime.utc(2037, 1, 3, 14);
      await service.sync(
        appointment: _appointment(preparationEndsAt),
        taskTitle: 'T23 Windows preparation',
      );
      final focusEndsAt = DateTime.utc(2037, 1, 3, 14, 30);
      await service.sync(
        session: _session(
          endsAt: focusEndsAt,
          status: FocusSessionStatus.active,
        ),
        taskTitle: 'T23 Windows focus',
      );
      expect(
        stateStore.loadScheduled()?.scheduledAt,
        DateTime.utc(2037, 1, 3, 14, 30),
      );

      await service.sync(
        session: _session(
          endsAt: focusEndsAt,
          status: FocusSessionStatus.paused,
          pausedAt: DateTime.utc(2037, 1, 3, 14, 5),
        ),
        taskTitle: 'T23 Windows paused focus',
      );
      expect(stateStore.loadScheduled(), isNull);

      final continuedEndsAt = DateTime.utc(2037, 1, 3, 14, 45);
      await service.sync(
        session: _session(
          endsAt: continuedEndsAt,
          status: FocusSessionStatus.active,
        ),
        taskTitle: 'T23 Windows continued focus',
      );
      expect(stateStore.loadScheduled()?.scheduledAt, continuedEndsAt);

      now = DateTime.utc(2037, 1, 3, 14, 46);
      await service.sync(taskTitle: 'T23 Windows completed focus');
      expect(stateStore.loadLastSentDayKey(), '2037-01-03');
      repositoryNow = now;
      expect(await repository.confirmToday(), 1);
      await service.syncNationalFocusReminder(
        hasPendingConfirmations: await _hasPendingConfirmations(repository),
      );
      expect(stateStore.loadScheduled(), isNull);

      repositoryNow = DateTime.utc(2037, 1, 3, 20);
      await repository.settleDueCheckpoints();
      expect(await _hasPendingConfirmations(repository), isTrue);
      now = DateTime.utc(2037, 1, 4, 13, 59);
      await service.syncNationalFocusReminder(
        hasPendingConfirmations: await _hasPendingConfirmations(repository),
      );
      expect(stateStore.loadScheduled(), isNotNull);
      await service.updatePreferences(
        (await preferencesStore.load()).copyWith(
          nationalFocusReminderEnabled: false,
        ),
      );
      expect(stateStore.loadScheduled(), isNull);

      await service.updatePreferences(
        (await preferencesStore.load()).copyWith(
          nationalFocusReminderEnabled: true,
        ),
      );
      await service.syncNationalFocusReminder(
        hasPendingConfirmations: await _hasPendingConfirmations(repository),
      );
      expect(stateStore.loadScheduled(), isNotNull);
      now = DateTime.utc(2037, 1, 4, 14);
      await service.syncNationalFocusReminder(
        hasPendingConfirmations: await _hasPendingConfirmations(repository),
      );
      expect(stateStore.loadLastSentDayKey(), '2037-01-04');
      repositoryNow = now;
      expect(await repository.confirmToday(), 1);
      await service.syncNationalFocusReminder(
        hasPendingConfirmations: await _hasPendingConfirmations(repository),
      );
      expect(stateStore.loadScheduled(), isNull);
    } finally {
      await service.clear();
      await service.dispose();
      await repository.dispose();
      await database.close();
      await _restorePreferences(preferences, previousValues);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<bool> _hasPendingConfirmations(
  NationalFocusRepository repository,
) async => (await repository.getTreeCards()).any(
  (card) => card.state == NationalFocusCardState.pendingTodayConfirmation,
);

AppointmentPreparation _appointment(DateTime endsAt) => AppointmentPreparation(
  id: 'ticket-23-windows-appointment',
  taskId: 'ticket-23-windows-task',
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
  id: 'ticket-23-windows-session',
  taskId: 'ticket-23-windows-task',
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
