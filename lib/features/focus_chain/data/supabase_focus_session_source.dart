import 'dart:async';

import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/domain/focus_chain_models.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FocusSessionMutation {
  const FocusSessionMutation({
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

class RemoteFocusSessionSnapshot {
  const RemoteFocusSessionSnapshot({
    required this.sessions,
    required this.nodes,
    required this.acceptedMutationIds,
  });

  final List<FocusSession> sessions;
  final List<FocusNode> nodes;
  final Set<String> acceptedMutationIds;
}

abstract interface class RemoteFocusSessionSource {
  Future<RemoteFocusSessionSnapshot> exchange(
    AppUserId userId,
    List<FocusSessionMutation> mutations,
  );
}

class RemoteFocusSessionUnavailable implements Exception {
  const RemoteFocusSessionUnavailable([this.message]);

  final String? message;

  @override
  String toString() => message ?? 'Remote Focus Session data is unavailable.';
}

class UnavailableRemoteFocusSessionSource implements RemoteFocusSessionSource {
  const UnavailableRemoteFocusSessionSource();

  @override
  Future<RemoteFocusSessionSnapshot> exchange(
    AppUserId userId,
    List<FocusSessionMutation> mutations,
  ) {
    throw const RemoteFocusSessionUnavailable();
  }
}

class SupabaseFocusSessionSource implements RemoteFocusSessionSource {
  SupabaseFocusSessionSource(this._client);

  final SupabaseClient _client;

  @override
  Future<RemoteFocusSessionSnapshot> exchange(
    AppUserId userId,
    List<FocusSessionMutation> mutations,
  ) async {
    try {
      final response = await _client.rpc(
        'sync_focus_sessions',
        params: {
          'p_user_id': userId.value,
          'p_mutations': [
            for (final mutation in mutations)
              {
                'entity_type': mutation.entityType,
                'entity_id': mutation.entityId,
                'mutation_id': mutation.mutationId,
                'updated_at': mutation.updatedAt.toIso8601String(),
                'payload': mutation.payload,
              },
          ],
        },
      );
      final result = Map<String, dynamic>.from(response as Map);
      return RemoteFocusSessionSnapshot(
        sessions: _sessions(userId, result['sessions']),
        nodes: _nodes(userId, result['nodes']),
        acceptedMutationIds:
            (result['accepted_mutation_ids'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toSet(),
      );
    } on RemoteFocusSessionUnavailable {
      rethrow;
    } on PostgrestException catch (error) {
      throw RemoteFocusSessionUnavailable(
        'The remote Focus Session data was rejected: ${error.message}',
      );
    } on TimeoutException catch (error) {
      throw RemoteFocusSessionUnavailable(error.toString());
    } on Exception catch (error) {
      throw RemoteFocusSessionUnavailable(error.toString());
    }
  }

  List<FocusSession> _sessions(AppUserId userId, dynamic value) {
    return (value as List<dynamic>? ?? const [])
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          return FocusSession(
            id: row['id'] as String,
            userId: AppUserId(row['user_id'] as String),
            taskId: row['task_id'] as String,
            mode: FocusChainMode.values.byName(row['mode'] as String),
            plannedDuration: Duration(seconds: row['planned_seconds'] as int),
            startedAt: DateTime.parse(row['started_at'] as String),
            outcome: _outcome(row['outcome']),
            actualElapsed: Duration(
              seconds: row['actual_elapsed_seconds'] as int,
            ),
            completedAt: _date(row['completed_at']),
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
            mutationId: row['mutation_id'] as String,
          );
        })
        .where((session) => session.userId == userId)
        .toList(growable: false);
  }

  FocusSessionOutcome? _outcome(dynamic value) =>
      value == null ? null : FocusSessionOutcome.values.byName(value as String);

  List<FocusNode> _nodes(AppUserId userId, dynamic value) {
    return (value as List<dynamic>? ?? const [])
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          return FocusNode(
            id: row['id'] as String,
            userId: AppUserId(row['user_id'] as String),
            sessionId: row['session_id'] as String,
            taskId: row['task_id'] as String,
            mode: FocusChainMode.values.byName(row['mode'] as String),
            elapsed: Duration(seconds: row['elapsed_seconds'] as int),
            createdAt: DateTime.parse(row['created_at'] as String),
            mutationId: row['mutation_id'] as String,
          );
        })
        .where((node) => node.userId == userId)
        .toList(growable: false);
  }

  DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();
}
