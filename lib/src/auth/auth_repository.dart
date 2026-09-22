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
}
