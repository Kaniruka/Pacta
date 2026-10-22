import 'dart:ui' show Tristate, SemanticsAction, SemanticsActionEvent;

import 'package:drift/native.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

void main() {
  testWidgets('目标描述可新增、编辑、清空并限制为200个用户可见字符', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final harness = await _BoardHarness.open(
      PactaDatabase(NativeDatabase.memory()),
    );
    addTearDown(harness.database.close);
    await harness.show(tester);

    await tester.tap(find.text('新建目标'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('目标名称'), '完成发布');
    await tester.enterText(_field('描述（可选）'), '  确认需求\r\n整理资料\n  ');
    expect(
      tester.widget<TextField>(_field('描述（可选）')).controller!.text,
      '  确认需求 整理资料   ',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    var goal = (await harness.tasks.getGoals()).single;
    expect(goal.description, '确认需求 整理资料');
    expect(find.text(goal.description), findsOneWidget);

    await tester.tap(find.byTooltip('编辑目标'));
    await tester.pumpAndSettle();
    final longDescription = List.filled(201, '👨‍👩‍👧‍👦').join();
    final maximumDescription = List.filled(200, '👨‍👩‍👧‍👦').join();
    await tester.enterText(_field('描述（可选）'), longDescription);
    expect(
      tester.widget<TextField>(_field('描述（可选）')).controller!.text,
      maximumDescription,
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    goal = (await harness.tasks.getGoals()).single;
    expect(goal.description, maximumDescription);
    final description = tester.widget<Text>(find.text(maximumDescription));
    expect(description.maxLines, 1);
    expect(description.overflow, TextOverflow.ellipsis);

    await tester.tap(find.byTooltip('编辑目标'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field('描述（可选）')).controller!.text,
      maximumDescription,
    );
    await tester.enterText(_field('描述（可选）'), '   ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    goal = (await harness.tasks.getGoals()).single;
    expect(goal.description, isEmpty);
    expect(find.text(maximumDescription), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('空目标标题支持键盘折叠、展开语义并与编辑删除独立', (tester) async {
    final semantics = tester.ensureSemantics();

    final harness = await _BoardHarness.open(
      PactaDatabase(NativeDatabase.memory()),
    );
    addTearDown(harness.database.close);
    final goal = await harness.tasks.createGoal(
      const GoalDraft(
        title: '空目标',
        description: '折叠仍可读的目标说明',
        classification: TaskClassification.regular,
      ),
    );
    await harness.show(tester);
    final header = find.byKey(ValueKey('goal-header-${goal.id}'));
    final headerNodeId = tester.getSemantics(header).id;
    expect(find.text('暂无任务，先添加一个可执行的下一步。'), findsOneWidget);
    expect(
      tester.getSemantics(header).getSemanticsData().label,
      isNot(contains('暂无任务，先添加一个可执行的下一步。')),
    );
    expect(
      tester.getSemantics(header).flagsCollection.isExpanded == Tristate.isTrue,
      isTrue,
    );
    expect(tester.getSemantics(header).getSemanticsData().value, '已展开');
    expect(
      tester
          .getSemantics(header)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        nodeId: tester.getSemantics(header).id,
        viewId: tester.view.viewId,
        type: SemanticsAction.tap,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSemantics(header).id, headerNodeId);
    expect(find.text('暂无任务，先添加一个可执行的下一步。'), findsNothing);
    expect(find.text('添加任务'), findsNothing);
    expect(find.text('折叠仍可读的目标说明'), findsOneWidget);
    expect(find.text('0 项任务\n暂无任务 · 未完成'), findsOneWidget);
    const taskTitle = '任务内容不应并入标题语义';
    await harness.tasks.createTask(
      goal.id,
      const TaskDraft(
        title: taskTitle,
        classification: TaskClassification.regular,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(header).getSemanticsData().label,
      isNot(contains(taskTitle)),
    );
    expect(
      tester.getSemantics(header).flagsCollection.isExpanded != Tristate.none,
      isTrue,
    );
    expect(
      tester.getSemantics(header).flagsCollection.isExpanded == Tristate.isTrue,
      isFalse,
    );
    expect(tester.getSemantics(header).getSemanticsData().value, '已折叠');
    expect(
      tester
          .getSemantics(header)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        nodeId: headerNodeId,
        viewId: tester.view.viewId,
        type: SemanticsAction.tap,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSemantics(header).id, headerNodeId);
    expect(
      tester.getSemantics(header).flagsCollection.isExpanded == Tristate.isTrue,
      isTrue,
    );
    expect(tester.getSemantics(header).getSemanticsData().value, '已展开');
    expect(find.text(taskTitle), findsOneWidget);
    expect(
      tester.getSemantics(header).getSemanticsData().label,
      isNot(contains(taskTitle)),
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        nodeId: headerNodeId,
        viewId: tester.view.viewId,
        type: SemanticsAction.tap,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSemantics(header).id, headerNodeId);
    expect(
      tester.getSemantics(header).flagsCollection.isExpanded == Tristate.isTrue,
      isFalse,
    );
    expect(tester.getSemantics(header).getSemanticsData().value, '已折叠');
    for (
      var i = 0;
      i < 30 &&
          tester.getSemantics(header).flagsCollection.isFocused !=
              Tristate.isTrue;
      i++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(
      tester.getSemantics(header).flagsCollection.isFocused == Tristate.isTrue,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('添加任务'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('添加任务'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('编辑目标'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('添加任务'), findsNothing);
    await tester.tap(find.byTooltip('删除目标'));
    await tester.pumpAndSettle();
    expect(find.text('删除目标和任务？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('添加任务'), findsNothing);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('分类只在目标默认与任务适用专注链编辑中呈现', (tester) async {
    final harness = await _BoardHarness.open(
      PactaDatabase(NativeDatabase.memory()),
    );
    addTearDown(harness.database.close);
    final goal = await harness.tasks.createGoal(
      const GoalDraft(title: '分类目标', classification: TaskClassification.elite),
    );
    await harness.tasks.createTask(
      goal.id,
      const TaskDraft(title: '分类任务', classification: TaskClassification.both),
    );
    await harness.show(tester);
    expect(find.textContaining('精锐'), findsNothing);
    expect(find.textContaining('两者'), findsNothing);
    await tester.tap(find.byTooltip('编辑目标'));
    await tester.pumpAndSettle();
    expect(find.text('新任务默认分类'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分类任务'));
    await tester.pumpAndSettle();
    expect(find.text('适用专注链'), findsOneWidget);
    expect(find.text('任务分类'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      (await harness.tasks.getGoals()).single.tasks.single.classification,
      TaskClassification.both,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('任务描述在看板单行省略，编辑可读全文并可清空', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    final harness = await _BoardHarness.open(
      PactaDatabase(NativeDatabase.memory()),
    );
    addTearDown(harness.database.close);
    final goal = await harness.tasks.createGoal(
      const GoalDraft(
        title: '交付材料',
        description: '目标说明始终可见',
        classification: TaskClassification.regular,
      ),
    );
    await harness.show(tester);

    await tester.tap(find.text('添加任务'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('任务名称'), '整理发布文案');
    final longDescription = List.filled(10, '这是一段完整的任务说明文字，').join();
    await tester.enterText(_field('描述（可选）'), longDescription);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    var task = (await harness.tasks.getGoals()).single.tasks.single;
    expect(task.goalId, goal.id);
    expect(task.description, longDescription);
    expect(find.text(goal.description), findsOneWidget);
    final description = tester.widget<Text>(find.text(longDescription));
    expect(description.maxLines, 1);
    expect(description.overflow, TextOverflow.ellipsis);

    await tester.ensureVisible(find.text('整理发布文案'));
    await tester.tap(find.text('整理发布文案'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field('描述（可选）')).controller!.text,
      longDescription,
    );
    await tester.enterText(_field('描述（可选）'), '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    task = (await harness.tasks.getGoals()).single.tasks.single;
    expect(task.description, isEmpty);
    expect(find.text(longDescription), findsNothing);

    await tester.tap(find.text('整理发布文案'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('描述（可选）'), '目标任务描述将在折叠时区分显示');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    task = (await harness.tasks.getGoals()).single.tasks.single;
    expect(task.description, '目标任务描述将在折叠时区分显示');
    expect(find.text(task.description), findsOneWidget);
    final goalCard = find.ancestor(
      of: find.text(goal.title),
      matching: find.byType(Card),
    );
    final collapseButton = find.descendant(
      of: goalCard,
      matching: find.byTooltip('收起任务'),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    await tester.tap(collapseButton);
    await tester.pumpAndSettle();
    expect(find.text(goal.description), findsOneWidget);
    expect(find.text(task.description), findsNothing);
    expect(find.text('整理发布文案'), findsNothing);
    await tester.tap(
      find.descendant(of: goalCard, matching: find.byTooltip('展开任务')),
    );
    await tester.pumpAndSettle();
    expect(find.text(task.description), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

class _BoardHarness {
  _BoardHarness({
    required this.database,
    required this.tasks,
    required this.focus,
    required this.nationalFocus,
  });

  static const userId = 'goal-task-description-widget-user';

  final PactaDatabase database;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;
  final LocalNationalFocusRepository nationalFocus;

  static Future<_BoardHarness> open(PactaDatabase database) async {
    return _BoardHarness(
      database: database,
      tasks: LocalTaskRepository(
        database: database,
        userId: userId,
        remote: InMemoryTaskRemote(),
      ),
      focus: LocalFocusRepository(
        database: database,
        userId: userId,
        remote: InMemoryFocusRemote(),
      ),
      nationalFocus: LocalNationalFocusRepository(
        database: database,
        userId: userId,
        remote: InMemoryNationalFocusRemoteDataSource(),
      ),
    );
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      PactaApp(
        authRepository: FakeAuthRepository()..signedInUser = userId,
        taskRepositoryFactory: (_) => tasks,
        focusRepositoryFactory: (_) => focus,
        nationalFocusRepositoryFactory: (_) => nationalFocus,
      ),
    );
    await tester.pumpAndSettle();
  }
}
