import 'dart:async';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'task_database.dart';
import 'task_models.dart';

class TaskRemoteSnapshot {
  const TaskRemoteSnapshot({this.goals = const [], this.tasks = const []});

  final List<Goal> goals;
  final List<Task> tasks;
}

abstract interface class TaskRemoteDataSource {
  Future<TaskRemoteSnapshot> pull({required String userId});

  Future<void> upsertGoals({required String userId, required List<Goal> goals});

  Future<void> upsertTasks({required String userId, required List<Task> tasks});
}

class UnavailableTaskRemoteDataSource implements TaskRemoteDataSource {
  const UnavailableTaskRemoteDataSource();

  @override
  Future<TaskRemoteSnapshot> pull({required String userId}) async {
    throw StateError('当前未配置 Supabase，任务将先保存在本机。');
  }

  @override
  Future<void> upsertGoals({
    required String userId,
    required List<Goal> goals,
  }) async {
    throw StateError('当前未配置 Supabase，任务将先保存在本机。');
  }

  @override
  Future<void> upsertTasks({
    required String userId,
    required List<Task> tasks,
  }) async {
    throw StateError('当前未配置 Supabase，任务将先保存在本机。');
  }
}

abstract interface class TaskRepository {
  Stream<List<Goal>> watchGoals({bool includeDeleted = false});
  Future<List<Goal>> getGoals({bool includeDeleted = false});
  Future<Goal> createGoal(GoalDraft draft);
  Future<Goal> updateGoal(String goalId, GoalDraft draft);
  Future<void> deleteGoal(String goalId);
  Future<Task> createTask(String goalId, TaskDraft draft);
  Future<Task> updateTask(String taskId, TaskDraft draft);
  Future<void> setTaskCompletion(String taskId, {required bool isComplete});
  Future<void> sync();
  Future<void> dispose();
}

