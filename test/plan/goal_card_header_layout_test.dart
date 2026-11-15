import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';
import '../support/plan_navigation.dart';

/// 目标卡头部的响应式排版：窄屏标题占满整行、动作另起一行；
/// 宽屏才并排。断言的是真实渲染尺寸，不是"存在即可"。
const _user = 'goal-card-header-layout';
const _shortTitle = '本周交付';
const _longTitle = '整理发布材料并同步给所有协作方确认最终版本后归档';

class _Harness {
  _Harness(this.database, this.tasks, this.focus, this.tree);

  final PactaDatabase database;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;
  final LocalNationalFocusRepository tree;

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
      LocalNationalFocusRepository(
        database: database,
        userId: _user,
        cloudSyncEnabled: false,
      ),
    );
  }

  Future<void> pump(WidgetTester tester, {double width = 360}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = _user,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => tree,
      ),
    );
    await tester.pumpAndSettle();
    await openPlan(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await focus.dispose();
    await tree.dispose();
    await database.close();
  }
}

void main() {
  testWidgets('窄屏目标卡：短标题占满整行，动作另起一行', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: _shortTitle,
          description: '周四前发出',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '发确认邮件',
          classification: TaskClassification.regular,
        ),
      );
      await harness.pump(tester);

      final headerRect = tester.getRect(
        find.byKey(ValueKey('goal-header-${goal.id}')),
      );
      expect(
        headerRect.width,
        greaterThan(260),
        reason: '窄屏标题块应占满整行，而不是被动作挤到几十像素',
      );
      final titleRect = tester.getRect(find.text(_shortTitle));
      expect(titleRect.height, lessThan(40), reason: '短标题应保持一行，而不是被迫折成两行');
      final summaryRect = tester.getRect(find.text('1 项任务 · 进行中'));
      expect(summaryRect.height, lessThan(30), reason: '元信息应保持一行，不碎成多段');
      final editRect = tester.getRect(find.byTooltip('编辑目标'));
      expect(
        editRect.top,
        greaterThanOrEqualTo(titleRect.bottom - 1),
        reason: '窄屏动作按钮必须在标题块下方单独一行',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('置顶后的目标卡沿用同一套窄屏排版', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: _shortTitle,
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '发确认邮件',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.setGoalPinned(goal.id, isPinned: true);
      await harness.pump(tester);

      expect(find.text('置顶目标 · 手动顺序'), findsOneWidget);
      final headerRect = tester.getRect(
        find.byKey(ValueKey('goal-header-${goal.id}')),
      );
      expect(headerRect.width, greaterThan(260), reason: '置顶后标题块仍占满整行');
      final titleRect = tester.getRect(find.text(_shortTitle));
      expect(titleRect.height, lessThan(40), reason: '置顶后标题仍是一行');
      final editRect = tester.getRect(find.byTooltip('编辑目标'));
      expect(
        editRect.top,
        greaterThanOrEqualTo(titleRect.bottom - 1),
        reason: '置顶多出上移/下移也不能把动作挤回标题同一行',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('窄屏长标题保持两行省略且不溢出', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: _longTitle,
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '拆分任务',
          classification: TaskClassification.regular,
        ),
      );
      await harness.pump(tester);

      final title = tester.widget<Text>(find.text(_longTitle));
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(
        tester.getRect(find.text(_longTitle)).width,
        greaterThan(200),
        reason: '长标题也应拿到整行宽度',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('宽屏目标卡仍把动作与标题并排', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: _shortTitle,
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '发确认邮件',
          classification: TaskClassification.regular,
        ),
      );
      await harness.pump(tester, width: 1000);

      final titleRect = tester.getRect(find.text(_shortTitle));
      final editRect = tester.getRect(find.byTooltip('编辑目标'));
      expect(editRect.top, lessThan(titleRect.bottom), reason: '宽屏保持内联排版');
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });
}
