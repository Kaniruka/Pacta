import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late PactaDatabase database;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('last known suspension stays cached through network failure and clears on restore', () async {
    final access = LocalUserLifecycleAccess(
      database: database,
      userId: 'user-a',
    );
    final suspendedAt = DateTime.utc(2026, 9, 1);
    await access.saveStatus(
      UserLifecycleStatus(
        isSuspended: true,
        suspendedAt: suspendedAt,
        purgeEligibleAt: suspendedAt.add(const Duration(days: 30)),
        checkedAt: suspendedAt,
      ),
    );

    final auth = FakeAuthRepository()
      ..lifecycleStatusError = StateError('network unavailable');
    final lifecycle = UserLifecycleRepository(
      authRepository: auth,
      localAccess: LocalUserLifecycleAccess(
        database: database,
        userId: 'user-a',
      ),
    );
    await expectLater(lifecycle.refresh(), throwsStateError);

    final reopenedAccess = LocalUserLifecycleAccess(
      database: database,
      userId: 'user-a',
    );
    expect(await reopenedAccess.isSuspended(), isTrue);
    expect(
      (await reopenedAccess.readStatus())!.suspendedAt!.isAtSameMomentAs(
        suspendedAt,
      ),
      isTrue,
    );

    auth.lifecycleStatus = UserLifecycleStatus(
      isSuspended: false,
      checkedAt: DateTime.utc(2026, 9, 2),
    );
    auth.lifecycleStatusError = null;
    await lifecycle.refresh();
    expect(await reopenedAccess.isSuspended(), isFalse);
  });
}

class MutableUserLifecycleAccess implements UserLifecycleAccess {
  bool suspended = false;

  @override
  Future<bool> isSuspended() async => suspended;

  @override
  Future<void> requireActive() async {
    if (suspended) throw const UserOperationsSuspendedException();
  }
}

class OfflineAwareTaskRemote extends InMemoryTaskRemote {
  bool offline = false;
  int pullCount = 0;

  @override
  Future<TaskRemoteSnapshot> pull({required String userId}) async {
    pullCount++;
    if (offline) throw StateError('network unavailable');
    return super.pull(userId: userId);
  }
}

class CountingFocusRemote extends InMemoryFocusRemote {
  int pullCount = 0;

  @override
  Future<FocusRemoteSnapshot> pull({required String userId}) {
    pullCount++;
    return super.pull(userId: userId);
  }
}

class CountingNationalFocusRemote
    extends InMemoryNationalFocusRemoteDataSource {
  int pullCount = 0;

  @override
  Future<List<NationalFocusSyncSource>> pull({required String userId}) {
    pullCount++;
    return super.pull(userId: userId);
  }
}

class OfflineAwareNationalFocusRemote
    extends InMemoryNationalFocusRemoteDataSource {
  bool offline = false;
  int pullCount = 0;

  @override
  Future<List<NationalFocusSyncSource>> pull({required String userId}) async {
    pullCount++;
    if (offline) throw StateError('network unavailable');
    return super.pull(userId: userId);
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<NationalFocusSyncSource> sources,
  }) async {
    if (offline) throw StateError('network unavailable');
    await super.upsertSources(userId: userId, sources: sources);
  }
}
