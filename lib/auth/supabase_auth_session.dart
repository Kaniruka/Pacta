import 'dart:async';

import 'package:pacta/auth/auth_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthSession implements AuthSession {
  SupabaseAuthSession(this._client);

  final SupabaseClient _client;

  @override
  AppUserId? get currentUser {
    final user = _client.auth.currentUser;
    return user == null ? null : AppUserId(user.id);
  }

  @override
  Stream<AppUserId?> get userChanges {
    StreamSubscription<AuthState>? subscription;
    late final StreamController<AppUserId?> controller;
    controller = StreamController<AppUserId?>(
      onListen: () {
        var previous = currentUser;
        controller.add(previous);
        subscription = _client.auth.onAuthStateChange.listen(
          (event) {
            final id = event.session?.user.id;
            final next = id == null ? null : AppUserId(id);
            if (next != previous) {
              previous = next;
              controller.add(next);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            // Offline token refresh errors must not discard the last stable
            // authenticated User. A later auth event remains authoritative.
          },
          onDone: controller.close,
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

class UnconfiguredAuthSession implements AuthSession {
  const UnconfiguredAuthSession();

  @override
  AppUserId? get currentUser => null;

  @override
  Stream<AppUserId?> get userChanges => Stream.value(null);

  @override
  Future<void> signIn({required String email, required String password}) {
    throw StateError(
      'Supabase is not configured. Supply SUPABASE_URL and '
      'SUPABASE_PUBLISHABLE_KEY with --dart-define.',
    );
  }

  @override
  Future<void> signOut() async {}
}
