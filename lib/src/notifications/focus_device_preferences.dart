import 'package:shared_preferences/shared_preferences.dart';

/// Notification choices belong to this installation and are never synchronized.
class FocusDevicePreferences {
  const FocusDevicePreferences({
    required this.notificationsEnabled,
    required this.backgroundRunningEnabled,
    this.nationalFocusReminderEnabled = true,
    this.nationalFocusReminderMinutesAfterMidnight = 22 * 60,
  });

  final bool notificationsEnabled;
  final bool backgroundRunningEnabled;
  final bool nationalFocusReminderEnabled;
  final int nationalFocusReminderMinutesAfterMidnight;

  FocusDevicePreferences copyWith({
    bool? notificationsEnabled,
    bool? backgroundRunningEnabled,
    bool? nationalFocusReminderEnabled,
    int? nationalFocusReminderMinutesAfterMidnight,
  }) => FocusDevicePreferences(
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    backgroundRunningEnabled:
        backgroundRunningEnabled ?? this.backgroundRunningEnabled,
    nationalFocusReminderEnabled:
        nationalFocusReminderEnabled ?? this.nationalFocusReminderEnabled,
    nationalFocusReminderMinutesAfterMidnight:
        nationalFocusReminderMinutesAfterMidnight ??
        this.nationalFocusReminderMinutesAfterMidnight,
  );
}

class FocusDevicePreferencesStore {
  FocusDevicePreferencesStore(this._preferences);

  static const _notificationsKey = 'pacta.device.focus_notifications_enabled';
  static const _backgroundKey = 'pacta.device.background_running_enabled';
  static const _nationalFocusReminderEnabledKey =
      'pacta.device.national_focus_reminder_enabled';
  static const _nationalFocusReminderMinuteKey =
      'pacta.device.national_focus_reminder_minute';
  static const defaultNationalFocusReminderMinute = 22 * 60;

  final SharedPreferences _preferences;

  Future<FocusDevicePreferences> load() async {
    final reminderMinute =
        _preferences.getInt(_nationalFocusReminderMinuteKey) ??
        defaultNationalFocusReminderMinute;
    return FocusDevicePreferences(
      notificationsEnabled: _preferences.getBool(_notificationsKey) ?? false,
      backgroundRunningEnabled: _preferences.getBool(_backgroundKey) ?? true,
      nationalFocusReminderEnabled:
          _preferences.getBool(_nationalFocusReminderEnabledKey) ?? true,
      nationalFocusReminderMinutesAfterMidnight: reminderMinute.clamp(
        0,
        24 * 60 - 1,
      ),
    );
  }

  Future<void> save(FocusDevicePreferences preferences) async {
    await _preferences.setBool(
      _notificationsKey,
      preferences.notificationsEnabled,
    );
    await _preferences.setBool(
      _backgroundKey,
      preferences.backgroundRunningEnabled,
    );
    await _preferences.setBool(
      _nationalFocusReminderEnabledKey,
      preferences.nationalFocusReminderEnabled,
    );
    await _preferences.setInt(
      _nationalFocusReminderMinuteKey,
      preferences.nationalFocusReminderMinutesAfterMidnight.clamp(
        0,
        24 * 60 - 1,
      ),
    );
  }
}
