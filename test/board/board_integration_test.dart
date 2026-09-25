import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

void main() {
  testWidgets('看板先显示真实任务进度并保留任务上下文进入专注设置和国策树', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var now = DateTime.utc(2026, 9, 22, 8);
    final taskRepository = LocalTaskRepository(
      database: database,
      userId: 'user@example.com',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user@example.com',
      remote: InMemoryFocusRemote(),
      now: () => now,
    );
    final nationalFocusRepository = LocalNationalFocusRepository(
      database: database,
      userId: 'user@example.com',
      remote: InMemoryNationalFocusRemoteDataSource(),
      now: () => now,
    );
    final goal = await taskRepository.createGoal(
      const GoalDraft(title: '发布', classification: TaskClassification.both),
    );
    final task = await taskRepository.createTask(
      goal.id,
      const TaskDraft(
        title: '整理发布材料',
        classification: TaskClassification.both,
        estimatedMinutes: 10,
      ),
    );
    final session = await focusRepository.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 25),
    );
    now = now.add(const Duration(minutes: 13));
    await focusRepository.abandonSession(
      sessionId: session.id,
      failureReason: '验证看板采用实际投入时间',
    );
    final card = await nationalFocusRepository.createCard(
      const NationalFocusCardDraft(triggerCondition: '开始工作前', action: '写下第一步'),
    );
    await nationalFocusRepository.placeCard(cardId: card.id, parentId: null);
    await nationalFocusRepository.lightCard(card.id);
    now = DateTime.utc(2026, 9, 22, 20, 1);
    await nationalFocusRepository.settleDueCheckpoints();

    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
        taskRepositoryFactory: (_) => taskRepository,
        focusRepositoryFactory: (_) => focusRepository,
        nationalFocusRepositoryFactory: (_) => nationalFocusRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('整理发布材料'), findsOneWidget);
    expect(find.textContaining('已专注 13分00秒'), findsOneWidget);
    expect(find.text('国策状态'), findsOneWidget);
    expect(find.text('点亮 0 · 待今日确认 1 · 熄灭 0'), findsOneWidget);
    await tester.ensureVisible(find.text('近期专注活动'));
    expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('开始专注'));
    await tester.tap(find.byTooltip('开始专注'));
    await tester.pumpAndSettle();
    expect(find.text('开始专注'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('整理发布材料'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('打开国策树'));
    await tester.tap(find.text('打开国策树'));
    await tester.pumpAndSettle();
    expect(find.text('确认节点今日继续有效，并查看连续记录与内化进度。'), findsOneWidget);
    expect(find.text('整理发布材料'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
