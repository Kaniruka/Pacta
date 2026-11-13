import 'package:shared_preferences/shared_preferences.dart';

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
  DailyOpenReminderStateStore(this._preferences);

  static const _lastSentDayKey =
      'pacta.device.daily_open_reminder_last_sent_day';
  static const _scheduledDayKey =
      'pacta.device.daily_open_reminder_scheduled_day';
  static const _scheduledAtKey =
      'pacta.device.daily_open_reminder_scheduled_at_utc_ms';
  static const _scheduledTimeZoneKey =
      'pacta.device.daily_open_reminder_scheduled_time_zone';

  final SharedPreferences _preferences;

  String? loadLastSentDayKey() => _preferences.getString(_lastSentDayKey);

  DailyOpenReminderSchedule? loadScheduled() {
    final dayKey = _preferences.getString(_scheduledDayKey);
    final milliseconds = _preferences.getInt(_scheduledAtKey);
    final timeZoneId = _preferences.getString(_scheduledTimeZoneKey);
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
    await _preferences.setString(_scheduledDayKey, schedule.dayKey);
    await _preferences.setInt(
      _scheduledAtKey,
      schedule.scheduledAt.toUtc().millisecondsSinceEpoch,
    );
    await _preferences.setString(_scheduledTimeZoneKey, schedule.timeZoneId);
  }

  Future<void> markSent(String dayKey) async {
    await _preferences.setString(_lastSentDayKey, dayKey);
    await clearScheduled();
  }

  Future<void> clearScheduled() async {
    await _preferences.remove(_scheduledDayKey);
    await _preferences.remove(_scheduledAtKey);
    await _preferences.remove(_scheduledTimeZoneKey);
  }
}
