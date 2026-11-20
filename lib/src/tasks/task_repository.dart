import 'dart:async';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../auth/user_lifecycle.dart';
import 'preference_storage_fallback.dart';
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

/// 每个目标未完成任务的手动顺序（设备偏好）。
///
/// 只落在本机 `SharedPreferences`：任务表与 Cloud Snapshot v3 载荷都不新增
/// 列，跨设备仍由既有整份快照同步目标与任务本身。
///
/// 纯 Dart 单测通常没有初始化 `WidgetsFlutterBinding`，此时
/// `SharedPreferences.getInstance()` 连方法通道都建立不起来。这里把这种
/// "偏好存储不可用" 视为正常的降级条件，退回进程内内存表，绝不让一次排序
/// 把既有单元测试或离线页面弄崩。
class GoalTaskOrderStore {
  const GoalTaskOrderStore({
    this.preferencesLoader = SharedPreferences.getInstance,
  });

  final Future<SharedPreferences> Function() preferencesLoader;

  /// 没有偏好存储时的兜底；键已包含用户与目标，跨用户不会串门。
  static final Map<String, List<String>> _memoryFallback =
      <String, List<String>>{};

  String keyFor(String userId, String goalId) =>
      'pacta.device.goal_task_order.v1.$userId.$goalId';

  Future<List<String>> load({
    required String userId,
    required String goalId,
  }) async {
    final key = keyFor(userId, goalId);
    final preferences = await _preferencesOrNull();
    if (preferences == null) {
      return List<String>.unmodifiable(
        _memoryFallback[key] ?? const <String>[],
      );
    }
    // 旧写入失败可能让内存缓存领先磁盘，读取前对齐一次。
    await preferences.reload();
    return List<String>.unmodifiable(
      preferences.getStringList(key) ?? const <String>[],
    );
  }

  Future<void> save({
    required String userId,
    required String goalId,
    required List<String> taskIds,
  }) async {
    final key = keyFor(userId, goalId);
    final preferences = await _preferencesOrNull();
    if (preferences == null) {
      _memoryFallback[key] = List<String>.of(taskIds);
      return;
    }
    if (!await preferences.setStringList(key, taskIds)) {
      throw StateError('任务顺序未保存，请重试。');
    }
  }

  Future<SharedPreferences?> _preferencesOrNull() =>
      loadSharedPreferencesOrNull(preferencesLoader);
}

abstract interface class TaskRepository {
  Stream<List<Goal>> watchGoals({bool includeDeleted = false});
  Future<List<Goal>> getGoals({bool includeDeleted = false});
  Future<Goal> createGoal(GoalDraft draft);
  Future<Goal> updateGoal(String goalId, GoalDraft draft);
  Future<void> deleteGoal(String goalId);

  /// Pins or unpins one goal. Pinning appends to the end of the manual order.
  Future<void> setGoalPinned(String goalId, {required bool isPinned});

  /// Persists the manual order of every currently pinned goal.
  Future<void> reorderPinnedGoals(List<String> orderedGoalIds);

  /// Persists the manual order of every currently unpinned goal.
  Future<void> reorderUnpinnedGoals(List<String> orderedGoalIds);

  /// Persists the manual order of the unfinished tasks inside one goal.
  ///
  /// The order is a device preference (it never enters the business snapshot);
  /// [orderedTaskIds] must cover exactly the goal's unfinished tasks.
  Future<void> reorderTasks(String goalId, List<String> orderedTaskIds);
  Future<Task> createTask(String goalId, TaskDraft draft);
  Future<Task> updateTask(String taskId, TaskDraft draft);
  Future<void> setTaskCompletion(String taskId, {required bool isComplete});

  /// Removes one task as a tombstone; owned schedules and focus records stay.
  Future<void> deleteTask(String taskId);
  Future<void> sync();
  Future<void> dispose();
}

class LocalTaskRepository implements TaskRepository {
  LocalTaskRepository({
    required this.database,
    required this.userId,
    required this.remote,
    this.cloudSyncEnabled = true,
    UserLifecycleAccess? lifecycleAccess,
    DateTime Function()? now,
    this.taskOrderStore = const GoalTaskOrderStore(),
  }) : lifecycleAccess =
           lifecycleAccess ?? const AlwaysActiveUserLifecycleAccess(),
       _now = now ?? DateTime.now;

  final PactaDatabase database;
  final String userId;
  final TaskRemoteDataSource remote;
  final bool cloudSyncEnabled;
  final UserLifecycleAccess lifecycleAccess;

