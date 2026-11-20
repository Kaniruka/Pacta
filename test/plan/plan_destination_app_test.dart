import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/ui/pacta_check_circle.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/schedules/schedule_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';

/// 票 07「计划目的地」的 App 级覆盖：五目的地、目标/任务完整管理、
/// 置顶与手动顺序持久化、一条任务多条安排、独立事项、提醒存储，
/// 以及看板只保留摘要、安排完成与任务完成仍然分开。
const _user = 'plan-destination-app';

class _Harness {
  _Harness(this.database);

  final PactaDatabase database;
  late LocalTaskRepository tasks;
  late LocalFocusRepository focus;
  late LocalNationalFocusRepository nationalFocus;
  late LocalScheduleRepository schedules;

  /// 每次 pump 都按同一份数据库重建仓储，等价于「关掉应用再打开」。
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1000, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tasks = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
    );
    focus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
    );
    nationalFocus = LocalNationalFocusRepository(
      database: database,
      userId: _user,
      cloudSyncEnabled: false,
    );
    schedules = LocalScheduleRepository(database: database, userId: _user);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => nationalFocus,
        scheduleRepositoryFactory: (_) => schedules,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 挂载中的 StreamBuilder 会让 Drift close 一直等待，先卸载再关闭。
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    const limit = Duration(seconds: 10);
    await focus.dispose().timeout(limit, onTimeout: () {});
    await nationalFocus.dispose().timeout(limit, onTimeout: () {});
    await database.close().timeout(limit, onTimeout: () {});
  }
}

Finder _navigation() {
  final rail = find.byType(NavigationRail);
  return rail.evaluate().isNotEmpty ? rail : find.byType(NavigationBar);
}

Finder _navDestination(String label) =>
    find.descendant(of: _navigation(), matching: find.text(label));

Future<void> _openDestination(WidgetTester tester, String label) async {
  await tester.tap(_navDestination(label));
  await tester.pumpAndSettle();
}

