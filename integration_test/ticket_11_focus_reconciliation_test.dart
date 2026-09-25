import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T11 用户在设备上分别选择来源配置和专注结果', (tester) async {
    final userId = 'ticket-11-user';
    final database = PactaDatabase(NativeDatabase.memory());
    final taskRemote = InMemoryTaskRemote();
    final focusRemote = InMemoryFocusRemote();
    final now = DateTime.utc(2026, 9, 25, 12);
    final taskRepository = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: taskRemote,
      now: () => now,
    );
    final focusRepository = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: focusRemote,
      now: () => now,
    );
    final auth = FakeAuthRepository()..signedInUser = userId;

    try {
      final goal = await taskRepository.createGoal(
        const GoalDraft(
          title: 'T11 平板验收',
          classification: TaskClassification.regular,
        ),
      );
      final taskA = await taskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: '设备 A 配置',
          classification: TaskClassification.elite,
        ),
      );
      final taskB = await taskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: '设备 B 配置',
          classification: TaskClassification.regular,
        ),
      );
      await taskRepository.sync();

      final startedA = DateTime.utc(2026, 9, 25, 10);
      final startedB = DateTime.utc(2026, 9, 25, 10, 10);
      final sessionA = _session(
        id: 'tablet-session',
        taskId: taskA.id,
        mode: FocusChainMode.elite,
        startedAt: startedA,
        endedAt: DateTime.utc(2026, 9, 25, 10, 20),
        status: FocusSessionStatus.completed,
        failureReason: null,
      );
      final sessionB = _session(
        id: 'tablet-session',
        taskId: taskB.id,
        mode: FocusChainMode.regular,
        startedAt: startedB,
        endedAt: DateTime.utc(2026, 9, 25, 10, 30),
        status: FocusSessionStatus.failed,
        failureReason: '设备 B 的记录结果',
      );
      await focusRemote.upsertSessions(
        userId: userId,
        sessions: [sessionA, sessionB],
      );
      await focusRemote.upsertSources(
        userId: userId,
        sources: [
          _source(sessionA, 'tablet-source-a', 'tablet-a'),
          _source(sessionB, 'tablet-source-b', 'tablet-b'),
        ],
      );
      await focusRepository.sync();

      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          taskRepositoryFactory: (_) => taskRepository,
          focusRepositoryFactory: (_) => focusRepository,
        ),
      );
      await tester.pumpAndSettle();

      final pendingEntry = find.text('1 组专注记录待核对');
      expect(pendingEntry, findsOneWidget);
      await tester.tap(pendingEntry);
      await tester.pumpAndSettle();
      expect(find.text('同一次专注存在多个来源'), findsOneWidget);
      expect(find.text('选择配置来源'), findsOneWidget);
      expect(find.text('选择专注结果来源'), findsOneWidget);

      final configurationChoice = find.text('设备 A 配置 · 精锐链 · 20分钟');
      await tester.ensureVisible(configurationChoice);
      await tester.tap(configurationChoice);
      await tester.pumpAndSettle();
      final configurationGroup = find
          .ancestor(
            of: configurationChoice,
            matching: find.byType(RadioGroup<String>),
          )
          .first;
      expect(
        tester.widget<RadioGroup<String>>(configurationGroup).groupValue,
        'tablet-source-a',
      );

      final outcomeChoice = find.text('失败：设备 B 的记录结果 · 20分钟有效时间');
      await tester.ensureVisible(outcomeChoice);
      await tester.tap(outcomeChoice);
      await tester.pumpAndSettle();
      final outcomeGroup = find
          .ancestor(
            of: outcomeChoice,
            matching: find.byType(RadioGroup<String>),
          )
          .first;
      expect(
        tester.widget<RadioGroup<String>>(outcomeGroup).groupValue,
        'tablet-source-b',
      );
      final saveButton = find.text('确认并保存核对');
      await tester.ensureVisible(saveButton);
      expect(
        tester
            .widget<FilledButton>(
              find
                  .ancestor(of: saveButton, matching: find.byType(FilledButton))
                  .first,
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('已核对'), findsOneWidget);
      expect(find.textContaining('设备 tablet-a'), findsOneWidget);
      expect(find.textContaining('设备 tablet-b'), findsOneWidget);
      final resolved = (await focusRepository.getSessions()).single;
      expect(resolved.taskId, taskA.id);
      expect(resolved.mode, FocusChainMode.elite);
      expect(resolved.status, FocusSessionStatus.failed);
      expect(resolved.effectiveSeconds, const Duration(minutes: 30).inSeconds);
      expect(await focusRepository.getNodes(), isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await focusRepository.dispose();
      await taskRepository.dispose();
      await database.close();
    }
  });
}

FocusSession _session({
  required String id,
  required String taskId,
  required FocusChainMode mode,
  required DateTime startedAt,
  required DateTime endedAt,
  required FocusSessionStatus status,
  required String? failureReason,
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
  completionType: FocusSessionCompletionType.countdown,
  failureReason: failureReason,
  effectiveIntervals: [
    FocusTimeInterval(startedAt: startedAt, endedAt: endedAt),
  ],
);

FocusSyncSource _source(
  FocusSession session,
  String sourceId,
  String deviceId,
) => FocusSyncSource(
  sourceId: sourceId,
  deviceId: deviceId,
  entityType: 'focus_session',
  entityId: session.id,
  occurredAt: session.completedAt!,
  payload: jsonEncode({
    'id': session.id,
    'appointment_id': session.appointmentId,
    'task_id': session.taskId,
    'mode': session.mode.storageValue,
    'duration_seconds': session.durationSeconds,
    'started_at': session.startedAt.toIso8601String(),
    'ends_at': session.endsAt.toIso8601String(),
    'status': session.status.storageValue,
    'completed_at': session.completedAt!.toIso8601String(),
    'effective_seconds': session.effectiveSeconds,
    'completion_type': session.completionType.storageValue,
    'completion_rule_text': session.completionRuleText,
    'paused_at': session.pausedAt?.toIso8601String(),
    'paused_seconds': session.pausedSeconds,
    'pause_rule_text': session.pauseRuleText,
    'failure_reason': session.failureReason,
    'effective_intervals': [
      {
        'started_at': session.effectiveIntervals.single.startedAt
            .toIso8601String(),
        'ended_at': session.effectiveIntervals.single.endedAt!
            .toIso8601String(),
      },
    ],
    'review_disposition': session.reviewDisposition.storageValue,
    'review_disposition_updated_at': null,
    'configuration_basis_source_id': null,
    'outcome_basis_source_id': null,
  }),
);
