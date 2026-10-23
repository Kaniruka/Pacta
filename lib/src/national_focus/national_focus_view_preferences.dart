import 'package:shared_preferences/shared_preferences.dart';

/// Per-user choices on this installation, outside business-data snapshots.
class NationalFocusViewPreferences {
  const NationalFocusViewPreferences({
    this.preferencesLoader = SharedPreferences.getInstance,
  });

  final Future<SharedPreferences> Function() preferencesLoader;

  String _key(String userId) => 'pacta.device.national_focus.detailed.$userId';

  Future<bool> load(String userId) async {
    final preferences = await preferencesLoader();
    // A failed legacy write can leave its in-memory cache ahead of disk.
    await preferences.reload();
    return preferences.getBool(_key(userId)) ?? false;
  }

  Future<void> save(String userId, bool detailed) async {
    final preferences = await preferencesLoader();
    if (!await preferences.setBool(_key(userId), detailed)) {
      throw StateError('国策视图偏好未保存。');
    }
  }
}
