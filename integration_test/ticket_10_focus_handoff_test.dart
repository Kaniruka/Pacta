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
      await tester.tap(find.text('开始').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始准备（15分钟）'));
      await tester.pumpAndSettle();

      final activeAppointment = await firstFocusRepository
          .getActiveAppointment();
      expect(activeAppointment, isNotNull);
      final appointment = activeAppointment!;
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
      await secondFocusRepository.sync();
      await firstFocusRepository.sync();
      await secondFocusRepository.sync();
      expect(
        (await secondFocusRepository.getAppointment(appointment.id))
            ?.isPendingReview,
        isTrue,
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
      expect(find.text('配置来源对比'), findsOneWidget);
      expect(find.text(firstConfigurationTask.title), findsWidgets);
      expect(find.text(secondConfigurationTask.title), findsWidgets);
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
      await tester.tap(find.text('提前进入专注').last);
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
}
