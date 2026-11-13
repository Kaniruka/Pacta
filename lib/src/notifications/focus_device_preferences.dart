import 'package:shared_preferences/shared_preferences.dart';

/// Notification choices belong to this installation and are never synchronized.
class FocusDevicePreferences {
  const FocusDevicePreferences({
    required this.notificationsEnabled,
    required this.backgroundRunningEnabled,
    this.nationalFocusReminderEnabled = true,
    this.nationalFocusReminderMinutesAfterMidnight = 22 * 60,
    this.dailyOpenReminderEnabled = false,
    this.dailyOpenReminderMinutesAfterMidnight = 9 * 60,
    this.dailyOpenReminderTimeChosen = false,
    this.notificationPermissionRequested = false,
  });

  final bool notificationsEnabled;
  final bool backgroundRunningEnabled;
  final bool nationalFocusReminderEnabled;
  final int nationalFocusReminderMinutesAfterMidnight;

  /// The independent daily reminder that opens Pacta on this device's clock.
  final bool dailyOpenReminderEnabled;
  final int dailyOpenReminderMinutesAfterMidnight;

  /// Whether the user already picked the daily reminder time themselves.
  final bool dailyOpenReminderTimeChosen;

  /// Whether this device already asked for the system notification permission.
  /// Android may stop showing the dialog, so a stored refusal needs the system
  /// settings entry instead of another request.
  final bool notificationPermissionRequested;

  FocusDevicePreferences copyWith({
    bool? notificationsEnabled,
    bool? backgroundRunningEnabled,
    bool? nationalFocusReminderEnabled,
    int? nationalFocusReminderMinutesAfterMidnight,
    bool? dailyOpenReminderEnabled,
    int? dailyOpenReminderMinutesAfterMidnight,
    bool? dailyOpenReminderTimeChosen,
    bool? notificationPermissionRequested,
  }) => FocusDevicePreferences(
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    backgroundRunningEnabled:
        backgroundRunningEnabled ?? this.backgroundRunningEnabled,
    nationalFocusReminderEnabled:
        nationalFocusReminderEnabled ?? this.nationalFocusReminderEnabled,
    nationalFocusReminderMinutesAfterMidnight:
        nationalFocusReminderMinutesAfterMidnight ??
        this.nationalFocusReminderMinutesAfterMidnight,
    dailyOpenReminderEnabled:
        dailyOpenReminderEnabled ?? this.dailyOpenReminderEnabled,
    dailyOpenReminderMinutesAfterMidnight:
        dailyOpenReminderMinutesAfterMidnight ??
        this.dailyOpenReminderMinutesAfterMidnight,
    dailyOpenReminderTimeChosen:
        dailyOpenReminderTimeChosen ?? this.dailyOpenReminderTimeChosen,
    notificationPermissionRequested:
        notificationPermissionRequested ?? this.notificationPermissionRequested,
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
  static const _dailyOpenReminderEnabledKey =
      'pacta.device.daily_open_reminder_enabled';
  static const _dailyOpenReminderMinuteKey =
      'pacta.device.daily_open_reminder_minute';
  static const _dailyOpenReminderTimeChosenKey =
      'pacta.device.daily_open_reminder_time_chosen';
  static const _notificationPermissionRequestedKey =
      'pacta.device.notification_permission_requested';
  static const defaultNationalFocusReminderMinute = 22 * 60;
  static const defaultDailyOpenReminderMinute = 9 * 60;

  final SharedPreferences _preferences;

  Future<FocusDevicePreferences> load() async {
    final reminderMinute =
        _preferences.getInt(_nationalFocusReminderMinuteKey) ??
        defaultNationalFocusReminderMinute;
    final dailyOpenReminderMinute = _validMinute(
      _preferences.getInt(_dailyOpenReminderMinuteKey),
    );
    return FocusDevicePreferences(
      notificationsEnabled: _preferences.getBool(_notificationsKey) ?? false,
      backgroundRunningEnabled: _preferences.getBool(_backgroundKey) ?? true,
      nationalFocusReminderEnabled:
          _preferences.getBool(_nationalFocusReminderEnabledKey) ?? true,
      nationalFocusReminderMinutesAfterMidnight: reminderMinute.clamp(
        0,
        24 * 60 - 1,
      ),
      dailyOpenReminderEnabled:
          _preferences.getBool(_dailyOpenReminderEnabledKey) ?? false,
      dailyOpenReminderMinutesAfterMidnight: dailyOpenReminderMinute,
      dailyOpenReminderTimeChosen:
          _preferences.getBool(_dailyOpenReminderTimeChosenKey) ?? false,
      notificationPermissionRequested:
          _preferences.getBool(_notificationPermissionRequestedKey) ?? false,
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
    await _preferences.setBool(
      _dailyOpenReminderEnabledKey,
      preferences.dailyOpenReminderEnabled,
    );
    await _preferences.setInt(
      _dailyOpenReminderMinuteKey,
      _validMinute(preferences.dailyOpenReminderMinutesAfterMidnight),
    );
    await _preferences.setBool(
      _dailyOpenReminderTimeChosenKey,
      preferences.dailyOpenReminderTimeChosen,
    );
    await _preferences.setBool(
      _notificationPermissionRequestedKey,
      preferences.notificationPermissionRequested,
    );
  }

  /// An unreadable stored time falls back to the documented default instead of
  /// silently moving the reminder to an unexpected hour.
  int _validMinute(int? value) {
    if (value == null || value < 0 || value >= 24 * 60) {
      return defaultDailyOpenReminderMinute;
    }
    return value;
  }
}
