import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/ui/pacta_check_circle.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';
import '../support/plan_navigation.dart';

/// 工单 04：按目标独立的"隐藏已完成任务"开关（双入口 + 全完成边界）。
const _user = 'goal-hide-completed-user';

class _Harness {
  _Harness(this.database, this.tasks, this.focus);

  final PactaDatabase database;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;

  static _Harness create() {
    final database = PactaDatabase(NativeDatabase.memory());
    return _Harness(
      database,
      LocalTaskRepository(
        database: database,
        userId: _user,
        remote: InMemoryTaskRemote(),
      ),
      LocalFocusRepository(
        database: database,
        userId: _user,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
      ),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1000, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 每次挂载都按同一份数据库新建仓储，等价于"关掉应用再打开"。
    final wired = LocalTaskRepository(
      database: database,
      userId: _user,
      remote: InMemoryTaskRemote(),
    );
    final wiredFocus = LocalFocusRepository(
      database: database,
      userId: _user,
      remote: InMemoryFocusRemote(),
      cloudSyncEnabled: false,
    );
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => wired,
        focusRepositoryFactory: (_) => wiredFocus,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await focus.dispose();
    await database.close();
  }
}

Finder _goalCard(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Card));

Finder _taskTile(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile));

Finder _inCard(String goalTitle, Finder matching) =>
    find.descendant(of: _goalCard(goalTitle), matching: matching);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('底部开关隐藏已完成，全完成时给出明确提示且可一键恢复', (tester) async {
    final harness = _Harness.create();
    try {
      final first = await harness.tasks.createGoal(
        const GoalDraft(
          title: '季度复盘',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(first.id, const TaskDraft(title: '写提纲'));
      final second = await harness.tasks.createTask(
        first.id,
        const TaskDraft(title: '校对'),
      );
      await harness.tasks.setTaskCompletion(second.id, isComplete: false);
      final done = await harness.tasks.createTask(
        first.id,
        const TaskDraft(title: '归档旧材料'),
      );
      await harness.tasks.setTaskCompletion(done.id, isComplete: true);

      final other = await harness.tasks.createGoal(
        const GoalDraft(
          title: '日常维护',
          classification: TaskClassification.regular,
        ),
      );
      final otherDone = await harness.tasks.createTask(
        other.id,
        const TaskDraft(title: '回复邮件'),
      );
      await harness.tasks.setTaskCompletion(otherDone.id, isComplete: true);
      await harness.tasks.createTask(other.id, const TaskDraft(title: '整理桌面'));

      await harness.pump(tester);
      await openPlan(tester);

      // 每个目标各自显示自己的计数。
      expect(_inCard('季度复盘', find.text('隐藏已完成 (1)')), findsOneWidget);
      expect(_inCard('日常维护', find.text('隐藏已完成 (1)')), findsOneWidget);

      await tester.tap(_inCard('季度复盘', find.text('隐藏已完成 (1)')));
      await tester.pumpAndSettle();
      expect(find.text('归档旧材料'), findsNothing, reason: '已完成任务被隐藏');
      expect(_inCard('季度复盘', find.text('写提纲')), findsOneWidget);
      expect(_inCard('季度复盘', find.text('校对')), findsOneWidget);
      expect(_inCard('季度复盘', find.text('显示已完成 (1)')), findsOneWidget);
      // 另一个目标不受影响。
      expect(_inCard('日常维护', find.text('回复邮件')), findsOneWidget);
      expect(_inCard('日常维护', find.text('隐藏已完成 (1)')), findsOneWidget);

      // 全部完成 + 隐藏：不能显示成"暂无任务"。
      await tester.tap(
        find.descendant(
          of: _taskTile('写提纲'),
          matching: find.byType(PactaCheckCircle),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: _taskTile('校对'),
          matching: find.byType(PactaCheckCircle),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('全部 3 项任务已完成并隐藏'), findsOneWidget);
      expect(find.text('暂无任务，先添加一个可执行的下一步。'), findsNothing);
      expect(_inCard('季度复盘', find.text('显示已完成')), findsOneWidget);

      await tester.tap(_inCard('季度复盘', find.text('显示已完成')));
      await tester.pumpAndSettle();
      expect(find.text('全部 3 项任务已完成并隐藏'), findsNothing);
      expect(find.text('归档旧材料'), findsOneWidget);
      expect(find.text('写提纲'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('长按操作面板提供同一开关，隐藏状态重开后保持', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '发布',
          classification: TaskClassification.regular,
        ),
      );
      final done = await harness.tasks.createTask(
        goal.id,
        const TaskDraft(title: '检查构建'),
      );
      await harness.tasks.setTaskCompletion(done.id, isComplete: true);
      await harness.tasks.createTask(goal.id, const TaskDraft(title: '整理说明'));

      await harness.pump(tester);
      await openPlan(tester);

      await tester.longPress(find.text('发布'));
      await tester.pumpAndSettle();
      expect(find.text('隐藏已完成任务'), findsOneWidget);
      await tester.tap(find.text('隐藏已完成任务'));
      await tester.pumpAndSettle();
      expect(find.text('检查构建'), findsNothing);
      expect(find.text('整理说明'), findsOneWidget);

      // 重开应用：偏好来自 SharedPreferences，不是内存状态。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await harness.pump(tester);
      await openPlan(tester);

      expect(find.text('检查构建'), findsNothing);
      expect(_inCard('发布', find.text('显示已完成 (1)')), findsOneWidget);

      await tester.longPress(find.text('发布'));
      await tester.pumpAndSettle();
      expect(find.text('显示已完成任务'), findsOneWidget);
      await tester.tap(find.text('显示已完成任务'));
      await tester.pumpAndSettle();
      expect(find.text('检查构建'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });
  testWidgets('唯一目标按住不动只弹目标面板，展开状态不被误折叠', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '唯一目标',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(goal.id, const TaskDraft(title: '唯一任务'));
      await harness.pump(tester);
      await openPlan(tester);

      expect(find.text('添加任务'), findsOneWidget, reason: '默认展开');
      await tester.longPress(find.text('唯一目标'));
      await tester.pumpAndSettle();

      expect(find.text('编辑目标'), findsOneWidget, reason: '原地长按弹出目标操作面板');
      expect(find.text('删除目标'), findsOneWidget);
      // 抬手不能被标题 InkWell 当成点按而折叠目标。
      expect(find.text('添加任务'), findsOneWidget, reason: '目标保持展开');
      expect(find.text('唯一任务'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('只有一项已完成任务时按住不动弹任务面板，不误开编辑框', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '已完成目标',
          classification: TaskClassification.regular,
        ),
      );
      final only = await harness.tasks.createTask(
        goal.id,
        const TaskDraft(title: '唯一已完成任务'),
      );
      await harness.tasks.setTaskCompletion(only.id, isComplete: true);
      await harness.pump(tester);
      await openPlan(tester);

      expect(find.text('唯一已完成任务'), findsOneWidget);
      await tester.longPress(find.text('唯一已完成任务'));
      await tester.pumpAndSettle();

      expect(find.text('标记未完成'), findsOneWidget, reason: '已完成行仍可原地长按弹任务面板');
      expect(find.text('编辑目标'), findsNothing, reason: '不应误触外层目标菜单');
      expect(find.byType(AlertDialog), findsNothing, reason: '抬手不应打开编辑弹窗');
      expect(find.text('任务名称'), findsNothing);
      expect(find.text('添加任务'), findsOneWidget, reason: '目标保持展开');
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });
}
