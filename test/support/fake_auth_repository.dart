import 'package:pacta/src/auth/auth_repository.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';

class FakeAuthRepository implements AuthRepository {
  String? signedInUser;
  UserLifecycleStatus? lifecycleStatus;
  Object? lifecycleStatusError;
  bool administrator = false;
  List<ManagedUserLifecycle> managedUsers = const [];
  final suspendedUserIds = <String>[];
  final restoredUserIds = <String>[];
  Object? passwordResetError;
  String? passwordResetEmail;
  String? passwordResetValue;
  bool? passwordResetManualVerificationConfirmed;

  @override
  Stream<String?> get authState => Stream.value(signedInUser);

  @override
  String? get currentUserIdentifier => signedInUser;

  @override
  String? get currentUserId => signedInUser;

  @override
  Future<void> signIn({required String email, required String password}) async {
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
  Future<bool> isAdministrator() async => administrator;

  @override
  Future<void> grantEligibility({required String email}) async {}

  @override
  Future<bool> revokeEligibility({required String email}) async => false;

  @override
  Future<void> adminResetUserPassword({
    required String targetEmail,
    required String newPassword,
    required bool manualVerificationConfirmed,
  }) async {
    passwordResetEmail = targetEmail;
    passwordResetValue = newPassword;
    passwordResetManualVerificationConfirmed = manualVerificationConfirmed;
    final error = passwordResetError;
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
  Future<List<ManagedUserLifecycle>> listUserLifecycles() async => managedUsers;

  @override
  Future<void> suspendUser(String userId) async {
    suspendedUserIds.add(userId);
    final index = managedUsers.indexWhere((user) => user.userId == userId);
    if (index == -1) return;
    final now = DateTime.now().toUtc();
    final previous = managedUsers[index];
    managedUsers = [
      for (var current = 0; current < managedUsers.length; current++)
        if (current == index)
          ManagedUserLifecycle(
            userId: previous.userId,
            email: previous.email,
            createdAt: previous.createdAt,
            isSuspended: true,
            suspendedAt: now,
            purgeEligibleAt: now.add(const Duration(days: 30)),
            isEligibleForPurge: false,
          )
        else
          managedUsers[current],
    ];
  }

  @override
  Future<void> restoreUser(String userId) async {
    restoredUserIds.add(userId);
    final index = managedUsers.indexWhere((user) => user.userId == userId);
    if (index == -1) return;
    final previous = managedUsers[index];
    managedUsers = [
      for (var current = 0; current < managedUsers.length; current++)
        if (current == index)
          ManagedUserLifecycle(
            userId: previous.userId,
            email: previous.email,
            createdAt: previous.createdAt,
            isSuspended: false,
            restoredAt: DateTime.now().toUtc(),
            isEligibleForPurge: false,
          )
        else
          managedUsers[current],
    ];
  }
}
