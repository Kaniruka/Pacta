import 'package:shared_preferences/shared_preferences.dart';

/// Device-local settings belong to the signed-in user on this installation.
///
/// Keys are scoped per user so switching accounts never inherits another
/// person's reminder choices, while signed-out reads keep the legacy layout for
/// tests and first-run defaults.
String deviceSettingsKey(String? userId, String name) =>
    userId == null ? 'pacta.device.$name' : 'pacta.device.u.$userId.$name';

/// One-time migration of the pre-scoping device keys.
///
/// The first signed-in user after the upgrade adopts the settings that used to
/// be installation-wide, then the legacy keys are removed. Later users on the
/// same installation start from the documented defaults instead of inheriting
/// somebody else's reminders.
const _legacySettingKeys = <String>[
  'pacta.device.focus_notifications_enabled',
  'pacta.device.background_running_enabled',
  'pacta.device.national_focus_reminder_enabled',
  'pacta.device.national_focus_reminder_minute',
  'pacta.device.daily_open_reminder_enabled',
  'pacta.device.daily_open_reminder_minute',
  'pacta.device.daily_open_reminder_time_chosen',
  'pacta.device.notification_permission_requested',
];

/// Delivery markers are transient per-user state, so they are dropped instead
/// of being adopted by one account.
const _legacyStateKeys = <String>[
  'pacta.device.national_focus_reminder_last_sent_day',
  'pacta.device.national_focus_reminder_scheduled_day',
  'pacta.device.national_focus_reminder_scheduled_at_utc_ms',
  'pacta.device.national_focus_reminder_repeats_daily',
  'pacta.device.daily_open_reminder_last_sent_day',
  'pacta.device.daily_open_reminder_scheduled_day',
  'pacta.device.daily_open_reminder_scheduled_at_utc_ms',
  'pacta.device.daily_open_reminder_scheduled_time_zone',
];

const _migratedFlagKey = 'pacta.device.user_scoped_migrated_v1';

Future<void> migrateLegacyDeviceSettings(
  SharedPreferences preferences,
  String userId,
) async {
  if (preferences.getBool(_migratedFlagKey) == true) return;
  for (final legacy in _legacySettingKeys) {
    final scoped = deviceSettingsKey(
      userId,
      legacy.substring('pacta.device.'.length),
    );
    final value = preferences.get(legacy);
    if (value != null && !preferences.containsKey(scoped)) {
      await _write(preferences, scoped, value);
    }
  }
  for (final legacy in [..._legacySettingKeys, ..._legacyStateKeys]) {
    await preferences.remove(legacy);
  }
  await preferences.setBool(_migratedFlagKey, true);
}

Future<void> _write(
  SharedPreferences preferences,
  String key,
  Object value,
) async {
  if (value is bool) {
    await preferences.setBool(key, value);
  } else if (value is int) {
    await preferences.setInt(key, value);
  } else if (value is double) {
    await preferences.setDouble(key, value);
  } else if (value is String) {
    await preferences.setString(key, value);
  } else if (value is List<String>) {
    await preferences.setStringList(key, value);
  }
}
