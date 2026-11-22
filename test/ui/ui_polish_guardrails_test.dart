import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/board/focus_national_calendar_card.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_shared_widgets.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/notifications/focus_notification_service.dart';
import 'package:pacta/src/notifications/focus_notification_settings_page.dart';
import 'package:pacta/src/plan/plan_calendar_view.dart';
import 'package:pacta/src/profile/profile_models.dart';
import 'package:pacta/src/profile/profile_repository.dart';
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/theme/pacta_calendar_colors.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';
import 'package:pacta/src/ui/pacta_calendar_day_cell.dart';
import 'package:pacta/src/ui/pacta_grouped_list.dart';
import 'package:pacta/src/ui/pacta_page_header.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';
import '../support/plan_navigation.dart';

/// Phase 2 的 7 条机械不变量在本文件里被真实渲染锁定。
///
/// 任何一条回退都会让这里先红，而不是等真机截图才发现。每个 group 对应
/// 工单 12 的一条编号：#2 倒计时、#3 拖拽代理与零边距、#16 目标头部间隙、
/// #10 专注弹窗窄屏、#4/#5 国策树详简视图、#1/Q2 日历三层语义、
/// #11/#12/#13 设置与我的页去冗余。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // ---------------------------------------------------------------------------
  // #2 倒计时精确结算
  // ---------------------------------------------------------------------------
  group('#2 倒计时精确结算', () {
    late PactaDatabase database;
    late LocalTaskRepository tasks;
    late LocalFocusRepository focus;
    late DateTime wallTime;
    late Duration monotonic;

    setUp(() {
      wallTime = DateTime.utc(2026, 11, 18, 9);
      monotonic = Duration.zero;
      database = PactaDatabase(NativeDatabase.memory());
      tasks = LocalTaskRepository(
        database: database,
        userId: 'guard-countdown',
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
        now: () => wallTime,
      );
      focus = LocalFocusRepository(
        database: database,
        userId: 'guard-countdown',
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
        now: () => wallTime,
        monotonicNow: () => monotonic,
      );
    });

    tearDown(() async {
      await focus.dispose();
      await tasks.dispose();
      await database.close();
    });

    Future<Task> createTask(String title) async {
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '倒计时守卫',
          classification: TaskClassification.both,
        ),
      );
      return tasks.createTask(
        goal.id,
        TaskDraft(title: title, classification: TaskClassification.both),
      );
    }

    int intervalSum(FocusSession session) =>
        session.effectiveIntervals.fold<int>(
          0,
          (seconds, interval) => seconds + interval.durationSeconds,
        );

    test('墙钟到点而单调时钟少 50ms 时记满 1500 秒', () async {
      final task = await createTask('25 分钟');
      final session = await focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );

      wallTime = session.endsAt;
      monotonic = const Duration(seconds: 1499, milliseconds: 950);
      await focus.settleDueSessions();

      final completed = (await focus.getSession(session.id))!;
      expect(completed.status, FocusSessionStatus.completed);
      expect(completed.effectiveSeconds, 1500);
      expect(intervalSum(completed), 1500);
      expect(
        (await focus.getNodes()).single.effectiveSeconds,
        1500,
        reason: '专注节点与结算口径一致',
      );
      final goalTask = (await tasks.getGoals()).single.tasks.single;
      expect(goalTask.focusProgressSeconds, 1500);
      final month = await focus.getMonthMetrics(
        timeZoneId: 'Etc/UTC',
        month: DateTime.utc(2026, 11),
      );
      expect(month.activeSecondsOn(DateTime.utc(2026, 11, 18)), 1500);
    });

    test('提前完成、主动放弃与时钟异常审核都不补齐到预设时长', () async {
      // 提前完成：只记实测 600 秒。
      final earlyTask = await createTask('提前完成');
      final early = await focus.startSession(
        taskId: earlyTask.id,
        mode: FocusChainMode.elite,
        duration: const Duration(minutes: 25),
      );
      wallTime = wallTime.add(const Duration(milliseconds: 600400));
      monotonic += const Duration(milliseconds: 600400);
      final earlyDone = await focus.completeEarlySession(
        sessionId: early.id,
        ruleText: '允许提前结束并保留已完成的工作',
      );
      expect(earlyDone.effectiveSeconds, 600);
      expect(intervalSum(earlyDone), 600);

      // 主动放弃：只记实测 300 秒。
      final abandonTask = await createTask('主动放弃');
      final abandoned = await focus.startSession(
        taskId: abandonTask.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      wallTime = wallTime.add(const Duration(milliseconds: 300600));
      monotonic += const Duration(milliseconds: 300600);
      final failed = await focus.abandonSession(
        sessionId: abandoned.id,
        failureReason: '临时有事离开了',
      );
      expect(failed.effectiveSeconds, 300);
      expect(intervalSum(failed), 300);
      expect((await focus.getNodes()).length, 1, reason: '只有正常/提前完成才生成专注节点');

      // 时钟异常：待审区间不计入有效秒数，也不补齐成 25 分钟。
      final reviewTask = await createTask('时钟异常');
      final review = await focus.startSession(
        taskId: reviewTask.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      wallTime = wallTime.add(const Duration(minutes: 5));
      monotonic += const Duration(minutes: 5);
      await focus.getSession(review.id);

      wallTime = wallTime.add(const Duration(hours: 2));
      monotonic += const Duration(seconds: 1);
      final jumped = (await focus.getSession(review.id))!;
      expect(await focus.getClockReviewCases(), hasLength(1));

      final remaining = jumped.endsAt.difference(wallTime);
      final monoBefore = monotonic;
      wallTime = jumped.endsAt;
      monotonic = monoBefore + remaining;
      await focus.settleDueSessions();

      final completed = (await focus.getSession(review.id))!;
      expect(completed.status, FocusSessionStatus.completed);
      expect(
        completed.effectiveIntervals.any(
          (interval) => interval.isAwaitingClockReview,
        ),
        isTrue,
      );
      expect(
        completed.effectiveSeconds,
        lessThan(completed.durationSeconds),
        reason: '待审区间不能靠补齐变成预设的 25 分钟',
      );
      expect(intervalSum(completed), completed.durationSeconds);
    });
  });

  // ---------------------------------------------------------------------------
  // #3 拖拽代理贴合与零外边距
  // ---------------------------------------------------------------------------
  group('#3 拖拽代理与零外边距', () {
    testWidgets('PactaHoldReorderList 使用透明拖拽代理，间距由 itemSpacing 承担', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: Scaffold(
            body: PactaHoldReorderList(
              itemCount: 3,
              itemSpacing: PactaSpacing.md,
              onReorder: (_, _) {},
              itemBuilder: (context, index) => Card(
                key: ValueKey<int>(index),
                margin: EdgeInsets.zero,
                child: ListTile(title: Text('行 ${index + 1}')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final list = tester.widget<ReorderableListView>(
        find.byType(ReorderableListView),
      );
      expect(list.proxyDecorator, isNotNull, reason: '必须接管控件代理，不能沿用框架默认白底');

      final proxy = list.proxyDecorator!(
        const SizedBox.shrink(),
        0,
        const AlwaysStoppedAnimation<double>(0.5),
      );
      expect(proxy, isA<InheritedWidget>());
      final surface = (proxy as InheritedWidget).child;
      expect(surface, isA<Material>());
      expect(
        (surface as Material).type,
        MaterialType.transparency,
        reason: '代理外层必须透明，白色直角块会破坏 20dp 圆角',
      );
      expect(surface.key, const ValueKey('pacta-hold-reorder-proxy-surface'));

      for (var index = 0; index < 3; index++) {
        expect(
          tester.widget<Card>(find.byKey(ValueKey<int>(index))).margin,
          EdgeInsets.zero,
        );
      }
      final first = tester.getRect(find.byKey(const ValueKey<int>(0)));
      final second = tester.getRect(find.byKey(const ValueKey<int>(1)));
      expect(
        second.top - first.bottom,
        moreOrLessEquals(PactaSpacing.md, epsilon: 0.01),
        reason: '卡片间距由列表提供，拖拽高亮不会把间距框进边框',
      );
    });

    testWidgets('计划与看板的置顶目标卡片自身零外边距，行距由列表承担', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = PactaDatabase(NativeDatabase.memory());
      const user = 'guard-pinned';
      final now = DateTime.utc(2026, 11, 12, 10);
      final tasks = LocalTaskRepository(
        database: database,
        userId: user,
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
        now: () => now,
      );
      final focus = LocalFocusRepository(
        database: database,
        userId: user,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
        now: () => now,
      );
      final first = await tasks.createGoal(
        const GoalDraft(
          title: '置顶甲',
          classification: TaskClassification.regular,
        ),
      );
      final second = await tasks.createGoal(
        const GoalDraft(
          title: '置顶乙',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.setGoalPinned(first.id, isPinned: true);
      await tasks.setGoalPinned(second.id, isPinned: true);
      try {
        await tester.pumpWidget(
          PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = user,
            taskRepositoryFactory: (_) => tasks,
            focusRepositoryFactory: (_) => focus,
            displayClock: () => now,
          ),
        );
        await tester.pumpAndSettle();

        await openPlan(tester);
        final goalCards = find.byType(GoalCard);
        expect(goalCards, findsNWidgets(2));
        for (var index = 0; index < 2; index++) {
          final cards = tester.widgetList<Card>(
            find.descendant(
              of: goalCards.at(index),
              matching: find.byType(Card),
            ),
          );
          expect(cards, isNotEmpty);
          for (final card in cards) {
            expect(
              card.margin,
              EdgeInsets.zero,
              reason: 'GoalCard 边距交给 PactaHoldReorderList(itemSpacing: 12)',
            );
          }
        }
        expect(
          tester.getRect(goalCards.at(1)).top -
              tester.getRect(goalCards.at(0)).bottom,
          greaterThanOrEqualTo(PactaSpacing.md - 0.01),
          reason: '置顶目标之间保留 12dp 行距',
        );

        await openBoard(tester);
        final pinnedFirst = find.byKey(
          ValueKey('board-pinned-goal-${first.id}'),
        );
        final pinnedSecond = find.byKey(
          ValueKey('board-pinned-goal-${second.id}'),
        );
        await tester.ensureVisible(pinnedSecond);
        await tester.pumpAndSettle();
        for (final finder in [pinnedFirst, pinnedSecond]) {
          expect(finder, findsOneWidget);
          expect(tester.widget<Card>(finder).margin, EdgeInsets.zero);
        }
        expect(
          tester.getRect(pinnedSecond).top - tester.getRect(pinnedFirst).bottom,
          greaterThanOrEqualTo(PactaSpacing.sm - 0.01),
          reason: '看板置顶目标之间保留 8dp 行距',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await focus.dispose();
        await tasks.dispose();
        await database.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // #16 目标头部到首任务间隙恒定
  // ---------------------------------------------------------------------------
  group('#16 目标头部到首任务间隙恒定', () {
    testWidgets('单行无描述目标与带描述目标的头部末行到首条任务顶距相同', (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      const user = 'guard-header-gap';
      final now = DateTime.utc(2026, 11, 12, 10);
      final tasks = LocalTaskRepository(
        database: database,
        userId: user,
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
        now: () => now,
      );
      final plain = await tasks.createGoal(
        const GoalDraft(
          title: '无描述目标',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.createTask(
        plain.id,
        const TaskDraft(
          title: '首条任务甲',
          classification: TaskClassification.regular,
        ),
      );
      final described = await tasks.createGoal(
        const GoalDraft(
          title: '带描述目标',
          description: '这一段描述会多占一行，不能改变头部到首条任务的距离。',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.createTask(
        described.id,
        const TaskDraft(
          title: '首条任务乙',
          classification: TaskClassification.regular,
        ),
      );
      final goals = await tasks.getGoals();
      final plainGoal = goals.firstWhere((goal) => goal.id == plain.id);
      final describedGoal = goals.firstWhere((goal) => goal.id == described.id);
      expect(plainGoal.description, isEmpty);
      expect(describedGoal.description, isNotEmpty);

      try {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: pactaTheme(Brightness.light),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(PactaSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final goal in [plainGoal, describedGoal])
                        GoalCard(
                          key: ValueKey(goal.id),
                          repository: tasks,
                          goal: goal,
                          focusProgressSecondsByTask: null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        double gapFor(String goalTitle) {
          final card = find.ancestor(
            of: find.text(goalTitle),
            matching: find.byType(GoalCard),
          );
          expect(card, findsOneWidget);
          final summary = find.descendant(
            of: card,
            matching: find.text('1 项任务 · 进行中'),
          );
          expect(summary, findsOneWidget);
          final taskRow = find
              .descendant(of: card, matching: find.byType(ListTile))
              .first;
          return tester.getRect(taskRow).top - tester.getRect(summary).bottom;
        }

        final plainGap = gapFor('无描述目标');
        final describedGap = gapFor('带描述目标');
        expect(plainGap, greaterThanOrEqualTo(PactaSpacing.sm));
        expect(
          (plainGap - describedGap).abs(),
          lessThanOrEqualTo(1.0),
          reason: '有无描述时头部文字底到首条任务顶距差值 <= 1dp',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tasks.dispose();
        await database.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // #10 开始专注弹窗 360dp 窄屏
  // ---------------------------------------------------------------------------
  group('#10 开始专注弹窗窄屏布局', () {
    testWidgets('360x800 下输入框在上、5/10/15 三个档位严格同排', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = PactaDatabase(NativeDatabase.memory());
      const user = 'guard-setup-dialog';
      final now = DateTime.utc(2026, 11, 12, 10);
      final tasks = LocalTaskRepository(
        database: database,
        userId: user,
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
        now: () => now,
      );
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '弹窗守卫',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '写一段足够长的任务名称以覆盖折行风险',
          classification: TaskClassification.regular,
        ),
      );
      try {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: pactaTheme(Brightness.light),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => showDialog<Object>(
                        context: context,
                        builder: (_) => FocusSetupDialog(
                          task: task,
                          initialMode: FocusChainMode.regular,
                        ),
                      ),
                      child: const Text('打开'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();

        final preparationField = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == '预约准备时长（分钟）',
        );
        expect(preparationField, findsOneWidget);
        final fieldRect = tester.getRect(preparationField);

        final chips = find.byType(ChoiceChip);
        expect(chips, findsNWidgets(3));
        final chipTops = [
          for (var index = 0; index < 3; index++)
            tester.getRect(chips.at(index)).top,
        ];
        final highest = chipTops.reduce(
          (left, right) => left < right ? left : right,
        );
        final lowest = chipTops.reduce(
          (left, right) => left > right ? left : right,
        );
        expect(
          lowest - highest,
          lessThanOrEqualTo(1.0),
          reason: '5/10/15 三个档位顶边必须在同一行',
        );
        expect(
          fieldRect.bottom,
          lessThanOrEqualTo(highest),
          reason: '输入框在上，档位在其下方',
        );
        for (final label in ['5 分钟', '10 分钟', '15 分钟']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tasks.dispose();
        await database.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // #4 / #5 国策树详简卡片差异与两行规则
  // ---------------------------------------------------------------------------
  group('#4/#5 国策树详简视图', () {
    final createdAt = DateTime.utc(2026, 11, 20, 9);

    NationalFocusCard card(
      String id,
      String name, {
      required NationalFocusCardState state,
      int currentConsecutiveDays = 0,
      int bestConsecutiveDays = 0,
    }) => NationalFocusCard(
      id: id,
      name: name,
      triggerCondition: '触发条件',
      action: '坐到书桌前先写下今天的第一步，再核对昨天的落实情况。',
      isInTree: true,
      state: state,
      createdAt: createdAt,
      updatedAt: createdAt,
      currentConsecutiveDays: currentConsecutiveDays,
      bestConsecutiveDays: bestConsecutiveDays,
    );

    Future<void> pumpTree(
      WidgetTester tester,
      NationalFocusRepository repository, {
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(brightness),
          home: Scaffold(body: NationalFocusTreePage(repository: repository)),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }

    Future<void> switchToDetailed(WidgetTester tester) async {
      final entry = find.text('简洁视图');
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(find.text('详细视图').last);
      await tester.pumpAndSettle();
    }

    testWidgets('简洁视图没有 Card，详细视图按状态着色、无状态条与胶囊且规则最多三行', (tester) async {
      final lit = card('lit', '点亮卡', state: NationalFocusCardState.lit);
      final pending = card(
        'pending',
        '待确认卡',
        state: NationalFocusCardState.pendingTodayConfirmation,
      );
      final out = card(
        'out',
        '熄灭卡',
        state: NationalFocusCardState.extinguished,
      );
      final repository = _FocusTreeFixtureRepository([lit, pending, out]);
      addTearDown(repository.dispose);
      try {
        await pumpTree(tester, repository);

        final node = find.byKey(const ValueKey('national-focus-node-lit'));
        expect(node, findsOneWidget);
        expect(
          find.descendant(of: node, matching: find.byType(Card)),
          findsNothing,
          reason: '简洁视图严格只留圆形状态图标 + 名称',
        );
        expect(
          find.descendant(of: node, matching: find.text(lit.effectiveAction)),
          findsNothing,
        );

        for (final brightness in Brightness.values) {
          await pumpTree(tester, repository, brightness: brightness);
          await switchToDetailed(tester);
          final colors = Theme.of(
            tester.element(find.byKey(const ValueKey('national-focus-canvas'))),
          ).colorScheme;
          final canvas = colors.surfaceContainerLow;
          for (final entry in [lit, pending, out]) {
            final cardFinder = find.byKey(
              ValueKey('national-focus-card-${entry.id}'),
            );
            expect(cardFinder, findsOneWidget, reason: entry.name);
            final cardWidget = tester.widget<Card>(cardFinder);
            expect(
              cardWidget.color,
              isNot(canvas),
              reason: '${entry.name} 的卡片底色必须与画布 surfaceContainerLow 分层',
            );
            // 详细卡片是等宽四周边框的 M3 状态卡：状态只由填色、边框色与
            // 左侧图标井表达，没有顶部 3dp 色条，也没有右上角文字胶囊。
            final shape = cardWidget.shape! as RoundedRectangleBorder;
            expect(
              shape.side.width,
              greaterThanOrEqualTo(1),
              reason: '${entry.name} 详细卡片四周必须有等宽描边',
            );
            expect(
              shape.side.color.a,
              greaterThan(0),
              reason: '${entry.name} 的边框色必须真的画出来',
            );
            final radius = shape.borderRadius as BorderRadius;
            expect(
              radius.topLeft,
              radius.topRight,
              reason: '${entry.name} 四角同半径',
            );
            expect(
              radius.topLeft,
              radius.bottomLeft,
              reason: '${entry.name} 四角同半径',
            );
            expect(
              radius.topLeft,
              radius.bottomRight,
              reason: '${entry.name} 四角同半径',
            );
            expect(
              _topStatusStripBands(tester, cardFinder),
              isEmpty,
              reason: '${entry.name} 不再有贴顶的整宽 3dp 状态色条',
            );
            expect(
              find.descendant(
                of: cardFinder,
                matching: find.byType(ColoredBox),
              ),
              findsNothing,
              reason: '${entry.name} 的卡内没有任何纯色块承担状态条',
            );
            expect(
              find.descendant(
                of: cardFinder,
                matching: find.text(entry.state.label),
              ),
              findsNothing,
              reason: '${entry.name} 不再显示右上角状态文字胶囊',
            );
            // 顶层节点不再渲染「根」胶囊：根只靠 2dp 外框与 Semantics 区分。
            expect(
              find.descendant(of: cardFinder, matching: find.text('根')),
              findsNothing,
              reason: '${entry.name} 不再渲染 根 胶囊',
            );
            final semantics = tester.widget<Semantics>(
              find.ancestor(
                of: cardFinder,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Semantics &&
                      (widget.properties.label?.contains('节点 ') ?? false),
                ),
              ),
            );
            expect(
              semantics.properties.label,
              contains(entry.state.label),
              reason: '${entry.name} 去掉文字胶囊后，状态语义仍要读得出来',
            );
            // 0/0 连击整行不渲染：既没有连击胶囊，也不留「连续 0 天」噪声。
            expect(
              find.descendant(
                of: cardFinder,
                matching: find.byType(NationalFocusStreakTags),
              ),
              findsNothing,
              reason: '${entry.name} 没有连续记录时不渲染连击胶囊',
            );
            expect(
              find.descendant(of: cardFinder, matching: find.text('连续 0 天')),
              findsNothing,
              reason: '${entry.name} 不显示 0 天连击噪声',
            );
            final rule = tester.widget<Text>(
              find.descendant(
                of: cardFinder,
                matching: find.text(entry.effectiveAction),
              ),
            );
            expect(rule.maxLines, 3, reason: '${entry.name} 规则最多三行');
          }
          final rules = tester.widgetList<Text>(
            find.descendant(
              of: find.byType(NationalFocusTreePage),
              matching: find.text(lit.effectiveAction),
            ),
          );
          expect(rules, isNotEmpty);
          for (final text in rules) {
            expect(text.maxLines, isNot(1), reason: '国策规则不再被压回一行');
            expect(text.maxLines, isNot(2), reason: '规则摘要不再被压回两行');
            expect(text.maxLines, 3, reason: '详细视图规则摘要最多三行');
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await repository.dispose();
      }
    });

    testWidgets('非零连击的详细卡片在标题下方、规则上方渲染连击胶囊', (tester) async {
      final streak = card(
        'streak',
        '连击卡',
        state: NationalFocusCardState.lit,
        currentConsecutiveDays: 3,
        bestConsecutiveDays: 5,
      );
      final repository = _FocusTreeFixtureRepository([streak]);
      try {
        await pumpTree(tester, repository);
        await switchToDetailed(tester);

        final cardFinder = find.byKey(
          const ValueKey('national-focus-card-streak'),
        );
        expect(cardFinder, findsOneWidget);
        final tags = find.descendant(
          of: cardFinder,
          matching: find.byType(NationalFocusStreakTags),
        );
        expect(tags, findsOneWidget, reason: '有连续记录时详情同款连击胶囊必须出现');
        final tagsWidget = tester.widget<NationalFocusStreakTags>(tags);
        expect(tagsWidget.currentConsecutiveDays, 3);
        expect(tagsWidget.bestConsecutiveDays, 5);

        final titleRect = tester.getRect(
          find.descendant(of: cardFinder, matching: find.text('连击卡')),
        );
        final tagsRect = tester.getRect(tags);
        final iconRect = tester.getRect(
          find.descendant(
            of: cardFinder,
            matching: find.byIcon(Icons.lightbulb),
          ),
        );
        expect(
          tagsRect.left,
          greaterThan(iconRect.right),
          reason: '连击胶囊在图标井右侧的标题列内，而不是图标下方的整卡宽行',
        );
        expect(
          tagsRect.left,
          greaterThanOrEqualTo(titleRect.left - 0.01),
          reason: '连击胶囊与名称共用右列左缘',
        );
        expect(
          find.descendant(of: cardFinder, matching: find.text('根')),
          findsNothing,
          reason: '顶层节点不再渲染 根 胶囊',
        );
        final ruleRect = tester.getRect(
          find.descendant(
            of: cardFinder,
            matching: find.text(streak.effectiveAction),
          ),
        );
        expect(
          tagsRect.top,
          greaterThanOrEqualTo(titleRect.bottom),
          reason: '连击胶囊位于名称下方',
        );
        expect(
          tagsRect.bottom,
          lessThanOrEqualTo(ruleRect.top),
          reason: '连击胶囊位于规则摘要上方',
        );
        expect(
          find.descendant(of: cardFinder, matching: find.text('连续 0 天')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await repository.dispose();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // #1 / Q2 日历三层独立语义
  // ---------------------------------------------------------------------------
  group('#1/Q2 日历三层独立语义', () {
    testWidgets('今天且选中只有一层 2dp 主蓝描边，业务底色不被覆写', (tester) async {
      final colors = PactaCalendarColors.light;
      final backgrounds = <Color>[
        colors.hasPlansBackground,
        colors.allCompleteBackground,
        colors.holidayBackground,
        colors.heat2Background,
      ];
      // 三种状态各自成立：只选中、只今天、今天且选中。
      const states = [(true, false), (false, true), (true, true)];
      for (final background in backgrounds) {
        for (final (selected, today) in states) {
          await tester.pumpWidget(
            MaterialApp(
              theme: pactaTheme(Brightness.light),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 64,
                    child: PactaCalendarDayBox(
                      cellKey: const ValueKey('primitive-cell'),
                      dayNumber: '15',
                      selected: selected,
                      today: today,
                      backgroundColor: background,
                      foregroundColor: colors.heat2Foreground,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final scope = find.byKey(const ValueKey('primitive-cell'));
          final ink = tester.widget<Ink>(
            find.descendant(of: scope, matching: find.byType(Ink)).first,
          );
          final decoration = ink.decoration! as BoxDecoration;
          expect(
            decoration.color,
            background,
            reason: '选中与今天都不覆写业务底色（selected=$selected today=$today）',
          );
          expect(decoration.color, isNot(colors.selectedBackground));
          final border = decoration.border as Border?;
          if (selected) {
            expect(border!.top.width, 2);
            expect(border.top.color, colors.selectedBorder);
          } else {
            expect(border!.top.width, 1.5);
            expect(border.top.color, colors.todayBorder);
          }
          expect(
            _borderLayers(tester, scope),
            1,
            reason: '只允许一层等大外框（selected=$selected today=$today）',
          );
          expect(
            find.descendant(of: scope, matching: find.text('今')),
            today ? findsOneWidget : findsNothing,
            reason: '今天用独立角标表达，与描边解耦',
          );
        }
      }
      // 无业务底色时也不允许出现第二层内框。
      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 64,
                child: PactaCalendarDayBox(
                  cellKey: ValueKey('plain-cell'),
                  dayNumber: '15',
                  selected: true,
                  today: true,
                  foregroundColor: Color(0xff1f1f1f),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        _borderLayers(tester, find.byKey(const ValueKey('plain-cell'))),
        1,
        reason: '今天且选中仍然只有一层外框',
      );
      expect(
        _hasKeyContaining(tester, 'plan-day-selected-ring'),
        isFalse,
        reason: '双层 plan-day-selected-ring 框必须彻底消失',
      );
    });

    testWidgets('计划日历、看板热力月历与融合卡片今天格都是单层描边加独立今角标', (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = PactaDatabase(NativeDatabase.memory());
      const user = 'guard-calendar';
      var wallTime = DateTime.utc(2026, 11, 15, 2);
      final tasks = LocalTaskRepository(
        database: database,
        userId: user,
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
        now: () => wallTime,
      );
      final focus = LocalFocusRepository(
        database: database,
        userId: user,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
        now: () => wallTime,
      );
      final schedules = LocalScheduleRepository(
        database: database,
        userId: user,
        now: () => wallTime,
      );
      final nationalFocus = LocalNationalFocusRepository(
        database: database,
        userId: user,
        remote: InMemoryNationalFocusRemoteDataSource(),
        cloudSyncEnabled: false,
        now: () => wallTime,
      );
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '日历守卫',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '写 13 分钟',
          classification: TaskClassification.regular,
        ),
      );
      final session = await focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 13),
      );
      wallTime = session.endsAt;
      await focus.settleDueSessions();
      final today = wallTime;
      await schedules.createSchedule(
        ScheduleDraft(
          title: '今日安排',
          window: ScheduleWindow.timed(
            startsAt: DateTime.utc(2026, 11, 15, 3),
            endsAt: DateTime.utc(2026, 11, 15, 4),
          ),
        ),
      );
      final colors = PactaCalendarColors.light;
      try {
        // 计划日历：今天默认选中，有安排则保留柔和黄底。
        await tester.pumpWidget(
          MaterialApp(
            theme: pactaTheme(Brightness.light),
            home: Scaffold(
              body: PlanCalendarView(
                repository: schedules,
                goals: await tasks.getGoals(includeDeleted: true),
                displayTimeZoneId: 'Asia/Shanghai',
                now: () => today,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final planCell = find.byKey(const ValueKey('plan-day-2026-11-15'));
        expect(planCell, findsOneWidget);
        final planDecoration =
            tester
                    .widget<Ink>(
                      find
                          .descendant(of: planCell, matching: find.byType(Ink))
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        expect(
          planDecoration.color,
          colors.hasPlansBackground,
          reason: '有安排的底色不被选中蓝覆写',
        );
        expect((planDecoration.border! as Border).top.width, 2);
        expect(_borderLayers(tester, planCell), 1);
        expect(
          find.descendant(of: planCell, matching: find.text('今')),
          findsOneWidget,
        );
        expect(_todayLabelBackdrops(tester), 0, reason: '计划日历的今字不得被填充胶囊包住');

        // 融合卡片：同一格同样是单层描边 + 今角标 + 热力底色。
        await tester.pumpWidget(
          MaterialApp(
            theme: pactaTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: FocusNationalCalendarCard(
                  focusRepository: focus,
                  nationalFocusRepository: nationalFocus,
                  displayTimeZoneId: 'Asia/Shanghai',
                  now: () => today,
                  onOpenNationalFocus: () {},
                  onRetryProjection: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boardCell = find.byKey(const ValueKey('board-focus-day-15'));
        expect(boardCell, findsOneWidget);
        final boardDecoration =
            tester
                    .widget<Ink>(
                      find
                          .descendant(of: boardCell, matching: find.byType(Ink))
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        expect(boardDecoration.color, colors.heat1Background);
        expect((boardDecoration.border! as Border).top.width, 2);
        expect(_borderLayers(tester, boardCell), 1);
        expect(
          find.descendant(of: boardCell, matching: find.text('今')),
          findsOneWidget,
        );
        expect(_todayLabelBackdrops(tester), 0, reason: '融合看板的今字不得被填充胶囊包住');
        expect(_hasKeyContaining(tester, 'plan-day-selected-ring'), isFalse);

        // 历史日期没有失败记录时必须显示未知，不推断为已完成。
        await tester.tap(find.byKey(const ValueKey('board-focus-day-9')));
        await tester.pumpAndSettle();
        expect(find.text('11 月 9 日'), findsOneWidget);
        expect(find.text('未知'), findsOneWidget);
        expect(find.text('全点亮'), findsNothing);
        expect(find.text('有失败记录'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await nationalFocus.dispose();
        await schedules.dispose();
        await focus.dispose();
        await tasks.dispose();
        await database.close();
      }
    });

    // 320dp × textScaler 2.0：'今' 角标必须自己收紧并二次缩放，绝不把右上角
    // 标记挤出 32.3dp 窄格（基线截图 plan-calendar-schedule-unchecked 曾报
    // RenderFlex overflowed by 3.2 pixels on the right）。
    testWidgets('320dp 与 2.0 字号下今字与右上角标记同排零溢出且不重叠', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final colors = PactaCalendarColors.light;
      // 现行调用方已把状态标记收进底部指示轨（5dp 圆点 / 8dp 完成勾）；
      // 这里对已弃用的右上角槽按 10dp 上限压测，旧调用方与极端标记也不得
      // 把「今」挤出窄格。
      final markers = <(String, Widget)>[
        (
          'dot',
          ExcludeSemantics(
            child: Container(
              key: const ValueKey('guard-marker-dot'),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.heat2Foreground,
              ),
            ),
          ),
        ),
        (
          'check',
          ExcludeSemantics(
            child: Icon(
              Icons.check,
              key: const ValueKey('guard-marker-check'),
              size: 10,
              color: colors.heat2Foreground,
            ),
          ),
        ),
      ];

      Future<void> pumpCell({
        required double width,
        required bool today,
        required Widget? marker,
        required double textScale,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: pactaTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: PactaCalendarDayBox(
                    cellKey: const ValueKey('guard-cell'),
                    dayNumber: '15',
                    today: today,
                    foregroundColor: colors.heat2Foreground,
                    topRightMarker: marker,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      // 32.3dp 是实机日志里的真实约束，38dp 是紧凑七列的量级。
      for (final width in <double>[32.3, 38]) {
        for (final (name, marker) in markers) {
          await pumpCell(
            width: width,
            today: true,
            marker: marker,
            textScale: 2.0,
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '${width}dp 宽 + $name 标记在 2.0 字号下不允许溢出',
          );
          final cell = tester.getRect(find.byKey(const ValueKey('guard-cell')));
          final label = _todayBadgeRect(tester);
          final topBar = tester.getRect(
            find
                .descendant(
                  of: find.byKey(const ValueKey('guard-cell')),
                  matching: find.byType(Row),
                )
                .first,
          );
          final markerRect = tester.getRect(
            find.byKey(ValueKey('guard-marker-$name')),
          );
          for (final rect in <Rect>[label, markerRect]) {
            expect(
              rect.left,
              greaterThanOrEqualTo(cell.left - 0.01),
              reason: '$name：不得越过格子左边界',
            );
            expect(
              rect.right,
              lessThanOrEqualTo(cell.right + 0.01),
              reason: '$name：不得越过格子右边界（右溢回归）',
            );
            expect(rect.top, greaterThanOrEqualTo(cell.top - 0.01));
            expect(rect.bottom, lessThanOrEqualTo(cell.bottom + 0.01));
          }
          expect(
            label.height,
            lessThanOrEqualTo(12.01),
            reason: '$name：今字仍须收在 12dp 顶栏内',
          );
          expect(
            topBar.contains(label.center),
            isTrue,
            reason: '$name：今字完整落在顶栏里，不放大的同时也不被裁切',
          );
          expect(
            _todayLabelBackdrops(tester),
            0,
            reason: '$name：今字不再有胶囊底衬，量到的就是字形本身',
          );
          expect(
            label.overlaps(markerRect),
            isFalse,
            reason: '$name：今字与右上角标记不得重叠',
          );
          expect(
            label.right,
            lessThanOrEqualTo(markerRect.left + 0.01),
            reason: '$name：今字必须整体位于标记左侧',
          );
        }

        // 只有今字、没有标记：整格宽度都归它，同样不得溢出。
        await pumpCell(width: width, today: true, marker: null, textScale: 2.0);
        expect(tester.takeException(), isNull);
        final bareCell = tester.getRect(
          find.byKey(const ValueKey('guard-cell')),
        );
        final bareBadge = _todayBadgeRect(tester);
        expect(bareBadge.left, greaterThanOrEqualTo(bareCell.left - 0.01));
        expect(bareBadge.right, lessThanOrEqualTo(bareCell.right + 0.01));
      }

      // 1.0 字号下四种组合的视觉位置完全不变：今字贴左内边距，标记贴右。
      for (final today in <bool>[true, false]) {
        for (final (name, marker) in <(String, Widget?)>[
          ...markers,
          ('none', null),
        ]) {
          await pumpCell(
            width: 38,
            today: today,
            marker: marker,
            textScale: 1.0,
          );
          expect(tester.takeException(), isNull);
          // 1.5dp 描边由 Ink 折成内边距，故以顶栏 Row 本体为基准比较位置。
          final row = tester.getRect(
            find
                .descendant(
                  of: find.byKey(const ValueKey('guard-cell')),
                  matching: find.byType(Row),
                )
                .first,
          );
          if (today) {
            expect(
              _todayBadgeRect(tester).left,
              closeTo(row.left, 0.01),
              reason: 'today=$today/$name：今字仍贴顶栏左端',
            );
          } else {
            expect(find.text('今'), findsNothing);
          }
          if (marker == null) {
            expect(find.byKey(ValueKey('guard-marker-$name')), findsNothing);
          } else {
            expect(
              tester.getRect(find.byKey(ValueKey('guard-marker-$name'))).right,
              closeTo(row.right, 0.01),
              reason: 'today=$today/$name：右上角标记仍贴顶栏右端',
            );
          }
        }
      }
    });

    // 七列紧凑网格行（每列 38dp）在 320dp + 2.0 字号下的整行场景。
    testWidgets('320dp 七列 38dp 紧凑网格行在 2.0 字号下零溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final colors = PactaCalendarColors.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: KeyedSubtree(
                key: const ValueKey('guard-grid-row'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var day = 1; day <= 7; day++)
                      SizedBox(
                        width: 38,
                        child: PactaCalendarDayBox(
                          cellKey: ValueKey('guard-grid-day-$day'),
                          dayNumber: '$day',
                          today: day == 4,
                          foregroundColor: colors.heat2Foreground,
                          topRightMarker: day == 4
                              ? ExcludeSemantics(
                                  child: Container(
                                    key: const ValueKey('guard-grid-marker'),
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: colors.heat2Foreground,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '七列密集行在 2.0 字号下不得溢出');
      final row = tester.getRect(find.byKey(const ValueKey('guard-grid-row')));
      expect(row.width, closeTo(7 * 38, 0.01));
      Rect? previous;
      for (var day = 1; day <= 7; day++) {
        final rect = tester.getRect(
          find.byKey(ValueKey('guard-grid-day-$day')),
        );
        expect(rect.width, closeTo(38, 0.01));
        expect(rect.left, greaterThanOrEqualTo(row.left - 0.01));
        expect(rect.right, lessThanOrEqualTo(row.right + 0.01));
        if (previous != null) {
          expect(rect.left, closeTo(previous.right, 0.01), reason: '格子之间不重叠');
        }
        previous = rect;
      }
      final todayCell = tester.getRect(
        find.byKey(const ValueKey('guard-grid-day-4')),
      );
      final label = _todayBadgeRect(tester);
      final marker = tester.getRect(
        find.byKey(const ValueKey('guard-grid-marker')),
      );
      for (final rect in <Rect>[label, marker]) {
        expect(rect.left, greaterThanOrEqualTo(todayCell.left - 0.01));
        expect(rect.right, lessThanOrEqualTo(todayCell.right + 0.01));
      }
      final topBar = tester.getRect(
        find
            .descendant(
              of: find.byKey(const ValueKey('guard-grid-day-4')),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(topBar.contains(label.center), isTrue);
      expect(_todayLabelBackdrops(tester), 0);
      expect(label.overlaps(marker), isFalse, reason: '今字与圆点不得重叠');
      expect(label.right, lessThanOrEqualTo(marker.left + 0.01));
    });
  });

  // ---------------------------------------------------------------------------
  // #11 / #12 / #13 设置与我的页去冗余
  // ---------------------------------------------------------------------------
  group('#11/#12/#13 设置与我的页去冗余', () {
    testWidgets('通知与设备权限页不再内嵌跳转按钮，全部使用分组列表', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: FocusNotificationSettingsPage(
            service: DisabledFocusNotificationService(),
            isAndroid: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PactaSectionHeader), findsNWidgets(3));
      expect(find.byType(PactaGroupedList), findsNWidgets(3));
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.byType(TextButton),
        ),
        findsNothing,
        reason: '整行可点后，ListTile 副标题里不得再塞跳转按钮',
      );
      for (final section in ['后台运行与系统权限', '后台倒计时与专注通知', '定时提醒']) {
        expect(find.text(section), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('我的与看板不再出现 MiSans 声明、专注记录核对与仅本机生效', (tester) async {
      final removed = ['本应用使用 MiSans 字体', '专注记录核对', '仅本机生效'];
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = 'guard-my',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BoardPage), findsOneWidget);
      // '看板' 同时出现在底部 NavigationBar 与顶部 PactaPageHeader：页头必须精确匹配。
      expect(
        find.descendant(
          of: find.byType(PactaPageHeader),
          matching: find.text('看板'),
        ),
        findsOneWidget,
      );
      for (final text in removed) {
        expect(
          find.textContaining(text),
          findsNothing,
          reason: '看板不再出现已移除声明：$text',
        );
      }

      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('我的'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MyPage), findsOneWidget);
      for (final text in removed) {
        expect(
          find.textContaining(text),
          findsNothing,
          reason: '我的页不再出现已移除声明：$text',
        );
      }
      expect(find.text('通知与设备权限'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 3：看板 360dp 七列零裁切、置顶优先级与去重复
  // ---------------------------------------------------------------------------
  group('Phase 3 看板 360dp 七列与去重复', () {
    NationalFocusCard boardCard(
      String id,
      String name,
      NationalFocusCardState state,
    ) => NationalFocusCard(
      id: id,
      name: name,
      triggerCondition: '打开待办清单',
      action: '坐到书桌前先写下今天的第一步。',
      isInTree: true,
      state: state,
      createdAt: DateTime.utc(2026, 11, 18, 1),
      updatedAt: DateTime.utc(2026, 11, 18, 1),
      currentConsecutiveDays: 0,
      bestConsecutiveDays: 0,
    );

    List<NationalFocusCard> treeCards() => [
      boardCard('board-lit', '根国策', NationalFocusCardState.lit),
      boardCard(
        'board-pending',
        '开始前写第一步',
        NationalFocusCardState.pendingTodayConfirmation,
      ),
      boardCard('board-out', '清理桌面', NationalFocusCardState.extinguished),
    ];

    testWidgets('360x800 下七列零裁切、无置顶区块、唯一月份与安排内联', (tester) async {
      _useView(tester, const Size(360, 800));
      final fixture = await _BoardPhase3Fixture.create(cards: treeCards());
      try {
        await tester.pumpWidget(fixture.app());
        await tester.pumpAndSettle();

        final cardFinder = find.byKey(
          const ValueKey('board-focus-national-card'),
        );
        expect(cardFinder, findsOneWidget);
        final cardRect = tester.getRect(cardFinder);
        final headerRect = tester.getRect(find.byType(PactaPageHeader));

        // 卡片左右矩形边界完整在 360 视口内。
        expect(cardRect.left, greaterThanOrEqualTo(0));
        expect(cardRect.right, lessThanOrEqualTo(360));
        expect(cardRect.width, greaterThan(300));

        // 无置顶目标：整块「置顶目标」与空置顶文案都不渲染，融合卡紧贴页头。
        expect(find.text('置顶目标'), findsNothing);
        expect(find.text('还没有置顶目标'), findsNothing);
        expect(cardRect.top, greaterThanOrEqualTo(headerRect.bottom - 0.01));
        expect(
          cardRect.top - headerRect.bottom,
          lessThanOrEqualTo(24),
          reason: '无置顶目标时融合卡直接位于 PactaPageHeader 下方',
        );

        // 星期表头「一..日」7 个文字矩形都在卡片左右边界内。
        for (final label in ['一', '二', '三', '四', '五', '六', '日']) {
          final rect = tester.getRect(
            find.descendant(of: cardFinder, matching: find.text(label)),
          );
          expect(
            rect.left,
            greaterThanOrEqualTo(cardRect.left),
            reason: '星期 $label 左缘不越界',
          );
          expect(
            rect.right,
            lessThanOrEqualTo(cardRect.right),
            reason: '星期 $label 右缘不越界',
          );
        }

        // 1..30 全部日格与每个周日（第 7 列）都完整落在卡片内。
        for (var day = 1; day <= 30; day++) {
          final cell = find.byKey(ValueKey('board-focus-day-$day'));
          expect(cell, findsOneWidget, reason: '11 月 $day 日格必须渲染');
          final rect = tester.getRect(cell);
          expect(
            rect.left,
            greaterThanOrEqualTo(cardRect.left),
            reason: '$day 日左缘不越界',
          );
          expect(
            rect.right,
            lessThanOrEqualTo(cardRect.right),
            reason: '$day 日右缘不越界',
          );
          expect(rect.width, greaterThanOrEqualTo(36), reason: '$day 日命中区不被压窄');
        }
        for (final sunday in [1, 8, 15, 22, 29]) {
          final rect = tester.getRect(
            find.byKey(ValueKey('board-focus-day-$sunday')),
          );
          expect(
            rect.right,
            greaterThan(cardRect.right - 48),
            reason: '周日 $sunday 贴着卡片右缘，而不是被挤到左边留白',
          );
          expect(find.text('$sunday'), findsOneWidget);
        }

        // 卡片内部不存在横向 Scrollable。
        expect(
          find.descendant(
            of: cardFinder,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  (widget.axisDirection == AxisDirection.right ||
                      widget.axisDirection == AxisDirection.left),
            ),
          ),
          findsNothing,
          reason: '热力月历内部不允许出现横向滚动条',
        );

        // 年月只在唯一的热力月历切换器里出现一次。
        expect(
          find.byKey(const ValueKey('board-focus-month-entry')),
          findsNothing,
          reason: '卡片顶部不再保留独立月份入口',
        );
        expect(find.text('2026年11月'), findsOneWidget);
        expect(find.textContaining('2026年11月'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('board-focus-previous-month')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('board-focus-next-month')),
          findsOneWidget,
        );

        // 今天已选中：顶部汇总给出三类计数，日期详情不再复述。
        final todayFocus = find.byKey(
          const ValueKey('board-today-national-focus'),
        );
        expect(todayFocus, findsOneWidget);
        for (final label in ['点亮 1', '待确认 1', '熄灭 1']) {
          expect(
            find.descendant(of: todayFocus, matching: find.text(label)),
            findsOneWidget,
            reason: '今日国策状态必须给出 $label',
          );
        }
        final heatTitle = tester.getRect(
          find.descendant(of: cardFinder, matching: find.text('专注热力月历')),
        );
        expect(
          tester.getRect(todayFocus).bottom,
          lessThanOrEqualTo(heatTitle.top),
          reason: '今日国策状态位于热力月历之上',
        );
        for (final duplicated in ['国策记录', '存在已熄灭', '存在待确认', '全点亮', '暂无国策']) {
          expect(
            find.text(duplicated),
            findsNothing,
            reason: '日期详情不再重复输出：$duplicated',
          );
        }
        expect(find.textContaining('点亮 1 · 待确认'), findsNothing);
        expect(find.textContaining('待确认 1 · 熄灭 1'), findsNothing);

        // 今天与今天的热力、安排都直接长在融合卡里。
        expect(find.text('11 月 18 日 · 今日'), findsOneWidget);
        expect(find.text('13分00秒'), findsOneWidget);
        expect(find.text('今日安排 · 1 项'), findsOneWidget);
        expect(
          find.descendant(of: cardFinder, matching: find.text('与设计评审对齐专注链层级')),
          findsOneWidget,
          reason: '今日安排标题直接呈现在融合卡内',
        );
        expect(
          find.textContaining('项安排'),
          findsNothing,
          reason: '不再有独立的「今天 · X 项安排」顶卡',
        );
        expect(find.textContaining('今天 · '), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });

    testWidgets('日期详情用 PactaSectionHeader 与两块 surfaceContainerLow 容器分区', (
      tester,
    ) async {
      _useView(tester, const Size(360, 1200));
      final fixture = await _BoardPhase3Fixture.create(cards: treeCards());
      try {
        await tester.pumpWidget(fixture.app());
        await tester.pumpAndSettle();

        final cardFinder = find.byKey(
          const ValueKey('board-focus-national-card'),
        );
        final header = find.descendant(
          of: cardFinder,
          matching: find.byType(PactaSectionHeader),
        );
        expect(header, findsOneWidget, reason: '日期详情使用谷歌蓝分组标题');
        final headerTitle = find.descendant(
          of: header,
          matching: find.text('日期详情'),
        );
        expect(headerTitle, findsOneWidget);
        final colors = Theme.of(tester.element(headerTitle)).colorScheme;
        expect(
          tester.widget<Text>(headerTitle).style?.color,
          colors.primary,
          reason: '分区标题取主蓝，而不是灰色小字',
        );

        // 日期副文本在标题右侧同一行，贴右缘但不越过卡片。
        final cardRect = tester.getRect(cardFinder);
        final titleRect = tester.getRect(headerTitle);
        final dateRect = tester.getRect(find.text('11 月 18 日 · 今日'));
        expect(dateRect.left, greaterThanOrEqualTo(titleRect.right));
        expect(dateRect.right, lessThanOrEqualTo(cardRect.right));
        expect(dateRect.top, lessThan(titleRect.bottom), reason: '日期与标题同一行');
        expect(dateRect.bottom, greaterThan(titleRect.top));

        // 两块柔和 tonal 容器：底色统一 surfaceContainerLow，各自承担一组内容。
        final durationPanel = find.byKey(
          const ValueKey('board-focus-day-duration-panel'),
        );
        final schedulePanel = find.byKey(
          const ValueKey('board-focus-schedule-panel'),
        );
        for (final panel in [durationPanel, schedulePanel]) {
          expect(panel, findsOneWidget);
          final decoration =
              tester.widget<Container>(panel).decoration! as BoxDecoration;
          expect(decoration.color, colors.surfaceContainerLow);
          expect(
            decoration.borderRadius,
            BorderRadius.circular(PactaSpacing.md),
          );
        }
        final durationLabel = find.descendant(
          of: durationPanel,
          matching: find.text('有效专注'),
        );
        expect(durationLabel, findsOneWidget);
        expect(
          find.descendant(
            of: durationPanel,
            matching: find.byKey(const ValueKey('board-focus-day-duration')),
          ),
          findsOneWidget,
        );
        final durationLabelRect = tester.getRect(durationLabel);
        final durationRect = tester.getRect(
          find.byKey(const ValueKey('board-focus-day-duration')),
        );
        expect(
          durationRect.top,
          greaterThan(durationLabelRect.bottom),
          reason: '标签与时长各自成行，不挤成一团',
        );
        expect(durationRect.left, closeTo(durationLabelRect.left, 0.01));

        expect(
          find.descendant(of: schedulePanel, matching: find.text('今日安排 · 1 项')),
          findsOneWidget,
        );
        final scheduleTitleRect = tester.getRect(find.text('今日安排 · 1 项'));
        final scheduleRowRect = tester.getRect(find.text('与设计评审对齐专注链层级'));
        expect(
          scheduleRowRect.top - scheduleTitleRect.bottom,
          greaterThanOrEqualTo(PactaSpacing.sm - 0.01),
          reason: '标题与日程列表之间留出 8dp 呼吸',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });

    testWidgets('有置顶目标时并进融合卡顶槽，热力月历仍在其下', (tester) async {
      _useView(tester, const Size(360, 1200));
      final fixture = await _BoardPhase3Fixture.create(
        cards: treeCards(),
        pinned: true,
      );
      try {
        await tester.pumpWidget(fixture.app());
        await tester.pumpAndSettle();

        // 今天仍有待确认节点 → 默认页签是国策状态；置顶目标在那枚紧凑
        // 胶囊后面，不再是压在月历上方的独立超高区块。
        expect(find.text('还没有置顶目标'), findsNothing);
        expect(find.text('置顶目标 (1)'), findsOneWidget);
        expect(
          find.byKey(ValueKey('board-pinned-goal-${fixture.goalId}')),
          findsNothing,
        );
        final pinnedTab = find.byKey(const ValueKey('board-top-slot-pinned'));
        await tester.tap(pinnedTab);
        await tester.pumpAndSettle();

        final pinnedCard = find.byKey(
          ValueKey('board-pinned-goal-${fixture.goalId}'),
        );
        expect(pinnedCard, findsOneWidget);

        final cardRect = tester.getRect(
          find.byKey(const ValueKey('board-focus-national-card')),
        );
        final heatTitle = tester.getRect(
          find.descendant(
            of: find.byKey(const ValueKey('board-focus-national-card')),
            matching: find.text('专注热力月历'),
          ),
        );
        expect(
          tester.getRect(pinnedCard).top,
          greaterThan(cardRect.top),
          reason: '置顶目标在融合卡顶槽内，而不是卡外上方的独立区块',
        );
        expect(
          tester.getRect(pinnedCard).bottom,
          lessThanOrEqualTo(heatTitle.top),
          reason: '顶槽仍在热力月历之上，月历保持首屏主角',
        );
        expect(find.text('2026年11月'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('board-focus-month-entry')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 3：目标卡收起态上下内边距对称 + 展开态头部末行到首任务恒定
  // ---------------------------------------------------------------------------
  group('Phase 3 目标卡内边距与展开间距', () {
    testWidgets('无描述与单行描述目标收起后上下对称，展开态末行间距恒定', (tester) async {
      _useView(tester, const Size(420, 1400));
      final database = PactaDatabase(NativeDatabase.memory());
      const user = 'guard-goal-symmetry';
      final now = DateTime.utc(2026, 11, 18, 2);
      final tasks = LocalTaskRepository(
        database: database,
        userId: user,
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
        now: () => now,
      );
      final plain = await tasks.createGoal(
        const GoalDraft(
          title: '无描述目标',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.createTask(
        plain.id,
        const TaskDraft(
          title: '首条任务甲',
          classification: TaskClassification.regular,
        ),
      );
      final described = await tasks.createGoal(
        const GoalDraft(
          title: '带描述目标',
          description: '单行描述不会改变卡片的上下节奏。',
          classification: TaskClassification.regular,
        ),
      );
      await tasks.createTask(
        described.id,
        const TaskDraft(
          title: '首条任务乙',
          classification: TaskClassification.regular,
        ),
      );
      final goals = await tasks.getGoals();
      final plainGoal = goals.firstWhere((goal) => goal.id == plain.id);
      final describedGoal = goals.firstWhere((goal) => goal.id == described.id);
      try {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: pactaTheme(Brightness.light),
              home: Scaffold(
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(PactaSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final goal in [plainGoal, describedGoal])
                        GoalCard(
                          key: ValueKey(goal.id),
                          repository: tasks,
                          goal: goal,
                          focusProgressSecondsByTask: null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Finder cardOf(String title) => find.ancestor(
          of: find.text(title),
          matching: find.byType(GoalCard),
        );
        Finder summaryOf(String title) => find.descendant(
          of: cardOf(title),
          matching: find.text('1 项任务 · 进行中'),
        );

        double expandedGap(String title) {
          final taskRow = find
              .descendant(of: cardOf(title), matching: find.byType(ListTile))
              .first;
          return tester.getRect(taskRow).top -
              tester.getRect(summaryOf(title)).bottom;
        }

        // 展开态：头部末行（摘要）到首条任务顶距与描述行数无关。
        final plainGap = expandedGap('无描述目标');
        final describedGap = expandedGap('带描述目标');
        expect(plainGap, greaterThanOrEqualTo(PactaSpacing.sm));
        expect(
          (plainGap - describedGap).abs(),
          lessThanOrEqualTo(1.0),
          reason: '展开态末行到首条任务顶距必须恒定',
        );

        // 收起两张卡：只剩「上边距 + 文字块 + 下边距」。
        for (final goal in [plainGoal, describedGoal]) {
          await tester.tap(find.byKey(ValueKey('goal-header-${goal.id}')));
          await tester.pumpAndSettle();
        }

        List<double> insets(String title) {
          expect(
            find.descendant(of: cardOf(title), matching: find.byType(ListTile)),
            findsNothing,
            reason: '$title 已收起，任务行不再渲染',
          );
          final cardRect = tester.getRect(cardOf(title));
          final titleRect = tester.getRect(
            find.descendant(of: cardOf(title), matching: find.text(title)),
          );
          final summaryRect = tester.getRect(summaryOf(title));
          return [
            titleRect.top - cardRect.top,
            cardRect.bottom - summaryRect.bottom,
          ];
        }

        final plainInsets = insets('无描述目标');
        final describedInsets = insets('带描述目标');
        for (final (label, values) in [
          ('无描述目标', plainInsets),
          ('带描述目标', describedInsets),
        ]) {
          expect(
            (values[0] - values[1]).abs(),
            lessThanOrEqualTo(1.0),
            reason: '$label 收起态上下内边距必须对称：上 ${values[0]} / 下 ${values[1]}',
          );
          expect(values[0], closeTo(PactaSpacing.lg, 1.0));
          expect(values[1], closeTo(PactaSpacing.lg, 1.0));
        }
        expect(
          (plainInsets[0] - describedInsets[0]).abs(),
          lessThanOrEqualTo(1.0),
          reason: '有无描述不改变收起态上边距',
        );
        expect(
          (plainInsets[1] - describedInsets[1]).abs(),
          lessThanOrEqualTo(1.0),
          reason: '有无描述不改变收起态下边距',
        );

        // 再展开：末行到首条任务的距离回到原值，收起不改变这条常量。
        for (final goal in [plainGoal, describedGoal]) {
          await tester.tap(find.byKey(ValueKey('goal-header-${goal.id}')));
          await tester.pumpAndSettle();
        }
        expect(expandedGap('无描述目标'), moreOrLessEquals(plainGap, epsilon: 1.0));
        expect(
          expandedGap('带描述目标'),
          moreOrLessEquals(describedGap, epsilon: 1.0),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tasks.dispose();
        await database.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 3：专注弹窗 360dp 提示不截断 + 下必为例唯一标题
  // ---------------------------------------------------------------------------
  group('Phase 3 专注弹窗提示与下必为例标题', () {
    testWidgets('360x800 下准备时长 helperText 两行不截断、三档位仍单排居中', (tester) async {
      _useView(tester, const Size(360, 800));
      final database = PactaDatabase(NativeDatabase.memory());
      const user = 'guard-setup-dialog-phase3';
      final now = DateTime.utc(2026, 11, 18, 2);
      final tasks = LocalTaskRepository(
        database: database,
        userId: user,
        remote: InMemoryTaskRemote(),
        cloudSyncEnabled: false,
        now: () => now,
      );
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '弹窗提示守卫',
          classification: TaskClassification.regular,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '写一段足够长的任务名称以覆盖折行风险',
          classification: TaskClassification.regular,
        ),
      );
      try {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: pactaTheme(Brightness.light),
              home: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: ElevatedButton(
                      onPressed: () => showDialog<Object>(
                        context: context,
                        builder: (_) => FocusSetupDialog(
                          task: task,
                          initialMode: FocusChainMode.regular,
                        ),
                      ),
                      child: const Text('打开'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();

        const helper = '1–60 分钟；超出范围或非整数不会开始预约。';
        expect(find.text(helper), findsOneWidget);
        final helperParagraph = tester.renderObject<RenderParagraph>(
          find.text(helper),
        );
        expect(
          helperParagraph.didExceedMaxLines,
          isFalse,
          reason: 'helperMaxLines: 2 下提示必须完整显示，不能被省略号截断',
        );
        expect(
          helperParagraph.size.height,
          greaterThanOrEqualTo(helperParagraph.preferredLineHeight * 1.8),
          reason: '提示确实排成两行，而不是被压成一行',
        );

        final viewport = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SingleChildScrollView),
        );
        expect(viewport, findsOneWidget);
        final viewportRect = tester.getRect(viewport);

        final chips = find.byType(ChoiceChip);
        expect(chips, findsNWidgets(3));
        final chipRects = [
          for (var index = 0; index < 3; index++)
            tester.getRect(chips.at(index)),
        ];
        final highest = chipRects
            .map((rect) => rect.top)
            .reduce((left, right) => left < right ? left : right);
        final lowest = chipRects
            .map((rect) => rect.top)
            .reduce((left, right) => left > right ? left : right);
        expect(
          lowest - highest,
          lessThanOrEqualTo(1.0),
          reason: '5/10/15 三个档位必须严格单排',
        );
        for (final rect in chipRects) {
          expect(
            rect.bottom,
            lessThanOrEqualTo(viewportRect.bottom + 0.01),
            reason: '档位底边必须高于父视口下沿，不能被裁掉',
          );
          expect(
            rect.top,
            greaterThanOrEqualTo(viewportRect.top - 0.01),
            reason: '档位顶边必须在父视口内',
          );
          expect(rect.width, greaterThan(24));
        }
        final chipWidths = chipRects.map((rect) => rect.width).toSet();
        expect(chipWidths.length, 1, reason: '三个档位等宽，选中时不因勾号占位被撑开');
        expect(
          (chipRects.first.left - viewportRect.left).abs(),
          lessThanOrEqualTo(0.5),
          reason: '档位行贴着内容区左缘',
        );
        expect(
          (viewportRect.right - chipRects.last.right).abs(),
          lessThanOrEqualTo(0.5),
          reason: '档位行贴着内容区右缘：整体居中而不是偏左',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tasks.dispose();
        await database.close();
      }
    });

    testWidgets('下必为例管理页只有 AppBar 一个标题，卡片不再重复', (tester) async {
      _useView(tester, const Size(360, 800));
      final database = PactaDatabase(NativeDatabase.memory());
      const user = 'guard-precedent-page';
      final focus = LocalFocusRepository(
        database: database,
        userId: user,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
      );
      try {
        await focus.createPrecedentRule(text: '允许短暂起身接水');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [focusRepositoryProvider.overrideWithValue(focus)],
            child: MaterialApp(
              theme: pactaTheme(Brightness.light),
              home: const PrecedentRulesPage(),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PrecedentRulesPage), findsOneWidget);
        expect(
          find.text('下必为例'),
          findsOneWidget,
          reason: '同屏只允许 AppBar 标题一处「下必为例」',
        );
        expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('下必为例')),
          findsOneWidget,
        );
        expect(find.text('允许短暂起身接水'), findsOneWidget);
        expect(find.text('新建规则'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await focus.dispose();
        await database.close();
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 4：去胶囊 '今' + 底部固定指示轨
  // ---------------------------------------------------------------------------
  group('Phase 4 去胶囊今字与底部指示轨', () {
    const zone = 'Asia/Shanghai';
    final now = DateTime.utc(2026, 11, 18, 2);
    final colors = PactaCalendarColors.light;

    NationalFocusFailure failureOn(DateTime checkpointAt, String id) =>
        NationalFocusFailure(
          id: id,
          batchId: 'batch-$id',
          cardId: 'card-$id',
          checkpointAt: checkpointAt,
          cause: NationalFocusFailureCause.missedConfirmation,
          failureReason: null,
          sharedExplanation: null,
          treeSnapshot: [
            NationalFocusCardSnapshot(
              id: 'card-$id',
              name: '先写第一步',
              triggerCondition: '开始前',
              action: '写一步',
              isInTree: true,
              state: NationalFocusCardState.pendingTodayConfirmation,
              successfulDays: 1,
              currentConsecutiveDays: 0,
              bestConsecutiveDays: 1,
              maintenanceCycleStarted: true,
              createdAt: DateTime.utc(2026, 9, 1),
              updatedAt: DateTime.utc(2026, 11, 6),
            ),
          ],
        );

    Schedule scheduleOn(String id, String title, DateTime startsAt) => Schedule(
      id: id,
      title: title,
      startsAt: startsAt,
      endsAt: startsAt.add(const Duration(hours: 1)),
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
      isCompleted: false,
    );

    // 5 种格态同屏：12 深绿+失败、14 灰蓝+失败、16 双态、18 今天+专注+安排、
    // 19 纯安排；17 是无状态对照日。16..20 同行，14 在上一行。
    Widget board() => MaterialApp(
      theme: pactaTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 360,
            child: FocusNationalCalendarCard(
              focusRepository: _Phase4FocusRepository(
                seconds: {12: 5400, 16: 5400, 18: 9000},
              ),
              nationalFocusRepository: _Phase4NationalFocusRepository(
                failures: [
                  failureOn(DateTime.utc(2026, 11, 12, 4), 'f12'),
                  failureOn(DateTime.utc(2026, 11, 14, 4), 'f14'),
                  failureOn(DateTime.utc(2026, 11, 16, 4), 'f16'),
                  failureOn(DateTime.utc(2026, 11, 20, 4), 'f20'),
                ],
              ),
              scheduleRepository: _Phase4ScheduleRepository([
                scheduleOn('s16', '周会', DateTime.utc(2026, 11, 16, 4)),
                scheduleOn('s18', '与设计评审', DateTime.utc(2026, 11, 18, 3)),
                scheduleOn('s19', '复盘', DateTime.utc(2026, 11, 19, 3)),
              ]),
              displayTimeZoneId: zone,
              now: () => now,
              onOpenNationalFocus: () {},
              onRetryProjection: () {},
            ),
          ),
        ),
      ),
    );

    testWidgets('三个入口的今字都不再有填充胶囊', (tester) async {
      _useView(tester, const Size(360, 1400));
      await tester.pumpWidget(board());
      await tester.pumpAndSettle();
      expect(find.text('今'), findsOneWidget);
      expect(
        _todayLabelBackdrops(tester),
        0,
        reason: '看板热力月历：今字之上不得出现带填充色的 Container/DecoratedBox',
      );
      expect(
        tester.widget<Text>(find.text('今')).style?.color,
        colors.heat3Foreground,
        reason: '深绿 heat3 上的今字用白色业务前景，而不是蓝字配绿底',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: Scaffold(
            body: PlanCalendarView(
              repository: _Phase4ScheduleRepository([
                scheduleOn('plan-s15', '今日安排', DateTime.utc(2026, 11, 15, 3)),
              ]),
              goals: const <Goal>[],
              displayTimeZoneId: zone,
              now: () => DateTime.utc(2026, 11, 15, 2),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('今'), findsOneWidget);
      expect(
        _todayLabelBackdrops(tester),
        0,
        reason: '计划日历：今字之上不得出现带填充色的 Container/DecoratedBox',
      );
      expect(
        tester.widget<Text>(find.text('今')).style?.color,
        colors.hasPlansForeground,
        reason: '柔和黄有安排底上的今字用该底色的高对比前景',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('同行四种格态的日期数字垂直中心严格对齐，没有上下跳动', (tester) async {
      _useView(tester, const Size(360, 1400));
      await tester.pumpWidget(board());
      await tester.pumpAndSettle();

      double numberCenterDy(int day) => tester
          .getRect(
            find.descendant(
              of: find.byKey(ValueKey('board-focus-day-$day')),
              matching: find.text('$day'),
            ),
          )
          .center
          .dy;

      // 16..20 在同一行：16 双态、17 无状态、18 今天、19 纯安排、20 纯失败。
      // 无论有没有状态点，日期数字都必须落在同一条水平线上。
      final centers = {
        for (final day in [16, 17, 18, 19, 20]) day: numberCenterDy(day),
      };
      final lowest = centers.values.reduce((a, b) => a < b ? a : b);
      final highest = centers.values.reduce((a, b) => a > b ? a : b);
      expect(
        highest - lowest,
        lessThanOrEqualTo(0.5),
        reason: '四种格态的数字中心必须严格齐平：$centers',
      );

      // 底部轨道恒定存在：无状态日的格子高度与双态日完全一致。
      final heights = {
        for (final day in [16, 17, 18, 19, 20])
          day: tester
              .getRect(find.byKey(ValueKey('board-focus-day-$day')))
              .height,
      };
      final staticHeights = {
        for (final day in [16, 17, 19, 20]) heights[day]!,
      };
      expect(
        staticHeights.length,
        1,
        reason:
            '指示轨恒定保留，无状态/纯安排/纯失败/双态格子高度不得随状态变化：'
            '$heights',
      );
      expect(
        (heights[18]! - staticHeights.first).abs(),
        lessThanOrEqualTo(4.5),
        reason: '今天只多出 1.5dp 外框的 4dp 内缩，不额外撑高内容：$heights',
      );
    });

    testWidgets('双态日微点与细杠同轨并排、互不重叠且仍只有一层描边', (tester) async {
      _useView(tester, const Size(360, 1400));
      await tester.pumpWidget(board());
      await tester.pumpAndSettle();

      final cell = find.byKey(const ValueKey('board-focus-day-16'));
      // 选中双态日：2dp 主蓝描边落在日格最外层 Ink 上，仍只有一层。
      await tester.tap(cell);
      await tester.pumpAndSettle();
      final number = tester.getRect(
        find.descendant(of: cell, matching: find.text('16')),
      );
      final dot = tester.getRect(
        find.byKey(const ValueKey('board-focus-schedule-dot-16')),
      );
      final bar = tester.getRect(
        find.byKey(const ValueKey('board-focus-failure-dot-16')),
      );
      expect(dot.width, closeTo(dot.height, 0.01), reason: '安排点是等宽高微点');
      expect(bar.width, greaterThan(bar.height), reason: '国策失败是横向细短杠');
      expect(dot.overlaps(bar), isFalse, reason: '微点与细杠不得重叠');
      expect(dot.right, lessThanOrEqualTo(bar.left + 0.01));
      for (final rect in [dot, bar]) {
        expect(
          rect.top,
          greaterThanOrEqualTo(number.bottom - 0.01),
          reason: '所有底部标记都在日期数字下方',
        );
      }
      expect(_borderLayers(tester, cell), 1, reason: '双态日仍只有一层等大外框');
      expect(_todayLabelBackdrops(tester), 0, reason: '底部标记不得把今字包回胶囊');

      // 14 在 heat0 上不需要托底；12 在 heat3 上必须有半透托底。
      expect(
        find.byKey(const ValueKey('board-focus-failure-halo-14')),
        findsNothing,
      );
      final halo = find.byKey(const ValueKey('board-focus-failure-halo-12'));
      expect(halo, findsOneWidget, reason: '深绿底上的珊瑚红细杠需要隔离托底');
      final haloDecoration =
          tester.widget<Container>(halo).decoration! as BoxDecoration;
      expect(
        haloDecoration.border,
        isNull,
        reason: '托底只能填充：加 border 会打破单层描边守卫',
      );
      // 未选中的深绿格：托底不引入任何 border，装饰层里没有第二层外框。
      expect(
        _borderLayers(tester, find.byKey(const ValueKey('board-focus-day-12'))),
        0,
        reason: '光晕托底不得带回第二层描边',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('今字按底色自适应取色：heat0/无底色用 todayLabelColor，业务底用前景', (tester) async {
      final cases = <(String, Color?, Color, Color)>[
        ('无底色', null, colors.heat0Foreground, colors.todayLabelColor),
        (
          'heat0',
          colors.heat0Background,
          colors.heat0Foreground,
          colors.todayLabelColor,
        ),
        (
          'heat3',
          colors.heat3Background,
          colors.heat3Foreground,
          colors.heat3Foreground,
        ),
        (
          'hasPlans',
          colors.hasPlansBackground,
          colors.hasPlansForeground,
          colors.hasPlansForeground,
        ),
      ];
      for (final (name, background, foreground, expected) in cases) {
        await tester.pumpWidget(
          MaterialApp(
            theme: pactaTheme(Brightness.light),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 64,
                  child: PactaCalendarDayBox(
                    cellKey: ValueKey('phase4-cell-$name'),
                    dayNumber: '15',
                    today: true,
                    backgroundColor: background,
                    foregroundColor: foreground,
                    centerTodayLabel: true,
                    reserveBottomSlot: true,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.text('今')).style?.color,
          expected,
          reason: '$name：今字颜色必须自适应底色',
        );
        expect(
          _borderLayers(tester, find.byKey(ValueKey('phase4-cell-$name'))),
          1,
        );
        expect(_todayLabelBackdrops(tester), 0, reason: '$name：今字不带胶囊');
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 5 T07：全站图标尺度、死页残留与去冗余的机械守卫
  // ---------------------------------------------------------------------------
  group('Phase 5 T07 机械守卫', () {
    test('lib/src 里显式 Icon 尺寸只取 PactaIconSizes 常量', () {
      final violations = <String>[];
      for (final file in _libSources()) {
        final path = _relativePath(file);
        final source = file.readAsStringSync();
        for (final entry in _iconSizeEntries(source)) {
          final location = '$path:${_lineOf(source, entry.offset)}';
          // 唯一白名单：计划日历底部 8dp 指示槽里的完成勾。它必须完整落在
          // 8dp 槽内，放大到 micro(14) 会上下各溢出 1dp。
          final size = entry.size;
          if (path == _calendarIndicatorSlotSource &&
              size is IntegerLiteral &&
              size.value == 8 &&
              entry.arguments.contains('plan-day-check-')) {
            continue;
          }
          // PactaCheckCircle 只把变量透传给 Icon：两个档位常量本身来自
          // PactaIconSizes，下面另有断言锁住这层来源。
          if (path == _checkCircleSource &&
              size is SimpleIdentifier &&
              size.name == 'effectiveVisualSize') {
            continue;
          }
          if (size is PrefixedIdentifier &&
              size.prefix.name == _iconSizesClass) {
            continue;
          }
          violations.add('$location -> ${size?.toSource() ?? 'null'}');
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            '图标尺寸只从 $_iconSizesClass 取：12/13/16/18/20/24/32/40/48 '
            '之类的散值会让同一层级的图标在亮暗、窄宽屏之间各写一套。'
            '违规：$violations',
      );
      // 透传变量的那一处必须仍然源自共享尺度常量。
      final checkCircle = File(_checkCircleSource).readAsStringSync();
      expect(
        checkCircle.contains(
          'static const double compactVisualSize = PactaIconSizes.sm;',
        ),
        isTrue,
      );
      expect(
        checkCircle.contains(
          'static const double interactiveVisualSize = PactaIconSizes.md;',
        ),
        isTrue,
      );
    });

    test('lib/src 不再引入裸 fontSize（今微字是唯一白名单）', () {
      final violations = <String>[];
      for (final file in _libSources()) {
        final path = _relativePath(file);
        final source = file.readAsStringSync();
        for (final entry in _fontSizeEntries(source)) {
          final literal = entry.value;
          final whitelisted =
              path == _todayLabelSource &&
              literal is IntegerLiteral &&
              literal.value == 10;
          if (whitelisted) continue;
          violations.add(
            '$path:${_lineOf(source, entry.offset)} -> ${literal.toSource()}',
          );
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            '字号只能从主题字阶派生；「今」微字是唯一白名单，'
            '它自己的 10dp 由 pacta_calendar_colors_test 锁定。'
            '违规：$violations',
      );
    });

    test('lib/src 不再残留已删除的页面与兼容转换器', () {
      const removed = <String>[
        'FocusMonthPage',
        'focus_month_page.dart',
        'NationalFocusReconciliationPage',
        'national_focus_reconciliation_page.dart',
        'LegacyCloudSnapshotConverter',
        'legacy_cloud_snapshot.dart',
      ];
      final violations = <String>[];
      for (final file in _libSources()) {
        final path = _relativePath(file);
        final source = file.readAsStringSync();
        for (final token in removed) {
          var index = source.indexOf(token);
          while (index >= 0) {
            violations.add('$path:${_lineOf(source, index)} -> $token');
            index = source.indexOf(token, index + token.length);
          }
        }
      }
      expect(violations, isEmpty, reason: '旧兼容死页已彻底删除，任何引用都会把读者带回已废弃路径。');
    });

    test('通知与设备权限页不再有仅本设备免责声明，机制说明留在行内 ⓘ', () {
      final source = File(
        'lib/src/notifications/focus_notification_settings_page.dart',
      ).readAsStringSync();
      expect(
        source.contains('这些提醒仅保存在本设备'),
        isFalse,
        reason: '页面底部的设备同步免责声明必须彻底删除，也不留只为它服务的间距',
      );
      expect(
        source.contains('national-focus-reminder-time-note'),
        isTrue,
        reason: '「不影响国策检查点」这类机制说明挂在行内 ⓘ 上',
      );
      expect(source.contains('不影响国策检查点'), isTrue);
      for (final removed in <String>[
        '直接向系统请求通知授权',
        '已允许；提醒按设定时刻送达',
        '系统可能限制后台运行',
        '默认关闭。',
      ]) {
        expect(
          source.contains(removed),
          isFalse,
          reason: '与状态胶囊重复的副标题必须删除：$removed',
        );
      }
      // 明确的可操作提示必须保留，不能被一起去冗余。
      expect(source.contains('未授予通知权限'), isTrue);
      expect(source.contains('桌面端保活运行，无需电池优化'), isTrue);
    });

    test('看板顶槽与计划日历的核心契约常量不被回退', () {
      final board = File(_boardCardSource).readAsStringSync();
      expect(
        board.contains('static const _pinnedSlotLimit = 2;'),
        isTrue,
        reason: '单栏顶槽最多展示 2 条置顶目标',
      );
      expect(
        board.contains('goals.take(_pinnedSlotLimit)'),
        isTrue,
        reason: '截断必须走同一个常量，第 3 条以后仍留给「查看全部 N 个」',
      );
      expect(
        _stringLiterals(board).where((value) => value == '国策记录'),
        isEmpty,
        reason: '顶部国策卡已经承担状态，底部不再有重复的「国策记录」区块',
      );

      final plan = File(_planCalendarSource).readAsStringSync();
      expect(plan.contains('centerTodayLabel: true'), isTrue);
      expect(plan.contains('reserveBottomSlot: true'), isTrue);
      expect(
        plan.contains('heat0Background'),
        isTrue,
        reason: '普通日必须取与看板热力月历一致的 heat0 中性底块',
      );
    });

    testWidgets('计划日历所有日格启用居中今字与底部指示轨，普通日取 heat0 中性底块', (tester) async {
      _useView(tester, const Size(360, 1200));
      final colors = PactaCalendarColors.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: pactaTheme(Brightness.light),
          home: Scaffold(
            body: PlanCalendarView(
              // 无任何安排：整月都必须是普通日，才量得到「今天也不覆写底块」。
              repository: _Phase4ScheduleRepository(const <Schedule>[]),
              goals: const <Goal>[],
              displayTimeZoneId: 'Asia/Shanghai',
              now: () => DateTime.utc(2026, 11, 18, 2),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boxes = tester
          .widgetList<PactaCalendarDayBox>(find.byType(PactaCalendarDayBox))
          .toList();
      expect(boxes, isNotEmpty, reason: '11 月网格必须渲染出日格');
      for (final box in boxes) {
        expect(
          box.centerTodayLabel,
          isTrue,
          reason: '每个日格的「今」都居中置顶，与看板热力月历同一套几何',
        );
        expect(
          box.reserveBottomSlot,
          isTrue,
          reason: '底部 8dp 指示轨恒定保留，日期数字不会因状态上下跳动',
        );
      }
      // 17 日无安排、非今天：普通日必须带 heat0 中性底块，不能留白。
      final neutral = boxes.firstWhere((box) => box.dayNumber == '17');
      expect(neutral.backgroundColor, colors.heat0Background);
      // 今天同样保留底块：今天只改变描边与独立「今」微字。
      final today = boxes.firstWhere((box) => box.dayNumber == '18');
      expect(today.today, isTrue);
      expect(today.backgroundColor, colors.heat0Background);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 6：组列表 M3 Expressive 分段、看板置顶槽对称、管理员界面彻底下线
  // ---------------------------------------------------------------------------
  group('Phase 6 机械守卫', () {
    NationalFocusCard phase6Card(String id, String name) => NationalFocusCard(
      id: id,
      name: name,
      triggerCondition: '触发条件',
      action: '坐到书桌前先写下今天的第一步。',
      isInTree: true,
      state: NationalFocusCardState.lit,
      createdAt: DateTime.utc(2026, 11, 18, 1),
      updatedAt: DateTime.utc(2026, 11, 18, 1),
    );

    testWidgets('PactaGroupedList 在亮暗双主题下是 M3 Expressive 分段卡片，零 Divider', (
      tester,
    ) async {
      _useView(tester, const Size(400, 900));
      for (final brightness in Brightness.values) {
        for (final count in [3, 1]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: pactaTheme(brightness),
              home: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(PactaSpacing.cardRadius),
                  children: [
                    PactaGroupedList(
                      children: [
                        for (var index = 0; index < count; index++)
                          ListTile(title: Text('第 $index 段')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final grouped = find.byType(PactaGroupedList);
          expect(grouped, findsOneWidget);
          // 分段靠透明缝隙分开，不靠 1dp 分隔线切割。
          expect(
            find.descendant(of: grouped, matching: find.byType(Divider)),
            findsNothing,
            reason: '$brightness $count 段分组里不允许出现任何 Divider',
          );

          // 每段各自是一张独立圆角 Material，而不是一颗大卡里的若干行。
          final segmentFinder = find.descendant(
            of: grouped,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Material && widget.shape is RoundedRectangleBorder,
            ),
          );
          final segments = tester.widgetList<Material>(segmentFinder).toList();
          expect(segments, hasLength(count), reason: '每一行各自成段');
          for (final material in segments) {
            expect(material.clipBehavior, Clip.antiAlias);
          }
          final radii = [
            for (final material in segments)
              (material.shape! as RoundedRectangleBorder).borderRadius,
          ];
          if (count == 1) {
            // 单行时就是一张完整的 20dp 圆角卡。
            expect(
              radii.single,
              BorderRadius.circular(20),
              reason: '单行分组四角统一 20dp',
            );
          } else {
            expect(
              radii.first,
              const BorderRadius.vertical(
                top: Radius.circular(20),
                bottom: Radius.circular(4),
              ),
              reason: '首段顶部 20dp、底部 4dp',
            );
            expect(radii[1], BorderRadius.circular(4), reason: '中段四隅统一 4dp');
            expect(
              radii.last,
              const BorderRadius.vertical(
                top: Radius.circular(4),
                bottom: Radius.circular(20),
              ),
              reason: '末段顶部 4dp、底部 20dp',
            );
            final rects = [
              for (var index = 0; index < segments.length; index++)
                tester.getRect(segmentFinder.at(index)),
            ];
            for (var index = 1; index < rects.length; index++) {
              expect(
                rects[index].top - rects[index - 1].bottom,
                moreOrLessEquals(2, epsilon: 0.01),
                reason: '第 $index 段与上一段之间是 2dp 透明缝隙',
              );
            }
          }
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('看板置顶目标卡槽上下内边距对称，差值不超过 0.5dp', (tester) async {
      _useView(tester, const Size(360, 1200));
      final fixture = await _BoardPhase3Fixture.create(
        cards: [phase6Card('phase6-lit', '根国策')],
        pinned: true,
        pinnedGoalCount: 2,
      );
      try {
        await tester.pumpWidget(fixture.app());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('board-top-slot-pinned')));
        await tester.pumpAndSettle();

        final surface = tester.getRect(
          find.byKey(const ValueKey('board-top-slot-pinned-surface')),
        );
        final first = tester.getRect(
          find.byKey(
            ValueKey('board-pinned-goal-${fixture.pinnedGoalIds.first}'),
          ),
        );
        final last = tester.getRect(
          find.byKey(
            ValueKey('board-pinned-goal-${fixture.pinnedGoalIds.last}'),
          ),
        );
        final topGap = first.top - surface.top;
        final bottomGap = surface.bottom - last.bottom;
        expect(topGap, greaterThan(0), reason: '首张置顶卡顶部必须留白');
        expect(bottomGap, greaterThan(0), reason: '末张置顶卡底部必须留白');
        expect(
          (topGap - bottomGap).abs(),
          lessThanOrEqualTo(0.5),
          reason: '置顶卡槽上下内边距必须对称（首卡顶距 $topGap、末卡底距 $bottomGap）',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });

    testWidgets('计划页分区小标题统一为谷歌蓝 PactaSectionHeader', (tester) async {
      _useView(tester, const Size(360, 1200));
      final fixture = await _BoardPhase3Fixture.create(
        cards: [phase6Card('plan-header-lit', '根国策')],
        pinned: true,
      );
      // 再建一个未置顶目标，让「置顶」与「其他」两处分区标题同时出现。
      await fixture.tasks.createGoal(
        const GoalDraft(
          title: '未置顶目标',
          classification: TaskClassification.both,
        ),
      );
      try {
        await tester.pumpWidget(fixture.app());
        await tester.pumpAndSettle();
        await openPlan(tester);

        final pinnedHeader = find.widgetWithText(
          PactaSectionHeader,
          '置顶目标 · 长按拖动排序',
        );
        final othersHeader = find.widgetWithText(
          PactaSectionHeader,
          '其他目标 · 长按拖动排序',
        );
        expect(pinnedHeader, findsOneWidget);
        expect(othersHeader, findsOneWidget);

        final pinnedTitle = find.descendant(
          of: pinnedHeader,
          matching: find.text('置顶目标 · 长按拖动排序'),
        );
        final colors = Theme.of(tester.element(pinnedTitle)).colorScheme;
        expect(
          tester.widget<Text>(pinnedTitle).style?.color,
          colors.primary,
          reason: '分区小标题与全站谷歌蓝分组标题一致，不再用灰色小字',
        );
        // 标题左缘与目标卡片对齐，不因组件默认 4dp 内缩而错位。
        final headerRect = tester.getRect(pinnedTitle);
        final cardRect = tester.getRect(
          find.byKey(ValueKey('pinned-goal-${fixture.pinnedGoalIds.first}')),
        );
        expect(
          headerRect.left,
          moreOrLessEquals(cardRect.left, epsilon: 0.5),
          reason: '分区标题与目标卡片共用同一条左缘',
        );
        // 2.0x 字号：标题换行而不是被截断，页面零溢出。
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: pinnedHeader,
            matching: find.text('置顶目标 · 长按拖动排序'),
          ),
          findsOneWidget,
        );
      } finally {
        await fixture.dispose(tester);
      }
    });

    test('已删除的管理员界面与旧 FocusStatisticsPage 不再回流到 lib/src', () {
      const removed = <String>[
        'FocusStatisticsPage',
        'AdminUsersPage',
        'AdminEligibilityCard',
        'AdminPasswordResetCard',
        'admin_password_reset_card.dart',
        'AdminUserLifecycleCard',
        'admin_user_lifecycle_card.dart',
      ];
      final violations = <String>[];
      for (final file in _libSources()) {
        final path = _relativePath(file);
        final source = file.readAsStringSync();
        for (final token in removed) {
          if (path.contains(token)) violations.add('$path -> 路径包含 $token');
          for (final offset in _tokenOffsets(source, token)) {
            violations.add('$path:${_lineOf(source, offset)} -> $token');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            '管理员管理界面已整体迁出客户端，旧 FocusStatisticsPage 也已由 '
            'FocusHistoryPage 取代：任何回流都会把读者带回已删除的路径。'
            '违规：$violations',
      );
      expect(
        File('lib/src/auth/admin_password_reset_card.dart').existsSync(),
        isFalse,
        reason: '管理员重置密码界面必须彻底删除',
      );
      expect(
        File('lib/src/auth/admin_user_lifecycle_card.dart').existsSync(),
        isFalse,
        reason: '管理员用户停用恢复界面必须彻底删除',
      );
    });
  });
}

// -----------------------------------------------------------------------------
// Phase 6 辅助：详细卡片顶部状态条的几何判定
// -----------------------------------------------------------------------------

/// 国策详细卡片里的整宽细色条（旧顶部 3dp 状态色条的回流形态）。
///
/// 只按几何判定、不绑定具体组件：宽 ≥ 卡片宽度的 90% 且高 ≤ 3.5dp。详细卡片
/// 的正常内容（图标井 32dp、名称两行、连击胶囊、规则摘要、6dp 段落间距）都
/// 不满足这两个条件，所以任何命中都是状态条回流。
List<Rect> _topStatusStripBands(WidgetTester tester, Finder cardFinder) {
  final cardRect = tester.getRect(cardFinder);
  final bands = <Rect>[];
  final descendants = find.descendant(
    of: cardFinder,
    matching: find.byWidgetPredicate((_) => true),
  );
  for (final element in descendants.evaluate()) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      continue;
    }
    final size = renderObject.size;
    if (size.height > 3.5 || size.width < cardRect.width * 0.9) continue;
    bands.add(renderObject.localToGlobal(Offset.zero) & size);
  }
  return bands;
}

// -----------------------------------------------------------------------------
// 源码扫描工具：守卫读真实 lib/src 源文件，而不是维护第二份“应该长什么样”。
// -----------------------------------------------------------------------------

/// 计划日历底部 8dp 指示槽里的完成勾：唯一允许的裸图标尺寸。
const _calendarIndicatorSlotSource = 'lib/src/plan/plan_calendar_view.dart';

/// 「今」微字：唯一允许的裸 fontSize。
const _todayLabelSource = 'lib/src/ui/pacta_calendar_day_cell.dart';

const _boardCardSource = 'lib/src/board/focus_national_calendar_card.dart';
const _planCalendarSource = 'lib/src/plan/plan_calendar_view.dart';
const _checkCircleSource = 'lib/src/ui/pacta_check_circle.dart';
const _iconSizesClass = 'PactaIconSizes';

/// lib/src 下所有视觉契约源码（生成代码同样不该出现裸尺寸）。
List<File> _libSources() =>
    Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => _relativePath(file).endsWith('.dart'))
        .toList(growable: false);

String _relativePath(File file) => file.path.replaceAll('\\', '/');

/// 解析出源码里每一处显式 Icon(..., size: ...)。
List<_IconSize> _iconSizeEntries(String source) {
  final visitor = _IconSizeVisitor();
  parseString(content: source, throwIfDiagnostics: false).unit.accept(visitor);
  return visitor.entries;
}

/// 解析出源码里每一处 fontSize: ...。
List<_FontSize> _fontSizeEntries(String source) {
  final visitor = _FontSizeVisitor();
  parseString(content: source, throwIfDiagnostics: false).unit.accept(visitor);
  return visitor.entries;
}

/// 源码里所有不带插值的字符串字面量（插值串是另一段动态文本，不参与比较）。
List<String> _stringLiterals(String source) {
  final visitor = _StringLiteralVisitor();
  parseString(content: source, throwIfDiagnostics: false).unit.accept(visitor);
  return visitor.values;
}

/// 按 Dart 标识符边界统计 token 出现位置。
///
/// 纯子串扫描会把仍在使用中的 NationalFocusStatisticsPage（国策统计明细）
/// 误判成已删除的 FocusStatisticsPage；边界判定既锁住回归，又不误伤同后缀的
/// 合法页面。
List<int> _tokenOffsets(String source, String token) {
  const identifierChars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_\$';
  final offsets = <int>[];
  var index = source.indexOf(token);
  while (index >= 0) {
    final before = index == 0 ? '' : source[index - 1];
    final afterIndex = index + token.length;
    final after = afterIndex >= source.length ? '' : source[afterIndex];
    final boundedBefore = before.isEmpty || !identifierChars.contains(before);
    final boundedAfter = after.isEmpty || !identifierChars.contains(after);
    if (boundedBefore && boundedAfter) offsets.add(index);
    index = source.indexOf(token, index + token.length);
  }
  return offsets;
}

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

class _IconSize {
  _IconSize(this.offset, this.size, this.arguments);

  final int offset;
  final Expression? size;
  final String arguments;
}

class _IconSizeVisitor extends RecursiveAstVisitor<void> {
  final entries = <_IconSize>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name.lexeme == 'Icon') {
      _collect(node.argumentList);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // 未解析的调用可能被解析成方法调用（非 const 上下文里的 Icon(...)）。
    if (node.methodName.name == 'Icon') _collect(node.argumentList);
    super.visitMethodInvocation(node);
  }

  void _collect(ArgumentList arguments) {
    for (final argument in arguments.arguments) {
      if (argument is! NamedExpression || argument.name.label.name != 'size') {
        continue;
      }
      entries.add(
        _IconSize(argument.offset, argument.expression, arguments.toSource()),
      );
    }
  }
}

class _FontSize {
  _FontSize(this.offset, this.value);

  final int offset;
  final Expression value;
}

class _FontSizeVisitor extends RecursiveAstVisitor<void> {
  final entries = <_FontSize>[];

  @override
  void visitNamedExpression(NamedExpression node) {
    if (node.name.label.name == 'fontSize') {
      entries.add(_FontSize(node.offset, node.expression));
    }
    super.visitNamedExpression(node);
  }
}

class _StringLiteralVisitor extends RecursiveAstVisitor<void> {
  final values = <String>[];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    values.add(node.value);
    super.visitSimpleStringLiteral(node);
  }
}

/// 固定逻辑尺寸与像素比，测试结束时自动还原。
void _useView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Phase 3 看板夹具：真实本地仓储 + 固定上海账号时区 + 三张国策卡。
///
/// 时钟固定为 2026-11-18 02:00Z（上海 10:00），11 月 1 日是周日，因此
/// 1..30 日全部落在同一屏月历内，今天与有安排的周日同时存在。
class _BoardPhase3Fixture {
  _BoardPhase3Fixture._({
    required this.database,
    required this.tasks,
    required this.focus,
    required this.schedules,
    required this.nationalFocus,
    required this.now,
    required this.goalId,
    required this.pinnedGoalIds,
  });

  static const String user = 'guard-board-phase3';

  final PactaDatabase database;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;
  final LocalScheduleRepository schedules;
  final _FocusTreeFixtureRepository nationalFocus;
  final DateTime now;
  final String goalId;

  /// 夹具创建的全部目标 ID（含被置顶的那些），按创建顺序排列。
  final List<String> pinnedGoalIds;

  static Future<_BoardPhase3Fixture> create({
    required List<NationalFocusCard> cards,
    bool pinned = false,
    int pinnedGoalCount = 1,
  }) async {
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.utc(2026, 11, 18, 2);
    final tasks = LocalTaskRepository(
      database: database,
      userId: user,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: user,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final schedules = LocalScheduleRepository(
      database: database,
      userId: user,
      now: () => now,
    );
    final nationalFocus = _FocusTreeFixtureRepository(cards);
    final goals = <Goal>[];
    for (var index = 0; index < pinnedGoalCount; index++) {
      goals.add(
        await tasks.createGoal(
          GoalDraft(
            title: index == 0 ? '把重要的事情向前推进' : '第二个置顶目标',
            classification: TaskClassification.both,
          ),
        ),
      );
    }
    final goal = goals.first;
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '写 13 分钟',
        classification: TaskClassification.both,
      ),
    );
    final session = await focus.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 13),
    );
    now = session.endsAt;
    await focus.settleDueSessions();
    if (pinned) {
      for (final pinnedGoal in goals) {
        await tasks.setGoalPinned(pinnedGoal.id, isPinned: true);
      }
    }
    await schedules.createSchedule(
      ScheduleDraft(
        title: '与设计评审对齐专注链层级',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 18, 3),
          endsAt: DateTime.utc(2026, 11, 18, 4),
        ),
        taskId: task.id,
      ),
    );
    await schedules.createSchedule(
      ScheduleDraft(
        title: '周日整理与复盘',
        window: ScheduleWindow.timed(
          startsAt: DateTime.utc(2026, 11, 29, 3),
          endsAt: DateTime.utc(2026, 11, 29, 4),
        ),
      ),
    );
    return _BoardPhase3Fixture._(
      database: database,
      tasks: tasks,
      focus: focus,
      schedules: schedules,
      nationalFocus: nationalFocus,
      now: now,
      goalId: goal.id,
      pinnedGoalIds: [for (final pinnedGoal in goals) pinnedGoal.id],
    );
  }

  Widget app() => PactaApp(
    authRepository: FakeAuthRepository()..signedInUser = user,
    taskRepositoryFactory: (_) => tasks,
    focusRepositoryFactory: (_) => focus,
    scheduleRepositoryFactory: (_) => schedules,
    nationalFocusRepositoryFactory: (_) => nationalFocus,
    profileRepositoryFactory: (_) =>
        const _FixedZoneProfileRepository('Asia/Shanghai'),
    displayClock: () => now,
    cloudCheckClock: () => now,
  );

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await nationalFocus.dispose();
    await schedules.dispose();
    await focus.dispose();
    await tasks.dispose();
    await database.close();
  }
}

/// 固定账号显示时区的资料仓储：把看板锁在上海，避免主机时区干扰。
class _FixedZoneProfileRepository extends UnavailableProfileRepository {
  const _FixedZoneProfileRepository(this.timeZoneId);

  final String? timeZoneId;

  @override
  Stream<ProfileAccount> watchProfile() => Stream.value(
    ProfileAccount(
      userId: _BoardPhase3Fixture.user,
      displayTimeZoneId: timeZoneId,
    ),
  );

  @override
  Future<ProfileAccount> getProfile() async => ProfileAccount(
    userId: _BoardPhase3Fixture.user,
    displayTimeZoneId: timeZoneId,
  );
}

/// 统计一个作用域里所有携带描边的装饰层数量（Ink / DecoratedBox / Container）。
int _borderLayers(WidgetTester tester, Finder scope) {
  final everything = find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((_) => true),
  );
  var count = 0;
  for (final element in everything.evaluate()) {
    final widget = element.widget;
    Decoration? decoration;
    if (widget is Ink) {
      decoration = widget.decoration;
    } else if (widget is DecoratedBox) {
      decoration = widget.decoration;
    } else if (widget is Container) {
      decoration = widget.decoration;
    }
    if (decoration is BoxDecoration && decoration.border != null) count += 1;
  }
  return count;
}

/// 取出 '今' 微字的视觉矩形，用于窄格边界断言。
///
/// 去胶囊后 '今' 就是一段纯文字：没有 3dp 内边距的底衬，量到的就是字形本身。
Rect _todayBadgeRect(WidgetTester tester) => tester.getRect(find.text('今'));

/// 整棵树里是否存在包含指定片段的 Key（例如已废弃的 plan-day-selected-ring-*）。
bool _hasKeyContaining(WidgetTester tester, String fragment) {
  for (final element in find.byWidgetPredicate((_) => true).evaluate()) {
    final key = element.widget.key;
    if (key == null) continue;
    if (key.toString().contains(fragment)) return true;
  }
  return false;
}

class _FocusTreeFixtureRepository extends UnavailableNationalFocusRepository {
  _FocusTreeFixtureRepository(this.cards);

  final List<NationalFocusCard> cards;

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => Stream.value(cards);

  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() =>
      Stream.value(const <NationalFocusCard>[]);
}

/// '今' 与格子之间带填充色的 Container / DecoratedBox 数量（去胶囊守卫）。
int _todayLabelBackdrops(WidgetTester tester) {
  final filled = find.ancestor(
    of: find.text('今'),
    matching: find.byWidgetPredicate((widget) {
      if (widget is Container) {
        if (widget.color != null) return true;
        final decoration = widget.decoration;
        return decoration is BoxDecoration && decoration.color != null;
      }
      if (widget is DecoratedBox) {
        final decoration = widget.decoration;
        return decoration is BoxDecoration && decoration.color != null;
      }
      return false;
    }),
  );
  return filled.evaluate().length;
}

/// Phase 4 夹具：按日给专注秒数，只读投影，不写库。
class _Phase4FocusRepository extends UnavailableFocusRepository {
  _Phase4FocusRepository({required this.seconds});

  final Map<int, int> seconds;

  @override
  Stream<FocusMonthMetrics> watchMonthMetrics({
    required String timeZoneId,
    required DateTime month,
  }) {
    final start = DateTime.utc(month.year, month.month);
    final count = DateTime.utc(start.year, start.month + 1, 0).day;
    final days = [
      for (var day = 1; day <= count; day++)
        FocusActivityDay(
          date: DateTime.utc(start.year, start.month, day),
          activeSeconds: seconds[day] ?? 0,
        ),
    ];
    return Stream.value(
      FocusMonthMetrics(
        displayTimeZoneId: timeZoneId,
        month: start,
        days: days,
        totalActiveSeconds: days.fold(0, (sum, day) => sum + day.activeSeconds),
        activeDayCount: days.where((day) => day.activeSeconds > 0).length,
      ),
    );
  }
}

/// Phase 4 夹具：固定的国策失败记录，不结算、不写库。
class _Phase4NationalFocusRepository
    extends UnavailableNationalFocusRepository {
  _Phase4NationalFocusRepository({required this.failures});

  final List<NationalFocusFailure> failures;

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() =>
      Stream.value(const <NationalFocusCard>[]);

  @override
  Stream<List<NationalFocusFailure>> watchFailures() => Stream.value(failures);

  @override
  Future<void> settleDueCheckpoints() async {}
}

/// Phase 4 夹具：固定的只读安排行。
class _Phase4ScheduleRepository extends UnavailableScheduleRepository {
  _Phase4ScheduleRepository(this.rows);

  final List<Schedule> rows;

  @override
  Stream<List<Schedule>> watchSchedules({DateTime? from, DateTime? to}) =>
      Stream.value(rows);
}
