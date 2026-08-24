import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_repository.dart';
import 'package:pacta/private_data/app_database.dart';
import 'package:uuid/uuid.dart';

class DriftGoalTaskRepository implements GoalTaskRepository {
  DriftGoalTaskRepository({
    required AppDatabase database,
    required RemoteGoalTaskSource remote,
    Uuid? ids,
    DateTime Function()? clock,
  }) : _database = database,
       _remote = remote,
       _ids = ids ?? const Uuid(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase _database;
  final RemoteGoalTaskSource _remote;
  final Uuid _ids;
  final DateTime Function() _clock;
  final _controllers = <String, StreamController<GoalTaskSnapshot>>{};
  final _syncOperations = <String, Future<GoalTaskSnapshot>>{};

  @override
  Stream<GoalTaskSnapshot> watch(AppUserId userId) {
    final key = userId.value;
    final controller = _controllers.putIfAbsent(
      key,
      () => StreamController<GoalTaskSnapshot>.broadcast(
        onListen: () => unawaited(_emit(userId)),
      ),
    );
    return controller.stream;
  }

  @override
  Future<GoalTaskSnapshot> read(AppUserId userId) async {
    final goalRows =
        await (_database.select(_database.cachedGoals)
              ..where((row) => row.userId.equals(userId.value))
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    final taskRows =
        await (_database.select(_database.cachedTasks)
              ..where((row) => row.userId.equals(userId.value))
              ..orderBy([
                (row) => OrderingTerm.asc(row.deadline),
                (row) => OrderingTerm.asc(row.createdAt),
              ]))
            .get();
    return GoalTaskSnapshot(
      goals: goalRows.map(_goalFromRow),
      tasks: taskRows.map(_taskFromRow),
    );
  }

  @override
  Future<Goal> saveGoal(AppUserId userId, GoalDraft draft) async {
    final now = _clock().toUtc();
    final id = draft.id ?? _ids.v4();
    final existing =
        await (_database.select(_database.cachedGoals)..where(
              (row) => row.userId.equals(userId.value) & row.id.equals(id),
            ))
            .getSingleOrNull();
    final goal = Goal(
      id: id,
      userId: userId,
      title: draft.title,
      notes: draft.notes,
      mutationId: _mutationId(now, id),
      createdAt: existing?.createdAt.toUtc() ?? now,
      updatedAt: now,
    );
    await _database.transaction(() async {
      await _database
          .into(_database.cachedGoals)
          .insertOnConflictUpdate(_goalCompanion(goal));
      await _writeOutbox(
        userId: userId,
        entityType: 'goal',
        entityId: goal.id,
        mutationId: goal.mutationId.isEmpty
            ? _mutationId(goal.updatedAt, goal.id)
            : goal.mutationId,
        updatedAt: goal.updatedAt,
        payload: _goalPayload(goal),
      );
    });
    await _emit(userId);
    return goal;
  }

  @override
  Future<Task> saveTask(AppUserId userId, TaskDraft draft) async {
    final now = _clock().toUtc();
    final id = draft.id ?? _ids.v4();
    final goal =
        await (_database.select(_database.cachedGoals)..where(
              (row) =>
                  row.userId.equals(userId.value) & row.id.equals(draft.goalId),
            ))
            .getSingleOrNull();
    if (goal == null) {
      throw ArgumentError(
        'A Task must belong to an existing Goal owned by this User.',
      );
    }
    final existing =
        await (_database.select(_database.cachedTasks)..where(
              (row) => row.userId.equals(userId.value) & row.id.equals(id),
            ))
            .getSingleOrNull();
    final task = Task(
      id: id,
      userId: userId,
      goalId: draft.goalId,
      title: draft.title,
      notes: draft.notes,
      deadline: draft.deadline,
      mutationId: _mutationId(now, id),
      estimatedDuration: draft.estimatedDuration,
      classification: draft.classification,
      focusProgress: _durationFromSeconds(existing?.focusProgressSeconds ?? 0),
      completedAt: existing?.completedAt?.toUtc(),
      createdAt: existing?.createdAt.toUtc() ?? now,
      updatedAt: now,
    );
    await _database.transaction(() async {
      await _database
          .into(_database.cachedTasks)
          .insertOnConflictUpdate(_taskCompanion(task));
      await _writeOutbox(
        userId: userId,
        entityType: 'task',
        entityId: task.id,
        mutationId: task.mutationId.isEmpty
            ? _mutationId(task.updatedAt, task.id)
            : task.mutationId,
        updatedAt: task.updatedAt,
        payload: _taskPayload(task),
      );
    });
    await _emit(userId);
    return task;
  }

  @override
  Future<Task> setTaskCompleted(
    AppUserId userId,
    String taskId,
    bool completed,
  ) async {
    final existing = await _taskForUser(userId, taskId);
    final now = _clock().toUtc();
    final task = existing.copyWith(
      completedAt: completed ? now : null,
      mutationId: _mutationId(now, existing.id),
      updatedAt: now,
    );
    await _saveTaskAndQueue(task);
    await _emit(userId);
    return task;
  }

  @override
  Future<Task> setFocusProgress(
    AppUserId userId,
    String taskId,
    Duration progress,
  ) async {
    final existing = await _taskForUser(userId, taskId);
    final now = _clock().toUtc();
    final task = existing.copyWith(
      focusProgress: progress,
      mutationId: _mutationId(now, existing.id),
      updatedAt: now,
    );
    await _saveTaskAndQueue(task);
    await _emit(userId);
    return task;
  }

  @override
  Future<GoalTaskSnapshot> sync(AppUserId userId) {
    final key = userId.value;
    final running = _syncOperations[key];
    if (running != null) {
      return running;
    }
    final operation = _performSync(userId);
    _syncOperations[key] = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_syncOperations[key], operation)) {
          _syncOperations.remove(key);
        }
      }),
    );
    return operation;
  }

  Future<GoalTaskSnapshot> _performSync(AppUserId userId) async {
    final pendingRows =
        await (_database.select(_database.goalTaskOutbox)
              ..where((row) => row.userId.equals(userId.value))
              ..orderBy([(row) => OrderingTerm.asc(row.updatedAt)]))
            .get();
    final mutations = pendingRows
        .map(
          (row) => GoalTaskMutation(
            userId: userId,
            entityType: row.entityType,
            entityId: row.entityId,
            mutationId: row.mutationId,
            updatedAt: row.updatedAt.toUtc(),
            payload: Map<String, Object?>.from(jsonDecode(row.payload) as Map),
          ),
        )
        .toList(growable: false);

    RemoteGoalTaskSnapshot remoteSnapshot;
    try {
      remoteSnapshot = await _remote.exchange(userId, mutations);
    } on RemoteGoalTaskUnavailable {
      return read(userId);
    } catch (error) {
      throw GoalTaskSyncFailure(
        'Unable to synchronize Goals and Tasks: $error',
      );
    }

    await _database.transaction(() async {
      for (final goal in remoteSnapshot.goals) {
        if (goal.userId != userId) continue;
        final local =
            await (_database.select(_database.cachedGoals)..where(
                  (row) =>
                      row.userId.equals(userId.value) & row.id.equals(goal.id),
                ))
                .getSingleOrNull();
        if (local == null ||
            _wins(
              goal.updatedAt,
              goal.mutationId,
              local.updatedAt,
              local.mutationId,
            )) {
          await _database
              .into(_database.cachedGoals)
              .insertOnConflictUpdate(_goalCompanion(goal));
        }
      }
      for (final task in remoteSnapshot.tasks) {
        if (task.userId != userId) continue;
        final local =
            await (_database.select(_database.cachedTasks)..where(
                  (row) =>
                      row.userId.equals(userId.value) & row.id.equals(task.id),
                ))
                .getSingleOrNull();
        if (local == null ||
            _wins(
              task.updatedAt,
              task.mutationId,
              local.updatedAt,
              local.mutationId,
            )) {
          await _database
              .into(_database.cachedTasks)
              .insertOnConflictUpdate(_taskCompanion(task));
        }
      }
      for (final mutationId in remoteSnapshot.acceptedMutationIds) {
        await (_database.delete(_database.goalTaskOutbox)..where(
              (row) =>
                  row.userId.equals(userId.value) &
                  row.mutationId.equals(mutationId),
            ))
            .go();
      }
    });
    final snapshot = await read(userId);
    await _emit(userId, snapshot);
    return snapshot;
  }

  Future<Task> _taskForUser(AppUserId userId, String taskId) async {
    final row =
        await (_database.select(_database.cachedTasks)..where(
              (candidate) =>
                  candidate.userId.equals(userId.value) &
                  candidate.id.equals(taskId),
            ))
            .getSingleOrNull();
    if (row == null) throw StateError('Task $taskId was not found.');
    return _taskFromRow(row);
  }

  Future<void> _saveTaskAndQueue(Task task) async {
    await _database.transaction(() async {
      await _database
          .into(_database.cachedTasks)
          .insertOnConflictUpdate(_taskCompanion(task));
      await _writeOutbox(
        userId: task.userId,
        entityType: 'task',
        entityId: task.id,
        mutationId: task.mutationId.isEmpty
            ? _mutationId(task.updatedAt, task.id)
            : task.mutationId,
        updatedAt: task.updatedAt,
        payload: _taskPayload(task),
      );
    });
  }

  Future<void> _writeOutbox({
    required AppUserId userId,
    required String entityType,
    required String entityId,
    required String mutationId,
    required DateTime updatedAt,
    required Map<String, Object?> payload,
  }) {
    return _database
        .into(_database.goalTaskOutbox)
        .insertOnConflictUpdate(
          GoalTaskOutboxCompanion.insert(
            userId: userId.value,
            entityType: entityType,
            entityId: entityId,
            mutationId: mutationId,
            updatedAt: updatedAt,
            payload: jsonEncode(payload),
          ),
        );
  }

  Future<void> _emit(AppUserId userId, [GoalTaskSnapshot? snapshot]) async {
    final controller = _controllers[userId.value];
    if (controller == null || controller.isClosed || !controller.hasListener) {
      return;
    }
    try {
      controller.add(snapshot ?? await read(userId));
    } catch (error, stackTrace) {
      controller.addError(error, stackTrace);
    }
  }

  Goal _goalFromRow(CachedGoalRow row) => Goal(
    id: row.id,
    userId: AppUserId(row.userId),
    title: row.title,
    notes: row.notes,
    mutationId: row.mutationId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  Task _taskFromRow(CachedTaskRow row) => Task(
    id: row.id,
    userId: AppUserId(row.userId),
    goalId: row.goalId,
    title: row.title,
    notes: row.notes,
    mutationId: row.mutationId,
    deadline: row.deadline,
    estimatedDuration: _durationOrNull(row.estimatedSeconds),
    classification: TaskChainClassification.fromWireValue(row.classification),
    focusProgress: _durationFromSeconds(row.focusProgressSeconds),
    completedAt: row.completedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  CachedGoalsCompanion _goalCompanion(Goal goal) => CachedGoalsCompanion.insert(
    id: goal.id,
    userId: goal.userId.value,
    title: goal.title,
    notes: Value(goal.notes),
    createdAt: goal.createdAt,
    updatedAt: goal.updatedAt,
    mutationId: goal.mutationId.isEmpty
        ? _mutationId(goal.updatedAt, goal.id)
        : goal.mutationId,
  );

  CachedTasksCompanion _taskCompanion(Task task) => CachedTasksCompanion.insert(
    id: task.id,
    userId: task.userId.value,
    goalId: task.goalId,
    title: task.title,
    notes: Value(task.notes),
    deadline: Value(task.deadline),
    estimatedSeconds: Value(
      task.estimatedSeconds == 0 ? null : task.estimatedSeconds,
    ),
    classification: task.classification.wireValue,
    focusProgressSeconds: Value(task.focusProgressSeconds),
    completedAt: Value(task.completedAt),
    createdAt: task.createdAt,
    updatedAt: task.updatedAt,
    mutationId: task.mutationId.isEmpty
        ? _mutationId(task.updatedAt, task.id)
        : task.mutationId,
  );

  Map<String, Object?> _goalPayload(Goal goal) => {
    'id': goal.id,
    'user_id': goal.userId.value,
    'title': goal.title,
    'notes': goal.notes,
    'created_at': goal.createdAt.toIso8601String(),
    'updated_at': goal.updatedAt.toIso8601String(),
    'mutation_id': _effectiveMutationId(
      goal.mutationId,
      goal.updatedAt,
      goal.id,
    ),
  };

  Map<String, Object?> _taskPayload(Task task) => {
    'id': task.id,
    'user_id': task.userId.value,
    'goal_id': task.goalId,
    'title': task.title,
    'notes': task.notes,
    'deadline': task.deadline?.toIso8601String(),
    'estimated_seconds': task.estimatedDuration?.inSeconds,
    'classification': task.classification.wireValue,
    'focus_progress_seconds': task.focusProgressSeconds,
    'completed_at': task.completedAt?.toIso8601String(),
    'created_at': task.createdAt.toIso8601String(),
    'updated_at': task.updatedAt.toIso8601String(),
    'mutation_id': _effectiveMutationId(
      task.mutationId,
      task.updatedAt,
      task.id,
    ),
  };

  String _effectiveMutationId(
    String mutationId,
    DateTime updatedAt,
    String entityId,
  ) {
    return mutationId.isEmpty ? _mutationId(updatedAt, entityId) : mutationId;
  }

  String _mutationId(DateTime updatedAt, String entityId) =>
      '${updatedAt.microsecondsSinceEpoch}-$entityId';
}

bool _wins(
  DateTime incomingTime,
  String incomingMutation,
  DateTime localTime,
  String localMutation,
) {
  final timeComparison = incomingTime.compareTo(localTime);
  if (timeComparison != 0) {
    return timeComparison > 0;
  }
  return incomingMutation.compareTo(localMutation) > 0;
}

Duration _durationFromSeconds(int seconds) => Duration(seconds: seconds);
Duration? _durationOrNull(int? seconds) =>
    seconds == null ? null : _durationFromSeconds(seconds);
