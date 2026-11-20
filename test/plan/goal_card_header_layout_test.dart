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

/// 目标卡头部只剩"标题 + 唯一展开箭头"：窄屏不再有两排动作图标，
/// 管理动作统一收进"按住不动"的操作面板。
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
  testWidgets('窄屏目标卡：标题占满整行，只有单一展开箭头', (tester) async {
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
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text(_shortTitle),
            matching: find.byType(Card),
          ),
          matching: find.byIcon(Icons.expand_less),
        ),
        findsOneWidget,
        reason: '收起态只保留一个展开/折叠箭头',
      );
      // 内联图标栏整排移除：编辑/删除字形不可能出现在头部。
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text(_shortTitle),
            matching: find.byType(Card),
          ),
          matching: find.byIcon(Icons.edit_outlined),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text(_shortTitle),
            matching: find.byType(Card),
          ),
          matching: find.byIcon(Icons.delete_outline),
        ),
        findsNothing,
      );

      await tester.longPress(find.text(_shortTitle));
      await tester.pumpAndSettle();
      expect(find.text('编辑目标'), findsOneWidget, reason: '长按打开操作面板');
      expect(find.text('删除目标'), findsOneWidget);
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('置顶目标用安静图钉区分，不再占用头部动作槽', (tester) async {
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

      expect(find.text('置顶目标 · 长按拖动排序'), findsOneWidget);
      final headerRect = tester.getRect(
        find.byKey(ValueKey('goal-header-${goal.id}')),
      );
      expect(headerRect.width, greaterThan(260), reason: '置顶后标题块仍占满整行');
      final titleRect = tester.getRect(find.text(_shortTitle));
      expect(titleRect.height, lessThan(40), reason: '置顶后标题仍是一行');
      final card = find.ancestor(
        of: find.text(_shortTitle),
        matching: find.byType(Card),
      );
      final pin = tester.getRect(
        find.descendant(of: card, matching: find.byIcon(Icons.push_pin)),
      );
      expect(
        pin.center.dy,
        closeTo(titleRect.center.dy, 2),
        reason: '图钉与标题同一基线，只做安静的区分',
      );
      expect(find.byTooltip('下移置顶目标'), findsNothing);
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

  testWidgets('宽屏目标卡仍是同一套"标题 + 单箭头"头部', (tester) async {
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

      final chevron = tester.getRect(find.byIcon(Icons.expand_less));
      final titleRect = tester.getRect(find.text(_shortTitle));
      expect(chevron.top, lessThan(titleRect.bottom), reason: '宽屏箭头与标题同一行');
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });
}
