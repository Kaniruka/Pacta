enum TaskClassification {
  elite,
  regular,
  both;

  String get storageValue => switch (this) {
    TaskClassification.elite => 'elite',
    TaskClassification.regular => 'regular',
    TaskClassification.both => 'both',
  };

  String get label => switch (this) {
    TaskClassification.elite => '精锐',
    TaskClassification.regular => '普通',
    TaskClassification.both => '两者',
  };

  static TaskClassification fromStorage(String value) => switch (value) {
    'elite' => TaskClassification.elite,
    'regular' => TaskClassification.regular,
    'both' => TaskClassification.both,
    _ => throw ArgumentError('Unknown task classification: $value'),
  };
}

class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.classification,
    required this.createdAt,
    required this.updatedAt,
    this.tasks = const [],
  });

  final String id;
  final String title;
  final TaskClassification classification;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Task> tasks;

  bool get isComplete =>
      tasks.isNotEmpty && tasks.every((task) => task.isComplete);

  Goal copyWith({
    String? title,
    TaskClassification? classification,
    DateTime? updatedAt,
    List<Task>? tasks,
  }) {
    return Goal(
      id: id,
      title: title ?? this.title,
      classification: classification ?? this.classification,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tasks: tasks ?? this.tasks,
    );
  }
}

class Task {
  const Task({
    required this.id,
    required this.goalId,
    required this.title,
    required this.classification,
    required this.estimatedMinutes,
    required this.deadline,
    required this.isComplete,
    this.focusProgressSeconds = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String goalId;
  final String title;
  final TaskClassification classification;
  final int? estimatedMinutes;
  final DateTime? deadline;
  final bool isComplete;
  final int focusProgressSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;

  Task copyWith({
    String? title,
    TaskClassification? classification,
    Object? estimatedMinutes = _unchanged,
    Object? deadline = _unchanged,
    bool? isComplete,
    int? focusProgressSeconds,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id,
      goalId: goalId,
      title: title ?? this.title,
      classification: classification ?? this.classification,
      estimatedMinutes: identical(estimatedMinutes, _unchanged)
          ? this.estimatedMinutes
          : estimatedMinutes as int?,
      deadline: identical(deadline, _unchanged)
          ? this.deadline
          : deadline as DateTime?,
      isComplete: isComplete ?? this.isComplete,
      focusProgressSeconds: focusProgressSeconds ?? this.focusProgressSeconds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

const _unchanged = Object();

class GoalDraft {
  const GoalDraft({required this.title, required this.classification});

  final String title;
  final TaskClassification classification;
}

class TaskDraft {
  const TaskDraft({
    required this.title,
    this.classification,
    this.estimatedMinutes,
    this.deadline,
  });

  final String title;
  final TaskClassification? classification;
  final int? estimatedMinutes;
  final DateTime? deadline;
}
