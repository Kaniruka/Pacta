import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show Tristate;

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/calendar/calendar_models.dart';
import 'package:pacta/src/calendar/calendar_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' hide FocusSession;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/ui/pacta_page_header.dart';

import '../test/support/fake_auth_repository.dart';
import '../test/support/fake_calendar_provider.dart';

/// Offline dashboard evidence using an in-memory database and fake auth.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('BOARD_PILOT_MODE')) {
    _boardPilot(binding);
    return;
  }

  testWidgets('看板摘要层级、计划页目标折叠与键盘、我的设置入口', (tester) async {
    const userId = 'board-design-offline-fixture';
    final database = PactaDatabase(NativeDatabase.memory());
    final sessionStart = DateTime.now().subtract(const Duration(minutes: 13));
    var now = sessionStart;
    final tasks = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: InMemoryTaskRemote(),
      now: () => now,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final nationalFocus = LocalNationalFocusRepository(
      database: database,
      userId: userId,
      cloudSyncEnabled: false,
    );
    final source = CalendarSource(
      id: 'board-design-calendar',
      displayName: '工作日历',
      timeZoneId: 'Asia/Shanghai',
      localCalendarId: '7',
    );
    final calendarProvider = FakeCalendarProvider(
      sources: [source],
      permission: CalendarPermissionState.granted,
      events: [
        CalendarEventOccurrence(
          sourceId: source.id,
          sourceEventId: 'board-design-event',
          occurrenceId: 'board-design-event-today',
          eventIdentity: 'board-design-event-today',
          title: '设计评审',
          startsAt: DateTime(now.year, now.month, now.day, 14),
          endsAt: DateTime(now.year, now.month, now.day, 15),
          allDay: false,
          availability: CalendarAvailability.busy,
          timeZoneId: source.timeZoneId,
        ),
      ],
    );
    final calendar = LocalCalendarRepository(
      database: database,
      userId: userId,
      provider: calendarProvider,
      remote: InMemoryCalendarRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final semantics = tester.ensureSemantics();
    try {
      final goal = await tasks.createGoal(
        const GoalDraft(
          title: '季度规划',
          description: '每周回顾并调整计划',
          classification: TaskClassification.both,
        ),
      );
      final task = await tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '整理发布材料',
          description: '先核对发布清单',
          classification: TaskClassification.both,
          estimatedMinutes: 30,
        ),
      );
      await tasks.createGoal(
        const GoalDraft(
          title: '待规划目标',
          classification: TaskClassification.regular,
        ),
      );
      // 07/12：看板只保留置顶目标摘要与下一项；目标的完整管理在计划页。
      await tasks.setGoalPinned(goal.id, isPinned: true);
      final session = await focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      now = sessionStart.add(const Duration(minutes: 13));
      await focus.abandonSession(
        sessionId: session.id,
        failureReason: '设备界面验收样例',
      );
      final card = await nationalFocus.createCard(
        const NationalFocusCardDraft(
          name: '开始工作前',
          triggerCondition: '开始工作前',
          action: '写下第一步',
        ),
      );
      await nationalFocus.placeCard(cardId: card.id, parentId: null);
      await nationalFocus.lightCard(card.id);
      await calendar.importCalendars({source.id});

      final initialPixelRatio = tester.view.devicePixelRatio;
      if (!Platform.isWindows) {
        tester.view.physicalSize = Size(
          320 * initialPixelRatio,
          800 * initialPixelRatio,
        );
      }
      await tester.pumpWidget(
        PactaApp(
          authRepository: FakeAuthRepository()..signedInUser = userId,
          taskRepositoryFactory: (_) => tasks,
          focusRepositoryFactory: (_) => focus,
          nationalFocusRepositoryFactory: (_) => nationalFocus,
          calendarRepositoryFactory: (_) => calendar,
          displayClock: () => now,
          cloudCheckClock: () => now,
        ),
      );
      await tester.pumpAndSettle();

      Finder navigation() => find.byWidgetPredicate(
        (widget) => widget is NavigationBar || widget is NavigationRail,
      );
      Future<void> openDestination(String label) async {
        await tester.tap(
          find.descendant(of: navigation(), matching: find.text(label)),
        );
        await tester.pumpAndSettle();
      }

      Finder boardScrollable() => find
          .descendant(
            of: find.byType(BoardPage),
            matching: find.byType(Scrollable),
          )
          .first;

      // 1. 看板是只读摘要：置顶目标 + 下一项，不再渲染完整目标卡与任务列。
      expect(find.byType(BoardPage), findsOneWidget);
      // 单栏顶槽默认页签由国策状态决定：切到置顶目标后摘要与「下一项」才可见。
      // 单栏才有顶槽胶囊：宽屏双栏的置顶摘要本来就在左栏，不能去找胶囊。
      final boardPinnedTab = find.byKey(
        const ValueKey('board-top-slot-pinned'),
      );
      if (boardPinnedTab.evaluate().isNotEmpty) {
        await tester.scrollUntilVisible(
          boardPinnedTab,
          250,
          scrollable: boardScrollable(),
        );
        await tester.pumpAndSettle();
        await tester.tap(boardPinnedTab);
        await tester.pumpAndSettle();
      }
      // 「看板」同时出现在导航与页头：只认页头里的那一处。
      expect(
        find.descendant(
          of: find.byType(PactaPageHeader),
          matching: find.text('看板'),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('下一项：整理发布材料'),
        250,
        scrollable: boardScrollable(),
      );
      await tester.pumpAndSettle();
      expect(find.text('季度规划'), findsOneWidget);
      expect(find.text('下一项：整理发布材料'), findsOneWidget);
      expect(find.text('整理发布材料'), findsNothing);
      expect(find.text('先核对发布清单'), findsNothing);
      expect(find.textContaining('项任务'), findsNothing);
      expect(find.text('添加任务'), findsNothing);
      expect(find.byKey(ValueKey('goal-header-${goal.id}')), findsNothing);
      expect(find.text('设计评审'), findsNothing);
      expect(find.text('日历块'), findsNothing);
      expect(find.text('显示时区'), findsNothing);
      expect(find.textContaining('检查点'), findsNothing);
      expect(find.textContaining('固定规则为北京时间'), findsNothing);

      // 国策状态与近 7 天活动已融合为一张「专注与国策」卡片。
      await tester.scrollUntilVisible(
        find.text('专注与国策'),
        250,
        scrollable: boardScrollable(),
      );
      await tester.pumpAndSettle();
      expect(find.text('专注与国策'), findsOneWidget);
      expect(find.text('今日国策状态'), findsOneWidget);
      expect(find.text('点击查看国策树及具体节点状态 →'), findsOneWidget);
      expect(find.text('13分00秒'), findsOneWidget);
      // 完整月历二级页已删除：日期详情不再有「完整月历 →」入口，年月仍
      // 只在热力月历的切换器里出现一次。
      expect(
        find.byKey(const ValueKey('board-focus-open-month')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('board-focus-month-entry')),
        findsNothing,
      );
      expect(find.text('专注热力月历'), findsOneWidget);

      // 2. 计划页承担目标与任务的完整管理：折叠、语义与键盘。
      await openDestination('计划');
      expect(find.byType(PlanPage), findsOneWidget);
      await tester.ensureVisible(find.text('季度规划'));
      await tester.pumpAndSettle();
      expect(find.text('置顶目标 · 长按拖动排序'), findsOneWidget);
      expect(find.text('每周回顾并调整计划'), findsOneWidget);
      expect(find.text('整理发布材料'), findsOneWidget);
      expect(find.text('先核对发布清单'), findsOneWidget);
      expect(find.textContaining('1 项任务'), findsOneWidget);
      final goalCard = find.ancestor(
        of: find.text('季度规划'),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.text('季度规划'),
        kind: Platform.isWindows
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
      expect(find.text('整理发布材料'), findsNothing);
      expect(find.text('先核对发布清单'), findsNothing);
      expect(find.text('每周回顾并调整计划'), findsOneWidget);
      expect(
        find.descendant(of: goalCard, matching: find.text('添加任务')),
        findsNothing,
      );
      expect(find.textContaining('1 项任务'), findsOneWidget);
      final header = find.byKey(ValueKey('goal-header-${goal.id}'));
      expect(
        tester.getSemantics(header).flagsCollection.isExpanded,
        Tristate.isFalse,
      );
      for (
        var i = 0;
        i < 80 &&
            tester.getSemantics(header).flagsCollection.isFocused !=
                Tristate.isTrue;
        i++
      ) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(
        tester.getSemantics(header).flagsCollection.isFocused,
        Tristate.isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('整理发布材料'), findsOneWidget);
      // 「添加任务」已归入目标长按菜单首项：卡片底部不再有常驻按钮。
      expect(
        find.descendant(of: goalCard, matching: find.text('添加任务')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('整理发布材料'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('整理发布材料'), findsOneWidget);

      // 3. 回看板：大字窄屏下摘要与近 7 天活动仍可读，且不夹带旧日历块。
      await openDestination('看板');
      {
        final devicePixelRatio = tester.view.devicePixelRatio;
        tester.view.physicalSize = Size(
          360 * devicePixelRatio,
          800 * devicePixelRatio,
        );
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('专注与国策'),
          250,
          scrollable: boardScrollable(),
        );
        await tester.pumpAndSettle();
        expect(find.text('专注与国策'), findsOneWidget);
        expect(find.text('13分00秒'), findsOneWidget);
        expect(find.textContaining('检查点'), findsNothing);
        expect(find.textContaining('固定规则为北京时间'), findsNothing);
        expect(find.text('日历块'), findsNothing);
        expect(find.text('显示时区'), findsNothing);
        expect(find.text('设计评审'), findsNothing);
        // 大字窄屏单栏：顶槽默认可能是国策状态，先切到置顶目标（若已
        // 在该页签则无变化）再核对摘要与下一项。
        final pinnedTab = find.byKey(const ValueKey('board-top-slot-pinned'));
        if (pinnedTab.evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            pinnedTab,
            -250,
            scrollable: boardScrollable(),
          );
          await tester.pumpAndSettle();
          await tester.tap(pinnedTab);
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(
          find.text('季度规划'),
          -250,
          scrollable: boardScrollable(),
        );
        await tester.pumpAndSettle();
        expect(find.text('季度规划'), findsOneWidget);
        expect(find.text('下一项：整理发布材料'), findsOneWidget);
        expect(find.text('添加任务'), findsNothing);
        expect(find.byKey(ValueKey('goal-header-${goal.id}')), findsNothing);
      }
      expect(tester.takeException(), isNull);
      const pause = int.fromEnvironment('BOARD_INSPECTION_SECONDS');
      if (pause > 0) {
        tester.view.resetPhysicalSize();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('季度规划'),
          -250,
          scrollable: boardScrollable(),
        );
        binding.framePolicy =
            LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
        binding.shouldPropagateDevicePointerEvents = true;
        await tester.pump();
        debugPrint('ISSUE65_INSPECTION_READY');
        await tester.runAsync(
          () => Future<void>.delayed(Duration(seconds: pause)),
        );
      }
      binding.framePolicy =
          LiveTestWidgetsFlutterBindingFramePolicy.fadePointers;
      binding.shouldPropagateDevicePointerEvents = false;
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.view.resetPhysicalSize();
      await tester.pumpAndSettle();

      // 4. 我的：一级入口仍在；系统日历入口可进入。账号显示时区已迁到
      // 资料编辑页（只读夹具不触碰真实资料），这里只核对可读入口。
      await openDestination('我的');
      expect(find.byType(MyPage), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('通知与设备权限'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(MyPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('通知与设备权限'), findsOneWidget);
      await tester.tap(find.text('通知与设备权限'));
      await tester.pumpAndSettle();
      // 系统日历导入已并入《通知与设备权限》：从该页的入口进入既有来源页。
      await tester.scrollUntilVisible(
        find.byKey(const Key('open-calendar-sources')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-calendar-sources')));
      await tester.pumpAndSettle();
      expect(find.text('系统日历导入'), findsOneWidget);
      if (Platform.isAndroid) {
        expect(find.text('已允许读取日历'), findsOneWidget);
      } else {
        expect(find.text('Windows 暂不支持读取系统日历'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
    } finally {
      semantics.dispose();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      tester.view.resetPhysicalSize();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await focus.dispose();
      await nationalFocus.dispose();
      await calendar.dispose();
      await database.close();
    }
  });
}

/// Same offline AppShell/repository seam as the original device acceptance above.
void _boardPilot(IntegrationTestWidgetsFlutterBinding binding) {
  testWidgets('看板任务列长内容与独立操作', (tester) async {
    const userId = 'board-task-pilot';
    const scenario = String.fromEnvironment('FOCUS_PILOT_SCENARIO');
    const view = String.fromEnvironment(
      'FOCUS_PILOT_VIEW',
      defaultValue: 'wide',
    );
    const directory = String.fromEnvironment('FOCUS_PILOT_DIR');
    const light = bool.fromEnvironment('FOCUS_PILOT_LIGHT');
    final database = PactaDatabase(NativeDatabase.memory());
    final remote = InMemoryFocusRemote();
    var now = DateTime(2026, 11, 12, 10);
    var taskNow = now;
    final tasks = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: InMemoryTaskRemote(),
      now: () {
        final timestamp = taskNow;
        taskNow = taskNow.add(const Duration(seconds: 1));
        return timestamp;
      },
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: remote,
      now: () => now,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: userId,
      cloudSyncEnabled: false,
      now: () => now,
    );
    final boundaryKey = GlobalKey();
    const goalTitle = '季度发布前需要逐项核实的产品规划与跨团队验收目标';
    const taskTitle = '整理发布清单并核对跨团队交付材料的长中文任务';
    const description = '先检查所有版本说明、截图和待确认事项，再联系相关人员完成最终核对';
    var androidReady = false;
    Future<void> shot(String state) async {
      final name = 'board-$scenario-$view-$state';
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      debugPrint(
        '[board-pilot] $state logical=$size boardWidth=${tester.getSize(find.byType(BoardPage)).width} dpr=${tester.view.devicePixelRatio} textScale=1.0 light=$light',
      );
      if (Platform.isAndroid) {
        if (!androidReady) {
          debugPrint('[board-capture] convert begin');
          await binding.convertFlutterSurfaceToImage().timeout(
            const Duration(seconds: 20),
          );
          debugPrint('[board-capture] convert done');
          // Surface conversion needs a new scene even when the UI is idle.
          (boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .markNeedsPaint();
          await tester.pumpAndSettle();
          androidReady = true;
        }
        debugPrint('[board-capture] screenshot begin');
        await binding.takeScreenshot(name).timeout(const Duration(seconds: 20));
        debugPrint('[board-capture] screenshot done');
      } else {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = File('build/ui-layout-evidence/$directory/$name.png');
        if (await file.exists()) fail('Refusing to overwrite ${file.path}');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
      }
    }

    Future<void> click(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(
        finder,
        kind: Platform.isWindows
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
      );
      await tester.pumpAndSettle();
    }

    /// 按住原地不动：目标/任务的管理动作都在操作面板里。
    Future<void> holdItem(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(finder),
        kind: Platform.isWindows
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
        buttons: kPrimaryButton,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    try {
      final support = scenario == 'default' || scenario == 'few';
      if (scenario != 'zero') {
        final goal = await tasks.createGoal(
          GoalDraft(
            title: scenario == 'few' ? '今日目标' : goalTitle,
            description: description,
            classification: TaskClassification.both,
          ),
        );
        final task = await tasks.createTask(
          goal.id,
          TaskDraft(
            title: scenario == 'few' ? '准备材料' : taskTitle,
            description: description,
            estimatedMinutes: 120,
            deadline: DateTime(2026, 11, 15, 18, 30),
            classification: TaskClassification.both,
          ),
        );
        // 看板只显示置顶摘要：让长标题以「下一项」形式进入摘要。
        await tasks.setGoalPinned(goal.id, isPinned: true);
        if (scenario != 'few') {
          final done = await tasks.createTask(
            goal.id,
            const TaskDraft(
              title: '已完成的资料校对',
              estimatedMinutes: 25,
              classification: TaskClassification.regular,
            ),
          );
          await tasks.setTaskCompletion(done.id, isComplete: true);
          await tasks.createTask(
            goal.id,
            const TaskDraft(
              title: '准备下一轮发布',
              classification: TaskClassification.regular,
            ),
          );
          await tasks.createGoal(
            const GoalDraft(
              title: '待规划目标',
              classification: TaskClassification.regular,
            ),
          );
        }
        FocusSession session(
          String id,
          int hour,
          FocusRecordDisposition disposition, [
          int day = 11,
        ]) {
          final start = DateTime(2026, 11, day, hour);
          final end = start.add(const Duration(minutes: 13));
          return FocusSession(
            id: id,
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
          );
        }

        // 测试阶段不再保留多端 pendingReview 语义：只灌当前设备可见的
        // 已接受记录，看板/专注链的基线由 beforeOpen 的本地状态决定。
        if (support) {
          await remote.upsertSessions(
            userId: userId,
            sessions: [
              for (var day = 0; day < (scenario == 'few' ? 1 : 7); day++)
                session(
                  'support-$day',
                  8,
                  FocusRecordDisposition.accepted,
                  12 - day,
                ),
            ],
          );
          final card = await tree.createCard(
            const NationalFocusCardDraft(
              name: '开始前先写一步',
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
        await focus.settleDueSessions();
      }
      final logical = Platform.isAndroid
          ? const Size(411, 731)
          : view == 'narrow'
          ? const Size(546, 682)
          : const Size(1265, 682);
      const hold = int.fromEnvironment('FOCUS_PILOT_HOLD_SECONDS');
      // Native Android screenshots require the render viewport to match the
      // actual ImageView surface, including its fractional logical dimensions.
      if (Platform.isAndroid || (Platform.isWindows && hold > 0)) {
        tester.view.resetPhysicalSize();
      } else {
        tester.view.physicalSize = logical * tester.view.devicePixelRatio;
      }
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      tester.platformDispatcher.platformBrightnessTestValue = light
          ? Brightness.light
          : Brightness.dark;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = userId,
            taskRepositoryFactory: (_) => tasks,
            focusRepositoryFactory: (_) => focus,
            nationalFocusRepositoryFactory: (_) => tree,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final androidManual = Platform.isAndroid && hold > 0;
      if (androidManual) {
        // As in the accepted focus pilot, retain the native surface for actual
        // system touch input. Convert to screenshot ImageView only after hold.
        debugPrint(
          '[board-pilot] manual-expanded hold=${hold}s nativeSurface=true',
        );
        final previous = binding.shouldPropagateDevicePointerEvents;
        binding.shouldPropagateDevicePointerEvents = true;
        debugPrint('BOARD_PILOT_INSPECTION_READY');
        try {
          final deadline = DateTime.now().add(Duration(seconds: hold));
          while (DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 100));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
          }
        } finally {
          binding.shouldPropagateDevicePointerEvents = previous;
        }
        await tester.pumpAndSettle();
        await shot('after-hold');
      } else {
        await shot('expanded');
      }
      if (hold > 0 && !androidManual) {
        binding.framePolicy =
            LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
        binding.shouldPropagateDevicePointerEvents = true;
        await tester.pump();
        debugPrint('BOARD_PILOT_INSPECTION_READY');
        await tester.runAsync(() async {
          var lastSize = tester.view.physicalSize;
          var capture = 0;
          for (var elapsed = 0; elapsed < hold; elapsed += 2) {
            await Future<void>.delayed(const Duration(seconds: 2));
            final size = tester.view.physicalSize;
            if (Platform.isWindows && size != lastSize) {
              lastSize = size;
              await shot('native-${capture++}');
            }
          }
        });
        binding.shouldPropagateDevicePointerEvents = false;
        binding.framePolicy =
            LiveTestWidgetsFlutterBindingFramePolicy.fadePointers;
      }
      if (const bool.fromEnvironment('FOCUS_DESIGN_SNAPSHOT_ONLY')) return;
      // 看板只保留摘要：置顶目标 + 融合卡（今日国策、热力月历、日期详情
      // 与只读安排）。今天安排不再是独立卡片。
      final boardScrollable = find
          .descendant(
            of: find.byType(BoardPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('专注与国策'),
        200,
        scrollable: boardScrollable,
      );
      await tester.pumpAndSettle();
      // 默认页签可能是置顶目标：截图前先固定到国策状态，断言才确定。
      final statusTab = find.byKey(const ValueKey('board-top-slot-status'));
      if (statusTab.evaluate().isNotEmpty) {
        await tester.tap(statusTab);
        await tester.pumpAndSettle();
      }
      await shot('support');
      expect(find.text('今日国策状态'), findsOneWidget);
      if (scenario == 'zero') {
        // 没有置顶目标时整套置顶区块（标题、管理入口、空卡片）都不渲染，
        // 融合卡直接贴着页头。
        expect(find.text('置顶目标'), findsNothing);
        expect(find.text('还没有置顶目标'), findsNothing);
        expect(find.text('专注与国策'), findsOneWidget);
      } else {
        // 单栏：置顶摘要在顶槽胶囊后面；宽屏：左栏本来就直接可见。
        final pinnedTab = find.byKey(const ValueKey('board-top-slot-pinned'));
        final statusTab = find.byKey(const ValueKey('board-top-slot-status'));
        if (pinnedTab.evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(
            pinnedTab,
            -250,
            scrollable: boardScrollable,
          );
          await tester.pumpAndSettle();
          await tester.tap(pinnedTab);
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('下一项：'), findsOneWidget);
        // 回到国策状态，后面的今日卡入口仍可直接点击。
        if (statusTab.evaluate().isNotEmpty) {
          await tester.tap(statusTab);
          await tester.pumpAndSettle();
        }
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('board-today-national-focus')),
        250,
        scrollable: boardScrollable,
      );
      await click(find.byKey(const ValueKey('board-today-national-focus')));
      expect(find.byTooltip('更多'), findsOneWidget);
      final navigation = find.byType(NavigationRail).evaluate().isNotEmpty
          ? find.byType(NavigationRail)
          : find.byType(NavigationBar);
      await click(find.descendant(of: navigation, matching: find.text('看板')));
      await tester.scrollUntilVisible(
        find.descendant(
          of: find.byType(PactaPageHeader),
          matching: find.text('看板'),
        ),
        -250,
        scrollable: boardScrollable,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(PactaPageHeader),
          matching: find.text('看板'),
        ),
        findsOneWidget,
      );
      if (scenario == 'zero') return;
      // 目标的完整管理在计划页：复核长标题、折叠与取消路径。
      await click(find.text('打开计划'));
      expect(find.byType(PlanPage), findsOneWidget);
      await tester.ensureVisible(find.text(goalTitle));
      await tester.pumpAndSettle();
      expect(find.text(goalTitle), findsOneWidget);
      expect(find.text(taskTitle), findsOneWidget);
      // 目标卡不再有内联编辑按钮：按住卡片原位不动打开操作面板。
      await holdItem(find.text(goalTitle));
      await click(find.text('编辑目标'));
      await click(find.text('取消'));
      await click(find.text(goalTitle));
      expect(find.text(taskTitle), findsNothing);
      await shot('collapsed');
      await click(find.text(goalTitle));
      await tester.ensureVisible(find.text(taskTitle));
      await tester.pumpAndSettle();
      expect(find.text(taskTitle), findsOneWidget);
      await click(find.text(taskTitle));
      await tester.enterText(find.byType(TextField).first, '已保存的任务修改');
      await click(find.text('保存'));
      expect(find.text('已保存的任务修改'), findsOneWidget);
      await click(find.text('已保存的任务修改'));
      await tester.enterText(find.byType(TextField).first, taskTitle);
      await click(find.text('保存'));
      await click(find.byTooltip('开始专注').first);
      expect(find.text('开始专注'), findsOneWidget);
      await click(find.text('取消'));
      expect(find.text(taskTitle), findsOneWidget);
      await shot('restored');
      expect(tester.takeException(), isNull);
    } finally {
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await focus.dispose();
      await tree.dispose();
      await database.close();
    }
  });
}
