import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/app/pacta_app.dart';
import 'package:pacta/auth/auth_session.dart';
import 'package:pacta/auth/auth_state.dart';
import 'package:pacta/private_data/offline_first_private_data_store.dart';
import 'package:pacta/private_data/private_data_state.dart';
import 'package:pacta/private_data/user_profile.dart';

void main() {
  testWidgets('unauthenticated User cannot enter the private shell', (
    tester,
  ) async {
    final privateData = _FakePrivateDataStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(
            _FakeAuthSession.unauthenticated(),
          ),
          privateDataStoreProvider.overrideWithValue(privateData),
          connectivityChangesProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
        child: const PactaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to Pacta'), findsOneWidget);
    expect(find.text("Today's Board"), findsNothing);
    expect(privateData.requestedUsers, isEmpty);
  });

  testWidgets('authenticated User enters the private shell', (tester) async {
    final privateData = _FakePrivateDataStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWithValue(
            _FakeAuthSession.authenticated(const AppUserId('user-a')),
          ),
          privateDataStoreProvider.overrideWithValue(privateData),
          connectivityChangesProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
        ],
        child: const PactaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Today's Board"), findsOneWidget);
    expect(find.text('Sign in to Pacta'), findsNothing);
    expect(privateData.requestedUsers, [const AppUserId('user-a')]);
  });
}

class _FakePrivateDataStore implements PrivateDataStore {
  final requestedUsers = <AppUserId>[];

  @override
  Future<PrivateDataBootstrap> bootstrap(AppUserId userId) async {
    requestedUsers.add(userId);
    return PrivateDataBootstrap(
      profile: UserProfile(
        userId: userId,
        displayName: 'Test User',
        updatedAt: DateTime.utc(2026, 8, 24),
      ),
      isOffline: false,
    );
  }
}

class _FakeAuthSession implements AuthSession {
  _FakeAuthSession._(this.currentUser);

  factory _FakeAuthSession.unauthenticated() => _FakeAuthSession._(null);

  factory _FakeAuthSession.authenticated(AppUserId userId) =>
      _FakeAuthSession._(userId);

  @override
  final AppUserId? currentUser;

  @override
  Stream<AppUserId?> get userChanges => Stream.value(currentUser);

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {}
}
