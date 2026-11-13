import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/focus/focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' hide FocusSession;
import 'package:pacta/src/tasks/task_models.dart';
import 'package:pacta/src/tasks/task_repository.dart';

import '../support/fake_auth_repository.dart';

/// 2026-11-13 体验清单 6/7/8/10/11 的验收测试（修复后行为）。
///
/// 基线复现记录见 `.scratch/experience-20261113/ui-repro.md`。
const _user = 'experience-repro';

class _Harness {
  _Harness(this.database, this.tasks, this.focus, this.nationalFocus);

  final PactaDatabase database;
  final LocalTaskRepository tasks;
  final LocalFocusRepository focus;
  final LocalNationalFocusRepository nationalFocus;

  static Future<_Harness> create() async {
    final database = PactaDatabase(NativeDatabase.memory());
    final now = DateTime(2026, 11, 13, 10);
    return _Harness(
      database,
      LocalTaskRepository(
        database: database,
        userId: _user,
        remote: InMemoryTaskRemote(),
        now: () => now,
      ),
      LocalFocusRepository(
        database: database,
        userId: _user,
        remote: InMemoryFocusRemote(),
        now: () => now,
      ),
      LocalNationalFocusRepository(
        database: database,
        userId: _user,
        cloudSyncEnabled: false,
        now: () => now,
      ),
    );
  }

  /// 挂载中的 StreamBuilder 会让 Drift close 一直等待，先卸载再关闭。
  Future<void> dispose() async {
    const limit = Duration(seconds: 10);
    await focus.dispose().timeout(limit, onTimeout: () {});
    await nationalFocus.dispose().timeout(limit, onTimeout: () {});
    await database.close().timeout(limit, onTimeout: () {});
  }
}