/// 有些目的地会持续播放加载动画，只等固定帧数，避免 pumpAndSettle 超时。
Future<void> _switchDestination(WidgetTester tester, String label) async {
  await tester.tap(_navDestination(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openPlan(WidgetTester tester) => _openDestination(tester, '计划');

Future<void> _openCalendar(WidgetTester tester) async {
  await _openPlan(tester);
  await tester.tap(find.text('日历'));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Finder _taskTile(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile));

/// 目标卡已不再提供内联图标栏：管理动作统一走"按住不动"的操作面板。
Future<void> _openGoalActions(WidgetTester tester, String title) async {
  await tester.longPress(find.text(title));
  await tester.pumpAndSettle();
}

/// 任务行同理：内层列表认领指针，弹出的是任务菜单而不是目标菜单。
Future<void> _openTaskActions(WidgetTester tester, String title) async {
  await tester.longPress(find.text(title));
  await tester.pumpAndSettle();
}

Finder _scheduleTile(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile));

Future<void> _createGoal(WidgetTester tester, String title) async {
  await tester.tap(find.text('新建目标'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('目标名称'), title);
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
}

Future<void> _addTask(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text('添加任务'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('添加任务'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('任务名称'), title);
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
}

Future<void> _createSchedule(
  WidgetTester tester,
  String title, {
  String? task,
  String? reminder,
}) async {
  await tester.ensureVisible(find.text('新建安排'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('新建安排'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('名称'), title);
  if (task != null) {
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(task).last);
    await tester.pumpAndSettle();
  }
  if (reminder != null) {
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(reminder).last);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  // 平台时区是系统边界：测试固定为 UTC，日历日期与显示时区才可复现。
  setUp(() {
    // 目标级"隐藏已完成"偏好走内存实现：读取在首帧后完成，不抢拖拽手势。
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => call.method == 'getLocalTimezone' ? 'Etc/UTC' : null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
  });

  testWidgets('五个目的地按顺序出现，计划页提供目标与日历两个视图', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);

      const labels = ['看板', '计划', '国策树', '专注链', '我的'];
      for (final label in labels) {
        expect(_navDestination(label), findsOneWidget, reason: '目的地 $label');
      }
      for (var index = 1; index < labels.length; index++) {
        expect(
          _top(tester, _navDestination(labels[index])),
          greaterThan(_top(tester, _navDestination(labels[index - 1]))),
          reason: '目的地顺序',
        );
      }

      await _openPlan(tester);
      expect(find.byType(PlanPage), findsOneWidget);
      expect(find.text('目标与任务'), findsOneWidget);

      await tester.tap(find.text('日历'));
      await tester.pumpAndSettle();
      expect(find.text('新建安排'), findsOneWidget);
      expect(find.text('添加事项'), findsNothing);

      await _switchDestination(tester, '国策树');
      expect(find.byType(NationalFocusTreePage), findsOneWidget);

      await _switchDestination(tester, '专注链');
      expect(find.byType(FocusChainPage), findsOneWidget);

      await _switchDestination(tester, '我的');
      expect(find.byType(MyPage), findsOneWidget);

      await _switchDestination(tester, '看板');
      expect(find.byType(BoardPage), findsOneWidget);
      expect(find.text('今天先做什么'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('计划页完成目标与任务的新建、编辑、完成与删除', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      await _openPlan(tester);

      await _createGoal(tester, '季度复盘');
      expect(find.text('季度复盘'), findsOneWidget);
      expect(find.text('0 项任务 · 暂无任务 · 未完成'), findsOneWidget);

      await _addTask(tester, '写提纲');
      expect(find.text('写提纲'), findsOneWidget);
      expect(find.text('1 项任务 · 进行中'), findsOneWidget);

      await tester.tap(find.text('写提纲'));
      await tester.pumpAndSettle();
      expect(find.text('编辑任务'), findsOneWidget);
      await tester.enterText(_field('任务名称'), '写提纲（修订）');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('写提纲（修订）'), findsOneWidget);
      expect(
        (await harness.tasks.getGoals()).single.tasks.single.title,
        '写提纲（修订）',
      );

      await tester.tap(
        find.descendant(
          of: _taskTile('写提纲（修订）'),
          matching: find.byType(PactaCheckCircle),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (await harness.tasks.getGoals()).single.tasks.single.isComplete,
        isTrue,
      );
      expect(find.text('1 项任务 · 已完成'), findsOneWidget);

      await _openTaskActions(tester, '写提纲（修订）');
      expect(find.text('标记未完成'), findsOneWidget);
      await tester.tap(find.text('删除任务'));
      await tester.pumpAndSettle();
      expect(find.text('删除任务？'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('写提纲（修订）'), findsNothing);
      expect(find.text('季度复盘'), findsOneWidget);
      expect(find.text('0 项任务 · 暂无任务 · 未完成'), findsOneWidget);

      await _openGoalActions(tester, '季度复盘');
      await tester.tap(find.text('删除目标'));
      await tester.pumpAndSettle();
      expect(find.text('删除目标和任务？'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('季度复盘'), findsNothing);
      expect(find.text('还没有目标'), findsOneWidget);
      expect(await harness.tasks.getGoals(), isEmpty);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('置顶多个目标可手动排序，重开应用后顺序保持一致', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      for (final title in ['目标甲', '目标乙', '目标丙']) {
        await harness.tasks.createGoal(
          GoalDraft(title: title, classification: TaskClassification.regular),
        );
      }
      await tester.pumpAndSettle();
      await _openPlan(tester);

      await _openGoalActions(tester, '目标乙');
      await tester.tap(find.text('置顶目标'));
      await tester.pumpAndSettle();
      await _openGoalActions(tester, '目标甲');
      await tester.tap(find.text('置顶目标'));
      await tester.pumpAndSettle();

      expect(find.text('置顶目标 · 长按拖动排序'), findsOneWidget);
      expect(find.text('其他目标 · 长按拖动排序'), findsOneWidget);
      expect(
        _top(tester, find.text('目标乙')),
        lessThan(_top(tester, find.text('目标甲'))),
      );
      expect(
        _top(tester, find.text('目标甲')),
        lessThan(_top(tester, find.text('目标丙'))),
      );

      // 按住拖动直接改手动顺序：乙向下越过甲。
      final drag = await tester.startGesture(
        tester.getCenter(find.text('目标乙')),
      );
      await tester.pump(const Duration(milliseconds: 400));
      for (var step = 0; step < 15; step++) {
        await drag.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(
        _top(tester, find.text('目标甲')),
        lessThan(_top(tester, find.text('目标乙'))),
      );
      expect(find.text('编辑目标'), findsNothing, reason: '拖拽不应弹出操作面板');

      final pinnedOrder = [
        for (final goal in await harness.tasks.getGoals())
          if (goal.isPinned) goal.title,
      ];
      expect(pinnedOrder, ['目标甲', '目标乙']);

      // 关掉应用再打开：顺序来自持久化数据，不是内存状态。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await harness.pump(tester);
      await _openPlan(tester);
      expect(
        _top(tester, find.text('目标甲')),
        lessThan(_top(tester, find.text('目标乙'))),
      );
      expect(find.text('置顶目标 · 长按拖动排序'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('一条任务可挂多条安排，提醒只存配置且完成安排不等于完成任务', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '写作',
          classification: TaskClassification.regular,
        ),
      );
      final task = await harness.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '写报告',
          classification: TaskClassification.regular,
        ),
      );
      await tester.pumpAndSettle();
      await _openCalendar(tester);

      await _createSchedule(tester, '上午整理', task: '写报告', reminder: '提前 10 分钟');
      expect(find.text('上午整理'), findsOneWidget);
      expect(find.text('任务：写报告'), findsOneWidget);
      expect(find.text('提前 10 分钟提醒'), findsOneWidget);
      expect(find.textContaining('1 项安排'), findsOneWidget);

      await _createSchedule(tester, '下午复核', task: '写报告');
      expect(find.text('下午复核'), findsOneWidget);
      expect(find.textContaining('2 项安排'), findsOneWidget);

      final schedules = await harness.schedules.getSchedules();
      expect(schedules, hasLength(2));
      expect({for (final schedule in schedules) schedule.taskId}, {task.id});
      expect(
        schedules
            .singleWhere((schedule) => schedule.title == '上午整理')
            .reminderMinutesBefore,
        10,
      );

      await tester.tap(
        find.descendant(
          of: _scheduleTile('下午复核'),
          matching: find.byType(PactaCheckCircle),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (await harness.schedules.getSchedules())
            .singleWhere((schedule) => schedule.title == '下午复核')
            .isCompleted,
        isTrue,
      );
      expect(
        (await harness.tasks.getGoals()).single.tasks.single.isComplete,
        isFalse,
        reason: '完成一条安排不等于完成专注，也不自动勾选任务',
      );

      await tester.tap(
        find.descendant(
          of: _scheduleTile('上午整理'),
          matching: find.byTooltip('安排操作'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除安排'));
      await tester.pumpAndSettle();
      expect(find.text('删除这条安排？'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('上午整理'), findsNothing);
      expect(find.text('下午复核'), findsOneWidget);
      expect(await harness.schedules.getSchedules(), hasLength(1));
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('独立事项可单独新建、改期、完成与删除，不需要目标或任务', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      await _openCalendar(tester);

      await _createSchedule(tester, '取快递');
      expect(find.text('取快递'), findsOneWidget);
      expect(find.text('独立事项'), findsOneWidget);

      await tester.tap(_scheduleTile('取快递'));
      await tester.pumpAndSettle();
      expect(find.text('编辑安排'), findsOneWidget);
      await tester.enterText(_field('名称'), '取快递并寄件');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('取快递并寄件'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: _scheduleTile('取快递并寄件'),
          matching: find.byType(PactaCheckCircle),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        (await harness.schedules.getSchedules()).single.isCompleted,
        isTrue,
      );

      await tester.tap(
        find.descendant(
          of: _scheduleTile('取快递并寄件'),
          matching: find.byTooltip('安排操作'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('改期'));
      await tester.pumpAndSettle();
      expect(find.text('改期'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('取快递并寄件'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: _scheduleTile('取快递并寄件'),
          matching: find.byTooltip('安排操作'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除安排'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('取快递并寄件'), findsNothing);
      expect(await harness.schedules.getSchedules(), isEmpty);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('看板只保留摘要，任务管理与专注入口都在计划页', (tester) async {
    final harness = _Harness(PactaDatabase(NativeDatabase.memory()));
    try {
      await harness.pump(tester);
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '发布',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '整理素材',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.setGoalPinned(goal.id, isPinned: true);
      await tester.pumpAndSettle();

      expect(find.text('置顶目标'), findsOneWidget);
      expect(find.text('发布'), findsOneWidget);
      expect(find.text('下一项：整理素材'), findsOneWidget);
      expect(find.text('整理素材'), findsNothing, reason: '看板不展开任务列表');
      expect(find.text('添加任务'), findsNothing);
      expect(find.byTooltip('开始专注'), findsNothing);
      expect(find.text('近期专注活动'), findsOneWidget);

      await tester.tap(find.text('打开计划'));
      await tester.pumpAndSettle();
      expect(find.byType(PlanPage), findsOneWidget);
      expect(find.text('整理素材'), findsOneWidget);
      expect(find.byTooltip('开始专注'), findsOneWidget);
    } finally {
      await harness.dispose(tester);
    }
  });
}
