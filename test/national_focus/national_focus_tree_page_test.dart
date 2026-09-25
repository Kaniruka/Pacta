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
    await tester.pumpAndSettle();

    expect(find.text('下次检查点：2026-09-26 05:00 · Asia/Tokyo'), findsOneWidget);
    expect(
      find.text('固定规则为北京时间 04:00；显示时区 Asia/Tokyo 不会移动结算边界。'),
      findsOneWidget,
    );
    expect(find.text('点亮'), findsOneWidget);

    await tester.tap(find.text('点亮'));
    await tester.pumpAndSettle();
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.lit,
    );
    expect(find.text('主动熄灭'), findsOneWidget);

    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await tester.pumpAndSettle();
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    expect(find.text('确认今日继续有效'), findsOneWidget);
    await tester.tap(find.text('一键确认今日'));
    await tester.pumpAndSettle();
    expect(
      (await repository.getCard(card.id)).state,
      NationalFocusCardState.lit,
    );

    await tester.ensureVisible(find.text('主动熄灭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主动熄灭'));
    await tester.pumpAndSettle();
    expect(find.text('失败原因（可选）'), findsOneWidget);
    await tester.tap(find.text('暂不填写'));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看失败记录'));
    await tester.pumpAndSettle();

    expect(find.text('国策失败记录'), findsOneWidget);
    expect(find.textContaining('1 个节点'), findsOneWidget);
    await tester.tap(find.text('补充说明'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '那天临时照顾家人');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();

    expect(find.text('确认今日继续有效'), findsOneWidget);
    expect(find.text('主动熄灭'), findsOneWidget);
    await tester.ensureVisible(find.text('主动熄灭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主动熄灭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂不填写'));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('主动熄灭').first);
    await tester.tap(find.text('主动熄灭').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('也会熄灭 1 个后代'), findsOneWidget);
    await tester.tap(find.text('暂不填写'));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看失败记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('· 1 个节点'));
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();

    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    final relocationButton = find.text('调整树中位置').last;
    await tester.tap(relocationButton);
    await tester.pumpAndSettle();

    expect(find.text('不能把有效分支放到本人、后代或熄灭分支下。'), findsOneWidget);
    expect((await repository.getCard(activeRoot.id)).parentId, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
