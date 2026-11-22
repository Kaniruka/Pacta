import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';
import 'package:pacta/src/ui/pacta_grouped_list.dart';

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

  Future<void> pump(
    WidgetTester tester, {
    double width = 360,
    double height = 800,
  }) async {
    tester.view.physicalSize = Size(width, height);
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
      // 置顶分区标题是谷歌蓝 PactaSectionHeader：主色、左缘与目标卡对齐。
      final pinnedHeader = find.widgetWithText(
        PactaSectionHeader,
        '置顶目标 · 长按拖动排序',
      );
      expect(pinnedHeader, findsOneWidget);
      final pinnedTitle = find.descendant(
        of: pinnedHeader,
        matching: find.text('置顶目标 · 长按拖动排序'),
      );
      expect(
        tester.widget<Text>(pinnedTitle).style?.color,
        Theme.of(tester.element(pinnedTitle)).colorScheme.primary,
        reason: '分区小标题取主蓝色，不再用灰色小字',
      );
      expect(
        tester.getRect(pinnedTitle).left,
        closeTo(
          tester
              .getRect(
                find
                    .ancestor(
                      of: find.text(_shortTitle),
                      matching: find.byType(Card),
                    )
                    .first,
              )
              .left,
          0.5,
        ),
        reason: '分区标题与目标卡片左缘对齐',
      );
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

  testWidgets('卡片零外边距并由列表统一 12dp 行距，拖拽高亮贴合卡片圆角', (tester) async {
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
      await harness.pump(tester);

      final cardFinder = find.ancestor(
        of: find.text(_shortTitle),
        matching: find.byType(Card),
      );
      // 卡片的上下间距移交给列表：Card 不再自带 margin，代理阴影才贴住圆角。
      expect(tester.widget<Card>(cardFinder).margin, EdgeInsets.zero);
      final goalList = tester.widget<PactaHoldReorderList>(
        find
            .ancestor(
              of: find.text(_shortTitle),
              matching: find.byType(PactaHoldReorderList),
            )
            .first,
      );
      expect(goalList.itemSpacing, 12);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('头部末行到首条任务的距离不随描述行数变化（偏差 <= 1dp）', (tester) async {
    final harness = _Harness.create();
    try {
      // 单行标题 + 无描述：头部文字块最矮（约 40dp）。
      final tight = await harness.tasks.createGoal(
        const GoalDraft(
          title: '无描述目标',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        tight.id,
        const TaskDraft(
          title: '先写提纲',
          classification: TaskClassification.regular,
        ),
      );
      // 同样的标题但多一行描述：头部文字块被撑高。
      final roomy = await harness.tasks.createGoal(
        const GoalDraft(
          title: '有描述目标',
          description: '周四前发出',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        roomy.id,
        const TaskDraft(
          title: '再发邮件',
          classification: TaskClassification.regular,
        ),
      );
      await harness.pump(tester, width: 420, height: 1200);

      double headerToFirstTask(String goalTitle, String taskTitle) {
        final card = find.ancestor(
          of: find.text(goalTitle),
          matching: find.byType(Card),
        );
        final summary = find.descendant(
          of: card,
          matching: find.text('1 项任务 · 进行中'),
        );
        final firstTask = find.ancestor(
          of: find.text(taskTitle),
          matching: find.byType(ListTile),
        );
        expect(summary, findsOneWidget);
        expect(firstTask, findsOneWidget);
        return tester.getRect(firstTask).top - tester.getRect(summary).bottom;
      }

      final withoutDescription = headerToFirstTask('无描述目标', '先写提纲');
      final withDescription = headerToFirstTask('有描述目标', '再发邮件');
      expect(withoutDescription, greaterThan(0));
      expect(
        (withoutDescription - withDescription).abs(),
        lessThanOrEqualTo(1.0),
        reason:
            '头部末行文字底到首条任务顶的距离必须恒定：'
            '无描述 $withoutDescription / 有描述 $withDescription',
      );
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('收起态目标卡上下内边距严格对称，且不随描述行数变化', (tester) async {
    final harness = _Harness.create();
    try {
      final tight = await harness.tasks.createGoal(
        const GoalDraft(
          title: '收起无描述',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        tight.id,
        const TaskDraft(
          title: '先写提纲',
          classification: TaskClassification.regular,
        ),
      );
      final roomy = await harness.tasks.createGoal(
        const GoalDraft(
          title: '收起有描述',
          description: '周四前发出',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        roomy.id,
        const TaskDraft(
          title: '再发邮件',
          classification: TaskClassification.regular,
        ),
      );
      await harness.pump(tester, width: 420, height: 1200);

      // 收起两张卡：头部只剩「16dp 上边距 + 文字块 + 16dp 下边距」。
      for (final id in [tight.id, roomy.id]) {
        await tester.tap(find.byKey(ValueKey('goal-header-$id')));
        await tester.pumpAndSettle();
      }

      List<double> insets(String goalTitle) {
        final card = find.ancestor(
          of: find.text(goalTitle),
          matching: find.byType(Card),
        );
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.byType(ListTile)),
          findsNothing,
          reason: '$goalTitle 应处于收起态，任务行不再渲染',
        );
        final cardRect = tester.getRect(card);
        final titleRect = tester.getRect(
          find.descendant(of: card, matching: find.text(goalTitle)),
        );
        final summaryRect = tester.getRect(
          find.descendant(of: card, matching: find.text('1 项任务 · 进行中')),
        );
        return [
          titleRect.top - cardRect.top,
          cardRect.bottom - summaryRect.bottom,
        ];
      }

      final tightInsets = insets('收起无描述');
      final roomyInsets = insets('收起有描述');
      expect(
        (tightInsets[0] - tightInsets[1]).abs(),
        lessThanOrEqualTo(1.0),
        reason:
            '无描述卡上下内边距必须对称：'
            '上 ${tightInsets[0]} / 下 ${tightInsets[1]}',
      );
      expect(
        (roomyInsets[0] - roomyInsets[1]).abs(),
        lessThanOrEqualTo(1.0),
        reason:
            '有描述卡上下内边距必须对称：'
            '上 ${roomyInsets[0]} / 下 ${roomyInsets[1]}',
      );
      expect(
        (tightInsets[0] - roomyInsets[0]).abs(),
        lessThanOrEqualTo(1.0),
        reason: '有无描述不改变顶部内边距',
      );
      expect(
        (tightInsets[1] - roomyInsets[1]).abs(),
        lessThanOrEqualTo(1.0),
        reason: '有无描述不改变底部内边距',
      );
      // 收起态上下各一档 16dp：底部不再叠加旧的 10dp 呼吸位变成 26dp。
      expect(tightInsets[0], closeTo(16, 1.0));
      expect(tightInsets[1], closeTo(16, 1.0));
      expect(roomyInsets[0], closeTo(16, 1.0));
      expect(roomyInsets[1], closeTo(16, 1.0));
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('卡片底部不再有添加任务按钮，空目标用可点提示起手', (tester) async {
    final harness = _Harness.create();
    try {
      final empty = await harness.tasks.createGoal(
        const GoalDraft(
          title: '空目标',
          classification: TaskClassification.regular,
        ),
      );
      final busy = await harness.tasks.createGoal(
        const GoalDraft(
          title: '有任务目标',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        busy.id,
        const TaskDraft(
          title: '已有任务',
          classification: TaskClassification.regular,
        ),
      );
      await harness.pump(tester, width: 420, height: 1200);

      expect(find.text('添加任务'), findsNothing, reason: '底部冗余按钮已移除');
      final hint = find.byKey(const ValueKey('goal-empty-task-hint'));
      expect(hint, findsOneWidget);
      expect(
        find.descendant(of: hint, matching: find.text('暂无任务，点击添加')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: hint,
          matching: find.byIcon(Icons.add_circle_outline),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSize(hint).height,
        greaterThanOrEqualTo(48),
        reason: '空态引导行保留 48dp 命中区',
      );

      await tester.tap(hint);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '点出来的任务');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final created = (await harness.tasks.getGoals()).singleWhere(
        (goal) => goal.id == empty.id,
      );
      expect(created.tasks.single.title, '点出来的任务');
      expect(find.text('暂无任务，点击添加'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await harness.dispose(tester);
    }
  });

  testWidgets('目标长按菜单首项是添加任务，点击直接新建任务', (tester) async {
    final harness = _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        const GoalDraft(
          title: '菜单目标',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '已有任务',
          classification: TaskClassification.regular,
        ),
      );
      await harness.pump(tester, width: 420, height: 1200);

      await tester.longPress(find.text('菜单目标'));
      await tester.pumpAndSettle();
      expect(find.text('添加任务'), findsOneWidget);
      expect(
        tester.getRect(find.text('添加任务')).top,
        lessThan(tester.getRect(find.text('编辑目标')).top),
        reason: '添加任务是目标菜单的第一项',
      );
      await tester.tap(find.text('添加任务'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '菜单添加的任务');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final updated = (await harness.tasks.getGoals()).singleWhere(
        (item) => item.id == goal.id,
      );
      expect(updated.tasks.map((task) => task.title), contains('菜单添加的任务'));
      expect(find.text('菜单添加的任务'), findsOneWidget);
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
