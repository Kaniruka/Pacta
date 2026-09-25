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

  test('选择或编辑强化要求会保留生效区间且不重置国策记录', () async {
    now = DateTime.utc(2026, 9, 25, 3, 59);
    final card = await repository.createCard(draft('开始工作后', '阅读 5 页'));
    await repository.placeCard(cardId: card.id, parentId: null);
    await repository.lightCard(card.id);

    final firstLevel = await repository.saveStrengtheningLevel(
      cardId: card.id,
      draft: const NationalFocusStrengtheningLevelDraft(action: '阅读 10 页'),
    );
    expect(firstLevel.levelNumber, 1);

    now = DateTime.utc(2026, 9, 25, 4);
    await repository.selectStrengtheningLevel(
      cardId: card.id,
      levelNumber: firstLevel.levelNumber,
    );
    var strengthened = await repository.getCard(card.id);
    expect(strengthened.effectiveTriggerCondition, '开始工作后');
    expect(strengthened.effectiveAction, '阅读 10 页');
    expect(strengthened.state, NationalFocusCardState.lit);

    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    final afterCheckpoint = await repository.getCard(card.id);
    expect(afterCheckpoint.successfulDays, 1);
    expect(afterCheckpoint.currentConsecutiveDays, 1);
    expect(
      afterCheckpoint.state,
      NationalFocusCardState.pendingTodayConfirmation,
    );

    now = DateTime.utc(2026, 9, 26, 4);
    await repository.saveStrengtheningLevel(
      cardId: card.id,
      levelNumber: firstLevel.levelNumber,
      draft: const NationalFocusStrengtheningLevelDraft(action: '阅读 12 页'),
    );

    strengthened = await repository.getCard(card.id);
    expect(strengthened.effectiveAction, '阅读 12 页');
    expect(strengthened.successfulDays, 1);
    expect(strengthened.currentConsecutiveDays, 1);
    expect(strengthened.state, NationalFocusCardState.pendingTodayConfirmation);
    expect(strengthened.requirementVersions, hasLength(3));
    expect(strengthened.requirementVersions[0].effectiveAction, '阅读 5 页');
    expect(
      strengthened.requirementVersions[0].effectiveUntil!.isAtSameMomentAs(
        DateTime.utc(2026, 9, 25, 4),
      ),
      isTrue,
    );
    expect(strengthened.requirementVersions[1].effectiveAction, '阅读 10 页');
    expect(
      strengthened.requirementVersions[1].effectiveUntil!.isAtSameMomentAs(
        DateTime.utc(2026, 9, 26, 4),
      ),
      isTrue,
    );
    expect(strengthened.requirementVersions[2].effectiveAction, '阅读 12 页');
    expect(strengthened.requirementVersions[2].effectiveUntil, isNull);

    await repository.dispose();
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'user-a',
      now: () => now,
    );
    final restored = await repository.getCard(card.id);
    expect(restored.activeStrengtheningLevel, 1);
    expect(restored.effectiveAction, '阅读 12 页');
    expect(restored.requirementVersions, hasLength(3));
    expect(restored.requirementVersions[1].effectiveAction, '阅读 10 页');
  });

  test('强化等级最多五个且未强化字段沿用基础要求', () async {
    final card = await repository.createCard(draft('开始工作后', '整理桌面'));
    for (
      var levelNumber = 1;
      levelNumber <= maxNationalFocusStrengtheningLevels;
      levelNumber++
    ) {
      final level = await repository.saveStrengtheningLevel(
        cardId: card.id,
        draft: NationalFocusStrengtheningLevelDraft(
          triggerCondition: '提前 $levelNumber 分钟开始',
        ),
      );
      expect(level.levelNumber, levelNumber);
    }

    await repository.selectStrengtheningLevel(cardId: card.id, levelNumber: 1);
    var updated = await repository.getCard(card.id);
    expect(updated.strengtheningLevels, hasLength(5));
    expect(updated.effectiveTriggerCondition, '提前 1 分钟开始');
    expect(updated.effectiveAction, '整理桌面');

    await expectLater(
      repository.saveStrengtheningLevel(
        cardId: card.id,
        draft: const NationalFocusStrengtheningLevelDraft(action: '写下计划'),
      ),
      throwsArgumentError,
    );
    updated = await repository.getCard(card.id);
    expect(updated.strengtheningLevels, hasLength(5));
  });

  test('失败快照保留检查点时的强化要求版本', () async {
    now = DateTime.utc(2026, 9, 25, 3, 59);
    final card = await repository.createCard(draft('开始工作后', '阅读 5 页'));
    await repository.placeCard(cardId: card.id, parentId: null);
    await repository.lightCard(card.id);
    final level = await repository.saveStrengtheningLevel(
      cardId: card.id,
      draft: const NationalFocusStrengtheningLevelDraft(action: '阅读 10 页'),
    );

    now = DateTime.utc(2026, 9, 25, 4);
    await repository.selectStrengtheningLevel(
      cardId: card.id,
      levelNumber: level.levelNumber,
    );
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    now = DateTime.utc(2026, 9, 26, 20);
    await repository.settleDueCheckpoints();

    var failure = (await repository.getFailures()).single;
    var snapshot = failure.treeSnapshot.singleWhere(
      (item) => item.id == card.id,
    );
    expect(snapshot.activeStrengtheningLevel, 1);
    expect(snapshot.requirementVersionNumber, 2);
    expect(snapshot.effectiveAction, '阅读 10 页');

    now = DateTime.utc(2026, 9, 26, 20, 1);
    await repository.saveStrengtheningLevel(
      cardId: card.id,
      levelNumber: 1,
      draft: const NationalFocusStrengtheningLevelDraft(action: '阅读 12 页'),
    );
    failure = (await repository.getFailures()).single;
    snapshot = failure.treeSnapshot.singleWhere((item) => item.id == card.id);
    expect(snapshot.effectiveAction, '阅读 10 页');
    expect(snapshot.requirementVersionNumber, 2);
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

  test('拒绝把仍在点亮的卡片重新挂到熄灭父节点下', () async {
    final extinguishedParent = await repository.createCard(
      draft('开始休息前', '关闭工作页面'),
    );
    final activeRoot = await repository.createCard(draft('坐到书桌前', '先写下第一步'));
    await repository.placeCard(cardId: extinguishedParent.id, parentId: null);
    await repository.placeCard(cardId: activeRoot.id, parentId: null);
    await repository.lightCard(activeRoot.id);

    await expectLater(
      repository.placeCard(
        cardId: activeRoot.id,
        parentId: extinguishedParent.id,
      ),
      throwsStateError,
    );

    final unchanged = await repository.getCard(activeRoot.id);
    expect(unchanged.parentId, isNull);
    expect(unchanged.state, NationalFocusCardState.lit);
  });

  test('卡片放在顶层后只获得结构位置，不会因此点亮', () async {
    final card = await repository.createCard(draft('完成早餐后', '复习单词'));
    await repository.placeCard(cardId: card.id, parentId: null);

    final placed = (await repository.getTreeCards()).single;
    expect(placed.isInTree, isTrue);
    expect(placed.isTopLevel, isTrue);
    expect(placed.state, NationalFocusCardState.extinguished);
  });

  test('主动熄灭父节点会级联熄灭后代，父恢复后后代仍需逐个点亮', () async {
    final parent = await repository.createCard(draft('开始工作前', '打开计划'));
    final child = await repository.createCard(draft('计划打开后', '先做第一项'));
    final grandchild = await repository.createCard(draft('第一项完成后', '记录结果'));
    await repository.placeCard(cardId: parent.id, parentId: null);
    await repository.placeCard(cardId: child.id, parentId: parent.id);
    await repository.placeCard(cardId: grandchild.id, parentId: child.id);
    for (final card in [parent, child, grandchild]) {
      await repository.lightCard(card.id);
    }

    await repository.extinguishCard(cardId: parent.id);
    for (final card in [parent, child, grandchild]) {
      expect(
        (await repository.getCard(card.id)).state,
        NationalFocusCardState.extinguished,
      );
    }
    final cascadedChild = await repository.getCard(child.id);
    expect(cascadedChild.cascadeSourceCardId, parent.id);
    expect(cascadedChild.cascadePriorState, NationalFocusCardState.lit);

    await repository.dispose();
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'user-a',
      now: () => now,
    );
    expect((await repository.getCard(child.id)).cascadeSourceCardId, parent.id);
    await expectLater(repository.lightCard(child.id), throwsStateError);

    await repository.lightCard(parent.id);
    expect(
      (await repository.getCard(child.id)).state,
      NationalFocusCardState.extinguished,
    );
    await repository.lightCard(child.id);
    await repository.lightCard(grandchild.id);

    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    for (final card in [parent, child, grandchild]) {
      final recovered = await repository.getCard(card.id);
      expect(recovered.state, NationalFocusCardState.pendingTodayConfirmation);
      expect(recovered.successfulDays, 1);
      expect(recovered.currentConsecutiveDays, 1);
    }
    expect(await repository.getFailures(), isEmpty);
  });

  test('父漏确认会连带熄灭已确认的子且子当天不增加成功日', () async {
    final parent = await repository.createCard(draft('开始工作前', '打开计划'));
    final child = await repository.createCard(draft('计划打开后', '先做第一项'));
    await repository.placeCard(cardId: parent.id, parentId: null);
    await repository.placeCard(cardId: child.id, parentId: parent.id);
    await repository.lightCard(parent.id);
    await repository.lightCard(child.id);

    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await repository.lightCard(child.id);
    now = DateTime.utc(2026, 9, 26, 20);
    await repository.settleDueCheckpoints();

    final parentAfterFailure = await repository.getCard(parent.id);
    final childAfterFailure = await repository.getCard(child.id);
    expect(parentAfterFailure.state, NationalFocusCardState.extinguished);
    expect(childAfterFailure.state, NationalFocusCardState.extinguished);
    expect(parentAfterFailure.successfulDays, 1);
    expect(childAfterFailure.successfulDays, 1);
    expect(childAfterFailure.currentConsecutiveDays, 0);

    final failures = await repository.getFailures();
    expect(failures, hasLength(1));
    expect(failures.single.cardId, parent.id);
    expect(failures.single.cause, NationalFocusFailureCause.missedConfirmation);
    expect(failures.single.treeSnapshot, hasLength(2));
    final parentSnapshot = failures.single.treeSnapshot.singleWhere(
      (card) => card.id == parent.id,
    );
    final childSnapshot = failures.single.treeSnapshot.singleWhere(
      (card) => card.id == child.id,
    );
    expect(parentSnapshot.failureSourceCardId, parent.id);
    expect(childSnapshot.failureSourceCardId, parent.id);
    expect(childSnapshot.state, NationalFocusCardState.lit);
    expect(childSnapshot.successfulDays, 1);
    await repository.settleDueCheckpoints();
    expect(await repository.getFailures(), hasLength(1));

    await repository.lightCard(parent.id);
    await repository.lightCard(child.id);
    final immutableSnapshot = (await repository.getFailures())
        .single
        .treeSnapshot
        .singleWhere((card) => card.id == child.id);
    expect(immutableSnapshot.failureSourceCardId, parent.id);
    expect(immutableSnapshot.state, NationalFocusCardState.lit);

    await repository.dispose();
    repository = LocalNationalFocusRepository(
      database: database,
      userId: 'user-a',
      now: () => now,
    );
    final restoredSnapshot = (await repository.getFailures())
        .single
        .treeSnapshot
        .singleWhere((card) => card.id == child.id);
    expect(restoredSnapshot.failureSourceCardId, parent.id);
    expect(restoredSnapshot.state, NationalFocusCardState.lit);
  });

  test('漏确认的子保留独立失败，已确认的子只记录父节点级联影响', () async {
    final parent = await repository.createCard(draft('开始工作前', '打开计划'));
    final missedChild = await repository.createCard(draft('计划打开后', '先做第一项'));
    final confirmedChild = await repository.createCard(draft('第一项完成后', '记录结果'));
    final unrelated = await repository.createCard(draft('午饭后', '散步十分钟'));
    await repository.placeCard(cardId: parent.id, parentId: null);
    await repository.placeCard(cardId: missedChild.id, parentId: parent.id);
    await repository.placeCard(cardId: confirmedChild.id, parentId: parent.id);
    await repository.placeCard(cardId: unrelated.id, parentId: null);
    for (final card in [parent, missedChild, confirmedChild, unrelated]) {
      await repository.lightCard(card.id);
    }

    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await repository.lightCard(confirmedChild.id);
    now = DateTime.utc(2026, 9, 26, 20);
    await repository.settleDueCheckpoints();

    final failures = await repository.getFailures();
    expect(failures, hasLength(3));
    expect(failures.map((failure) => failure.cardId).toSet(), {
      parent.id,
      missedChild.id,
      unrelated.id,
    });
    expect(
      failures.every(
        (failure) =>
            failure.cause == NationalFocusFailureCause.missedConfirmation,
      ),
      isTrue,
    );
    expect(failures.map((failure) => failure.batchId).toSet(), hasLength(1));
    final snapshot = failures.first.treeSnapshot;
    expect(
      snapshot.singleWhere((card) => card.id == parent.id).failureSourceCardId,
      parent.id,
    );
    expect(
      snapshot
          .singleWhere((card) => card.id == missedChild.id)
          .failureSourceCardId,
      missedChild.id,
    );
    expect(
      snapshot
          .singleWhere((card) => card.id == confirmedChild.id)
          .failureSourceCardId,
      parent.id,
    );
    expect(
      snapshot
          .singleWhere((card) => card.id == unrelated.id)
          .failureSourceCardId,
      unrelated.id,
    );
    expect((await repository.getCard(confirmedChild.id)).successfulDays, 1);
    expect(
      (await repository.getCard(confirmedChild.id)).state,
      NationalFocusCardState.extinguished,
    );

    await repository.updateFailureExplanation(
      batchId: failures.first.batchId,
      explanation: '这组节点当天未完成确认',
    );
    expect(
      (await repository.getFailures()).every(
        (failure) => failure.sharedExplanation == '这组节点当天未完成确认',
      ),
      isTrue,
    );
  });

  test('先主动熄灭子再熄灭父时两个独立失败来源都只结算一次', () async {
    final parent = await repository.createCard(draft('开始工作前', '打开计划'));
    final child = await repository.createCard(draft('计划打开后', '先做第一项'));
    await repository.placeCard(cardId: parent.id, parentId: null);
    await repository.placeCard(cardId: child.id, parentId: parent.id);
    await repository.lightCard(parent.id);
    await repository.lightCard(child.id);
    await repository.extinguishCard(
      cardId: child.id,
      failureReason: '子节点要求不再适用',
    );
    await repository.extinguishCard(
      cardId: parent.id,
      failureReason: '父节点要求不再适用',
    );

    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    final failures = await repository.getFailures();
    expect(failures, hasLength(2));
    expect(failures.map((failure) => failure.cardId).toSet(), {
      parent.id,
      child.id,
    });
    expect(
      failures.every(
        (failure) =>
            failure.cause == NationalFocusFailureCause.activeExtinguish,
      ),
      isTrue,
    );

    await repository.settleDueCheckpoints();
    expect(await repository.getFailures(), hasLength(2));
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
          rawDatabase.execute('''
            INSERT INTO local_national_focus_cards
              (user_id, id, trigger_condition, action, is_in_tree, parent_id,
               state, created_at, updated_at)
            VALUES ('user-a', 'legacy-parent', '旧父节点', '旧行动', 1, NULL,
                    'extinguished', 0, 0)
          ''');
          rawDatabase.execute('''
            INSERT INTO local_national_focus_cards
              (user_id, id, trigger_condition, action, is_in_tree, parent_id,
               state, created_at, updated_at)
            VALUES ('user-a', 'legacy-pending-child', '旧待确认子节点', '旧行动',
                    1, 'legacy-parent', 'pending_today_confirmation', 0, 0)
          ''');
          rawDatabase.execute('''
            CREATE TABLE focus_source_devices (
              user_id TEXT NOT NULL PRIMARY KEY,
              device_id TEXT NOT NULL
            )
          ''');
          rawDatabase.execute('''
            CREATE TABLE focus_sync_sources (
              user_id TEXT NOT NULL,
              source_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              parent_source_id TEXT,
              parent_source_ids TEXT NOT NULL DEFAULT '[]',
              occurred_at INTEGER NOT NULL,
              payload TEXT NOT NULL,
              PRIMARY KEY (user_id, source_id)
            )
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

    final migratedChild = await migratedRepository.getCard(
      'legacy-pending-child',
    );
    expect(migratedChild.state, NationalFocusCardState.extinguished);
    expect(migratedChild.cascadeSourceCardId, 'legacy-parent');
    expect(
      migratedChild.cascadePriorState,
      NationalFocusCardState.pendingTodayConfirmation,
    );
    expect(await migratedRepository.confirmToday(), 0);

    await migratedRepository.lightCard(migrated.id);
    expect(
      (await migratedRepository.getCard(migrated.id)).state,
      NationalFocusCardState.lit,
    );
  });

  test('从 T14 升级时清理已失败父节点下的旧活动状态而不补造子失败', () async {
    final lastSettledCheckpoint = DateTime.utc(2026, 9, 24, 20);
    var migrationNow = lastSettledCheckpoint;
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
            INSERT INTO local_national_focus_cards
              (user_id, id, trigger_condition, action, is_in_tree, parent_id,
               state, successful_days, current_consecutive_days,
               best_consecutive_days, maintenance_cycle_started,
               created_at, updated_at)
            VALUES ('user-a', 'support-root', '有效上级', '维持行动', 1, NULL,
                    'lit', 1, 1, 1, 1, 0,
                    ${lastSettledCheckpoint.millisecondsSinceEpoch})
          ''');
          rawDatabase.execute('''
            INSERT INTO local_national_focus_cards
              (user_id, id, trigger_condition, action, is_in_tree, parent_id,
               state, successful_days, current_consecutive_days,
               best_consecutive_days, maintenance_cycle_started,
               created_at, updated_at)
            VALUES ('user-a', 'failed-parent', '旧父节点', '旧行动', 1,
                    'support-root',
                    'extinguished', 2, 0, 2, 0, 0, ${lastSettledCheckpoint.millisecondsSinceEpoch + 120000})
          ''');
          rawDatabase.execute('''
            INSERT INTO local_national_focus_cards
              (user_id, id, trigger_condition, action, is_in_tree, parent_id,
               state, successful_days, current_consecutive_days,
               best_consecutive_days, maintenance_cycle_started,
               created_at, updated_at)
            VALUES ('user-a', 'pending-child', '旧待确认子节点', '旧行动', 1,
                    'failed-parent', 'pending_today_confirmation', 4, 2, 5, 1,
                    0, ${lastSettledCheckpoint.millisecondsSinceEpoch + 60000})
          ''');
          rawDatabase.execute('''
            INSERT INTO local_national_focus_maintenance
              (user_id, last_settled_checkpoint_at)
            VALUES ('user-a', ${lastSettledCheckpoint.millisecondsSinceEpoch})
          ''');
          rawDatabase.execute('''
            INSERT INTO local_national_focus_failures
              (user_id, id, batch_id, card_id, checkpoint_at, cause,
               tree_snapshot)
            VALUES ('user-a', 'parent-failure', 'parent-batch', 'failed-parent',
                    ${lastSettledCheckpoint.millisecondsSinceEpoch},
                    'missed_confirmation', '[]')
          ''');
          rawDatabase.execute('''
            CREATE TABLE focus_source_devices (
              user_id TEXT NOT NULL PRIMARY KEY,
              device_id TEXT NOT NULL
            )
          ''');
          rawDatabase.execute('''
            CREATE TABLE focus_sync_sources (
              user_id TEXT NOT NULL,
              source_id TEXT NOT NULL,
              device_id TEXT NOT NULL,
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              parent_source_id TEXT,
              parent_source_ids TEXT NOT NULL DEFAULT '[]',
              occurred_at INTEGER NOT NULL,
              payload TEXT NOT NULL,
              PRIMARY KEY (user_id, source_id)
            )
          ''');
          rawDatabase.execute('PRAGMA user_version = 14');
        },
      ),
    );
    final migratedRepository = LocalNationalFocusRepository(
      database: oldDatabase,
      userId: 'user-a',
      now: () => migrationNow,
    );
    addTearDown(migratedRepository.dispose);
    addTearDown(oldDatabase.close);

    final migratedChild = await migratedRepository.getCard('pending-child');
    expect(migratedChild.state, NationalFocusCardState.extinguished);
    expect(migratedChild.cascadeSourceCardId, 'failed-parent');
    expect(migratedChild.cascadePriorState, NationalFocusCardState.lit);
    expect(migratedChild.successfulDays, 4);
    expect(migratedChild.currentConsecutiveDays, 0);
    expect(migratedChild.maintenanceCycleStarted, isFalse);

    migrationNow = lastSettledCheckpoint.add(const Duration(hours: 24));
    await migratedRepository.settleDueCheckpoints();
    final failures = await migratedRepository.getFailures();
    expect(failures, hasLength(1));
    expect(failures.single.cardId, 'failed-parent');
  });
}
