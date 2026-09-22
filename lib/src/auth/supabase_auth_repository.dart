import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  @override
  Stream<String?> get authState =>
      _client.auth.onAuthStateChange.map((event) => event.session?.user.email);

  @override
  String? get currentUserIdentifier {
    final user = _client.auth.currentUser;
    return user?.email;
  }

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> signIn({required String email, required String password}) async {
    _requireEmail(email);
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    _requireEmail(email);
    await _client.auth.signUp(email: email, password: password);
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
  Future<void> grantEligibility({required String email}) async {
    await _client.rpc(
      'admin_grant_registration_eligibility',
      params: {'p_identifier': email, 'p_identifier_type': 'email'},
    );
  }

  @override
  Future<bool> revokeEligibility({required String email}) async {
    return await _client.rpc(
      'admin_revoke_registration_eligibility',
      params: {'p_identifier': email, 'p_identifier_type': 'email'},
    ) as bool;
  }

  void _requireEmail(String value) {
    if (!value.contains('@')) {
      throw const FormatException('请输入有效的邮箱地址。');
    }
  }
}

class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository();

  static const message = '尚未配置 Supabase。请使用 --dart-define-from-file=.env 启动。';

  @override
  Stream<String?> get authState => const Stream.empty();

  @override
  String? get currentUserIdentifier => null;

  @override
  String? get currentUserId => null;

  @override
  Future<void> signIn({required String email, required String password}) async {
    throw StateError(message);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    throw StateError(message);
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> isAdministrator() async => false;

  @override
  Future<void> grantEligibility({required String email}) async {
    throw StateError(message);
  }

  @override
  Future<bool> revokeEligibility({required String email}) async {
    throw StateError(message);
  }
}
