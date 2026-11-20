import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/plan/goal_view_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 工单 04：按（用户, 目标）独立的"隐藏已完成任务"偏好。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认显示已完成，切换后按用户与目标独立持久化', () async {
    const preferences = GoalViewPreferences();
    expect(
      await preferences.hideCompletedTasks(userId: 'user-a', goalId: 'goal-1'),
      isFalse,
      reason: '默认不隐藏',
    );

    await preferences.setHideCompletedTasks(
      userId: 'user-a',
      goalId: 'goal-1',
      hide: true,
    );

    expect(
      await preferences.hideCompletedTasks(userId: 'user-a', goalId: 'goal-1'),
      isTrue,
    );
    expect(
      await preferences.hideCompletedTasks(userId: 'user-a', goalId: 'goal-2'),
      isFalse,
      reason: '同一用户的不同目标互不影响',
    );
    expect(
      await preferences.hideCompletedTasks(userId: 'user-b', goalId: 'goal-1'),
      isFalse,
      reason: '不同用户互不影响',
    );

    // 新的实例读到同一份磁盘偏好，证明不是实例内缓存。
    const reopened = GoalViewPreferences();
    expect(
      await reopened.hideCompletedTasks(userId: 'user-a', goalId: 'goal-1'),
      isTrue,
    );
    final stored = await SharedPreferences.getInstance();
    expect(
      stored.getBool('pacta.device.goal.hide_completed.v1.user-a.goal-1'),
      isTrue,
    );
  });

  test('插件不可用时降级为 false，同一键的切换仍在内存中生效', () async {
    final degraded = GoalViewPreferences(
      preferencesLoader: () => Future<SharedPreferences>.error(
        MissingPluginException('no plugin for shared preferences'),
      ),
    );
    expect(
      await degraded.hideCompletedTasks(
        userId: 'degraded-user',
        goalId: 'degraded-goal',
      ),
      isFalse,
    );
    await degraded.setHideCompletedTasks(
      userId: 'degraded-user',
      goalId: 'degraded-goal',
      hide: true,
    );
    expect(
      await degraded.hideCompletedTasks(
        userId: 'degraded-user',
        goalId: 'degraded-goal',
      ),
      isTrue,
      reason: '没有偏好存储时用内存兜底，页面不会因为读不到而闪回默认值',
    );
    expect(
      await degraded.hideCompletedTasks(
        userId: 'degraded-user',
        goalId: 'other-goal',
      ),
      isFalse,
    );
  });

  test('默认装载器在无绑定纯 Dart 场景也能安全降级', () async {
    // 本文件的绑定已初始化，所以这里显式使用会失败的装载器模拟"没有插件"；
    // 真实的纯 Dart 无绑定路径由 GoalTaskOrderStore 的仓储测试覆盖。
    final noBinding = GoalViewPreferences(
      preferencesLoader: () => Future<SharedPreferences>.error(
        StateError('Binding has not yet been initialized.'),
      ),
    );
    expect(
      await noBinding.hideCompletedTasks(
        userId: 'no-binding',
        goalId: 'goal-x',
      ),
      isFalse,
    );
    await noBinding.setHideCompletedTasks(
      userId: 'no-binding',
      goalId: 'goal-x',
      hide: true,
    );
    expect(
      await noBinding.hideCompletedTasks(
        userId: 'no-binding',
        goalId: 'goal-x',
      ),
      isTrue,
    );
  });
}
