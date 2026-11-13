import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/sync/cloud_auto_upload_preference.dart';
import 'package:pacta/src/sync/cloud_auto_upload_queue.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';

void main() {
  late PactaDatabase database;
  late FakeAuthRepository auth;
  late UserPurgeCleanupRepository cleanup;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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

  test('确认清除后一并删除冻结队列与开关，且不影响其他用户', () async {
    await _seedGoal(database, 'old-user-id');
    await _seedGoal(database, 'current-user-id');
    final store = InMemoryCloudAutoUploadQueueStore();
    await store.save('old-user-id', _frozenQueue('old-user-id'));
    await store.save(
      'current-user-id',
      const CloudAutoUploadQueue().recordIntent(DateTime.utc(2026, 11, 13)),
    );
    const preference = CloudAutoUploadPreference();
    await preference.save('old-user-id', true);
    await preference.save('current-user-id', true);
    auth.lookupPurgeReceipts['old-user-id'] = _receipt('old-user-id');
    final scoped = UserPurgeCleanupRepository(
      authRepository: auth,
      database: database,
      queueStore: store,
      autoUploadPreference: preference,
    );

    expect(await scoped.purgeLocallyConfirmedUsers(), 1);

    expect((await store.load('old-user-id')).hasWork, isFalse);
    expect(await preference.load('old-user-id'), isFalse);
    expect(await _goalCount(database, 'old-user-id'), 0);
    expect((await store.load('current-user-id')).pending, isTrue);
    expect(await preference.load('current-user-id'), isTrue);
    expect(await _goalCount(database, 'current-user-id'), 1);
  });

  test('只剩队列残留的旧用户也按 receipt 清除，不依赖当前登录用户', () async {
    final store = InMemoryCloudAutoUploadQueueStore();
    await store.save('purged-only-queue', _frozenQueue('purged-only-queue'));
    await store.save(
      'queue-without-receipt',
      _frozenQueue('queue-without-receipt'),
    );
    auth.lookupPurgeReceipts['purged-only-queue'] = _receipt(
      'purged-only-queue',
    );
    final scoped = UserPurgeCleanupRepository(
      authRepository: auth,
      database: database,
      queueStore: store,
      autoUploadPreference: const CloudAutoUploadPreference(),
    );

    expect(await scoped.purgeLocallyConfirmedUsers(), 1);
    expect((await store.load('purged-only-queue')).hasWork, isFalse);
    expect((await store.load('queue-without-receipt')).hasWork, isTrue);
    expect(
      auth.purgeReceiptLookupIds,
      containsAll(['purged-only-queue', 'queue-without-receipt']),
    );
  });

  test('清除后留下只前进的资料清除代次，且不会被重复清扫', () async {
    await _seedGoal(database, 'old-user-id');
    await database
        .into(database.localProfileAccounts)
        .insertOnConflictUpdate(
          LocalProfileAccountsCompanion.insert(
            userId: 'old-user-id',
            updatedAt: DateTime.utc(2026, 11, 13),
            displayName: const Value('已清除昵称'),
          ),
        );
    auth.lookupPurgeReceipts['old-user-id'] = _receipt('old-user-id');

    expect(await cleanup.purgeLocallyConfirmedUsers(), 1);
    expect(
      await (database.select(database.localProfileAccounts)).get(),
      isEmpty,
    );
    var mark = await (database.select(
      database.localProfileClearMarks,
    )..where((row) => row.userId.equals('old-user-id'))).getSingle();
    expect(mark.generation, 1, reason: '清除代次必须前进');

    // 代次本身不是用户数据：第二次清扫不会把这具清除标记当成待清除内容。
    expect(await cleanup.purgeLocallyConfirmedUsers(), 0);
    mark = await (database.select(
      database.localProfileClearMarks,
    )..where((row) => row.userId.equals('old-user-id'))).getSingle();
    expect(mark.generation, 1);
  });

  test('清除队列失败时抛错保留 receipt，下次运行继续重试', () async {
    final store = _FailingClearStore();
    await store.save('old-user-id', _frozenQueue('old-user-id'));
    auth.lookupPurgeReceipts['old-user-id'] = _receipt('old-user-id');
    final scoped = UserPurgeCleanupRepository(
      authRepository: auth,
      database: database,
      queueStore: store,
      autoUploadPreference: const CloudAutoUploadPreference(),
    );

    store.clearFailure = StateError('disk busy');
    await expectLater(
      scoped.purgeLocallyConfirmedUsers(),
      throwsA(isA<StateError>()),
    );
    expect((await store.load('old-user-id')).hasWork, isTrue);

    store.clearFailure = null;
    expect(await scoped.purgeLocallyConfirmedUsers(), 1);
    expect((await store.load('old-user-id')).hasWork, isFalse);
    expect(
      auth.purgeReceiptLookupIds.where((id) => id == 'old-user-id'),
      hasLength(2),
    );
  });

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

UserPurgeReceipt _receipt(String userId) => UserPurgeReceipt(
  userId: userId,
  status: UserPurgeStatus.completed,
  purgedAt: DateTime.utc(2026, 11, 13),
);

CloudAutoUploadQueue _frozenQueue(String userId) => CloudAutoUploadQueue(
  pending: true,
  requestedAt: DateTime.utc(2026, 11, 13),
  request: CloudAutoUploadAttempt(
    requestId: 'request-$userId',
    fingerprint: 'v2:0000000000000001',
    expectedRevision: 3,
    startedAt: DateTime.utc(2026, 11, 13),
    attempted: true,
    payload: {
      'schemaVersion': 1,
      'userId': userId,
      'tables': {
        'local_goals': [
          {'id': 'goal-1', 'title': '冻结的业务副本'},
        ],
      },
    },
    rowCount: 1,
    dataUpdatedAt: DateTime.utc(2026, 11, 13),
  ),
);

class _FailingClearStore extends InMemoryCloudAutoUploadQueueStore {
  Object? clearFailure;

  @override
  Future<void> clear(String userId) async {
    final failure = clearFailure;
    if (failure != null) throw failure;
    await super.clear(userId);
  }
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
