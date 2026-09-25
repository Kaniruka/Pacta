import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  group('T11 专注记录核对', () {
    late PactaDatabase database;
    late InMemoryTaskRemote taskRemote;
    late InMemoryFocusRemote focusRemote;
    late LocalTaskRepository taskRepository;
    late LocalFocusRepository focusRepository;
    late DateTime now;
    late Task taskA;
    late Task taskB;
    late Task taskC;

    setUp(() async {
      database = PactaDatabase(NativeDatabase.memory());
      taskRemote = InMemoryTaskRemote();
      focusRemote = InMemoryFocusRemote();
      now = DateTime.utc(2026, 9, 25, 12);
      taskRepository = LocalTaskRepository(
        database: database,
        userId: 't11-user',
        remote: taskRemote,
        now: () => now,
      );
      focusRepository = LocalFocusRepository(
        database: database,
        userId: 't11-user',
        remote: focusRemote,
        now: () => now,
      );
      addTearDown(focusRepository.dispose);
      addTearDown(taskRepository.dispose);
      addTearDown(database.close);

      final goal = await taskRepository.createGoal(
        const GoalDraft(
          title: 'T11 核对目标',
          classification: TaskClassification.regular,
        ),
      );
      taskA = await taskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: '设备 A 的任务',
          classification: TaskClassification.elite,
        ),
      );
      taskB = await taskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: '设备 B 的任务',
          classification: TaskClassification.regular,
        ),
      );
      taskC = await taskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: '无争议任务',
          classification: TaskClassification.regular,
        ),
      );
      await taskRepository.sync();
    });

    test('来源配置和结果分别选择，同次会话时间按并集合并并可跨设备查询', () async {
      final startedA = DateTime.utc(2026, 9, 25, 10);
      final startedB = DateTime.utc(2026, 9, 25, 10, 10);
      final sessionA = _session(
        id: 'same-session',
        taskId: taskA.id,
        mode: FocusChainMode.elite,
        startedAt: startedA,
        endedAt: DateTime.utc(2026, 9, 25, 10, 20),
        status: FocusSessionStatus.completed,
        completionType: FocusSessionCompletionType.countdown,
      );
      final sessionB = _session(
        id: 'same-session',
        taskId: taskB.id,
        mode: FocusChainMode.regular,
        startedAt: startedB,
        endedAt: DateTime.utc(2026, 9, 25, 10, 30),
        status: FocusSessionStatus.failed,
        completionType: FocusSessionCompletionType.countdown,
        failureReason: '设备 B 记录为失败',
      );
      await _seedSessionSources(
        focusRemote,
        [sessionA, sessionB],
        ['source-a', 'source-b'],
      );

      await focusRepository.sync();
      var reconciliations = await focusRepository.getFocusReconciliations();
      expect(reconciliations, hasLength(1));
      final pending = reconciliations.single;
      expect(pending.isPendingReview, isTrue);
      expect(pending.sessions.single.requiresConfigurationChoice, isTrue);
      expect(pending.sessions.single.requiresOutcomeChoice, isTrue);

      await focusRepository.resolveFocusReconciliation(
        caseId: pending.id,
        sessionSelections: {
          'same-session': const FocusSessionReconciliationSelection(
            configurationSourceId: 'source-a',
            outcomeSourceId: 'source-b',
          ),
        },
      );

      final resolved = (await focusRepository.getSessions()).single;
      expect(resolved.taskId, taskA.id);
      expect(resolved.mode, FocusChainMode.elite);
      expect(resolved.durationSeconds, const Duration(minutes: 20).inSeconds);
      expect(resolved.status, FocusSessionStatus.failed);
      expect(resolved.effectiveSeconds, const Duration(minutes: 30).inSeconds);
      expect(resolved.effectiveIntervals, hasLength(1));
      expect(resolved.effectiveIntervals.single.startedAt, startedA);
      expect(
        resolved.effectiveIntervals.single.endedAt,
        DateTime.utc(2026, 9, 25, 10, 30),
      );
      expect(await focusRepository.getNodes(), isEmpty);
      expect(
        (await taskRepository.getGoals()).single.tasks
            .singleWhere((task) => task.id == taskA.id)
            .focusProgressSeconds,
        const Duration(minutes: 30).inSeconds,
      );
      expect(
        (await taskRepository.getGoals()).single.tasks
            .singleWhere((task) => task.id == taskB.id)
            .focusProgressSeconds,
        0,
      );
      expect(
        (await focusRepository.getChainRecords())
            .singleWhere((record) => record.mode == FocusChainMode.elite)
            .currentConsecutive,
        0,
      );
      expect(
        (await focusRepository.getDashboardMetrics(deviceTimeZoneId: 'Etc/UTC'))
            .totalAcceptedFocusSeconds,
        const Duration(minutes: 30).inSeconds,
      );

      await focusRepository.sync();
      final mergedSource = (await focusRemote.pull(userId: 't11-user')).sources
          .singleWhere(
            (source) =>
                source.entityType == 'focus_session' &&
                source.entityId == 'same-session' &&
                source.parentSourceIds.length == 2,
          );
      expect(mergedSource.parentSourceIds.toSet(), {'source-a', 'source-b'});

      final secondDatabase = PactaDatabase(NativeDatabase.memory());
      final secondTaskRepository = LocalTaskRepository(
        database: secondDatabase,
        userId: 't11-user',
        remote: taskRemote,
        now: () => now,
      );
      final secondFocusRepository = LocalFocusRepository(
        database: secondDatabase,
        userId: 't11-user',
        remote: focusRemote,
        now: () => now,
      );
      addTearDown(secondFocusRepository.dispose);
      addTearDown(secondTaskRepository.dispose);
      addTearDown(secondDatabase.close);
      await secondTaskRepository.sync();
      await secondFocusRepository.sync();

      final remoteResolved = (await secondFocusRepository.getSessions()).single;
      expect(remoteResolved.status, FocusSessionStatus.failed);
      expect(remoteResolved.reviewDisposition, FocusRecordDisposition.accepted);
      expect(
        remoteResolved.effectiveSeconds,
        const Duration(minutes: 30).inSeconds,
      );
      expect(
        (await secondFocusRepository.getFocusReconciliations())
            .single
            .isPendingReview,
        isFalse,
      );
      await secondFocusRepository.sync();
      expect(
        (await secondTaskRepository.getGoals()).single.tasks
            .singleWhere((task) => task.id == taskA.id)
            .focusProgressSeconds,
        const Duration(minutes: 30).inSeconds,
      );
    });

    test('重叠的不同会话由用户选采用者，重复记录不计时、不造节点、不重置链', () async {
      final acceptedPrior = _session(
        id: 'prior-regular-session',
        taskId: taskC.id,
        mode: FocusChainMode.regular,
        startedAt: DateTime.utc(2026, 9, 25, 9),
        endedAt: DateTime.utc(2026, 9, 25, 9, 10),
        status: FocusSessionStatus.completed,
        completionType: FocusSessionCompletionType.countdown,
      );
      final sessionA = _session(
        id: 'overlap-a',
        taskId: taskA.id,
        mode: FocusChainMode.elite,
        startedAt: DateTime.utc(2026, 9, 25, 10),
        endedAt: DateTime.utc(2026, 9, 25, 10, 20),
        status: FocusSessionStatus.completed,
        completionType: FocusSessionCompletionType.countdown,
      );
      final sessionB = _session(
        id: 'overlap-b',
        taskId: taskB.id,
        mode: FocusChainMode.regular,
        startedAt: DateTime.utc(2026, 9, 25, 10, 10),
        endedAt: DateTime.utc(2026, 9, 25, 10, 30),
        status: FocusSessionStatus.completed,
        completionType: FocusSessionCompletionType.countdown,
      );
      await _seedSessionSources(
        focusRemote,
        [acceptedPrior, sessionA, sessionB],
        ['source-prior', 'source-overlap-a', 'source-overlap-b'],
      );

      await focusRepository.sync();
      var reconciliations = await focusRepository.getFocusReconciliations();
      expect(reconciliations, hasLength(1));
      expect(reconciliations.single.isPendingReview, isTrue);
      expect(reconciliations.single.sessions, hasLength(2));
      expect(
        (await taskRepository.getGoals()).single.tasks
            .where((task) => task.id != taskC.id)
            .every((task) => task.focusProgressSeconds == 0),
        isTrue,
      );

      await focusRepository.resolveFocusReconciliation(
        caseId: reconciliations.single.id,
        adoptedSessionId: 'overlap-a',
        sessionSelections: const {
          'overlap-a': FocusSessionReconciliationSelection(),
          'overlap-b': FocusSessionReconciliationSelection(),
        },
      );

      final sessions = {
        for (final session in await focusRepository.getSessions())
          session.id: session,
      };
      expect(
        sessions['overlap-a']!.reviewDisposition,
        FocusRecordDisposition.accepted,
      );
      expect(
        sessions['overlap-b']!.reviewDisposition,
        FocusRecordDisposition.duplicate,
      );
      expect(await focusRepository.getNodes(), hasLength(2));
      final tasks = (await taskRepository.getGoals()).single.tasks;
      expect(
        tasks.singleWhere((task) => task.id == taskA.id).focusProgressSeconds,
        const Duration(minutes: 20).inSeconds,
      );
      expect(
        tasks.singleWhere((task) => task.id == taskB.id).focusProgressSeconds,
        0,
      );
      expect(
        tasks.singleWhere((task) => task.id == taskC.id).focusProgressSeconds,
        const Duration(minutes: 10).inSeconds,
      );
      final chainRecords = await focusRepository.getChainRecords();
      expect(
        chainRecords
            .singleWhere((record) => record.mode == FocusChainMode.regular)
            .currentConsecutive,
        1,
      );
      expect(
        (await focusRepository.getDashboardMetrics(deviceTimeZoneId: 'Etc/UTC'))
            .totalAcceptedFocusSeconds,
        const Duration(minutes: 30).inSeconds,
      );

      await focusRepository.sync();
      await focusRepository.sync();
      await focusRepository.sync();
      reconciliations = await focusRepository.getFocusReconciliations();
      expect(reconciliations, hasLength(1));
      expect(reconciliations.single.isPendingReview, isFalse);
      expect(
        (await focusRepository.getNodes()).map((node) => node.sessionId),
        containsAll(['prior-regular-session', 'overlap-a']),
      );
    });

    test('不同来源的时间并集会触发与另一会话的重叠核对', () async {
      final sessionShort = _session(
        id: 'branched-session',
        taskId: taskA.id,
        mode: FocusChainMode.elite,
        startedAt: DateTime.utc(2026, 9, 25, 9),
        endedAt: DateTime.utc(2026, 9, 25, 9, 5),
        status: FocusSessionStatus.completed,
        completionType: FocusSessionCompletionType.countdown,
      );
      final sessionLong = _session(
        id: 'branched-session',
        taskId: taskA.id,
        mode: FocusChainMode.elite,
        startedAt: DateTime.utc(2026, 9, 25, 9),
        endedAt: DateTime.utc(2026, 9, 25, 9, 40),
        status: FocusSessionStatus.completed,
        completionType: FocusSessionCompletionType.countdown,
      );
      final overlappingSession = _session(
        id: 'other-session',
        taskId: taskB.id,
        mode: FocusChainMode.regular,
        startedAt: DateTime.utc(2026, 9, 25, 9, 30),
        endedAt: DateTime.utc(2026, 9, 25, 9, 45),
        status: FocusSessionStatus.completed,
        completionType: FocusSessionCompletionType.countdown,
      );
      await focusRemote.upsertSessions(
        userId: 't11-user',
        sessions: [sessionShort, overlappingSession],
      );
      await focusRemote.upsertSources(
        userId: 't11-user',
        sources: [
          for (final (sourceId, session) in [
            ('source-a-short', sessionShort),
            ('source-b-long', sessionLong),
            ('source-c-other', overlappingSession),
          ])
            FocusSyncSource(
              sourceId: sourceId,
              deviceId: 'device-$sourceId',
              entityType: 'focus_session',
              entityId: session.id,
              occurredAt: session.completedAt!,
              payload: jsonEncode(_sessionPayload(session)),
            ),
        ],
      );

      await focusRepository.sync();

      final sessionsById = {
        for (final session in await focusRepository.getSessions())
          session.id: session,
      };
      expect(
        sessionsById['other-session']!.reviewDisposition,
        FocusRecordDisposition.pendingReview,
      );
      final reconciliation =
          (await focusRepository.getFocusReconciliations()).single;
      expect(reconciliation.isPendingReview, isTrue);
      expect(
        reconciliation.sessions.map((entry) => entry.session.id),
        containsAll(['branched-session', 'other-session']),
      );
    });
  });
}

