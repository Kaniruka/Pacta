abstract interface class AuthRepository {
  Stream<String?> get authState;
  String? get currentUserIdentifier;
  String? get currentUserId;

  Future<void> signIn({required String identifier, required String password});

  Future<void> signUp({required String identifier, required String password});

  Future<void> signOut();

  Future<bool> isAdministrator();

  Future<void> grantEligibility({
    required String identifier,
    required String type,
  });

  Future<bool> revokeEligibility({
    required String identifier,
    required String type,
  });
}
