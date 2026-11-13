import 'package:shared_preferences/shared_preferences.dart';

/// 本机当前用户的“今日确认后自动上传”开关。
///
/// 默认关闭；它是设备偏好，不随业务快照替换或跨设备复制。
class CloudAutoUploadPreference {
  const CloudAutoUploadPreference({
    this.preferencesLoader = SharedPreferences.getInstance,
  });

  final Future<SharedPreferences> Function() preferencesLoader;

  String _key(String userId) =>
      'pacta.device.cloud_auto_upload.enabled.$userId';

  Future<bool> load(String userId) async {
    final preferences = await preferencesLoader();
    await preferences.reload();
    return preferences.getBool(_key(userId)) ?? false;
  }

  Future<void> save(String userId, bool enabled) async {
    final preferences = await preferencesLoader();
    final saved = await preferences.setBool(_key(userId), enabled);
    if (!saved) throw StateError('自动上传开关未保存，请重试。');
  }
}
