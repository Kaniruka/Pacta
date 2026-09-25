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

  test('北京时间 03:59 首次点亮可在固定检查点计为一天且不会重复累计', () async {
    final card = await repository.createCard(draft('开始工作前', '先写三行'));
    await repository.placeCard(cardId: card.id, parentId: null);

    await repository.lightCard(card.id);
    final litBeforeCheckpoint = await repository.getCard(card.id);
    expect(litBeforeCheckpoint.state, NationalFocusCardState.lit);
    expect(litBeforeCheckpoint.successfulDays, 0);

    now = DateTime.utc(2026, 9, 25, 20);
    final afterCheckpoint = await repository.getCard(card.id);
    expect(
      afterCheckpoint.state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    expect(afterCheckpoint.successfulDays, 1);
    expect(afterCheckpoint.currentConsecutiveDays, 1);
    expect(afterCheckpoint.bestConsecutiveDays, 1);
    expect(afterCheckpoint.internalizationProgress, closeTo(1.6528, 0.001));

    final repeatedRead = await repository.getCard(card.id);
    expect(repeatedRead.successfulDays, 1);
    expect(repeatedRead.currentConsecutiveDays, 1);
  });

  test('一键确认只处理待今日确认节点并保持已经点亮与真正熄灭节点原样', () async {
    final first = await repository.createCard(draft('起床后', '整理床铺'));
    final second = await repository.createCard(draft('到工位后', '写下第一步'));
    final extinguished = await repository.createCard(draft('晚饭后', '收拾厨房'));
    for (final card in [first, second, extinguished]) {
      await repository.placeCard(cardId: card.id, parentId: null);
    }
    await repository.lightCard(first.id);
    await repository.lightCard(second.id);

    now = DateTime.utc(2026, 9, 25, 20);
    expect(
      (await repository.getCard(first.id)).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    expect(
      (await repository.getCard(second.id)).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );

    await repository.lightCard(first.id);
    expect(await repository.confirmToday(), 1);
    expect(await repository.confirmToday(), 0);

    expect(
      (await repository.getCard(first.id)).state,
      NationalFocusCardState.lit,
    );
    expect(
      (await repository.getCard(second.id)).state,
      NationalFocusCardState.lit,
    );
    expect(
      (await repository.getCard(extinguished.id)).state,
      NationalFocusCardState.extinguished,
    );
    expect(await repository.getFailures(), isEmpty);
  });

  test('漏确认仅失败未确认节点并保留完整快照与共享补充说明', () async {
    final confirmed = await repository.createCard(draft('开始工作前', '打开计划'));
    final missedOne = await repository.createCard(draft('午饭后', '读十分钟'));
    final missedTwo = await repository.createCard(draft('下班前', '整理桌面'));
    final cards = [confirmed, missedOne, missedTwo];
    for (final card in cards) {
      await repository.placeCard(cardId: card.id, parentId: null);
      await repository.lightCard(card.id);
    }

    now = DateTime.utc(2026, 9, 25, 20);
    expect(await repository.getTreeCards(), hasLength(3));
    await repository.lightCard(confirmed.id);

    now = DateTime.utc(2026, 9, 26, 20);
    final afterFailure = await repository.getTreeCards();
    expect(
      afterFailure.singleWhere((card) => card.id == confirmed.id).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    final failedCard = afterFailure.singleWhere(
      (card) => card.id == missedOne.id,
    );
    expect(failedCard.state, NationalFocusCardState.extinguished);
    expect(failedCard.successfulDays, 1);
    expect(failedCard.currentConsecutiveDays, 0);
    expect(failedCard.bestConsecutiveDays, 1);
    expect(failedCard.internalizationProgress, closeTo(1.6528, 0.001));

    var failures = await repository.getFailures();
    expect(failures, hasLength(2));
    expect(
      failures.every(
        (failure) =>
            failure.cause == NationalFocusFailureCause.missedConfirmation &&
            failure.failureReason == '未完成今日确认',
      ),
      isTrue,
    );
    expect(failures.map((failure) => failure.batchId).toSet(), hasLength(1));
    expect(
      failures.every((failure) => failure.sharedExplanation == null),
      isTrue,
    );
    final missedSnapshot = failures.first.treeSnapshot.singleWhere(
      (card) => card.id == missedOne.id,
    );
    expect(
      missedSnapshot.state,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    expect(missedSnapshot.currentConsecutiveDays, 1);
    expect(failures.first.treeSnapshot, hasLength(3));

    final batchId = failures.first.batchId;
    await repository.updateFailureExplanation(
      batchId: batchId,
      explanation: '那天临时处理了紧急事务',
    );
    failures = await repository.getFailures();
    expect(
      failures.every((failure) => failure.sharedExplanation == '那天临时处理了紧急事务'),
      isTrue,
    );

    await repository.dispose();
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'user-a',
      now: () => now,
    );
    expect(await repository.getFailures(), hasLength(2));
    expect(
      (await repository.getFailures()).every(
        (failure) => failure.sharedExplanation == '那天临时处理了紧急事务',
      ),
      isTrue,
    );

    expect(await repository.confirmToday(), 1);
    now = DateTime.utc(2026, 9, 27, 20);
    final afterNextDay = await repository.getCard(confirmed.id);
    expect(afterNextDay.successfulDays, 3);
    expect(afterNextDay.currentConsecutiveDays, 3);
    expect(await repository.getFailures(), hasLength(2));
  });

  test('主动熄灭可不填写原因，检查点前恢复保留记录，持续熄灭才正式失败', () async {
    final card = await repository.createCard(draft('午休后', '继续写作'));
    await repository.placeCard(cardId: card.id, parentId: null);
    await repository.lightCard(card.id);
    await repository.extinguishCard(cardId: card.id);
    expect((await repository.getCard(card.id)).failureReason, isNull);

    await repository.lightCard(card.id);
    now = DateTime.utc(2026, 9, 25, 20);
    final recovered = await repository.getCard(card.id);
    expect(recovered.state, NationalFocusCardState.pendingTodayConfirmation);
    expect(recovered.successfulDays, 1);
    expect(recovered.currentConsecutiveDays, 1);
    expect(await repository.getFailures(), isEmpty);

    await repository.extinguishCard(
      cardId: card.id,
      failureReason: '今天的规则条件不成立',
    );
    now = DateTime.utc(2026, 9, 26, 20);
    final failed = await repository.getCard(card.id);
    expect(failed.state, NationalFocusCardState.extinguished);
    expect(failed.successfulDays, 1);
    expect(failed.currentConsecutiveDays, 0);
    expect(failed.bestConsecutiveDays, 1);
    final failure = (await repository.getFailures()).single;
    expect(failure.cause, NationalFocusFailureCause.activeExtinguish);
    expect(failure.failureReason, '今天的规则条件不成立');
    await repository.updateFailureExplanation(
      batchId: failure.batchId,
      explanation: '之后补充的背景说明',
    );
    expect(
      (await repository.getFailures()).single.sharedExplanation,
      '之后补充的背景说明',
    );

    await repository.lightCard(card.id);
    expect((await repository.getCard(card.id)).currentConsecutiveDays, 0);
    now = DateTime.utc(2026, 9, 27, 20);
    final restartedCycle = await repository.getCard(card.id);
    expect(restartedCycle.successfulDays, 2);
    expect(restartedCycle.currentConsecutiveDays, 1);
    expect(restartedCycle.bestConsecutiveDays, 1);
    expect(await repository.getFailures(), hasLength(1));
  });

  test('空待确认集合和从未点亮的节点跨检查点不会失败或增加成功日', () async {
    expect(await repository.confirmToday(), 0);
    expect(await repository.getFailures(), isEmpty);

    now = DateTime.utc(2026, 9, 25, 20);
    expect(await repository.getTreeCards(), isEmpty);
    final card = await repository.createCard(draft('周末早晨', '读一本书'));
    await repository.placeCard(cardId: card.id, parentId: null);

    now = DateTime.utc(2026, 9, 28, 20);
    final unchanged = await repository.getCard(card.id);
    expect(unchanged.state, NationalFocusCardState.extinguished);
    expect(unchanged.successfulDays, 0);
    expect(unchanged.currentConsecutiveDays, 0);
    expect(await repository.getFailures(), isEmpty);
  });

  test('从 T13 数据库升级后保留国策卡并初始化新的记录字段', () async {
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
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (user_id, id)
            )
          ''');
          rawDatabase.execute('''
            INSERT INTO local_national_focus_cards
              (user_id, id, trigger_condition, action, is_in_tree, state,
               created_at, updated_at)
            VALUES ('user-a', 'legacy-card', '旧触发条件', '旧行动', 1,
                    'extinguished', 0, 0)
          ''');
          rawDatabase.execute('PRAGMA user_version = 13');
        },
      ),
    );
    final migratedRepository = LocalNationalFocusRepository(
      database: oldDatabase,
      userId: 'user-a',
      now: () => DateTime.utc(2026, 9, 25, 19, 59),
    );
    addTearDown(migratedRepository.dispose);
    addTearDown(oldDatabase.close);

    final migrated = await migratedRepository.getCard('legacy-card');
    expect(migrated.triggerCondition, '旧触发条件');
    expect(migrated.action, '旧行动');
    expect(migrated.isInTree, isTrue);
    expect(migrated.state, NationalFocusCardState.extinguished);
    expect(migrated.successfulDays, 0);
    expect(migrated.currentConsecutiveDays, 0);
    expect(migrated.bestConsecutiveDays, 0);
    expect(migrated.maintenanceCycleStarted, isFalse);

    await migratedRepository.lightCard(migrated.id);
    expect(
      (await migratedRepository.getCard(migrated.id)).state,
      NationalFocusCardState.lit,
    );
  });
}
