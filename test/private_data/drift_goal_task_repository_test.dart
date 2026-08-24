import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/goals_tasks/data/drift_goal_task_repository.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_repository.dart';
import 'package:pacta/private_data/app_database.dart';

void main() {
  final userA = const AppUserId('user-a');
  final userB = const AppUserId('user-b');
  final now = DateTime.utc(2026, 8, 24, 9);

  test('persists Goal and Task CRUD with explicit completion', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final remote = _RecordingRemote();
    final repository = DriftGoalTaskRepository(
      database: database,
      remote: remote,
      clock: () => now,
    );

    final goal = await repository.saveGoal(
      userA,
      const GoalDraft(title: 'Ship release', notes: 'Small steps'),
    );
    final task = await repository.saveTask(
      userA,
      TaskDraft(
        goalId: goal.id,
        title: 'Write changelog',
        classification: TaskChainClassification.regular,
        estimatedDuration: const Duration(minutes: 30),
      ),
    );
    final progressed = await repository.setFocusProgress(
      userA,
      task.id,
      const Duration(minutes: 30),
    );

    expect(progressed.isComplete, isFalse);
    expect((await repository.read(userA)).isGoalComplete(goal.id), isFalse);

    await repository.setTaskCompleted(userA, task.id, true);
    final complete = await repository.read(userA);
    expect(complete.tasks.single.isComplete, isTrue);
    expect(complete.isGoalComplete(goal.id), isTrue);
  });

  test('keeps Goal and Task records private to their User', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftGoalTaskRepository(
      database: database,
      remote: _RecordingRemote(),
      clock: () => now,
    );

    await repository.saveGoal(userA, const GoalDraft(title: 'Alpha goal'));
    await repository.saveGoal(userB, const GoalDraft(title: 'Beta goal'));

    expect((await repository.read(userA)).goals.single.title, 'Alpha goal');
    expect((await repository.read(userB)).goals.single.title, 'Beta goal');
  });

  test('synchronizes offline mutations without losing local state', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final remote = _RecordingRemote();
    final repository = DriftGoalTaskRepository(
      database: database,
      remote: remote,
      clock: () => now,
    );

    await repository.saveGoal(userA, const GoalDraft(title: 'Offline goal'));
    await repository.sync(userA);

    expect(remote.calls, hasLength(1));
    expect(remote.calls.single.single.entityType, 'goal');
    expect((await repository.read(userA)).goals.single.title, 'Offline goal');
  });
}

class _RecordingRemote implements RemoteGoalTaskSource {
  final calls = <List<GoalTaskMutation>>[];

  @override
  Future<RemoteGoalTaskSnapshot> exchange(
    AppUserId userId,
    List<GoalTaskMutation> mutations,
  ) async {
    calls.add(mutations);
    return RemoteGoalTaskSnapshot(
      goals: const [],
      tasks: const [],
      acceptedMutationIds: mutations
          .map((mutation) => mutation.mutationId)
          .toSet(),
    );
  }
}
