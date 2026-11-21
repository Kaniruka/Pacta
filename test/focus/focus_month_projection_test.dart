import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/focus_session_seed.dart';

void main() {
  late PactaDatabase database;
  late InMemoryTaskRemote taskRemote;
  late InMemoryFocusRemote focusRemote;
  late LocalTaskRepository taskRepository;
  late LocalFocusRepository focusRepository;
  var now = DateTime.utc(2026, 9, 22, 8);

  setUp(() {
    now = DateTime.utc(2026, 9, 22, 8);
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

  Future<Task> createTask({String title = '整理发布材料'}) async {
    final goal = await taskRepository.createGoal(
      const GoalDraft(title: '本周工作', classification: TaskClassification.both),
    );
    return taskRepository.createTask(
      goal.id,
      TaskDraft(title: title, classification: TaskClassification.both),
    );
  }

  test('月历有效投入包含已完成与失败会话，并按天分摊', () async {
    final task = await createTask();
    await seedFocusSessions(
      database,
      userId: 'user-a',
      sessions: [
        _settledSession(
          id: 'completed',
          taskId: task.id,
          startedAt: DateTime.utc(2026, 9, 10, 8),
          seconds: 20 * 60,
        ),
        _settledSession(
          id: 'failed',
          taskId: task.id,
          startedAt: DateTime.utc(2026, 9, 11, 8),
          seconds: 10 * 60,
          status: FocusSessionStatus.failed,
        ),
      ],
    );
    await focusRepository.settleDueSessions();

    final month = await focusRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 9),
    );

    expect(month.displayTimeZoneId, 'Asia/Shanghai');
    expect(month.month, DateTime.utc(2026, 9, 1));
    expect(month.days, hasLength(30));
    expect(month.totalActiveSeconds, 30 * 60);
    expect(month.activeDayCount, 2);
    expect(month.activeSecondsOn(DateTime.utc(2026, 9, 10)), 20 * 60);
    expect(month.activeSecondsOn(DateTime(2026, 9, 11)), 10 * 60);
  });

  test('暂停间隔、排除区间与待核对区间不计入月分摊', () async {
    final task = await createTask();
    final base = DateTime.utc(2026, 9, 12, 1);
    await seedFocusSessions(
      database,
      userId: 'user-a',
      sessions: [
        _settledSession(
          id: 'gapped',
          taskId: task.id,
          startedAt: base,
          effectiveSeconds: 35 * 60,
          intervals: [
            FocusTimeInterval(
              startedAt: base,
              endedAt: base.add(const Duration(minutes: 10)),
            ),
            FocusTimeInterval(
              startedAt: base.add(const Duration(minutes: 25)),
              endedAt: base.add(const Duration(minutes: 30)),
            ),
            FocusTimeInterval(
              startedAt: base.add(const Duration(minutes: 40)),
              endedAt: base.add(const Duration(minutes: 50)),
              excludeFromFocusProgress: true,
            ),
            FocusTimeInterval(
              startedAt: base.add(const Duration(minutes: 60)),
              endedAt: base.add(const Duration(minutes: 70)),
              clockReviewStatus: FocusClockReviewStatus.pending,
            ),
          ],
        ),
      ],
    );
    await focusRepository.settleDueSessions();

    final month = await focusRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 9),
    );

    expect(month.totalActiveSeconds, 15 * 60);
    expect(month.activeDayCount, 1);
  });

  test('跨月区间按账号时区午夜拆分，每个月只算自己那段', () async {
    final task = await createTask();
    // 2026-09-30T15:00Z 是上海 9 月 30 日 23:00，两小时后进入 10 月 1 日 01:00。
    await seedFocusSessions(
      database,
      userId: 'user-a',
      sessions: [
        _settledSession(
          id: 'cross-month',
          taskId: task.id,
          startedAt: DateTime.utc(2026, 9, 30, 15),
          seconds: 2 * 60 * 60,
        ),
      ],
    );
    await focusRepository.settleDueSessions();

    final september = await focusRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 9),
    );
    final october = await focusRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 10),
    );

    expect(september.totalActiveSeconds, 60 * 60);
    expect(september.activeSecondsOn(DateTime.utc(2026, 9, 30)), 60 * 60);
    expect(october.days, hasLength(31));
    expect(october.totalActiveSeconds, 60 * 60);
    expect(october.activeSecondsOn(DateTime.utc(2026, 10, 1)), 60 * 60);
  });

  test('夏令时结束日按账号时区的真实日长分摊', () async {
    final task = await createTask();
    // 伦敦 2026-10-25 是夏令时结束日：本地当天有 25 小时。
    await seedFocusSessions(
      database,
      userId: 'user-a',
      sessions: [
        _settledSession(
          id: 'long-day',
          taskId: task.id,
          startedAt: DateTime.utc(2026, 10, 24, 23),
          seconds: 25 * 60 * 60,
        ),
      ],
    );
    await focusRepository.settleDueSessions();

    final month = await focusRepository.getMonthMetrics(
      timeZoneId: 'Europe/London',
      month: DateTime(2026, 10),
    );

    expect(month.totalActiveSeconds, 25 * 60 * 60);
    expect(month.activeSecondsOn(DateTime.utc(2026, 10, 25)), 25 * 60 * 60);
    expect(month.activeSecondsOn(DateTime.utc(2026, 10, 24)), 0);
    expect(month.activeSecondsOn(DateTime.utc(2026, 10, 26)), 0);
  });

  test('旧记录没有区间时回退到有效时长', () async {
    final task = await createTask();
    await seedFocusSessions(
      database,
      userId: 'user-a',
      sessions: [
        _settledSession(
          id: 'legacy',
          taskId: task.id,
          startedAt: DateTime.utc(2026, 9, 5, 8),
          effectiveSeconds: 10 * 60,
          intervals: const [],
        ),
      ],
    );
    await focusRepository.settleDueSessions();

    final month = await focusRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 9),
    );

    expect(month.totalActiveSeconds, 10 * 60);
    expect(month.activeSecondsOn(DateTime.utc(2026, 9, 5)), 10 * 60);
  });

  test('没有有效投入的月份是中性空白', () async {
    final month = await focusRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 9),
    );

    expect(month.days, hasLength(30));
    expect(month.totalActiveSeconds, 0);
    expect(month.activeDayCount, 0);
    expect(month.hasActivity, isFalse);
    expect(month.month, DateTime.utc(2026, 9, 1));
    for (final day in month.days) {
      expect(day.activeSeconds, 0);
      expect(day.date.isUtc, isTrue);
      expect(day.date.hour, 0);
    }
  });

  test('账号之间互不可见对方的有效投入', () async {
    final task = await createTask();
    final otherRepository = LocalFocusRepository(
      database: database,
      userId: 'user-b',
      remote: focusRemote,
      now: () => now,
    );
    addTearDown(otherRepository.dispose);
    await seedFocusSessions(
      database,
      userId: 'user-a',
      sessions: [
        _settledSession(
          id: 'a-session',
          taskId: task.id,
          startedAt: DateTime.utc(2026, 9, 18, 8),
          seconds: 20 * 60,
        ),
      ],
    );
    await seedFocusSessions(
      database,
      userId: 'user-b',
      sessions: [
        _settledSession(
          id: 'b-session',
          taskId: task.id,
          startedAt: DateTime.utc(2026, 9, 18, 9),
          seconds: 10 * 60,
        ),
      ],
    );
    await focusRepository.settleDueSessions();
    await otherRepository.settleDueSessions();

    final mine = await focusRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 9),
    );
    final theirs = await otherRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 9),
    );

    expect(mine.totalActiveSeconds, 20 * 60);
    expect(theirs.totalActiveSeconds, 10 * 60);
  });

  test('切换账号时区不改变全历史总额，但会移动月边界分摊', () async {
    final task = await createTask();
    await seedFocusSessions(
      database,
      userId: 'user-a',
      sessions: [
        _settledSession(
          id: 'boundary',
          taskId: task.id,
          // 上海 9 月 30 日 23:00 开始，两小时里各月各占一半。
          startedAt: DateTime.utc(2026, 9, 30, 15),
          seconds: 2 * 60 * 60,
        ),
      ],
    );
    await focusRepository.settleDueSessions();

    final shanghaiMonth = await focusRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 9),
    );
    final utcMonth = await focusRepository.getMonthMetrics(
      timeZoneId: 'Etc/UTC',
      month: DateTime(2026, 9),
    );
    final shanghaiTotal = await focusRepository.getDashboardMetrics(
      timeZoneId: 'Asia/Shanghai',
    );
    final utcTotal = await focusRepository.getDashboardMetrics(
      timeZoneId: 'Etc/UTC',
    );

    expect(shanghaiMonth.totalActiveSeconds, 60 * 60);
    expect(utcMonth.totalActiveSeconds, 2 * 60 * 60);
    expect(shanghaiTotal.totalAcceptedFocusSeconds, 2 * 60 * 60);
    expect(utcTotal.totalAcceptedFocusSeconds, 2 * 60 * 60);
  });

  test('完成独立事项不点亮月历，专注也不自动完成任务', () async {
    final errand = await createTask(title: '取快递');
    await taskRepository.setTaskCompletion(errand.id, isComplete: true);

    final emptyMonth = await focusRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 9),
    );
    expect(emptyMonth.totalActiveSeconds, 0);
    expect(emptyMonth.activeDayCount, 0);

    final focusTask = await createTask(title: '整理发布材料');
    final session = await focusRepository.startSession(
      taskId: focusTask.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 20),
    );
    now = now.add(const Duration(minutes: 10));
    await focusRepository.abandonSession(
      sessionId: session.id,
      failureReason: '先到这里',
    );

    final litMonth = await focusRepository.getMonthMetrics(
      timeZoneId: 'Asia/Shanghai',
      month: DateTime(2026, 9),
    );
    expect(litMonth.totalActiveSeconds, 10 * 60);

    final tasks = [
      for (final goal in await taskRepository.getGoals()) ...goal.tasks,
    ];
    expect(
      tasks.singleWhere((task) => task.id == errand.id).isComplete,
      isTrue,
    );
    expect(
      tasks.singleWhere((task) => task.id == focusTask.id).isComplete,
      isFalse,
      reason: '专注时长不自动完成任务',
    );
  });

  test('订阅月投影会随新增有效投入更新', () async {
    final totals = <int>[];
    final subscription = focusRepository
        .watchMonthMetrics(
          timeZoneId: 'Asia/Shanghai',
          month: DateTime(2026, 9),
        )
        .listen((metrics) => totals.add(metrics.totalActiveSeconds));
    addTearDown(subscription.cancel);
    await _flush();

    expect(totals, [0]);

    final task = await createTask();
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 10),
    );
    now = now.add(const Duration(minutes: 5));
    await focusRepository.abandonSession(
      sessionId: session.id,
      failureReason: '先到这里',
    );
    await _flush();

    expect(totals.last, 5 * 60);
  });
}

