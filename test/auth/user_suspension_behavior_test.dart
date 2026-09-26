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

  test('two devices reconcile offline work when they learn suspension at different times', () async {
    final remote = OfflineAwareTaskRemote();
    final firstDatabase = PactaDatabase(NativeDatabase.memory());
    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    addTearDown(firstDatabase.close);
    addTearDown(secondDatabase.close);

    final firstLifecycle = LocalUserLifecycleAccess(
      database: firstDatabase,
      userId: 'user-a',
    );
    final secondLifecycle = LocalUserLifecycleAccess(
      database: secondDatabase,
      userId: 'user-a',
    );
    final firstDevice = LocalTaskRepository(
      database: firstDatabase,
      userId: 'user-a',
      remote: remote,
      lifecycleAccess: firstLifecycle,
    );
    final secondDevice = LocalTaskRepository(
      database: secondDatabase,
      userId: 'user-a',
      remote: remote,
      lifecycleAccess: secondLifecycle,
    );
    addTearDown(firstDevice.dispose);
    addTearDown(secondDevice.dispose);
    final checkedAt = DateTime.utc(2026, 9, 26);

    final sharedGoal = await firstDevice.createGoal(
      const GoalDraft(
        title: 'Shared goal',
        classification: TaskClassification.regular,
      ),
    );
    await firstDevice.sync();
    await secondDevice.sync();
    expect((await secondDevice.getGoals()).single.id, sharedGoal.id);
    expect(await secondLifecycle.readStatus(), isNull);

    final suspension = UserLifecycleStatus(
      isSuspended: true,
      suspendedAt: checkedAt,
      purgeEligibleAt: checkedAt.add(const Duration(days: 30)),
      checkedAt: checkedAt,
    );
    await firstLifecycle.saveStatus(suspension);
    await expectLater(
      firstDevice.createTask(
        sharedGoal.id,
        const TaskDraft(title: 'Blocked on device one'),
      ),
      throwsA(isA<UserOperationsSuspendedException>()),
    );

    remote.offline = true;
    final offlineTask = await secondDevice.createTask(
      sharedGoal.id,
      const TaskDraft(title: 'Offline work from device two'),
    );
    await expectLater(secondDevice.sync(), throwsStateError);
    expect(remote.tasks, isEmpty);

    await secondLifecycle.saveStatus(suspension);
    await secondDevice.sync();
    expect(remote.tasks, isEmpty);
    expect(
      (await secondDevice.getGoals()).single.tasks.single.id,
      offlineTask.id,
    );

    remote.offline = false;
    final restored = UserLifecycleStatus(
      isSuspended: false,
      checkedAt: checkedAt.add(const Duration(days: 2)),
    );
    await firstLifecycle.saveStatus(restored);
    await secondLifecycle.saveStatus(restored);
    await secondDevice.sync();
    await firstDevice.sync();
    await secondDevice.sync();

    expect(remote.tasks, hasLength(1));
    expect(remote.tasks.single.id, offlineTask.id);
    expect(
      (await firstDevice.getGoals()).single.tasks.single.id,
      offlineTask.id,
    );
    expect(
      (await secondDevice.getGoals()).single.tasks.single.id,
      offlineTask.id,
    );
  });

  test('two devices preserve focus and National Focus state across suspension and restore', () async {
    var now = DateTime.utc(2026, 9, 20, 19, 59);
    final firstDatabase = PactaDatabase(NativeDatabase.memory());
    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    addTearDown(firstDatabase.close);
    addTearDown(secondDatabase.close);

    final firstLifecycle = LocalUserLifecycleAccess(
      database: firstDatabase,
      userId: 'user-a',
    );
    final secondLifecycle = LocalUserLifecycleAccess(
      database: secondDatabase,
      userId: 'user-a',
    );
    final taskRemote = OfflineAwareTaskRemote();
    final firstTasks = LocalTaskRepository(
      database: firstDatabase,
      userId: 'user-a',
      remote: taskRemote,
      lifecycleAccess: firstLifecycle,
      now: () => now,
    );
    final secondTasks = LocalTaskRepository(
      database: secondDatabase,
      userId: 'user-a',
      remote: taskRemote,
      lifecycleAccess: secondLifecycle,
      now: () => now,
    );
    addTearDown(firstTasks.dispose);
    addTearDown(secondTasks.dispose);

    final focusRemote = CountingFocusRemote();
    final firstFocus = LocalFocusRepository(
      database: firstDatabase,
      userId: 'user-a',
      remote: focusRemote,
      lifecycleAccess: firstLifecycle,
      now: () => now,
    );
    final secondFocus = LocalFocusRepository(
      database: secondDatabase,
      userId: 'user-a',
      remote: focusRemote,
      lifecycleAccess: secondLifecycle,
      now: () => now,
    );
    addTearDown(firstFocus.dispose);
    addTearDown(secondFocus.dispose);

    final nationalFocusRemote = OfflineAwareNationalFocusRemote();
    final firstNationalFocus = LocalNationalFocusRepository(
      database: firstDatabase,
      userId: 'user-a',
      remote: nationalFocusRemote,
      lifecycleAccess: firstLifecycle,
      now: () => now,
    );
    final secondNationalFocus = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'user-a',
      remote: nationalFocusRemote,
      lifecycleAccess: secondLifecycle,
      now: () => now,
    );
    addTearDown(firstNationalFocus.dispose);
    addTearDown(secondNationalFocus.dispose);

    final goal = await firstTasks.createGoal(
      const GoalDraft(
        title: 'Shared lifecycle goal',
        classification: TaskClassification.regular,
      ),
    );
    final task = await firstTasks.createTask(
      goal.id,
      const TaskDraft(title: 'Focus across suspension'),
    );
    await firstTasks.sync();
    await secondTasks.sync();

    final card = await firstNationalFocus.createCard(
      const NationalFocusCardDraft(triggerCondition: '开始工作前', action: '写下第一步'),
    );
    await firstNationalFocus.placeCard(cardId: card.id, parentId: null);
    await firstNationalFocus.lightCard(card.id);
    await firstNationalFocus.sync();
    await secondNationalFocus.sync();

    now = DateTime.utc(2026, 9, 20, 20, 0, 1);
    await secondNationalFocus.settleDueCheckpoints();
    expect(
      (await secondNationalFocus.getCard(card.id)).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    expect(await secondNationalFocus.confirmToday(), 1);
    nationalFocusRemote.offline = true;
    await expectLater(secondNationalFocus.sync(), throwsStateError);
    expect(
      (await secondNationalFocus.getCard(card.id)).state,
      NationalFocusCardState.lit,
    );

    final appointment = await firstFocus.startAppointment(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 40),
    );
    await firstFocus.sync();
    final focusPullsBeforeSuspension = focusRemote.pullCount;
    final suspension = UserLifecycleStatus(
      isSuspended: true,
      suspendedAt: now,
      purgeEligibleAt: now.add(const Duration(days: 30)),
      checkedAt: now,
    );
    await firstLifecycle.saveStatus(suspension);

    now = appointment.endsAt;
    await firstFocus.sync();
    expect(
      (await firstFocus.getAppointment(appointment.id))!.isSucceeded,
      isTrue,
    );
    final handedOffSession = (await firstFocus.getActiveSession())!;
      expect(
        handedOffSession.startedAt.isAtSameMomentAs(appointment.endsAt),
        isTrue,
      );
    expect(focusRemote.pullCount, focusPullsBeforeSuspension);

    now = handedOffSession.endsAt;
    await firstFocus.sync();
    expect(
      (await firstFocus.getSession(handedOffSession.id))!.status,
      FocusSessionStatus.completed,
    );

    await firstLifecycle.saveStatus(
      UserLifecycleStatus(isSuspended: false, checkedAt: now),
    );
    final pausedSession = await firstFocus.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(seconds: 30),
    );
    await firstFocus.pauseSession(pausedSession.id, ruleText: '暂停状态保留到恢复后');
    await firstLifecycle.saveStatus(
      UserLifecycleStatus(
        isSuspended: true,
        suspendedAt: now,
        purgeEligibleAt: now.add(const Duration(days: 30)),
        checkedAt: now,
      ),
    );
    now = pausedSession.endsAt.add(const Duration(hours: 1));
    await firstFocus.sync();
    expect(
      (await firstFocus.getSession(pausedSession.id))!.status,
      FocusSessionStatus.paused,
    );

    expect(await secondLifecycle.readStatus(), isNull);
    taskRemote.offline = true;
    final offlineTask = await secondTasks.createTask(
      goal.id,
      const TaskDraft(title: 'Offline task while status is unknown'),
    );
    await expectLater(secondTasks.sync(), throwsStateError);
    expect(
      taskRemote.tasks.any((remoteTask) => remoteTask.id == offlineTask.id),
      isFalse,
    );

    await secondLifecycle.saveStatus(suspension);
    final taskPullsWhileSuspended = taskRemote.pullCount;
    final nationalFocusPullsWhileSuspended = nationalFocusRemote.pullCount;
    await secondTasks.sync();
    await secondNationalFocus.sync();
    expect(taskRemote.pullCount, taskPullsWhileSuspended);
    expect(nationalFocusRemote.pullCount, nationalFocusPullsWhileSuspended);
    expect(
      taskRemote.tasks.any((remoteTask) => remoteTask.id == offlineTask.id),
      isFalse,
    );

    taskRemote.offline = false;
    nationalFocusRemote.offline = false;
    final restored = UserLifecycleStatus(
      isSuspended: false,
      checkedAt: now.add(const Duration(minutes: 1)),
    );
    await firstLifecycle.saveStatus(restored);
    await secondLifecycle.saveStatus(restored);
    await secondTasks.sync();
    await firstTasks.sync();
    await secondTasks.sync();
    await firstFocus.sync();
    await firstFocus.sync();
    await secondFocus.sync();
    await secondNationalFocus.sync();
    await firstNationalFocus.sync();
    await secondNationalFocus.sync();

    expect(
      taskRemote.tasks.where((remoteTask) => remoteTask.id == offlineTask.id),
      hasLength(1),
    );
    expect(
      (await secondTasks.getGoals()).single.tasks.any(
        (localTask) => localTask.id == offlineTask.id,
      ),
      isTrue,
    );
    expect(
      (await secondFocus.getAppointment(appointment.id))!.isSucceeded,
      isTrue,
    );
    expect(
      (await secondFocus.getSession(handedOffSession.id))!.status,
      FocusSessionStatus.completed,
    );
    expect(
      (await secondFocus.getSession(pausedSession.id))!.status,
      FocusSessionStatus.paused,
    );
    expect(
      (await secondNationalFocus.getCard(card.id)).state,
      NationalFocusCardState.lit,
    );
    expect(await secondNationalFocus.getFailures(cardId: card.id), isEmpty);
    final remoteSources = await nationalFocusRemote.pull(userId: 'user-a');
    expect(
      remoteSources.map((source) => source.sourceId).toSet(),
      hasLength(remoteSources.length),
    );
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
