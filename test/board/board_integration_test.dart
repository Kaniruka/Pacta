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
      const NationalFocusCardDraft(
        name: '开始工作前',
        triggerCondition: '开始工作前',
        action: '写下第一步',
      ),
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
    expect(find.textContaining('检查点'), findsNothing);
    expect(find.text('时区'), findsNothing);
    expect(find.text('日历来源'), findsNothing);
    expect(find.text('点亮 0 · 确认 1 · 熄灭 0'), findsOneWidget);
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
    expect(find.text('全部确认 (1)'), findsOneWidget);
    expect(find.byTooltip('更多'), findsOneWidget);
    expect(find.text('检查点与失败记录'), findsNothing);
    expect(find.text('整理发布材料'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('看板可按目标收起任务，并限制长目标和任务名称的行数', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final database = PactaDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var fixtureNow = DateTime.utc(2026, 10, 8, 8);
    final taskRepository = LocalTaskRepository(
      database: database,
      userId: 'user@example.com',
      remote: InMemoryTaskRemote(),
      now: () => fixtureNow,
    );
    final focusRepository = LocalFocusRepository(
      database: database,
      userId: 'user@example.com',
      remote: InMemoryFocusRemote(),
    );
    final nationalFocusRepository = LocalNationalFocusRepository(
      database: database,
      userId: 'user@example.com',
      remote: InMemoryNationalFocusRemoteDataSource(),
    );
    final longGoalTitle = List.filled(8, '用于验证长目标名称显示高度的文字').join();
    final longTaskTitle = List.filled(10, '用于验证长任务名称不会撑高看板的文字').join();
    final firstGoal = await taskRepository.createGoal(
      GoalDraft(
        title: longGoalTitle,
        classification: TaskClassification.regular,
      ),
    );
    await taskRepository.createTask(
      firstGoal.id,
      TaskDraft(
        title: longTaskTitle,
        classification: TaskClassification.regular,
      ),
    );
    fixtureNow = fixtureNow.add(const Duration(minutes: 1));
    final secondGoal = await taskRepository.createGoal(
      const GoalDraft(title: '另一个目标', classification: TaskClassification.elite),
    );
    await taskRepository.createTask(
      secondGoal.id,
      const TaskDraft(title: '另一个任务', classification: TaskClassification.elite),
    );

    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = 'user@example.com',
        taskRepositoryFactory: (_) => taskRepository,
        focusRepositoryFactory: (_) => focusRepository,
        nationalFocusRepositoryFactory: (_) => nationalFocusRepository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(longTaskTitle), findsOneWidget);
    expect(find.text('另一个任务'), findsOneWidget);
    final goalTitle = tester.widget<Text>(find.text(longGoalTitle));
    final taskTitle = tester.widget<Text>(find.text(longTaskTitle));
    expect(goalTitle.maxLines, 2);
    expect(goalTitle.overflow, TextOverflow.ellipsis);
    expect(taskTitle.maxLines, 2);
    expect(taskTitle.overflow, TextOverflow.ellipsis);

    final firstGoalCard = find.ancestor(
      of: find.text(longGoalTitle),
      matching: find.byType(Card),
    );
    final collapseButton = find.descendant(
      of: firstGoalCard,
      matching: find.byTooltip('收起任务'),
    );
    await tester.ensureVisible(collapseButton);
    await tester.tap(collapseButton);
    await tester.pumpAndSettle();

    expect(find.text(longTaskTitle), findsNothing);
    await tester.scrollUntilVisible(
      find.text('另一个任务'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('另一个任务'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(longGoalTitle),
      -100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('1 项任务'), findsWidgets);
    final collapsedCountFinder = find.descendant(
      of: firstGoalCard,
      matching: find.text('1 项任务\n进行中'),
    );
    expect(collapsedCountFinder, findsOneWidget);
    final collapsedCount = tester.widget<Text>(collapsedCountFinder);
    expect(collapsedCount.data, '1 项任务\n进行中');
    expect(collapsedCount.maxLines, 2);
    expect(
      collapsedCount.style,
      Theme.of(tester.element(collapsedCountFinder)).textTheme.bodySmall,
    );

    final expandButton = find.descendant(
      of: firstGoalCard,
      matching: find.byTooltip('展开任务'),
    );
    await tester.ensureVisible(expandButton);
    await tester.tap(expandButton);
    await tester.pumpAndSettle();
    expect(find.text(longTaskTitle), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
