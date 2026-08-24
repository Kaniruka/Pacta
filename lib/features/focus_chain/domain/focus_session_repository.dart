import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/features/focus_chain/domain/focus_session_models.dart';

abstract interface class FocusSessionRepository {
  Future<FocusSession> start(AppUserId userId, FocusSessionConfig config);

  Future<FocusSession?> read(AppUserId userId, String sessionId);

  Stream<FocusSession> watch(AppUserId userId, String sessionId);

  /// Reconciles a durable active Session against the current wall-clock fact.
  ///
  /// A Session is completed only when the persisted countdown has reached zero.
  /// Calling this repeatedly is safe and returns the same completed Session.
  Future<FocusSession> reconcile(AppUserId userId, String sessionId);

  Future<List<FocusNode>> readNodes(AppUserId userId, String sessionId);

  Future<void> sync(AppUserId userId);
}
