import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_auth_repository.dart';

void main() {
  late PactaDatabase database;
  late FakeAuthRepository auth;
  late UserPurgeCleanupRepository cleanup;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    auth = FakeAuthRepository();
    cleanup = UserPurgeCleanupRepository(
      authRepository: auth,
      database: database,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'startup sweep checks locally cached identities without active auth',
    () async {
      await _seedGoal(database, 'old-user-id');
      await _seedGoal(database, 'current-user-id');
      auth.lookupPurgeReceipts['old-user-id'] = UserPurgeReceipt(
        userId: 'old-user-id',
        status: UserPurgeStatus.completed,
        purgedAt: DateTime.utc(2026, 9, 26),
      );

      final purgedCount = await cleanup.purgeLocallyConfirmedUsers();

      expect(purgedCount, 1);
      expect(
        auth.purgeReceiptLookupIds,
        containsAll(['old-user-id', 'current-user-id']),
      );
      expect(await _goalCount(database, 'old-user-id'), 0);
      expect(await _goalCount(database, 'current-user-id'), 1);
    },
  );

  test(
    'lookup failure propagates and leaves that identity data intact',
    () async {
      await _seedGoal(database, 'old-user-id');
      auth.purgeReceiptLookupError = StateError('offline');

      await expectLater(
        cleanup.purgeLocallyConfirmedUsers(),
        throwsA(isA<StateError>()),
      );

      expect(await _goalCount(database, 'old-user-id'), 1);
    },
  );

  testWidgets('application startup sweeps receipts before any user signs in', (
    tester,
  ) async {
    await _seedGoal(database, 'old-user-id');
    auth.signedInUser = null;
    auth.lookupPurgeReceipts['old-user-id'] = UserPurgeReceipt(
      userId: 'old-user-id',
      status: UserPurgeStatus.completed,
      purgedAt: DateTime.utc(2026, 9, 26),
    );

    await tester.pumpWidget(
      PactaApp(authRepository: auth, userPurgeCleanupRepository: cleanup),
    );
    await tester.pumpAndSettle();

    expect(auth.currentUserId, isNull);
    expect(auth.purgeReceiptLookupIds, contains('old-user-id'));
    expect(await _goalCount(database, 'old-user-id'), 0);
  });
}

Future<void> _seedGoal(PactaDatabase database, String userId) => database
    .into(database.localGoals)
    .insert(
      LocalGoalsCompanion.insert(
        userId: userId,
        id: 'goal-$userId',
        title: 'Local cache',
        classification: 'regular',
        createdAt: DateTime.utc(2026, 9, 26),
        updatedAt: DateTime.utc(2026, 9, 26),
      ),
    );

Future<int> _goalCount(PactaDatabase database, String userId) async =>
    (await (database.select(
      database.localGoals,
    )..where((row) => row.userId.equals(userId))).get()).length;