Future<void> _pumpApp(
  WidgetTester tester,
  _Harness harness, {
  Size size = const Size(1000, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    PactaApp(
      authRepository: FakeAuthRepository()..signedInUser = _user,
      taskRepositoryFactory: (_) => harness.tasks,
      focusRepositoryFactory: (_) => harness.focus,
      nationalFocusRepositoryFactory: (_) => harness.nationalFocus,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _unmountAndSettle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _openNationalFocusTab(WidgetTester tester) async {
  final navigation = find.byType(NavigationBar).evaluate().isNotEmpty
      ? find.byType(NavigationBar)
      : find.byType(NavigationRail);
  await tester.tap(find.descendant(of: navigation, matching: find.text('国策树')));
  await tester.pumpAndSettle();
}

Future<void> _openLibrary(WidgetTester tester) async {
  await tester.tap(find.text('卡片库'));
  await tester.pumpAndSettle();
}

Finder _goalCard(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Card));

Finder _taskTile(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(ListTile));

void main() {
  testWidgets('7 目标收起箭头与编辑/删除按钮对齐且折叠控制仍独立可用', (tester) async {
    final harness = await _Harness.create();
    try {
      final goal = await harness.tasks.createGoal(
        GoalDraft(
          title: '整理本周材料',
          description: '先核对本周计划与已交付内容',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '准备材料',
          classification: TaskClassification.regular,
        ),
      );
      await harness.tasks.createGoal(
        const GoalDraft(
          title: '无描述目标',
          classification: TaskClassification.regular,
        ),
      );
      await _pumpApp(tester, harness);

      for (final title in ['整理本周材料', '无描述目标']) {
        final card = _goalCard(title);
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        final chevron = tester.getRect(
          find.descendant(of: card, matching: find.byIcon(Icons.expand_less)),
        );
        final editBox = tester.getRect(
          find.descendant(of: card, matching: find.byTooltip('编辑目标')),
        );
        final deleteBox = tester.getRect(
          find.descendant(of: card, matching: find.byTooltip('删除目标')),
        );
        final editGlyph = tester.getRect(
          find.descendant(of: card, matching: find.byIcon(Icons.edit_outlined)),
        );
        final deleteGlyph = tester.getRect(
          find.descendant(
            of: card,
            matching: find.byIcon(Icons.delete_outline),
          ),
        );
        expect(chevron.center.dy, closeTo(editBox.center.dy, 0.5));
        expect(chevron.center.dy, closeTo(deleteBox.center.dy, 0.5));
        expect(
          editGlyph.left - chevron.right,
          closeTo(deleteGlyph.left - editGlyph.right, 0.5),
          reason: '箭头字形与按钮字形的水平节奏一致',
        );
        expect(editBox.center.dy, closeTo(deleteBox.center.dy, 0.5));
      }

      // 标题整体仍是折叠控制。
      final card = _goalCard('整理本周材料');
      expect(find.text('准备材料'), findsOneWidget);
      await tester.tap(find.text('整理本周材料'));
      await tester.pumpAndSettle();
      expect(find.text('准备材料'), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      await tester.tap(find.text('整理本周材料'));
      await tester.pumpAndSettle();
      expect(find.text('准备材料'), findsOneWidget);

      // 编辑与删除独立，不触发折叠。
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip('编辑目标')),
      );
      await tester.pumpAndSettle();
      expect(find.text('编辑目标'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('准备材料'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmountAndSettle(tester);
      await harness.dispose();
    }
  });

  testWidgets('8 任务没有可选信息时不占三行高且标题居中', (tester) async {
    final harness = await _Harness.create();
    try {
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
      await harness.tasks.createTask(
        goal.id,
        const TaskDraft(
          title: '写提纲',
          description: '先写三段',
          estimatedMinutes: 45,
          classification: TaskClassification.regular,
        ),
      );
      await _pumpApp(tester, harness);

      final emptyTile = _taskTile('整理素材');
      final filledTile = _taskTile('写提纲');
      final emptyRect = tester.getRect(emptyTile);
      final filledRect = tester.getRect(filledTile);
      final emptyTitle = tester.getRect(find.text('整理素材'));
      final emptyCheckbox = tester.getRect(
        find.descendant(of: emptyTile, matching: find.byType(Checkbox)),
      );
      expect(tester.widget<ListTile>(emptyTile).subtitle, isNull);
      expect(tester.widget<ListTile>(emptyTile).isThreeLine, isFalse);
      expect(
        emptyRect.height,
        lessThan(filledRect.height),
        reason: '空可选信息不应和被填满的任务一样高',
      );
      expect(emptyRect.height, lessThan(72), reason: '空可选信息行回到单行高度');
      expect(
        (emptyTitle.center.dy - emptyRect.center.dy).abs(),
        lessThan(1),
        reason: '只有标题时文字垂直居中，不留偏下的空白',
      );
      expect(
        (emptyCheckbox.center.dy - emptyRect.center.dy).abs(),
        lessThan(1),
      );
      expect(tester.widget<ListTile>(filledTile).subtitle, isNotNull);
    } finally {
      await _unmountAndSettle(tester);
      await harness.dispose();
    }
  });

  testWidgets('11 预计时长可用分钟或小时并保持总时长', (tester) async {
    final harness = await _Harness.create();
    try {
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
      await _pumpApp(tester, harness);

      Future<void> openEditor() async {
        await tester.tap(find.text('整理素材'));
        await tester.pumpAndSettle();
      }

      Finder estimator() => find.ancestor(
        of: find.text('预计时长（可选）'),
        matching: find.byType(TextField),
      );

      Future<void> switchUnit(String label) async {
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await openEditor();
      expect(find.text('预计时长（可选）'), findsOneWidget);
      expect(find.textContaining('（分钟，可选）'), findsNothing);
      await tester.enterText(estimator(), '90');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('90 分钟'), findsOneWidget);

      await openEditor();
      expect(tester.widget<TextField>(estimator()).controller!.text, '90');
      await switchUnit('小时');
      expect(tester.widget<TextField>(estimator()).controller!.text, '1.5');
      await switchUnit('分钟');
      expect(tester.widget<TextField>(estimator()).controller!.text, '90');

      // 非法值给出明确错误且不关闭弹窗。
      await switchUnit('小时');
      await tester.enterText(estimator(), '0.01');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('按分钟'), findsOneWidget);

      // 空值清除。
      await tester.enterText(estimator(), '');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('分钟', findRichText: true), findsNothing);
      expect(
        (await harness.tasks.getGoals()).first.tasks.first.estimatedMinutes,
        isNull,
      );

      // 1.5 小时 = 90 分钟精确换算。
      await openEditor();
      await switchUnit('小时');
      await tester.enterText(estimator(), '1.5');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('90 分钟'), findsOneWidget);
      final saved = (await harness.tasks.getGoals()).first.tasks.first;
      expect(saved.estimatedMinutes, 90);
      expect(tester.takeException(), isNull);

      // 1 分钟 → 小时 → 分钟 往返不因显示舍入漂移。
      await openEditor();
      await tester.enterText(estimator(), '1');
      await switchUnit('小时');
      final hoursText = tester.widget<TextField>(estimator()).controller!.text;
      // 切换不截断精度（不出现 0.02 之类的显示舍入）。
      expect(hoursText.startsWith('0.0166'), isTrue, reason: hoursText);
      await switchUnit('分钟');
      final backText = tester.widget<TextField>(estimator()).controller!.text;
      expect(backText, '1');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('1 分钟'), findsOneWidget);

      // 粘贴的非法文本不被静默过滤，给出明确错误。
      await openEditor();
      await tester.enterText(estimator(), '-1');
      expect(tester.widget<TextField>(estimator()).controller!.text, '-1');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请输入大于 0'), findsOneWidget);

      // 非整数分钟与超出范围的值都有明确错误。
      await switchUnit('小时');
      await tester.enterText(estimator(), '1.005');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('按分钟需为整数'), findsOneWidget);
      await tester.enterText(estimator(), '999999999999999999');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('超出可存储范围'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    } finally {
      await _unmountAndSettle(tester);
      await harness.dispose();
    }
  });

  testWidgets('11b 320 宽正常字号下预计时长行不溢出', (tester) async {
    final harness = await _Harness.create();
    try {
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
      await _pumpApp(tester, harness, size: const Size(320, 800));
      await tester.ensureVisible(find.text('整理素材'));
      await tester.tap(find.text('整理素材'));
      await tester.pumpAndSettle();
      final label = find.text('预计时长（可选）');
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      expect(label, findsOneWidget);
      expect(find.text('单位'), findsOneWidget);
      final field = tester.getRect(
        find.ancestor(of: label, matching: find.byType(TextField)),
      );
      final dialog = tester.getRect(find.byType(AlertDialog));
      expect(field.left, greaterThanOrEqualTo(dialog.left));
      expect(field.right, lessThanOrEqualTo(dialog.right));
      expect(tester.takeException(), isNull);
    } finally {
      await _unmountAndSettle(tester);
      await harness.dispose();
    }
  });

  testWidgets('10 国策卡详情只保留编辑卡片改名入口', (tester) async {
    final harness = await _Harness.create();
    try {
      await harness.nationalFocus.createCard(
        const NationalFocusCardDraft(
          name: '先写第一步',
          triggerCondition: '坐到书桌前',
          action: '写下第一步',
        ),
      );
      await _pumpApp(tester, harness);
      await _openNationalFocusTab(tester);
      await _openLibrary(tester);
      await tester.tap(find.byTooltip('卡片操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      expect(find.text('国策卡详情'), findsOneWidget);

      // The detail offers a single visible edit entry and no separate rename.
      expect(find.text('编辑卡片'), findsOneWidget);
      expect(find.byTooltip('卡片操作'), findsNothing);
      expect(find.text('修改名称'), findsNothing);

      await tester.tap(find.text('编辑卡片'));
      await tester.pumpAndSettle();
      final nameField = find.ancestor(
        of: find.text('卡片名称'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(nameField, '改过的名字');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('国策卡详情'), findsOneWidget);
      expect(find.text('改过的名字'), findsWidgets);
      final renamed = (await harness.nationalFocus.getLibraryCards()).single;
      expect(renamed.name, '改过的名字');
      expect(renamed.effectiveAction, '写下第一步');
      expect(tester.takeException(), isNull);
    } finally {
      await _unmountAndSettle(tester);
      await harness.dispose();
    }
  });

  testWidgets('6 国策卡详情可进入强化管理并在返回后刷新要求', (tester) async {
    final harness = await _Harness.create();
    try {
      final card = await harness.nationalFocus.createCard(
        const NationalFocusCardDraft(
          name: '先写第一步',
          triggerCondition: '坐到书桌前',
          action: '写下第一步',
        ),
      );
      await harness.nationalFocus.saveStrengtheningLevel(
        cardId: card.id,
        draft: const NationalFocusStrengtheningLevelDraft(
          triggerCondition: '起床后坐到书桌前',
          action: '写下第一步并读一遍',
        ),
      );
      await harness.nationalFocus.selectStrengtheningLevel(
        cardId: card.id,
        levelNumber: 1,
      );
      await _pumpApp(tester, harness);
      await _openNationalFocusTab(tester);
      await _openLibrary(tester);
      await tester.tap(find.byTooltip('卡片操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      expect(find.textContaining('当前规则 · 强化等级 1'), findsOneWidget);
      // Strengthening management is entered from the card editor only.
      expect(find.text('管理强化要求'), findsNothing);
      await tester.tap(find.text('编辑卡片'));
      await tester.pumpAndSettle();
      final entry = find.text('管理强化要求');
      expect(entry, findsOneWidget);
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('国策强化要求'), findsOneWidget);
      expect(find.text('当前使用 · 强化等级 1'), findsOneWidget);
      expect(find.textContaining('生效版本记录'), findsOneWidget);

      final reset = find.descendant(
        of: find.byKey(
          const ValueKey('national-focus-strengthening-level-base'),
        ),
        matching: find.text('选择'),
      );
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(find.text('当前使用 · 基础要求'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('编辑国策卡'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('国策卡详情'), findsOneWidget);
      expect(find.text('国策规则'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _unmountAndSettle(tester);
      await harness.dispose();
    }
  });
}
