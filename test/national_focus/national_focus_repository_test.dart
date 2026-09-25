import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  late PactaDatabase database;
  late LocalNationalFocusRepository repository;

  final now = DateTime.utc(2026, 9, 25, 8);

  setUp(() {
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

  NationalFocusCardDraft draft(String trigger, String action) =>
      NationalFocusCardDraft(
        triggerCondition: trigger,
        action: action,
        scope: '仅工作日',
        exceptionNotes: '出差时顺延',
      );

  test('创建卡片先进入卡片库，放置后重建仓储仍保留位置和熄灭状态', () async {
    final card = await repository.createCard(draft('开始工作前', '整理桌面'));

    expect((await repository.getLibraryCards()).single.id, card.id);
    expect(await repository.getTreeCards(), isEmpty);
    expect(card.state, NationalFocusCardState.extinguished);

    await repository.placeCard(cardId: card.id, parentId: null);
    final treeCard = (await repository.getTreeCards()).single;
    expect(treeCard.isTopLevel, isTrue);
    expect(treeCard.parentId, isNull);
    expect(treeCard.state, NationalFocusCardState.extinguished);
    expect(await repository.getLibraryCards(), isEmpty);

    await repository.dispose();
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'user-a',
      now: () => now,
    );
    final restored = (await repository.getTreeCards()).single;
    expect(restored.id, card.id);
    expect(restored.triggerCondition, '开始工作前');
    expect(restored.action, '整理桌面');
    expect(restored.scope, '仅工作日');
    expect(restored.exceptionNotes, '出差时顺延');
    expect(restored.isTopLevel, isTrue);
    expect(restored.state, NationalFocusCardState.extinguished);
  });

  test('不同 userId 看不到其他用户的卡片', () async {
    final card = await repository.createCard(draft('早餐后', '阅读十分钟'));
    final otherUser = LocalNationalFocusRepository(
      database: database,
      userId: 'user-b',
      now: () => now,
    );
    addTearDown(otherUser.dispose);

    expect(await otherUser.getLibraryCards(), isEmpty);
    expect(await otherUser.getTreeCards(), isEmpty);
    await expectLater(otherUser.getCard(card.id), throwsStateError);
  });

  test('拒绝把自己或自己的后代设为父节点', () async {
    final root = await repository.createCard(draft('到办公室后', '打开计划'));
    final child = await repository.createCard(draft('计划打开后', '先做第一项'));
    await repository.placeCard(cardId: root.id, parentId: null);
    await repository.placeCard(cardId: child.id, parentId: root.id);

    await expectLater(
      repository.placeCard(cardId: root.id, parentId: root.id),
      throwsArgumentError,
    );
    await expectLater(
      repository.placeCard(cardId: root.id, parentId: child.id),
      throwsArgumentError,
    );

    final tree = await repository.getTreeCards();
    expect(tree.singleWhere((card) => card.id == root.id).parentId, isNull);
    expect(tree.singleWhere((card) => card.id == child.id).parentId, root.id);
  });

  test('卡片放在顶层后只获得结构位置，不会因此点亮', () async {
    final card = await repository.createCard(draft('完成早餐后', '复习单词'));
    await repository.placeCard(cardId: card.id, parentId: null);

    final placed = (await repository.getTreeCards()).single;
    expect(placed.isInTree, isTrue);
    expect(placed.isTopLevel, isTrue);
    expect(placed.state, NationalFocusCardState.extinguished);
  });
}
