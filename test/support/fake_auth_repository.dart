import 'package:pacta/src/auth/auth_repository.dart';

class FakeAuthRepository implements AuthRepository {
  String? signedInUser;

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
  Future<bool> isAdministrator() async => false;

  @override
  Future<void> grantEligibility({required String email}) async {}

  @override
  Future<bool> revokeEligibility({required String email}) async => false;
}
