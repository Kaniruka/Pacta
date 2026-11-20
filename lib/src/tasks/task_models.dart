import 'package:characters/characters.dart';

const taskDescriptionMaxGraphemes = 200;

String normalizeDescription(String description) {
  final normalized = description
      .replaceAll(RegExp(r'\r\n|\r|\n|\u000b|\u000c|\u0085|\u2028|\u2029'), ' ')
      .trim();
  if (normalized.characters.length > taskDescriptionMaxGraphemes) {
    throw ArgumentError('描述不能超过$taskDescriptionMaxGraphemes个用户可见字符。');
  }
  return normalized;
}

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
    this.description = '',
    required this.classification,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isPinned = false,
    this.sortOrder,
    this.tasks = const [],
    this.hasManualTaskOrder = false,
  });

  final String id;
  final String title;
  final String description;
  final TaskClassification classification;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Account data: the goal appears in the board's pinned summary block.
  final bool isPinned;

  /// Manual position among pinned or unpinned goals; null until reordered.
  final int? sortOrder;
  final List<Task> tasks;

  /// Whether [tasks] already carries the user's own unfinished-task order.
  ///
  /// The repository sets this after applying a saved manual order; [nextTask]
  /// then projects the first unfinished row instead of re-deriving a deadline
  /// ranking. It is a projection flag, never persisted.
  final bool hasManualTaskOrder;

  bool get isComplete =>
      tasks.isNotEmpty && tasks.every((task) => task.isComplete);
  bool get isDeleted => deletedAt != null;

  /// Read-only board projection: the earliest unfinished deadline first, then
  /// unfinished tasks without a deadline, then creation time and stable id.
  /// Never a completion signal; picking a task does not change its state.
  Task? get nextTask {
    if (hasManualTaskOrder) {
      // 手动顺序是用户显式表达的“下一步”：直接取列表中的第一个未完成任务，
      // 不再按截止时间重新挑选。
      for (final task in tasks) {
        if (!task.isComplete) return task;
      }
      return null;
    }
    Task? best;
    for (final task in tasks) {
      if (task.isComplete) continue;
      if (best == null || _before(task, best)) best = task;
    }
    return best;
  }

  static bool _before(Task candidate, Task current) {
    final candidateDeadline = candidate.deadline;
    final currentDeadline = current.deadline;
    if ((candidateDeadline == null) != (currentDeadline == null)) {
      return candidateDeadline != null;
    }
    if (candidateDeadline != null && currentDeadline != null) {
      final byDeadline = candidateDeadline.compareTo(currentDeadline);
      if (byDeadline != 0) return byDeadline < 0;
    }
    final byCreated = candidate.createdAt.compareTo(current.createdAt);
    if (byCreated != 0) return byCreated < 0;
    return candidate.id.compareTo(current.id) < 0;
  }

  Goal copyWith({
    String? title,
    String? description,
    TaskClassification? classification,
    DateTime? updatedAt,
    List<Task>? tasks,
    bool? isPinned,
    Object? sortOrder = _unchanged,
    Object? deletedAt = _unchanged,
    bool? hasManualTaskOrder,
  }) {
    return Goal(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      classification: classification ?? this.classification,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      sortOrder: identical(sortOrder, _unchanged)
          ? this.sortOrder
          : sortOrder as int?,
      deletedAt: identical(deletedAt, _unchanged)
          ? this.deletedAt
          : deletedAt as DateTime?,
      tasks: tasks ?? this.tasks,
      hasManualTaskOrder: hasManualTaskOrder ?? this.hasManualTaskOrder,
    );
  }
}

class Task {
  const Task({
    required this.id,
    required this.goalId,
    required this.title,
    this.description = '',
    required this.classification,
    required this.estimatedMinutes,
    required this.deadline,
    required this.isComplete,
    this.focusProgressSeconds = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String goalId;
  final String title;
  final String description;
  final TaskClassification classification;
  final int? estimatedMinutes;
  final DateTime? deadline;
  final bool isComplete;
  final int focusProgressSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  Task copyWith({
    String? title,
    String? description,
    TaskClassification? classification,
    Object? estimatedMinutes = _unchanged,
    Object? deadline = _unchanged,
    bool? isComplete,
    int? focusProgressSeconds,
    DateTime? updatedAt,
    Object? deletedAt = _unchanged,
  }) {
    return Task(
      id: id,
      goalId: goalId,
      title: title ?? this.title,
      description: description ?? this.description,
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
      deletedAt: identical(deletedAt, _unchanged)
          ? this.deletedAt
          : deletedAt as DateTime?,
    );
  }
}

const _unchanged = Object();

class GoalDraft {
  const GoalDraft({
    required this.title,
    this.description = '',
    required this.classification,
  });

  final String title;
  final String description;
  final TaskClassification classification;
}

class TaskDraft {
  const TaskDraft({
    required this.title,
    this.description = '',
    this.classification,
    this.estimatedMinutes,
    this.deadline,
  });

  final String title;
  final String description;
  final TaskClassification? classification;
  final int? estimatedMinutes;
  final DateTime? deadline;
}