Future<void> _flush() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

FocusSession _settledSession({
  required String id,
  required String taskId,
  required DateTime startedAt,
  int? seconds,
  int? effectiveSeconds,
  List<FocusTimeInterval>? intervals,
  FocusSessionStatus status = FocusSessionStatus.completed,
  FocusRecordDisposition disposition = FocusRecordDisposition.accepted,
}) {
  final resolvedIntervals =
      intervals ??
      [
        FocusTimeInterval(
          startedAt: startedAt,
          endedAt: startedAt.add(Duration(seconds: seconds ?? 0)),
        ),
      ];
  final computedSeconds = resolvedIntervals.fold<int>(
    0,
    (sum, interval) =>
        sum + (interval.endedAt?.difference(interval.startedAt).inSeconds ?? 0),
  );
  final effective = effectiveSeconds ?? seconds ?? computedSeconds;
  final endedAt = resolvedIntervals.isEmpty
      ? startedAt.add(Duration(seconds: effective))
      : (resolvedIntervals.last.endedAt ?? startedAt);
  return FocusSession(
    id: id,
    taskId: taskId,
    mode: FocusChainMode.regular,
    durationSeconds: computedSeconds,
    startedAt: startedAt,
    endsAt: endedAt,
    status: status,
    completedAt: endedAt,
    effectiveSeconds: effective,
    effectiveIntervals: resolvedIntervals,
    reviewDisposition: disposition,
  );
}
