// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/chain_signals_repository.dart';
import 'package:pacta/src/focus/focus_models.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart'
    show NationalFocusTreePage;
import 'package:pacta/src/notifications/focus_notification_settings_page.dart'
    show FocusNotificationSettingsPage;
import 'package:pacta/src/schedules/schedule_models.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/ui/pacta_check_circle.dart';
import 'package:pacta/src/ui/pacta_page_header.dart';

import '../test/support/fake_auth_repository.dart';

/// 离线基线截图：只读本机 fixture，不写云、不读凭据。
const _dir = String.fromEnvironment(
  'UI_BASELINE_DIR',
  defaultValue: 'ui-baseline/current',
);

/// `matrix`：桌面端按 360/411/1280 × 亮暗 × 1.0/2.0 逐格截图；
/// `device`：移动端只按设备自身窗口截亮暗与两种字号。
const _mode = String.fromEnvironment(
  'UI_BASELINE_MODE',
  defaultValue: 'device',
);

const _seedTaskTitle = '阅读一章，留下三个要点';

const _pages = String.fromEnvironment(
  'UI_BASELINE_PAGES',
  defaultValue: 'focus,plan-goals,plan-calendar,my',
);

const _sizes = <Size>[
  Size(320, 568),
  Size(360, 800),
  Size(411, 731),
  Size(1280, 800),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('四目的地亮暗与字号基线截图', (tester) async {
    const userId = 'ui-baseline-offline-fixture';
    final database = PactaDatabase(NativeDatabase.memory());
    var now = DateTime(2026, 11, 18, 9);
    final tasks = LocalTaskRepository(
      database: database,
      userId: userId,
      remote: InMemoryTaskRemote(),
      cloudSyncEnabled: false,
    );
    final focus = LocalFocusRepository(
      database: database,
      userId: userId,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
      now: () => now,
    );
    final tree = LocalNationalFocusRepository(
      database: database,
      userId: userId,
      cloudSyncEnabled: false,
      // 与其余 fixture 共用同一个注入时钟：国策检查点结算不能落到真实今天。
      now: () => now,
    );
    final signals = ChainSignalsRepository(database: database, userId: userId);
    final schedules = LocalScheduleRepository(
      database: database,
      userId: userId,
      now: () => now,
    );
    await signals.save(
      const ChainSignalTexts(
        focusMarker: '戴上耳机，坐到书桌前',
        appointmentTriggerSignal: '合上手机，倒一杯水',
      ),
    );
    await focus.createPrecedentRule(text: '允许短暂起身接水');
    await focus.createPrecedentRule(text: '允许查询与本次任务相关的资料');
    final goal = await tasks.createGoal(
      const GoalDraft(
        title: '把重要的事情向前推进',
        classification: TaskClassification.both,
      ),
    );
    final task = await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: _seedTaskTitle,
        classification: TaskClassification.both,
        estimatedMinutes: 30,
      ),
    );
    await tasks.createTask(
      goal.id,
      const TaskDraft(
        title: '梳理明天的计划',
        classification: TaskClassification.regular,
        estimatedMinutes: 15,
      ),
    );
    // Phase 3：第二个目标带单行描述，与无描述的种子目标形成对照，收起态
    // 上下内边距与展开态头部末行间距在双端截图里都有真实样本。
    final weeklyGoal = await tasks.createGoal(
      const GoalDraft(
        title: '每周体能与休息',
        description: '保证作息与运动节奏',
        classification: TaskClassification.regular,
      ),
    );
    await tasks.createTask(
      weeklyGoal.id,
      const TaskDraft(
        title: '慢跑 30 分钟',
        classification: TaskClassification.regular,
        estimatedMinutes: 30,
      ),
    );
    // Phase 5：第三个目标补齐「3 个置顶目标」样本——单栏顶槽只展示前两条并
    // 给出「查看全部 3 个 →」出口，宽屏左栏则完整列出三条置顶摘要。三个目标
    // 都各有未完成任务，顶槽里的「下一项」因此都是真实任务而不是占位文案。
    final reviewGoal = await tasks.createGoal(
      const GoalDraft(
        title: '每周复盘与下一步',
        description: '周五留出复盘时间',
        classification: TaskClassification.regular,
      ),
    );
    await tasks.createTask(
      reviewGoal.id,
      const TaskDraft(
        title: '写下本周的三个观察',
        classification: TaskClassification.regular,
        estimatedMinutes: 20,
      ),
    );
    // 置顶顺序就是顶槽展示顺序：主目标第一、周目标第二，复盘目标只在出口里。
    for (final pinnedGoal in [goal, weeklyGoal, reviewGoal]) {
      await tasks.setGoalPinned(pinnedGoal.id, isPinned: true);
    }
    // Phase 4：11 月 12 日的一条 90 分钟已完成专注，正好落在 heat3 深绿档。
    // 它必须按时间顺序先结算，再进入 11 月 18 日的一批会话，这样看板月历
    // 上同时存在「深绿 + 带隔离光晕的珊瑚红细短杠」的真实样本。
    now = DateTime(2026, 11, 12, 8);
    await focus.startSession(
      taskId: task.id,
      mode: FocusChainMode.regular,
      duration: const Duration(minutes: 90),
    );
    now = now.add(const Duration(minutes: 90));
    await focus.settleDueSessions();
    // Phase 5：11 月 17 日的精锐链时间轴样本——先完成一条（#1），再主动放弃
    // 一条并写明一句失败原因（断链）。11 月 18 日随后完成三条，历史因此回放
    // 成 #1 -> 断链 -> #1 -> #2 -> #3；最新一段没有被断，当前连击仍是 3。
    now = DateTime(2026, 11, 17, 8);
    await focus.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 25),
    );
    now = now.add(const Duration(minutes: 25));
    await focus.settleDueSessions();
    final abandonedElite = await focus.startSession(
      taskId: task.id,
      mode: FocusChainMode.elite,
      duration: const Duration(minutes: 25),
    );
    now = now.add(const Duration(minutes: 5));
    await focus.abandonSession(
      sessionId: abandonedElite.id,
      failureReason: '被临时会议叫走，主动结束这一轮',
    );
    now = DateTime(2026, 11, 18, 9);
    for (final mode in [FocusChainMode.elite, FocusChainMode.regular]) {
      for (var round = 0; round < 3; round++) {
        await focus.startSession(
          taskId: task.id,
          mode: mode,
          duration: const Duration(minutes: 25),
        );
        now = now.add(const Duration(minutes: 25));
        await focus.settleDueSessions();
      }
    }
    final todaySchedule = await schedules.createSchedule(
      ScheduleDraft(
        title: '与设计评审对齐专注链层级',
        window: ScheduleWindow.timed(
          startsAt: DateTime(2026, 11, 18, 10),
          endsAt: DateTime(2026, 11, 18, 11),
        ),
        taskId: task.id,
      ),
    );
    await schedules.createSchedule(
      ScheduleDraft(
        title: '明天下午的复盘',
        window: ScheduleWindow.timed(
          startsAt: DateTime(2026, 11, 19, 10),
          endsAt: DateTime(2026, 11, 19, 11),
        ),
      ),
    );
    final completedSchedule = await schedules.createSchedule(
      ScheduleDraft(
        title: '已经完成的整理',
        window: ScheduleWindow.timed(
          startsAt: DateTime(2026, 11, 16, 10),
          endsAt: DateTime(2026, 11, 16, 11),
        ),
      ),
    );
    await schedules.setScheduleCompletion(
      completedSchedule.id,
      isCompleted: true,
    );
    // Phase 3：国策树样本——根节点点亮、子节点未点亮（即熄灭态），看板顶部
    // 因此显示「点亮 1 / 待确认 0 / 熄灭 1」，国策树页也有真实分支而不是空态
    // 引导。两张卡都在同一个检查点窗口内，不跨天结算。
    final rootNationalFocus = await tree.createCard(
      const NationalFocusCardDraft(
        name: '根国策',
        triggerCondition: '打开今天的待办清单',
        action: '坐到书桌前先写下今天的第一步。',
      ),
    );
    await tree.placeCard(cardId: rootNationalFocus.id, parentId: null);
    await tree.lightCard(rootNationalFocus.id);
    final childNationalFocus = await tree.createCard(
      const NationalFocusCardDraft(
        name: '开始前写第一步',
        triggerCondition: '每次开始专注之前',
        action: '先写下一句话的目标，再决定这件事是否值得 25 分钟。',
      ),
    );
    await tree.placeCard(
      cardId: childNationalFocus.id,
      parentId: rootNationalFocus.id,
    );
    // Phase 5：树上的第三张卡承载「已内化」——成功天数跨过 180 天门槛后，详细
    // 视图胶囊行出现「已内化」微标；同一画布里根节点靠更粗的等宽外框区分，
    // 卡片无顶部状态条、规则最多三行，熄灭子节点保留灰态。它保持点亮，所以看板
    // 顶部计数是「点亮 2 / 待确认 0 / 熄灭 1」：待确认仍为 0，顶槽默认页签
    // 不会被这张卡改写，单栏胶囊的两种页签都能各截一张。
    final internalizedNationalFocus = await tree.createCard(
      const NationalFocusCardDraft(
        name: '每天先复盘再开始',
        triggerCondition: '每天开始工作之前',
        action: '先用五分钟写下昨天的复盘，再决定今天的第一件事。',
      ),
    );
    await tree.placeCard(
      cardId: internalizedNationalFocus.id,
      parentId: rootNationalFocus.id,
    );
    await tree.lightCard(internalizedNationalFocus.id);
    // 成功天数只由真实推进写入；这里直接落到 180 天门槛，让「已内化」微标与
    // 180 天连击在同一张真实卡片上同时可见（详细视图两行规则照常渲染）。
    await (database.update(database.localNationalFocusCards)
          ..where((row) => row.userId.equals(userId))
          ..where((row) => row.id.equals(internalizedNationalFocus.id)))
        .write(
          LocalNationalFocusCardsCompanion(
            state: Value(NationalFocusCardState.lit.storageValue),
            successfulDays: const Value(180),
            currentConsecutiveDays: const Value(180),
            bestConsecutiveDays: const Value(180),
          ),
        );
    // Phase 4：三条已回顾（reviewedAt 非空）的历史国策失败记录，检查点落在
    // 11 月 12 / 14 / 16 日（04:00Z = 上海当天 12:00，与看板按账号时区归日
    // 的规则一致）。字段与 LocalNationalFocusFailures 完全一一对应，树快照
    // 与 _failureFromRow 的读取顺序一致；reviewedAt 已回填，所以真实设备
    // 看板截图不会出现顶栏「待回顾」提醒。配合上面的 90 分钟会话，同一张
    // 月历上可以同时目检 5 种格态。
    final childSnapshot = jsonEncode([
      <String, Object?>{
        'id': childNationalFocus.id,
        'name': '开始前写第一步',
        'triggerCondition': '每次开始专注之前',
        'action': '先写下一句话的目标，再决定这件事是否值得 25 分钟。',
        'effectiveTriggerCondition': '每次开始专注之前',
        'effectiveAction': '先写下一句话的目标，再决定这件事是否值得 25 分钟。',
        'activeStrengtheningLevel': 0,
        'iconKey': null,
        'scope': null,
        'exceptionNotes': null,
        'isInTree': true,
        'parentId': rootNationalFocus.id,
        'state': NationalFocusCardState.pendingTodayConfirmation.storageValue,
        'successfulDays': 0,
        'currentConsecutiveDays': 0,
        'bestConsecutiveDays': 0,
        'maintenanceCycleStarted': true,
        'failureReason': null,
        'cascadeSourceCardId': null,
        'cascadePriorState': null,
        'failureSourceCardId': null,
        'createdAt': childNationalFocus.createdAt.toUtc().toIso8601String(),
        'updatedAt': childNationalFocus.updatedAt.toUtc().toIso8601String(),
      },
    ]);
    for (final day in const [12, 14, 16]) {
      await database
          .into(database.localNationalFocusFailures)
          .insert(
            LocalNationalFocusFailuresCompanion.insert(
              userId: userId,
              id: 'ui-baseline-failure-202611$day',
              batchId: 'ui-baseline-batch-202611$day',
              cardId: childNationalFocus.id,
              checkpointAt: DateTime.utc(2026, 11, day, 4),
              cause: NationalFocusFailureCause.missedConfirmation.storageValue,
              failureReason: const Value(null),
              sharedExplanation: const Value(null),
              treeSnapshot: childSnapshot,
              reviewedAt: Value(now),
            ),
          );
    }

    final boundaryKey = GlobalKey();
    var androidSurfaceReady = false;
    Future<void> shot(String name) async {
      if (Platform.isAndroid) {
        if (!androidSurfaceReady) {
          await binding.convertFlutterSurfaceToImage();
          await tester.pump();
          androidSurfaceReady = true;
        }
        await binding.takeScreenshot(name);
      } else {
        final object = boundaryKey.currentContext?.findRenderObject();
        if (object is! RenderRepaintBoundary) {
          fail('screenshot "$name": repaint boundary not found');
        }
        final image = await object.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data == null) fail('screenshot "$name": PNG encoding failed');
        final directory = Directory('build/ui-layout-evidence/$_dir');
        await directory.create(recursive: true);
        final file = File('${directory.path}/$name.png');
        if (await file.exists()) {
          fail('screenshot "$name": refusing to overwrite');
        }
        await file.writeAsBytes(data.buffer.asUint8List());
      }
      print('[ui-baseline] shot=$name dir=$_dir');
    }

    // 桌面窗口被遮挡时 pumpAndSettle 可能等不到新帧；固定推进两帧更稳。
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    Future<void> openDestination(String label) async {
      final bar = find.byType(NavigationBar);
      final rail = find.byType(NavigationRail);
      final host = bar.evaluate().isNotEmpty ? bar : rail;
      await tester.tap(find.descendant(of: host, matching: find.text(label)));
      await settle();
    }

    /// 零时长滚动到目标：不等待动画帧，避免桌面窗口被遮挡时 pump 卡住。
    Future<void> reveal(Finder finder) async {
      await Scrollable.ensureVisible(
        tester.element(finder),
        duration: Duration.zero,
      );
      await settle();
    }

    Future<void> tapDay(String ymd) async {
      final finder = find.byKey(ValueKey('plan-day-$ymd'));
      await reveal(finder);
      await tester.tap(finder);
      await settle();
    }

    Future<void> resetCalendarScroll() async {
      await reveal(find.byKey(const ValueKey('plan-month-label')));
    }

    /// 有限次轮询等待：真实设备上的平台通道（视图偏好、设备通知权限）、路由
    /// 动画与数据流都是异步的，桌面窗口被遮挡时又不能用 pumpAndSettle。超时
    /// 直接按截图契约失败，绝不静默跳过让基线缺口混过去。
    Future<void> waitFor(Finder finder, {required String reason}) async {
      for (var attempt = 0; attempt < 40; attempt++) {
        if (finder.evaluate().isNotEmpty) return;
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(finder, findsWidgets, reason: reason);
    }

    /// 等瞬时提示消失（例如「正在更新视图…」），过渡态不写进基线。
    Future<void> waitUntilGone(Finder finder) async {
      for (var attempt = 0; attempt < 40; attempt++) {
        if (finder.evaluate().isEmpty) return;
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    /// 等到加载菊花消失、[content] 已经渲染：Android 真机上隔离库的异步
    /// 读取晚于桌面，固定 350ms 会截到 CircularProgressIndicator。最多轮询
    /// 5 秒，超时按截图契约失败，绝不把加载态悄悄写进基线。
    Future<void> waitUntilLoaded(
      Finder content, {
      required String reason,
    }) async {
      for (var attempt = 0; attempt < 50; attempt++) {
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
            content.evaluate().isNotEmpty) {
          return;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: reason,
      );
      expect(content, findsWidgets, reason: reason);
    }

    /// 把包含 [descendant] 的滚动容器拉回顶部。
    ///
    /// 五个目的地由 IndexedStack 常驻，切换目的地不会重置各页自己的滚动
    /// 位置：进过二级页再回来时必须显式复位，否则矩阵下一轮的同名截图会带
    /// 上上一轮的偏移。
    Future<void> scrollToTop(Finder descendant) async {
      final scrollable = find.ancestor(
        of: descendant,
        matching: find.byType(Scrollable),
      );
      if (scrollable.evaluate().isEmpty) return;
      final state = tester.state<ScrollableState>(scrollable.first);
      if (state.position.pixels == state.position.minScrollExtent) return;
      state.position.jumpTo(state.position.minScrollExtent);
      await settle();
    }

    /// 专注历史正文：有记录时是链式时间轴，没有记录时是空态；两者都算
    /// 「页面已加载完成」，加载菊花不在此列。
    Finder historyContent() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      if (key is! ValueKey<String>) return false;
      return key.value == 'focus-history-timeline' ||
          key.value == 'focus-history-empty';
    });

    /// 国策树节点：简洁视图是 national-focus-node-*，详细视图是
    /// national-focus-card-*，两种都算「树已渲染」。
    Finder nationalTreeNode() => find.byWidgetPredicate((widget) {
      final key = widget.key;
      if (key is! ValueKey<String>) return false;
      return key.value.startsWith('national-focus-node-') ||
          key.value.startsWith('national-focus-card-');
    });

    /// 国策视图偏好菜单：整个应用只有国策树页有 PopupMenuButton<bool>，
    /// 这里仍按页面收敛，避免以后别的页面加同类菜单时取到错误的那个。
    Finder nationalViewMenu() => find.descendant(
      of: find.byType(NationalFocusTreePage),
      matching: find.byType(PopupMenuButton<bool>),
    );

    Finder nationalViewLabel(String label) =>
        find.descendant(of: nationalViewMenu(), matching: find.text(label));

    Future<void> captureAll(String suffix) async {
      final wanted = _pages.split(',').map((page) => page.trim()).toSet();
      const known = {
        'focus',
        'plan-goals',
        'plan-calendar',
        'my',
        'national',
        'board',
      };
      final unknown = wanted.difference(known);
      if (unknown.isNotEmpty) {
        fail('UI_BASELINE_PAGES 含未知页面：${unknown.join(', ')}');
      }
      if (wanted.contains('focus')) {
        await openDestination('专注链');
        await shot('focus-$suffix');
        if (suffix.endsWith('-s1.0')) {
          // Phase 5：专注历史的链式时间轴必须单独成基线——11 月 17 日的
          // #1 -> 断链 与 11 月 18 日的 #1 -> #2 -> #3 在同一条链上回放。
          // 只在 1x 字号追加，2x 不重复膨胀；截完立刻 pop 回专注链。
          final historyEntry = find.byKey(
            const ValueKey('focus-history-entry'),
          );
          await reveal(historyEntry);
          await tester.tap(historyEntry);
          await settle();
          await waitFor(
            find.byType(FocusHistoryPage),
            reason: '点「历史」应进入《专注历史》，截图不得静默跳过',
          );
          await waitUntilLoaded(
            historyContent(),
            reason: '《专注历史》应完成加载并回放出链式时间轴或空态',
          );
          await settle();
          await shot('focus-history-$suffix');
          Navigator.of(tester.element(find.byType(FocusHistoryPage))).pop();
          await settle();
          expect(
            find.byType(FocusHistoryPage),
            findsNothing,
            reason: '截完必须干净返回专注链，矩阵下一轮不得停在历史页',
          );
        }
      }
      if (wanted.contains('plan-goals') || wanted.contains('plan-calendar')) {
        await openDestination('计划');
        if (wanted.contains('plan-goals')) {
          await shot('plan-goals-$suffix');
          final taskTile = find
              .ancestor(
                of: find.text(_seedTaskTitle),
                matching: find.byType(ListTile),
              )
              .first;
          final taskCheck = find.descendant(
            of: taskTile,
            matching: find.byType(PactaCheckCircle),
          );
          await reveal(taskCheck);
          await tester.tap(taskCheck);
          await settle();
          await shot('plan-goals-checked-$suffix');
          await tester.tap(taskCheck);
          await settle();
          // Phase 3：第二个目标带单行描述——收起后上下内边距严格对称，头部
          // 末行到首条任务的间距与无描述目标一致。独立后缀，不覆盖既有基线。
          final weeklyHeader = find.byKey(
            ValueKey('goal-header-${weeklyGoal.id}'),
          );
          await reveal(weeklyHeader);
          await tester.tap(weeklyHeader);
          await settle();
          await shot('plan-goals-collapsed-$suffix');
          await tester.tap(weeklyHeader);
          await settle();
          await reveal(find.byType(PactaPageHeader));
        }
        if (wanted.contains('plan-calendar')) {
          await tester.tap(find.text('日历'));
          await settle();
          await shot('plan-calendar-$suffix');
          final scheduleTile = find.byKey(
            ValueKey('schedule-${todaySchedule.id}'),
          );
          expect(
            scheduleTile,
            findsOneWidget,
            reason: '计划日历应显示今日种子安排，截图不得静默跳过',
          );
          final scheduleCheck = find.descendant(
            of: scheduleTile,
            matching: find.byType(PactaCheckCircle),
          );
          await reveal(scheduleCheck);
          await shot('plan-calendar-schedule-unchecked-$suffix');
          await tester.tap(scheduleCheck);
          await settle();
          await shot('plan-calendar-schedule-checked-$suffix');
          await tester.tap(scheduleCheck);
          await settle();
          // 有安排=黄、全部完成=绿、选中=蓝；选中日 20 无安排，让 16/18/19
          // 的状态同时出现。
          await tapDay('2026-11-20');
          await shot('plan-calendar-day-states-$suffix');
          await tapDay('2026-11-19');
          await shot('plan-calendar-selected-plan-$suffix');
          await tapDay('2026-11-21');
          await shot('plan-calendar-no-plans-$suffix');
          // 选中态移开后，今日只剩描边：两种状态必须仍可分辨。
          await tapDay('2026-11-01');
          await shot('plan-calendar-today-outline-$suffix');
          // 上一个月：10 月是法定节假日最密集的一个月，放假日底色要能判读。
          await reveal(find.byIcon(Icons.chevron_left));
          await tester.tap(find.byIcon(Icons.chevron_left));
          await settle();
          await shot('plan-calendar-holiday-$suffix');
          await reveal(find.byIcon(Icons.chevron_right));
          await tester.tap(find.byIcon(Icons.chevron_right));
          await settle();
          await tapDay('2026-11-18');
          await resetCalendarScroll();
          await tester.tap(find.text('目标'));
          await settle();
        }
      }
      if (wanted.contains('my')) {
        await openDestination('我的');
        await shot('my-$suffix');
        if (suffix.endsWith('-s1.0')) {
          // Phase 5：《通知与设备权限》是设备级设置面，独立截图后干净返回，
          // 并把《我的》滚回顶部，后面的目的地切换与下一轮矩阵都不带偏移。
          final entry = find.text('通知与设备权限');
          await reveal(entry);
          await tester.tap(entry);
          await settle();
          await waitFor(
            find.byType(FocusNotificationSettingsPage),
            reason: '点「通知与设备权限」应进入设备级设置页',
          );
          await waitFor(find.text('后台运行与系统权限'), reason: '设备级设置页应完成权限读取并渲染分组');
          await waitUntilLoaded(
            find.text('后台运行与系统权限'),
            reason: '设备级设置页应完成权限读取，不得截到加载中状态',
          );
          await settle();
          await shot('notifications-$suffix');
          Navigator.of(
            tester.element(find.byType(FocusNotificationSettingsPage)),
          ).pop();
          await settle();
          expect(
            find.byType(FocusNotificationSettingsPage),
            findsNothing,
            reason: '截完必须干净返回《我的》',
          );
          await scrollToTop(find.text('通知与设备权限'));
        }
      }
      if (wanted.contains('national')) {
        await openDestination('国策树');
        await waitFor(
          nationalTreeNode(),
          reason: '国策树应渲染真实节点（根 / 熄灭 / 已内化），不得截成空态',
        );
        await shot('national-$suffix');
        if (suffix.endsWith('-s1.0')) {
          // 默认是简洁视图，详细视图的根徽标、3dp 状态色条与恒两行国策规则
          // 需要一张独立基线。亮暗两轮都跑；离开前把偏好切回进入时的状态，
          // s2.0 与下一轮矩阵因此不会继承详细视图。
          final menu = nationalViewMenu();
          await reveal(menu);
          // 弹层有自己的过渡动画：先让菜单完全展开，再点目标项，绝不在动画
          // 中间点到相邻项。
          Future<void> selectView(String label) async {
            // 偏好读写期间菜单是禁用态：先等「正在更新视图…」消失，再展开。
            await waitUntilGone(find.text('正在更新视图…'));
            await tester.tap(menu);
            await settle();
            await tester.pump(const Duration(milliseconds: 300));
            await waitFor(find.text(label), reason: '国策视图菜单应展开并给出「$label」项');
            await tester.tap(find.text(label).last);
            await settle();
          }

          final startedDetailed = nationalViewLabel('详细视图')
              .evaluate()
              .isNotEmpty;
          if (!startedDetailed) {
            await selectView('详细视图');
          }
          await waitFor(nationalViewLabel('详细视图'), reason: '国策树应切到详细视图');
          await waitUntilGone(find.text('正在更新视图…'));
          await waitFor(
            nationalViewLabel('详细视图'),
            reason: '国策视图偏好写入完成后详细视图应保持选中',
          );
          await shot('national-detailed-$suffix');
          if (!startedDetailed) {
            await selectView('简洁视图');
            await waitFor(
              nationalViewLabel('简洁视图'),
              reason: '离开前应恢复简洁视图偏好，避免污染后续轮次',
            );
            await waitUntilGone(find.text('正在更新视图…'));
          }
        }
      }
      if (wanted.contains('board')) {
        await openDestination('看板');
        await waitFor(
          find.byKey(const ValueKey('board-focus-national-card')),
          reason: '看板融合卡应渲染，截图不得静默跳过',
        );
        await shot('board-$suffix');
        if (suffix.endsWith('-s1.0')) {
          // 单栏顶槽的胶囊切换栏只在有置顶目标（或目标读取失败）时出现；
          // 宽屏两栏把置顶目标交给左栏摘要，顶槽没有胶囊，直接跳过。
          final statusPill = find.byKey(
            const ValueKey('board-top-slot-status'),
          );
          final pinnedPill = find.byKey(
            const ValueKey('board-top-slot-pinned'),
          );
          final hasTopSlotSwitch =
              statusPill.evaluate().isNotEmpty &&
              pinnedPill.evaluate().isNotEmpty;
          // 顶槽默认页签：今日待确认数为 0 时默认展示置顶目标，否则国策状态。
          // 截完按同一规则复位，矩阵下一轮的同名截图才不会串态。
          final defaultTab =
              find
                  .byKey(const ValueKey('board-today-national-focus'))
                  .evaluate()
                  .isNotEmpty
              ? 'status'
              : 'pinned';
          if (hasTopSlotSwitch) {
            await reveal(statusPill);
            await tester.tap(statusPill);
            await settle();
            await waitFor(find.text('今日国策状态'), reason: '国策状态页签应展示今日国策状态');
            await shot('board-status-$suffix');
            await reveal(pinnedPill);
            await tester.tap(pinnedPill);
            await settle();
            await waitFor(
              find.byKey(const ValueKey('board-top-slot-pinned-all')),
              reason: '3 个置顶目标应给出「查看全部 3 个 →」出口',
            );
            expect(
              find.text('查看全部 3 个 →'),
              findsOneWidget,
              reason: '单栏顶槽只展示前两条置顶目标，第三条经出口进入',
            );
            await shot('board-pinned-$suffix');
          }
          // 11 月 12 日：90 分钟专注 + 历史国策失败记录。点日期格后顶槽切到
          // 「11月12日国策记录」，历史结论与今日实时状态可在同一张卡上对照。
          final pastDay = find.byKey(const ValueKey('board-focus-day-12'));
          await reveal(pastDay);
          await tester.tap(pastDay);
          await settle();
          await waitFor(
            find.text('11月12日国策记录'),
            reason: '点选 11 月 12 日后顶槽应显示当日国策记录',
          );
          await reveal(
            find.byKey(const ValueKey('board-today-national-focus')),
          );
          await shot('board-past-day-$suffix');
          // 复位到今天：顶槽标题、日期详情与日格选中态都回到默认。
          final todayCell = find.byKey(const ValueKey('board-focus-day-18'));
          await reveal(todayCell);
          await tester.tap(todayCell);
          await settle();
          await waitFor(find.text('今日国策状态'), reason: '恢复今天后顶槽应回到今日国策状态');
          if (hasTopSlotSwitch && defaultTab == 'pinned') {
            await reveal(pinnedPill);
            await tester.tap(pinnedPill);
            await settle();
            await waitFor(
              find.byKey(const ValueKey('board-top-slot-pinned-all')),
              reason: '复位到默认的置顶目标页签',
            );
          }
          await scrollToTop(
            find.byKey(const ValueKey('board-focus-national-card')),
          );
        }
      }
    }

    try {
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: PactaApp(
            authRepository: FakeAuthRepository()..signedInUser = userId,
            displayClock: () => DateTime(2026, 11, 18, 9),
            taskRepositoryFactory: (_) => tasks,
            focusRepositoryFactory: (_) => focus,
            nationalFocusRepositoryFactory: (_) => tree,
            chainSignalsRepositoryFactory: (_) => signals,
            scheduleRepositoryFactory: (_) => schedules,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sizes = _mode == 'matrix'
          ? _sizes
          : [tester.view.physicalSize / tester.view.devicePixelRatio];
      for (final size in sizes) {
        if (_mode == 'matrix') {
          final dpr = tester.view.devicePixelRatio;
          tester.view.physicalSize = size * dpr;
          await settle();
        }
        for (final brightness in Brightness.values) {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          for (final scale in const [1.0, 2.0]) {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            await settle();
            final suffix =
                '${size.width.toInt()}x${size.height.toInt()}-'
                '${brightness == Brightness.dark ? 'dark' : 'light'}-'
                's${scale.toStringAsFixed(1)}';
            _printMetrics(tester, suffix);
            await captureAll(suffix);
          }
        }
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      if (Platform.isWindows) {
        // Windows 上的鼠标反馈：把指针悬停在主操作上再截一张。
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        final dpr = tester.view.devicePixelRatio;
        tester.view.physicalSize = const Size(1280, 800) * dpr;
        await settle();
        await openDestination('专注链');
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        final target = find.byKey(const ValueKey('focus-task-picker-entry'));
        await gesture.moveTo(tester.getCenter(target));
        await settle();
        await shot('focus-1280x800-light-s1.0-hover');
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      }
    } finally {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await focus.dispose();
      await tree.dispose();
      await schedules.dispose();
      await database.close();
    }
  });
}

void _printMetrics(WidgetTester tester, String label) {
  final view = tester.view;
  final logical = view.physicalSize / view.devicePixelRatio;
  final media = MediaQuery.of(tester.element(find.byType(PactaApp)));
  print(
    '[ui-baseline] $label platform=${Platform.operatingSystem} '
    'logical=${logical.width.toStringAsFixed(1)}x'
    '${logical.height.toStringAsFixed(1)} dpr=${view.devicePixelRatio} '
    'textScaler=${media.textScaler.scale(1.0)}',
  );
}
