import 'user_lifecycle_models.dart';

abstract interface class AuthRepository {
  Stream<String?> get authState;
  String? get currentUserIdentifier;
  String? get currentUserId;

  Future<void> signIn({required String email, required String password});

  Future<void> signUp({required String email, required String password});

  Future<void> signOut();

  Future<bool> isAdministrator();

  Future<void> grantEligibility({required String email});

  Future<bool> revokeEligibility({required String email});

  Future<void> adminResetUserPassword({
    required String targetEmail,
    required String newPassword,
    required bool manualVerificationConfirmed,
  });

  Future<UserLifecycleStatus> getCurrentUserLifecycle();

  Future<List<ManagedUserLifecycle>> listUserLifecycles();

  Future<void> suspendUser(String userId);

  Future<void> restoreUser(String userId);

  Future<UserPurgeReceipt> purgeUser(String userId);

  Future<UserPurgeReceipt?> lookupPurgeReceipt(String oldUserId);
}
