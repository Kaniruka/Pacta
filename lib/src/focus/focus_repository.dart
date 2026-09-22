import 'dart:async';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../tasks/task_database.dart' as db;
import 'focus_models.dart';

class FocusRemoteSnapshot {
  const FocusRemoteSnapshot({
    this.sessions = const [],
    this.nodes = const [],
    this.records = const [],
  });

  final List<FocusSession> sessions;
  final List<FocusNode> nodes;
  final List<FocusChainRecord> records;
}

abstract interface class FocusRemoteDataSource {
  Future<FocusRemoteSnapshot> pull({required String userId});

  Future<void> upsertSessions({
    required String userId,
    required List<FocusSession> sessions,
  });

  Future<void> upsertNodes({
    required String userId,
    required List<FocusNode> nodes,
  });

  Future<void> upsertRecords({
    required String userId,
    required List<FocusChainRecord> records,
  });
}

class UnavailableFocusRemoteDataSource implements FocusRemoteDataSource {
  const UnavailableFocusRemoteDataSource();

  @override
  Future<FocusRemoteSnapshot> pull({required String userId}) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> upsertSessions({
    required String userId,
    required List<FocusSession> sessions,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> upsertNodes({
    required String userId,
    required List<FocusNode> nodes,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }

  @override
  Future<void> upsertRecords({
    required String userId,
    required List<FocusChainRecord> records,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }
}

abstract interface class FocusRepository {
  Stream<List<FocusSession>> watchSessions();
  Future<List<FocusSession>> getSessions();
  Future<FocusSession?> getActiveSession();
  Future<FocusSession> startSession({
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  });
  Future<void> settleDueSessions();
  Future<List<FocusNode>> getNodes();
  Future<List<FocusChainRecord>> getChainRecords();
  Future<FocusChainMode> getLastMode();
  Future<void> sync();
  Future<void> dispose();
}

class LocalFocusRepository implements FocusRepository {
  LocalFocusRepository({
    required this.database,
    required this.userId,
    required this.remote,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final db.PactaDatabase database;
  final String userId;
  final FocusRemoteDataSource remote;
  final DateTime Function() _now;
  final _changes = StreamController<List<FocusSession>>.broadcast();
  final _uuid = const Uuid();

  @override
  Stream<List<FocusSession>> watchSessions() async* {
    yield await getSessions();
    yield* _changes.stream;
  }

  @override
  Future<List<FocusSession>> getSessions() async {
    await _settleDueSessions();
    final rows =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..orderBy([(session) => OrderingTerm.desc(session.startedAt)]))
            .get();
    return [for (final row in rows) _sessionFromRow(row)];
  }

  @override
  Future<FocusSession?> getActiveSession() async {
    await _settleDueSessions();
    final row =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..where((session) => session.status.equals('active'))
              ..orderBy([(session) => OrderingTerm.desc(session.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _sessionFromRow(row);
  }

  @override
  Future<FocusSession> startSession({
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  }) async {
    if (duration <= Duration.zero) {
      throw ArgumentError('专注时长必须大于 0。');
    }
    final task =
        await (database.select(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..where((task) => task.id.equals(taskId)))
            .getSingleOrNull();
    if (task == null) throw StateError('任务不存在或已不属于当前用户。');
    if (task.isComplete) throw StateError('已完成任务不能开始新的专注。');

    await _settleDueSessions();
    final existing = await getActiveSession();
    if (existing != null) return existing;

    final startedAt = _now().toUtc();
    final session = FocusSession(
      id: _uuid.v4(),
      taskId: taskId,
      mode: mode,
      durationSeconds: duration.inSeconds,
      startedAt: startedAt,
      endsAt: startedAt.add(duration),
      status: FocusSessionStatus.active,
      completedAt: null,
      effectiveSeconds: 0,
    );
    await database.transaction(() async {
      await _saveSession(session);
      await database
          .into(database.focusPreferences)
          .insertOnConflictUpdate(
            db.FocusPreferencesCompanion.insert(
              userId: userId,
              lastMode: mode.storageValue,
            ),
          );
    });
    await _publish();
    return session;
  }

  @override
  Future<void> settleDueSessions() => _settleDueSessions();

  Future<void> _settleDueSessions() async {
    final now = _now().toUtc();
    final rows =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..where((session) => session.status.equals('active'))
              ..where((session) => session.endsAt.isSmallerOrEqualValue(now)))
            .get();
    for (final row in rows) {
      await _completeSession(row.id, now: now);
    }
    if (rows.isNotEmpty) await _publish();
  }

  Future<void> _completeSession(
    String sessionId, {
    required DateTime now,
  }) async {
    await database.transaction(() async {
      final row =
          await (database.select(database.focusSessions)
                ..where((session) => session.userId.equals(userId))
                ..where((session) => session.id.equals(sessionId)))
              .getSingleOrNull();
      if (row == null || row.status != 'active' || row.endsAt.isAfter(now)) {
        return;
      }
      final seconds = row.durationSeconds;
      final completedAt = row.endsAt;
      await (database.update(database.focusSessions)
            ..where((session) => session.userId.equals(userId))
            ..where((session) => session.id.equals(sessionId)))
          .write(
            db.FocusSessionsCompanion(
              status: const Value('completed'),
              completedAt: Value(completedAt),
              effectiveSeconds: Value(seconds),
            ),
          );

      // One node is generated per logical session. Reusing the session UUID
      // makes the completion idempotent both locally and in Supabase.
      final nodeId = sessionId;
      final existingNode =
          await (database.select(database.focusNodes)
                ..where((node) => node.userId.equals(userId))
                ..where((node) => node.id.equals(nodeId)))
              .getSingleOrNull();
      if (existingNode == null) {
        await database
            .into(database.focusNodes)
            .insert(
              db.FocusNodesCompanion.insert(
                userId: userId,
                id: nodeId,
                sessionId: sessionId,
                taskId: row.taskId,
                mode: row.mode,
                createdAt: completedAt,
                effectiveSeconds: seconds,
              ),
            );

        final task =
            await (database.select(database.localTasks)
                  ..where((task) => task.userId.equals(userId))
                  ..where((task) => task.id.equals(row.taskId)))
                .getSingleOrNull();
        if (task != null) {
          await (database.update(database.localTasks)
                ..where((task) => task.userId.equals(userId))
                ..where((task) => task.id.equals(row.taskId)))
              .write(
                db.LocalTasksCompanion(
                  focusProgressSeconds: Value(
                    task.focusProgressSeconds + seconds,
                  ),
                ),
              );
          await _queue('task', row.taskId, completedAt);
        }

        final mode = row.mode;
        final record =
            await (database.select(database.focusChainRecords)
                  ..where((entry) => entry.userId.equals(userId))
                  ..where((entry) => entry.mode.equals(mode)))
                .getSingleOrNull();
        final current = (record?.currentConsecutive ?? 0) + 1;
        final best = current > (record?.bestConsecutive ?? 0)
            ? current
            : (record?.bestConsecutive ?? 0);
        await database
            .into(database.focusChainRecords)
            .insertOnConflictUpdate(
              db.FocusChainRecordsCompanion.insert(
                userId: userId,
                mode: mode,
                currentConsecutive: Value(current),
                bestConsecutive: Value(best),
                updatedAt: completedAt,
              ),
            );
        await _queue('focus_node', nodeId, completedAt);
        await _queue('focus_chain', mode, completedAt);
      }
      await _queue('focus_session', sessionId, completedAt);
    });
  }

  @override
  Future<List<FocusNode>> getNodes() async {
    final rows =
        await (database.select(database.focusNodes)
              ..where((node) => node.userId.equals(userId))
              ..orderBy([(node) => OrderingTerm.desc(node.createdAt)]))
            .get();
    return [for (final row in rows) _nodeFromRow(row)];
  }

  @override
  Future<List<FocusChainRecord>> getChainRecords() async {
    final rows = await (database.select(
      database.focusChainRecords,
    )..where((record) => record.userId.equals(userId))).get();
    final byMode = {for (final row in rows) row.mode: _recordFromRow(row)};
    final now = _now().toUtc();
    return [
      for (final mode in FocusChainMode.values)
        byMode[mode.storageValue] ??
            FocusChainRecord(
              mode: mode,
              currentConsecutive: 0,
              bestConsecutive: 0,
              updatedAt: now,
            ),
    ];
  }

  @override
  Future<FocusChainMode> getLastMode() async {
    final row = await (database.select(
      database.focusPreferences,
    )..where((entry) => entry.userId.equals(userId))).getSingleOrNull();
    return row == null
        ? FocusChainMode.regular
        : FocusChainMode.fromStorage(row.lastMode);
  }

  @override
  Future<void> sync() async {
    await _settleDueSessions();
    final snapshot = await remote.pull(userId: userId);
    for (final session in snapshot.sessions) {
      final local =
          await (database.select(database.focusSessions)
                ..where((row) => row.userId.equals(userId))
                ..where((row) => row.id.equals(session.id)))
              .getSingleOrNull();
      if (local == null ||
          (local.status == 'active' &&
              session.status == FocusSessionStatus.completed)) {
        await _saveSession(session, queue: false);
      }
    }
    for (final node in snapshot.nodes) {
      await database
          .into(database.focusNodes)
          .insertOnConflictUpdate(
            db.FocusNodesCompanion.insert(
              userId: userId,
              id: node.id,
              sessionId: node.sessionId,
              taskId: node.taskId,
              mode: node.mode.storageValue,
              createdAt: node.createdAt,
              effectiveSeconds: node.effectiveSeconds,
            ),
          );
    }
    for (final record in snapshot.records) {
      await database
          .into(database.focusChainRecords)
          .insertOnConflictUpdate(
            db.FocusChainRecordsCompanion.insert(
              userId: userId,
              mode: record.mode.storageValue,
              currentConsecutive: Value(record.currentConsecutive),
              bestConsecutive: Value(record.bestConsecutive),
              updatedAt: record.updatedAt,
            ),
          );
    }
    final sessions = await getSessions();
    final nodes = await getNodes();
    final records = await getChainRecords();
    if (sessions.isNotEmpty) {
      await remote.upsertSessions(userId: userId, sessions: sessions);
    }
    if (nodes.isNotEmpty) {
      await remote.upsertNodes(userId: userId, nodes: nodes);
    }
    await remote.upsertRecords(userId: userId, records: records);
    await _publish();
  }

  @override
  Future<void> dispose() => _changes.close();

  Future<void> _saveSession(FocusSession session, {bool queue = true}) async {
    await database
        .into(database.focusSessions)
        .insertOnConflictUpdate(
          db.FocusSessionsCompanion.insert(
            userId: userId,
            id: session.id,
            taskId: session.taskId,
            mode: session.mode.storageValue,
            durationSeconds: session.durationSeconds,
            startedAt: session.startedAt,
            endsAt: session.endsAt,
            status: session.status.storageValue,
            completedAt: Value(session.completedAt),
            effectiveSeconds: Value(session.effectiveSeconds),
          ),
        );
    if (queue) await _queue('focus_session', session.id, session.startedAt);
  }

  Future<void> _queue(String type, String id, DateTime updatedAt) async {
    await database
        .into(database.taskSyncEntries)
        .insertOnConflictUpdate(
          db.TaskSyncEntriesCompanion.insert(
            userId: userId,
            entityType: type,
            entityId: id,
            updatedAt: updatedAt,
          ),
        );
  }

  Future<void> _publish() async {
    if (_changes.hasListener) _changes.add(await _getSessionsWithoutSettling());
  }

  Future<List<FocusSession>> _getSessionsWithoutSettling() async {
    final rows =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..orderBy([(session) => OrderingTerm.desc(session.startedAt)]))
            .get();
    return [for (final row in rows) _sessionFromRow(row)];
  }

  FocusSession _sessionFromRow(db.FocusSession row) => FocusSession(
    id: row.id,
    taskId: row.taskId,
    mode: FocusChainMode.fromStorage(row.mode),
    durationSeconds: row.durationSeconds,
    startedAt: row.startedAt,
    endsAt: row.endsAt,
    status: row.status == 'active'
        ? FocusSessionStatus.active
        : FocusSessionStatus.completed,
    completedAt: row.completedAt,
    effectiveSeconds: row.effectiveSeconds,
  );

  FocusNode _nodeFromRow(db.FocusNode row) => FocusNode(
    id: row.id,
    sessionId: row.sessionId,
    taskId: row.taskId,
    mode: FocusChainMode.fromStorage(row.mode),
    createdAt: row.createdAt,
    effectiveSeconds: row.effectiveSeconds,
  );

  FocusChainRecord _recordFromRow(db.FocusChainRecord row) => FocusChainRecord(
    mode: FocusChainMode.fromStorage(row.mode),
    currentConsecutive: row.currentConsecutive,
    bestConsecutive: row.bestConsecutive,
    updatedAt: row.updatedAt,
  );
}

class SupabaseFocusRemoteDataSource implements FocusRemoteDataSource {
  SupabaseFocusRemoteDataSource(this.client);

  final SupabaseClient client;

  @override
  Future<FocusRemoteSnapshot> pull({required String userId}) async {
    final sessions = await client.from('focus_sessions').select();
    final nodes = await client.from('focus_nodes').select();
    final records = await client.from('focus_chain_records').select();
    return FocusRemoteSnapshot(
      sessions: [for (final row in sessions) _sessionFromJson(row)],
      nodes: [for (final row in nodes) _nodeFromJson(row)],
      records: [for (final row in records) _recordFromJson(row)],
    );
  }

  @override
  Future<void> upsertSessions({
    required String userId,
    required List<FocusSession> sessions,
  }) async {
    await client.from('focus_sessions').upsert([
      for (final session in sessions)
        {
          'id': session.id,
          'user_id': userId,
          'task_id': session.taskId,
          'mode': session.mode.storageValue,
          'duration_seconds': session.durationSeconds,
          'started_at': _utcIso8601(session.startedAt),
          'ends_at': _utcIso8601(session.endsAt),
          'status': session.status.storageValue,
          'completed_at': session.completedAt == null
              ? null
              : _utcIso8601(session.completedAt!),
          'effective_seconds': session.effectiveSeconds,
        },
    ], onConflict: 'id');
  }

  @override
  Future<void> upsertNodes({
    required String userId,
    required List<FocusNode> nodes,
  }) async {
    await client.from('focus_nodes').upsert([
      for (final node in nodes)
        {
          'id': node.id,
          'user_id': userId,
          'session_id': node.sessionId,
          'task_id': node.taskId,
          'mode': node.mode.storageValue,
          'created_at': _utcIso8601(node.createdAt),
          'effective_seconds': node.effectiveSeconds,
        },
    ], onConflict: 'id');
  }

  @override
  Future<void> upsertRecords({
    required String userId,
    required List<FocusChainRecord> records,
  }) async {
    await client.from('focus_chain_records').upsert([
      for (final record in records)
        {
          'user_id': userId,
          'mode': record.mode.storageValue,
          'current_consecutive': record.currentConsecutive,
          'best_consecutive': record.bestConsecutive,
          'updated_at': _utcIso8601(record.updatedAt),
        },
    ], onConflict: 'user_id,mode');
  }

  FocusSession _sessionFromJson(Map<String, dynamic> json) => FocusSession(
    id: json['id'] as String,
    taskId: json['task_id'] as String,
    mode: FocusChainMode.fromStorage(json['mode'] as String),
    durationSeconds: json['duration_seconds'] as int,
    startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
    endsAt: DateTime.parse(json['ends_at'] as String).toUtc(),
    status: json['status'] == 'active'
        ? FocusSessionStatus.active
        : FocusSessionStatus.completed,
    completedAt: (json['completed_at'] as String?) == null
        ? null
        : DateTime.parse(json['completed_at'] as String).toUtc(),
    effectiveSeconds: json['effective_seconds'] as int,
  );

  FocusNode _nodeFromJson(Map<String, dynamic> json) => FocusNode(
    id: json['id'] as String,
    sessionId: json['session_id'] as String,
    taskId: json['task_id'] as String,
    mode: FocusChainMode.fromStorage(json['mode'] as String),
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    effectiveSeconds: json['effective_seconds'] as int,
  );

  FocusChainRecord _recordFromJson(Map<String, dynamic> json) =>
      FocusChainRecord(
        mode: FocusChainMode.fromStorage(json['mode'] as String),
        currentConsecutive: json['current_consecutive'] as int,
        bestConsecutive: json['best_consecutive'] as int,
        updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      );
}

String _utcIso8601(DateTime value) => value.toUtc().toIso8601String();

class InMemoryFocusRemote implements FocusRemoteDataSource {
  final _sessions = <String, Map<String, FocusSession>>{};
  final _nodes = <String, Map<String, FocusNode>>{};
  final _records = <String, Map<String, FocusChainRecord>>{};

  @override
  Future<FocusRemoteSnapshot> pull({required String userId}) async {
    return FocusRemoteSnapshot(
      sessions: (_sessions[userId] ?? {}).values.toList(),
      nodes: (_nodes[userId] ?? {}).values.toList(),
      records: (_records[userId] ?? {}).values.toList(),
    );
  }

  @override
  Future<void> upsertSessions({
    required String userId,
    required List<FocusSession> sessions,
  }) async {
    final target = _sessions.putIfAbsent(userId, () => {});
    for (final session in sessions) {
      target[session.id] = session;
    }
  }

  @override
  Future<void> upsertNodes({
    required String userId,
    required List<FocusNode> nodes,
  }) async {
    final target = _nodes.putIfAbsent(userId, () => {});
    for (final node in nodes) {
      target[node.id] = node;
    }
  }

  @override
  Future<void> upsertRecords({
    required String userId,
    required List<FocusChainRecord> records,
  }) async {
    final target = _records.putIfAbsent(userId, () => {});
    for (final record in records) {
      target[record.mode.storageValue] = record;
    }
  }
}

class UnavailableFocusRepository implements FocusRepository {
  const UnavailableFocusRepository();

  @override
  Stream<List<FocusSession>> watchSessions() => Stream.value(const []);

  @override
  Future<List<FocusSession>> getSessions() async => const [];

  @override
  Future<FocusSession?> getActiveSession() async => null;

  @override
  Future<FocusSession> startSession({
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  }) => _unavailable();

  @override
  Future<void> settleDueSessions() async {}

  @override
  Future<List<FocusNode>> getNodes() async => const [];

  @override
  Future<List<FocusChainRecord>> getChainRecords() async => const [];

  @override
  Future<FocusChainMode> getLastMode() async => FocusChainMode.regular;

  @override
  Future<void> sync() async {}

  @override
  Future<void> dispose() async {}

  Future<T> _unavailable<T>() async {
    throw StateError('当前用户的专注存储尚未配置。');
  }
}
