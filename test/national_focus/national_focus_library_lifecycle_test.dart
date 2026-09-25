import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
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

  Future<NationalFocusCard> createCard(String trigger) => repository.createCard(
    NationalFocusCardDraft(triggerCondition: trigger, action: '执行行动'),
  );

  test('重复移入卡片库和删除已不存在的卡片可安全重试', () async {
    final card = await createCard('可重试卡片');
    await repository.placeCard(cardId: card.id, parentId: null);

    await repository.moveCardToLibrary(card.id);
    final movedCard = await repository.getCard(card.id);
    await repository.moveCardToLibrary(card.id);

    expect((await repository.getCard(card.id)).updatedAt, movedCard.updatedAt);
    expect(
      await repository.deleteCard(card.id),
      NationalFocusCardDeletion.permanentlyDeleted,
    );
    expect(
      await repository.deleteCard(card.id),
      NationalFocusCardDeletion.permanentlyDeleted,
    );
  });

  test('将父卡移入卡片库会拆散整支分支，逐卡放回时保留记录', () async {
    final parent = await createCard('父卡');
    final child = await createCard('子卡');
    final grandchild = await createCard('孙卡');
    await repository.placeCard(cardId: parent.id, parentId: null);
    await repository.placeCard(cardId: child.id, parentId: parent.id);
    await repository.placeCard(cardId: grandchild.id, parentId: child.id);
    for (final card in [parent, child, grandchild]) {
      await repository.lightCard(card.id);
    }
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await repository.confirmToday();

    await repository.moveCardToLibrary(parent.id);

    expect(await repository.getTreeCards(), isEmpty);
    final library = await repository.getLibraryCards();
    expect(library.map((card) => card.id).toSet(), {
      parent.id,
      child.id,
      grandchild.id,
    });
    expect(library.every((card) => card.parentId == null), isTrue);
    expect(
      library.every(
        (card) => card.state == NationalFocusCardState.pendingTodayConfirmation,
      ),
      isTrue,
    );

    await repository.placeCard(cardId: child.id, parentId: null);
    await repository.lightCard(child.id);

    final restoredChild = await repository.getCard(child.id);
    expect(restoredChild.isInTree, isTrue);
    expect(restoredChild.parentId, isNull);
    expect(restoredChild.state, NationalFocusCardState.lit);
    expect(restoredChild.successfulDays, 1);
    expect(restoredChild.currentConsecutiveDays, 1);
    expect((await repository.getTreeCards()).map((card) => card.id), [
      child.id,
    ]);
    expect(
      (await repository.getLibraryCards()).map((card) => card.id).toSet(),
      {parent.id, grandchild.id},
    );
  });

  test('卡片库不参加一键确认，未及时放回的已启动维护周期只结算一次', () async {
    final parent = await createCard('父卡');
    final child = await createCard('子卡');
    final unused = await createCard('未点亮卡');
    await repository.placeCard(cardId: parent.id, parentId: null);
    await repository.placeCard(cardId: child.id, parentId: parent.id);
    await repository.lightCard(parent.id);
    await repository.lightCard(child.id);
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await repository.confirmToday();
    await repository.moveCardToLibrary(parent.id);

    expect(await repository.confirmToday(), 0);

    await repository.placeCard(cardId: child.id, parentId: null);
    await repository.lightCard(child.id);
    now = DateTime.utc(2026, 9, 26, 20);
    await repository.settleDueCheckpoints();

    final childAfterCheckpoint = await repository.getCard(child.id);
    expect(
      childAfterCheckpoint.state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    expect(childAfterCheckpoint.successfulDays, 2);
    expect(
      (await repository.getCard(parent.id)).state,
      NationalFocusCardState.extinguished,
    );
    expect((await repository.getCard(parent.id)).currentConsecutiveDays, 0);
    expect(
      (await repository.getCard(unused.id)).state,
      NationalFocusCardState.extinguished,
    );
    final failures = await repository.getFailures();
    expect(failures.map((failure) => failure.cardId).toSet(), {parent.id});
    expect(
      failures.single.treeSnapshot
          .singleWhere((card) => card.id == parent.id)
          .isInTree,
      isFalse,
    );
    expect(await repository.confirmToday(), 1);

    now = DateTime.utc(2026, 9, 27, 20);
    await repository.settleDueCheckpoints();
    expect(await repository.getFailures(), hasLength(1));
  });

  test('快照引用卡片只能软删除并恢复到卡片库，其他卡片可永久删除', () async {
    final historicalParent = await createCard('历史父卡');
    final historical = await createCard('历史卡片');
    await repository.placeCard(cardId: historicalParent.id, parentId: null);
    await repository.placeCard(
      cardId: historical.id,
      parentId: historicalParent.id,
    );
    await repository.lightCard(historicalParent.id);
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    now = DateTime.utc(2026, 9, 26, 20);
    await repository.settleDueCheckpoints();
    final originalFailure = (await repository.getFailures()).single;
    final originalSnapshot = originalFailure.treeSnapshot.singleWhere(
      (card) => card.id == historical.id,
    );
    expect(originalSnapshot.id, historical.id);
    expect(originalSnapshot.triggerCondition, '历史卡片');

    await repository.moveCardToLibrary(historicalParent.id);
    expect(
      await repository.deleteCard(historical.id),
      NationalFocusCardDeletion.softDeleted,
    );
    final deleted = (await repository.getDeletedCards()).single;
    expect(
      await repository.deleteCard(historical.id),
      NationalFocusCardDeletion.softDeleted,
    );
    expect(
      (await repository.getDeletedCards()).single.deletedAt,
      deleted.deletedAt,
    );
    expect((await repository.getLibraryCards()).single.id, historicalParent.id);
    expect((await repository.getDeletedCards()).single.id, historical.id);

    await repository.restoreDeletedCard(historical.id);
    final restoredCards = await repository.getLibraryCards();
    final restored = restoredCards.singleWhere(
      (card) => card.id == historical.id,
    );
    expect(restored.id, historical.id);
    expect(restored.isInTree, isFalse);
    expect(restored.parentId, isNull);
    expect(restored.successfulDays, originalSnapshot.successfulDays);
    expect(restored.bestConsecutiveDays, originalSnapshot.bestConsecutiveDays);
    await repository.restoreDeletedCard(historical.id);
    expect(
      (await repository.getCard(historical.id)).updatedAt,
      restored.updatedAt,
    );
    final preservedFailure = (await repository.getFailures()).single;
    final preservedSnapshot = preservedFailure.treeSnapshot.singleWhere(
      (card) => card.id == originalSnapshot.id,
    );
    expect(preservedSnapshot.id, originalSnapshot.id);
    expect(
      preservedSnapshot.triggerCondition,
      originalSnapshot.triggerCondition,
    );
    expect(
      preservedSnapshot.currentConsecutiveDays,
      originalSnapshot.currentConsecutiveDays,
    );

    final disposable = await createCard('无历史卡片');
    expect(
      await repository.deleteCard(disposable.id),
      NationalFocusCardDeletion.permanentlyDeleted,
    );
    await expectLater(repository.getCard(disposable.id), throwsStateError);
    expect(await repository.getDeletedCards(), isEmpty);
  });

  test('T15 本地数据库升级后保留国策卡并初始化可恢复状态', () async {
    final oldDatabase = PactaDatabase(
      NativeDatabase.memory(
        setup: (rawDatabase) {
          rawDatabase.execute('''
            CREATE TABLE local_national_focus_cards (
              user_id TEXT NOT NULL,
              id TEXT NOT NULL,
              trigger_condition TEXT NOT NULL,
              action TEXT NOT NULL,
              scope TEXT,
              exception_notes TEXT,
              is_in_tree INTEGER NOT NULL DEFAULT 0,
              parent_id TEXT,
              state TEXT NOT NULL DEFAULT 'extinguished',
              successful_days INTEGER NOT NULL DEFAULT 0,
              current_consecutive_days INTEGER NOT NULL DEFAULT 0,
              best_consecutive_days INTEGER NOT NULL DEFAULT 0,
              maintenance_cycle_started INTEGER NOT NULL DEFAULT 0,
              failure_reason TEXT,
              cascade_source_card_id TEXT,
              cascade_prior_state TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (user_id, id)
            )
          ''');
          rawDatabase.execute('''
            CREATE TABLE local_national_focus_maintenance (
              user_id TEXT NOT NULL PRIMARY KEY,
              last_settled_checkpoint_at INTEGER NOT NULL
            )
          ''');
          rawDatabase.execute('''
            CREATE TABLE local_national_focus_failures (
              user_id TEXT NOT NULL,
              id TEXT NOT NULL,
              batch_id TEXT NOT NULL,
              card_id TEXT NOT NULL,
              checkpoint_at INTEGER NOT NULL,
              cause TEXT NOT NULL,
              failure_reason TEXT,
              shared_explanation TEXT,
              tree_snapshot TEXT NOT NULL,
              PRIMARY KEY (user_id, id)
            )
          ''');
          rawDatabase.execute('''
            INSERT INTO local_national_focus_cards (
              user_id, id, trigger_condition, action, is_in_tree, state,
              successful_days, current_consecutive_days, best_consecutive_days,
              maintenance_cycle_started, created_at, updated_at
            ) VALUES (
              'user-a', 'legacy-card', '旧触发条件', '旧行动', 1, 'extinguished',
              3, 0, 3, 0, 0, 0
            )
          ''');
          rawDatabase.execute('PRAGMA user_version = 15');
        },
      ),
    );
    final migratedRepository = LocalNationalFocusRepository(
      database: oldDatabase,
      userId: 'user-a',
      now: () => now,
    );
    addTearDown(migratedRepository.dispose);
    addTearDown(oldDatabase.close);

    final card = await migratedRepository.getCard('legacy-card');
    expect(card.triggerCondition, '旧触发条件');
    expect(card.action, '旧行动');
    expect(card.isInTree, isTrue);
    expect(card.deletedAt, isNull);
    expect(card.successfulDays, 3);
    expect(await migratedRepository.getDeletedCards(), isEmpty);
  });
}
