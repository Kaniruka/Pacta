import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_models.dart';
import 'package:pacta/features/goals_tasks/domain/goal_task_repository.dart';
import 'package:pacta/private_data/private_data_state.dart';

final goalTaskRepositoryProvider = Provider<GoalTaskRepository>((ref) {
  throw StateError(
    'GoalTaskRepository must be configured at the application root.',
  );
});

final goalTaskSnapshotProvider = StreamProvider.autoDispose
    .family<GoalTaskSnapshot, AppUserId>((ref, userId) {
      return ref.watch(goalTaskRepositoryProvider).watch(userId);
    });

/// Starts with the local snapshot, then retries on connectivity and lifecycle
/// triggers. The Board can render cached data while this stream is syncing.
final goalTaskSyncProvider = StreamProvider.autoDispose
    .family<GoalTaskSnapshot, AppUserId>((ref, userId) async* {
      final repository = ref.watch(goalTaskRepositoryProvider);
      yield await repository.sync(userId);
      await for (final _ in ref.watch(syncRetryTriggersProvider)) {
        yield await repository.sync(userId);
      }
    });
