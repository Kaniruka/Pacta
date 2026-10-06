import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
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
      cloudSyncEnabled: false,
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
        name: '坐到书桌前',
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

  Future<void> openNode(WidgetTester tester, NationalFocusCard card) async {
    final node = find.byKey(ValueKey('national-focus-node-${card.id}'));
    await tester.ensureVisible(node);
    await tester.tap(node);
    await tester.pumpAndSettle();
  }

  testWidgets('视图入口为文字下拉菜单', (tester) async {
    await createPlacedCard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NationalFocusTreePage(repository: repository)),
      ),
    );
    await pumpNationalFocusUi(tester);
    expect(find.text('简洁视图'), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    await tester.tap(find.text('简洁视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('详细视图').last);
    await tester.pumpAndSettle();
    expect(find.text('详细视图'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('三态操作首项固定，面板无状态标签改名与技术路径', (tester) async {
    final card = await createPlacedCard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    Future<void> expectFirst(String title) async {
      await openNode(tester, card);
      final first = tester.widget<ListTile>(find.byType(ListTile).first);
      expect((first.title! as Text).data, title);
      expect(find.byType(Chip), findsNothing);
      expect(find.text('修改名称'), findsNothing);
      expect(find.text('节点 1'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    }

    await expectFirst('点亮');
    await repository.lightCard(card.id);
    await pumpNationalFocusUi(tester);
    await expectFirst('主动熄灭');
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await pumpNationalFocusUi(tester);
    await expectFirst('确认今日继续有效');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('卡片库更多菜单改名保持规则与树外状态', (tester) async {
    final card = await repository.createCard(
      const NationalFocusCardDraft(
        name: '库卡原名',
        triggerCondition: '开始前',
        action: '执行动作',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: NationalFocusCardLibraryPage(repository: repository)),
    );
    await pumpNationalFocusUi(tester);
    await tester.tap(find.byTooltip('卡片操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改名称'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '库卡新名');
    await tester.tap(find.text('保存'));
    await pumpNationalFocusUi(tester);
    final renamed = await repository.getCard(card.id);
    expect(renamed.name, '库卡新名');
    expect(renamed.effectiveAction, '执行动作');
    expect(renamed.isInTree, isFalse);
    expect(find.text('库卡新名'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('详情独立阅读完整要求与记录，返回保持原画布', (tester) async {
    final card = await repository.createCard(
      const NationalFocusCardDraft(
        name: '完整规则卡',
        triggerCondition: '触发说明',
        action: '行动说明',
        scope: '范围说明',
        exceptionNotes: '可暂停一次',
      ),
    );
    await repository.placeCard(cardId: card.id, parentId: null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NationalFocusTreePage(repository: repository)),
      ),
    );
    await pumpNationalFocusUi(tester);
    await openNode(tester, card);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('国策卡详情'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('触发说明'), findsOneWidget);
    expect(find.text('行动说明'), findsOneWidget);
    expect(find.text('范围说明'), findsOneWidget);
    expect(find.text('可暂停一次'), findsOneWidget);
    expect(find.text('强化要求'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.textContaining('历史最高'), findsOneWidget);
    expect(find.textContaining('成功日'), findsNWidgets(2));
    expect(find.textContaining('内化进度'), findsOneWidget);
    expect(find.text('管理强化要求'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('national-focus-node-${card.id}')),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('父节点在上方且两个子节点并排，点击面板保持布局', (tester) async {
    final parent = await createPlacedCard();
    final children = <NationalFocusCard>[];
    for (var index = 0; index < 2; index++) {
      final card = await repository.createCard(
        NationalFocusCardDraft(
          name: '子节点 $index',
          triggerCondition: '条件',
          action: '行动',
        ),
      );
      await repository.placeCard(cardId: card.id, parentId: parent.id);
      children.add(card);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NationalFocusTreePage(repository: repository)),
      ),
    );
    await pumpNationalFocusUi(tester);
    Finder node(NationalFocusCard card) =>
        find.byKey(ValueKey('national-focus-node-${card.id}'));
    final parentRect = tester.getRect(node(parent));
    final firstRect = tester.getRect(node(children.first));
    final secondRect = tester.getRect(node(children.last));
    expect(parentRect.bottom, lessThan(firstRect.top));
    expect(firstRect.top, closeTo(secondRect.top, 0.1));
    final siblingRects = [firstRect, secondRect]
      ..sort((a, b) => a.left.compareTo(b.left));
    expect(siblingRects.first.right, lessThanOrEqualTo(siblingRects.last.left));
    await tester.tap(node(parent));
    await tester.pumpAndSettle();
    expect(find.text('查看详情'), findsOneWidget);
    expect(tester.getRect(node(parent)), parentRect);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('画布只显示适应屏幕图标，手势缩放后可恢复整树', (tester) async {
    await createPlacedCard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NationalFocusTreePage(repository: repository)),
      ),
    );
    await pumpNationalFocusUi(tester);
    final canvas = find.byKey(const ValueKey('national-focus-canvas'));
    final surface = find
        .ancestor(of: canvas, matching: find.byType(RawGestureDetector))
        .first;
    final fitted = tester.widget<Transform>(canvas).transform.clone();
    expect(find.byTooltip('适应屏幕'), findsOneWidget);
    expect(find.text('适应屏幕'), findsNothing);
    expect(find.byTooltip('画布缩放'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    final center = tester.getCenter(surface);
    final first = await tester.startGesture(
      center - const Offset(25, 0),
      pointer: 71,
    );
    final second = await tester.startGesture(
      center + const Offset(25, 0),
      pointer: 72,
    );
    await first.moveBy(const Offset(-25, 0));
    await second.moveBy(const Offset(25, 0));
    await tester.pump();
    expect(
      tester.widget<Transform>(canvas).transform.entry(0, 0),
      greaterThan(fitted.entry(0, 0)),
    );
    await first.up();
    await second.up();
    await tester.tap(find.byTooltip('适应屏幕'));
    await tester.pump();
    expect(
      tester.widget<Transform>(canvas).transform.storage,
      orderedEquals(fitted.storage),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('整树初始适应小于原始比例时双指缩放仍有效', (tester) async {
    for (var index = 0; index < 8; index++) {
      final card = await repository.createCard(
        NationalFocusCardDraft(
          name: '顶层节点 $index',
          triggerCondition: '顶层节点 $index',
          action: '完成行动 $index',
        ),
      );
      await repository.placeCard(cardId: card.id, parentId: null);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NationalFocusTreePage(repository: repository)),
      ),
    );
    await pumpNationalFocusUi(tester);
    final canvas = find.byKey(const ValueKey('national-focus-canvas'));
    final surface = find
        .ancestor(of: canvas, matching: find.byType(RawGestureDetector))
        .first;
    final initialScale = tester.widget<Transform>(canvas).transform.entry(0, 0);
    expect(initialScale, lessThan(1));

    final center = tester.getCenter(surface);
    final first = await tester.startGesture(
      center + const Offset(-25, 0),
      kind: ui.PointerDeviceKind.touch,
      pointer: 61,
    );
    final second = await tester.startGesture(
      center + const Offset(25, 0),
      kind: ui.PointerDeviceKind.touch,
      pointer: 62,
    );
    await first.moveBy(const Offset(-25, 0));
    await second.moveBy(const Offset(25, 0));
    await tester.pump();
    final zoomedScale = tester.widget<Transform>(canvas).transform.entry(0, 0);
    expect(zoomedScale, greaterThan(initialScale));
    await first.up();
    await second.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('触屏单指滚动页面，双指移动画布且抬起一指即停止移动', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var parent = await createPlacedCard();
    for (var index = 0; index < 8; index++) {
      final child = await repository.createCard(
        NationalFocusCardDraft(
          name: '深层 $index',
          triggerCondition: '深层 $index',
          action: '行动',
        ),
      );
      await repository.placeCard(cardId: child.id, parentId: parent.id);
      parent = child;
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NationalFocusTreePage(repository: repository)),
      ),
    );
    await pumpNationalFocusUi(tester);
    final canvas = find.byKey(const ValueKey('national-focus-canvas'));
    final gestureArea = find
        .ancestor(of: canvas, matching: find.byType(RawGestureDetector))
        .first;
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    final scrollPosition = tester.state<ScrollableState>(scrollable).position;
    final startScroll = scrollPosition.pixels;
    final center = tester.getCenter(gestureArea);
    expect(scrollPosition.maxScrollExtent, greaterThan(0));
    expect(center.dy, lessThan(tester.view.physicalSize.height));
    final original = tester.widget<Transform>(canvas).transform.clone();

    final one = await tester.startGesture(
      center,
      kind: ui.PointerDeviceKind.touch,
      pointer: 51,
    );
    await one.moveBy(const Offset(0, -100));
    await tester.pump();
    await one.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(scrollPosition.pixels, greaterThan(startScroll));
    expect(
      tester.widget<Transform>(canvas).transform.storage,
      orderedEquals(original.storage),
    );
    await one.up();
    await tester.pumpAndSettle();

    final touchCenter = tester.getCenter(gestureArea);
    final first = await tester.startGesture(
      touchCenter + const Offset(-35, 0),
      kind: ui.PointerDeviceKind.touch,
      pointer: 52,
    );
    final second = await tester.startGesture(
      touchCenter + const Offset(35, 0),
      kind: ui.PointerDeviceKind.touch,
      pointer: 53,
    );
    final beforePan = tester.widget<Transform>(canvas).transform.clone();
    await first.moveBy(const Offset(35, -55));
    await second.moveBy(const Offset(35, -55));
    await tester.pump();
    final afterPan = tester.widget<Transform>(canvas).transform.clone();
    expect(afterPan.storage, isNot(orderedEquals(beforePan.storage)));
    await first.moveBy(const Offset(-25, 0));
    await second.moveBy(const Offset(25, 0));
    await tester.pump();
    final afterPinch = tester.widget<Transform>(canvas).transform.clone();
    expect(afterPinch.entry(0, 0), greaterThan(afterPan.entry(0, 0)));
    await second.up();
    await first.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(
      tester.widget<Transform>(canvas).transform.storage,
      orderedEquals(afterPinch.storage),
    );
    await first.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Windows 滚轮只在按住 Ctrl 时缩放画布', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await createPlacedCard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NationalFocusTreePage(repository: repository)),
      ),
    );
    await pumpNationalFocusUi(tester);
    final canvas = find.byKey(const ValueKey('national-focus-canvas'));
    final area = find
        .ancestor(of: canvas, matching: find.byType(RawGestureDetector))
        .first;
    final center = tester.getCenter(area);
    final scrollable = find
        .descendant(
          of: find.byType(CustomScrollView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    final scrollPosition = tester.state<ScrollableState>(scrollable).position;
    final original = tester.widget<Transform>(canvas).transform.clone();
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 120)),
    );
    await tester.pump();
    expect(scrollPosition.pixels, greaterThan(0));
    expect(
      tester.widget<Transform>(canvas).transform.storage,
      orderedEquals(original.storage),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -120)),
    );
    await tester.pump();
    expect(
      tester.widget<Transform>(canvas).transform.storage,
      isNot(orderedEquals(original.storage)),
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    final mouseCenter = tester.getCenter(area);
    final beforeMousePan = tester.widget<Transform>(canvas).transform.clone();
    final mouse = await tester.startGesture(
      mouseCenter,
      kind: ui.PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await mouse.moveBy(const Offset(40, 25));
    await tester.pump();
    await mouse.moveBy(const Offset(20, 15));
    await tester.pump();
    expect(
      tester.widget<Transform>(canvas).transform.storage,
      isNot(orderedEquals(beforeMousePan.storage)),
    );
    await mouse.up();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  Future<void> tapAction(WidgetTester tester, String label) async {
    final action = find.text(label);
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

  Future<void> openRecords(WidgetTester tester) async {
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查点与失败记录'));
    await tester.pumpAndSettle();
  }

  testWidgets('页内标题、检查点二级入口与节点面板维护', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
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
    expect(find.text('今日确认 (0)'), findsOneWidget);
    await openRecords(tester);
    expect(find.text('下次检查点：2026-09-26 05:00 · Asia/Tokyo'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openNode(tester, card);
    expect(find.text('点亮'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前连续'), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openNode(tester, card);
    await tapAction(tester, '点亮');
    await pumpNationalFocusUi(tester);
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.lit,
    );
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await pumpNationalFocusUi(tester);
    expect(find.text('今日确认 (1)'), findsOneWidget);
    await tester.tap(find.text('今日确认 (1)'));
    await pumpNationalFocusUi(tester);
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.lit,
    );
    await openNode(tester, card);
    await tapAction(tester, '主动熄灭');
    await pumpNationalFocusUi(tester);
    expect(find.text('失败原因（可选）'), findsOneWidget);
    await tester.tap(find.text('暂不填写'));
    await pumpNationalFocusUi(tester);
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.extinguished,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('待今日确认节点可直接主动熄灭，失败记录保留当时名称与说明', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
    final card = await createPlacedCard();
    await repository.lightCard(card.id);
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await openNode(tester, card);
    expect(find.text('确认今日继续有效'), findsOneWidget);
    await tapAction(tester, '主动熄灭');
    await pumpNationalFocusUi(tester);
    await tester.tap(find.text('暂不填写'));
    await pumpNationalFocusUi(tester);
    expect((await repository.getCard(card.id)).successfulDays, 1);
    expect((await repository.getCard(card.id)).failureReason, isNull);
    now = DateTime.utc(2026, 9, 26, 20);
    await repository.settleDueCheckpoints();
    await pumpNationalFocusUi(tester);
    await openRecords(tester);
    await tester.tap(find.text('查看失败记录'));
    await pumpNationalFocusUi(tester);
    expect(find.text('国策失败记录'), findsOneWidget);
    await tester.tap(find.textContaining('· 1 个节点'));
    await pumpNationalFocusUi(tester);
    expect(find.text(card.name), findsWidgets);
    await tester.tap(find.text('补充说明'));
    await pumpNationalFocusUi(tester);
    await tester.enterText(find.byType(TextFormField), '临时照顾家人');
    await tester.tap(find.text('保存'));
    await pumpNationalFocusUi(tester);
    expect(find.text('编辑共同说明'), findsOneWidget);
    await tester.tap(find.text('编辑共同说明'));
    await pumpNationalFocusUi(tester);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '临时照顾家人',
    );
    await tester.tap(find.text('取消'));
    await pumpNationalFocusUi(tester);
    expect((await repository.getFailures()).single.sharedExplanation, '临时照顾家人');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('父节点熄灭级联后，后代在面板中不能点亮', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
    final parent = await createPlacedCard();
    final child = await repository.createCard(
      const NationalFocusCardDraft(
        name: '子节点',
        triggerCondition: '计划打开后',
        action: '先做第一项',
      ),
    );
    await repository.placeCard(cardId: child.id, parentId: parent.id);
    await repository.lightCard(parent.id);
    await repository.lightCard(child.id);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await openNode(tester, parent);
    await tapAction(tester, '主动熄灭');
    await pumpNationalFocusUi(tester);
    expect(find.textContaining('也会熄灭 1 个后代'), findsOneWidget);
    await tester.tap(find.text('暂不填写'));
    await pumpNationalFocusUi(tester);
    expect(
      (await repository.getCard(child.id)).state,
      NationalFocusCardState.extinguished,
    );
    await openNode(tester, child);
    final light = tester.widget<ListTile>(find.widgetWithText(ListTile, '点亮'));
    expect(light.enabled, isFalse);
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.textContaining('因「${parent.name}」连带熄灭'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('卡片可改名，添加库中或新建子节点后自动放置但保持熄灭', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
    final parent = await createPlacedCard();
    final existing = await repository.createCard(
      const NationalFocusCardDraft(
        name: '已有子卡',
        triggerCondition: '触发',
        action: '行动',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await openNode(tester, parent);
    expect(find.text('修改名称'), findsNothing);
    await tapAction(tester, '查看详情');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('卡片操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改名称'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '新的父名称');
    await tester.tap(find.text('保存'));
    await pumpNationalFocusUi(tester);
    expect((await repository.getCard(parent.id)).name, '新的父名称');
    expect(find.text('新的父名称'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openNode(tester, parent);
    await tapAction(tester, '添加子节点');
    await pumpNationalFocusUi(tester);
    await tester.tap(find.text('放入树画布'));
    await pumpNationalFocusUi(tester);
    final placed = await repository.getCard(existing.id);
    expect(placed.parentId, parent.id);
    expect(placed.state, NationalFocusCardState.extinguished);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  Future<void> createInLibrary(WidgetTester tester, String name) async {
    await tester.tap(find.text('新建国策卡'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), name);
    await tester.enterText(find.byType(TextFormField).at(1), '条件成立后');
    await tester.enterText(find.byType(TextFormField).at(2), '执行行动');
    await tester.tap(find.text('保存到卡片库'));
    await pumpNationalFocusUi(tester);
  }

  testWidgets('普通卡片库新建后留在库中，不自动选择树位置', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await tester.tap(find.byTooltip('卡片库'));
    await tester.pumpAndSettle();
    await createInLibrary(tester, '留在库中的卡');
    expect(find.text('国策卡片库'), findsOneWidget);
    expect((await repository.getLibraryCards()).single.name, '留在库中的卡');
    expect(await repository.getTreeCards(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('添加子节点中新建后直接挂到发起父节点且不点亮', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final parent = await createPlacedCard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await openNode(tester, parent);
    await tapAction(tester, '添加子节点');
    await tester.pumpAndSettle();
    await createInLibrary(tester, '新建的子国策');
    expect(find.text('国策卡片库'), findsNothing);
    final cards = await repository.getTreeCards();
    final child = cards.singleWhere((card) => card.id != parent.id);
    expect(child.name, '新建的子国策');
    expect(child.parentId, parent.id);
    expect(child.state, NationalFocusCardState.extinguished);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('添加待确认库卡保留原状态且提示确认，不自动点亮', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final parent = await createPlacedCard();
    await repository.lightCard(parent.id);
    final child = await repository.createCard(
      const NationalFocusCardDraft(
        name: '待恢复子卡',
        triggerCondition: '原条件',
        action: '原行动',
      ),
    );
    await repository.placeCard(cardId: child.id, parentId: null);
    await repository.lightCard(child.id);
    await repository.moveCardToLibrary(child.id);
    expect(
      (await repository.getCard(child.id)).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await openNode(tester, parent);
    await tapAction(tester, '添加子节点');
    await tester.pumpAndSettle();
    await tester.tap(find.text('放入树画布'));
    await pumpNationalFocusUi(tester);
    final placed = await repository.getCard(child.id);
    expect(placed.parentId, parent.id);
    expect(placed.state, NationalFocusCardState.pendingTodayConfirmation);
    expect(find.textContaining('请确认今日继续有效'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('有效节点不能移到熄灭父节点，移入库确认整子树语义', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
    final active = await createPlacedCard();
    final child = await repository.createCard(
      const NationalFocusCardDraft(
        name: '子卡',
        triggerCondition: '触发',
        action: '行动',
      ),
    );
    await repository.placeCard(cardId: child.id, parentId: active.id);
    final dark = await repository.createCard(
      const NationalFocusCardDraft(
        name: '熄灭父卡',
        triggerCondition: '触发',
        action: '行动',
      ),
    );
    await repository.placeCard(cardId: dark.id, parentId: null);
    await repository.lightCard(active.id);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await openNode(tester, active);
    await tapAction(tester, '调整树中位置');
    await pumpNationalFocusUi(tester);
    await tester.tap(find.byKey(ValueKey('national-focus-node-${dark.id}')));
    await pumpNationalFocusUi(tester);
    expect((await repository.getCard(active.id)).parentId, isNull);
    await tester.tap(find.byTooltip('取消选择位置'));
    await pumpNationalFocusUi(tester);
    await openNode(tester, active);
    await tapAction(tester, '移入卡片库');
    await tester.pumpAndSettle();
    expect(find.textContaining('1 张后代卡片将一起移入卡片库并解除父子关系'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '移入卡片库'));
    await pumpNationalFocusUi(tester);
    expect((await repository.getCard(active.id)).isInLibrary, isTrue);
    expect((await repository.getCard(child.id)).parentId, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('强化要求管理仍由节点面板进入', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
    final card = await createPlacedCard();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await openNode(tester, card);
    await tapAction(tester, '管理强化要求');
    await pumpNationalFocusUi(tester);
    expect(find.text('国策强化要求'), findsOneWidget);
    expect(find.text('基础要求'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('两倍字号窄屏节点和顶部操作可达且无裁切异常', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final card = await createPlacedCard();
    final longName = List.filled(12, '在重要工作开始之前保持专注').join();
    await repository.renameCard(cardId: card.id, name: longName);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    expect(find.byTooltip('卡片库'), findsOneWidget);
    expect(find.byTooltip('更多'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('适应屏幕'));
    await tester.pump();
    final canvas = find.byKey(const ValueKey('national-focus-canvas'));
    final gestureSurface = find
        .ancestor(of: canvas, matching: find.byType(RawGestureDetector))
        .first;
    final canvasRect = tester.getRect(gestureSurface);
    for (final control in [find.byTooltip('适应屏幕')]) {
      final rect = tester.getRect(control);
      expect(rect.left, greaterThanOrEqualTo(canvasRect.left));
      expect(rect.right, lessThanOrEqualTo(canvasRect.right));
    }
    final node = find.byKey(ValueKey('national-focus-node-${card.id}'));
    await tester.ensureVisible(node);
    await tester.tap(node);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(longName),
      ),
      findsOneWidget,
    );
    expect(find.text('查看详情'), findsOneWidget);
    await tapAction(tester, '查看详情');
    expect(find.text('国策卡详情'), findsOneWidget);
    expect(find.text(longName), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('放置时待核对父节点禁用', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });
    final pending = NationalFocusCard(
      name: '待核对父节点',
      id: 'pending-parent',
      triggerCondition: '待核对父节点',
      action: '行动',
      isInTree: true,
      state: NationalFocusCardState.extinguished,
      hasPendingReview: true,
      createdAt: now,
      updatedAt: now,
    );
    final library = NationalFocusCard(
      name: '待放置卡片',
      id: 'library-card',
      triggerCondition: '待放置卡片',
      action: '行动',
      isInTree: false,
      state: NationalFocusCardState.extinguished,
      createdAt: now,
      updatedAt: now,
    );
    final fake = _PendingPlacementRepository(pending, library);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: fake, now: () => now),
        ),
      ),
    );
    await pumpNationalFocusUi(tester);
    await tester.tap(find.byTooltip('卡片库'));
    await pumpNationalFocusUi(tester);
    await tester.tap(find.text('放入树画布'));
    await pumpNationalFocusUi(tester);
    final node = find.byKey(
      const ValueKey('national-focus-node-pending-parent'),
    );
    final semantics = find.descendant(
      of: node,
      matching: find.byType(Semantics),
    );
    expect(
      tester.widget<Semantics>(semantics.first).properties.enabled,
      isFalse,
    );
    expect(
      tester.widget<Semantics>(semantics.first).properties.label,
      contains('待核对'),
    );
    expect(
      tester.widget<Semantics>(semantics.first).properties.label,
      contains('待核对状态需先完成核对'),
    );
    await tester.tap(node);
    await pumpNationalFocusUi(tester);
    expect(fake.placeCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

class _PendingPlacementRepository extends UnavailableNationalFocusRepository {
  _PendingPlacementRepository(this.pending, this.library);
  final NationalFocusCard pending;
  final NationalFocusCard library;
  int placeCalls = 0;

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => Stream.value([pending]);
  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() =>
      Stream.value([library]);
  @override
  Future<void> placeCard({required String cardId, String? parentId}) async {
    placeCalls++;
  }
}
