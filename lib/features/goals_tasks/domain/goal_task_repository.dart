import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';

abstract interface class GoalTaskRepository {
  Stream<GoalTaskSnapshot> watch(AppUserId userId);

  Future<GoalTaskSnapshot> read(AppUserId userId);

  Future<Goal> saveGoal(AppUserId userId, GoalDraft draft);

  Future<Task> saveTask(AppUserId userId, TaskDraft draft);

  Future<Task> setTaskCompleted(
    AppUserId userId,
    String taskId,
    bool completed,
  );

  /// Focus Progress is evidence of work and never changes [Task.completedAt].
  Future<Task> setFocusProgress(
    AppUserId userId,
    String taskId,
    Duration progress,
  );

  Future<GoalTaskSnapshot> sync(AppUserId userId);
}

abstract interface class RemoteGoalTaskSource {
  Future<RemoteGoalTaskSnapshot> exchange(
    AppUserId userId,
    List<GoalTaskMutation> mutations,
  );
}

class GoalTaskMutation {
  const GoalTaskMutation({
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.mutationId,
    required this.updatedAt,
    required this.payload,
  });

  final AppUserId userId;
  final String entityType;
  final String entityId;
  final String mutationId;
  final DateTime updatedAt;
  final Map<String, Object?> payload;
}

class RemoteGoalTaskSnapshot {
  const RemoteGoalTaskSnapshot({
    required this.goals,
    required this.tasks,
    this.acceptedMutationIds = const {},
  });

  final List<Goal> goals;
  final List<Task> tasks;
  final Set<String> acceptedMutationIds;
}

class RemoteGoalTaskUnavailable implements Exception {
  const RemoteGoalTaskUnavailable([
    this.message = 'Remote Goal and Task data is unavailable.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class GoalTaskSyncFailure implements Exception {
  const GoalTaskSyncFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
