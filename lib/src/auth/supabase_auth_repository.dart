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

  /// 普通用户自助修改密码：先用当前密码向 GoTrue 复核身份，再更新密码。
  ///
  /// 密码不做 trim：空白字符也是密码的一部分，去掉它等于替用户改写输入。
  /// 全部校验都在发请求之前完成，界面只需处理 [FormatException] 与
  /// [StateError] 两种可读结果。
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword.isEmpty) {
      throw const FormatException('请输入当前密码。');
    }
    if (newPassword.length < 8) {
      throw const FormatException('新密码至少需要 8 个字符。');
    }
    if (newPassword.length > 256) {
      throw const FormatException('新密码长度不能超过 256 个字符。');
    }
    if (newPassword == currentPassword) {
      throw const FormatException('新密码不能与当前密码相同。');
    }

    final email = _client.auth.currentUser?.email?.trim();
    if (email == null || email.isEmpty) {
      throw StateError('当前未登录或缺少账号邮箱，请重新登录后再试。');
    }

    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
    } on AuthException catch (error) {
      if (_isInvalidCredentials(error)) {
        throw const FormatException('当前密码不正确，请重新输入。');
      }
      rethrow;
    }

    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      final message = error.message.toLowerCase();
      if (message.contains('same_password') ||
          message.contains('different from the old password')) {
        throw const FormatException('新密码不能与当前密码相同。');
      }
      if (message.contains('weak_password') || message.contains('at least')) {
        throw const FormatException('新密码强度不足或长度不符合要求，请更换后重试。');
      }
      rethrow;
    }
  }

  /// 只有 GoTrue 明确表示凭据不匹配时才算当前密码错误。
  ///
  /// 不能用 400 一概而论：同是 400 的 `user_banned`、`email_not_confirmed`
  /// 与频率限制都不是「密码打错了」，映射成中文后用户会一直重输正确的密码。
  bool _isInvalidCredentials(AuthException error) {
    final code = error.code?.toLowerCase() ?? '';
    if (code == 'invalid_credentials' || code == 'invalid_grant') {
      return true;
    }
    final message = error.message.toLowerCase();
    return message.contains('invalid login credentials') ||
        message.contains('invalid_credentials') ||
        message.contains('invalid email or password') ||
        message.contains('invalid_grant');
  }

  @override
  Future<UserLifecycleStatus> getCurrentUserLifecycle() async {
    final response = await _client.rpc('current_user_lifecycle_status');
    return UserLifecycleStatus.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
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
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    throw StateError(message);
  }

  @override
  Future<UserLifecycleStatus> getCurrentUserLifecycle() async {
    throw StateError(message);
  }

  @override
  Future<UserPurgeReceipt?> lookupPurgeReceipt(String oldUserId) async {
    throw StateError(message);
  }
}
