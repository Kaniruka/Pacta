import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

void main() {
  testWidgets('T10 配置分歧显示两端来源并能选择来源接续预约', (tester) async {
    final userId = 't10-source-page-user';
    final taskRemote = InMemoryTaskRemote();
    final focusRemote = InMemoryFocusRemote();
    final firstDatabase = PactaDatabase(NativeDatabase.memory());
    final secondDatabase = PactaDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 9, 23, 8);
    final secondNow = now;
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
      now: () => secondNow,
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
      now: () => secondNow,
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await secondFocusRepository.dispose();
      await secondTaskRepository.dispose();
      await secondDatabase.close();
      await firstFocusRepository.dispose();
      await firstTaskRepository.dispose();
      await firstDatabase.close();
    });

    final goal = await firstTaskRepository.createGoal(
      const GoalDraft(
        title: 'T10 配置来源目标',
        classification: TaskClassification.regular,
      ),
    );
    final originalTask = await firstTaskRepository.createTask(
      goal.id,
      const TaskDraft(
        title: 'T10 原预约任务',
        classification: TaskClassification.regular,
      ),
    );
    final firstBranchTask = await firstTaskRepository.createTask(
      goal.id,
      const TaskDraft(
        title: 'T10 第一台设备的配置',
        classification: TaskClassification.regular,
      ),
    );
    final secondBranchTask = await firstTaskRepository.createTask(
      goal.id,
      const TaskDraft(
        title: 'T10 第二台设备的配置',
        classification: TaskClassification.regular,
      ),
    );
    await firstTaskRepository.sync();
    await secondTaskRepository.sync();

    final appointment = await firstFocusRepository.startAppointment(
      taskId: originalTask.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    await firstFocusRepository.sync();
    await secondFocusRepository.sync();
    await firstFocusRepository.updateAppointment(
      appointmentId: appointment.id,
      taskId: firstBranchTask.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 20),
    );
    await secondFocusRepository.updateAppointment(
      appointmentId: appointment.id,
      taskId: secondBranchTask.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 30),
    );
    await secondFocusRepository.sync();
    await firstFocusRepository.sync();
    await secondFocusRepository.sync();

    final pending = await secondFocusRepository.getAppointment(appointment.id);
    expect(pending?.isPendingReview, isTrue);
    final sources = await secondFocusRepository
        .getAppointmentConfigurationSources(appointment.id);
    expect(
      sources.map((source) => source.taskId),
      containsAll([firstBranchTask.id, secondBranchTask.id]),
    );
    final taskTitles = (await secondTaskRepository.getGoals())
        .expand((goal) => goal.tasks)
        .map((task) => task.title)
        .toSet();
    expect(taskTitles, contains(firstBranchTask.title));
    expect(taskTitles, contains(secondBranchTask.title));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          taskRepositoryProvider.overrideWithValue(secondTaskRepository),
          focusRepositoryProvider.overrideWithValue(secondFocusRepository),
        ],
        child: MaterialApp(
          home: AppointmentPreparationPage(
            appointment: pending!,
            taskTitle: 'T10 原预约任务',
          ),
        ),
      ),
    );

    for (
      var attempt = 0;
      attempt < 50 &&
          (find.text('任务：T10 第一台设备的配置').evaluate().isEmpty ||
              find.text('任务：T10 第二台设备的配置').evaluate().isEmpty);
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('配置来源对比'), findsOneWidget);
    expect(find.text('任务：T10 第一台设备的配置'), findsOneWidget);
    expect(find.text('任务：T10 第二台设备的配置'), findsOneWidget);
    await tester.tap(find.text('采用此来源作为配置依据').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('当前配置依据'), findsOneWidget);
    final selectedAppointment = await secondFocusRepository.getAppointment(
      appointment.id,
    );
    expect(
      selectedAppointment?.configurationBasisSourceId,
      sources.first.sourceId,
    );

    final enterEarlyButton = find.text('提前进入专注');
    await tester.scrollUntilVisible(
      enterEarlyButton,
      240,
      scrollable: find.descendant(
        of: find.byType(ListView).last,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
    );
    expect(enterEarlyButton, findsOneWidget);
    await tester.tap(enterEarlyButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('专注进行中'), findsOneWidget);
    final continuedSession = await secondFocusRepository.getActiveSession();
    expect(continuedSession?.id, appointment.id);
    expect(continuedSession?.isPendingReview, isTrue);
  });
}
