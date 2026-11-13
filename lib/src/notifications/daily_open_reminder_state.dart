import 'package:shared_preferences/shared_preferences.dart';

import 'device_settings_scope.dart';

class DailyOpenReminderSchedule {
  const DailyOpenReminderSchedule({
    required this.dayKey,
    required this.scheduledAt,
    required this.timeZoneId,
  });

  final String dayKey;
  final DateTime scheduledAt;

  /// The device time zone identifier the occurrence was planned in. A changed
  /// identifier means the wall clock moved and the reminder must be replanned.
  final String timeZoneId;
}

/// Durable device-local delivery markers for the daily open-Pacta reminder.
class DailyOpenReminderStateStore {
  DailyOpenReminderStateStore(this._preferences, {this.userId});

  static const _lastSentDayKey = 'daily_open_reminder_last_sent_day';
  static const _scheduledDayKey = 'daily_open_reminder_scheduled_day';
  static const _scheduledAtKey = 'daily_open_reminder_scheduled_at_utc_ms';
  static const _scheduledTimeZoneKey =
      'daily_open_reminder_scheduled_time_zone';

  final SharedPreferences _preferences;

  /// Delivery markers belong to the signed-in user of this installation.
  final String? userId;

  String _key(String name) => deviceSettingsKey(userId, name);

  String? loadLastSentDayKey() => _preferences.getString(_key(_lastSentDayKey));

  DailyOpenReminderSchedule? loadScheduled() {
    final dayKey = _preferences.getString(_key(_scheduledDayKey));
    final milliseconds = _preferences.getInt(_key(_scheduledAtKey));
    final timeZoneId = _preferences.getString(_key(_scheduledTimeZoneKey));
    if (dayKey == null || milliseconds == null || timeZoneId == null) {
      return null;
    }
    return DailyOpenReminderSchedule(
      dayKey: dayKey,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ),
      timeZoneId: timeZoneId,
    );
  }

  Future<void> saveScheduled(DailyOpenReminderSchedule schedule) async {
    await _preferences.setString(_key(_scheduledDayKey), schedule.dayKey);
    await _preferences.setInt(
      _key(_scheduledAtKey),
      schedule.scheduledAt.toUtc().millisecondsSinceEpoch,
    );
    await _preferences.setString(
      _key(_scheduledTimeZoneKey),
      schedule.timeZoneId,
    );
  }

  Future<void> markSent(String dayKey) async {
    await _preferences.setString(_key(_lastSentDayKey), dayKey);
    await clearScheduled();
  }

  Future<void> clearScheduled() async {
    await _preferences.remove(_key(_scheduledDayKey));
    await _preferences.remove(_key(_scheduledAtKey));
    await _preferences.remove(_key(_scheduledTimeZoneKey));
  }
}
