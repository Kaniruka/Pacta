import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth_repository.dart';
import '../support/plan_navigation.dart';

/// 工单 04：计划页任务行的"按住不动 = 菜单 / 按住拖动 = 排序"与
/// 仓储、看板下一项任务的联动。
const _user = 'goal-task-reorder-user';

class _Harness {
  _Harness._(this.database, this.tasks, this.focus);

  final PactaDatabase database;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;

  static _Harness create() {
    final database = PactaDatabase(NativeDatabase.memory());
    // 固定且单调的写入时钟：同一秒内创建的多条任务不会因为 unstable sort
    // 产生随机的兜底顺序，排序断言只反映手动顺序。
    var clock = DateTime.utc(2026, 11, 20, 8);
    return _Harness._(
      database,
      LocalTaskRepository(
        database: database,
        userId: _user,
        remote: InMemoryTaskRemote(),
        now: () => clock = clock.add(const Duration(seconds: 1)),
      ),
      LocalFocusRepository(
        database: database,
        userId: _user,
        remote: InMemoryFocusRemote(),
        cloudSyncEnabled: false,
      ),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
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

/// 拖动结束后的写入是异步的：轮询到仓储真正反映新顺序再断言，避免与
/// ReorderableListView 的收尾动画抢跑。
Future<bool> _pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (await condition()) return true;
    await tester.pump(const Duration(milliseconds: 50));
  }
  return false;
}

/// 长按后拖动：FakeAsync 下手势竞技场偶尔让页面滚动先认领同一指针，
/// 重试一次即可稳定复现真实交互，不改变被测行为。
Future<void> _dragUntilReordered(
  WidgetTester tester,
  Finder target,
  Future<bool> Function() done,
) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    await _dragDown(tester, target, 300);
    if (await _pumpUntil(tester, done)) return;
    await tester.pumpAndSettle();
  }
  fail('连续三次拖动都没有触发任务重排');
}

