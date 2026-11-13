import 'package:shared_preferences/shared_preferences.dart';

import 'device_settings_scope.dart';

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
  NationalFocusReminderStateStore(this._preferences, {this.userId});

  static const _lastSentDayKey = 'national_focus_reminder_last_sent_day';
  static const _scheduledDayKey = 'national_focus_reminder_scheduled_day';
  static const _scheduledAtKey = 'national_focus_reminder_scheduled_at_utc_ms';
  static const _repeatsDailyKey = 'national_focus_reminder_repeats_daily';

  final SharedPreferences _preferences;

  /// Delivery markers belong to the signed-in user of this installation.
  final String? userId;

  String _key(String name) => deviceSettingsKey(userId, name);

  String? loadLastSentDayKey() => _preferences.getString(_key(_lastSentDayKey));

  NationalFocusReminderSchedule? loadScheduled() {
    final dayKey = _preferences.getString(_key(_scheduledDayKey));
    final milliseconds = _preferences.getInt(_key(_scheduledAtKey));
    if (dayKey == null || milliseconds == null) return null;
    return NationalFocusReminderSchedule(
      dayKey: dayKey,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(
        milliseconds,
        isUtc: true,
      ),
      repeatsDaily: _preferences.getBool(_key(_repeatsDailyKey)) ?? false,
    );
  }

  Future<void> saveScheduled(NationalFocusReminderSchedule schedule) async {
    await _preferences.setString(_key(_scheduledDayKey), schedule.dayKey);
    await _preferences.setInt(
      _key(_scheduledAtKey),
      schedule.scheduledAt.toUtc().millisecondsSinceEpoch,
    );
    await _preferences.setBool(_key(_repeatsDailyKey), schedule.repeatsDaily);
  }

  Future<void> markSent(String dayKey) async {
    await _preferences.setString(_key(_lastSentDayKey), dayKey);
    await clearScheduled();
  }

  Future<void> clearScheduled() async {
    await _preferences.remove(_key(_scheduledDayKey));
    await _preferences.remove(_key(_scheduledAtKey));
    await _preferences.remove(_key(_repeatsDailyKey));
  }
}
