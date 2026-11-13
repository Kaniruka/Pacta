import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_strengthening_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;
  late LocalNationalFocusRepository repository;

  setUp(() {
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'strengthening-user',
      cloudSyncEnabled: false,
      now: () => DateTime.utc(2026, 11, 13, 9),
    );
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  Future<void> pumpPage(WidgetTester tester, NationalFocusCard card) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NationalFocusStrengtheningPage(
          repository: repository,
          cardId: card.id,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('强化等级只录入国策规则并保留旧触发存储', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final card = await repository.createCard(
      const NationalFocusCardDraft(
        name: '阅读',
        triggerCondition: '旧基础触发',
        action: '阅读 5 页',
        exceptionNotes: '出差时顺延',
      ),
    );
    await repository.saveStrengtheningLevel(
      cardId: card.id,
      draft: const NationalFocusStrengtheningLevelDraft(
        triggerCondition: '旧强化触发',
        action: '阅读 10 页',
      ),
    );
    await pumpPage(tester, card);

    expect(find.text('触发条件'), findsNothing);
    expect(find.text('旧基础触发'), findsNothing);
    expect(find.text('阅读 5 页'), findsWidgets);
    // The management page keeps one current requirement plus a compact list;
    // exception notes stay in the reading layers.
    expect(find.text('例外与判例'), findsNothing);
    expect(find.text('出差时顺延'), findsNothing);

    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑强化等级 1'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('强化后的国策规则'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '阅读 20 页');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();

    final updated = await repository.getCard(card.id);
    expect(updated.strengtheningLevels, hasLength(1));
    expect(updated.strengtheningLevels.single.action, '阅读 20 页');
    expect(updated.strengtheningLevels.single.triggerCondition, '旧强化触发');
    expect(find.text('阅读 20 页'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('仅旧触发覆盖的等级允许留空国策规则并保持版本历史', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final card = await repository.createCard(
      const NationalFocusCardDraft(name: '阅读', action: '阅读 5 页'),
    );
    await repository.saveStrengtheningLevel(
      cardId: card.id,
      draft: const NationalFocusStrengtheningLevelDraft(
        triggerCondition: '仅旧触发',
      ),
    );
    final before = await repository.getCard(card.id);
    expect(before.strengtheningLevels.single.action, isNull);
    expect(before.requirementVersions, hasLength(1));
    await pumpPage(tester, card);

    await tester.tap(find.text('选择'));
    await tester.pumpAndSettle();
    // Adopting the level records its own requirement version; editing must not
    // add another one when the rule stays unchanged.
    final versionsAfterSelect = (await repository.getCard(card.id))
        .requirementVersions
        .length;
    await tester.tap(find.byTooltip('编辑强化等级 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('留空则沿用基础要求'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();

    expect(find.text('填写强化后的国策规则。'), findsNothing);
    final after = await repository.getCard(card.id);
    expect(after.strengtheningLevels.single.action, isNull);
    expect(after.strengtheningLevels.single.triggerCondition, '仅旧触发');
    expect(after.requirementVersions, hasLength(versionsAfterSelect));
    expect(after.effectiveAction, '阅读 5 页');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('新建强化等级要求填写强化后的国策规则', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final card = await repository.createCard(
      const NationalFocusCardDraft(name: '阅读', action: '阅读 5 页'),
    );
    await pumpPage(tester, card);

    await tester.tap(find.text('新建强化要求'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('填写强化后的国策规则。'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '阅读 10 页');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();

    final updated = await repository.getCard(card.id);
    expect(updated.strengtheningLevels, hasLength(1));
    expect(updated.strengtheningLevels.single.action, '阅读 10 页');
    expect(updated.strengtheningLevels.single.triggerCondition, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
