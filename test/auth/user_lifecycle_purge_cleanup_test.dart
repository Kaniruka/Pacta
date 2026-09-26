import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/fake_auth_repository.dart';

void main() {
  late PactaDatabase database;
  late FakeAuthRepository auth;
  late UserLifecycleRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    auth = FakeAuthRepository();
    repository = UserLifecycleRepository(
      authRepository: auth,
      localAccess: LocalUserLifecycleAccess(
        database: database,
        userId: 'old-user-id',
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'a completed receipt for the old identity clears only its local rows',
    () async {
      await _seedGoal(database, 'old-user-id');
      await _seedGoal(database, 'new-user-id');
      auth.lookupPurgeReceiptResult = UserPurgeReceipt(
        userId: 'old-user-id',
        status: UserPurgeStatus.completed,
        purgedAt: DateTime.utc(2026, 9, 26),
      );

      final cleaned = await repository.purgeLocalDataIfConfirmed('old-user-id');

      expect(cleaned, isTrue);
      expect(await _goalCount(database, 'old-user-id'), 0);
      expect(await _goalCount(database, 'new-user-id'), 1);
      expect(auth.purgeReceiptLookupIds, ['old-user-id']);
    },
  );

  test(
    'a missing, pending, or mismatched receipt leaves the cache intact',
    () async {
      await _seedGoal(database, 'old-user-id');
      auth.lookupPurgeReceiptResult = UserPurgeReceipt(
        userId: 'another-user-id',
        status: UserPurgeStatus.completed,
        purgedAt: DateTime.utc(2026, 9, 26),
      );

      expect(
        await repository.purgeLocalDataIfConfirmed('old-user-id'),
        isFalse,
      );
      expect(await _goalCount(database, 'old-user-id'), 1);

      auth.lookupPurgeReceiptResult = UserPurgeReceipt(
        userId: 'old-user-id',
        status: UserPurgeStatus.pending,
      );
      expect(
        await repository.purgeLocalDataIfConfirmed('old-user-id'),
        isFalse,
      );
      expect(await _goalCount(database, 'old-user-id'), 1);

      auth.lookupPurgeReceiptResult = null;
      expect(
        await repository.purgeLocalDataIfConfirmed('old-user-id'),
        isFalse,
      );
      expect(await _goalCount(database, 'old-user-id'), 1);
    },
  );

  test(
    'a receipt lookup error propagates without deleting cached data',
    () async {
      await _seedGoal(database, 'old-user-id');
      auth.purgeReceiptLookupError = StateError('network unavailable');

      await expectLater(
        repository.purgeLocalDataIfConfirmed('old-user-id'),
        throwsA(isA<StateError>()),
      );
      expect(await _goalCount(database, 'old-user-id'), 1);
    },
  );
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
