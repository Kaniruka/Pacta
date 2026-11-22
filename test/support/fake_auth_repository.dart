import 'package:pacta/src/auth/auth_repository.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';

class FakeAuthRepository implements AuthRepository {
  String? signedInUser;
  UserLifecycleStatus? lifecycleStatus;
  Object? lifecycleStatusError;
  final purgeReceiptLookupIds = <String>[];
  final lookupPurgeReceipts = <String, UserPurgeReceipt>{};
  UserPurgeReceipt? lookupPurgeReceiptResult;
  Object? purgeReceiptLookupError;
  Object? signInError;

  /// 自助修改密码：只记录调用与入参，错误由 [changePasswordError] 注入，
  /// 测试因此能区分“界面拦下了”和“仓储被调用了”。
  int changePasswordCalls = 0;
  String? lastCurrentPassword;
  String? lastNewPassword;
  Object? changePasswordError;

  @override
  Stream<String?> get authState => Stream.value(signedInUser);

  @override
  String? get currentUserIdentifier => signedInUser;

  @override
  String? get currentUserId => signedInUser;

  @override
  Future<void> signIn({required String email, required String password}) async {
    final error = signInError;
    if (error != null) throw error;
    signedInUser = email;
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    signedInUser = email;
  }

  @override
  Future<void> signOut() async {
    signedInUser = null;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalls++;
    lastCurrentPassword = currentPassword;
    lastNewPassword = newPassword;
    final error = changePasswordError;
    if (error != null) throw error;
  }

  @override
  Future<UserLifecycleStatus> getCurrentUserLifecycle() async {
    final error = lifecycleStatusError;
    if (error != null) throw error;
    return lifecycleStatus ??
        UserLifecycleStatus(
          isSuspended: false,
          checkedAt: DateTime.now().toUtc(),
        );
  }

  @override
  Future<UserPurgeReceipt?> lookupPurgeReceipt(String oldUserId) async {
    purgeReceiptLookupIds.add(oldUserId);
    final error = purgeReceiptLookupError;
    if (error != null) throw error;
    return lookupPurgeReceipts[oldUserId] ?? lookupPurgeReceiptResult;
  }
}
