import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/domain/focus_chain_models.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';

void main() {
  final userId = const AppUserId('focus-user');
  final timestamp = DateTime.utc(2026, 8, 24, 9);
  final goal = Goal(
    id: 'goal-1',
    userId: userId,
    title: 'Release',
    createdAt: timestamp,
    updatedAt: timestamp,
  );

  Task task(
    String id,
    TaskChainClassification classification, {
    bool complete = false,
  }) {
    return Task(
      id: id,
      userId: userId,
      goalId: goal.id,
      title: id,
      classification: classification,
      completedAt: complete ? timestamp : null,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  final tasks = [
    task('elite', TaskChainClassification.elite),
    task('regular', TaskChainClassification.regular),
    task('both', TaskChainClassification.both),
    task('completed', TaskChainClassification.elite, complete: true),
  ];

  test('picker filters executable Tasks by the requested classification', () {
    expect(filterTasks(tasks, TaskPickerFilter.all).map((task) => task.id), [
      'elite',
      'regular',
      'both',
    ]);
    expect(filterTasks(tasks, TaskPickerFilter.elite).map((task) => task.id), [
      'elite',
    ]);
    expect(
      filterTasks(tasks, TaskPickerFilter.regular).map((task) => task.id),
      ['regular'],
    );
    expect(filterTasks(tasks, TaskPickerFilter.both).map((task) => task.id), [
      'both',
    ]);
  });

  test(
    'Both classification is eligible for either explicitly selected mode',
    () {
      final both = task('both', TaskChainClassification.both);
      expect(isEligibleForMode(both, FocusChainMode.elite), isTrue);
      expect(isEligibleForMode(both, FocusChainMode.regular), isTrue);
      expect(
        isEligibleForMode(
          task('elite', TaskChainClassification.elite),
          FocusChainMode.regular,
        ),
        isFalse,
      );
    },
  );

  test('classification never determines mode or countdown duration', () {
    expect(
      FocusChainMode.values,
      containsAll([FocusChainMode.elite, FocusChainMode.regular]),
    );
    expect(
      const Duration(minutes: 45),
      isNot(equals(const Duration(minutes: 15))),
    );
    expect(TaskPickerFilter.elite, isNot(equals(FocusChainMode.elite)));
  });
}
