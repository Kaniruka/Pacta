import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
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

  test('known suspension rejects new task work and keeps queued edits for restoration', () async {
    final access = MutableUserLifecycleAccess();
    final remote = OfflineAwareTaskRemote()..offline = true;
    final repository = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: remote,
      lifecycleAccess: access,
    );
    addTearDown(repository.dispose);

    final goal = await repository.createGoal(
      const GoalDraft(
        title: 'Keep local work',
        classification: TaskClassification.regular,
      ),
    );
    await expectLater(repository.sync(), throwsStateError);

    access.suspended = true;
    await expectLater(
      repository.createTask(goal.id, const TaskDraft(title: 'Blocked task')),
      throwsA(isA<UserOperationsSuspendedException>()),
    );
    final requestsBeforeSuspendedSync = remote.pullCount;

    await repository.sync();

    expect(remote.pullCount, requestsBeforeSuspendedSync);
    expect((await repository.getGoals()).single.title, 'Keep local work');

    access.suspended = false;
    remote.offline = false;
    await repository.sync();

    expect(remote.goals.single.title, 'Keep local work');
    expect(remote.pullCount, requestsBeforeSuspendedSync + 1);
  });

  test(
    'known suspension lets due preparation hand off and focus settle locally',
    () async {
      var now = DateTime.utc(2026, 9, 26, 2);
      final access = MutableUserLifecycleAccess();
      final tasks = LocalTaskRepository(
        database: database,
        userId: 'user-a',
        remote: InMemoryTaskRemote(),
        now: () => now,
      );
      addTearDown(tasks.dispose);
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: 'Offline flow',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(title: 'Finish offline flow'),
      );
      final remote = CountingFocusRemote();
      final focus = LocalFocusRepository(
        database: database,
        userId: 'user-a',
        remote: remote,
        now: () => now,
        lifecycleAccess: access,
      );
      addTearDown(focus.dispose);

      final appointment = await focus.startAppointment(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(seconds: 40),
      );
      access.suspended = true;
      now = appointment.endsAt;
      await focus.sync();

      expect((await focus.getAppointment(appointment.id))!.isSucceeded, isTrue);
      final handedOffSession = await focus.getActiveSession();
      expect(handedOffSession, isNotNull);
      expect(
        handedOffSession!.startedAt.isAtSameMomentAs(appointment.endsAt),
        isTrue,
      );

      now = handedOffSession.endsAt;
      await focus.sync();

      expect(
        (await focus.getSession(handedOffSession.id))!.status,
        FocusSessionStatus.completed,
      );
      expect(await focus.getNodes(), hasLength(1));
      expect(remote.pullCount, 0);
    },
  );

  test(
    'known suspension leaves an already paused focus session paused',
    () async {
      var now = DateTime.utc(2026, 9, 26, 3);
      final access = MutableUserLifecycleAccess();
      final tasks = LocalTaskRepository(
        database: database,
        userId: 'user-a',
        remote: InMemoryTaskRemote(),
        now: () => now,
      );
      addTearDown(tasks.dispose);
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: 'Paused flow',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(title: 'Keep pause'),
      );
      final focus = LocalFocusRepository(
        database: database,
        userId: 'user-a',
        remote: CountingFocusRemote(),
        now: () => now,
        lifecycleAccess: access,
      );
      addTearDown(focus.dispose);

      final session = await focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(seconds: 30),
      );
      await focus.pauseSession(session.id, ruleText: 'approved pause');
      access.suspended = true;
      now = session.endsAt.add(const Duration(hours: 1));

      await focus.sync();

      expect(
        (await focus.getSession(session.id))!.status,
        FocusSessionStatus.paused,
      );
      await expectLater(
        focus.resumeSession(session.id),
        throwsA(isA<UserOperationsSuspendedException>()),
      );
    },
  );

  test('suspension preserves a valid offline National Focus confirmation for later sync', () async {
    var now = DateTime.utc(2026, 9, 20, 19, 59);
    final access = MutableUserLifecycleAccess();
    final remote = CountingNationalFocusRemote();
    final firstDevice = LocalNationalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: remote,
      now: () => now,
      lifecycleAccess: access,
    );
    addTearDown(firstDevice.dispose);
    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    addTearDown(secondDatabase.close);
    final secondDevice = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'user-a',
      remote: remote,
      now: () => now,
    );
    addTearDown(secondDevice.dispose);

    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '开始阅读', action: '阅读 5 页'),
    );
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);
    now = DateTime.utc(2026, 9, 20, 20);
    await firstDevice.settleDueCheckpoints();
    await firstDevice.sync();
    await secondDevice.sync();

    now = DateTime.utc(2026, 9, 21, 19);
    expect(await firstDevice.confirmToday(), 1);
    access.suspended = true;
    now = DateTime.utc(2026, 9, 21, 20);
    await secondDevice.settleDueCheckpoints();
    await secondDevice.sync();
    final pullsBeforeSuspendedSync = remote.pullCount;
    await firstDevice.sync();

    expect(remote.pullCount, pullsBeforeSuspendedSync);
    await expectLater(
      firstDevice.confirmToday(),
      throwsA(isA<UserOperationsSuspendedException>()),
    );

    access.suspended = false;
    now = DateTime.utc(2026, 9, 23, 21);
    await firstDevice.sync();
    await secondDevice.sync();

    final failures = await secondDevice.getFailures(cardId: card.id);
    expect(failures, hasLength(1));
    expect(failures.single.checkpointAt.toUtc(), DateTime.utc(2026, 9, 22, 20));
    expect((await secondDevice.getCard(card.id)).successfulDays, 2);
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
