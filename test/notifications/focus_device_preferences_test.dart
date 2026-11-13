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
}