Future<void> _seedSessionSources(
  FocusRemoteDataSource remote,
  List<FocusSession> sessions,
  List<String> sourceIds,
) async {
  await remote.upsertSessions(userId: 't11-user', sessions: sessions);
  await remote.upsertSources(
    userId: 't11-user',
    sources: [
      for (var index = 0; index < sessions.length; index++)
        FocusSyncSource(
          sourceId: sourceIds[index],
          deviceId: 'device-${sourceIds[index]}',
          entityType: 'focus_session',
          entityId: sessions[index].id,
          occurredAt: sessions[index].completedAt!,
          payload: jsonEncode(_sessionPayload(sessions[index])),
        ),
    ],
  );
}

FocusSession _session({
  required String id,
  required String taskId,
  required FocusChainMode mode,
  required DateTime startedAt,
  required DateTime endedAt,
  required FocusSessionStatus status,
  required FocusSessionCompletionType completionType,
  String? failureReason,
}) => FocusSession(
  id: id,
  taskId: taskId,
  mode: mode,
  durationSeconds: const Duration(minutes: 20).inSeconds,
  startedAt: startedAt,
  endsAt: startedAt.add(const Duration(minutes: 20)),
  status: status,
  completedAt: endedAt,
  effectiveSeconds: endedAt.difference(startedAt).inSeconds,
  completionType: completionType,
  failureReason: failureReason,
  effectiveIntervals: [
    FocusTimeInterval(startedAt: startedAt, endedAt: endedAt),
  ],
);

