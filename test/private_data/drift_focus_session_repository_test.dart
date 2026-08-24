import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/data/drift_focus_session_repository.dart';
import 'package:pacta/features/focus_chain/domain/focus_chain_models.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_models.dart';
import 'package:pacta/features/goals_tasks/data/drift_goal_task_repository.dart';
import 'package:pacta/features/goals_tasks/data/supabase_goal_task_source.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';
import 'package:pacta/private_data/app_database.dart';

void main() {
  final userId = const AppUserId('session-repository-user');
  final startedAt = DateTime.utc(2026, 8, 24, 9);

  test(
    'zero reconciliation atomically records progress and one Focus Node',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      var now = startedAt;
      final goals = DriftGoalTaskRepository(
        database: database,
        remote: const UnavailableRemoteGoalTaskSource(),
        clock: () => now,
      );
      final goal = await goals.saveGoal(
        userId,
        const GoalDraft(title: 'Session Goal'),
      );
      final task = await goals.saveTask(
        userId,
        TaskDraft(
          goalId: goal.id,
          title: 'Session Task',
          classification: TaskChainClassification.both,
        ),
      );
      final sessions = DriftFocusSessionRepository(
        database: database,
        clock: () => now,
      );
      final config = FocusSessionConfig(
        task: task,
        mode: FocusChainMode.elite,
        duration: const Duration(minutes: 15),
      );

      final started = await sessions.start(userId, config);
      expect(started.isActive, isTrue);
      expect((await sessions.read(userId, started.id))?.isActive, isTrue);

      now = startedAt.add(const Duration(minutes: 15));
      final completed = await sessions.reconcile(userId, started.id);
      expect(completed.outcome, FocusSessionOutcome.completed);
      expect(completed.actualElapsed, const Duration(minutes: 15));
      expect(completed.completedAt, now);

      final snapshot = await goals.read(userId);
      expect(snapshot.tasks.single.focusProgress, const Duration(minutes: 15));
      expect(snapshot.tasks.single.isComplete, isFalse);
      expect(snapshot.isGoalComplete(goal.id), isFalse);
      expect(await sessions.readNodes(userId, started.id), hasLength(1));

      final repeated = await sessions.reconcile(userId, started.id);
      expect(repeated, completed);
      expect(
        (await goals.read(userId)).tasks.single.focusProgress,
        const Duration(minutes: 15),
      );
      expect(await sessions.readNodes(userId, started.id), hasLength(1));
    },
  );

  test('an active Session before zero remains active', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var now = startedAt;
    final goals = DriftGoalTaskRepository(
      database: database,
      remote: const UnavailableRemoteGoalTaskSource(),
      clock: () => now,
    );
    final goal = await goals.saveGoal(userId, const GoalDraft(title: 'Goal'));
    final task = await goals.saveTask(
      userId,
      TaskDraft(
        goalId: goal.id,
        title: 'Task',
        classification: TaskChainClassification.elite,
      ),
    );
    final sessions = DriftFocusSessionRepository(
      database: database,
      clock: () => now,
    );
    final started = await sessions.start(
      userId,
      FocusSessionConfig(
        task: task,
        mode: FocusChainMode.elite,
        duration: const Duration(minutes: 10),
      ),
    );

    now = startedAt.add(const Duration(minutes: 9, seconds: 59));
    final stillActive = await sessions.reconcile(userId, started.id);
    expect(stillActive.isActive, isTrue);
    expect(await sessions.readNodes(userId, started.id), isEmpty);
  });
}
