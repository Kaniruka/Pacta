import 'package:shared_preferences/shared_preferences.dart';

import '../tasks/preference_storage_fallback.dart';

/// 每个目标独立的"隐藏已完成任务"设备偏好。
///
/// 键里同时包含用户与目标，因此不同目标、不同账号互不影响；偏好只落在
/// 本机，不进入业务数据快照。没有初始化 `WidgetsFlutterBinding` 的纯 Dart
/// 场景（或宿主没有 SharedPreferences 插件）退回进程内内存表：读到的默认
/// 值仍是 `false`，但同一次运行内的切换保持一致，不会把页面弄崩。
class GoalViewPreferences {
  const GoalViewPreferences({
    this.preferencesLoader = SharedPreferences.getInstance,
  });

  final Future<SharedPreferences> Function() preferencesLoader;

  static final Map<String, bool> _memoryFallback = <String, bool>{};

  String keyFor(String userId, String goalId) =>
      'pacta.device.goal.hide_completed.v1.$userId.$goalId';

  Future<bool> hideCompletedTasks({
    required String userId,
    required String goalId,
  }) async {
    final key = keyFor(userId, goalId);
    final preferences = await _preferencesOrNull();
    if (preferences == null) return _memoryFallback[key] ?? false;
    // 旧写入失败可能让内存缓存领先磁盘，读取前对齐一次。
    await preferences.reload();
    return preferences.getBool(key) ?? false;
  }

  Future<void> setHideCompletedTasks({
    required String userId,
    required String goalId,
    required bool hide,
  }) async {
    final key = keyFor(userId, goalId);
    final preferences = await _preferencesOrNull();
    if (preferences == null) {
      _memoryFallback[key] = hide;
      return;
    }
    if (!await preferences.setBool(key, hide)) {
      throw StateError('隐藏已完成任务偏好未保存，请重试。');
    }
  }

  Future<SharedPreferences?> _preferencesOrNull() =>
      loadSharedPreferencesOrNull(preferencesLoader);
}
