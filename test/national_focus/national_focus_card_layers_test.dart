import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_shared_widgets.dart';
import 'package:pacta/src/national_focus/national_focus_strengthening_page.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';
import 'package:pacta/src/theme/pacta_spacing.dart';
import 'package:pacta/src/theme/pacta_surfaces.dart';
import 'package:pacta/src/theme/pacta_theme.dart';

/// Lightweight layering of the national focus card surfaces: node sheet,
/// detail, card editor and strengthening management. Each test drives the
/// real page against the real local repository (Drift in memory).
void main() {
  late PactaDatabase database;
  late LocalNationalFocusRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'card-layers-user',
      cloudSyncEnabled: false,
      now: () => DateTime.utc(2026, 11, 13, 9),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  Future<void> pumpUi(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<NationalFocusCard> createTreeCard({
    String name = '晨光校准',
    String action = '闹钟第一次响起时打开床边灯。',
    String? exceptionNotes,
  }) async {
    final card = await repository.createCard(
      NationalFocusCardDraft(
        name: name,
        action: action,
        exceptionNotes: exceptionNotes,
      ),
    );
    await repository.placeCard(cardId: card.id, parentId: null);
    await repository.lightCard(card.id);
    return repository.getCard(card.id);
  }

  Future<void> pumpTree(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NationalFocusTreePage(repository: repository)),
      ),
    );
    await pumpUi(tester);
  }

  Future<void> openNode(WidgetTester tester, NationalFocusCard card) async {
    final node = find.byKey(ValueKey('national-focus-node-${card.id}'));
    await tester.ensureVisible(node);
    await tester.tap(node);
    await tester.pumpAndSettle();
  }

  Finder inSheet(Finder matching) =>
      find.descendant(of: find.byType(BottomSheet), matching: matching);

  testWidgets('节点弹层只有标题、当前规则与操作，不含分割线、例外与强化入口', (tester) async {
    final card = await createTreeCard(exceptionNotes: '当天取消安排记不适用。');
    await pumpTree(tester);
    await openNode(tester, card);

    expect(inSheet(find.text(card.name)), findsOneWidget);
    expect(inSheet(find.text(card.action)), findsOneWidget);
    expect(inSheet(find.text('例外与判例')), findsNothing);
    expect(inSheet(find.text('当天取消安排记不适用。')), findsNothing);
    expect(inSheet(find.text('强化要求')), findsNothing);
    expect(inSheet(find.byType(Divider)), findsNothing);
    expect(inSheet(find.text('查看详情')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('详情按需展开例外与判例，保留记录与编辑入口且不提供强化入口', (tester) async {
    final card = await createTreeCard(exceptionNotes: '当天取消安排记不适用。');
    await pumpTree(tester);
    await openNode(tester, card);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();

    expect(find.text('国策卡详情'), findsOneWidget);
    expect(find.text('例外与判例'), findsOneWidget);
    expect(find.text('当天取消安排记不适用。'), findsNothing);
    await tester.tap(find.text('例外与判例'));
    await tester.pumpAndSettle();
    expect(find.text('当天取消安排记不适用。'), findsOneWidget);

    expect(find.text('记录'), findsOneWidget);
    expect(find.textContaining('内化进度'), findsOneWidget);
    expect(find.text('强化要求'), findsNothing);
    // 编辑入口收进顶栏：页内不再有孤立的底部按钮。
    expect(
      find.byKey(const ValueKey('national-focus-detail-edit')),
      findsOneWidget,
    );
    expect(find.text('编辑卡片'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('编辑卡片是强化管理的入口，进入后返回保留未保存草稿', (tester) async {
    final card = await createTreeCard(exceptionNotes: '当天取消安排记不适用。');
    await pumpTree(tester);
    await openNode(tester, card);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('national-focus-detail-edit')));
    await tester.pumpAndSettle();

    expect(find.text('强化要求'), findsOneWidget);
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '未保存的名称');
    await tester.enterText(fields.at(1), '未保存的国策规则');
    await tester.pumpAndSettle();

    final manage = find.text('强化要求');
    await tester.ensureVisible(manage);
    await tester.pumpAndSettle();
    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(find.text('国策强化要求'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('编辑国策卡'), findsOneWidget);
    expect(find.text('未保存的名称'), findsOneWidget);
    expect(find.text('未保存的国策规则'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final updated = await repository.getCard(card.id);
    expect(updated.name, '未保存的名称');
    expect(updated.action, '未保存的国策规则');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  Future<void> seedLevels(NationalFocusCard card, List<String> rules) async {
    for (final rule in rules) {
      await repository.saveStrengtheningLevel(
        cardId: card.id,
        draft: NationalFocusStrengtheningLevelDraft(action: rule),
      );
    }
  }

  Future<void> pumpManager(
    WidgetTester tester,
    NationalFocusCard card, {
    Size size = const Size(900, 1800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NationalFocusStrengtheningPage(
          repository: repository,
          cardId: card.id,
        ),
      ),
    );
    await pumpUi(tester);
  }

  testWidgets('强化管理突出当前要求、紧凑列出其他等级并支持手动切换', (tester) async {
    final card = await createTreeCard(action: '基础规则');
    await seedLevels(card, ['强化规则 1', '强化规则 2', '强化规则 3']);
    await repository.selectStrengtheningLevel(cardId: card.id, levelNumber: 2);
    await pumpManager(tester, card);

    // 页面顶部不再复述当前要求：当前档只由可用要求列表里那一段表达。
    expect(find.text('当前使用 · 强化等级 2'), findsNothing);
    expect(find.text('可用要求'), findsOneWidget);
    expect(find.text('3 / 5 级'), findsOneWidget);
    expect(find.text('基础规则'), findsOneWidget);
    expect(find.text('强化规则 1'), findsOneWidget);
    expect(find.text('强化规则 3'), findsOneWidget);
    expect(find.text('正在使用'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('national-focus-strengthening-level-2')),
        matching: find.text('正在使用'),
      ),
      findsOneWidget,
      reason: '选中段自己承担「正在使用」状态',
    );

    final thirdRow = find.byKey(
      const ValueKey('national-focus-strengthening-level-3'),
    );
    await tester.tap(find.descendant(of: thirdRow, matching: find.text('选择')));
    await tester.pumpAndSettle();
    expect((await repository.getCard(card.id)).activeStrengtheningLevel, 3);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('national-focus-strengthening-level-3')),
        matching: find.text('正在使用'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('national-focus-strengthening-level-2')),
        matching: find.text('正在使用'),
      ),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('强化管理在五级上限后不再提供新建要求且没有版本记录', (tester) async {
    final card = await createTreeCard(action: '基础规则');
    await seedLevels(card, ['一级', '二级', '三级', '四级', '五级']);
    await pumpManager(tester, card);

    expect(find.text('5 / 5 级'), findsOneWidget);
    expect(find.text('已达 5 级上限'), findsOneWidget);
    final createRow = tester.widget<ListTile>(
      find.byKey(const ValueKey('national-focus-strengthening-create')),
    );
    expect(createRow.enabled, isFalse, reason: '到达上限后新建行不可点');
    expect(createRow.onTap, isNull);
    expect(
      find.byKey(const ValueKey('national-focus-version-history-card')),
      findsNothing,
    );
    expect(find.text('生效版本记录'), findsNothing);
    expect(
      find.byKey(const ValueKey('national-focus-version-history-disclosure')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('编辑强化要求时基础规则对照默认折叠并按需展开', (tester) async {
    final card = await createTreeCard(action: '基础规则内容');
    await seedLevels(card, ['强化规则内容']);
    await pumpManager(tester, card);

    final firstRow = find.byKey(
      const ValueKey('national-focus-strengthening-level-1'),
    );
    // The management list edits the requirement in force; adopting the level
    // first is how an inactive requirement becomes editable.
    await tester.tap(find.descendant(of: firstRow, matching: find.text('选择')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑强化等级 1'));
    await tester.pumpAndSettle();

    expect(find.text('强化后的国策规则'), findsOneWidget);
    expect(find.text('对照基础规则'), findsOneWidget);
    expect(find.text('基础规则内容'), findsNothing);
    await tester.tap(find.text('对照基础规则'));
    await tester.pumpAndSettle();
    expect(find.text('基础规则内容'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '改写后的强化规则');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    final updated = await repository.getCard(card.id);
    expect(updated.strengtheningLevels.single.action, '改写后的强化规则');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('窄屏 ${brightness.name} 主题下弹层、详情与编辑页可操作', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final card = await createTreeCard(exceptionNotes: '当天取消安排记不适用。');
      final base = ThemeData(brightness: brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: base,
          home: Scaffold(body: NationalFocusTreePage(repository: repository)),
        ),
      );
      await pumpUi(tester);
      await openNode(tester, card);
      expect(inSheet(find.text(card.name)), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(inSheet(find.text('查看详情')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('national-focus-detail-edit')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('national-focus-detail-edit')),
      );
      await tester.pumpAndSettle();
      expect(find.text('强化要求'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('强化要求'));
      await tester.pumpAndSettle();
      expect(find.text('国策强化要求'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('卡片库整卡进入详情，强化管理仍只从编辑卡片进入', (tester) async {
    final card = await repository.createCard(
      const NationalFocusCardDraft(name: '库卡', action: '库规则'),
    );
    await tester.pumpWidget(
      MaterialApp(home: NationalFocusCardLibraryPage(repository: repository)),
    );
    await pumpUi(tester);

    expect(find.text(card.name), findsOneWidget);
    // The direct library entry for strengthening management is gone.
    expect(find.textContaining('强化等级 0/5'), findsNothing);
    expect(find.text('强化要求'), findsNothing);
    // 整卡就是详情入口：不经过溢出菜单。
    await tester.tap(find.text(card.name));
    await tester.pumpAndSettle();
    expect(find.text('国策卡详情'), findsOneWidget);
    expect(find.text('强化要求'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('national-focus-detail-edit')));
    await tester.pumpAndSettle();
    expect(find.text('强化要求'), findsOneWidget);
    final manage = find.text('强化要求');
    await tester.ensureVisible(manage);
    await tester.pumpAndSettle();
    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(find.text('国策强化要求'), findsOneWidget);
    expect((await repository.getCard(card.id)).id, card.id);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('详情页规则区与记录区各自成一张 M3 Card', (tester) async {
    final card = await createTreeCard(exceptionNotes: '当天取消安排记不适用。');
    await pumpTree(tester);
    await openNode(tester, card);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();

    final header = find.byKey(
      const ValueKey('national-focus-detail-header-card'),
    );
    final rules = find.byKey(
      const ValueKey('national-focus-detail-rules-card'),
    );
    final records = find.byKey(
      const ValueKey('national-focus-detail-records-card'),
    );
    expect(header, findsOneWidget);
    expect(rules, findsOneWidget);
    expect(records, findsOneWidget);
    expect(
      tester.getRect(rules).left,
      moreOrLessEquals(tester.getRect(header).left, epsilon: 0.5),
      reason: '三张卡共用同一条阅读线',
    );
    expect(
      tester.getRect(records).left,
      moreOrLessEquals(tester.getRect(header).left, epsilon: 0.5),
    );
    // 状态与名称都在身份卡里，不在页面顶部裸排。
    expect(
      find.descendant(of: header, matching: find.text(card.state.label)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rules, matching: find.text('国策规则')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rules, matching: find.text('例外与判例')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: records, matching: find.text('记录')),
      findsOneWidget,
    );
    expect(find.descendant(of: rules, matching: find.text('记录')), findsNothing);
    // 百分比只在记录卡右上出现一次；底部只解释计算口径，不再抄第二遍。
    expect(
      find.descendant(of: records, matching: find.textContaining('%')),
      findsOneWidget,
    );
    expect(find.text('内化进度 · 按成功日累计计算'), findsOneWidget);
    // 两张卡片之间留一档 16dp 间隙：边界靠容器色与间距，不靠分割线。
    expect(
      tester.getRect(records).top - tester.getRect(rules).bottom,
      moreOrLessEquals(PactaSpacing.lg, epsilon: 0.01),
    );
    expect(find.byType(Divider), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('卡片库列表规则三行省略，长判例收成含判例徽标且底栏无重复删除', (tester) async {
    final longRule = List.filled(4, '坐到书桌前先写下今天的第一步，再核对昨天没有落地的部分。').join();
    const notes = '出差时顺延；当天取消安排记不适用。';
    await repository.createCard(
      NationalFocusCardDraft(
        name: '长规则卡',
        action: longRule,
        exceptionNotes: notes,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: NationalFocusCardLibraryPage(repository: repository)),
    );
    await pumpUi(tester);

    final rule = tester.widget<Text>(find.text(longRule));
    expect(rule.maxLines, 3);
    expect(rule.overflow, TextOverflow.ellipsis);
    expect(rule.style?.height, 1.45, reason: '三行正文用同一档行高');
    // 每张卡不再重复抄写「国策规则」机械标签：正文本身就是识别信息。
    expect(find.text('国策规则'), findsNothing);
    // 判例正文不铺出：列表只留一个轻徽标，全文在详情页。
    expect(find.text('含判例'), findsOneWidget);
    expect(find.textContaining('出差时顺延'), findsNothing);

    final cardSurface = find
        .ancestor(of: find.text('长规则卡'), matching: find.byType(Card))
        .first;
    expect(
      find.descendant(of: cardSurface, matching: find.text('放入国策树')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: cardSurface, matching: find.text('删除')),
      findsNothing,
      reason: '底栏不再并排一颗重复的删除按钮',
    );

    // 溢出菜单只剩查看详情与危险样式的删除。
    await tester.tap(find.byTooltip('卡片操作'));
    await tester.pumpAndSettle();
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    final deleteItem = tester.widget<Text>(find.text('删除'));
    expect(
      deleteItem.style?.color,
      Theme.of(tester.element(find.text('删除'))).colorScheme.error,
    );
    expect(find.text('编辑卡片'), findsNothing);
    expect(find.text('修改名称'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('强化管理可直接编辑非当前等级且不改变当前要求', (tester) async {
    final card = await createTreeCard(action: '基础规则');
    await seedLevels(card, ['强化规则 1', '强化规则 2']);
    await repository.selectStrengtheningLevel(cardId: card.id, levelNumber: 1);
    await pumpManager(tester, card);

    final secondRow = find.byKey(
      const ValueKey('national-focus-strengthening-level-2'),
    );
    expect(
      find.descendant(of: secondRow, matching: find.text('选择')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: secondRow, matching: find.byTooltip('编辑强化等级 2')),
    );
    await tester.pumpAndSettle();
    expect(find.text('强化后的国策规则'), findsOneWidget);
    expect(find.text('强化规则 2'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '改写后的二级规则');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();

    final after = await repository.getCard(card.id);
    expect(after.strengtheningLevels[1].action, '改写后的二级规则');
    expect(after.activeStrengtheningLevel, 1);
    expect(after.effectiveAction, '强化规则 1');
    expect(after.strengtheningLevels, hasLength(2));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('national-focus-strengthening-level-1')),
        matching: find.text('正在使用'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('窄屏强化管理把等级与操作留在首行，规则正文独占整行', (tester) async {
    final card = await createTreeCard(action: '基础规则');
    await seedLevels(card, ['强化规则 1', '强化规则 2']);
    await repository.selectStrengtheningLevel(cardId: card.id, levelNumber: 1);
    await pumpManager(tester, card, size: const Size(320, 1200));

    final activeRow = find.byKey(
      const ValueKey('national-focus-strengthening-level-1'),
    );
    final label = find.descendant(of: activeRow, matching: find.text('强化 1 级'));
    final status = find.descendant(of: activeRow, matching: find.text('正在使用'));
    final edit = find.descendant(
      of: activeRow,
      matching: find.byTooltip('编辑强化等级 1'),
    );
    final rule = find.descendant(of: activeRow, matching: find.text('强化规则 1'));

    final firstLineBottom = [
      label,
      status,
      edit,
    ].map((finder) => tester.getRect(finder).bottom).reduce(max);
    expect(tester.getRect(rule).top, greaterThanOrEqualTo(firstLineBottom - 1));
    expect(tester.getRect(rule).width, greaterThan(240));
    final editButton = find.descendant(
      of: activeRow,
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(editButton).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(editButton).height, greaterThanOrEqualTo(48));

    final otherRow = find.byKey(
      const ValueKey('national-focus-strengthening-level-2'),
    );
    final otherSelect = find.descendant(
      of: otherRow,
      matching: find.byType(TextButton),
    );
    final otherRule = find.descendant(
      of: otherRow,
      matching: find.text('强化规则 2'),
    );
    expect(
      tester.getRect(otherRule).top,
      greaterThanOrEqualTo(tester.getRect(otherSelect).bottom - 1),
    );
    expect(tester.getRect(otherRule).width, greaterThan(200));
    expect(tester.getSize(otherSelect).height, greaterThanOrEqualTo(48));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('宽屏强化管理保留等级与规则同一行的紧凑横排', (tester) async {
    final card = await createTreeCard(action: '基础规则');
    await seedLevels(card, ['强化规则 1']);
    await pumpManager(tester, card);

    final row = find.byKey(
      const ValueKey('national-focus-strengthening-level-1'),
    );
    final label = find.descendant(of: row, matching: find.text('强化 1 级'));
    final rule = find.descendant(of: row, matching: find.text('强化规则 1'));
    final labelRect = tester.getRect(label);
    final ruleRect = tester.getRect(rule);
    expect((ruleRect.top - labelRect.top).abs(), lessThan(8));
    expect(ruleRect.left, greaterThanOrEqualTo(labelRect.right));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('强化管理已移除生效版本记录，选中行保持实底并带主色强调条', (tester) async {
    final card = await createTreeCard(action: '基础规则');
    await seedLevels(card, ['强化规则 1', '强化规则 2']);
    await repository.selectStrengtheningLevel(cardId: card.id, levelNumber: 2);
    await pumpManager(tester, card);

    // 版本记录整块下线：正文里不再出现说明、白卡或版本条目。
    expect(find.text('生效版本记录'), findsNothing);
    expect(
      find.byKey(const ValueKey('national-focus-version-history-card')),
      findsNothing,
    );
    expect(find.textContaining('当前版本'), findsNothing);
    expect(find.textContaining('版本 '), findsNothing);

    final activeRow = find.byKey(
      const ValueKey('national-focus-strengthening-level-2'),
    );
    final inactiveRow = find.byKey(
      const ValueKey('national-focus-strengthening-level-1'),
    );
    final activeMaterial = tester.widget<Material>(
      find.descendant(of: activeRow, matching: find.byType(Material)).first,
    );
    final inactiveMaterial = tester.widget<Material>(
      find.descendant(of: inactiveRow, matching: find.byType(Material)).first,
    );
    final surfaces = PactaSurfaces.of(tester.element(activeRow));
    expect(
      activeMaterial.color,
      surfaces.card,
      reason: '选中行与列表同底，不再用半透明主色混出透明缺块',
    );
    expect(inactiveMaterial.color, surfaces.card);

    final activeBar = find.descendant(
      of: activeRow,
      matching: find.byKey(
        const ValueKey('national-focus-strengthening-active-bar'),
      ),
    );
    expect(activeBar, findsOneWidget);
    expect(
      tester.getSize(activeBar).width,
      moreOrLessEquals(3.5, epsilon: 0.01),
    );
    expect(
      find.descendant(
        of: inactiveRow,
        matching: find.byKey(
          const ValueKey('national-focus-strengthening-active-bar'),
        ),
      ),
      findsNothing,
      reason: '强调条只属于当前生效项',
    );
    expect(
      find.descendant(of: activeRow, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: activeRow, matching: find.text('正在使用')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('窄屏长规则完整换行且不缩小字号', (tester) async {
    const longRule = '坐下后先把今天最重要的三件事写进纸质本子，再逐条核对昨天的落实情况，最后决定今天是否调整顺序。';
    final card = await createTreeCard(action: '基础规则');
    await seedLevels(card, [longRule]);
    await repository.selectStrengtheningLevel(cardId: card.id, levelNumber: 1);
    await pumpManager(tester, card, size: const Size(320, 1200));

    final row = find.byKey(
      const ValueKey('national-focus-strengthening-level-1'),
    );
    final rule = find.descendant(of: row, matching: find.text(longRule));
    expect(rule, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(rule).didExceedMaxLines,
      isFalse,
    );
    final expected = Theme.of(tester.element(rule))
        .textTheme
        .bodyMedium!
        .fontSize;
    expect(tester.widget<Text>(rule).style?.fontSize, expected);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('详情在没有例外记录时不显示例外与判例分组', (tester) async {
    final card = await createTreeCard();
    await pumpTree(tester);
    await openNode(tester, card);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();

    expect(find.text('国策卡详情'), findsOneWidget);
    expect(find.text('例外与判例'), findsNothing);
    expect(find.text('记录'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('编辑页强化提示条与强化要求副标题跟随档位刷新', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final card = await createTreeCard(action: '基础规则');
    await seedLevels(card, ['强化规则 1', '强化规则 2']);
    final fresh = await repository.getCard(card.id);
    await tester.pumpWidget(
      MaterialApp(
        home: NationalFocusCardEditorPage(repository: repository, card: fresh),
      ),
    );
    await pumpUi(tester);

    // 初始没有启用强化档位：提示条不占位，副标题写基础要求。
    expect(find.textContaining('当前正使用强化等级'), findsNothing);
    expect(find.text('当前使用基础要求 · 进入调整草稿，随卡片一起保存'), findsOneWidget);

    final manage = find.text('强化要求');
    await tester.ensureVisible(manage);
    await tester.pumpAndSettle();
    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(find.text('国策强化要求'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('national-focus-strengthening-level-2')),
        matching: find.text('选择'),
      ),
    );
    await tester.pumpAndSettle();
    // 草稿态：选中只改内存，未点编辑页「保存」前不写库。
    expect(
      (await repository.getCard(card.id)).activeStrengtheningLevel,
      isNull,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('national-focus-strengthening-level-2')),
        matching: find.text('正在使用'),
      ),
      findsOneWidget,
    );

    await tester.pageBack();
    await pumpUi(tester);

    // 回到编辑页：提示条与副标题读的是草稿态，不是构造时的 widget.card。
    expect(find.text('当前正使用强化等级 2，此处修改的是基础要求。'), findsOneWidget);
    expect(find.text('当前使用强化等级 2 · 进入调整草稿，随卡片一起保存'), findsOneWidget);
    expect(find.text('2 / 5 级'), findsOneWidget);
    expect(find.text('编辑国策卡'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('例外与判例副标题随输入与清空实时切换', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final card = await repository.createCard(
      const NationalFocusCardDraft(name: '判例卡', action: '规则'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NationalFocusCardEditorPage(repository: repository, card: card),
      ),
    );
    await pumpUi(tester);
    expect(find.text('可选 · 按需展开'), findsOneWidget);
    expect(find.text('已填写 · 按需展开'), findsNothing);

    await tester.tap(find.text('例外与判例'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('national-focus-exception-notes'));
    await tester.enterText(field, '出差时顺延');
    await tester.pump();
    expect(find.text('已填写 · 按需展开'), findsOneWidget);
    expect(find.text('可选 · 按需展开'), findsNothing);

    await tester.enterText(field, '   ');
    await tester.pump();
    expect(find.text('可选 · 按需展开'), findsOneWidget);
    expect(find.text('已填写 · 按需展开'), findsNothing);

    await tester.enterText(field, '再次填写');
    await tester.pump();
    expect(find.text('已填写 · 按需展开'), findsOneWidget);
    // 副标题重建不影响输入内容与展开状态。
    expect(find.text('再次填写'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('身份卡展示已内化与连带说明，记录卡底部不重复百分比', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final internalized = NationalFocusCard(
      id: 'internalized-card',
      name: '已内化卡',
      triggerCondition: '',
      action: '规则',
      isInTree: true,
      state: NationalFocusCardState.lit,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      successfulDays: 180,
      currentConsecutiveDays: 3,
      bestConsecutiveDays: 9,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: pactaTheme(Brightness.light),
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(PactaSpacing.lg),
            children: [
              NationalFocusCardIdentityCard(
                card: internalized,
                cascadeNote: '父节点已恢复；此节点仍需单独点亮。',
              ),
              const SizedBox(height: PactaSpacing.lg),
              NationalFocusDetailRecordsCard(card: internalized),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已内化'), findsOneWidget);
    expect(find.text('点亮'), findsOneWidget);
    expect(find.text('父节点已恢复；此节点仍需单独点亮。'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NationalFocusCardIdentityCard),
        matching: find.text('已内化卡'),
      ),
      findsOneWidget,
    );
    // 右上角 100.0% 只出现一次，底部只解释口径。
    expect(find.text('100.0%'), findsOneWidget);
    expect(find.text('内化进度 · 按成功日累计计算'), findsOneWidget);
    expect(find.textContaining('内化进度 100.0%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已删除卡片保留恢复提示与恢复回调，窄卡片底栏自动堆叠', (tester) async {
    tester.view.physicalSize = const Size(280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final deleted = NationalFocusCard(
      id: 'deleted-card',
      name: '旧卡',
      triggerCondition: '',
      action: '旧规则',
      isInTree: false,
      state: NationalFocusCardState.extinguished,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );
    final fake = _DeletedCardRepository(deleted);
    await tester.pumpWidget(
      MaterialApp(home: NationalFocusCardLibraryPage(repository: fake)),
    );
    await pumpUi(tester);
    await tester.tap(find.text('已删除'));
    await tester.pumpAndSettle();

    expect(find.text('旧卡'), findsOneWidget);
    expect(find.text('恢复后会回到卡片库；树位置和点亮状态需要重新选择。'), findsOneWidget);
    final restore = find.widgetWithText(FilledButton, '恢复到卡片库');
    expect(restore, findsOneWidget);
    // 280dp 视口下卡片内容宽约 216dp（< 300dp）：进度摘要与按钮上下堆叠。
    final progress = find.textContaining('成功日');
    expect(progress, findsOneWidget);
    expect(
      tester.getRect(restore).top,
      greaterThanOrEqualTo(tester.getRect(progress).bottom),
      reason: '极窄卡片把操作按钮放到摘要下方，不再并排挤压',
    );
    expect(tester.getRect(restore).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(restore).right, lessThanOrEqualTo(280));
    expect(tester.takeException(), isNull);

    await tester.tap(restore);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(fake.restoredId, 'deleted-card');
    expect(fake.restoreCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

/// 只提供已删除列表的仓储：验证恢复回调，不触网、不写库。
class _DeletedCardRepository extends UnavailableNationalFocusRepository {
  _DeletedCardRepository(this.card);

  final NationalFocusCard card;
  int restoreCalls = 0;
  String? restoredId;

  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() =>
      Stream.value(const <NationalFocusCard>[]);

  @override
  Stream<List<NationalFocusCard>> watchDeletedCards() =>
      Stream.value(<NationalFocusCard>[card]);

  @override
  Future<void> restoreDeletedCard(String cardId) async {
    restoreCalls += 1;
    restoredId = cardId;
  }
}
