import 'package:flutter/foundation.dart';
import 'package:pacta/auth/auth_session.dart';

const _unset = Object();

/// The only Focus Chain classifications a Task may carry.
enum TaskChainClassification {
  elite,
  regular,
  both;

  String get wireValue => switch (this) {
    elite => 'elite',
    regular => 'regular',
    both => 'both',
  };

  String get label => switch (this) {
    elite => 'Elite',
    regular => 'Regular',
    both => 'Both',
  };

  static TaskChainClassification fromWireValue(String value) {
    return switch (value) {
      'elite' => elite,
      'regular' => regular,
      'both' => both,
      _ => throw ArgumentError.value(value, 'value', 'Unknown classification'),
    };
  }
}

@immutable
class Goal {
  Goal({
    required this.id,
    required this.userId,
    required String title,
    String? notes,
    this.mutationId = '',
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : title = _requiredText(title, 'title'),
       notes = _optionalText(notes, 'notes'),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  final String id;
  final AppUserId userId;
  final String title;
  final String? notes;
  final String mutationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool isComplete(Iterable<Task> tasks) {
    final goalTasks = tasks.where((task) => task.goalId == id);
    return goalTasks.isNotEmpty && goalTasks.every((task) => task.isComplete);
  }

  Goal copyWith({
    String? title,
    Object? notes = _unset,
    String? mutationId,
    DateTime? updatedAt,
  }) {
    return Goal(
      id: id,
      userId: userId,
      title: title ?? this.title,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      mutationId: mutationId ?? this.mutationId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Goal &&
        other.id == id &&
        other.userId == userId &&
        other.title == title &&
        other.notes == notes &&
        other.mutationId == mutationId &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      Object.hash(id, userId, title, notes, mutationId, createdAt, updatedAt);
}

@immutable
class Task {
  Task({
    required this.id,
    required this.userId,
    required this.goalId,
    required String title,
    String? notes,
    this.mutationId = '',
    DateTime? deadline,
    Duration? estimatedDuration,
    required this.classification,
    Duration focusProgress = Duration.zero,
    DateTime? completedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : title = _requiredText(title, 'title'),
       notes = _optionalText(notes, 'notes'),
       deadline = deadline?.toUtc(),
       estimatedDuration = _positiveOrNull(
         estimatedDuration,
         'estimatedDuration',
       ),
       focusProgress = _nonNegative(focusProgress, 'focusProgress'),
       completedAt = completedAt?.toUtc(),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  final String id;
  final AppUserId userId;
  final String goalId;
  final String title;
  final String? notes;
  final String mutationId;
  final DateTime? deadline;
  final Duration? estimatedDuration;
  final TaskChainClassification classification;
  final Duration focusProgress;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isComplete => completedAt != null;
  int get estimatedSeconds => estimatedDuration?.inSeconds ?? 0;
  int get focusProgressSeconds => focusProgress.inSeconds;

  Task copyWith({
    String? goalId,
    String? title,
    Object? notes = _unset,
    Object? deadline = _unset,
    String? mutationId,
    Duration? estimatedDuration,
    TaskChainClassification? classification,
    Duration? focusProgress,
    Object? completedAt = _unset,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id,
      userId: userId,
      goalId: goalId ?? this.goalId,
      title: title ?? this.title,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      deadline: identical(deadline, _unset)
          ? this.deadline
          : deadline as DateTime?,
      mutationId: mutationId ?? this.mutationId,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      classification: classification ?? this.classification,
      focusProgress: focusProgress ?? this.focusProgress,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Task &&
        other.id == id &&
        other.userId == userId &&
        other.goalId == goalId &&
        other.title == title &&
        other.notes == notes &&
        other.mutationId == mutationId &&
        other.deadline == deadline &&
        other.estimatedDuration == estimatedDuration &&
        other.classification == classification &&
        other.focusProgress == focusProgress &&
        other.completedAt == completedAt &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    goalId,
    title,
    notes,
    mutationId,
    deadline,
    estimatedDuration,
    classification,
    focusProgress,
    completedAt,
    createdAt,
    updatedAt,
  );
}

@immutable
class GoalTaskSnapshot {
  GoalTaskSnapshot({
    required Iterable<Goal> goals,
    required Iterable<Task> tasks,
  }) : goals = List.unmodifiable(goals),
       tasks = List.unmodifiable(tasks) {
    final goalsById = {for (final goal in this.goals) goal.id: goal};
    if (goalsById.length != this.goals.length) {
      throw ArgumentError('A snapshot cannot contain duplicate Goals.');
    }
    final taskIds = <String>{};
    for (final task in this.tasks) {
      if (!taskIds.add(task.id)) {
        throw ArgumentError('A snapshot cannot contain duplicate Tasks.');
      }
      final goal = goalsById[task.goalId];
      if (goal == null || goal.userId != task.userId) {
        throw ArgumentError(
          'Every Task must belong to a Goal owned by the same User.',
        );
      }
    }
  }

  final List<Goal> goals;
  final List<Task> tasks;

  static final empty = GoalTaskSnapshot(goals: const [], tasks: const []);

  List<Task> tasksForGoal(String goalId) =>
      tasks.where((task) => task.goalId == goalId).toList(growable: false);

  List<Task> get executableTasks =>
      tasks.where((task) => !task.isComplete).toList(growable: false);

  bool isGoalComplete(String goalId) {
    final goal = goals.firstWhere((candidate) => candidate.id == goalId);
    return goal.isComplete(tasks);
  }

  GoalTaskSnapshot copyWith({Iterable<Goal>? goals, Iterable<Task>? tasks}) {
    return GoalTaskSnapshot(
      goals: goals ?? this.goals,
      tasks: tasks ?? this.tasks,
    );
  }
}

@immutable
class GoalDraft {
  const GoalDraft({this.id, required this.title, this.notes});

  final String? id;
  final String title;
  final String? notes;
}

@immutable
class TaskDraft {
  const TaskDraft({
    this.id,
    required this.goalId,
    required this.title,
    this.notes,
    this.deadline,
    this.estimatedDuration,
    required this.classification,
  });

  final String? id;
  final String goalId;
  final String title;
  final String? notes;
  final DateTime? deadline;
  final Duration? estimatedDuration;
  final TaskChainClassification classification;
}

String _requiredText(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) throw ArgumentError('$field cannot be empty.');
  if (normalized.length > 240) {
    throw ArgumentError('$field cannot exceed 240 characters.');
  }
  return normalized;
}

String? _optionalText(String? value, String field) {
  if (value == null) return null;
  final normalized = value.trim();
  if (normalized.isEmpty) return null;
  if (normalized.length > 4000) {
    throw ArgumentError('$field cannot exceed 4000 characters.');
  }
  return normalized;
}

Duration _nonNegative(Duration value, String field) {
  if (value.isNegative) throw ArgumentError('$field cannot be negative.');
  return value;
}

Duration? _positiveOrNull(Duration? value, String field) {
  if (value != null && value <= Duration.zero) {
    throw ArgumentError('$field must be positive when provided.');
  }
  return value;
}
