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
    this.precedentRules = const [],
  });

  final List<FocusSession> sessions;
  final List<FocusNode> nodes;
  final List<FocusChainRecord> records;
  final List<PrecedentRule> precedentRules;
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

  Future<void> upsertPrecedentRules({
    required String userId,
    required List<PrecedentRule> rules,
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

  @override
  Future<void> upsertPrecedentRules({
    required String userId,
    required List<PrecedentRule> rules,
  }) async {
    throw StateError('当前未配置 Supabase，专注记录将先保存在本机。');
  }
}

abstract interface class FocusRepository {
  Stream<List<FocusSession>> watchSessions();
  Future<List<FocusSession>> getSessions();
  Future<FocusSession?> getSession(String sessionId);
  Future<FocusSession?> getActiveSession();
  Future<FocusSession> startSession({
    required String taskId,
    required FocusChainMode mode,
    required Duration duration,
  });
  Future<void> settleDueSessions();
  Future<FocusSession> pauseSession(
    String sessionId, {
    required String ruleText,
  });
  Future<FocusSession> resumeSession(String sessionId);
  Future<FocusSession> completeEarlySession({
    required String sessionId,
    required String ruleText,
  });
  Future<FocusSession> abandonSession({
    required String sessionId,
    required String failureReason,
  });
  Future<void> updateFailureReason({
    required String sessionId,
    required String failureReason,
  });
  Future<void> updateNodeNote({required String nodeId, required String note});
  Future<List<FocusNode>> getNodes();
  Future<List<FocusChainRecord>> getChainRecords();
  Future<List<PrecedentRule>> getPrecedentRules();
  Future<PrecedentRule> createPrecedentRule({required String text});
  Future<PrecedentRule> updatePrecedentRule({
    required String ruleId,
    required String text,
  });
  Future<void> deletePrecedentRule(String ruleId);
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
              ..where((session) => session.status.isIn(['active', 'paused']))
              ..orderBy([(session) => OrderingTerm.desc(session.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _sessionFromRow(row);
  }

  @override
  Future<FocusSession?> getSession(String sessionId) async {
    await _settleDueSessions();
    final row =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..where((session) => session.id.equals(sessionId)))
            .getSingleOrNull();
    return row == null ? null : _sessionFromRow(row);
  }

  @override
  Future<List<PrecedentRule>> getPrecedentRules() async {
    final rows =
        await (database.select(database.focusPrecedentRules)
              ..where((rule) => rule.userId.equals(userId))
              ..where((rule) => rule.deletedAt.isNull())
              ..orderBy([(rule) => OrderingTerm.desc(rule.updatedAt)]))
            .get();
    return [for (final row in rows) _precedentRuleFromRow(row)];
  }

  @override
  Future<PrecedentRule> createPrecedentRule({required String text}) async {
    final ruleText = _requiredRuleText(text);
    final now = _now().toUtc();
    final rule = PrecedentRule(
      id: _uuid.v4(),
      text: ruleText,
      createdAt: now,
      updatedAt: now,
    );
    await database
        .into(database.focusPrecedentRules)
        .insert(
          db.FocusPrecedentRulesCompanion.insert(
            userId: userId,
            id: rule.id,
            ruleText: rule.text,
            createdAt: rule.createdAt,
            updatedAt: rule.updatedAt,
          ),
        );
    await _queue('focus_precedent_rule', rule.id, now);
    return rule;
  }

  @override
  Future<PrecedentRule> updatePrecedentRule({
    required String ruleId,
    required String text,
  }) async {
    final ruleText = _requiredRuleText(text);
    final row =
        await (database.select(database.focusPrecedentRules)
              ..where((rule) => rule.userId.equals(userId))
              ..where((rule) => rule.id.equals(ruleId)))
            .getSingleOrNull();
    if (row == null || row.deletedAt != null) {
      throw StateError('下必为例不存在或已删除。');
    }
    final now = _now().toUtc();
    await (database.update(database.focusPrecedentRules)
          ..where((rule) => rule.userId.equals(userId))
          ..where((rule) => rule.id.equals(ruleId)))
        .write(
          db.FocusPrecedentRulesCompanion(
            ruleText: Value(ruleText),
            updatedAt: Value(now),
          ),
        );
    await _queue('focus_precedent_rule', ruleId, now);
    return PrecedentRule(
      id: row.id,
      text: ruleText,
      createdAt: row.createdAt,
      updatedAt: now,
    );
  }

  @override
  Future<void> deletePrecedentRule(String ruleId) async {
    final row =
        await (database.select(database.focusPrecedentRules)
              ..where((rule) => rule.userId.equals(userId))
              ..where((rule) => rule.id.equals(ruleId)))
            .getSingleOrNull();
    if (row == null || row.deletedAt != null) return;
    final now = _now().toUtc();
    await (database.update(database.focusPrecedentRules)
          ..where((rule) => rule.userId.equals(userId))
          ..where((rule) => rule.id.equals(ruleId)))
        .write(
          db.FocusPrecedentRulesCompanion(
            updatedAt: Value(now),
            deletedAt: Value(now),
          ),
        );
    await _queue('focus_precedent_rule', ruleId, now);
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

  @override
  Future<FocusSession> pauseSession(
    String sessionId, {
    required String ruleText,
  }) async {
    final normalizedRule = _requiredRuleText(ruleText);
    await _settleDueSessions();
    final now = _now().toUtc();
    await database.transaction(() async {
      final row = await _sessionRow(sessionId);
      if (row == null) throw StateError('专注会话不存在或已不属于当前用户。');
      if (row.status != 'active') {
        if (row.status == 'paused') return;
        throw StateError('当前专注会话已经结算。');
      }
      await (database.update(database.focusSessions)
            ..where((session) => session.userId.equals(userId))
            ..where((session) => session.id.equals(sessionId)))
          .write(
            db.FocusSessionsCompanion(
              status: const Value('paused'),
              pausedAt: Value(now),
              pauseRuleText: Value(normalizedRule),
            ),
          );
      await _queue('focus_session', sessionId, now);
    });
    await _publish();
    return (await getSession(sessionId))!;
  }

  @override
  Future<FocusSession> resumeSession(String sessionId) async {
    final now = _now().toUtc();
    await database.transaction(() async {
      final row = await _sessionRow(sessionId);
      if (row == null) throw StateError('专注会话不存在或已不属于当前用户。');
      if (row.status == 'active') return;
      if (row.status != 'paused' || row.pausedAt == null) {
        throw StateError('当前专注会话不能继续。');
      }
      final pausedDuration = now.difference(row.pausedAt!);
      final pausedSeconds = pausedDuration.inSeconds;
      final adjustedEndsAt = row.endsAt.add(pausedDuration);
      await (database.update(database.focusSessions)
            ..where((session) => session.userId.equals(userId))
            ..where((session) => session.id.equals(sessionId)))
          .write(
            db.FocusSessionsCompanion(
              status: const Value('active'),
              endsAt: Value(adjustedEndsAt),
              pausedAt: const Value(null),
              pausedSeconds: Value(row.pausedSeconds + pausedSeconds),
            ),
          );
      await _queue('focus_session', sessionId, now);
    });
    await _publish();
    return (await getSession(sessionId))!;
  }

  @override
  Future<FocusSession> completeEarlySession({
    required String sessionId,
    required String ruleText,
  }) async {
    final normalizedRule = _requiredRuleText(ruleText);
    await _settleDueSessions();
    final existing = await _sessionRow(sessionId);
    if (existing == null) {
      throw StateError('专注会话不存在或已不属于当前用户。');
    }
    if (existing.status == 'completed') {
      if (existing.completionType ==
          FocusSessionCompletionType.precedentRule.storageValue) {
        return (await getSession(sessionId))!;
      }
      throw StateError('正常完成的专注不能改为提前完成。');
    }
    if (existing.status == 'failed') {
      throw StateError('失败的专注不能改为提前完成。');
    }
    await _completeSession(
      sessionId,
      now: _now().toUtc(),
      completionType: FocusSessionCompletionType.precedentRule,
      completionRuleText: normalizedRule,
    );
    await _publish();
    return (await getSession(sessionId))!;
  }

  @override
  Future<FocusSession> abandonSession({
    required String sessionId,
    required String failureReason,
  }) async {
    final reason = _requiredFailureReason(failureReason);
    await _settleDueSessions();
    final now = _now().toUtc();
    await database.transaction(() async {
      final row = await _sessionRow(sessionId);
      if (row == null) throw StateError('专注会话不存在或已不属于当前用户。');
      if (row.status == 'failed') return;
      if (row.status == 'completed') throw StateError('正常完成的专注不能改为失败。');
      final effectiveSeconds = _effectiveSeconds(row, now);
      await (database.update(database.focusSessions)
            ..where((session) => session.userId.equals(userId))
            ..where((session) => session.id.equals(sessionId)))
          .write(
            db.FocusSessionsCompanion(
              status: const Value('failed'),
              completedAt: Value(now),
              pausedAt: const Value(null),
              effectiveSeconds: Value(effectiveSeconds),
              failureReason: Value(reason),
            ),
          );
      await _addTaskProgress(row.taskId, effectiveSeconds, now);
      final record =
          await (database.select(database.focusChainRecords)
                ..where((entry) => entry.userId.equals(userId))
                ..where((entry) => entry.mode.equals(row.mode)))
              .getSingleOrNull();
      await database
          .into(database.focusChainRecords)
          .insertOnConflictUpdate(
            db.FocusChainRecordsCompanion.insert(
              userId: userId,
              mode: row.mode,
              currentConsecutive: const Value(0),
              bestConsecutive: Value(record?.bestConsecutive ?? 0),
              updatedAt: now,
            ),
          );
      await _queue('focus_session', sessionId, now);
      await _queue('focus_chain', row.mode, now);
    });
    await _publish();
    return (await getSession(sessionId))!;
  }

  @override
  Future<void> updateFailureReason({
    required String sessionId,
    required String failureReason,
  }) async {
    final reason = _requiredFailureReason(failureReason);
    final row = await _sessionRow(sessionId);
    if (row == null) throw StateError('专注会话不存在或已不属于当前用户。');
    if (row.status != 'failed') throw StateError('只有失败的专注可以编辑失败原因。');
    await (database.update(database.focusSessions)
          ..where((session) => session.userId.equals(userId))
          ..where((session) => session.id.equals(sessionId)))
        .write(db.FocusSessionsCompanion(failureReason: Value(reason)));
    await _queue('focus_session', sessionId, _now().toUtc());
    await _publish();
  }

  @override
  Future<void> updateNodeNote({
    required String nodeId,
    required String note,
  }) async {
    final normalized = note.trim();
    if (normalized.length > 500) throw ArgumentError('节点备注不能超过 500 字。');
    final row =
        await (database.select(database.focusNodes)
              ..where((node) => node.userId.equals(userId))
              ..where((node) => node.id.equals(nodeId)))
            .getSingleOrNull();
    if (row == null) throw StateError('专注节点不存在或已不属于当前用户。');
    final now = _now().toUtc();
    await (database.update(database.focusNodes)
          ..where((node) => node.userId.equals(userId))
          ..where((node) => node.id.equals(nodeId)))
        .write(
          db.FocusNodesCompanion(
            note: Value(normalized.isEmpty ? null : normalized),
          ),
        );
    await _queue('focus_node', nodeId, now);
    await _publish();
  }

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
    FocusSessionCompletionType completionType =
        FocusSessionCompletionType.countdown,
    String? completionRuleText,
  }) async {
    await database.transaction(() async {
      final row =
          await (database.select(database.focusSessions)
                ..where((session) => session.userId.equals(userId))
                ..where((session) => session.id.equals(sessionId)))
              .getSingleOrNull();
      final isEarlyCompletion =
          completionType == FocusSessionCompletionType.precedentRule;
      if (row == null ||
          (!isEarlyCompletion &&
              (row.status != 'active' || row.endsAt.isAfter(now))) ||
          (isEarlyCompletion &&
              row.status != 'active' &&
              row.status != 'paused')) {
        return;
      }
      final seconds = isEarlyCompletion
          ? _effectiveSeconds(row, now)
          : row.durationSeconds;
      if (isEarlyCompletion && seconds <= 0) {
        throw StateError('至少需要有有效专注时间才能提前完成。');
      }
      final completedAt = isEarlyCompletion ? now : row.endsAt;
      await (database.update(database.focusSessions)
            ..where((session) => session.userId.equals(userId))
            ..where((session) => session.id.equals(sessionId)))
          .write(
            db.FocusSessionsCompanion(
              status: const Value('completed'),
              completedAt: Value(completedAt),
              effectiveSeconds: Value(seconds),
              completionType: Value(completionType.storageValue),
              completionRuleText: Value(completionRuleText),
              pausedAt: const Value(null),
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

        await _addTaskProgress(row.taskId, seconds, completedAt);

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
      final shouldApplyCompletedEffects =
          session.status == FocusSessionStatus.completed &&
          (local == null ||
              local.status == 'active' ||
              local.status == 'paused');
      if (local == null ||
          ((local.status == 'active' || local.status == 'paused') &&
              !session.status.isUnfinished)) {
        await _saveSession(session, queue: false);
        if (session.isFailed) await _applyFailedEffects(session);
        if (shouldApplyCompletedEffects) {
          await _applyCompletedEffects(session);
        }
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
              note: Value(node.note),
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
    for (final rule in snapshot.precedentRules) {
      final local =
          await (database.select(database.focusPrecedentRules)
                ..where((row) => row.userId.equals(userId))
                ..where((row) => row.id.equals(rule.id)))
              .getSingleOrNull();
      if (local == null ||
          rule.updatedAt.isAfter(local.updatedAt) ||
          (rule.updatedAt.isAtSameMomentAs(local.updatedAt) &&
              rule.deletedAt != null &&
              local.deletedAt == null)) {
        await database
            .into(database.focusPrecedentRules)
            .insertOnConflictUpdate(
              db.FocusPrecedentRulesCompanion.insert(
                userId: userId,
                id: rule.id,
                ruleText: rule.text,
                createdAt: rule.createdAt,
                updatedAt: rule.updatedAt,
                deletedAt: Value(rule.deletedAt),
              ),
            );
      }
    }
    await _reconcileTaskFocusProgressFromSessions();
    final sessions = await getSessions();
    final nodes = await getNodes();
    final records = await getChainRecords();
    final precedentRules = await _getPrecedentRulesIncludingDeleted();
    if (sessions.isNotEmpty) {
      await remote.upsertSessions(userId: userId, sessions: sessions);
    }
    if (nodes.isNotEmpty) {
      await remote.upsertNodes(userId: userId, nodes: nodes);
    }
    await remote.upsertRecords(userId: userId, records: records);
    await remote.upsertPrecedentRules(userId: userId, rules: precedentRules);
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
            completionType: Value(session.completionType.storageValue),
            completionRuleText: Value(session.completionRuleText),
            pausedAt: Value(session.pausedAt),
            pausedSeconds: Value(session.pausedSeconds),
            pauseRuleText: Value(session.pauseRuleText),
            failureReason: Value(session.failureReason),
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

  Future<List<PrecedentRule>> _getPrecedentRulesIncludingDeleted() async {
    final rows = await (database.select(
      database.focusPrecedentRules,
    )..where((rule) => rule.userId.equals(userId))).get();
    return [for (final row in rows) _precedentRuleFromRow(row)];
  }

  Future<db.FocusSession?> _sessionRow(String sessionId) {
    return (database.select(database.focusSessions)
          ..where((session) => session.userId.equals(userId))
          ..where((session) => session.id.equals(sessionId)))
        .getSingleOrNull();
  }

  int _effectiveSeconds(db.FocusSession row, DateTime now) {
    final end = row.status == 'paused' && row.pausedAt != null
        ? row.pausedAt!
        : (now.isBefore(row.endsAt) ? now : row.endsAt);
    final elapsed = end.difference(row.startedAt).inSeconds;
    return (elapsed - row.pausedSeconds).clamp(0, row.durationSeconds);
  }

  Future<void> _addTaskProgress(
    String taskId,
    int seconds,
    DateTime updatedAt,
  ) async {
    if (seconds <= 0) return;
    final task =
        await (database.select(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..where((task) => task.id.equals(taskId)))
            .getSingleOrNull();
    if (task == null) return;
    await (database.update(database.localTasks)
          ..where((task) => task.userId.equals(userId))
          ..where((task) => task.id.equals(taskId)))
        .write(
          db.LocalTasksCompanion(
            focusProgressSeconds: Value(task.focusProgressSeconds + seconds),
          ),
        );
    await _queue('task', taskId, updatedAt);
  }

  Future<void> _reconcileTaskFocusProgressFromSessions() async {
    final settledRows =
        await (database.select(database.focusSessions)
              ..where((session) => session.userId.equals(userId))
              ..where(
                (session) => session.status.isIn(['completed', 'failed']),
              ))
            .get();
    final secondsByTask = <String, int>{};
    for (final session in settledRows) {
      secondsByTask.update(
        session.taskId,
        (seconds) => seconds + session.effectiveSeconds,
        ifAbsent: () => session.effectiveSeconds,
      );
    }
    if (secondsByTask.isEmpty) return;
    final taskRows =
        await (database.select(database.localTasks)
              ..where((task) => task.userId.equals(userId))
              ..where((task) => task.id.isIn(secondsByTask.keys)))
            .get();
    for (final task in taskRows) {
      final reconciled = secondsByTask[task.id]!;
      if (task.focusProgressSeconds == reconciled) continue;
      await (database.update(database.localTasks)
            ..where((row) => row.userId.equals(userId))
            ..where((row) => row.id.equals(task.id)))
          .write(
            db.LocalTasksCompanion(focusProgressSeconds: Value(reconciled)),
          );
      await _queue('task', task.id, _now().toUtc());
    }
  }

  Future<void> _applyFailedEffects(FocusSession session) async {
    final settledAt = session.completedAt ?? session.endsAt;
    await _addTaskProgress(session.taskId, session.effectiveSeconds, settledAt);
    final record =
        await (database.select(database.focusChainRecords)
              ..where((entry) => entry.userId.equals(userId))
              ..where((entry) => entry.mode.equals(session.mode.storageValue)))
            .getSingleOrNull();
    await database
        .into(database.focusChainRecords)
        .insertOnConflictUpdate(
          db.FocusChainRecordsCompanion.insert(
            userId: userId,
            mode: session.mode.storageValue,
            currentConsecutive: const Value(0),
            bestConsecutive: Value(record?.bestConsecutive ?? 0),
            updatedAt: settledAt,
          ),
        );
    await _queue('focus_chain', session.mode.storageValue, settledAt);
  }

  Future<void> _applyCompletedEffects(FocusSession session) async {
    final settledAt = session.completedAt ?? session.endsAt;
    await database.transaction(() async {
      final existingNode =
          await (database.select(database.focusNodes)
                ..where((node) => node.userId.equals(userId))
                ..where((node) => node.id.equals(session.id)))
              .getSingleOrNull();
      if (existingNode == null) {
        await database
            .into(database.focusNodes)
            .insert(
              db.FocusNodesCompanion.insert(
                userId: userId,
                id: session.id,
                sessionId: session.id,
                taskId: session.taskId,
                mode: session.mode.storageValue,
                createdAt: settledAt,
                effectiveSeconds: session.effectiveSeconds,
              ),
            );
      }
      await _addTaskProgress(
        session.taskId,
        session.effectiveSeconds,
        settledAt,
      );
      final record =
          await (database.select(database.focusChainRecords)
                ..where((entry) => entry.userId.equals(userId))
                ..where(
                  (entry) => entry.mode.equals(session.mode.storageValue),
                ))
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
              mode: session.mode.storageValue,
              currentConsecutive: Value(current),
              bestConsecutive: Value(best),
              updatedAt: settledAt,
            ),
          );
      await _queue('focus_node', session.id, settledAt);
      await _queue('focus_chain', session.mode.storageValue, settledAt);
    });
  }

  String _requiredFailureReason(String reason) {
    final normalized = reason.trim();
    if (normalized.isEmpty) throw ArgumentError('失败原因不能为空。');
    if (normalized.length > 200) throw ArgumentError('失败原因不能超过 200 字。');
    return normalized;
  }

  String _requiredRuleText(String ruleText) {
    final normalized = ruleText.trim();
    if (normalized.isEmpty) throw ArgumentError('下必为例内容不能为空。');
    if (normalized.length > 500) throw ArgumentError('下必为例内容不能超过 500 字。');
    return normalized;
  }

  FocusSession _sessionFromRow(db.FocusSession row) => FocusSession(
    id: row.id,
    taskId: row.taskId,
    mode: FocusChainMode.fromStorage(row.mode),
    durationSeconds: row.durationSeconds,
    startedAt: row.startedAt,
    endsAt: row.endsAt,
    status: switch (row.status) {
      'active' => FocusSessionStatus.active,
      'paused' => FocusSessionStatus.paused,
      'failed' => FocusSessionStatus.failed,
      _ => FocusSessionStatus.completed,
    },
    completedAt: row.completedAt,
    effectiveSeconds: row.effectiveSeconds,
    completionType: FocusSessionCompletionType.fromStorage(row.completionType),
    completionRuleText: row.completionRuleText,
    pausedAt: row.pausedAt,
    pausedSeconds: row.pausedSeconds,
    pauseRuleText: row.pauseRuleText,
    failureReason: row.failureReason,
  );

  FocusNode _nodeFromRow(db.FocusNode row) => FocusNode(
    id: row.id,
    sessionId: row.sessionId,
    taskId: row.taskId,
    mode: FocusChainMode.fromStorage(row.mode),
    createdAt: row.createdAt,
    effectiveSeconds: row.effectiveSeconds,
    note: row.note,
  );

  FocusChainRecord _recordFromRow(db.FocusChainRecord row) => FocusChainRecord(
    mode: FocusChainMode.fromStorage(row.mode),
    currentConsecutive: row.currentConsecutive,
    bestConsecutive: row.bestConsecutive,
    updatedAt: row.updatedAt,
  );

  PrecedentRule _precedentRuleFromRow(db.FocusPrecedentRule row) =>
      PrecedentRule(
        id: row.id,
        text: row.ruleText,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
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
    final precedentRules = await client.from('focus_precedent_rules').select();
    return FocusRemoteSnapshot(
      sessions: [for (final row in sessions) _sessionFromJson(row)],
      nodes: [for (final row in nodes) _nodeFromJson(row)],
      records: [for (final row in records) _recordFromJson(row)],
      precedentRules: [
        for (final row in precedentRules) _precedentRuleFromJson(row),
      ],
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
          'completion_type': session.completionType.storageValue,
          'completion_rule_text': session.completionRuleText,
          'paused_at': session.pausedAt == null
              ? null
              : _utcIso8601(session.pausedAt!),
          'paused_seconds': session.pausedSeconds,
          'pause_rule_text': session.pauseRuleText,
          'failure_reason': session.failureReason,
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
          'note': node.note,
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

  @override
  Future<void> upsertPrecedentRules({
    required String userId,
    required List<PrecedentRule> rules,
  }) async {
    if (rules.isEmpty) return;
    await client.from('focus_precedent_rules').upsert([
      for (final rule in rules)
        {
          'id': rule.id,
          'user_id': userId,
          'rule_text': rule.text,
          'created_at': _utcIso8601(rule.createdAt),
          'updated_at': _utcIso8601(rule.updatedAt),
          'deleted_at': rule.deletedAt == null
              ? null
              : _utcIso8601(rule.deletedAt!),
        },
    ], onConflict: 'id');
  }

  FocusSession _sessionFromJson(Map<String, dynamic> json) => FocusSession(
    id: json['id'] as String,
    taskId: json['task_id'] as String,
    mode: FocusChainMode.fromStorage(json['mode'] as String),
    durationSeconds: json['duration_seconds'] as int,
    startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
    endsAt: DateTime.parse(json['ends_at'] as String).toUtc(),
    status: switch (json['status'] as String) {
      'active' => FocusSessionStatus.active,
      'paused' => FocusSessionStatus.paused,
      'failed' => FocusSessionStatus.failed,
      _ => FocusSessionStatus.completed,
    },
    completedAt: (json['completed_at'] as String?) == null
        ? null
        : DateTime.parse(json['completed_at'] as String).toUtc(),
    effectiveSeconds: json['effective_seconds'] as int,
    completionType: FocusSessionCompletionType.fromStorage(
      json['completion_type'] as String?,
    ),
    completionRuleText: json['completion_rule_text'] as String?,
    pausedAt: (json['paused_at'] as String?) == null
        ? null
        : DateTime.parse(json['paused_at'] as String).toUtc(),
    pausedSeconds: (json['paused_seconds'] as int?) ?? 0,
    pauseRuleText: json['pause_rule_text'] as String?,
    failureReason: json['failure_reason'] as String?,
  );

  FocusNode _nodeFromJson(Map<String, dynamic> json) => FocusNode(
    id: json['id'] as String,
    sessionId: json['session_id'] as String,
    taskId: json['task_id'] as String,
    mode: FocusChainMode.fromStorage(json['mode'] as String),
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    effectiveSeconds: json['effective_seconds'] as int,
    note: json['note'] as String?,
  );

  FocusChainRecord _recordFromJson(Map<String, dynamic> json) =>
      FocusChainRecord(
        mode: FocusChainMode.fromStorage(json['mode'] as String),
        currentConsecutive: json['current_consecutive'] as int,
        bestConsecutive: json['best_consecutive'] as int,
        updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      );

  PrecedentRule _precedentRuleFromJson(Map<String, dynamic> json) =>
      PrecedentRule(
        id: json['id'] as String,
        text: json['rule_text'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
        deletedAt: (json['deleted_at'] as String?) == null
            ? null
            : DateTime.parse(json['deleted_at'] as String).toUtc(),
      );
}

String _utcIso8601(DateTime value) => value.toUtc().toIso8601String();

class InMemoryFocusRemote implements FocusRemoteDataSource {
  final _sessions = <String, Map<String, FocusSession>>{};
  final _nodes = <String, Map<String, FocusNode>>{};
  final _records = <String, Map<String, FocusChainRecord>>{};
  final _precedentRules = <String, Map<String, PrecedentRule>>{};

  @override
  Future<FocusRemoteSnapshot> pull({required String userId}) async {
    return FocusRemoteSnapshot(
      sessions: (_sessions[userId] ?? {}).values.toList(),
      nodes: (_nodes[userId] ?? {}).values.toList(),
      records: (_records[userId] ?? {}).values.toList(),
      precedentRules: (_precedentRules[userId] ?? {}).values.toList(),
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

  @override
  Future<void> upsertPrecedentRules({
    required String userId,
    required List<PrecedentRule> rules,
  }) async {
    final target = _precedentRules.putIfAbsent(userId, () => {});
    for (final rule in rules) {
      target[rule.id] = rule;
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
  Future<FocusSession?> getSession(String sessionId) async => null;

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
  Future<FocusSession> pauseSession(
    String sessionId, {
    required String ruleText,
  }) => _unavailable();

  @override
  Future<FocusSession> resumeSession(String sessionId) => _unavailable();

  @override
  Future<FocusSession> completeEarlySession({
    required String sessionId,
    required String ruleText,
  }) => _unavailable();

  @override
  Future<FocusSession> abandonSession({
    required String sessionId,
    required String failureReason,
  }) => _unavailable();

  @override
  Future<void> updateFailureReason({
    required String sessionId,
    required String failureReason,
  }) => _unavailable();

  @override
  Future<void> updateNodeNote({required String nodeId, required String note}) =>
      _unavailable();

  @override
  Future<List<FocusNode>> getNodes() async => const [];

  @override
  Future<List<FocusChainRecord>> getChainRecords() async => const [];

  @override
  Future<List<PrecedentRule>> getPrecedentRules() async => const [];

  @override
  Future<PrecedentRule> createPrecedentRule({required String text}) =>
      _unavailable();

  @override
  Future<PrecedentRule> updatePrecedentRule({
    required String ruleId,
    required String text,
  }) => _unavailable();

  @override
  Future<void> deletePrecedentRule(String ruleId) => _unavailable();

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
