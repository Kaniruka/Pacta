import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/notifications/focus_device_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'notification and background preferences persist on this device',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final store = FocusDevicePreferencesStore(preferences);

      await store.save(
        const FocusDevicePreferences(
          notificationsEnabled: true,
          backgroundRunningEnabled: false,
        ),
      );

      final restored = await FocusDevicePreferencesStore(preferences).load();

      expect(restored.notificationsEnabled, isTrue);
      expect(restored.backgroundRunningEnabled, isFalse);
    },
  );

  test(
    'National Focus reminder choice and time persist on this device',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final store = FocusDevicePreferencesStore(preferences);

      await store.save(
        const FocusDevicePreferences(
          notificationsEnabled: false,
          backgroundRunningEnabled: true,
          nationalFocusReminderEnabled: false,
          nationalFocusReminderMinutesAfterMidnight: 7 * 60 + 30,
        ),
      );

      final restored = await FocusDevicePreferencesStore(preferences).load();

      expect(restored.nationalFocusReminderEnabled, isFalse);
      expect(restored.nationalFocusReminderMinutesAfterMidnight, 7 * 60 + 30);
    },
  );

  test('notification and background preferences have safe defaults', () async {
    final preferences = await SharedPreferences.getInstance();
    final settings = await FocusDevicePreferencesStore(preferences).load();

    expect(settings.notificationsEnabled, isFalse);
    expect(settings.backgroundRunningEnabled, isTrue);
    expect(settings.nationalFocusReminderEnabled, isTrue);
    expect(settings.nationalFocusReminderMinutesAfterMidnight, 22 * 60);
  });

  test(
    'the daily Pacta reminder is off until this device turns it on',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final defaults = await FocusDevicePreferencesStore(preferences).load();

      expect(defaults.dailyOpenReminderEnabled, isFalse);
      expect(defaults.dailyOpenReminderTimeChosen, isFalse);
      expect(defaults.dailyOpenReminderMinutesAfterMidnight, 9 * 60);
    },
  );

  test('the daily Pacta reminder choice and local time persist', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = FocusDevicePreferencesStore(preferences);

    await store.save(
      const FocusDevicePreferences(
        notificationsEnabled: false,
        backgroundRunningEnabled: true,
        dailyOpenReminderEnabled: true,
        dailyOpenReminderMinutesAfterMidnight: 6 * 60 + 45,
        dailyOpenReminderTimeChosen: true,
      ),
    );

    final restored = await FocusDevicePreferencesStore(preferences).load();

    expect(restored.dailyOpenReminderEnabled, isTrue);
    expect(restored.dailyOpenReminderMinutesAfterMidnight, 6 * 60 + 45);
    expect(restored.dailyOpenReminderTimeChosen, isTrue);
  });

  test(
    'an out-of-range stored daily reminder time falls back safely',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(
        'pacta.device.daily_open_reminder_minute',
        24 * 60 + 30,
      );

      final restored = await FocusDevicePreferencesStore(preferences).load();

      expect(restored.dailyOpenReminderMinutesAfterMidnight, 9 * 60);
    },
  );

  test('reminder settings stay with the user who changed them', () async {
    final preferences = await SharedPreferences.getInstance();
    final userA = FocusDevicePreferencesStore(preferences, userId: 'user-a');
    final userB = FocusDevicePreferencesStore(preferences, userId: 'user-b');

    await userA.save(
      const FocusDevicePreferences(
        notificationsEnabled: true,
        backgroundRunningEnabled: true,
        dailyOpenReminderEnabled: true,
        dailyOpenReminderMinutesAfterMidnight: 6 * 60 + 30,
        dailyOpenReminderTimeChosen: true,
      ),
    );

    final seenByB = await userB.load();
    expect(seenByB.dailyOpenReminderEnabled, isFalse);
    expect(seenByB.notificationsEnabled, isFalse);
    expect(seenByB.dailyOpenReminderMinutesAfterMidnight, 9 * 60);

    final seenByA = await userA.load();
    expect(seenByA.dailyOpenReminderEnabled, isTrue);
    expect(seenByA.notificationsEnabled, isTrue);
    expect(seenByA.dailyOpenReminderMinutesAfterMidnight, 6 * 60 + 30);
  });

  test('pre-scoping device settings migrate to one user only', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('pacta.device.daily_open_reminder_enabled', true);
    await preferences.setInt('pacta.device.daily_open_reminder_minute', 7 * 60);
    await preferences.setBool(
      'pacta.device.notification_permission_requested',
      true,
    );
    await preferences.setString(
      'pacta.device.daily_open_reminder_scheduled_day',
      '2026-11-13',
    );

    final migrated = await FocusDevicePreferencesStore(
      preferences,
      userId: 'first-user',
    ).load();

    expect(migrated.dailyOpenReminderEnabled, isTrue);
    expect(migrated.dailyOpenReminderMinutesAfterMidnight, 7 * 60);
    expect(migrated.notificationPermissionRequested, isTrue);
    expect(
      preferences.getString('pacta.device.daily_open_reminder_scheduled_day'),
      isNull,
      reason: 'Transient delivery markers must not survive the migration.',
    );

    final laterUser = await FocusDevicePreferencesStore(
      preferences,
      userId: 'later-user',
    ).load();
    expect(laterUser.dailyOpenReminderEnabled, isFalse);
    expect(laterUser.dailyOpenReminderMinutesAfterMidnight, 9 * 60);
  });

  test('two first logins cannot both adopt the legacy settings', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('pacta.device.daily_open_reminder_enabled', true);
    await preferences.setInt('pacta.device.daily_open_reminder_minute', 6 * 60);

    final first = FocusDevicePreferencesStore(preferences, userId: 'user-a');
    final second = FocusDevicePreferencesStore(preferences, userId: 'user-b');
    await Future.wait([first.load(), second.load()]);

    final adopted = [
      (await first.load()).dailyOpenReminderEnabled,
      (await second.load()).dailyOpenReminderEnabled,
    ].where((enabled) => enabled).length;
    expect(
      adopted,
      1,
      reason: 'Exactly one account may inherit the installation settings.',
    );
    expect(
      preferences.getBool('pacta.device.daily_open_reminder_enabled'),
      isNull,
    );
  });

  test('a second migration attempt keeps the scoped values', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('pacta.device.daily_open_reminder_enabled', true);
    final store = FocusDevicePreferencesStore(preferences, userId: 'user-a');
    await store.load();
    await store.save(
      (await store.load()).copyWith(
        dailyOpenReminderMinutesAfterMidnight: 5 * 60,
      ),
    );

    expect((await store.load()).dailyOpenReminderEnabled, isTrue);
    expect((await store.load()).dailyOpenReminderMinutesAfterMidnight, 5 * 60);
  });
}
