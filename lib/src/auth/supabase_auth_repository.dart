import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<String?> get authState => _client.auth.onAuthStateChange.map(
    (event) => event.session?.user.email ?? event.session?.user.phone,
  );

  @override
  String? get currentUserIdentifier {
    final user = _client.auth.currentUser;
    return user?.email ?? user?.phone;
  }

  @override
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    if (_isEmail(identifier)) {
      await _client.auth.signInWithPassword(
        email: identifier,
        password: password,
      );
    } else {
      await _client.auth.signInWithPassword(
        phone: identifier,
        password: password,
      );
    }
  }

  @override
  Future<void> signUp({
    required String identifier,
    required String password,
  }) async {
    if (_isEmail(identifier)) {
      await _client.auth.signUp(email: identifier, password: password);
    } else {
      await _client.auth.signUp(phone: identifier, password: password);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<bool> isAdministrator() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final result = await _client
        .from('app_admins')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();
    return result != null;
  }

  @override
  Future<void> grantEligibility({
    required String identifier,
    required String type,
  }) async {
    await _client.rpc(
      'admin_grant_registration_eligibility',
      params: {'p_identifier': identifier, 'p_identifier_type': type},
    );
  }

  @override
  Future<bool> revokeEligibility({
    required String identifier,
    required String type,
  }) async {
    return await _client.rpc(
      'admin_revoke_registration_eligibility',
      params: {'p_identifier': identifier, 'p_identifier_type': type},
    ) as bool;
  }

  bool _isEmail(String value) => value.contains('@');
}

class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository();

  static const message = '尚未配置 Supabase。请使用 --dart-define-from-file=.env 启动。';

  @override
  Stream<String?> get authState => const Stream.empty();

  @override
  String? get currentUserIdentifier => null;

  @override
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    throw StateError(message);
  }

  @override
  Future<void> signUp({
    required String identifier,
    required String password,
  }) async {
    throw StateError(message);
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> isAdministrator() async => false;

  @override
  Future<void> grantEligibility({
    required String identifier,
    required String type,
  }) async {
    throw StateError(message);
  }

  @override
  Future<bool> revokeEligibility({
    required String identifier,
    required String type,
  }) async {
    throw StateError(message);
  }
}
