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
}
