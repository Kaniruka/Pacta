import 'package:flutter/foundation.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/domain/focus_chain_models.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';

/// The normal terminal outcome in the foreground countdown slice.
///
/// Failure and abandonment outcomes are introduced with the later interruption
/// slices. An active Session has no outcome yet.
enum FocusSessionOutcome {
  completed;

  String get label => 'Completed';
}

@immutable
class FocusSessionConfig {
  const FocusSessionConfig({
    required this.task,
    required this.mode,
    required this.duration,
  }) : assert(duration > Duration.zero);

  final Task task;
  final FocusChainMode mode;
  final Duration duration;
}

@immutable
class FocusSession {
  FocusSession({
    required this.id,
    required this.userId,
    required this.taskId,
    required this.mode,
    required this.plannedDuration,
    required DateTime startedAt,
    required this.outcome,
    required this.actualElapsed,
    DateTime? completedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.mutationId = '',
  }) : assert(plannedDuration > Duration.zero),
       assert(actualElapsed >= Duration.zero),
       assert(actualElapsed <= plannedDuration),
       assert(outcome == null || actualElapsed == plannedDuration),
       startedAt = startedAt.toUtc(),
       completedAt = completedAt?.toUtc(),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc();

  final String id;
  final AppUserId userId;
  final String taskId;
  final FocusChainMode mode;
  final Duration plannedDuration;
  final DateTime startedAt;
  final FocusSessionOutcome? outcome;
  final Duration actualElapsed;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String mutationId;

  bool get isActive => outcome == null;

  DateTime get expectedEndAt => startedAt.add(plannedDuration);

  FocusSession copyWith({
    FocusSessionOutcome? outcome,
    Duration? actualElapsed,
    Object? completedAt = _unset,
    DateTime? updatedAt,
    String? mutationId,
  }) {
    return FocusSession(
      id: id,
      userId: userId,
      taskId: taskId,
      mode: mode,
      plannedDuration: plannedDuration,
      startedAt: startedAt,
      outcome: outcome ?? this.outcome,
      actualElapsed: actualElapsed ?? this.actualElapsed,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mutationId: mutationId ?? this.mutationId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FocusSession &&
        other.id == id &&
        other.userId == userId &&
        other.taskId == taskId &&
        other.mode == mode &&
        other.plannedDuration == plannedDuration &&
        other.startedAt == startedAt &&
        other.outcome == outcome &&
        other.actualElapsed == actualElapsed &&
        other.completedAt == completedAt &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.mutationId == mutationId;
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    taskId,
    mode,
    plannedDuration,
    startedAt,
    outcome,
    actualElapsed,
    completedAt,
    createdAt,
    updatedAt,
    mutationId,
  );
}

@immutable
class FocusNode {
  const FocusNode({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.taskId,
    required this.mode,
    required this.elapsed,
    required this.createdAt,
    this.mutationId = '',
  });

  final String id;
  final AppUserId userId;
  final String sessionId;
  final String taskId;
  final FocusChainMode mode;
  final Duration elapsed;
  final DateTime createdAt;
  final String mutationId;
}

@immutable
class FocusSessionClockState {
  const FocusSessionClockState({
    required this.session,
    required this.elapsed,
    required this.remaining,
  });

  final FocusSession session;
  final Duration elapsed;
  final Duration remaining;

  bool get reachedZero => remaining == Duration.zero;

  static FocusSessionClockState fromSession(
    FocusSession session,
    DateTime now,
  ) {
    final elapsed = session.isActive
        ? _clamp(
            now.toUtc().difference(session.startedAt),
            Duration.zero,
            session.plannedDuration,
          )
        : session.actualElapsed;
    return FocusSessionClockState(
      session: session,
      elapsed: elapsed,
      remaining: session.plannedDuration - elapsed,
    );
  }
}

const _unset = Object();

Duration _clamp(Duration value, Duration minimum, Duration maximum) {
  if (value < minimum) return minimum;
  if (value > maximum) return maximum;
  return value;
}
