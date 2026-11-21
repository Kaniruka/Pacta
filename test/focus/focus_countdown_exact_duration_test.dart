import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

/// 正常倒计时的结算口径：到点完成必须严格记满 [FocusSession.durationSeconds]，
/// 不允许单调时钟的亚秒余量被 `.floor()` 吃掉而显示成 24 分 59 秒。
///
/// 真实设备上墙钟与单调时钟从不完全同步：墙钟刚跨过 `endsAt` 时，单调时钟
/// 只走了 1499.95 秒就会把 1500 秒向下取整成 1499 秒。这个用例把墙钟与单调
/// 时钟分开注入，先复现 1499 秒的红态，再守住修复后的 1500 秒口径。
void main() {
  late PactaDatabase database;
  late InMemoryTaskRemote taskRemote;
  late InMemoryFocusRemote focusRemote;
  late LocalTaskRepository taskRepository;
  late LocalFocusRepository focusRepository;
  late DateTime wallTime;
  late Duration monotonicTime;

  setUp(() {
    wallTime = DateTime.utc(2026, 11, 18, 9);
    monotonicTime = Duration.zero;
    database = PactaDatabase(NativeDatabase.memory());
    taskRemote = InMemoryTaskRemote();
    focusRemote = InMemoryFocusRemote();
    taskRepository = LocalTaskRepository(
      database: database,
      userId: 'exact-duration',
      remote: taskRemote,
      cloudSyncEnabled: false,
      now: () => wallTime,
    );
    focusRepository = LocalFocusRepository(
      database: database,
      userId: 'exact-duration',
      remote: focusRemote,
      cloudSyncEnabled: false,
      now: () => wallTime,
      monotonicNow: () => monotonicTime,
    );
  });

  tearDown(() async {
    await focusRepository.dispose();
    await taskRepository.dispose();
    await database.close();
  });

  Future<Task> createTask(String title) async {
    final goal = await taskRepository.createGoal(
      const GoalDraft(
        title: '倒计时精确结算',
        classification: TaskClassification.both,
      ),
    );
    return taskRepository.createTask(
      goal.id,
      TaskDraft(title: title, classification: TaskClassification.both),
    );
  }

  Future<int> taskFocusProgressSeconds() async =>
      (await taskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds;

  Future<int> monthActiveSeconds() async {
    final metrics = await focusRepository.getMonthMetrics(
      timeZoneId: 'Etc/UTC',
      month: DateTime.utc(2026, 11),
    );
    return metrics.activeSecondsOn(DateTime.utc(2026, 11, 18));
  }

  int intervalSum(FocusSession session) => session.effectiveIntervals.fold<int>(
    0,
    (seconds, interval) => seconds + interval.durationSeconds,
  );

  test('墙钟到点、单调时钟差 50 毫秒时仍结算为完整的 25 分 00 秒', () async {
    final task = await createTask('25 分钟专注');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );

    // 墙钟恰好到 endsAt，单调时钟只走了 1499.95 秒。
    wallTime = session.endsAt;
    monotonicTime = const Duration(seconds: 1499, milliseconds: 950);
    await focusRepository.settleDueSessions();

    final completed = (await focusRepository.getSession(session.id))!;
    expect(completed.status, FocusSessionStatus.completed);
    expect(
      completed.completedAt!.isAtSameMomentAs(session.endsAt),
      isTrue,
      reason: '完成时刻落在预设的 endsAt',
    );
    expect(completed.effectiveSeconds, 1500, reason: '正常倒计时必须记满 25 分 00 秒');
    expect(intervalSum(completed), 1500, reason: '区间累加必须与有效秒数一致');
    expect(
      completed.effectiveIntervals.last.endedAt!.isAtSameMomentAs(
        session.endsAt,
      ),
      isTrue,
      reason: '末段区间结束于预设的 endsAt',
    );

    final nodes = await focusRepository.getNodes();
    expect(nodes.single.effectiveSeconds, 1500, reason: '专注节点与结算口径一致');
    expect(await taskFocusProgressSeconds(), 1500, reason: '任务累计与结算口径一致');
    expect(await monthActiveSeconds(), 1500, reason: '月度统计与结算口径一致');
  });

  test('中途暂停一次后正常倒计时完成，各段取整不丢秒', () async {
    final task = await createTask('暂停一次后完成');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );

    // 第 1 段：墙钟与单调时钟同步走 600.4 秒。
    wallTime = wallTime.add(const Duration(milliseconds: 600400));
    monotonicTime += const Duration(milliseconds: 600400);
    await focusRepository.pauseSession(session.id, ruleText: '允许短暂离开');

    // 暂停 2 秒后继续。
    wallTime = wallTime.add(const Duration(seconds: 2));
    monotonicTime += const Duration(seconds: 2);
    final resumed = await focusRepository.resumeSession(session.id);
    expect(resumed.status, FocusSessionStatus.active);

    // 第 2 段：墙钟走到调整后的 endsAt，单调时钟只有 899.7 秒。
    wallTime = resumed.endsAt;
    monotonicTime += const Duration(seconds: 899, milliseconds: 700);
    await focusRepository.settleDueSessions();

    final completed = (await focusRepository.getSession(session.id))!;
    expect(completed.status, FocusSessionStatus.completed);
    expect(
      completed.completedAt!.isAtSameMomentAs(resumed.endsAt),
      isTrue,
      reason: '完成时刻落在调整后的 endsAt',
    );
    expect(completed.effectiveSeconds, 1500, reason: '两段取整余量不能叠加成 24 分 59 秒');
    expect(intervalSum(completed), 1500);
    expect(completed.effectiveIntervals, hasLength(2));
    expect(
      completed.effectiveIntervals.last.endedAt!.isAtSameMomentAs(
        resumed.endsAt,
      ),
      isTrue,
      reason: '补偿只落在末段区间，且结束于 endsAt',
    );

    final nodes = await focusRepository.getNodes();
    expect(nodes.single.effectiveSeconds, 1500);
    expect(await taskFocusProgressSeconds(), 1500);
    expect(await monthActiveSeconds(), 1500);
  });

  test('下必为例提前完成仍按实测秒数结算，不补齐到预设时长', () async {
    final task = await createTask('提前完成');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 25),
    );

    wallTime = wallTime.add(const Duration(milliseconds: 600400));
    monotonicTime += const Duration(milliseconds: 600400);
    final completed = await focusRepository.completeEarlySession(
      sessionId: session.id,
      ruleText: '允许提前结束并保留已完成的工作',
    );

    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.completionType, FocusSessionCompletionType.precedentRule);
    expect(completed.effectiveSeconds, 600, reason: '提前完成只记实测的 10 分 00 秒');
    expect(intervalSum(completed), 600);
    expect(
      (await focusRepository.getNodes()).single.effectiveSeconds,
      600,
      reason: '节点与提前完成口径一致',
    );
    expect(await taskFocusProgressSeconds(), 600);
  });

  test('主动放弃仍按实测秒数结算，不补齐到预设时长', () async {
    final task = await createTask('主动放弃');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );

    wallTime = wallTime.add(const Duration(milliseconds: 300600));
    monotonicTime += const Duration(milliseconds: 300600);
    final failed = await focusRepository.abandonSession(
      sessionId: session.id,
      failureReason: '临时有事离开了',
    );

    expect(failed.status, FocusSessionStatus.failed);
    expect(failed.effectiveSeconds, 300, reason: '放弃只记实测的 5 分 00 秒');
    expect(intervalSum(failed), 300);
    expect(await focusRepository.getNodes(), isEmpty);
    expect(await taskFocusProgressSeconds(), 300);
  });

  test('时钟异常进入审核的区间仍按实测秒数结算，不虚增到预设时长', () async {
    final task = await createTask('时钟异常');
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );

    // 正常走 5 分钟：建立上一个墙钟/单调时钟样本。
    wallTime = wallTime.add(const Duration(minutes: 5));
    monotonicTime += const Duration(minutes: 5);
    await focusRepository.getSession(session.id);

    // 墙钟前跳 2 小时、单调时钟只走 1 秒：这段差异必须进入审核。
    wallTime = wallTime.add(const Duration(hours: 2));
    monotonicTime += const Duration(seconds: 1);
    final jumped = (await focusRepository.getSession(session.id))!;
    final reviewCases = await focusRepository.getClockReviewCases();
    expect(reviewCases, hasLength(1));
    expect(reviewCases.single.direction, FocusClockChangeDirection.forward);

    // 走到重新锚定后的 endsAt，单调时钟同步走完剩余时长。
    final remaining = jumped.endsAt.difference(wallTime);
    final monoBefore = monotonicTime;
    wallTime = jumped.endsAt;
    monotonicTime = monoBefore + remaining;
    await focusRepository.settleDueSessions();

    final completed = (await focusRepository.getSession(session.id))!;
    expect(completed.status, FocusSessionStatus.completed);
    expect(
      completed.effectiveIntervals.any(
        (interval) => interval.isAwaitingClockReview,
      ),
      isTrue,
      reason: '审核区间保持待审状态',
    );
    final reliable = completed.effectiveIntervals
        .where(
          (interval) =>
              !interval.isAwaitingClockReview &&
              !interval.excludeFromFocusProgress,
        )
        .fold<int>(
          0,
          (seconds, interval) => seconds + interval.durationSeconds,
        );
    expect(
      completed.effectiveSeconds,
      reliable,
      reason: '有待审区间时不补齐，按可靠区间实测秒数结算',
    );
    expect(
      completed.effectiveSeconds,
      lessThan(completed.durationSeconds),
      reason: '待审的 1 秒不能靠补齐变成预设的 25 分钟',
    );
    expect(
      intervalSum(completed),
      completed.durationSeconds,
      reason: '待审区间仍是墙钟覆盖的一部分，只是暂不计入有效秒数',
    );
  });
}
