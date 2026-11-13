import 'package:shared_preferences/shared_preferences.dart';

/// Device-local settings belong to the signed-in user on this installation.
///
/// Keys are scoped per user so switching accounts never inherits another
/// person's reminder choices, while signed-out reads keep the legacy layout for
/// tests and first-run defaults.
String deviceSettingsKey(String? userId, String name) =>
    userId == null ? 'pacta.device.$name' : 'pacta.device.u.$userId.$name';

/// Settings that existed before keys were scoped and may be adopted once.
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

Future<void>? _migrationInFlight;

/// Migrates the installation-wide keys to [userId] exactly once.
///
/// Legacy keys are removed only after every adoption was written **and** read
/// back, and the completion marker is written last. A failed write therefore
/// leaves the legacy values intact for a later attempt instead of losing the
/// user's settings. Concurrent callers share a single attempt, so two accounts
/// cannot both adopt the same legacy values.
Future<void> migrateLegacyDeviceSettings(
  SharedPreferences preferences,
  String userId,
) {
  final inFlight = _migrationInFlight;
  if (inFlight != null) return inFlight;
  final work = _runMigration(preferences, userId);
  _migrationInFlight = work;
  return work.whenComplete(() {
    if (identical(_migrationInFlight, work)) _migrationInFlight = null;
  });
}

Future<void> _runMigration(SharedPreferences preferences, String userId) async {
  if (preferences.getBool(_migratedFlagKey) == true) return;
  for (final legacy in _legacySettingKeys) {
    final scoped = deviceSettingsKey(
      userId,
      legacy.substring('pacta.device.'.length),
    );
    final value = preferences.get(legacy);
    if (value == null || preferences.containsKey(scoped)) continue;
    if (!await _write(preferences, scoped, value)) return;
    // A store can reject or drop a write; never delete the legacy value unless
    // the scoped copy is actually readable again.
    if (preferences.get(scoped) != value) return;
  }
  for (final legacy in _legacySettingKeys) {
    await preferences.remove(legacy);
  }
  for (final legacy in _legacyStateKeys) {
    await preferences.remove(legacy);
  }
  await preferences.setBool(_migratedFlagKey, true);
}

Future<bool> _write(
  SharedPreferences preferences,
  String key,
  Object value,
) async {
  if (value is bool) return preferences.setBool(key, value);
  if (value is int) return preferences.setInt(key, value);
  if (value is double) return preferences.setDouble(key, value);
  if (value is String) return preferences.setString(key, value);
  if (value is List<String>) return preferences.setStringList(key, value);
  return false;
}
