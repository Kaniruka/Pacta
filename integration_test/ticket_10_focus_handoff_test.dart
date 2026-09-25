import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T10 另一端显示并接续同一预约和专注', (tester) async {
    final userId = 'ticket-10-user';
    final taskRemote = InMemoryTaskRemote();
    final focusRemote = InMemoryFocusRemote();
    final firstDatabase = PactaDatabase(NativeDatabase.memory());
    final now = DateTime.now().toUtc();
    final firstTaskRepository = LocalTaskRepository(
      database: firstDatabase,
      userId: userId,
      remote: taskRemote,
      now: () => now,
    );
    final firstFocusRepository = LocalFocusRepository(
      database: firstDatabase,
      userId: userId,
      remote: focusRemote,
      now: () => now,
    );

    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    final secondTaskRepository = LocalTaskRepository(
      database: secondDatabase,
      userId: userId,
      remote: taskRemote,
      now: () => now,
    );
    final secondFocusRepository = LocalFocusRepository(
      database: secondDatabase,
      userId: userId,
      remote: focusRemote,
      now: () => now,
    );

    final auth = FakeAuthRepository()..signedInUser = userId;
    try {
      final goal = await firstTaskRepository.createGoal(
        const GoalDraft(
          title: 'T10 设备接续目标',
          classification: TaskClassification.regular,
        ),
      );
      final task = await firstTaskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: 'T10 同一预约任务',
          classification: TaskClassification.regular,
        ),
      );
      final firstConfigurationTask = await firstTaskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: 'T10 第一台设备的配置',
          classification: TaskClassification.regular,
        ),
      );
      final secondConfigurationTask = await firstTaskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: 'T10 第二台设备的配置',
          classification: TaskClassification.regular,
        ),
      );
      await firstTaskRepository.sync();

      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          taskRepositoryFactory: (_) => firstTaskRepository,
          focusRepositoryFactory: (_) => firstFocusRepository,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('专注链').last);
      await tester.pumpAndSettle();
      expect(find.text(task.title), findsOneWidget);
      final startTaskButton = find.byTooltip('开始任务：${task.title}');
      expect(startTaskButton, findsOneWidget);
      await tester.tap(startTaskButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始准备（15分钟）'));
      await tester.pumpAndSettle();

      final activeAppointment = await firstFocusRepository
          .getActiveAppointment();
      expect(activeAppointment, isNotNull);
      final appointment = activeAppointment!;
      expect(appointment.taskId, task.id);
      await firstFocusRepository.sync();

      await secondTaskRepository.sync();
      await secondFocusRepository.sync();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await firstFocusRepository.updateAppointment(
        appointmentId: appointment.id,
        taskId: firstConfigurationTask.id,
        mode: FocusChainMode.elite,
        duration: const Duration(minutes: 20),
      );
      await secondFocusRepository.updateAppointment(
        appointmentId: appointment.id,
        taskId: secondConfigurationTask.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      expect(
        (await firstFocusRepository.getAppointment(appointment.id))?.taskId,
        firstConfigurationTask.id,
        reason: '第一端必须先持久化自己的配置修改',
      );
      expect(
        (await secondFocusRepository.getAppointment(appointment.id))?.taskId,
        secondConfigurationTask.id,
        reason: '第二端必须先持久化自己的配置修改',
      );
      await secondFocusRepository.sync();
      await firstFocusRepository.sync();
      final firstDeviceSources = await firstFocusRepository
          .getAppointmentConfigurationSources(appointment.id);
      final remoteSourceRows = (await focusRemote.pull(userId: userId)).sources
          .where(
            (source) =>
                source.entityType == 'focus_appointment' &&
                source.entityId == appointment.id,
          )
          .toList();
      final mergedSourceTrace = _formatSourceTrace(
        remoteSourceRows,
        firstConfigurationTask.id,
        secondConfigurationTask.id,
      );
      expect(
        firstDeviceSources.map((source) => source.taskId),
        containsAll([firstConfigurationTask.id, secondConfigurationTask.id]),
        reason: '同步后两端的不同配置都必须保留为来源分支。\n$mergedSourceTrace',
      );
      expect(
        (await firstFocusRepository.getAppointment(appointment.id))
            ?.isPendingReview,
        isTrue,
        reason: '第一端合并两个配置分支后应标记待核对',
      );
      await secondFocusRepository.sync();
      final secondDeviceSources = await secondFocusRepository
          .getAppointmentConfigurationSources(appointment.id);
      expect(
        secondDeviceSources.map((source) => source.taskId),
        containsAll([firstConfigurationTask.id, secondConfigurationTask.id]),
        reason: '另一端重同步后也必须保留两个不同配置来源',
      );
      expect(
        (await secondFocusRepository.getAppointment(appointment.id))
            ?.isPendingReview,
        isTrue,
      );
      final synchronizedTaskTitles = (await secondTaskRepository.getGoals())
          .expand((goal) => goal.tasks)
          .map((task) => task.title)
          .toSet();
      expect(
        synchronizedTaskTitles,
        containsAll([
          firstConfigurationTask.title,
          secondConfigurationTask.title,
        ]),
      );
      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          taskRepositoryFactory: (_) => secondTaskRepository,
          focusRepositoryFactory: (_) => secondFocusRepository,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('专注链').last);
      await tester.pumpAndSettle();
      expect(find.text('已有预约准备'), findsOneWidget);
      await tester.tap(find.text('返回准备'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final firstConfigurationLabel = find.text(
        '任务：${firstConfigurationTask.title}',
      );
      final secondConfigurationLabel = find.text(
        '任务：${secondConfigurationTask.title}',
      );
      for (
        var attempt = 0;
        attempt < 50 &&
            (firstConfigurationLabel.evaluate().isEmpty ||
                secondConfigurationLabel.evaluate().isEmpty);
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('配置来源对比'), findsOneWidget);
      expect(firstConfigurationLabel, findsOneWidget);
      expect(secondConfigurationLabel, findsOneWidget);
      final chooseConfiguration = find.text('采用此来源作为配置依据');
      expect(chooseConfiguration, findsNWidgets(2));
      await tester.tap(chooseConfiguration.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('当前配置依据'), findsOneWidget);
      final selectedAppointment = await secondFocusRepository.getAppointment(
        appointment.id,
      );
      expect(selectedAppointment?.configurationBasisSourceId, isNotNull);
      final enterEarlyButton = find.text('提前进入专注');
      final logicalSize =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final swipeStart = Offset(
        logicalSize.width / 2,
        logicalSize.height * .75,
      );
      for (
        var attempt = 0;
        attempt < 8 && enterEarlyButton.hitTestable().evaluate().isEmpty;
        attempt++
      ) {
        await tester.dragFrom(swipeStart, const Offset(0, -240));
        await tester.pumpAndSettle();
      }
      expect(enterEarlyButton, findsOneWidget);
      expect(enterEarlyButton.hitTestable(), findsOneWidget);
      await tester.tap(enterEarlyButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('专注进行中'), findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);

      final continuedSession = await secondFocusRepository.getActiveSession();
      expect(continuedSession?.id, appointment.id);
      expect(continuedSession?.appointmentId, appointment.id);
      expect(continuedSession?.isPendingReview, isTrue);
      await secondFocusRepository.sync();
      await firstFocusRepository.sync();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          taskRepositoryFactory: (_) => firstTaskRepository,
          focusRepositoryFactory: (_) => firstFocusRepository,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('专注链').last);
      await tester.pumpAndSettle();
      expect(find.text('已有进行中的专注'), findsOneWidget);
      await tester.tap(find.text('返回专注'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('专注进行中'), findsOneWidget);
      expect(
        (await firstFocusRepository.getActiveSession())?.id,
        appointment.id,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await secondFocusRepository.dispose();
      await secondTaskRepository.dispose();
      await secondDatabase.close();
      await firstFocusRepository.dispose();
      await firstTaskRepository.dispose();
      await firstDatabase.close();
    }
  });

  testWidgets('T10 两端自动交接、暂停恢复、完成和重同步只结算一次', (tester) async {
    const userId = 'ticket-10-idempotency-user';
    final taskRemote = InMemoryTaskRemote();
    final focusRemote = InMemoryFocusRemote();
    final firstDatabase = PactaDatabase(NativeDatabase.memory());
    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 9, 25, 8);
    final firstTaskRepository = LocalTaskRepository(
      database: firstDatabase,
      userId: userId,
      remote: taskRemote,
      now: () => now,
    );
    final secondTaskRepository = LocalTaskRepository(
      database: secondDatabase,
      userId: userId,
      remote: taskRemote,
      now: () => now,
    );
    final firstFocusRepository = LocalFocusRepository(
      database: firstDatabase,
      userId: userId,
      remote: focusRemote,
      now: () => now,
    );
    final secondFocusRepository = LocalFocusRepository(
      database: secondDatabase,
      userId: userId,
      remote: focusRemote,
      now: () => now,
    );
    final auth = FakeAuthRepository()..signedInUser = userId;

    Future<void> openActiveSession(
      LocalTaskRepository tasks,
      LocalFocusRepository focus,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('专注链').last);
      await tester.pumpAndSettle();
      expect(find.text('已有进行中的专注'), findsOneWidget);
      await tester.tap(find.text('返回专注'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('专注进行中'), findsOneWidget);
    }

    try {
      final goal = await firstTaskRepository.createGoal(
        const GoalDraft(
          title: 'T10 自动交接目标',
          classification: TaskClassification.regular,
        ),
      );
      final task = await firstTaskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: 'T10 幂等结算任务',
          classification: TaskClassification.regular,
        ),
      );
      await firstTaskRepository.sync();
      await secondTaskRepository.sync();

      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          taskRepositoryFactory: (_) => firstTaskRepository,
          focusRepositoryFactory: (_) => firstFocusRepository,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('专注链').last);
      await tester.pumpAndSettle();
      expect(find.text(task.title), findsOneWidget);
      await tester.tap(find.text('开始').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始准备（15分钟）'));
      await tester.pumpAndSettle();

      final appointment = (await firstFocusRepository.getActiveAppointment())!;
      expect(appointment.taskId, task.id);
      await firstFocusRepository.sync();
      await secondTaskRepository.sync();
      await secondFocusRepository.sync();
      expect(
        (await secondFocusRepository.getAppointment(appointment.id))?.isActive,
        isTrue,
      );

      now = appointment.endsAt;
      await secondFocusRepository.sync();
      await firstFocusRepository.sync();
      await secondFocusRepository.sync();

      final secondSession = await secondFocusRepository.getActiveSession();
      expect(secondSession?.id, appointment.id);
      expect(secondSession?.appointmentId, appointment.id);
      expect(secondSession?.startedAt, appointment.endsAt);
      expect(
        (await secondFocusRepository.getAppointment(appointment.id))?.status,
        AppointmentPreparationStatus.succeeded,
      );
      expect(
        (await secondFocusRepository.getAppointmentChainRecord())
            .currentConsecutive,
        1,
      );

      const ruleText = 'T10 暂停与提前完成依据';
      await secondFocusRepository.createPrecedentRule(text: ruleText);
      await secondFocusRepository.sync();
      await firstFocusRepository.sync();
      await secondFocusRepository.sync();
      await openActiveSession(secondTaskRepository, secondFocusRepository);

      now = now.add(const Duration(seconds: 30));
      await tester.tap(find.text('暂停'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('选择下必为例'), findsOneWidget);
      await tester.tap(find.text(ruleText));
      await tester.pump();
      await tester.tap(find.text('确认暂停'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        (await secondFocusRepository.getSession(appointment.id))?.isPaused,
        isTrue,
      );
      expect(
        (await secondFocusRepository.getSession(appointment.id))?.pauseRuleText,
        ruleText,
      );

      await secondFocusRepository.sync();
      await firstFocusRepository.sync();
      final firstPaused = await firstFocusRepository.getSession(appointment.id);
      expect(firstPaused?.isPaused, isTrue);
      expect(firstPaused?.pauseRuleText, ruleText);

      now = now.add(const Duration(minutes: 1));
      await openActiveSession(firstTaskRepository, firstFocusRepository);
      await tester.tap(find.text('继续'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final resumed = await firstFocusRepository.getSession(appointment.id);
      expect(resumed?.isActive, isTrue);
      expect(resumed?.pausedSeconds, 60);

      await firstFocusRepository.sync();
      await secondFocusRepository.sync();
      final secondResumed = await secondFocusRepository.getSession(
        appointment.id,
      );
      expect(secondResumed?.isActive, isTrue);
      expect(secondResumed?.pausedSeconds, 60);

      now = now.add(const Duration(seconds: 30));
      await openActiveSession(secondTaskRepository, secondFocusRepository);
      await tester.tap(find.text('依据规则提前完成'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('选择下必为例'), findsOneWidget);
      await tester.tap(find.text(ruleText));
      await tester.pump();
      await tester.tap(find.text('选择依据'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('确认提前完成？'), findsOneWidget);
      await tester.tap(find.text('提前完成').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await secondFocusRepository.sync();
      await firstFocusRepository.sync();
      await secondFocusRepository.sync();

      Future<void> expectSettledOnce(LocalFocusRepository focus) async {
        final sessions = (await focus.getSessions())
            .where((session) => session.appointmentId == appointment.id)
            .toList();
        expect(sessions, hasLength(1));
        expect(sessions.single.id, appointment.id);
        expect(sessions.single.taskId, task.id);
        expect(sessions.single.mode, FocusChainMode.regular);
        expect(sessions.single.isEarlyCompleted, isTrue);
        expect(sessions.single.effectiveSeconds, 60);
        expect(sessions.single.pauseRuleText, ruleText);
        expect(sessions.single.completionRuleText, ruleText);
        expect(
          (await focus.getAppointments()).where(
            (candidate) => candidate.id == appointment.id,
          ),
          hasLength(1),
        );
        expect(
          (await focus.getAppointment(appointment.id))?.status,
          AppointmentPreparationStatus.succeeded,
        );
        expect((await focus.getAppointmentChainRecord()).currentConsecutive, 1);
        expect(await focus.getNodes(), hasLength(1));
        expect((await focus.getNodes()).single.sessionId, appointment.id);
        final modeRecords = await focus.getChainRecords();
        expect(modeRecords, hasLength(2));
        final regularRecord = modeRecords.singleWhere(
          (record) => record.mode == FocusChainMode.regular,
        );
        final eliteRecord = modeRecords.singleWhere(
          (record) => record.mode == FocusChainMode.elite,
        );
        expect(regularRecord.currentConsecutive, 1);
        expect(eliteRecord.currentConsecutive, 0);
      }

      await expectSettledOnce(firstFocusRepository);
      await expectSettledOnce(secondFocusRepository);
      final taskProgress = (await secondTaskRepository.getGoals())
          .single
          .tasks
          .single
          .focusProgressSeconds;
      expect(taskProgress, 60);

      await firstFocusRepository.sync();
      await secondFocusRepository.sync();
      await firstFocusRepository.sync();
      await expectSettledOnce(firstFocusRepository);
      await expectSettledOnce(secondFocusRepository);
      expect(
        (await firstTaskRepository.getGoals())
            .single
            .tasks
            .single
            .focusProgressSeconds,
        60,
      );
      expect(
        (await secondTaskRepository.getGoals())
            .single
            .tasks
            .single
            .focusProgressSeconds,
        60,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await secondFocusRepository.dispose();
      await secondTaskRepository.dispose();
      await secondDatabase.close();
      await firstFocusRepository.dispose();
      await firstTaskRepository.dispose();
      await firstDatabase.close();
    }
  });
}

String _formatSourceTrace(
  Iterable<FocusSyncSource> sources,
  String firstTaskId,
  String secondTaskId,
) {
  return sources
      .map((source) {
        final sourcePayload = source.payload;
        final branch = sourcePayload.contains(firstTaskId)
            ? 'A'
            : sourcePayload.contains(secondTaskId)
            ? 'B'
            : 'base';
        return '${source.sourceId}->${source.parentSourceId}:$branch';
      })
      .join(' | ');
}
