import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'dart:ui' show Tristate;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
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

import '../test/support/fake_auth_repository.dart';
import '../test/support/fake_calendar_provider.dart';

/// Offline dashboard evidence using an in-memory database and fake auth.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('BOARD_PILOT_MODE')) {
    _boardPilot(binding);
    return;
  }

  testWidgets('看板层级、目标折叠、我的设置入口与日历访问', (tester) async {
    const userId = 'board-design-offline-fixture';
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime.now().subtract(const Duration(minutes: 13));
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
      final session = await focus.startSession(
        taskId: task.id,
        mode: FocusChainMode.regular,
        duration: const Duration(minutes: 25),
      );
      now = DateTime.now();
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
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('今天先做什么'), findsOneWidget);
      expect(find.text('整理发布材料'), findsOneWidget);
      expect(find.text('每周回顾并调整计划'), findsOneWidget);
      expect(find.text('先核对发布清单'), findsOneWidget);
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
        i < 40 &&
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
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('整理发布材料'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('整理发布材料'), findsOneWidget);
      expect(
        tester.getCenter(find.text('打开国策树')).dy,
        closeTo(tester.getCenter(find.text('国策状态')).dy, 1),
      );
      expect(find.textContaining('检查点'), findsNothing);
      expect(find.textContaining('固定规则为北京时间'), findsNothing);
      expect(find.text('日历块'), findsNothing);
      expect(find.text('显示时区'), findsNothing);
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
          find.text('近期专注活动'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('近期专注活动'), findsOneWidget);
        expect(find.textContaining('累计有效专注 13分00秒'), findsOneWidget);
        expect(find.textContaining('检查点'), findsNothing);
        expect(find.textContaining('固定规则为北京时间'), findsNothing);
        expect(find.text('日历块'), findsNothing);
        expect(find.text('显示时区'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('设计评审'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('设计评审'), findsOneWidget);
        await tester.scrollUntilVisible(
          header,
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(find.text('整理发布材料'), findsNothing);
        expect(find.text('每周回顾并调整计划'), findsOneWidget);
        await tester.tap(header);
        await tester.pumpAndSettle();
        expect(find.text('整理发布材料'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('待规划目标'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('待规划目标'));
        await tester.pumpAndSettle();
        expect(find.text('暂无任务，先添加一个可执行的下一步。'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      const pause = int.fromEnvironment('BOARD_INSPECTION_SECONDS');
      if (pause > 0) {
        tester.view.resetPhysicalSize();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('季度规划'),
          -250,
          scrollable: find.byType(Scrollable).first,
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

      final navigation = find.byWidgetPredicate(
        (widget) => widget is NavigationBar || widget is NavigationRail,
      );
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('我的')),
      );
      await tester.pumpAndSettle();
      expect(find.text('显示时区'), findsOneWidget);
      await tester.tap(find.text('显示时区'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'America/Los_Angeles',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('America/Los_Angeles').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('America/Los_Angeles'), findsOneWidget);

      await tester.tap(find.text('日历块'));
      await tester.pumpAndSettle();
      expect(find.text('工作日历'), findsOneWidget);
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

        await remote.upsertSessions(
          userId: userId,
          sessions: [
            if (!support)
              session('accepted', 9, FocusRecordDisposition.accepted),
            if (!support)
              session('pending', 10, FocusRecordDisposition.pendingReview),
          ],
        );
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
        await focus.sync();
      }
      final logical = Platform.isAndroid
          ? const Size(411, 731)
          : view == 'narrow'
          ? const Size(546, 682)
          : const Size(1265, 682);
      const hold = int.fromEnvironment('FOCUS_PILOT_HOLD_SECONDS');
      // Native Android capture must match the actual ImageView surface.
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
      await shot('expanded');
      if (hold > 0) {
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
      if (support || scenario == 'zero') {
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
        await tester.pumpAndSettle();
        await shot('support');
        expect(find.text('今天没有导入的安排。'), findsOneWidget);
        await click(find.text('打开国策树'));
        expect(find.byTooltip('更多'), findsOneWidget);
        final navigation = find.byType(NavigationRail).evaluate().isNotEmpty
            ? find.byType(NavigationRail)
            : find.byType(NavigationBar);
        await click(find.descendant(of: navigation, matching: find.text('看板')));
        await tester.scrollUntilVisible(
          find.text('今天先做什么'),
          -250,
          scrollable: find
              .descendant(
                of: find.byType(BoardPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.text('今天先做什么'), findsOneWidget);
      } else {
        expect(find.text(taskTitle), findsOneWidget);
        expect(find.textContaining('待核对'), findsWidgets);
        await click(find.text(goalTitle));
        expect(find.text(taskTitle), findsNothing);
        expect(find.text(description), findsOneWidget);
        await shot('collapsed');
        await click(find.byTooltip('编辑目标').first);
        await click(find.text('取消'));
        expect(find.text(taskTitle), findsNothing);
        await click(find.byTooltip('删除目标').first);
        expect(find.textContaining('且不能恢复'), findsOneWidget);
        await click(find.text('取消'));
        expect(find.text(taskTitle), findsNothing);
        await click(find.text(goalTitle));
        await click(find.text(taskTitle));
        final titleField = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '任务名称',
        );
        // Existing editor labels are verified by the public visible field value.
        final field = titleField.evaluate().isNotEmpty
            ? titleField
            : find.byType(TextField).first;
        await tester.enterText(field, '取消时不保存');
        await click(find.text('取消'));
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
      }
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
