import 'package:shared_preferences/shared_preferences.dart';

import 'device_settings_scope.dart';

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
  FocusDevicePreferencesStore(this._preferences, {this.userId});

  static const _notificationsKey = 'focus_notifications_enabled';
  static const _backgroundKey = 'background_running_enabled';
  static const _nationalFocusReminderEnabledKey =
      'national_focus_reminder_enabled';
  static const _nationalFocusReminderMinuteKey =
      'national_focus_reminder_minute';
  static const _dailyOpenReminderEnabledKey = 'daily_open_reminder_enabled';
  static const _dailyOpenReminderMinuteKey = 'daily_open_reminder_minute';
  static const _dailyOpenReminderTimeChosenKey =
      'daily_open_reminder_time_chosen';
  static const _notificationPermissionRequestedKey =
      'notification_permission_requested';
  static const defaultNationalFocusReminderMinute = 22 * 60;
  static const defaultDailyOpenReminderMinute = 9 * 60;

  final SharedPreferences _preferences;

  /// The signed-in user this installation's settings belong to.
  final String? userId;

  String _key(String name) => deviceSettingsKey(userId, name);

  Future<FocusDevicePreferences> load() async {
    final scopedUserId = userId;
    if (scopedUserId != null) {
      await migrateLegacyDeviceSettings(_preferences, scopedUserId);
    }
    final reminderMinute =
        _preferences.getInt(_key(_nationalFocusReminderMinuteKey)) ??
        defaultNationalFocusReminderMinute;
    final dailyOpenReminderMinute = _validMinute(
      _preferences.getInt(_key(_dailyOpenReminderMinuteKey)),
    );
    return FocusDevicePreferences(
      notificationsEnabled:
          _preferences.getBool(_key(_notificationsKey)) ?? false,
      backgroundRunningEnabled:
          _preferences.getBool(_key(_backgroundKey)) ?? true,
      nationalFocusReminderEnabled:
          _preferences.getBool(_key(_nationalFocusReminderEnabledKey)) ?? true,
      nationalFocusReminderMinutesAfterMidnight: reminderMinute.clamp(
        0,
        24 * 60 - 1,
      ),
      dailyOpenReminderEnabled:
          _preferences.getBool(_key(_dailyOpenReminderEnabledKey)) ?? false,
      dailyOpenReminderMinutesAfterMidnight: dailyOpenReminderMinute,
      dailyOpenReminderTimeChosen:
          _preferences.getBool(_key(_dailyOpenReminderTimeChosenKey)) ?? false,
      notificationPermissionRequested:
          _preferences.getBool(_key(_notificationPermissionRequestedKey)) ??
          false,
    );
  }

  Future<void> save(FocusDevicePreferences preferences) async {
    final scopedUserId = userId;
    if (scopedUserId != null) {
      await migrateLegacyDeviceSettings(_preferences, scopedUserId);
    }
    await _preferences.setBool(
      _key(_notificationsKey),
      preferences.notificationsEnabled,
    );
    await _preferences.setBool(
      _key(_backgroundKey),
      preferences.backgroundRunningEnabled,
    );
    await _preferences.setBool(
      _key(_nationalFocusReminderEnabledKey),
      preferences.nationalFocusReminderEnabled,
    );
    await _preferences.setInt(
      _key(_nationalFocusReminderMinuteKey),
      preferences.nationalFocusReminderMinutesAfterMidnight.clamp(
        0,
        24 * 60 - 1,
      ),
    );
    await _preferences.setBool(
      _key(_dailyOpenReminderEnabledKey),
      preferences.dailyOpenReminderEnabled,
    );
    await _preferences.setInt(
      _key(_dailyOpenReminderMinuteKey),
      _validMinute(preferences.dailyOpenReminderMinutesAfterMidnight),
    );
    await _preferences.setBool(
      _key(_dailyOpenReminderTimeChosenKey),
      preferences.dailyOpenReminderTimeChosen,
    );
    await _preferences.setBool(
      _key(_notificationPermissionRequestedKey),
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
