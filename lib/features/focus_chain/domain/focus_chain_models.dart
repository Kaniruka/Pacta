import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';

enum FocusChainMode {
  elite,
  regular;

  String get label => switch (this) {
    elite => 'Elite',
    regular => 'Regular',
  };
}

enum TaskPickerFilter {
  all,
  elite,
  regular,
  both;

  String get label => switch (this) {
    all => 'All eligible',
    elite => 'Elite',
    regular => 'Regular',
    both => 'Both',
  };
}

List<Task> filterTasks(Iterable<Task> tasks, TaskPickerFilter filter) {
  return tasks
      .where((task) => !task.isComplete)
      .where((task) {
        return switch (filter) {
          TaskPickerFilter.all => true,
          TaskPickerFilter.elite =>
            task.classification == TaskChainClassification.elite,
          TaskPickerFilter.regular =>
            task.classification == TaskChainClassification.regular,
          TaskPickerFilter.both =>
            task.classification == TaskChainClassification.both,
        };
      })
      .toList(growable: false);
}

bool isEligibleForMode(Task task, FocusChainMode mode) {
  if (task.isComplete) return false;
  return task.classification == TaskChainClassification.both ||
      switch (mode) {
        FocusChainMode.elite =>
          task.classification == TaskChainClassification.elite,
        FocusChainMode.regular =>
          task.classification == TaskChainClassification.regular,
      };
}

bool hasEligibleTask(Iterable<Task> tasks, FocusChainMode mode) =>
    tasks.any((task) => isEligibleForMode(task, mode));
