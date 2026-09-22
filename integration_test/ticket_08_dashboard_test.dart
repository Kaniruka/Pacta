import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/focus/focus_time_zones.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android 看板按时区显示一致的任务进度与近期活动', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 9, 22, 15, 50);
    final taskRepository = LocalTaskRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user-a',
      remote: InMemoryFocusRemote(),
      now: () => now,
    );

    try {
      final goal = await taskRepository.createGoal(
        const GoalDraft(title: '设备验收', classification: TaskClassification.both),
      );
      final task = await taskRepository.createTask(
        goal.id,
        const TaskDraft(
          title: '核对有效投入',
          classification: TaskClassification.both,
          estimatedMinutes: 10,
        ),
      );
      final session = await focusRepository.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(hours: 1),
      );
      now = now.add(const Duration(minutes: 30));
      await focusRepository.abandonSession(
        sessionId: session.id,
        failureReason: '验证失败会话仍计入实际投入',
      );
      await focusRepository.setDisplayTimeZonePreference('Asia/Shanghai');

      final platformTimeZone = await FlutterTimezone.getLocalTimezone();
      expect(FocusTimeZones.contains(platformTimeZone.identifier), isTrue);

      final auth = FakeAuthRepository()..signedInUser = 'user-a';
      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          taskRepositoryFactory: (_) => taskRepository,
          focusRepositoryFactory: (_) => focusRepository,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('今天先做什么'), findsOneWidget);
      expect(find.text('核对有效投入'), findsOneWidget);
      expect(find.textContaining('已专注 30分00秒'), findsOneWidget);
      expect(find.text('近期专注活动'), findsOneWidget);
      expect(find.textContaining('累计有效专注 30分00秒'), findsOneWidget);
      expect(find.textContaining('9月22日'), findsOneWidget);
      expect(find.textContaining('9月23日'), findsOneWidget);

      await tester.tap(find.byTooltip('显示时区：Asia/Shanghai'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'America/Los_Angeles',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'America/Los_Angeles',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('已专注 30分00秒'), findsOneWidget);
      expect(find.textContaining('累计有效专注 30分00秒'), findsOneWidget);
      expect(find.textContaining('9月22日'), findsOneWidget);
      expect(find.textContaining('9月23日'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    }
  });
}