  /// 未完成任务的手动顺序；默认使用本机偏好存储，测试可注入替身。
  final GoalTaskOrderStore taskOrderStore;
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
    for (final tasks in tasksByGoal.values) {
      tasks.sort(_compareTasks);
    }
    // 手动顺序是设备偏好：只影响本机读取的呈现，不写入任务行与快照。
    final visibleGoalIds = <String>[
      for (final row in goalRows)
        if (includeDeleted || row.deletedAt == null) row.id,
    ];
    final taskOrders = await Future.wait([
      for (final goalId in visibleGoalIds)
        taskOrderStore.load(userId: userId, goalId: goalId),
    ]);
    final ordersByGoal = <String, List<String>>{
      for (var index = 0; index < visibleGoalIds.length; index++)
        visibleGoalIds[index]: taskOrders[index],
    };
    final goals = <Goal>[];
    for (final row in goalRows) {
      if (!includeDeleted && row.deletedAt != null) continue;
      final applied = _applyManualTaskOrder(
        tasksByGoal[row.id] ?? const [],
        ordersByGoal[row.id] ?? const [],
      );
      goals.add(
        _goalFromRow(
          row,
          tasks: applied.tasks,
          // 只有真正命中至少一项未完成任务时才算"手动顺序生效"；旧顺序里
          // 的任务全部完成/删除后，新建任务必须回退到既有截止时间排序。
          hasManualTaskOrder: applied.hasManualOrder,
        ),
      );
    }
    goals.sort(_compareGoals);
    return goals;
  }

  /// 未完成在前、已完成在后；同组按最后更新时间，保持既有回退顺序。
  static int _compareTasks(Task left, Task right) {
    if (left.isComplete != right.isComplete) {
      return left.isComplete ? 1 : -1;
    }
    return left.updatedAt.compareTo(right.updatedAt);
  }

  /// 应用已保存的手动顺序。
  ///
  /// 已保存的未完成任务按保存顺序排在前面；保存之后才新增的未完成任务
  /// （或从已完成恢复的任务）沿用更新时间顺序接在其后；已完成任务始终
  /// 留在末尾。空顺序或全部失效时退回既有排序，不伪造顺序。
  ({List<Task> tasks, bool hasManualOrder}) _applyManualTaskOrder(
    List<Task> base,
    List<String> order,
  ) {
    if (order.isEmpty) {
      return (tasks: base, hasManualOrder: false);
    }
    final byId = {for (final task in base) task.id: task};
    final applied = <Task>[];
    final used = <String>{};
    for (final id in order) {
      final task = byId[id];
      if (task == null || task.isComplete) continue;
      if (!used.add(id)) continue;
      applied.add(task);
    }
    final appended = [
      for (final task in base)
        if (!task.isComplete && !used.contains(task.id)) task,
    ];
    final completed = [
      for (final task in base)
        if (task.isComplete) task,
    ];
    return (
      tasks: [...applied, ...appended, ...completed],
      // applied 为空说明保存过的顺序已全部失效（完成或删除）：此时只做
      // "未完成在前、已完成在后"的稳定分组，不应声称手动顺序仍生效。
      hasManualOrder: applied.isNotEmpty,
    );
  }

  /// Pinned goals lead in their manual order; the rest keep the established
  /// "has an unfinished task" then last-updated order. No user-visible task
  /// sorting control is introduced here.
  int _compareGoals(Goal left, Goal right) {
    if (left.isPinned != right.isPinned) return left.isPinned ? -1 : 1;
    if (left.isPinned) {
      final leftOrder = left.sortOrder ?? 1 << 30;
      final rightOrder = right.sortOrder ?? 1 << 30;
      if (leftOrder != rightOrder) return leftOrder.compareTo(rightOrder);
      final byCreated = left.createdAt.compareTo(right.createdAt);
      if (byCreated != 0) return byCreated;
      return left.id.compareTo(right.id);
    }
    // 未置顶目标一旦被手动排过序，就先按保存的序号；两边都没有序号时
    // 继续沿用既有"有未完成任务优先 + 最近更新"的回退顺序，旧数据不变。
    final leftOrder = left.sortOrder;
    final rightOrder = right.sortOrder;
    if (leftOrder != null || rightOrder != null) {
      final byOrder = (leftOrder ?? 1 << 30).compareTo(rightOrder ?? 1 << 30);
      if (byOrder != 0) return byOrder;
    }
    final leftHasExecutableTask = left.tasks.any((task) => !task.isComplete);
    final rightHasExecutableTask = right.tasks.any((task) => !task.isComplete);
    if (leftHasExecutableTask != rightHasExecutableTask) {
      return leftHasExecutableTask ? -1 : 1;
    }
    return left.updatedAt.compareTo(right.updatedAt);
  }

  @override
  Future<Goal> createGoal(GoalDraft draft) async {
    await lifecycleAccess.requireActive();
    final title = _requiredTitle(draft.title, '目标');
    final timestamp = _nextTimestamp();
    final goal = Goal(
      id: _uuid.v4(),
      title: title,
      description: normalizeDescription(draft.description),
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
    await lifecycleAccess.requireActive();
    final existing = await _findGoal(goalId);
    final updated = existing.copyWith(
      title: _requiredTitle(draft.title, '目标'),
      description: normalizeDescription(draft.description),
      classification: draft.classification,
      updatedAt: _nextTimestamp(existing.updatedAt),
    );
    await _saveGoal(updated);
    await _publish();
    return (await getGoals()).firstWhere((goal) => goal.id == goalId);
  }

  @override
  Future<void> deleteGoal(String goalId) async {
    await lifecycleAccess.requireActive();
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
  Future<void> setGoalPinned(String goalId, {required bool isPinned}) async {
    await lifecycleAccess.requireActive();
    final existing = await _findGoal(goalId);
    if (existing.isPinned == isPinned) return;
    final goals = await getGoals();
    final pinned = [
      for (final goal in goals)
        if (goal.isPinned && goal.id != goalId) goal,
    ];
    final nextOrder = pinned.isEmpty
        ? 0
        : pinned
                  .map((goal) => goal.sortOrder ?? 1 << 30)
                  .reduce((left, right) => left > right ? left : right) +
              1;
    final updatedAt = _nextTimestamp(existing.updatedAt);
    await (database.update(database.localGoals)
          ..where((goal) => goal.userId.equals(userId))
          ..where((goal) => goal.id.equals(goalId)))
        .write(
          LocalGoalsCompanion(
            isPinned: Value(isPinned),
            sortOrder: Value(isPinned ? nextOrder : null),
            updatedAt: Value(updatedAt),
          ),
        );
    await _publish();
  }

  @override
  Future<void> reorderPinnedGoals(List<String> orderedGoalIds) async {
    await lifecycleAccess.requireActive();
    final pinned = [
      for (final goal in await getGoals())
        if (goal.isPinned) goal,
    ];
    final pinnedIds = {for (final goal in pinned) goal.id};
    if (orderedGoalIds.length != pinnedIds.length ||
        orderedGoalIds.toSet().length != orderedGoalIds.length ||
        !pinnedIds.containsAll(orderedGoalIds)) {
      throw ArgumentError('排序必须且只能覆盖当前全部置顶目标。');
    }
    await database.transaction(() async {
      for (var index = 0; index < orderedGoalIds.length; index++) {
        await (database.update(database.localGoals)
              ..where((goal) => goal.userId.equals(userId))
              ..where((goal) => goal.id.equals(orderedGoalIds[index])))
            .write(LocalGoalsCompanion(sortOrder: Value(index)));
      }
    });
    await _publish();
  }

  @override
  Future<void> reorderUnpinnedGoals(List<String> orderedGoalIds) async {
    await lifecycleAccess.requireActive();
    final unpinnedIds = <String>{
      for (final goal in await getGoals())
        if (!goal.isPinned) goal.id,
    };
    if (orderedGoalIds.length != unpinnedIds.length ||
        orderedGoalIds.toSet().length != orderedGoalIds.length ||
        !unpinnedIds.containsAll(orderedGoalIds)) {
      throw ArgumentError('排序必须且只能覆盖当前全部未置顶目标。');
    }
    await database.transaction(() async {
      for (var index = 0; index < orderedGoalIds.length; index++) {
        await (database.update(database.localGoals)
              ..where((goal) => goal.userId.equals(userId))
              ..where((goal) => goal.id.equals(orderedGoalIds[index])))
            .write(LocalGoalsCompanion(sortOrder: Value(index)));
      }
    });
    await _publish();
  }

  @override
  Future<void> reorderTasks(String goalId, List<String> orderedTaskIds) async {
    await lifecycleAccess.requireActive();
    // _findGoal 同时校验归属：跨用户或已删除的目标不会被写入顺序。
    final goal = await _findGoal(goalId);
    final rows =
        await (database.select(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..where((task) => task.goalId.equals(goal.id))
              ..where((task) => task.deletedAt.isNull()))
            .get();
    final unfinishedIds = <String>{
      for (final row in rows)
        if (!row.isComplete) row.id,
    };
    if (orderedTaskIds.toSet().length != orderedTaskIds.length ||
        orderedTaskIds.length != unfinishedIds.length ||
        !unfinishedIds.containsAll(orderedTaskIds)) {
      throw ArgumentError('排序必须且只能覆盖该目标当前全部未完成任务。');
    }
    await taskOrderStore.save(
      userId: userId,
      goalId: goal.id,
      taskIds: orderedTaskIds,
    );
    await _publish();
  }

  @override
  Future<Task> createTask(String goalId, TaskDraft draft) async {
    await lifecycleAccess.requireActive();
    final goal = await _findGoal(goalId);
    final timestamp = _nextTimestamp();
    final task = Task(
      id: _uuid.v4(),
      goalId: goalId,
      title: _requiredTitle(draft.title, '任务'),
      description: normalizeDescription(draft.description),
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
    await lifecycleAccess.requireActive();
    final existing = await _findTask(taskId);
    final updated = existing.copyWith(
      title: _requiredTitle(draft.title, '任务'),
      description: normalizeDescription(draft.description),
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
    await lifecycleAccess.requireActive();
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
  Future<void> deleteTask(String taskId) async {
    await lifecycleAccess.requireActive();
    final existing = await _findTaskIncludingDeleted(taskId);
    if (existing.isDeleted) return;
    // 墓碑保留任务身份：已有日程、专注与暂停继续引用原任务名称，
    // 不隐式删除任何已拥有的安排，也不伪造新目标。
    final deletedAt = _nextTimestamp(existing.updatedAt);
    await _saveTask(
      existing.copyWith(deletedAt: deletedAt, updatedAt: deletedAt),
    );
    await _publish();
  }

  @override
  Future<void> sync() async {
    if (!cloudSyncEnabled) return;
    if (await lifecycleAccess.isSuspended()) return;
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
            description: Value(goal.description),
            classification: goal.classification.storageValue,
            createdAt: goal.createdAt,
            updatedAt: goal.updatedAt,
            deletedAt: Value(goal.deletedAt),
            isPinned: Value(goal.isPinned),
            sortOrder: Value(goal.sortOrder),
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
            description: Value(task.description),
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

  Future<Task> _findTaskIncludingDeleted(String taskId) async {
    final row =
        await (database.select(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..where((task) => task.id.equals(taskId)))
            .getSingleOrNull();
    if (row == null) throw StateError('任务不存在或已不属于当前用户。');
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

  Goal _goalFromRow(
    LocalGoal row, {
    List<Task> tasks = const [],
    bool hasManualTaskOrder = false,
  }) => Goal(
    id: row.id,
    title: row.title,
    description: row.description,
    classification: TaskClassification.fromStorage(row.classification),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    isPinned: row.isPinned,
    sortOrder: row.sortOrder,
    tasks: tasks,
    hasManualTaskOrder: hasManualTaskOrder,
  );

  Task _taskFromRow(LocalTask row) => Task(
    id: row.id,
    goalId: row.goalId,
    title: row.title,
    description: row.description,
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
    // 置顶与排序位只随整份账号快照往返；旧逐实体同步不理解这两列，
    // 因此合并时一律保留本机值，避免按远端默认值清空用户排序。
    final withPins = preferred.copyWith(
      isPinned: local.isPinned,
      sortOrder: local.sortOrder,
    );
    if (deletedAt == null) return withPins;
    return withPins.copyWith(
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
  Future<void> setGoalPinned(String goalId, {required bool isPinned}) =>
      _unavailable();

  @override
  Future<void> reorderPinnedGoals(List<String> orderedGoalIds) =>
      _unavailable();

  @override
  Future<void> reorderUnpinnedGoals(List<String> orderedGoalIds) =>
      _unavailable();

  @override
  Future<void> reorderTasks(String goalId, List<String> orderedTaskIds) =>
      _unavailable();

  @override
  Future<Task> createTask(String goalId, TaskDraft draft) => _unavailable();

  @override
  Future<Task> updateTask(String taskId, TaskDraft draft) => _unavailable();

  @override
  Future<void> setTaskCompletion(String taskId, {required bool isComplete}) =>
      _unavailable();

  @override
  Future<void> deleteTask(String taskId) => _unavailable();

  @override
  Future<void> sync() async {}

  @override
  Future<void> dispose() async {}

  Future<T> _unavailable<T>() async {
    throw StateError('当前用户的任务存储尚未配置。');
  }
}
