import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';
import 'user_lifecycle_models.dart';

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

  @override
  Future<void> adminResetUserPassword({
    required String targetEmail,
    required String newPassword,
    required bool manualVerificationConfirmed,
  }) async {
    if (!manualVerificationConfirmed) {
      throw const FormatException('请先确认已完成人工核实。');
    }
    _requireEmail(targetEmail);
    if (newPassword.length < 8) {
      throw const FormatException('新密码至少需要 8 个字符。');
    }
    await _client.functions.invoke(
      'admin-reset-user-password',
      body: {
        'email': targetEmail.trim().toLowerCase(),
        'new_password': newPassword,
        'manual_verification_confirmed': true,
      },
    );
  }

  @override
  Future<UserLifecycleStatus> getCurrentUserLifecycle() async {
    final response = await _client.rpc('current_user_lifecycle_status');
    return UserLifecycleStatus.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  @override
  Future<List<ManagedUserLifecycle>> listUserLifecycles() async {
    final response = await _client.rpc('admin_list_user_lifecycles');
    return [
      for (final row in response as List)
        ManagedUserLifecycle.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  @override
  Future<void> suspendUser(String userId) async {
    await _client.rpc('admin_suspend_user', params: {'p_user_id': userId});
  }

  @override
  Future<void> restoreUser(String userId) async {
    await _client.rpc('admin_restore_user', params: {'p_user_id': userId});
  }

  @override
  Future<UserPurgeReceipt> purgeUser(String userId) async {
    final response = await _client.functions.invoke(
      'admin-purge-user',
      body: {'user_id': userId},
    );
    final data = response.data;
    if (data is! Map) throw const FormatException('清除回执格式无效。');
    final receipt = UserPurgeReceipt.fromJson(Map<String, dynamic>.from(data));
    if (!receipt.confirmsPurgedUser(userId)) {
      throw StateError('服务端未确认该用户身份已清除。');
    }
    return receipt;
  }

  @override
  Future<UserPurgeReceipt?> lookupPurgeReceipt(String oldUserId) async {
    final response = await _client.rpc(
      'user_purge_receipt',
      params: {'p_user_id': oldUserId},
    );
    if (response is! Map) return null;
    final receipt = UserPurgeReceipt.fromJson(
      Map<String, dynamic>.from(response),
    );
    return receipt.confirmsPurgedUser(oldUserId) ? receipt : null;
  }

  void _requireEmail(String value) {
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
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

  @override
  Future<void> adminResetUserPassword({
    required String targetEmail,
    required String newPassword,
    required bool manualVerificationConfirmed,
  }) async {
    throw StateError(message);
  }

  @override
  Future<UserLifecycleStatus> getCurrentUserLifecycle() async {
    throw StateError(message);
  }

  @override
  Future<List<ManagedUserLifecycle>> listUserLifecycles() async {
    throw StateError(message);
  }

  @override
  Future<void> suspendUser(String userId) async {
    throw StateError(message);
  }

  @override
  Future<void> restoreUser(String userId) async {
    throw StateError(message);
  }

  @override
  Future<UserPurgeReceipt> purgeUser(String userId) async {
    throw StateError(message);
  }

  @override
  Future<UserPurgeReceipt?> lookupPurgeReceipt(String oldUserId) async {
    throw StateError(message);
  }
}
