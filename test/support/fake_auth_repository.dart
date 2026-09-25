import 'package:pacta/src/auth/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  String? signedInUser;
  bool administrator = false;
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
}
