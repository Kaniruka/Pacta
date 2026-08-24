import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';

void main() {
  final userId = const AppUserId('user-a');
  final createdAt = DateTime.utc(2026, 8, 24, 9);

  Goal goal() => Goal(
    id: 'goal-1',
    userId: userId,
    title: 'Ship the release',
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  Task task({String id = 'task-1', DateTime? completedAt}) => Task(
    id: id,
    userId: userId,
    goalId: 'goal-1',
    title: 'Write the changelog',
    classification: TaskChainClassification.both,
    estimatedDuration: const Duration(minutes: 30),
    focusProgress: const Duration(minutes: 30),
    completedAt: completedAt,
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  test('accepts exactly the three Task Chain classifications', () {
    expect(TaskChainClassification.values, hasLength(3));
    expect(TaskChainClassification.elite.wireValue, 'elite');
    expect(TaskChainClassification.regular.wireValue, 'regular');
    expect(TaskChainClassification.both.wireValue, 'both');
  });

  test('Focus Progress never completes a Task or its Goal', () {
    final snapshot = GoalTaskSnapshot(goals: [goal()], tasks: [task()]);

    expect(snapshot.tasks.single.isComplete, isFalse);
    expect(snapshot.isGoalComplete('goal-1'), isFalse);

    final exceeded = task().copyWith(focusProgress: const Duration(hours: 2));
    final exceededSnapshot = GoalTaskSnapshot(
      goals: [goal()],
      tasks: [exceeded],
    );
    expect(exceededSnapshot.tasks.single.isComplete, isFalse);
    expect(exceededSnapshot.isGoalComplete('goal-1'), isFalse);
  });

  test('a Goal completes only when every Task is explicitly complete', () {
    final first = task();
    final second = task(id: 'task-2');
    final snapshot = GoalTaskSnapshot(goals: [goal()], tasks: [first, second]);
    expect(snapshot.isGoalComplete('goal-1'), isFalse);

    final completed = GoalTaskSnapshot(
      goals: [goal()],
      tasks: [
        first.copyWith(completedAt: createdAt.add(const Duration(minutes: 1))),
        second.copyWith(completedAt: createdAt.add(const Duration(minutes: 2))),
      ],
    );
    expect(completed.isGoalComplete('goal-1'), isTrue);

    final reopened = GoalTaskSnapshot(
      goals: completed.goals,
      tasks: [
        completed.tasks.first.copyWith(completedAt: null),
        completed.tasks.last,
      ],
    );
    expect(reopened.isGoalComplete('goal-1'), isFalse);
  });

  test('matches the synchronized field length limits locally', () {
    expect(
      () => Goal(
        id: 'long-goal',
        userId: userId,
        title: 'x' * 241,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsArgumentError,
    );
    expect(
      () => Goal(
        id: 'long-notes',
        userId: userId,
        title: 'Valid title',
        notes: 'x' * 4001,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsArgumentError,
    );
  });

  test('GoalTaskSnapshot rejects a Task from another Goal', () {
    expect(
      () => GoalTaskSnapshot(
        goals: [goal()],
        tasks: [task().copyWith(goalId: 'other-goal')],
      ),
      throwsArgumentError,
    );
  });
}
