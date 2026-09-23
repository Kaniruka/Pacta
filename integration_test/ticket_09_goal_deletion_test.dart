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

  testWidgets('T09 删除目标后旧预约仍可交接且不再显示新任务', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final taskRepository = LocalTaskRepository(
      database: database,
      userId: 'ticket-09-user',
      remote: InMemoryTaskRemote(),
    );
    final focusRepository = LocalFocusRepository(
      database: database,
      userId: 'ticket-09-user',
      remote: InMemoryFocusRemote(),
    );

    try {
      final goal = await taskRepository.createGoal(
        const GoalDraft(
          title: 'T09 设备验收目标',
          classification: TaskClassification.regular,
        ),
      );
      final task = await taskRepository.createTask(
        goal.id,
        const TaskDraft(title: 'T09 保留历史名称', classification: null),
      );
      final appointment = await focusRepository.startAppointment(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 20),
      );
      final auth = FakeAuthRepository()..signedInUser = 'ticket-09-user';

      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          taskRepositoryFactory: (_) => taskRepository,
          focusRepositoryFactory: (_) => focusRepository,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('删除目标'));
      await tester.pumpAndSettle();
      expect(find.text('删除目标和任务？'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(await taskRepository.getGoals(), isEmpty);
      expect(
        (await taskRepository.getGoals(includeDeleted: true))
            .single
            .tasks
            .single
            .isDeleted,
        isTrue,
      );
      await tester.tap(find.text('专注链').last);
      await tester.pumpAndSettle();
      expect(find.text('当前筛选下没有可开始的任务。'), findsOneWidget);
      expect(find.text('T09 保留历史名称（已删除）'), findsOneWidget);

      await tester.tap(find.text('提前进入专注'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('专注进行中'), findsOneWidget);
      expect(find.text('T09 保留历史名称（已删除）'), findsOneWidget);
      final active = await focusRepository.getActiveSession();
      expect(active?.taskId, task.id);
      expect(active?.appointmentId, appointment.id);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    }
  });
}
