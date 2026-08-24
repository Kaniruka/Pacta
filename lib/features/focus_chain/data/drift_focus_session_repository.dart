import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/domain/focus_chain_models.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_models.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_repository.dart';
import 'package:pacta/features/focus_chain/data/supabase_focus_session_source.dart';
import 'package:pacta/private_data/app_database.dart';
import 'package:uuid/uuid.dart';

class DriftFocusSessionRepository implements FocusSessionRepository {
  DriftFocusSessionRepository({
    required AppDatabase database,
    RemoteFocusSessionSource? remote,
    Uuid? ids,
    DateTime Function()? clock,
  }) : _database = database,
       _remote = remote,
       _ids = ids ?? const Uuid(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase _database;
  final RemoteFocusSessionSource? _remote;
  final Uuid _ids;
  final DateTime Function() _clock;
  final _controllers = <String, StreamController<FocusSession>>{};

  @override
  Future<FocusSession> start(
    AppUserId userId,
    FocusSessionConfig config,
  ) async {
    if (config.task.userId != userId) {
      throw ArgumentError('A Focus Session Task must belong to this User.');
    }
    final taskRow =
        await (_database.select(_database.cachedTasks)..where(
              (row) =>
                  row.userId.equals(userId.value) &
                  row.id.equals(config.task.id),
            ))
            .getSingleOrNull();
    if (taskRow == null) {
      throw StateError('Task ${config.task.id} was not found.');
    }
    if (taskRow.completedAt != null) {
      throw StateError('A completed Task cannot start a Focus Session.');
    }

    final activeRow =
        await (_database.select(_database.cachedFocusSessions)..where(
              (row) =>
                  row.userId.equals(userId.value) &
                  row.taskId.equals(config.task.id) &
                  row.outcome.isNull(),
            ))
            .getSingleOrNull();
    if (activeRow != null) {
      final active = _sessionFromRow(activeRow);
      await _emit(userId, active.id);
      return active;
    }

    final now = _clock().toUtc();
    final session = FocusSession(
      id: _ids.v4(),
      userId: userId,
      taskId: config.task.id,
      mode: config.mode,
      plannedDuration: config.duration,
      startedAt: now,
      outcome: null,
      actualElapsed: Duration.zero,
      createdAt: now,
      updatedAt: now,
      mutationId: _mutationId(now, config.task.id),
    );
    await _database.transaction(() async {
      await _database
          .into(_database.cachedFocusSessions)
          .insert(_sessionCompanion(session));
      await _writeOutbox(
        userId: userId,
        entityType: 'session',
        entityId: session.id,
        mutationId: session.mutationId,
        updatedAt: session.updatedAt,
        payload: _sessionPayload(session),
      );
    });
    await _emit(userId, session.id, session);
    return session;
  }

  @override
  Future<FocusSession?> read(AppUserId userId, String sessionId) async {
    final row =
        await (_database.select(_database.cachedFocusSessions)..where(
              (candidate) =>
                  candidate.userId.equals(userId.value) &
                  candidate.id.equals(sessionId),
            ))
            .getSingleOrNull();
    return row == null ? null : _sessionFromRow(row);
  }

  @override
  Stream<FocusSession> watch(AppUserId userId, String sessionId) {
    final key = _key(userId, sessionId);
    final controller = _controllers.putIfAbsent(
      key,
      () => StreamController<FocusSession>.broadcast(
        onListen: () => unawaited(_emit(userId, sessionId)),
      ),
    );
    return controller.stream;
  }

  @override
  Future<FocusSession> reconcile(AppUserId userId, String sessionId) async {
    final existing = await read(userId, sessionId);
    if (existing == null) {
      throw StateError('Focus Session $sessionId was not found.');
    }
    if (!existing.isActive) return existing;

    final now = _clock().toUtc();
    final clockState = FocusSessionClockState.fromSession(existing, now);
    if (!clockState.reachedZero) {
      await _emit(userId, sessionId, existing);
      return existing;
    }

    final completed = await _database.transaction<FocusSession>(() async {
      final currentRow =
          await (_database.select(_database.cachedFocusSessions)..where(
                (candidate) =>
                    candidate.userId.equals(userId.value) &
                    candidate.id.equals(sessionId),
              ))
              .getSingleOrNull();
      if (currentRow == null) {
        throw StateError('Focus Session $sessionId was not found.');
      }
      if (currentRow.outcome == _outcomeWire(FocusSessionOutcome.completed)) {
        return _sessionFromRow(currentRow);
      }

      final current = _sessionFromRow(currentRow);
      final currentClock = FocusSessionClockState.fromSession(current, now);
      if (!currentClock.reachedZero) return current;

      final completedAt = now;
      final elapsedSeconds = current.plannedDuration.inSeconds;
      final completedSession = current.copyWith(
        outcome: FocusSessionOutcome.completed,
        actualElapsed: Duration(seconds: elapsedSeconds),
        completedAt: completedAt,
        updatedAt: completedAt,
        mutationId: _mutationId(completedAt, current.id),
      );
      await _database
          .into(_database.cachedFocusSessions)
          .insertOnConflictUpdate(_sessionCompanion(completedSession));
      await _writeOutbox(
        userId: userId,
        entityType: 'session',
        entityId: completedSession.id,
        mutationId: completedSession.mutationId,
        updatedAt: completedSession.updatedAt,
        payload: _sessionPayload(completedSession),
      );

      final taskRow =
          await (_database.select(_database.cachedTasks)..where(
                (candidate) =>
                    candidate.userId.equals(userId.value) &
                    candidate.id.equals(current.taskId),
              ))
              .getSingleOrNull();
      if (taskRow == null) {
        throw StateError('Task ${current.taskId} was not found.');
      }
      final taskMutationId = _mutationId(completedAt, taskRow.id);
      final nextProgress = taskRow.focusProgressSeconds + elapsedSeconds;
      await _database
          .into(_database.cachedTasks)
          .insertOnConflictUpdate(
            CachedTasksCompanion.insert(
              id: taskRow.id,
              userId: taskRow.userId,
              goalId: taskRow.goalId,
              title: taskRow.title,
              notes: Value(taskRow.notes),
              deadline: Value(taskRow.deadline),
              estimatedSeconds: Value(taskRow.estimatedSeconds),
              classification: taskRow.classification,
              focusProgressSeconds: Value(nextProgress),
              completedAt: Value(taskRow.completedAt),
              createdAt: taskRow.createdAt,
              updatedAt: completedAt,
              mutationId: taskMutationId,
            ),
          );
      await _database
          .into(_database.goalTaskOutbox)
          .insertOnConflictUpdate(
            GoalTaskOutboxCompanion.insert(
              userId: userId.value,
              entityType: 'task',
              entityId: taskRow.id,
              mutationId: taskMutationId,
              updatedAt: completedAt,
              payload: jsonEncode(
                _taskPayload(
                  taskRow,
                  nextProgress,
                  completedAt,
                  taskMutationId,
                ),
              ),
            ),
          );

      final node = FocusNode(
        id: current.id,
        userId: userId,
        sessionId: current.id,
        taskId: current.taskId,
        mode: current.mode,
        elapsed: Duration(seconds: elapsedSeconds),
        createdAt: completedAt,
        mutationId: _mutationId(completedAt, '${current.id}-node'),
      );
      await _database
          .into(_database.cachedFocusNodes)
          .insertOnConflictUpdate(_nodeCompanion(node));
      await _writeOutbox(
        userId: userId,
        entityType: 'node',
        entityId: node.id,
        mutationId: node.mutationId,
        updatedAt: node.createdAt,
        payload: _nodePayload(node),
      );
      return completedSession;
    });
    await _emit(userId, sessionId, completed);
    return completed;
  }

  @override
  Future<List<FocusNode>> readNodes(AppUserId userId, String sessionId) async {
    final rows =
        await (_database.select(_database.cachedFocusNodes)..where(
              (row) =>
                  row.userId.equals(userId.value) &
                  row.sessionId.equals(sessionId),
            ))
            .get();
    return rows.map(_nodeFromRow).toList(growable: false);
  }

  @override
  Future<void> sync(AppUserId userId) async {
    final remote = _remote;
    if (remote == null) return;
    final pendingRows =
        await (_database.select(_database.focusSessionOutbox)
              ..where((row) => row.userId.equals(userId.value))
              ..orderBy([(row) => OrderingTerm.asc(row.updatedAt)]))
            .get();
    final mutations = pendingRows
        .map(
          (row) => FocusSessionMutation(
            userId: userId,
            entityType: row.entityType,
            entityId: row.entityId,
            mutationId: row.mutationId,
            updatedAt: row.updatedAt.toUtc(),
            payload: Map<String, Object?>.from(jsonDecode(row.payload) as Map),
          ),
        )
        .toList(growable: false);

    late final RemoteFocusSessionSnapshot snapshot;
    try {
      snapshot = await remote.exchange(userId, mutations);
    } on RemoteFocusSessionUnavailable {
      return;
    }
    await _database.transaction(() async {
      for (final session in snapshot.sessions) {
        if (session.userId != userId) continue;
        final taskExists =
            await (_database.select(_database.cachedTasks)..where(
                  (row) =>
                      row.userId.equals(userId.value) &
                      row.id.equals(session.taskId),
                ))
                .getSingleOrNull();
        if (taskExists == null) continue;
        final local =
            await (_database.select(_database.cachedFocusSessions)..where(
                  (row) =>
                      row.userId.equals(userId.value) &
                      row.id.equals(session.id),
                ))
                .getSingleOrNull();
        if (local == null ||
            _winsFocus(
              session.updatedAt,
              session.mutationId,
              local.updatedAt,
              local.mutationId,
            )) {
          await _database
              .into(_database.cachedFocusSessions)
              .insertOnConflictUpdate(_sessionCompanion(session));
        }
      }
      for (final node in snapshot.nodes) {
        if (node.userId != userId) continue;
        final sessionExists =
            await (_database.select(_database.cachedFocusSessions)..where(
                  (row) =>
                      row.userId.equals(userId.value) &
                      row.id.equals(node.sessionId),
                ))
                .getSingleOrNull();
        final taskExists =
            await (_database.select(_database.cachedTasks)..where(
                  (row) =>
                      row.userId.equals(userId.value) &
                      row.id.equals(node.taskId),
                ))
                .getSingleOrNull();
        if (sessionExists == null || taskExists == null) continue;
        await _database
            .into(_database.cachedFocusNodes)
            .insertOnConflictUpdate(_nodeCompanion(node));
      }
      for (final mutationId in snapshot.acceptedMutationIds) {
        await (_database.delete(_database.focusSessionOutbox)..where(
              (row) =>
                  row.userId.equals(userId.value) &
                  row.mutationId.equals(mutationId),
            ))
            .go();
      }
    });
    for (final session in snapshot.sessions) {
      await _emit(userId, session.id, session);
    }
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
        .into(_database.focusSessionOutbox)
        .insertOnConflictUpdate(
          FocusSessionOutboxCompanion.insert(
            userId: userId.value,
            entityType: entityType,
            entityId: entityId,
            mutationId: mutationId,
            updatedAt: updatedAt,
            payload: jsonEncode(payload),
          ),
        );
  }

  Future<void> _emit(
    AppUserId userId,
    String sessionId, [
    FocusSession? session,
  ]) async {
    final controller = _controllers[_key(userId, sessionId)];
    if (controller == null || controller.isClosed || !controller.hasListener) {
      return;
    }
    final value = session ?? await read(userId, sessionId);
    if (value != null) controller.add(value);
  }

  String _key(AppUserId userId, String sessionId) =>
      '${userId.value}:$sessionId';

  FocusSession _sessionFromRow(FocusSessionRow row) => FocusSession(
    id: row.id,
    userId: AppUserId(row.userId),
    taskId: row.taskId,
    mode: _modeFromWire(row.mode),
    plannedDuration: Duration(seconds: row.plannedSeconds),
    startedAt: row.startedAt,
    outcome: _outcomeFromWire(row.outcome),
    actualElapsed: Duration(seconds: row.actualElapsedSeconds),
    completedAt: row.completedAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    mutationId: row.mutationId,
  );

  FocusNode _nodeFromRow(FocusNodeRow row) => FocusNode(
    id: row.id,
    userId: AppUserId(row.userId),
    sessionId: row.sessionId,
    taskId: row.taskId,
    mode: _modeFromWire(row.mode),
    elapsed: Duration(seconds: row.elapsedSeconds),
    createdAt: row.createdAt,
    mutationId: row.mutationId,
  );

  CachedFocusSessionsCompanion _sessionCompanion(FocusSession session) =>
      CachedFocusSessionsCompanion.insert(
        id: session.id,
        userId: session.userId.value,
        taskId: session.taskId,
        mode: session.mode.name,
        plannedSeconds: session.plannedDuration.inSeconds,
        startedAt: session.startedAt,
        actualElapsedSeconds: Value(session.actualElapsed.inSeconds),
        outcome: Value(_outcomeWire(session.outcome)),
        completedAt: Value(session.completedAt),
        createdAt: session.createdAt,
        updatedAt: session.updatedAt,
        mutationId: session.mutationId,
      );

  CachedFocusNodesCompanion _nodeCompanion(FocusNode node) =>
      CachedFocusNodesCompanion.insert(
        id: node.id,
        userId: node.userId.value,
        sessionId: node.sessionId,
        taskId: node.taskId,
        mode: node.mode.name,
        elapsedSeconds: node.elapsed.inSeconds,
        createdAt: node.createdAt,
        mutationId: node.mutationId,
      );

  Map<String, Object?> _sessionPayload(FocusSession session) => {
    'id': session.id,
    'user_id': session.userId.value,
    'task_id': session.taskId,
    'mode': session.mode.name,
    'planned_seconds': session.plannedDuration.inSeconds,
    'started_at': session.startedAt.toIso8601String(),
    'actual_elapsed_seconds': session.actualElapsed.inSeconds,
    'outcome': _outcomeWire(session.outcome),
    'completed_at': session.completedAt?.toIso8601String(),
    'created_at': session.createdAt.toIso8601String(),
    'updated_at': session.updatedAt.toIso8601String(),
    'mutation_id': session.mutationId,
  };

  Map<String, Object?> _nodePayload(FocusNode node) => {
    'id': node.id,
    'user_id': node.userId.value,
    'session_id': node.sessionId,
    'task_id': node.taskId,
    'mode': node.mode.name,
    'elapsed_seconds': node.elapsed.inSeconds,
    'created_at': node.createdAt.toIso8601String(),
    'mutation_id': node.mutationId,
  };

  Map<String, Object?> _taskPayload(
    CachedTaskRow row,
    int focusProgressSeconds,
    DateTime updatedAt,
    String mutationId,
  ) => {
    'id': row.id,
    'user_id': row.userId,
    'goal_id': row.goalId,
    'title': row.title,
    'notes': row.notes,
    'deadline': row.deadline?.toIso8601String(),
    'estimated_seconds': row.estimatedSeconds,
    'classification': row.classification,
    'focus_progress_seconds': focusProgressSeconds,
    'completed_at': row.completedAt?.toIso8601String(),
    'created_at': row.createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'mutation_id': mutationId,
  };

  String _mutationId(DateTime updatedAt, String entityId) =>
      '${updatedAt.microsecondsSinceEpoch}-$entityId';
}

String? _outcomeWire(FocusSessionOutcome? outcome) => outcome?.name;

FocusSessionOutcome? _outcomeFromWire(String? value) =>
    value == null ? null : FocusSessionOutcome.values.byName(value);

FocusChainMode _modeFromWire(String value) =>
    FocusChainMode.values.byName(value);

bool _winsFocus(
  DateTime incomingTime,
  String incomingMutation,
  DateTime localTime,
  String localMutation,
) {
  final timeComparison = incomingTime.compareTo(localTime);
  if (timeComparison != 0) return timeComparison > 0;
  return incomingMutation.compareTo(localMutation) > 0;
}
