import 'dart:async';

import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UnavailableRemoteGoalTaskSource implements RemoteGoalTaskSource {
  const UnavailableRemoteGoalTaskSource();

  @override
  Future<RemoteGoalTaskSnapshot> exchange(
    AppUserId userId,
    List<GoalTaskMutation> mutations,
  ) {
    throw const RemoteGoalTaskUnavailable();
  }
}

class SupabaseGoalTaskSource implements RemoteGoalTaskSource {
  SupabaseGoalTaskSource(this._client);

  final SupabaseClient _client;

  @override
  Future<RemoteGoalTaskSnapshot> exchange(
    AppUserId userId,
    List<GoalTaskMutation> mutations,
  ) async {
    try {
      final response = await _client.rpc(
        'sync_goal_tasks',
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
      final goals = _goals(userId, result['goals']);
      final tasks = _tasks(userId, result['tasks']);
      final accepted =
          (result['accepted_mutation_ids'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toSet();
      return RemoteGoalTaskSnapshot(
        goals: goals,
        tasks: tasks,
        acceptedMutationIds: accepted,
      );
    } on RemoteGoalTaskUnavailable {
      rethrow;
    } on PostgrestException catch (error) {
      throw GoalTaskSyncFailure(
        'The remote Goal and Task data was rejected: ${error.message}',
      );
    } on TimeoutException catch (error) {
      throw RemoteGoalTaskUnavailable(error.toString());
    } on Exception catch (error) {
      throw RemoteGoalTaskUnavailable(error.toString());
    }
  }

  List<Goal> _goals(AppUserId userId, dynamic value) {
    return (value as List<dynamic>? ?? const [])
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          return Goal(
            id: row['id'] as String,
            userId: AppUserId(row['user_id'] as String),
            title: row['title'] as String,
            notes: row['notes'] as String?,
            mutationId: row['mutation_id'] as String? ?? '',
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
          );
        })
        .where((goal) => goal.userId == userId)
        .toList(growable: false);
  }

  List<Task> _tasks(AppUserId userId, dynamic value) {
    return (value as List<dynamic>? ?? const [])
        .map((raw) {
          final row = Map<String, dynamic>.from(raw as Map);
          final estimatedSeconds = row['estimated_seconds'] as int?;
          return Task(
            id: row['id'] as String,
            userId: AppUserId(row['user_id'] as String),
            goalId: row['goal_id'] as String,
            title: row['title'] as String,
            notes: row['notes'] as String?,
            mutationId: row['mutation_id'] as String? ?? '',
            deadline: _date(row['deadline']),
            estimatedDuration: estimatedSeconds == null
                ? null
                : Duration(seconds: estimatedSeconds),
            classification: TaskChainClassification.fromWireValue(
              row['classification'] as String,
            ),
            focusProgress: Duration(
              seconds: (row['focus_progress_seconds'] as int?) ?? 0,
            ),
            completedAt: _date(row['completed_at']),
            createdAt: DateTime.parse(row['created_at'] as String),
            updatedAt: DateTime.parse(row['updated_at'] as String),
          );
        })
        .where((task) => task.userId == userId)
        .toList(growable: false);
  }

  DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.parse(value as String).toUtc();
}
