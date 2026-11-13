import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' hide FocusSession;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../test/support/fake_auth_repository.dart';

/// Real-clock reproduction probe. The host may background the Android app
/// after FOCUS_REAL_STARTED, then bring it back before the 70-second wait ends.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('看板启动真实一分钟专注同时累计次数与时长', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    const user = 'focus-real-clock-fixture';
    final tasks = LocalTaskRepository(
      database: database,
      userId: user,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: user,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: user,
      cloudSyncEnabled: false,
    );
    try {
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '真实计时验收',
          classification: TaskClassification.elite,
        ),
      );
      await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '一分钟任务',
          classification: TaskClassification.elite,
        ),
      );
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = user,
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
          nationalFocusRepositoryFactory: (_) => tree,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('看板'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('开始专注'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.ancestor(
          of: find.text('时长（分钟）'),
          matching: find.byType(TextField),
        ),
        '1',
      );
      await tester.tap(find.text('开始倒计时'));
      await tester.pumpAndSettle();
      final session = (await focus.getActiveSession())!;
      expect(session.mode, FocusChainMode.elite);
      // ignore: avoid_print
      print('FOCUS_REAL_STARTED ${DateTime.now().toIso8601String()}');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 70)),
      );
      await tester.pumpAndSettle();
      final settled = (await focus.getSession(session.id))!;
      expect(settled.status, FocusSessionStatus.completed);
      // Independent real-clock samples can lose a fractional second when
      // persisted as whole seconds; this probe must still reject zero time.
      expect(settled.effectiveSeconds, inInclusiveRange(59, 60));
      final record = (await focus.getChainRecords()).singleWhere(
        (record) => record.mode == FocusChainMode.elite,
      );
      expect(record.currentConsecutive, 1);
      await tester.tap(find.text('返回上一页'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data == '已专注 1分00秒' || widget.data == '已专注 0分59秒'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('专注链'));
      await tester.pumpAndSettle();
      expect(find.text('累计专注'), findsNWidgets(2));
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              (widget.data == '1 分钟' || widget.data == '59 秒'),
        ),
        findsWidgets,
      );
      // ignore: avoid_print
      print(
        'FOCUS_REAL_VERIFIED effectiveSeconds=${settled.effectiveSeconds} '
        'consecutive=1 boardAndChain=nonzero',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tasks.dispose();
      await focus.dispose();
      await tree.dispose();
      await database.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
