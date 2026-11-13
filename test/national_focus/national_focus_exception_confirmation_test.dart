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
      userId: 'exception-user',
      cloudSyncEnabled: false,
      now: () => now,
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  Future<NationalFocusCard> createPlacedCard({
    required String name,
    required String action,
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
    return card;
  }

  Future<void> settleUi(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NationalFocusTreePage(repository: repository, now: () => now),
        ),
      ),
    );
    await settleUi(tester);
  }

  Future<void> openNode(WidgetTester tester, NationalFocusCard card) async {
    final node = find.byKey(ValueKey('national-focus-node-${card.id}'));
    await tester.ensureVisible(node);
    await tester.tap(node);
    await tester.pumpAndSettle();
  }

  Future<void> moveToPending() async {
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
  }

  testWidgets('全部确认先批量确认无例外节点，再逐项展示规则与例外', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final plain = await createPlacedCard(name: '批量卡', action: '打开今日计划');
    final withNotes = await createPlacedCard(
      name: '例外卡',
      action: '阅读十分钟',
      exceptionNotes: '出差时顺延',
    );
    await repository.lightCard(plain.id);
    await repository.lightCard(withNotes.id);
    await moveToPending();
    await pumpPage(tester);

    expect(find.text('全部确认 (2)'), findsOneWidget);
    await tester.tap(find.text('全部确认 (2)'));
    await settleUi(tester);

    expect(find.text('确认今日继续有效？'), findsOneWidget);
    expect(find.text('阅读十分钟'), findsOneWidget);
    expect(find.text('出差时顺延'), findsOneWidget);
    expect(find.text('这是最后一个例外节点'), findsOneWidget);
    expect(
      (await repository.getCard(plain.id)).state,
      NationalFocusCardState.lit,
    );

    await tester.tap(find.text('确认'));
    await settleUi(tester);

    expect(find.text('确认今日继续有效？'), findsNothing);
    expect(
      (await repository.getCard(withNotes.id)).state,
      NationalFocusCardState.lit,
    );
    expect(find.text('全部确认 (0)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('关闭逐项确认面板后例外节点仍待确认', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final card = await createPlacedCard(
      name: '例外卡',
      action: '阅读十分钟',
      exceptionNotes: '出差时顺延',
    );
    await repository.lightCard(card.id);
    await moveToPending();
    await pumpPage(tester);

    await tester.tap(find.text('全部确认 (1)'));
    await settleUi(tester);
    expect(find.text('确认今日继续有效？'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await settleUi(tester);

    expect(find.text('确认今日继续有效？'), findsNothing);
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    expect(find.text('全部确认 (1)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('全部为待确认例外卡时批量不改变状态', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final first = await createPlacedCard(
      name: '先创建的例外卡',
      action: '第一条规则',
      exceptionNotes: '第一个例外',
    );
    now = now.add(const Duration(seconds: 2));
    final second = await createPlacedCard(
      name: '后创建的例外卡',
      action: '第二条规则',
      exceptionNotes: '第二个例外',
    );
    await repository.lightCard(first.id);
    await repository.lightCard(second.id);
    await moveToPending();
    await pumpPage(tester);

    await tester.tap(find.text('全部确认 (2)'));
    await settleUi(tester);
    expect(find.text('第一条规则'), findsOneWidget);
    expect(find.text('还有 2 个例外节点待逐项确认'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await settleUi(tester);

    expect(find.text('确认今日继续有效？'), findsNothing);
    for (final card in [first, second]) {
      expect(
        (await repository.getCard(card.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );
    }
    expect(find.text('全部确认 (2)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('单点待确认例外节点在弹层只看当前规则并直接确认', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final card = await createPlacedCard(
      name: '例外卡',
      action: '阅读十分钟',
      exceptionNotes: '出差时顺延',
    );
    await repository.lightCard(card.id);
    await moveToPending();
    await pumpPage(tester);

    await openNode(tester, card);
    expect(find.text('阅读十分钟'), findsOneWidget);
    // The node sheet keeps one reading layer: the rule in force and actions.
    expect(find.text('例外与判例'), findsNothing);
    expect(find.text('出差时顺延'), findsNothing);
    await tester.tap(find.text('确认'));
    await settleUi(tester);

    expect(find.text('确认今日继续有效？'), findsNothing);
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.lit,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('逐项熄灭父节点后级联的子节点不再进入确认面板', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final parent = await createPlacedCard(
      name: '父例外卡',
      action: '父规则',
      exceptionNotes: '父例外',
    );
    now = now.add(const Duration(seconds: 2));
    final child = await repository.createCard(
      const NationalFocusCardDraft(
        name: '子例外卡',
        action: '子规则',
        exceptionNotes: '子例外',
      ),
    );
    await repository.placeCard(cardId: child.id, parentId: parent.id);
    await repository.lightCard(parent.id);
    await repository.lightCard(child.id);
    await moveToPending();
    await pumpPage(tester);

    await tester.tap(find.text('全部确认 (2)'));
    await settleUi(tester);
    expect(find.text('父规则'), findsOneWidget);
    await tester.tap(find.text('熄灭'));
    await settleUi(tester);
    expect(find.text('熄灭这个节点？'), findsOneWidget);
    await tester.tap(find.text('暂不填写'));
    await settleUi(tester);

    expect(find.text('确认今日继续有效？'), findsNothing);
    expect(
      (await repository.getCard(parent.id)).state,
      NationalFocusCardState.extinguished,
    );
    expect(
      (await repository.getCard(child.id)).state,
      NationalFocusCardState.extinguished,
    );
    expect(find.text('全部确认 (0)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('关闭熄灭原因框不算已处理，例外节点保持待确认', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final card = await createPlacedCard(
      name: '例外卡',
      action: '阅读十分钟',
      exceptionNotes: '出差时顺延',
    );
    await repository.lightCard(card.id);
    await moveToPending();
    await pumpPage(tester);

    await tester.tap(find.text('全部确认 (1)'));
    await settleUi(tester);
    await tester.tap(find.text('熄灭'));
    await settleUi(tester);
    expect(find.text('熄灭这个节点？'), findsOneWidget);
    expect(find.text('出差时顺延'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await settleUi(tester);

    expect(find.text('确认今日继续有效？'), findsNothing);
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    expect(find.text('全部确认 (1)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('已点亮节点熄灭原因框跨日后不熄灭新一天待确认节点', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final card = await createPlacedCard(name: '已点亮卡', action: '阅读十分钟');
    await repository.lightCard(card.id);
    await pumpPage(tester);

    await openNode(tester, card);
    await tester.tap(find.text('熄灭'));
    await settleUi(tester);
    expect(find.text('熄灭这个节点？'), findsOneWidget);

    now = DateTime.utc(2026, 9, 25, 20);
    await tester.tap(find.text('暂不填写'));
    await settleUi(tester);

    expect(find.text('熄灭这个节点？'), findsNothing);
    final settled = await repository.getCard(card.id);
    expect(settled.state, NationalFocusCardState.pendingTodayConfirmation);
    expect(settled.successfulDays, 1);
    expect(await repository.getFailures(), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('熄灭原因框跨过检查点后不提交旧熄灭', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final card = await createPlacedCard(
      name: '例外卡',
      action: '阅读十分钟',
      exceptionNotes: '出差时顺延',
    );
    await repository.lightCard(card.id);
    await moveToPending();
    await pumpPage(tester);

    await tester.tap(find.text('全部确认 (1)'));
    await settleUi(tester);
    await tester.tap(find.text('熄灭'));
    await settleUi(tester);
    expect(find.text('熄灭这个节点？'), findsOneWidget);

    now = DateTime.utc(2026, 9, 26, 20);
    await tester.tap(find.text('暂不填写'));
    await settleUi(tester);

    expect(find.text('熄灭这个节点？'), findsNothing);
    final settled = await repository.getCard(card.id);
    expect(settled.state, NationalFocusCardState.extinguished);
    expect(await repository.getFailures(), hasLength(1));
    expect((await repository.getFailures()).single.failureReason, '未完成今日确认');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('逐项确认跨过检查点后不重新点亮已失败节点', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final card = await createPlacedCard(
      name: '例外卡',
      action: '阅读十分钟',
      exceptionNotes: '出差时顺延',
    );
    await repository.lightCard(card.id);
    await moveToPending();
    await pumpPage(tester);

    await tester.tap(find.text('全部确认 (1)'));
    await settleUi(tester);
    expect(find.text('确认今日继续有效？'), findsOneWidget);

    // The window the panel was opened in has closed.
    now = DateTime.utc(2026, 9, 26, 20);
    await tester.tap(find.text('确认'));
    await settleUi(tester);

    expect(find.text('确认今日继续有效？'), findsNothing);
    final settled = await repository.getCard(card.id);
    expect(settled.state, NationalFocusCardState.extinguished);
    expect(settled.successfulDays, 1);
    expect(await repository.getFailures(), hasLength(1));
    expect(find.textContaining('确认窗口已跨过检查点'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('单点待确认跨过检查点后保持结算状态', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    final card = await createPlacedCard(
      name: '例外卡',
      action: '阅读十分钟',
      exceptionNotes: '出差时顺延',
    );
    await repository.lightCard(card.id);
    await moveToPending();
    await pumpPage(tester);

    await openNode(tester, card);
    now = DateTime.utc(2026, 9, 26, 20);
    await tester.tap(find.text('确认'));
    await settleUi(tester);

    final settled = await repository.getCard(card.id);
    expect(settled.state, NationalFocusCardState.extinguished);
    expect(await repository.getFailures(), hasLength(1));
    expect(find.textContaining('确认窗口已跨过检查点'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
