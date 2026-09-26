import 'package:shared_preferences/shared_preferences.dart';

class NationalFocusReminderSchedule {
  const NationalFocusReminderSchedule({
    required this.dayKey,
    required this.scheduledAt,
    required this.repeatsDaily,
  });

  final String dayKey;
  final DateTime scheduledAt;
  final bool repeatsDaily;
}

/// Durable device-local delivery markers for National Focus reminders.
class NationalFocusReminderStateStore {
  NationalFocusReminderStateStore(this._preferences);

  static const _lastSentDayKey =
      'pacta.device.national_focus_reminder_last_sent_day';
  static const _scheduledDayKey =
      'pacta.device.national_focus_reminder_scheduled_day';
  static const _scheduledAtKey =
      'pacta.device.national_focus_reminder_scheduled_at_utc_ms';
  static const _repeatsDailyKey =
      'pacta.device.national_focus_reminder_repeats_daily';

  final SharedPreferences _preferences;

  String? loadLastSentDayKey() => _preferences.getString(_lastSentDayKey);

  NationalFocusReminderSchedule? loadScheduled() {
    final dayKey = _preferences.getString(_scheduledDayKey);
    final milliseconds = _preferences.getInt(_scheduledAtKey);
    if (dayKey == null || milliseconds == null) return null;
    return NationalFocusReminderSchedule(
      dayKey: dayKey,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ),
      repeatsDaily: _preferences.getBool(_repeatsDailyKey) ?? false,
    );
  }

  Future<void> saveScheduled(NationalFocusReminderSchedule schedule) async {
    await _preferences.setString(_scheduledDayKey, schedule.dayKey);
    await _preferences.setInt(
      _scheduledAtKey,
      schedule.scheduledAt.toUtc().millisecondsSinceEpoch,
    );
    await _preferences.setBool(_repeatsDailyKey, schedule.repeatsDaily);
  }

  Future<void> markSent(String dayKey) async {
    await _preferences.setString(_lastSentDayKey, dayKey);
    await clearScheduled();
  }

  Future<void> clearScheduled() async {
    await _preferences.remove(_scheduledDayKey);
    await _preferences.remove(_scheduledAtKey);
    await _preferences.remove(_repeatsDailyKey);
  }
}
