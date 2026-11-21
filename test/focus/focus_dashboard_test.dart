import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  late PactaDatabase database;
  late InMemoryTaskRemote taskRemote;
  late InMemoryFocusRemote focusRemote;
  late LocalTaskRepository taskRepository;
  late LocalFocusRepository focusRepository;
  var now = DateTime.utc(2026, 9, 22, 8);

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    taskRemote = InMemoryTaskRemote();
    focusRemote = InMemoryFocusRemote();
    taskRepository = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: taskRemote,
      now: () => now,
    );
    focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
  });

  tearDown(() async {
    await focusRepository.dispose();
    await taskRepository.dispose();
    await database.close();
  });

  Future<Task> createTask(String title, {int? estimatedMinutes}) async {
    final goal = await taskRepository.createGoal(
      const GoalDraft(title: '本周工作', classification: TaskClassification.both),
    );
    return taskRepository.createTask(
      goal.id,
      TaskDraft(
        title: title,
        classification: TaskClassification.both,
        estimatedMinutes: estimatedMinutes,
      ),
    );
  }

  test('任务进度与近期活动共用已完成和失败会话的有效时间', () async {
    final task = await createTask('整理发布材料', estimatedMinutes: 10);
    await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 20),
    );
    now = now.add(const Duration(minutes: 20));
    await focusRepository.getSessions();

    final failedSession = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 60),
    );
    now = now.add(const Duration(minutes: 10));
    await focusRepository.pauseSession(failedSession.id, ruleText: '处理紧急来电');
    now = now.add(const Duration(minutes: 5));
    final failed = await focusRepository.abandonSession(
      sessionId: failedSession.id,
      failureReason: '本次无法继续',
    );

    expect(failed.status, FocusSessionStatus.failed);
    expect(failed.effectiveSeconds, 10 * 60);
    expect(await focusRepository.getNodes(), hasLength(1));
    expect(
      (await taskRepository.getGoals()).single.tasks.single.isComplete,
      isFalse,
    );

    final metrics = await focusRepository.getDashboardMetrics(
      timeZoneId: 'Asia/Shanghai',
    );
    expect(metrics.focusProgressSecondsByTask[task.id], 30 * 60);
    expect(metrics.totalAcceptedFocusSeconds, 30 * 60);
    expect(_dailySeconds(metrics)['2026-09-22'], 30 * 60);
    expect(
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds,
      30 * 60,
    );

    final repeatedQuery = await focusRepository.getDashboardMetrics(
      timeZoneId: 'Asia/Shanghai',
    );
    expect(repeatedQuery.totalAcceptedFocusSeconds, 30 * 60);
  });

  test('跨午夜活动按账号显示时区拆分，切换时区不改总量或链记录', () async {
    final task = await createTask('跨日专注');
    now = DateTime.utc(2026, 9, 22, 15, 50);
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(hours: 1),
    );
    now = now.add(const Duration(minutes: 30));
    await focusRepository.abandonSession(
      sessionId: session.id,
      failureReason: '今天先到这里',
    );

    final shanghai = await focusRepository.getDashboardMetrics(
      timeZoneId: 'Asia/Shanghai',
    );
    expect(shanghai.displayTimeZoneId, 'Asia/Shanghai');
    expect(_dailySeconds(shanghai)['2026-09-22'], 10 * 60);
    expect(_dailySeconds(shanghai)['2026-09-23'], 20 * 60);

    final recordsBeforeChange = await focusRepository.getChainRecords();
    // 另一个账号级显示时区：投影重新分摊，但总量与链记录不变。
    final losAngeles = await focusRepository.getDashboardMetrics(
      timeZoneId: 'America/Los_Angeles',
    );
    expect(losAngeles.displayTimeZoneId, 'America/Los_Angeles');
    expect(_dailySeconds(losAngeles)['2026-09-22'], 30 * 60);
    expect(_dailySeconds(losAngeles)['2026-09-23'], isNull);
    expect(losAngeles.totalAcceptedFocusSeconds, 30 * 60);
    expect(
      (await focusRepository.getChainRecords())
          .map(
            (record) => (
              record.mode,
              record.currentConsecutive,
              record.bestConsecutive,
              record.updatedAt,
            ),
          )
          .toList(),
      recordsBeforeChange
          .map(
            (record) => (
              record.mode,
              record.currentConsecutive,
              record.bestConsecutive,
              record.updatedAt,
            ),
          )
          .toList(),
    );

    // 无法识别的值不会被当成设备时区分支，而是固定的统一 fallback。
    final unknownZone = await focusRepository.getDashboardMetrics(
      timeZoneId: 'Not/AZone',
    );
    expect(unknownZone.displayTimeZoneId, 'Etc/UTC');
    expect(unknownZone.totalAcceptedFocusSeconds, 30 * 60);
  });

  test('重开本地 SQLite 后进度和近期活动重算且不重复', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pacta-t08-dashboard-',
    );
    final file = File('${directory.path}${Platform.pathSeparator}pacta.sqlite');
    var persistentNow = DateTime.utc(2026, 9, 22, 8);
    final persistentTaskRemote = InMemoryTaskRemote();
    final persistentFocusRemote = InMemoryFocusRemote();
    PactaDatabase? persistentDatabase;
    LocalTaskRepository? persistentTaskRepository;
    LocalFocusRepository? persistentFocusRepository;

    try {
      persistentDatabase = PactaDatabase(NativeDatabase(file));
      persistentTaskRepository = LocalTaskRepository(
        database: persistentDatabase,
        userId: 'user-a',
        remote: persistentTaskRemote,
        now: () => persistentNow,
      );
      persistentFocusRepository = LocalFocusRepository(
        database: persistentDatabase,
        userId: 'user-a',
        remote: persistentFocusRemote,
        now: () => persistentNow,
      );
      final goal = await persistentTaskRepository.createGoal(
        const GoalDraft(title: '重开看板', classification: TaskClassification.both),
      );
      final task = await persistentTaskRepository.createTask(
        goal.id,
        const TaskDraft(title: '恢复进度', classification: TaskClassification.both),
      );
      final session = await persistentFocusRepository.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 60),
      );
      persistentNow = persistentNow.add(const Duration(minutes: 30));
      await persistentFocusRepository.abandonSession(
        sessionId: session.id,
        failureReason: '验证持久化',
      );
      await persistentFocusRepository.getDashboardMetrics(
        timeZoneId: 'Asia/Shanghai',
      );

      await persistentFocusRepository.dispose();
      persistentFocusRepository = null;
      await persistentTaskRepository.dispose();
      persistentTaskRepository = null;
      await persistentDatabase.close();
      persistentDatabase = null;

      persistentDatabase = PactaDatabase(NativeDatabase(file));
      persistentTaskRepository = LocalTaskRepository(
        database: persistentDatabase,
        userId: 'user-a',
        remote: persistentTaskRemote,
        now: () => persistentNow,
      );
      persistentFocusRepository = LocalFocusRepository(
        database: persistentDatabase,
        userId: 'user-a',
        remote: persistentFocusRemote,
        now: () => persistentNow,
      );
      final afterRestart = await persistentFocusRepository.getDashboardMetrics(
        timeZoneId: 'Asia/Shanghai',
      );
      final restoredTask =
          (await persistentTaskRepository.getGoals()).single.tasks.single;
      expect(afterRestart.totalAcceptedFocusSeconds, 30 * 60);
      expect(afterRestart.focusProgressSecondsByTask[task.id], 30 * 60);
      expect(restoredTask.focusProgressSeconds, 30 * 60);

      final repeated = await persistentFocusRepository.getDashboardMetrics(
        timeZoneId: 'Asia/Shanghai',
      );
      expect(repeated.totalAcceptedFocusSeconds, 30 * 60);
      expect(
        (await persistentTaskRepository.getGoals())
            .single
            .tasks
            .single
            .focusProgressSeconds,
        30 * 60,
      );
    } finally {
      await persistentFocusRepository?.dispose();
      await persistentTaskRepository?.dispose();
      await persistentDatabase?.close();
      await directory.delete(recursive: true);
    }
  });
}

Map<String, int> _dailySeconds(FocusDashboardMetrics metrics) => {
  for (final day in metrics.recentActivity)
    _dateKey(day.date): day.activeSeconds,
};

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
