import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

import '../support/national_focus_reference_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PactaDatabase database;
  late LocalNationalFocusRepository repository;
  late NationalFocusReferenceFixture fixture;
  late NationalFocusReferenceSeed seed;

  setUp(() async {
    database = PactaDatabase(NativeDatabase.memory());
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'national-focus-reference-fixture',
      cloudSyncEnabled: false,
      now: () => DateTime.utc(2026, 9, 25, 10),
    );
    fixture = await NationalFocusReferenceFixture.load();
    seed = await fixture.seed(repository);
  });

  tearDown(() async {
    await repository.dispose();
    await database.close();
  });

  test('图片卡片数量、分类和父子层级映射到隔离的演示树', () async {
    final cards = await repository.getTreeCards();
    final cardsById = {for (final card in cards) card.id: card};

    expect(seed.ruleCount, 37);
    expect(seed.demoNodeCount, 13);
    expect(seed.totalNodeCount, 50);
    expect(cards, hasLength(50));
    expect(cards.where((card) => card.scope == '仅演示'), hasLength(13));
    expect(cards.where((card) => card.scope != '仅演示'), hasLength(37));

    final rootId = seed.cardId('national_focus_tree');
    final centralId = seed.cardId('rural_encirclement');
    expect(cardsById[rootId]!.parentId, isNull);
    expect(cardsById[centralId]!.parentId, rootId);

    for (final branchId in [
      'risk_avoidance',
      'means_of_revolution',
      'inner_journey',
    ]) {
      expect(cardsById[seed.cardId(branchId)]!.parentId, centralId);
    }
    expect(
      cardsById[seed.cardId('ready_to_go')]!.parentId,
      seed.cardId('risk_avoidance'),
    );
    expect(
      cardsById[seed.cardId('eat_well')]!.parentId,
      seed.cardId('means_of_revolution'),
    );
    expect(
      cardsById[seed.cardId('live_well')]!.parentId,
      seed.cardId('inner_journey'),
    );

    final router = cardsById[seed.cardId('router')]!;
    expect(router.parentId, rootId);
    expect(router.triggerCondition, '路由器');
    expect(router.action, contains('切换不同的国策树分支'));
    expect(router.state, NationalFocusCardState.extinguished);

    final breakfast = cardsById[seed.cardId('eat_breakfast')]!;
    expect(breakfast.parentId, seed.cardId('eat_well'));
    expect(breakfast.scope, '农村包围城市 › 革命的本钱 › 好好吃饭');

    final demoCards = cards.where((card) => card.scope == '仅演示');
    expect(
      demoCards.every(
        (card) =>
            card.action == nationalFocusReferenceDemoAction &&
            card.triggerCondition.isNotEmpty,
      ),
      isTrue,
    );
  });

  test('子节点逐级受父节点点亮门槛约束，父节点不会自动点亮后代', () async {
    final rootId = seed.cardId('national_focus_tree');
    final centralId = seed.cardId('rural_encirclement');
    final branchId = seed.cardId('risk_avoidance');
    final groupId = seed.cardId('ready_to_go');
    final ruleId = seed.cardId('pain_free_early_rise');
    final siblingId = seed.cardId('fully_prepared');

    await expectLater(repository.lightCard(ruleId), throwsStateError);
    await repository.lightCard(rootId);
    expect(
      (await repository.getCard(centralId)).state,
      NationalFocusCardState.extinguished,
    );
    await expectLater(repository.lightCard(ruleId), throwsStateError);

    for (final parentId in [centralId, branchId, groupId]) {
      await repository.lightCard(parentId);
    }
    await repository.lightCard(ruleId);

    expect(
      (await repository.getCard(ruleId)).state,
      NationalFocusCardState.lit,
    );
    expect(
      (await repository.getCard(siblingId)).state,
      NationalFocusCardState.extinguished,
    );
  });
}