Future<void> _dragDown(
  WidgetTester tester,
  Finder target,
  double distance,
) async {
  final gesture = await tester.startGesture(tester.getCenter(target));
  // 先安稳按住：延迟识别器在延迟结束、指针仍未移动时率先锁定手势，
  // 页面滚动不会在同一指针上抢走拖拽。
  await tester.pump(const Duration(milliseconds: 600));
  var travelled = 0.0;
  while (travelled < distance) {
    final step = math.min(30.0, distance - travelled);
    await gesture.moveBy(Offset(0, step));
    travelled += step;
    await tester.pump(const Duration(milliseconds: 50));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    // 偏好存储在测试里走内存实现：隐藏偏好的读取在首个 pumpAndSettle 内完成，
    // 不会在拖拽进行中触发页面重建。
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('按住拖动任务重排写回仓储，并改变看板"下一项"', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '发布',
          classification: TaskClassification.regular,
        ),
      );
      final first = await harness.tasks.createTask(
        goal.id,
        TaskDraft(title: '甲', deadline: DateTime.utc(2026, 12, 1)),
      );
      final second = await harness.tasks.createTask(
        goal.id,
        TaskDraft(title: '乙', deadline: DateTime.utc(2027, 1, 1)),
      );
      final third = await harness.tasks.createTask(
        goal.id,
        TaskDraft(title: '丙', deadline: DateTime.utc(2027, 2, 1)),
      );

      // 看板只投影置顶目标：先置顶，再验证"下一项"随手动顺序变化。
      await harness.tasks.setGoalPinned(goal.id, isPinned: true);
      await harness.pump(tester);
      await openPlan(tester);
      expect(
        (await harness.tasks.getGoals()).single.nextTask?.id,
        first.id,
        reason: '排序前按最早截止时间',
      );

      await _dragUntilReordered(
        tester,
        find.text('甲'),
        () async => (await harness.tasks.getGoals()).single.hasManualTaskOrder,
      );

      final reordered = (await harness.tasks.getGoals()).single;
      expect(reordered.hasManualTaskOrder, isTrue);
      // 跨端条目高度不同，落点可能是一格或两格；要验证的是"被拖走的那项
      // 不再是第一项，且下一项由手动顺序而不是截止时间决定"。
      expect(reordered.tasks.first.id, isNot(first.id));
      expect(reordered.tasks.map((item) => item.id).toSet(), {
        first.id,
        second.id,
        third.id,
      });
      final nextTask = reordered.nextTask;
      expect(nextTask, isNotNull);
      expect(
        nextTask!.id,
        reordered.tasks.firstWhere((item) => !item.isComplete).id,
        reason: '下一项就是手动顺序里的第一条未完成任务',
      );
      expect(find.text('编辑目标'), findsNothing, reason: '拖动不应弹目标菜单');

      // 看板读同一份仓储：置顶摘要的"下一项"必须跟着手动顺序走。
      await openBoard(tester);
      // 1000 宽减去 AppShell 80dp 侧边栏后 BoardPage 只有 920 < 960（单栏），
      // 且这里没有国策节点：顶槽默认停在「国策状态」，置顶摘要在胶囊后面。
      // 先切到置顶目标页签再断言；宽屏双栏没有胶囊，摘要本来就在左栏。
      final pinnedTab = find.byKey(const ValueKey('board-top-slot-pinned'));
      if (pinnedTab.evaluate().isNotEmpty) {
        await tester.ensureVisible(pinnedTab);
        await tester.pumpAndSettle();
        await tester.tap(pinnedTab);
        await tester.pumpAndSettle();
      }
      expect(find.text('下一项：${nextTask.title}'), findsOneWidget);
      expect(find.textContaining('下一项：甲'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('按住任务不动弹任务菜单，不会误触外层目标菜单', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '交付',
          classification: TaskClassification.regular,
        ),
      );
      final open = await harness.tasks.createTask(
        goal.id,
        const TaskDraft(title: '写提纲'),
      );
      final done = await harness.tasks.createTask(
        goal.id,
        const TaskDraft(title: '归档'),
      );
      await harness.tasks.setTaskCompletion(done.id, isComplete: true);

      await harness.pump(tester);
      await openPlan(tester);

      await tester.longPress(find.text('写提纲'));
      await tester.pumpAndSettle();
      expect(find.text('标记完成'), findsOneWidget);
      expect(find.text('开始专注'), findsOneWidget);
      expect(find.text('编辑目标'), findsNothing);
      await tester.tap(find.text('标记完成'));
      await tester.pumpAndSettle();
      expect(
        (await harness.tasks.getGoals()).single.tasks
            .singleWhere((item) => item.id == open.id)
            .isComplete,
        isTrue,
      );

      // 已完成任务同样能原地长按（禁用排序但认领指针）。
      await tester.longPress(find.text('归档'));
      await tester.pumpAndSettle();
      expect(find.text('标记未完成'), findsOneWidget);
      expect(find.text('编辑目标'), findsNothing);
      await tester.tap(find.text('标记未完成'));
      await tester.pumpAndSettle();
      expect(
        (await harness.tasks.getGoals()).single.tasks
            .singleWhere((item) => item.id == done.id)
            .isComplete,
        isFalse,
      );

      // 目标标题仍然只开目标菜单。
      await tester.longPress(find.text('交付'));
      await tester.pumpAndSettle();
      expect(find.text('编辑目标'), findsOneWidget);
      expect(find.text('标记完成'), findsNothing);
      expect(find.text('删除目标'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });
  testWidgets('只有一个任务时按住不动只弹任务面板，不误开编辑框', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '单任务目标',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(goal.id, const TaskDraft(title: '唯一任务'));
      await harness.pump(tester);
      await openPlan(tester);

      expect(find.byType(AlertDialog), findsNothing);
      await tester.longPress(find.text('唯一任务'));
      await tester.pumpAndSettle();

      expect(find.text('标记完成'), findsOneWidget, reason: '原地长按弹出任务操作面板');
      expect(find.text('编辑目标'), findsNothing, reason: '不应误触外层目标菜单');
      // 抬手后 ListTile 的 onTap 必须被抑制：不能同时弹出"编辑任务"弹窗。
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('任务名称'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });
}
