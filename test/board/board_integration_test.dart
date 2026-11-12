import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' hide FocusSession;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

void main() {
  for (final activeDays in [0, 1, 7]) {
    testWidgets('支撑摘要 $activeDays 日活动在实际宽度切换后保留事实和顺序', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = PactaDatabase(NativeDatabase.memory());
      const user = 'support';
      var now = DateTime(2026, 11, 12, 10);
      final tasks = LocalTaskRepository(
        database: database,
        userId: user,
        remote: InMemoryTaskRemote(),
        now: () => now,
      );
      final remote = InMemoryFocusRemote();
      final focus = LocalFocusRepository(
        database: database,
        userId: user,
        remote: remote,
        now: () => now,
      );
      final tree = LocalNationalFocusRepository(
        database: database,
        userId: user,
        cloudSyncEnabled: false,
        now: () => now,
      );
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '今日目标',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '准备材料',
          classification: TaskClassification.regular,
        ),
      );
      for (var day = 0; day < activeDays; day++) {
        final start = DateTime(2026, 11, 12 - day, 8);
        final end = start.add(const Duration(minutes: 13));
        await remote.upsertSessions(
          userId: user,
          sessions: [
            FocusSession(
              id: 'day-$day',
              taskId: task.id,
              mode: FocusChainMode.regular,
              durationSeconds: 780,
              startedAt: start,
              endsAt: end,
              completedAt: end,
              status: FocusSessionStatus.completed,
              effectiveSeconds: 780,
              effectiveIntervals: [
                FocusTimeInterval(startedAt: start, endedAt: end),
              ],
              reviewDisposition: FocusRecordDisposition.accepted,
            ),
          ],
        );
      }
      await focus.sync();
      if (activeDays > 0) {
        final card = await tree.createCard(
          const NationalFocusCardDraft(
            name: '先写第一步',
            triggerCondition: '开始前',
            action: '写一步',
          ),
        );
        await tree.placeCard(cardId: card.id, parentId: null);
        await tree.lightCard(card.id);
        now = DateTime(2026, 11, 13, 10);
        await tree.settleDueCheckpoints();
        now = DateTime(2026, 11, 12, 10);
      }
      try {
        tester.view.physicalSize = const Size(1200, 800);
        await tester.pumpWidget(
          PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = user,
            taskRepositoryFactory: (_) => tasks,
            focusRepositoryFactory: (_) => focus,
            nationalFocusRepositoryFactory: (_) => tree,
          ),
        );
        await tester.pumpAndSettle();
        for (final width in [
          1200.0,
          1041.0,
          1040.0,
          1039.0,
          546.0,
          320.0,
          1200.0,
        ]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpAndSettle();
          debugPrint(
            'support width=$width page=${tester.getSize(find.byType(BoardPage)).width}',
          );
          final title = tester.getRect(find.text('今天先做什么'));
          final national = tester.getRect(find.text('国策状态'));
          if (tester.getSize(find.byType(BoardPage)).width >= 960) {
            expect(national.left, greaterThan(title.right));
            expect(national.top, lessThan(title.bottom));
          } else {
            expect(
              national.top,
              greaterThan(tester.getRect(find.text('准备材料')).bottom),
            );
          }
          expect(
            tester.getRect(find.text('近期专注活动')).top,
            greaterThan(national.bottom),
          );
          expect(
            find.text(activeDays == 0 ? '国策树尚无节点。' : '点亮 0 · 确认 1 · 熄灭 0'),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              activeDays == 0
                  ? '累计有效专注 0分00秒'
                  : activeDays == 1
                  ? '累计有效专注 13分00秒'
                  : '累计有效专注 91分00秒',
            ),
            findsOneWidget,
          );
          if (activeDays == 0) {
            expect(find.text('近 7 天暂无专注活动。'), findsOneWidget);
          } else {
            expect(find.text('近 7 天暂无专注活动。'), findsNothing);
            for (final date in ['11月6日 · 周五', '11月12日 · 周四']) {
              final text = find.text(date);
              expect(text, findsOneWidget);
              expect(
                tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
                isFalse,
              );
            }
            expect(find.text('13分00秒'), findsNWidgets(activeDays));
            final bars = find.descendant(
              of: find.byType(BoardPage),
              matching: find.byType(LinearProgressIndicator),
            );
            expect(bars, findsNWidgets(7));
            final firstDate = tester.getRect(find.text('11月6日 · 周五'));
            final firstBar = tester.getRect(bars.first);
            expect(firstBar.width, greaterThan(0));
            expect(firstBar.left, greaterThanOrEqualTo(0));
            expect(firstBar.right, lessThanOrEqualTo(width));
            if (width == 320 ||
                tester.getSize(find.byType(BoardPage)).width >= 960) {
              expect(firstBar.top, greaterThanOrEqualTo(firstDate.bottom));
            } else {
              expect(firstBar.left, greaterThanOrEqualTo(firstDate.right));
            }
          }
          await tester.scrollUntilVisible(
            find.text('今日日历'),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(BoardPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(find.text('今天没有导入的安排。'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'width=$width');
          await tester.scrollUntilVisible(
            find.text('今天先做什么'),
            -300,
            scrollable: find
                .descendant(
                  of: find.byType(BoardPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(find.text('打开国策树'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开国策树'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('更多'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text('看板'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('准备材料'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await focus.dispose();
        await tree.dispose();
        await database.close();
      }
    });
  }

  testWidgets('320宽长任务仍完整呈现预计、已专注、待核对和截止并可开始', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = PactaDatabase(NativeDatabase.memory());
    final now = DateTime(2026, 11, 12, 10);
    final remote = InMemoryFocusRemote();
    final tasks = LocalTaskRepository(
      database: database,
      userId: 'readable',
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: 'readable',
      remote: remote,
      now: () => now,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: 'readable',
      cloudSyncEnabled: false,
      now: () => now,
    );
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '发布前逐项核实跨团队验收与产品规划的长目标名称',
        classification: TaskClassification.both,
      ),
    );
    final task = await tasks.createTask(
      goal.id,
      TaskDraft(
        title: '整理发布清单并核对跨团队交付材料的长中文任务',
        description: '先检查版本说明、截图和所有待确认事项',
        estimatedMinutes: 120,
        deadline: DateTime(2026, 11, 15, 18, 30),
        classification: TaskClassification.both,
      ),
    );
    for (final disposition in [
      FocusRecordDisposition.accepted,
      FocusRecordDisposition.pendingReview,
    ]) {
      final start = DateTime(
        2026,
        11,
        11,
        disposition == FocusRecordDisposition.accepted ? 9 : 10,
      );
      final end = start.add(const Duration(minutes: 13));
      await remote.upsertSessions(
        userId: 'readable',
        sessions: [
          FocusSession(
            id: disposition.name,
            taskId: task.id,
            mode: FocusChainMode.regular,
            durationSeconds: 780,
            startedAt: start,
            endsAt: end,
            completedAt: end,
            status: FocusSessionStatus.completed,
            effectiveSeconds: 780,
            effectiveIntervals: [
              FocusTimeInterval(startedAt: start, endedAt: end),
            ],
            reviewDisposition: disposition,
          ),
        ],
      );
    }
    await focus.sync();
    try {
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = 'readable',
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
          nationalFocusRepositoryFactory: (_) => tree,
        ),
      );
      await tester.pumpAndSettle();
      for (final fact in [
        '120 分钟',
        '已专注 13分00秒',
        '待核对（争议部分暂不计入专注统计）',
        '截止 2026-11-15 18:30',
      ]) {
        final text = find.textContaining(fact);
        expect(text, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$fact 必须直接可读');
      }
      final play = find.byTooltip('开始专注');
      expect(tester.getSize(play).width, greaterThanOrEqualTo(40));
      expect(tester.getRect(play).right, lessThanOrEqualTo(320));
      await tester.ensureVisible(play);
      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(find.text('开始专注'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text(task.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await focus.dispose();
      await tree.dispose();
      await database.close();
    }
  });

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
    await tester.tap(find.text(longGoalTitle));
    await tester.pumpAndSettle();

    expect(find.text(longTaskTitle), findsNothing);
    expect(
      find.descendant(of: firstGoalCard, matching: find.text('添加任务')),
      findsNothing,
    );
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
      matching: find.text('1 项任务 · 进行中'),
    );
    expect(collapsedCountFinder, findsOneWidget);
    final collapsedCount = tester.widget<Text>(collapsedCountFinder);
    expect(collapsedCount.data, '1 项任务 · 进行中');
    expect(collapsedCount.maxLines, isNull);
    final theme = Theme.of(tester.element(collapsedCountFinder));
    expect(collapsedCount.style?.fontSize, theme.textTheme.bodySmall?.fontSize);
    expect(collapsedCount.style?.color, theme.colorScheme.onSurfaceVariant);

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
