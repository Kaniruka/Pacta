import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_strengthening_page.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

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
    expect(inSheet(find.text('管理强化要求')), findsNothing);
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
    expect(find.text('管理强化要求'), findsNothing);
    expect(find.text('编辑卡片'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('编辑卡片是强化管理的入口，进入后返回保留未保存草稿', (tester) async {
    final card = await createTreeCard(exceptionNotes: '当天取消安排记不适用。');
    await pumpTree(tester);
    await openNode(tester, card);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑卡片'));
    await tester.pumpAndSettle();

    expect(find.text('管理强化要求'), findsOneWidget);
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '未保存的名称');
    await tester.enterText(fields.at(1), '未保存的国策规则');

    await tester.tap(find.text('管理强化要求'));
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

  Future<void> pumpManager(WidgetTester tester, NationalFocusCard card) async {
    tester.view.physicalSize = const Size(900, 1800);
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

    expect(find.text('当前使用 · 强化等级 2'), findsOneWidget);
    expect(find.text('可用要求'), findsOneWidget);
    expect(find.text('3 / 5 级'), findsOneWidget);
    expect(find.text('基础规则'), findsOneWidget);
    expect(find.text('强化规则 1'), findsOneWidget);
    expect(find.text('强化规则 3'), findsOneWidget);
    expect(find.text('正在使用'), findsOneWidget);

    final thirdRow = find.byKey(
      const ValueKey('national-focus-strengthening-level-3'),
    );
    await tester.tap(find.descendant(of: thirdRow, matching: find.text('选择')));
    await tester.pumpAndSettle();
    expect((await repository.getCard(card.id)).activeStrengtheningLevel, 3);
    expect(find.text('当前使用 · 强化等级 3'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('强化管理在五级上限后不再提供新建要求并保留版本记录', (tester) async {
    final card = await createTreeCard(action: '基础规则');
    await seedLevels(card, ['一级', '二级', '三级', '四级', '五级']);
    await pumpManager(tester, card);

    expect(find.text('5 / 5 级'), findsOneWidget);
    expect(find.text('已达 5 级上限'), findsOneWidget);
    final newButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '新建强化要求'),
    );
    expect(newButton.onPressed, isNull);
    expect(
      find.ancestor(
        of: find.textContaining('生效版本记录'),
        matching: find.byType(ExpansionTile),
      ),
      findsOneWidget,
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

  testWidgets('待核对状态阻断弹层操作与详情编辑入口', (tester) async {
    final now = DateTime.utc(2026, 11, 13, 9);
    final pending = NationalFocusCard(
      id: 'pending-review-card',
      name: '待核对卡片',
      triggerCondition: '',
      action: '待核对规则',
      isInTree: true,
      state: NationalFocusCardState.lit,
      hasPendingReview: true,
      createdAt: now,
      updatedAt: now,
    );
    final pendingRepository = _PendingReviewRepository(pending);
    addTearDown(pendingRepository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: pendingRepository),
        ),
      ),
    );
    await pumpUi(tester);
    await openNode(tester, pending);

    expect(inSheet(find.text('请先完成核对后再操作。')), findsOneWidget);
    final firstAction = tester.widget<ListTile>(
      inSheet(find.byType(ListTile)).first,
    );
    expect(firstAction.enabled, isFalse);

    await tester.tap(inSheet(find.text('查看详情')));
    await tester.pumpAndSettle();
    final editEntry = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '编辑卡片'),
    );
    expect(editEntry.onPressed, isNull);

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
      expect(find.text('编辑卡片'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('编辑卡片'));
      await tester.pumpAndSettle();
      expect(find.text('管理强化要求'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('管理强化要求'));
      await tester.pumpAndSettle();
      expect(find.text('国策强化要求'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

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
}

class _PendingReviewRepository extends UnavailableNationalFocusRepository {
  _PendingReviewRepository(this.card);

  final NationalFocusCard card;

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => Stream.value([card]);

  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() =>
      Stream.value(const <NationalFocusCard>[]);
}
