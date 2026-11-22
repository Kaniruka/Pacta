import 'user_lifecycle_models.dart';

abstract interface class AuthRepository {
  Stream<String?> get authState;
  String? get currentUserIdentifier;
  String? get currentUserId;

  Future<void> signIn({required String email, required String password});

  Future<void> signUp({required String email, required String password});

  Future<void> signOut();

  /// 普通用户自助修改密码：先用当前密码复核身份，再更新登录密码。
  ///
  /// 入口只在账号设置里，管理员动作已彻底下线；两者不共用任何接口。
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  Future<UserLifecycleStatus> getCurrentUserLifecycle();

  Future<UserPurgeReceipt?> lookupPurgeReceipt(String oldUserId);
}
