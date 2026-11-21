import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/focus_session_seed.dart';

/// 七个候选城市的日分摊必须由 IANA 时区规则决定，而不是固定偏移：
/// 同一段 UTC 时间在夏令时切换前后可能落在不同的本地日期。
void main() {
  late PactaDatabase database;
  late InMemoryFocusRemote focusRemote;
  late LocalFocusRepository focus;
  late LocalTaskRepository tasks;
  late String taskId;
  var now = DateTime.utc(2026, 3, 8, 12);

  setUp(() async {
    database = PactaDatabase(NativeDatabase.memory());
    focusRemote = InMemoryFocusRemote();
    tasks = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    focus = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: focusRemote,
      now: () => now,
    );
    final goal = await tasks.createGoal(
      const GoalDraft(title: '夏令时验收', classification: TaskClassification.both),
    );
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(title: '跨时区投入', classification: TaskClassification.both),
    );
    taskId = task.id;
  });

  tearDown(() async {
    await focus.dispose();
    await tasks.dispose();
    await database.close();
  });

  test('3 月 8 日美国夏令时开始：洛杉矶仍在 3/7，纽约已到 3/8', () async {
    // 07:30Z–08:00Z：纽约 03:30 EDT（切换发生在 07:00Z），
    // 洛杉矶 23:30 PST（切换要到 10:00Z），因此两地日期不同。
    await seedFocusSessions(
      database,
      userId: 'user-a',
      sessions: [
        _settledSession(
          id: 'spring-forward',
          taskId: taskId,
          start: DateTime.utc(2026, 3, 8, 7, 30),
          seconds: 30 * 60,
        ),
      ],
    );
    now = DateTime.utc(2026, 3, 8, 12);
    await focus.settleDueSessions();

    const expected = {
      'Asia/Shanghai': '2026-03-08',
      'Asia/Singapore': '2026-03-08',
      'Asia/Tokyo': '2026-03-08',
      'Europe/London': '2026-03-08',
      'America/New_York': '2026-03-08',
      'America/Los_Angeles': '2026-03-07',
      'Etc/UTC': '2026-03-08',
    };
    for (final entry in expected.entries) {
      final metrics = await focus.getDashboardMetrics(timeZoneId: entry.key);
      expect(metrics.totalAcceptedFocusSeconds, 30 * 60, reason: entry.key);
      final day = _dayWithSeconds(metrics);
      expect(day.$1, entry.value, reason: entry.key);
      expect(day.$2, 30 * 60, reason: entry.key);
    }
  });

  test('11 月 1 日美国夏令时结束：洛杉矶回到 10/31，纽约已到 11/1', () async {
    // 06:30Z–07:00Z：纽约 01:30 EST（06:00Z 回落），洛杉矶 23:30 PDT。
    await seedFocusSessions(
      database,
      userId: 'user-a',
      sessions: [
        _settledSession(
          id: 'fall-back',
          taskId: taskId,
          start: DateTime.utc(2026, 11, 1, 6, 30),
          seconds: 30 * 60,
        ),
      ],
    );
    now = DateTime.utc(2026, 11, 1, 12);
    await focus.settleDueSessions();

    const expected = {
      'Asia/Shanghai': '2026-11-01',
      'Asia/Singapore': '2026-11-01',
      'Asia/Tokyo': '2026-11-01',
      'Europe/London': '2026-11-01',
      'America/New_York': '2026-11-01',
      'America/Los_Angeles': '2026-10-31',
      'Etc/UTC': '2026-11-01',
    };
    for (final entry in expected.entries) {
      final metrics = await focus.getDashboardMetrics(timeZoneId: entry.key);
      expect(metrics.totalAcceptedFocusSeconds, 30 * 60, reason: entry.key);
      final day = _dayWithSeconds(metrics);
      expect(day.$1, entry.value, reason: entry.key);
      expect(day.$2, 30 * 60, reason: entry.key);
    }
  });
}

FocusSession _settledSession({
  required String id,
  required String taskId,
  required DateTime start,
  required int seconds,
}) {
  final end = start.add(Duration(seconds: seconds));
  return FocusSession(
    id: id,
    taskId: taskId,
    mode: FocusChainMode.regular,
    durationSeconds: seconds,
    startedAt: start,
    endsAt: end,
    status: FocusSessionStatus.failed,
    completedAt: end,
    effectiveSeconds: seconds,
    effectiveIntervals: [FocusTimeInterval(startedAt: start, endedAt: end)],
    reviewDisposition: FocusRecordDisposition.accepted,
  );
}

/// 返回唯一有有效时间的近期活动日及其秒数。
(String, int) _dayWithSeconds(FocusDashboardMetrics metrics) {
  final active = metrics.recentActivity
      .where((day) => day.activeSeconds > 0)
      .toList();
  expect(active, hasLength(1), reason: '一段 30 分钟投入应只落在一天');
  final day = active.single;
  final key =
      '${day.date.year.toString().padLeft(4, '0')}-'
      '${day.date.month.toString().padLeft(2, '0')}-'
      '${day.date.day.toString().padLeft(2, '0')}';
  return (key, day.activeSeconds);
}