class LocalTaskRepository implements TaskRepository {
  LocalTaskRepository({
    required this.database,
    required this.userId,
    required this.remote,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PactaDatabase database;
  final String userId;
  final TaskRemoteDataSource remote;
  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast();
  final _uuid = const Uuid();

  @override
  Stream<List<Goal>> watchGoals({bool includeDeleted = false}) async* {
    yield await getGoals(includeDeleted: includeDeleted);
    await for (final _ in _changes.stream) {
      yield await getGoals(includeDeleted: includeDeleted);
    }
  }

  @override
  Future<List<Goal>> getGoals({bool includeDeleted = false}) async {
    final goalRows =
        await (database.select(database.localGoals)
              ..where((goal) => goal.userId.equals(userId))
              ..orderBy([(goal) => OrderingTerm(expression: goal.updatedAt)]))
            .get();
    final taskRows =
        await (database.select(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..orderBy([(task) => OrderingTerm(expression: task.updatedAt)]))
            .get();
    final tasksByGoal = <String, List<Task>>{};
    for (final row in taskRows) {
      if (!includeDeleted && row.deletedAt != null) continue;
      tasksByGoal.putIfAbsent(row.goalId, () => []).add(_taskFromRow(row));
    }
    final goals = [
      for (final row in goalRows)
        if (includeDeleted || row.deletedAt == null)
          _goalFromRow(row, tasks: tasksByGoal[row.id] ?? const []),
    ];
    for (final tasks in tasksByGoal.values) {
      tasks.sort((left, right) {
        if (left.isComplete != right.isComplete) {
          return left.isComplete ? 1 : -1;
        }
        return left.updatedAt.compareTo(right.updatedAt);
      });
    }
    goals.sort((left, right) {
      final leftHasExecutableTask = left.tasks.any((task) => !task.isComplete);
      final rightHasExecutableTask = right.tasks.any(
        (task) => !task.isComplete,
      );
      if (leftHasExecutableTask != rightHasExecutableTask) {
        return leftHasExecutableTask ? -1 : 1;
      }
      return left.updatedAt.compareTo(right.updatedAt);
    });
    return goals;
  }

  @override
  Future<Goal> createGoal(GoalDraft draft) async {
    final title = _requiredTitle(draft.title, '目标');
    final timestamp = _nextTimestamp();
    final goal = Goal(
      id: _uuid.v4(),
      title: title,
      classification: draft.classification,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await _saveGoal(goal);
    await _publish();
    return goal;
  }

  @override
  Future<Goal> updateGoal(String goalId, GoalDraft draft) async {
    final existing = await _findGoal(goalId);
    final updated = existing.copyWith(
      title: _requiredTitle(draft.title, '目标'),
      classification: draft.classification,
      updatedAt: _nextTimestamp(existing.updatedAt),
    );
    await _saveGoal(updated);
    await _publish();
    return (await getGoals()).firstWhere((goal) => goal.id == goalId);
  }

  @override
  Future<void> deleteGoal(String goalId) async {
    final existing = await _findGoalIncludingDeleted(goalId);
    if (existing.isDeleted) return;

    final deletedAt = _nextTimestamp(existing.updatedAt);
    await database.transaction(() async {
      final taskRows =
          await (database.select(database.localTasks)
                ..where((task) => task.userId.equals(userId))
                ..where((task) => task.goalId.equals(goalId)))
              .get();
      for (final row in taskRows) {
        if (row.deletedAt != null) continue;
        final updatedAt = _nextTimestamp(row.updatedAt);
        await (database.update(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..where((task) => task.id.equals(row.id)))
            .write(
              LocalTasksCompanion(
                deletedAt: Value(deletedAt),
                updatedAt: Value(updatedAt),
              ),
            );
        await _queue('task', row.id, updatedAt);
      }
      await (database.update(database.localGoals)
            ..where((goal) => goal.userId.equals(userId))
            ..where((goal) => goal.id.equals(goalId)))
          .write(
            LocalGoalsCompanion(
              deletedAt: Value(deletedAt),
              updatedAt: Value(deletedAt),
            ),
          );
      await _queue('goal', goalId, deletedAt);
    });
    await _publish();
  }

  @override
  Future<Task> createTask(String goalId, TaskDraft draft) async {
    final goal = await _findGoal(goalId);
    final timestamp = _nextTimestamp();
    final task = Task(
      id: _uuid.v4(),
      goalId: goalId,
      title: _requiredTitle(draft.title, '任务'),
      classification: draft.classification ?? goal.classification,
      estimatedMinutes: _validEstimatedMinutes(draft.estimatedMinutes),
      deadline: draft.deadline,
      isComplete: false,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await _saveTask(task);
    await _publish();
    return task;
  }

  @override
  Future<Task> updateTask(String taskId, TaskDraft draft) async {
    final existing = await _findTask(taskId);
    final updated = existing.copyWith(
      title: _requiredTitle(draft.title, '任务'),
      classification: draft.classification ?? existing.classification,
      estimatedMinutes: _validEstimatedMinutes(draft.estimatedMinutes),
      deadline: draft.deadline,
      updatedAt: _nextTimestamp(existing.updatedAt),
    );
    await _saveTask(updated);
    await _publish();
    return updated;
  }

  @override
  Future<void> setTaskCompletion(
    String taskId, {
    required bool isComplete,
  }) async {
    final existing = await _findTask(taskId);
    await _saveTask(
      existing.copyWith(
        isComplete: isComplete,
        updatedAt: _nextTimestamp(existing.updatedAt),
      ),
    );
    await _publish();
  }

  @override
  Future<void> sync() async {
    final snapshot = await remote.pull(userId: userId);
    final localGoals = await _localGoalsById();
    final localTasks = await _localTasksById();
    final queued = await (database.select(
      database.taskSyncEntries,
    )..where((entry) => entry.userId.equals(userId))).get();
    final queuedKeys = {
      for (final entry in queued) '${entry.entityType}:${entry.entityId}',
    };

    final remoteGoalsById = _byId(snapshot.goals);
    final remoteTasksById = _byId(snapshot.tasks);
    for (final goal in snapshot.goals) {
      final local = localGoals[goal.id];
      final merged = local == null ? goal : _mergeGoal(local, goal);
      await _saveGoal(merged, queue: false);
      localGoals[goal.id] = merged;
      if (merged.isDeleted && goal.deletedAt == null) {
        await _queue('goal', goal.id, merged.updatedAt);
        queuedKeys.add('goal:${goal.id}');
      }
    }
    for (final task in snapshot.tasks) {
      final local = localTasks[task.id];
      final deletedAt = localGoals[task.goalId]?.deletedAt;
      final incoming = deletedAt == null ? task : _markDeleted(task, deletedAt);
      final merged = local == null ? incoming : _mergeTask(local, incoming);
      await _saveTask(merged, queue: false);
      localTasks[task.id] = merged;
      if (merged.isDeleted && task.deletedAt == null) {
        await _queue('task', task.id, merged.updatedAt);
        queuedKeys.add('task:${task.id}');
      }
    }

    for (final task in localTasks.values.toList()) {
      final deletedAt = localGoals[task.goalId]?.deletedAt;
      if (deletedAt == null || task.isDeleted) continue;
      final deleted = _markDeleted(task, deletedAt);
      await _saveTask(deleted);
      localTasks[task.id] = deleted;
      queuedKeys.add('task:${task.id}');
    }

    final goalsToUpload = [
      for (final goal in localGoals.values)
        if (_shouldUpload(
          entityType: 'goal',
          entityId: goal.id,
          local: goal.updatedAt,
          remote: remoteGoalsById[goal.id]?.updatedAt,
          queuedKeys: queuedKeys,
        ))
          goal,
    ];
    final tasksToUpload = [
      for (final task in localTasks.values)
        if (_shouldUpload(
          entityType: 'task',
          entityId: task.id,
          local: task.updatedAt,
          remote: remoteTasksById[task.id]?.updatedAt,
          queuedKeys: queuedKeys,
        ))
          task,
    ];
    if (goalsToUpload.isNotEmpty) {
      await remote.upsertGoals(userId: userId, goals: goalsToUpload);
    }
    if (tasksToUpload.isNotEmpty) {
      await remote.upsertTasks(userId: userId, tasks: tasksToUpload);
    }
    await _clearQueue(goalsToUpload, tasksToUpload);
    await _publish();
  }

  @override
  Future<void> dispose() => _changes.close();

  Future<void> _saveGoal(Goal goal, {bool queue = true}) async {
    await database
        .into(database.localGoals)
        .insertOnConflictUpdate(
          LocalGoalsCompanion.insert(
            userId: userId,
            id: goal.id,
            title: goal.title,
            classification: goal.classification.storageValue,
            createdAt: goal.createdAt,
            updatedAt: goal.updatedAt,
            deletedAt: Value(goal.deletedAt),
          ),
        );
    if (queue) await _queue('goal', goal.id, goal.updatedAt);
  }

  Future<void> _saveTask(Task task, {bool queue = true}) async {
    await database
        .into(database.localTasks)
        .insertOnConflictUpdate(
          LocalTasksCompanion.insert(
            userId: userId,
            id: task.id,
            goalId: task.goalId,
            title: task.title,
            classification: task.classification.storageValue,
            estimatedMinutes: Value(task.estimatedMinutes),
            deadline: Value(task.deadline),
            isComplete: Value(task.isComplete),
            focusProgressSeconds: Value(task.focusProgressSeconds),
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            deletedAt: Value(task.deletedAt),
          ),
        );
    if (queue) await _queue('task', task.id, task.updatedAt);
  }

  Future<void> _queue(String type, String id, DateTime updatedAt) async {
    await database
        .into(database.taskSyncEntries)
        .insertOnConflictUpdate(
          TaskSyncEntriesCompanion.insert(
            userId: userId,
            entityType: type,
            entityId: id,
            updatedAt: updatedAt,
          ),
        );
  }

  Future<void> _clearQueue(List<Goal> goals, List<Task> tasks) async {
    final ids = [
      ...goals.map((goal) => ('goal', goal.id)),
      ...tasks.map((task) => ('task', task.id)),
    ];
    for (final (type, id) in ids) {
      await (database.delete(database.taskSyncEntries)
            ..where((entry) => entry.userId.equals(userId))
            ..where((entry) => entry.entityType.equals(type))
            ..where((entry) => entry.entityId.equals(id)))
          .go();
    }
  }

  Future<Goal> _findGoal(String goalId) async {
    final row =
        await (database.select(database.localGoals)
              ..where((goal) => goal.userId.equals(userId))
              ..where((goal) => goal.id.equals(goalId)))
            .getSingleOrNull();
    if (row == null || row.deletedAt != null) {
      throw StateError('目标不存在或已删除。');
    }
    return _goalFromRow(row);
  }

  Future<Goal> _findGoalIncludingDeleted(String goalId) async {
    final row =
        await (database.select(database.localGoals)
              ..where((goal) => goal.userId.equals(userId))
              ..where((goal) => goal.id.equals(goalId)))
            .getSingleOrNull();
    if (row == null) throw StateError('目标不存在或已不属于当前用户。');
    return _goalFromRow(row);
  }

  Future<Task> _findTask(String taskId) async {
    final row =
        await (database.select(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..where((task) => task.id.equals(taskId)))
            .getSingleOrNull();
    if (row == null || row.deletedAt != null) {
      throw StateError('任务不存在或已删除。');
    }
    return _taskFromRow(row);
  }

  Future<Map<String, Goal>> _localGoalsById() async {
    final goals = await getGoals(includeDeleted: true);
    return {for (final goal in goals) goal.id: goal};
  }

  Future<Map<String, Task>> _localTasksById() async {
    final rows = await (database.select(
      database.localTasks,
    )..where((task) => task.userId.equals(userId))).get();
    return {for (final row in rows) row.id: _taskFromRow(row)};
  }

  Future<void> _publish() async {
    if (!_changes.hasListener) return;
    _changes.add(null);
  }

  Goal _goalFromRow(LocalGoal row, {List<Task> tasks = const []}) => Goal(
    id: row.id,
    title: row.title,
    classification: TaskClassification.fromStorage(row.classification),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    tasks: tasks,
  );

  Task _taskFromRow(LocalTask row) => Task(
    id: row.id,
    goalId: row.goalId,
    title: row.title,
    classification: TaskClassification.fromStorage(row.classification),
    estimatedMinutes: row.estimatedMinutes,
    deadline: row.deadline,
    isComplete: row.isComplete,
    focusProgressSeconds: row.focusProgressSeconds,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  Goal _mergeGoal(Goal local, Goal remote) {
    final preferred = remote.updatedAt.isAfter(local.updatedAt)
        ? remote
        : local;
    final deletedAt = _retainedDeletion(local.deletedAt, remote.deletedAt);
    if (deletedAt == null) return preferred;
    return preferred.copyWith(
      deletedAt: deletedAt,
      updatedAt: _laterDate(preferred.updatedAt, deletedAt),
    );
  }

  Task _mergeTask(Task local, Task remote) {
    final preferred = remote.updatedAt.isAfter(local.updatedAt)
        ? remote
        : local;
    final deletedAt = _retainedDeletion(local.deletedAt, remote.deletedAt);
    if (deletedAt == null) return preferred;
    return preferred.copyWith(
      deletedAt: deletedAt,
      updatedAt: _laterDate(preferred.updatedAt, deletedAt),
    );
  }

  Task _markDeleted(Task task, DateTime deletedAt) => task.copyWith(
    deletedAt: _retainedDeletion(task.deletedAt, deletedAt),
    updatedAt: _laterDate(task.updatedAt, deletedAt),
  );

  DateTime? _retainedDeletion(DateTime? local, DateTime? remote) {
    if (local == null) return remote;
    if (remote == null || local.isBefore(remote)) return local;
    return remote;
  }

  DateTime _laterDate(DateTime first, DateTime second) =>
      first.isAfter(second) ? first : second;

  String _requiredTitle(String title, String kind) {
    final normalized = title.trim();
    if (normalized.isEmpty) throw ArgumentError('$kind名称不能为空。');
    return normalized;
  }

  int? _validEstimatedMinutes(int? minutes) {
    if (minutes != null && minutes <= 0) {
      throw ArgumentError('预计时长必须大于 0 分钟。');
    }
    return minutes;
  }

  DateTime _nextTimestamp([DateTime? previous]) {
    final candidate = _now().toUtc();
    final second = DateTime.fromMillisecondsSinceEpoch(
      candidate.millisecondsSinceEpoch - candidate.millisecond,
      isUtc: true,
    );
    if (previous == null) return second;
    final previousUtc = previous.toUtc();
    return second.isAfter(previousUtc)
        ? second
        : previousUtc.add(const Duration(seconds: 1));
  }

  bool _shouldUpload({
    required String entityType,
    required String entityId,
    required DateTime local,
    required DateTime? remote,
    required Set<String> queuedKeys,
  }) {
    return queuedKeys.contains('$entityType:$entityId') ||
        remote == null ||
        !remote.isAfter(local);
  }

  Map<String, T> _byId<T extends Object>(List<T> values) {
    return {
      for (final value in values)
        (value is Goal ? value.id : (value as Task).id): value,
    };
  }
}

class SupabaseTaskRemoteDataSource implements TaskRemoteDataSource {
  SupabaseTaskRemoteDataSource(this.client);

  final SupabaseClient client;

  @override
  Future<TaskRemoteSnapshot> pull({required String userId}) async {
    final goals = await client.from('goals').select();
    final tasks = await client.from('tasks').select();
    return TaskRemoteSnapshot(
      goals: [for (final row in goals) _goalFromJson(row)],
      tasks: [for (final row in tasks) _taskFromJson(row)],
    );
  }

  @override
  Future<void> upsertGoals({
    required String userId,
    required List<Goal> goals,
  }) async {
    await client.from('goals').upsert([
      for (final goal in goals)
        {
          'id': goal.id,
          'user_id': userId,
          'title': goal.title,
          'classification': goal.classification.storageValue,
          'created_at': _utcIso8601(goal.createdAt),
          'updated_at': _utcIso8601(goal.updatedAt),
          'deleted_at': goal.deletedAt == null
              ? null
              : _utcIso8601(goal.deletedAt!),
        },
    ], onConflict: 'id');
  }

  @override
  Future<void> upsertTasks({
    required String userId,
    required List<Task> tasks,
  }) async {
    await client.from('tasks').upsert([
      for (final task in tasks)
        {
          'id': task.id,
          'user_id': userId,
          'goal_id': task.goalId,
          'title': task.title,
          'classification': task.classification.storageValue,
          'estimated_minutes': task.estimatedMinutes,
          'deadline': task.deadline == null
              ? null
              : _utcIso8601(task.deadline!),
          'is_complete': task.isComplete,
          'focus_progress_seconds': task.focusProgressSeconds,
          'created_at': _utcIso8601(task.createdAt),
          'updated_at': _utcIso8601(task.updatedAt),
          'deleted_at': task.deletedAt == null
              ? null
              : _utcIso8601(task.deletedAt!),
        },
    ], onConflict: 'id');
  }

  Goal _goalFromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String,
    title: json['title'] as String,
    classification: TaskClassification.fromStorage(
      json['classification'] as String,
    ),
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    deletedAt: (json['deleted_at'] as String?) == null
        ? null
        : DateTime.parse(json['deleted_at'] as String).toUtc(),
  );

  Task _taskFromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    goalId: json['goal_id'] as String,
    title: json['title'] as String,
    classification: TaskClassification.fromStorage(
      json['classification'] as String,
    ),
    estimatedMinutes: json['estimated_minutes'] as int?,
    deadline: (json['deadline'] as String?) == null
        ? null
        : DateTime.parse(json['deadline'] as String).toUtc(),
    isComplete: json['is_complete'] as bool,
    focusProgressSeconds: (json['focus_progress_seconds'] as int?) ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    deletedAt: (json['deleted_at'] as String?) == null
        ? null
        : DateTime.parse(json['deleted_at'] as String).toUtc(),
  );
}

String _utcIso8601(DateTime value) => value.toUtc().toIso8601String();

class InMemoryTaskRemote implements TaskRemoteDataSource {
  final _goals = <String, Map<String, Goal>>{};
  final _tasks = <String, Map<String, Task>>{};

  List<Goal> get goals => _goals['user-a']?.values.toList() ?? const [];
  List<Task> get tasks => _tasks['user-a']?.values.toList() ?? const [];

  @override
  Future<TaskRemoteSnapshot> pull({required String userId}) async {
    return TaskRemoteSnapshot(
      goals: (_goals[userId] ?? {}).values.toList(),
      tasks: (_tasks[userId] ?? {}).values.toList(),
    );
  }

  @override
  Future<void> upsertGoals({
    required String userId,
    required List<Goal> goals,
  }) async {
    final target = _goals.putIfAbsent(userId, () => {});
    for (final goal in goals) {
      final previous = target[goal.id];
      final deletedAt = previous?.deletedAt;
      target[goal.id] = deletedAt == null
          ? goal
          : goal.copyWith(deletedAt: deletedAt);
    }
  }

  @override
  Future<void> upsertTasks({
    required String userId,
    required List<Task> tasks,
  }) async {
    final target = _tasks.putIfAbsent(userId, () => {});
    for (final task in tasks) {
      final previous = target[task.id];
      final deletedAt = previous?.deletedAt;
      target[task.id] = deletedAt == null
          ? task
          : task.copyWith(deletedAt: deletedAt);
    }
  }
}

class UnavailableTaskRepository implements TaskRepository {
  const UnavailableTaskRepository();

  @override
  Stream<List<Goal>> watchGoals({bool includeDeleted = false}) =>
      Stream.value(const []);

  @override
  Future<List<Goal>> getGoals({bool includeDeleted = false}) async => const [];

  @override
  Future<Goal> createGoal(GoalDraft draft) => _unavailable();

  @override
  Future<Goal> updateGoal(String goalId, GoalDraft draft) => _unavailable();

  @override
  Future<void> deleteGoal(String goalId) => _unavailable();

  @override
  Future<Task> createTask(String goalId, TaskDraft draft) => _unavailable();

  @override
  Future<Task> updateTask(String taskId, TaskDraft draft) => _unavailable();

  @override
  Future<void> setTaskCompletion(String taskId, {required bool isComplete}) =>
      _unavailable();

  @override
  Future<void> sync() async {}

  @override
  Future<void> dispose() async {}

  Future<T> _unavailable<T>() async {
    throw StateError('当前用户的任务存储尚未配置。');
  }
}
