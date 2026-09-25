import 'package:shared_preferences/shared_preferences.dart';

/// Notification choices belong to this installation and are never synchronized.
class FocusDevicePreferences {
  const FocusDevicePreferences({
    required this.notificationsEnabled,
    required this.backgroundRunningEnabled,
  });

  final bool notificationsEnabled;
  final bool backgroundRunningEnabled;

  FocusDevicePreferences copyWith({
    bool? notificationsEnabled,
    bool? backgroundRunningEnabled,
  }) =>
      FocusDevicePreferences(
        notificationsEnabled:
            notificationsEnabled ?? this.notificationsEnabled,
        backgroundRunningEnabled:
            backgroundRunningEnabled ?? this.backgroundRunningEnabled,
      );
}

class FocusDevicePreferencesStore {
  FocusDevicePreferencesStore(this._preferences);

  static const _notificationsKey = 'pacta.device.focus_notifications_enabled';
  static const _backgroundKey = 'pacta.device.background_running_enabled';

  final SharedPreferences _preferences;

  Future<FocusDevicePreferences> load() async => FocusDevicePreferences(
    notificationsEnabled: _preferences.getBool(_notificationsKey) ?? false,
    backgroundRunningEnabled: _preferences.getBool(_backgroundKey) ?? true,
  );

  Future<void> save(FocusDevicePreferences preferences) async {
    await _preferences.setBool(
      _notificationsKey,
      preferences.notificationsEnabled,
    );
    await _preferences.setBool(
      _backgroundKey,
      preferences.backgroundRunningEnabled,
    );
  }
}
