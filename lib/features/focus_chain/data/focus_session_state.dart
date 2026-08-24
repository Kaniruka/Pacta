import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_models.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_repository.dart';
import 'package:pacta/private_data/private_data_state.dart';

final focusSessionRepositoryProvider = Provider<FocusSessionRepository>((ref) {
  throw StateError(
    'FocusSessionRepository must be configured at the application root.',
  );
});

final focusSessionProvider = FutureProvider.autoDispose
    .family<FocusSession?, ({AppUserId userId, String sessionId})>(
      (ref, key) => ref
          .watch(focusSessionRepositoryProvider)
          .read(key.userId, key.sessionId),
    );

final focusSessionSyncProvider = StreamProvider.autoDispose
    .family<void, AppUserId>((ref, userId) async* {
      final repository = ref.watch(focusSessionRepositoryProvider);
      await repository.sync(userId);
      await for (final _ in ref.watch(syncRetryTriggersProvider)) {
        await repository.sync(userId);
        yield null;
      }
    });
