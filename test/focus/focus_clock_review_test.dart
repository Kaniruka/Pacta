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
  late DateTime wallTime;
  late Duration monotonicTime;
  final focusRepositories = <LocalFocusRepository>[];
  final taskRepositories = <LocalTaskRepository>[];
  final databases = <PactaDatabase>[];

  setUp(() {
    wallTime = DateTime.utc(2026, 9, 25, 8);
    monotonicTime = Duration.zero;
    database = PactaDatabase(NativeDatabase.memory());
    databases.add(database);
    taskRemote = InMemoryTaskRemote();
    focusRemote = InMemoryFocusRemote();
    taskRepository = LocalTaskRepository(
      database: database,
      userId: 'clock-user',
      remote: taskRemote,
      now: () => wallTime,
    );
    taskRepositories.add(taskRepository);
    focusRepository = _newFocusRepository(
      database: database,
      remote: focusRemote,
      wallTime: () => wallTime,
      monotonicTime: () => monotonicTime,
      register: focusRepositories.add,
    );
  });

  tearDown(() async {
    for (final repository in focusRepositories) {
      await repository.dispose();
    }
    focusRepositories.clear();
    for (final repository in taskRepositories) {
      await repository.dispose();
    }
    taskRepositories.clear();
    for (final item in databases) {
      await item.close();
    }
    databases.clear();
  });

  Future<Task> createTask(String title) async {
    final goal = await taskRepository.createGoal(
      const GoalDraft(
        title: 'T12 设备时钟核对',
        classification: TaskClassification.both,
      ),
    );
    return taskRepository.createTask(
      goal.id,
      TaskDraft(title: title, classification: TaskClassification.both),
    );
  }

  Future<(FocusSession, FocusClockReviewCase)> createClockJump({
    required bool forward,
    Duration duration = const Duration(minutes: 20),
  }) async {
    final task = await createTask(forward ? '前跳专注' : '后跳专注');
    final started = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: duration,
    );
    wallTime = wallTime.add(const Duration(minutes: 5));
    monotonicTime += const Duration(minutes: 5);
    await focusRepository.getSession(started.id);

    wallTime = wallTime.add(
      forward ? const Duration(hours: 2) : -const Duration(hours: 2),
    );
    monotonicTime += const Duration(seconds: 1);
    final session = (await focusRepository.getSession(started.id))!;
    final reviewCase = (await focusRepository.getClockReviewCases()).single;
    return (session, reviewCase);
  }

  test('前跳保留可靠时间，可暂缓、继续新专注並核对单调计时', () async {
    final (afterJump, reviewCase) = await createClockJump(forward: true);

    expect(afterJump.status, FocusSessionStatus.active);
    expect(afterJump.isFailed, isFalse);
    expect(reviewCase.direction, FocusClockChangeDirection.forward);
    expect(reviewCase.reliableSeconds, const Duration(minutes: 5).inSeconds);
    expect(reviewCase.uncertainSeconds, 1);
    expect(afterJump.endsAt.isAfter(wallTime), isTrue);
    expect(
      afterJump.effectiveIntervals.map((interval) => interval.startedAt),
      orderedEquals(
        afterJump.effectiveIntervals
            .map((interval) => interval.startedAt)
            .toList()
          ..sort(),
      ),
    );

    await focusRepository.deferClockReviewCase(reviewCase.id);
    final deferred = (await focusRepository.getClockReviewCases()).single;
    expect(deferred.isDeferred, isTrue);
    expect(deferred.interval.isAwaitingClockReview, isTrue);
    expect(
      deferred.interval.observedStartedAt,
      reviewCase.interval.observedStartedAt,
    );
    expect(
      deferred.interval.observedEndedAt,
      reviewCase.interval.observedEndedAt,
    );

    wallTime = wallTime.add(const Duration(minutes: 15));
    monotonicTime += const Duration(minutes: 15);
    final completed = (await focusRepository.getSession(afterJump.id))!;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.isFailed, isFalse);
    expect(
      completed.effectiveSeconds,
      const Duration(minutes: 19, seconds: 59).inSeconds,
    );
    expect(
      (await focusRepository.getClockReviewCases()).single.isDeferred,
      isTrue,
    );

    final nextTask = await createTask('继续处理其他任务');
    final nextSession = await focusRepository.startSession(
      taskId: nextTask.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 3),
    );
    expect(nextSession.id, isNot(completed.id));
    expect(nextSession.isActive, isTrue);

    await focusRepository.resolveClockReviewCase(
      caseId: reviewCase.id,
      decision: FocusClockReviewDecision.acceptMonotonicEstimate,
    );
    expect(await focusRepository.getClockReviewCases(), isEmpty);
    final resolved = (await focusRepository.getSession(completed.id))!;
    expect(resolved.effectiveSeconds, const Duration(minutes: 20).inSeconds);
    expect(
      resolved.effectiveIntervals.any(
        (interval) =>
            interval.clockReviewStatus == FocusClockReviewStatus.resolved &&
            interval.observedStartedAt != null &&
            interval.observedEndedAt != null,
      ),
      isTrue,
    );
    final metrics = await focusRepository.getDashboardMetrics(
      deviceTimeZoneId: 'Etc/UTC',
    );
    expect(metrics.focusProgressSecondsByTask[completed.taskId], 20 * 60);
  });

  test('后跳采用连续计时排序，不产生重叠或重复统计', () async {
    final (afterJump, reviewCase) = await createClockJump(
      forward: false,
      duration: const Duration(minutes: 20),
    );
    final intervals = afterJump.effectiveIntervals;
    expect(afterJump.status, FocusSessionStatus.active);
    expect(afterJump.isFailed, isFalse);
    expect(reviewCase.direction, FocusClockChangeDirection.backward);
    expect(reviewCase.reliableSeconds, const Duration(minutes: 5).inSeconds);
    expect(intervals, hasLength(3));
    expect(intervals[0].endedAt, intervals[1].startedAt);
    expect(intervals[1].endedAt, intervals[2].startedAt);
    expect(intervals[1].endedAt!.isAfter(wallTime), isTrue);
    expect(intervals[2].startedAt.isAfter(wallTime), isTrue);

    wallTime = wallTime.add(const Duration(minutes: 15));
    monotonicTime += const Duration(minutes: 15);
    final completed = (await focusRepository.getSession(afterJump.id))!;
    expect(completed.status, FocusSessionStatus.completed);
    expect(
      completed.effectiveSeconds,
      const Duration(minutes: 19, seconds: 59).inSeconds,
    );

    await focusRepository.resolveClockReviewCase(
      caseId: reviewCase.id,
      decision: FocusClockReviewDecision.keepReliableTimeOnly,
    );
    final resolved = (await focusRepository.getSession(completed.id))!;
    expect(
      resolved.effectiveSeconds,
      const Duration(minutes: 19, seconds: 59).inSeconds,
    );
    expect(resolved.effectiveIntervals[1].excludeFromFocusProgress, isTrue);
    final metrics = await focusRepository.getDashboardMetrics(
      deviceTimeZoneId: 'Etc/UTC',
    );
    expect(
      metrics.focusProgressSecondsByTask[completed.taskId],
      const Duration(minutes: 19, seconds: 59).inSeconds,
    );
  });

  test('无时钟异常时完整计时并自动结算', () async {
    final task = await createTask('正常计时');
    final started = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 60),
    );
    wallTime = wallTime.add(const Duration(seconds: 60));
    monotonicTime += const Duration(seconds: 60);

    final completed = (await focusRepository.getSession(started.id))!;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.effectiveSeconds, 60);
    expect(await focusRepository.getClockReviewCases(), isEmpty);
  });

  test('仅有待核对区间时不会回退到过时的 effectiveSeconds 汇总值', () async {
    final task = await createTask('核对前不计争议时间');
    final startedAt = wallTime.subtract(const Duration(hours: 1));
    final endedAt = startedAt.add(const Duration(seconds: 45));
    await focusRemote.upsertSessions(
      userId: 'clock-user',
      sessions: [
        FocusSession(
          id: 'pending-only-session',
          taskId: task.id,
          mode: FocusChainMode.regular,
          durationSeconds: 60,
          startedAt: startedAt,
          endsAt: endedAt,
          status: FocusSessionStatus.completed,
          completedAt: endedAt,
          // Simulate an older or stale aggregate. The retained interval is
          // the authority while its clock evidence is pending.
          effectiveSeconds: 45,
          effectiveIntervals: [
            FocusTimeInterval(
              startedAt: startedAt,
              endedAt: endedAt,
              measuredDurationSeconds: 45,
              observedStartedAt: startedAt,
              observedEndedAt: endedAt,
              clockDiscrepancySeconds: 7200,
              clockReviewStatus: FocusClockReviewStatus.pending,
            ),
          ],
        ),
      ],
    );

    await focusRepository.sync();

    final metrics = await focusRepository.getDashboardMetrics(
      deviceTimeZoneId: 'Etc/UTC',
    );
    expect(metrics.focusProgressSecondsByTask.containsKey(task.id), isFalse);
    expect(metrics.totalAcceptedFocusSeconds, 0);
    expect((await focusRepository.getNodes()).single.effectiveSeconds, 0);
  });

  test('正常进程重启保留原倒计时结束点并恢复有效专注时间', () async {
    final task = await createTask('重启后继续');
    final started = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 10),
    );
    final originalEndsAt = started.endsAt;
    wallTime = wallTime.add(const Duration(minutes: 4));
    monotonicTime += const Duration(minutes: 4);
    await focusRepository.getSession(started.id);

    await focusRepository.dispose();
    focusRepositories.clear();
    monotonicTime = Duration.zero;
    focusRepository = _newFocusRepository(
      database: database,
      remote: focusRemote,
      wallTime: () => wallTime,
      monotonicTime: () => monotonicTime,
      register: focusRepositories.add,
    );

    final recovered = (await focusRepository.getActiveSession())!;
    expect(recovered.status, FocusSessionStatus.active);
    expect(recovered.endsAt.isAtSameMomentAs(originalEndsAt), isTrue);
    expect(recovered.effectiveSeconds, const Duration(minutes: 4).inSeconds);
    expect(await focusRepository.getClockReviewCases(), isEmpty);
    expect(recovered.isFailed, isFalse);

    wallTime = originalEndsAt;
    monotonicTime = const Duration(minutes: 6);
    final completed = (await focusRepository.getSession(started.id))!;
    expect(completed.status, FocusSessionStatus.completed);
    expect(completed.completedAt?.isAtSameMomentAs(originalEndsAt), isTrue);
    expect(completed.effectiveSeconds, const Duration(minutes: 10).inSeconds);
    expect(await focusRepository.getClockReviewCases(), isEmpty);
  });

  test('进程停止期间回拨未越过会话开始点也保留待核对证据', () async {
    final task = await createTask('重启后识别设备后跳');
    final started = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 10),
    );
    wallTime = wallTime.add(const Duration(minutes: 4));
    monotonicTime += const Duration(minutes: 4);
    await focusRepository.getSession(started.id);

    await focusRepository.dispose();
    focusRepositories.clear();
    wallTime = wallTime.subtract(const Duration(minutes: 2));
    monotonicTime = Duration.zero;
    focusRepository = _newFocusRepository(
      database: database,
      remote: focusRemote,
      wallTime: () => wallTime,
      monotonicTime: () => monotonicTime,
      register: focusRepositories.add,
    );

    final recovered = (await focusRepository.getActiveSession())!;
    final reviewCase = (await focusRepository.getClockReviewCases()).single;
    expect(recovered.status, FocusSessionStatus.active);
    expect(recovered.isFailed, isFalse);
    expect(recovered.effectiveSeconds, const Duration(minutes: 4).inSeconds);
    expect(reviewCase.direction, FocusClockChangeDirection.backward);
    expect(reviewCase.canAcceptMonotonicEstimate, isFalse);
    expect(reviewCase.interval.isAwaitingClockReview, isTrue);
    expect(
      reviewCase.interval.observedStartedAt,
      started.startedAt.add(const Duration(minutes: 4)),
    );
    expect(reviewCase.interval.observedEndedAt, wallTime);
  });

  test('共享远端跨设备保留待核对与暂缓状态，核对后同步结果和统计', () async {
    final task = await createTask('跨设备核对');
    final started = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 10),
    );
    wallTime = wallTime.add(const Duration(minutes: 1));
    monotonicTime += const Duration(minutes: 1);
    await focusRepository.getSession(started.id);
    wallTime = wallTime.add(const Duration(hours: 1));
    monotonicTime += const Duration(seconds: 1);
    await focusRepository.getSession(started.id);
    wallTime = wallTime.add(const Duration(minutes: 9));
    monotonicTime += const Duration(minutes: 9);
    final completed = (await focusRepository.getSession(started.id))!;
    expect(completed.status, FocusSessionStatus.completed);
    expect(
      completed.effectiveSeconds,
      const Duration(minutes: 9, seconds: 59).inSeconds,
    );
    await taskRepository.sync();
    await focusRepository.sync();

    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    databases.add(secondDatabase);
    final secondTaskRepository = LocalTaskRepository(
      database: secondDatabase,
      userId: 'clock-user',
      remote: taskRemote,
      now: () => wallTime,
    );
    taskRepositories.add(secondTaskRepository);
    final secondMonotonicTime = Duration.zero;
    final secondFocusRepository = _newFocusRepository(
      database: secondDatabase,
      remote: focusRemote,
      wallTime: () => wallTime,
      monotonicTime: () => secondMonotonicTime,
      register: focusRepositories.add,
    );
    await secondTaskRepository.sync();
    await secondFocusRepository.sync();

    final remoteCase =
        (await secondFocusRepository.getClockReviewCases()).single;
    expect(remoteCase.interval.observedStartedAt, isNotNull);
    expect(remoteCase.interval.observedEndedAt, isNotNull);
    expect(remoteCase.interval.measuredDurationSeconds, 1);
    await secondFocusRepository.deferClockReviewCase(remoteCase.id);
    await secondFocusRepository.sync();
    await focusRepository.sync();
    expect(
      (await focusRepository.getClockReviewCases()).single.isDeferred,
      isTrue,
    );

    final syncedDeferred = await focusRemote.pull(userId: 'clock-user');
    final deferredPayload = syncedDeferred.sources
        .where((source) => source.entityId == started.id)
        .map((source) => source.payload)
        .map((payload) => payload)
        .last;
    expect(deferredPayload, contains('"clock_review_status":"deferred"'));
    expect(deferredPayload, contains('"observed_started_at":'));
    expect(deferredPayload, contains('"observed_ended_at":'));

    await secondFocusRepository.resolveClockReviewCase(
      caseId: remoteCase.id,
      decision: FocusClockReviewDecision.acceptMonotonicEstimate,
    );
    await secondFocusRepository.sync();
    await focusRepository.sync();
    expect(await focusRepository.getClockReviewCases(), isEmpty);
    final resolved = (await focusRepository.getSession(started.id))!;
    expect(resolved.effectiveSeconds, const Duration(minutes: 10).inSeconds);
    expect(
      resolved.effectiveIntervals[1].clockReviewStatus,
      FocusClockReviewStatus.resolved,
    );
    final metrics = await focusRepository.getDashboardMetrics(
      deviceTimeZoneId: 'Etc/UTC',
    );
    expect(metrics.focusProgressSecondsByTask[task.id], 10 * 60);
  });
}

LocalFocusRepository _newFocusRepository({
  required PactaDatabase database,
  required InMemoryFocusRemote remote,
  required DateTime Function() wallTime,
  required Duration Function() monotonicTime,
  required void Function(LocalFocusRepository repository) register,
}) {
  final repository = LocalFocusRepository(
    database: database,
    userId: 'clock-user',
    remote: remote,
    now: wallTime,
    monotonicNow: monotonicTime,
  );
  register(repository);
  return repository;
}
