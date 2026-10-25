import 'dart:async';

import 'package:drift/native.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/calendar/calendar_provider.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/sync/cloud_sync_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/auth/user_lifecycle.dart';
import 'package:pacta/src/auth/user_lifecycle_models.dart';
import 'package:pacta/src/sync/cloud_snapshot_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' hide FocusSession;

import '../support/fake_auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
          (_) async => null,
        );
  });
  testWidgets(
    'cold start discovers cloud without transferring business data and foreground waits five minutes',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _Remote();
      var now = DateTime.utc(2026, 10, 24);
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      final tasks = LocalTaskRepository(
        database: database,
        userId: 'reader',
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
      );
      await tasks.createGoal(
        const GoalDraft(
          title: 'Untouched local business',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.dispose();
      // Establish ordinary local recovery metadata before measuring cloud reads.
      final nationalFocus = LocalNationalFocusRepository(
        database: database,
        userId: 'reader',
        cloudSyncEnabled: false,
      );
      await nationalFocus.settleDueCheckpoints();
      await nationalFocus.dispose();
      final before = await repository.captureLocalState();
      await tester.pumpWidget(
        _app(database, auth, repository, cloudCheckClock: () => now),
      );
      await tester.pumpAndSettle();
      expect(remote.inspections, 1);
      expect(find.text('选择同步方式'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('云端有待处理更新'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      now = now.add(const Duration(minutes: 4, seconds: 59));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(remote.inspections, 1);
      now = now.add(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(remote.inspections, 2);
      expect(remote.transfers, 0);
      expect(
        (await repository.captureLocalState()).fingerprint,
        before.fingerprint,
      );
      auth.lifecycleStatus = UserLifecycleStatus(
        isSuspended: true,
        checkedAt: now,
      );
      now = now.add(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.textContaining('此用户已停用'), findsOneWidget);
      expect(remote.inspections, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );
  testWidgets(
    'ignore persists per user across restart and only suppresses that version',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _Remote();
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      var now = DateTime.utc(2026, 10, 24);
      Future<void> open() async {
        await tester.pumpWidget(
          _app(database, auth, repository, cloudCheckClock: () => now),
        );
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.text('选择同步方式'), findsOneWidget);
      await tester.tap(find.text('忽略'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await open();
      expect(find.text('选择同步方式'), findsNothing);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('查看云端并选择方向'));
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      remote.revision = 3;
      now = now.add(const Duration(minutes: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsOneWidget);
      expect(remote.transfers, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );

  for (final flow in ['appointment', 'active', 'paused']) {
    testWidgets(
      '$flow defers choice, preserves manual upload and offers latest version after ending',
      (tester) async {
        final database = PactaDatabase(NativeDatabase.memory());
        final auth = FakeAuthRepository()..signedInUser = 'reader';
        final remote = _Remote();
        final repository = CloudSnapshotRepository(
          database: database,
          remote: remote,
          userId: 'reader',
          deviceName: 'test',
        );
        final tasks = LocalTaskRepository(
          database: database,
          userId: 'reader',
          remote: InMemoryTaskRemote(),
          cloudSyncEnabled: false,
        );
        final goal = await tasks.createGoal(
          const GoalDraft(
            title: 'Goal',
            classification: TaskClassification.regular,
          ),
        );
        final task = await tasks.createTask(
          goal.id,
          const TaskDraft(title: 'Focus task', classification: null),
        );
        await tasks.dispose();
        final focus = LocalFocusRepository(
          database: database,
          userId: 'reader',
          remote: InMemoryFocusRemote(),
          cloudSyncEnabled: false,
          now: () => DateTime.utc(2026, 10, 25),
        );
        String flowId;
        if (flow == 'appointment') {
          flowId = (await focus.startAppointment(
            taskId: task.id,
            mode: FocusChainMode.regular,
            duration: const Duration(minutes: 25),
          )).id;
        } else {
          flowId = (await focus.startSession(
            taskId: task.id,
            mode: FocusChainMode.regular,
            duration: const Duration(minutes: 25),
          )).id;
          if (flow == 'paused') {
            await focus.pauseSession(flowId, ruleText: 'Pause test');
          }
        }
        await tester.pumpWidget(
          _app(database, auth, repository, focusRepository: focus),
        );
        await tester.pumpAndSettle();
        expect(find.text('选择同步方式'), findsNothing);
        expect(find.text('云端有待处理更新，流程结束后可选择同步。'), findsOneWidget);
        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('查看云端并选择方向'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '下载'))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '上传'))
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        remote.revision = 3;
        remote.deviceName = 'Latest device';
        if (flow == 'appointment') {
          await focus.cancelAppointment(
            appointmentId: flowId,
            failureReason: 'End test',
          );
        } else {
          await focus.abandonSession(
            sessionId: flowId,
            failureReason: 'End test',
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('选择同步方式'), findsOneWidget);
        expect(find.text('云端来源：Latest device'), findsOneWidget);
        expect(remote.transfers, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await database.close();
      },
    );
  }

  testWidgets(
    'ending focus while manual preview is open offers the latest version after cancellation once',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _Remote();
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      final tasks = LocalTaskRepository(
        database: database,
        userId: 'reader',
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
      );
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: 'Goal',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(title: 'Focus task', classification: null),
      );
      await tasks.dispose();
      var now = DateTime.utc(2026, 10, 25);
      final focus = LocalFocusRepository(
        database: database,
        userId: 'reader',
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
        now: () => now,
      );
      await focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      await tester.pumpWidget(
        _app(database, auth, repository, focusRepository: focus),
      );
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsNothing);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('查看云端并选择方向'));
      await tester.pumpAndSettle();
      expect(find.text('云端来源：Other device'), findsOneWidget);
      remote.revision = 3;
      remote.deviceName = 'Latest device';
      now = now.add(const Duration(minutes: 25));
      await focus.settleDueSessions();
      await tester.pumpAndSettle();
      // The user's open preview stays stable until it is closed.
      expect(find.text('云端来源：Other device'), findsOneWidget);
      expect(find.text('云端来源：Latest device'), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsOneWidget);
      expect(find.text('云端来源：Latest device'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsNothing);
      expect(remote.transfers, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );

  testWidgets(
    'appointment cancellation keeps a newer cloud choice open while notification cleanup completes',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _Remote();
      final notifications = _DelayedNotificationCleanup();
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      final tasks = LocalTaskRepository(
        database: database,
        userId: 'reader',
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
      );
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: 'Goal',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(title: 'Focus task', classification: null),
      );
      await tasks.dispose();
      final focus = LocalFocusRepository(
        database: database,
        userId: 'reader',
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
        now: () => DateTime.utc(2026, 10, 25),
      );
      await focus.startAppointment(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      await tester.pumpWidget(
        _app(
          database,
          auth,
          repository,
          focusRepository: focus,
          notificationService: notifications,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('专注链'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('返回准备'));
      await tester.tap(find.text('返回准备'));
      await tester.pumpAndSettle();
      expect(find.text('预约准备'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('取消预约并填写失败原因'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(AppointmentPreparationPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('取消预约并填写失败原因'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Cancel appointment',
      );
      remote.revision = 3;
      remote.deviceName = 'Latest device';
      notifications.armed = true;
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsOneWidget);
      expect(find.text('云端来源：Latest device'), findsOneWidget);
      notifications.release.complete();
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsOneWidget);
      expect(find.text('云端来源：Latest device'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('预约准备'), findsNothing);
      expect(find.text('选择任务'), findsOneWidget);
      expect(await focus.getActiveAppointment(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );

  for (final action in ['忽略', '上传']) {
    testWidgets(
      'manual $action during focus prevents a deferred reminder after ending',
      (tester) async {
        final database = PactaDatabase(NativeDatabase.memory());
        final auth = FakeAuthRepository()..signedInUser = 'reader';
        final remote = _Remote()..allowUpload = true;
        final repository = CloudSnapshotRepository(
          database: database,
          remote: remote,
          userId: 'reader',
          deviceName: 'test',
        );
        final tasks = LocalTaskRepository(
          database: database,
          userId: 'reader',
          remote: InMemoryTaskRemote(),
          cloudSyncEnabled: false,
        );
        final goal = await tasks.createGoal(
          const GoalDraft(
            title: 'Goal',
            classification: TaskClassification.regular,
          ),
        );
        final task = await tasks.createTask(
          goal.id,
          const TaskDraft(title: 'Focus task', classification: null),
        );
        await tasks.dispose();
        var focusNow = DateTime.utc(2026, 10, 25);
        var focusElapsed = Duration.zero;
        final focus = LocalFocusRepository(
          database: database,
          userId: 'reader',
          remote: InMemoryFocusRemote(),
          cloudSyncEnabled: false,
          now: () => focusNow,
          monotonicNow: () => focusElapsed,
        );
        final session = await focus.startSession(
          taskId: task.id,
          mode: FocusChainMode.regular,
          duration: const Duration(minutes: 25),
        );
        await tester.pumpWidget(
          _app(database, auth, repository, focusRepository: focus),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('查看云端并选择方向'));
        await tester.pumpAndSettle();
        final before = await repository.captureLocalState();
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        if (action == '上传') {
          focusNow = focusNow.add(const Duration(seconds: 3));
          focusElapsed += const Duration(seconds: 3);
          await focus.settleDueSessions();
          await tester.pumpAndSettle();
          await tester.tap(find.text('确认上传'));
          await tester.pumpAndSettle();
          expect(find.textContaining('同步未完成：'), findsNothing);
          expect(await repository.loadSyncResult(), isNotNull);
        } else {
          expect(
            (await repository.captureLocalState()).fingerprint,
            before.fingerprint,
          );
          expect(await repository.loadSyncResult(), isNull);
        }
        await focus.abandonSession(
          sessionId: session.id,
          failureReason: 'End test',
        );
        await tester.pumpAndSettle();
        expect(find.text('选择同步方式'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await database.close();
      },
    );
  }

  testWidgets(
    'download preserves ignored version metadata independently of business replacement',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _Remote();
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      remote.payload = (await repository.captureLocalState()).payload;
      Future<void> open() async {
        await tester.pumpWidget(_app(database, auth, repository));
        await tester.pumpAndSettle();
      }

      await open();
      await tester.tap(find.text('忽略'));
      await tester.pumpAndSettle();
      remote.revision = 3;
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('查看云端并选择方向'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载'));
      await tester.pumpAndSettle();
      expect(find.textContaining('本机独有的记录将被丢弃'), findsOneWidget);
      await tester.tap(find.text('确认下载'));
      await tester.pumpAndSettle();
      expect((await repository.loadSyncResult())!.cloudRevision, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await open();
      expect(find.text('选择同步方式'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      // Re-present the ignored version at the external boundary. Its reminder
      // preference must survive even though download replaced all business rows.
      remote.revision = 2;
      await open();
      expect(find.text('选择同步方式'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );

  testWidgets(
    'old fingerprint baselines remain unknown rather than claiming unsynced changes',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _Remote();
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      await repository.syncResultStore.save(
        'reader',
        CloudSyncResult(
          succeededAt: DateTime.utc(2026),
          localFingerprint: '0123456789abcdef',
          cloudRevision: 2,
        ),
      );
      await tester.pumpWidget(_app(database, auth, repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('查看云端并选择方向'));
      await tester.pumpAndSettle();
      expect(find.textContaining('尚无可靠的本地同步基线'), findsOneWidget);
      expect(find.text('本机有尚未同步的修改；下载将丢弃这些修改。'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );

  testWidgets(
    'offline discovery is silent and the card retries without transfer',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _Remote()..fail = true;
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      await tester.pumpWidget(_app(database, auth, repository));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('云端检查失败，点击重试'), findsOneWidget);
      remote.fail = false;
      await tester.tap(find.text('云端检查失败，点击重试'));
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('云端有待处理更新'), findsOneWidget);
      expect(remote.transfers, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );

  testWidgets('failed check retry respects newly suspended access', (
    tester,
  ) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final auth = FakeAuthRepository()..signedInUser = 'reader';
    final remote = _Remote()..fail = true;
    final repository = CloudSnapshotRepository(
      database: database,
      remote: remote,
      userId: 'reader',
      deviceName: 'test',
    );
    await tester.pumpWidget(_app(database, auth, repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    auth.lifecycleStatus = UserLifecycleStatus(
      isSuspended: true,
      checkedAt: DateTime.utc(2026),
    );
    remote.fail = false;
    await tester.tap(find.text('云端检查失败，点击重试'));
    await tester.pumpAndSettle();
    expect(remote.inspections, 1);
    expect(find.text('云端有待处理更新'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await database.close();
  });
  for (final legacy in [false, true]) {
    testWidgets(
      'handled ${legacy ? 'legacy token' : 'revision'} stays quiet until version changes',
      (tester) async {
        final database = PactaDatabase(NativeDatabase.memory());
        final auth = FakeAuthRepository()..signedInUser = 'reader';
        final remote = _Remote()..legacy = legacy;
        var now = DateTime.utc(2026, 10, 24);
        final repository = CloudSnapshotRepository(
          database: database,
          remote: remote,
          userId: 'reader',
          deviceName: 'test',
        );
        await repository.syncResultStore.save(
          'reader',
          CloudSyncResult(
            succeededAt: DateTime.utc(2026),
            localFingerprint: null,
            cloudRevision: 2,
            legacyToken: legacy ? 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' : null,
          ),
        );
        await tester.pumpWidget(
          _app(database, auth, repository, cloudCheckClock: () => now),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('我的'));
        await tester.pumpAndSettle();
        expect(find.text('云端有待处理更新'), findsNothing);
        remote.revision = 3;
        remote.token = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        now = now.add(const Duration(minutes: 5));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('选择同步方式'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.text('云端有待处理更新'), findsOneWidget);
        expect(remote.transfers, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await database.close();
      },
    );
  }

  testWidgets(
    'switching user closes the previous choice without ignoring the new user version',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = _Auth()..signedInUser = 'reader';
      final remote = _Remote();
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      await tester.pumpWidget(_app(database, auth, repository));
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsOneWidget);
      remote.empty = true;
      auth.signedInUser = 'other-reader';
      auth.changes.add('same-email@example.test');
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsNothing);
      remote.empty = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('查看云端并选择方向'));
      await tester.pumpAndSettle();
      expect(find.text('选择同步方式'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await auth.changes.close();
      await database.close();
    },
  );

  testWidgets(
    'direct user switch discards a late result even with the same identifier',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = _Auth()..signedInUser = 'reader';
      final remote = _Remote()..gate = Completer<void>();
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      await tester.pumpWidget(_app(database, auth, repository));
      await tester.pumpAndSettle();
      expect(remote.inspections, 1);
      auth.signedInUser = 'other-reader';
      remote.empty = true;
      auth.changes.add('same-email@example.test');
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      remote.gate!.complete();
      await tester.pumpAndSettle();
      expect(remote.users, ['reader', 'other-reader']);
      expect(find.text('云端有待处理更新'), findsNothing);
      expect(find.text('尚未同步'), findsOneWidget);
      expect(remote.transfers, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await auth.changes.close();
      await database.close();
    },
  );
  testWidgets(
    'unknown lifecycle status never reads cloud and its failed card can retry',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()
        ..signedInUser = 'reader'
        ..lifecycleStatusError = StateError('offline');
      final remote = _Remote()..empty = true;
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      await tester.pumpWidget(_app(database, auth, repository));
      await tester.pumpAndSettle();
      expect(remote.inspections, 0);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('云端检查失败，点击重试'), findsOneWidget);
      auth.lifecycleStatusError = null;
      await tester.tap(find.text('云端检查失败，点击重试'));
      await tester.pumpAndSettle();
      expect(remote.inspections, 1);
      expect(find.text('尚未同步'), findsOneWidget);
      expect(remote.transfers, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );

  testWidgets(
    'own upload handles the version while an older automatic result arrives late',
    (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final auth = FakeAuthRepository()..signedInUser = 'reader';
      final remote = _RaceRemote();
      final repository = CloudSnapshotRepository(
        database: database,
        remote: remote,
        userId: 'reader',
        deviceName: 'test',
      );
      final local = await repository.captureLocalState();
      await remote.upload(
        userId: 'reader',
        expectedRevision: 0,
        payload: local.payload,
        deviceId: 'other',
        deviceName: 'Other',
        dataUpdatedAt: DateTime.utc(2020),
        rowCount: 0,
      );
      await tester.pumpWidget(_app(database, auth, repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('查看云端并选择方向'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上传'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认上传'));
      await tester.pumpAndSettle();
      expect((await repository.loadSyncResult())!.cloudRevision, 2);
      remote.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('云端有待处理更新'), findsNothing);
      expect(find.text('正在检查云端…'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
    },
  );
}

class _Remote implements CloudSnapshotRemote {
  final users = <String>[];
  Completer<void>? gate;
  bool empty = false;
  bool fail = false;
  bool legacy = false;
  int revision = 2;
  String deviceName = 'Other device';
  String token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  int inspections = 0;
  int transfers = 0;
  bool allowUpload = false;
  Map<String, dynamic>? payload;
  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    inspections++;
    users.add(userId);
    if (empty) return null;
    await gate?.future;
    if (fail) throw StateError('offline');
    return CloudSnapshotMetadata(
      revision: revision,
      isLegacy: legacy,
      legacyToken: legacy ? token : null,
      deviceId: 'other',
      deviceName: deviceName,
      dataUpdatedAt: DateTime.utc(2020),
      uploadedAt: DateTime.utc(2020),
      rowCount: 0,
      payload: payload,
    );
  }

  @override
  Future<CloudSnapshotMetadata> download({required String userId}) async {
    transfers++;
    if (payload == null) throw StateError('Unexpected download');
    return (await inspect(userId: userId))!;
  }

  @override
  Future<CloudSnapshotMetadata> upload({
    required String userId,
    required int expectedRevision,
    required Map<String, dynamic> payload,
    required String deviceId,
    required String deviceName,
    required DateTime dataUpdatedAt,
    required int rowCount,
    String? deviceManufacturer,
    String? deviceModel,
  }) async {
    transfers++;
    if (!allowUpload) throw StateError('Unexpected upload');
    revision++;
    this.payload = payload;
    return (await inspect(userId: userId))!;
  }
}

PactaApp _app(
  PactaDatabase database,
  FakeAuthRepository auth,
  CloudSnapshotRepository repository, {
  DateTime Function() cloudCheckClock = DateTime.now,
  FocusRepository? focusRepository,
  FocusNotificationService? notificationService,
}) => PactaApp(
  authRepository: auth,
  cloudCheckClock: cloudCheckClock,
  focusNotificationService: notificationService,
  taskRepositoryFactory: (id) => LocalTaskRepository(
    database: database,
    userId: id,
    remote: InMemoryTaskRemote(),
    cloudSyncEnabled: false,
  ),
  focusRepositoryFactory: (id) =>
      focusRepository ??
      LocalFocusRepository(
        database: database,
        userId: id,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
      ),
  nationalFocusRepositoryFactory: (id) => LocalNationalFocusRepository(
    database: database,
    userId: id,
    cloudSyncEnabled: false,
  ),
  calendarRepositoryFactory: (id) => LocalCalendarRepository(
    database: database,
    userId: id,
    provider: const UnsupportedCalendarProvider(),
    remote: InMemoryCalendarRemote(),
    cloudSyncEnabled: false,
  ),
  userLifecycleRepositoryFactory: (id) => UserLifecycleRepository(
    authRepository: auth,
    localAccess: LocalUserLifecycleAccess(database: database, userId: id),
  ),
  cloudSnapshotRepositoryFactory: (id) => id == repository.userId
      ? repository
      : CloudSnapshotRepository(
          database: database,
          remote: repository.remote,
          userId: id,
          deviceName: 'test',
        ),
);

class _Auth extends FakeAuthRepository {
  final changes = StreamController<String?>.broadcast();
  @override
  Stream<String?> get authState => changes.stream;
  @override
  String? get currentUserIdentifier => 'same-email@example.test';
}

class _RaceRemote extends InMemoryCloudSnapshotRemote {
  final gate = Completer<void>();
  bool firstInspection = true;
  @override
  Future<CloudSnapshotMetadata?> inspect({required String userId}) async {
    final snapshot = await super.inspect(userId: userId);
    if (firstInspection) {
      firstInspection = false;
      await gate.future;
    }
    return snapshot;
  }
}

class _DelayedNotificationCleanup extends DisabledFocusNotificationService {
  bool armed = false;
  final release = Completer<void>();

  @override
  Future<void> sync({
    AppointmentPreparation? appointment,
    FocusSession? session,
    required String taskTitle,
  }) async {
    if (armed && appointment == null && session == null) await release.future;
  }
}
