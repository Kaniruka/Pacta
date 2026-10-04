import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;
  late LocalNationalFocusRepository repository;
  var now = DateTime.utc(2026, 9, 25, 19, 59);

  setUp(() {
    now = DateTime.utc(2026, 9, 25, 19, 59);
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'user-a',
      now: () => now,
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  Future<NationalFocusCard> createPlacedCard() async {
    final card = await repository.createCard(
      const NationalFocusCardDraft(
        triggerCondition: '坐到书桌前',
        action: '先写下今天的第一步',
      ),
    );
    await repository.placeCard(cardId: card.id, parentId: null);
    return card;
  }

  Future<void> pumpNationalFocusUi(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty &&
        find.byType(CustomScrollView).evaluate().isNotEmpty) {
      final scrollable = find
          .descendant(
            of: find.byType(CustomScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
    }
    if (finder.evaluate().isEmpty &&
        find.text('检查点与失败记录').evaluate().isNotEmpty) {
      final checkpoint = find.text('检查点与失败记录');
      await tester.ensureVisible(checkpoint);
      await tester.pump();
      await tester.tap(checkpoint);
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  testWidgets('国策树使用所选时区展示固定检查点并支持点亮、确认和选填熄灭原因', (tester) async {
    final card = await createPlacedCard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(
            repository: repository,
            now: () => now,
            displayTimeZoneLoader: () async => 'Asia/Tokyo',
          ),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);

    await reveal(tester, find.text('检查点与失败记录'));
    await tester.tap(find.text('检查点与失败记录'));
    await tester.pumpAndSettle();
    expect(find.text('下次检查点：2026-09-26 05:00 · Asia/Tokyo'), findsOneWidget);
    expect(
      find.text('固定规则为北京时间 04:00；显示时区 Asia/Tokyo 不会移动结算边界。'),
      findsOneWidget,
    );
    expect(find.text('点亮'), findsOneWidget);

    await reveal(tester, find.text('点亮'));
    await tester.pump();
    await tester.tap(find.text('点亮'));
    await pumpNationalFocusUi(tester);
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.lit,
    );
    expect(find.text('主动熄灭'), findsOneWidget);

    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await pumpNationalFocusUi(tester);
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    expect(find.text('确认今日继续有效'), findsOneWidget);
    await reveal(tester, find.text('一键确认今日'));
    await tester.pump();
    await tester.tap(find.text('一键确认今日'));
    await pumpNationalFocusUi(tester);
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.lit,
    );

    await reveal(tester, find.text('主动熄灭'));
    await tester.pump();
    await pumpNationalFocusUi(tester);
    await reveal(tester, find.text('主动熄灭'));
    await tester.pump();
    await tester.tap(find.text('主动熄灭'));
    await pumpNationalFocusUi(tester);
    expect(find.text('失败原因（可选）'), findsOneWidget);
    await reveal(tester, find.text('暂不填写'));
    await tester.pump();
    await tester.tap(find.text('暂不填写'));
    await pumpNationalFocusUi(tester);
    final extinguished = await repository.getCard(card.id);
    expect(extinguished.state, NationalFocusCardState.extinguished);
    expect(extinguished.failureReason, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('失败历史展示完整树快照并允许非阻断补充说明', (tester) async {
    final card = await createPlacedCard();
    await repository.lightCard(card.id);
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    now = DateTime.utc(2026, 9, 26, 20);
    await repository.settleDueCheckpoints();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(
            repository: repository,
            now: () => now,
            displayTimeZoneLoader: () async => 'Asia/Shanghai',
          ),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await reveal(tester, find.text('查看失败记录'));
    await tester.pump();
    await tester.tap(find.text('查看失败记录'));
    await pumpNationalFocusUi(tester);

    expect(find.text('国策失败记录'), findsOneWidget);
    expect(find.textContaining('1 个节点'), findsOneWidget);
    await reveal(tester, find.text('补充说明'));
    await tester.pump();
    await tester.tap(find.text('补充说明'));
    await pumpNationalFocusUi(tester);
    await tester.enterText(find.byType(TextFormField), '那天临时照顾家人');
    await reveal(tester, find.text('保存'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await pumpNationalFocusUi(tester);
    expect(find.text('编辑共同说明'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('待今日确认节点可直接主动熄灭且不需要先确认', (tester) async {
    final card = await createPlacedCard();
    await repository.lightCard(card.id);
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(
            repository: repository,
            now: () => now,
            displayTimeZoneLoader: () async => 'Asia/Shanghai',
          ),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);

    expect(find.text('确认今日继续有效'), findsOneWidget);
    expect(find.text('主动熄灭'), findsOneWidget);
    await reveal(tester, find.text('主动熄灭'));
    await tester.pump();
    await pumpNationalFocusUi(tester);
    await reveal(tester, find.text('主动熄灭'));
    await tester.pump();
    await tester.tap(find.text('主动熄灭'));
    await pumpNationalFocusUi(tester);
    await reveal(tester, find.text('暂不填写'));
    await tester.pump();
    await tester.tap(find.text('暂不填写'));
    await pumpNationalFocusUi(tester);

    final extinguished = await repository.getCard(card.id);
    expect(extinguished.state, NationalFocusCardState.extinguished);
    expect(extinguished.successfulDays, 1);
    expect(extinguished.failureReason, isNull);
    expect(find.text('确认今日继续有效'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('父节点熄灭时禁用后代点亮并在失败快照中标明连带来源', (tester) async {
    final parent = await createPlacedCard();
    final child = await repository.createCard(
      const NationalFocusCardDraft(triggerCondition: '计划打开后', action: '先做第一项'),
    );
    await repository.placeCard(cardId: child.id, parentId: parent.id);
    await repository.lightCard(parent.id);
    await repository.lightCard(child.id);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(
            repository: repository,
            now: () => now,
            displayTimeZoneLoader: () async => 'Asia/Shanghai',
          ),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);

    await reveal(tester, find.text('主动熄灭').first);
    await tester.pump();
    await reveal(tester, find.text('主动熄灭').first);
    await tester.pump();
    await tester.tap(find.text('主动熄灭').first);
    await pumpNationalFocusUi(tester);
    expect(find.textContaining('也会熄灭 1 个后代'), findsOneWidget);
    await reveal(tester, find.text('暂不填写'));
    await tester.pump();
    await tester.tap(find.text('暂不填写'));
    await pumpNationalFocusUi(tester);

    expect(
      (await repository.getCard(child.id)).state,
      NationalFocusCardState.extinguished,
    );
    expect(find.textContaining('因「坐到书桌前」连带熄灭'), findsOneWidget);
    final lightButtons = find.widgetWithText(FilledButton, '点亮');
    expect(lightButtons, findsNWidgets(2));
    expect(tester.widget<FilledButton>(lightButtons.last).onPressed, isNull);

    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await pumpNationalFocusUi(tester);
    await reveal(tester, find.text('查看失败记录'));
    await tester.pump();
    await tester.tap(find.text('查看失败记录'));
    await pumpNationalFocusUi(tester);
    await tester.tap(find.textContaining('· 1 个节点'));
    await pumpNationalFocusUi(tester);

    expect(find.textContaining('独立失败来源'), findsOneWidget);
    expect(find.textContaining('因「坐到书桌前」连带熄灭'), findsOneWidget);
    final failures = await repository.getFailures();
    expect(failures, hasLength(1));
    expect(failures.single.cardId, parent.id);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('重新放置有效节点时不能选择熄灭父节点', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final extinguishedParent = await repository.createCard(
      const NationalFocusCardDraft(triggerCondition: '准备休息', action: '关闭工作页面'),
    );
    final activeRoot = await createPlacedCard();
    await repository.placeCard(cardId: extinguishedParent.id, parentId: null);
    await repository.lightCard(activeRoot.id);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(
            repository: repository,
            now: () => now,
            displayTimeZoneLoader: () async => 'Asia/Shanghai',
          ),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);

    await reveal(tester, find.text('详情'));
    await tester.pump();
    await tester.tap(find.text('详情'));
    await pumpNationalFocusUi(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await pumpNationalFocusUi(tester);
    final relocationButton = find.text('调整树中位置').last;
    await reveal(tester, relocationButton);
    await tester.pump();
    await tester.tap(relocationButton);
    await pumpNationalFocusUi(tester);

    expect(find.text('不能把有效分支放到本人、后代或熄灭分支下。'), findsOneWidget);
    expect((await repository.getCard(activeRoot.id)).parentId, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('用户可编辑并切换强化要求且详情与卡片库显示当前内容', (tester) async {
    final card = await createPlacedCard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(
            repository: repository,
            now: () => now,
            displayTimeZoneLoader: () async => 'Asia/Shanghai',
          ),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await reveal(tester, find.text('详情'));
    await tester.pump();
    await tester.tap(find.text('详情'));
    await pumpNationalFocusUi(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await pumpNationalFocusUi(tester);
    await reveal(tester, find.text('管理强化要求'));
    await tester.pump();
    await tester.tap(find.text('管理强化要求'));
    await pumpNationalFocusUi(tester);

    expect(find.text('国策强化要求'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -350));
    await pumpNationalFocusUi(tester);
    expect(find.text('强化等级 0/5'), findsOneWidget);
    expect(find.text('基础要求'), findsOneWidget);
    await reveal(tester, find.text('新建强化等级'));
    await tester.pump();
    await tester.tap(find.text('新建强化等级'));
    await pumpNationalFocusUi(tester);
    expect(find.text('基础行动'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('strengthened-action')),
      '每天阅读 10 页',
    );
    await reveal(tester, find.text('保存'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await pumpNationalFocusUi(tester);

    expect(find.text('强化等级 1/5'), findsOneWidget);
    expect(find.text('每天阅读 10 页'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -350));
    await pumpNationalFocusUi(tester);
    await reveal(tester, find.text('采用强化等级 1'));
    await tester.pump();
    await tester.tap(find.text('采用强化等级 1'));
    await pumpNationalFocusUi(tester);
    expect((await repository.getCard(card.id)).effectiveAction, '每天阅读 10 页');

    await tester.pageBack();
    await pumpNationalFocusUi(tester);
    expect(find.text('每天阅读 10 页'), findsOneWidget);

    await repository.moveCardToLibrary(card.id);
    await pumpNationalFocusUi(tester);
    await reveal(tester, find.text('卡片库'));
    await tester.pump();
    await tester.tap(find.text('卡片库'));
    await pumpNationalFocusUi(tester);
    expect(find.text('当前要求 · 强化等级 1'), findsOneWidget);
    expect(find.text('每天阅读 10 页'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('竖向树让父节点位于并排子分支上方，首次完整显示父节点', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final root = await createPlacedCard();
    final children = <NationalFocusCard>[];
    for (var index = 0; index < 2; index++) {
      final child = await repository.createCard(
        NationalFocusCardDraft(
          triggerCondition: '子条件 $index',
          action: '子行动 $index',
        ),
      );
      await repository.placeCard(cardId: child.id, parentId: root.id);
      children.add(child);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    Rect node(NationalFocusCard card) =>
        tester.getRect(find.byKey(ValueKey('national-focus-node-${card.id}')));
    final parentRect = node(root);
    expect(parentRect.left, greaterThanOrEqualTo(20));
    expect(parentRect.right, lessThanOrEqualTo(340));
    expect(node(children.first).top, greaterThan(parentRect.bottom));
    expect(node(children.first).top, node(children.last).top);
    expect(
      (node(children.last).center.dx - node(children.first).center.dx).abs(),
      greaterThan(node(children.first).width),
    );
    expect(find.text(root.effectiveTriggerCondition), findsOneWidget);
    expect(find.text(root.effectiveAction), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('深层国策树在窄屏两倍字号保持卡片宽度且可滚动维护', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final root = await createPlacedCard();
    var parent = root;
    for (var index = 0; index < 12; index++) {
      final child = await repository.createCard(
        NationalFocusCardDraft(
          triggerCondition: '深层条件 $index',
          action: '完整行动要求 $index',
        ),
      );
      await repository.placeCard(cardId: child.id, parentId: parent.id);
      parent = child;
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pump();
    final rootFinder = find.byKey(ValueKey('national-focus-node-${root.id}'));
    final leafFinder = find.byKey(ValueKey('national-focus-node-${parent.id}'));
    final rootWidth = tester.getSize(rootFinder).width;
    expect(tester.getSize(leafFinder).width, rootWidth);
    expect(rootWidth, lessThanOrEqualTo(320));
    await tester.ensureVisible(leafFinder);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('结构节点的详情按钮可查看完整连续记录与内化进度', (tester) async {
    final card = await createPlacedCard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    expect(find.text('顶层位置'), findsNothing);
    expect(find.textContaining('当前连续'), findsNothing);
    final detailButton = find.byTooltip('显示详情');
    await reveal(tester, detailButton);
    await tester.tap(detailButton);
    await pumpNationalFocusUi(tester);
    expect(find.text('节点 1'), findsOneWidget);
    expect(find.textContaining('当前连续'), findsOneWidget);
    expect(find.textContaining('内化进度'), findsOneWidget);
    expect(find.text(card.effectiveTriggerCondition), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