Map<String, Object?> _sessionPayload(FocusSession session) => {
  'id': session.id,
  'appointment_id': session.appointmentId,
  'task_id': session.taskId,
  'mode': session.mode.storageValue,
  'duration_seconds': session.durationSeconds,
  'started_at': session.startedAt.toIso8601String(),
  'ends_at': session.endsAt.toIso8601String(),
  'status': session.status.storageValue,
  'completed_at': session.completedAt?.toIso8601String(),
  'effective_seconds': session.effectiveSeconds,
  'completion_type': session.completionType.storageValue,
  'completion_rule_text': session.completionRuleText,
  'paused_at': session.pausedAt?.toIso8601String(),
  'paused_seconds': session.pausedSeconds,
  'pause_rule_text': session.pauseRuleText,
  'failure_reason': session.failureReason,
  'effective_intervals': [
    for (final interval in session.effectiveIntervals)
      {
        'started_at': interval.startedAt.toIso8601String(),
        'ended_at': interval.endedAt?.toIso8601String(),
      },
  ],
  'review_disposition': session.reviewDisposition.storageValue,
  'review_disposition_updated_at': session.reviewDispositionUpdatedAt
      ?.toIso8601String(),
  'configuration_basis_source_id': session.configurationBasisSourceId,
  'outcome_basis_source_id': session.outcomeBasisSourceId,
};
