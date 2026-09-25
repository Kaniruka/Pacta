import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late Directory directory;
  late PactaDatabase firstDatabase;
  late PactaDatabase secondDatabase;
  late LocalNationalFocusRepository firstDevice;
  late LocalNationalFocusRepository secondDevice;
  late InMemoryNationalFocusRemoteDataSource remote;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pacta-t19-review-');
    firstDatabase = PactaDatabase(
      NativeDatabase(File('${directory.path}/first.sqlite')),
    );
    secondDatabase = PactaDatabase(
      NativeDatabase(File('${directory.path}/second.sqlite')),
    );
    now = DateTime.utc(2026, 9, 20, 19, 59);
    remote = InMemoryNationalFocusRemoteDataSource();
    firstDevice = LocalNationalFocusRepository(
      database: firstDatabase,
      userId: 'ticket-19-user',
      remote: remote,
      now: () => now,
    );
    secondDevice = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'ticket-19-user',
      remote: remote,
      now: () => now,
    );
  });

  tearDown(() async {
    await firstDevice.dispose();
    await secondDevice.dispose();
    await firstDatabase.close();
    await secondDatabase.close();
    await directory.delete(recursive: true);
  });

  test('核对并发分支时展示来源影响、保留证据并幂等传播裁决', () async {
    final parent = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '开始写作', action: '写一段'),
    );
    final child = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '开始阅读', action: '读一页'),
    );
    await firstDevice.placeCard(cardId: parent.id, parentId: null);
    await firstDevice.placeCard(cardId: child.id, parentId: null);
    await firstDevice.lightCard(parent.id);
    await firstDevice.lightCard(child.id);
    now = DateTime.utc(2026, 9, 20, 20);
    await firstDevice.settleDueCheckpoints();
    await firstDevice.sync();
    await secondDevice.sync();

    now = DateTime.utc(2026, 9, 21, 19);
    await firstDevice.placeCard(cardId: child.id, parentId: parent.id);
    await secondDevice.placeCard(cardId: parent.id, parentId: child.id);
    await firstDevice.sync();
    await secondDevice.sync();

    var reviewState = await secondDevice.getNationalFocusReviewState();
    expect(reviewState.reconciliationCases, hasLength(1));
    final review = reviewState.reconciliationCases.single;
    expect(review.cardIds, unorderedEquals([parent.id, child.id]));
    expect(review.options, hasLength(2));
    final acceptedBranch = review.options.singleWhere(
      (option) => option.effects.any(
        (effect) =>
            effect.cardId == child.id && effect.newParentId == parent.id,
      ),
    );
    expect(
      acceptedBranch.operations.map((operation) => operation.operation),
      contains('place_card'),
    );
    expect(acceptedBranch.effects, isNotEmpty);
    expect((await secondDevice.getCard(parent.id)).hasPendingReview, isTrue);
    expect(
      (await secondDevice.getFailures()).where((f) => f.isPendingReview),
      isEmpty,
    );

    await secondDevice.deferNationalFocusReconciliation(review.id);
    reviewState = await secondDevice.getNationalFocusReviewState();
    expect(reviewState.reconciliationCases.single.isDeferred, isTrue);

    await secondDevice.resolveNationalFocusReconciliation(
      caseId: review.id,
      selectedSourceId: acceptedBranch.sourceId,
    );
    await secondDevice.sync();

    final resolvedTree = await secondDevice.getTreeCards();
    expect(
      resolvedTree.singleWhere((card) => card.id == child.id).parentId,
      parent.id,
    );
    for (final effect in acceptedBranch.effects) {
      if (effect.newSuccessfulDays != null) {
        expect(
          resolvedTree
              .singleWhere((card) => card.id == effect.cardId)
              .successfulDays,
          effect.newSuccessfulDays,
        );
      }
      if (effect.newBestConsecutiveDays != null) {
        expect(
          resolvedTree
              .singleWhere((card) => card.id == effect.cardId)
              .bestConsecutiveDays,
          effect.newBestConsecutiveDays,
        );
      }
    }
    expect(resolvedTree.every((card) => !card.hasPendingReview), isTrue);
    reviewState = await secondDevice.getNationalFocusReviewState();
    expect(reviewState.reconciliationCases, isEmpty);
    expect(reviewState.reconciliationHistory, hasLength(1));
    final resolution = reviewState.reconciliationHistory.single;
    expect(resolution.acceptedSourceIds, contains(acceptedBranch.sourceId));
    expect(resolution.retainedSourceIds.length, greaterThanOrEqualTo(2));

    await firstDevice.sync();
    await firstDevice.sync();
    final firstDeviceTree = await firstDevice.getTreeCards();
    expect(
      firstDeviceTree.singleWhere((card) => card.id == child.id).parentId,
      parent.id,
    );
    expect(
      (await firstDevice.getNationalFocusReviewState()).reconciliationHistory,
      hasLength(1),
    );
  });

  test('跨过检查点裁决旧分支时按选定操作重算失败快照', () async {
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '晨间复盘', action: '写下三点'),
    );
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);
    now = DateTime.utc(2026, 9, 20, 20);
    await firstDevice.settleDueCheckpoints();
    await firstDevice.sync();
    await secondDevice.sync();

    now = DateTime.utc(2026, 9, 21, 19, 59);
    await secondDevice.dispose();
    var secondNow = now;
    secondDevice = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'ticket-19-user',
      remote: remote,
      now: () => secondNow,
    );
    await firstDevice.extinguishCard(
      cardId: card.id,
      failureReason: '手机端选择的熄灭原因',
    );
    await secondDevice.extinguishCard(
      cardId: card.id,
      failureReason: '平板端选择的熄灭原因',
    );

    now = DateTime.utc(2026, 9, 21, 20);
    await firstDevice.settleDueCheckpoints();
    await firstDevice.sync();
    await secondDevice.sync();

    final review = (await secondDevice.getNationalFocusReviewState())
        .reconciliationCases
        .single;
    final selectedBranch = review.options.firstWhere(
      (option) => option.operations.any(
        (operation) => operation.effects.any(
          (effect) => effect.newFailureReason == '平板端选择的熄灭原因',
        ),
      ),
    );
    await secondDevice.resolveNationalFocusReconciliation(
      caseId: review.id,
      selectedSourceId: selectedBranch.sourceId,
    );

    final failure = (await secondDevice.getFailures(cardId: card.id)).single;
    expect(failure.checkpointAt.toUtc(), DateTime.utc(2026, 9, 21, 20));
    expect(failure.cause, NationalFocusFailureCause.activeExtinguish);
    expect(failure.failureReason, '平板端选择的熄灭原因');
  });

  test('跨过检查点裁决点亮分支时重算成功天数和确认状态', () async {
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '完成晨间计划', action: '逐项检查'),
    );
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);
    now = DateTime.utc(2026, 9, 20, 20);
    await firstDevice.settleDueCheckpoints();
    expect((await firstDevice.getCard(card.id)).successfulDays, 1);
    await firstDevice.confirmToday();
    await firstDevice.sync();
    await secondDevice.sync();

    now = DateTime.utc(2026, 9, 21, 19, 59);
    await secondDevice.dispose();
    var secondNow = now;
    secondDevice = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'ticket-19-user',
      remote: remote,
      now: () => secondNow,
    );
    await firstDevice.extinguishCard(
      cardId: card.id,
      failureReason: '另一分支选择熄灭',
    );
    await secondDevice.saveStrengtheningLevel(
      cardId: card.id,
      draft: const NationalFocusStrengtheningLevelDraft(action: '检查十五分钟'),
    );

    now = DateTime.utc(2026, 9, 21, 20);
    await firstDevice.settleDueCheckpoints();
    await firstDevice.sync();
    await secondDevice.sync();

    final review = (await secondDevice.getNationalFocusReviewState())
        .reconciliationCases
        .single;
    final selectedBranch = review.options.firstWhere(
      (option) => option.operations.any(
        (operation) => operation.operation == 'edit_strengthening_level',
      ),
    );
    await secondDevice.resolveNationalFocusReconciliation(
      caseId: review.id,
      selectedSourceId: selectedBranch.sourceId,
    );

    final selectedCard = await secondDevice.getCard(card.id);
    expect(selectedCard.successfulDays, 2);
    expect(selectedCard.state, NationalFocusCardState.pendingTodayConfirmation);
    expect(selectedCard.action, '逐项检查');
  });

  test('分支裁决保留重叠时钟核对状态，最后一项核对完成后才解除', () async {
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '开始拉伸', action: '伸展三分钟'),
    );
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);
    await firstDevice.sync();
    await secondDevice.dispose();
    var secondWallTime = now;
    var secondMonotonicTime = Duration.zero;
    secondDevice = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'ticket-19-user',
      remote: remote,
      now: () => secondWallTime,
      monotonicNow: () => secondMonotonicTime,
    );
    await secondDevice.sync();

    await firstDevice.extinguishCard(cardId: card.id, failureReason: '手机端原因');
    await secondDevice.extinguishCard(cardId: card.id, failureReason: '平板端原因');
    await firstDevice.sync();
    await secondDevice.sync();

    secondWallTime = secondWallTime.add(const Duration(hours: 2));
    secondMonotonicTime += const Duration(seconds: 1);
    await secondDevice.settleDueCheckpoints();
    var reviewState = await secondDevice.getNationalFocusReviewState();
    final reconciliation = reviewState.reconciliationCases.single;
    final selectedBranch = reconciliation.options.firstWhere(
      (option) => option.operations.any(
        (operation) => operation.effects.any(
          (effect) => effect.newFailureReason == '平板端原因',
        ),
      ),
    );
    final clockReview = reviewState.clockReviewCases.single;

    await secondDevice.resolveNationalFocusReconciliation(
      caseId: reconciliation.id,
      selectedSourceId: selectedBranch.sourceId,
    );
    expect((await secondDevice.getCard(card.id)).hasPendingReview, isTrue);

    await secondDevice.resolveNationalFocusClockReview(clockReview.id);
    expect((await secondDevice.getCard(card.id)).hasPendingReview, isFalse);
    reviewState = await secondDevice.getNationalFocusReviewState();
    expect(reviewState.reconciliationCases, isEmpty);
    expect(reviewState.clockReviewCases, isEmpty);
  });

  test('时钟前跳只结算连续计时确认的时间并允许暂缓', () async {
    var wallTime = DateTime.utc(2026, 9, 20, 19, 59);
    var monotonicTime = Duration.zero;
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '开始运动', action: '活动五分钟'),
    );
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);
    await firstDevice.sync();
    await secondDevice.sync();

    await firstDevice.dispose();
    firstDevice = LocalNationalFocusRepository(
      database: firstDatabase,
      userId: 'ticket-19-user',
      remote: remote,
      now: () => wallTime,
      monotonicNow: () => monotonicTime,
    );
    await firstDevice.settleDueCheckpoints();
    wallTime = wallTime.add(const Duration(minutes: 2));
    monotonicTime += const Duration(minutes: 2);
    await firstDevice.settleDueCheckpoints();
    expect((await firstDevice.getCard(card.id)).successfulDays, 1);

    wallTime = wallTime.add(const Duration(hours: 2));
    monotonicTime += const Duration(seconds: 1);
    await firstDevice.settleDueCheckpoints();

    var reviewState = await firstDevice.getNationalFocusReviewState();
    expect(reviewState.clockReviewCases, hasLength(1));
    final clockReview = reviewState.clockReviewCases.single;
    expect(clockReview.direction, NationalFocusClockChangeDirection.forward);
    expect((await firstDevice.getCard(card.id)).hasPendingReview, isTrue);
    expect(await firstDevice.getFailures(cardId: card.id), isEmpty);

    await firstDevice.deferNationalFocusClockReview(clockReview.id);
    reviewState = await firstDevice.getNationalFocusReviewState();
    expect(reviewState.clockReviewCases.single.isDeferred, isTrue);
    expect((await firstDevice.getCard(card.id)).successfulDays, 1);
    expect(await firstDevice.getFailures(cardId: card.id), isEmpty);

    await firstDevice.resolveNationalFocusClockReview(clockReview.id);
    reviewState = await firstDevice.getNationalFocusReviewState();
    expect(reviewState.clockReviewCases, isEmpty);
    expect(reviewState.clockReviewHistory, hasLength(1));
    expect((await firstDevice.getCard(card.id)).hasPendingReview, isFalse);
    expect((await firstDevice.getCard(card.id)).successfulDays, 1);
    expect(await firstDevice.getFailures(cardId: card.id), isEmpty);
    await firstDevice.sync();
    await secondDevice.sync();
    final syncedReview = await secondDevice.getNationalFocusReviewState();
    expect(syncedReview.clockReviewCases, isEmpty);
    expect(syncedReview.clockReviewHistory, hasLength(1));
    expect((await secondDevice.getCard(card.id)).hasPendingReview, isFalse);

    await firstDevice.dispose();
    firstDevice = LocalNationalFocusRepository(
      database: firstDatabase,
      userId: 'ticket-19-user',
      remote: remote,
      now: () => wallTime,
      monotonicNow: () => monotonicTime,
    );
    await firstDevice.settleDueCheckpoints();
    expect(await firstDevice.getFailures(cardId: card.id), isEmpty);
    expect((await firstDevice.getCard(card.id)).successfulDays, 1);
  });

  test('裁决采用分支时恢复完整熄灭原因并将结果同步到两个端点', () async {
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '晨间锻炼', action: '热身三分钟'),
    );
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);
    await firstDevice.sync();
    await secondDevice.sync();

    now = DateTime.utc(2026, 9, 21, 19);
    await firstDevice.extinguishCard(
      cardId: card.id,
      failureReason: '手机端记录的原因',
    );
    await secondDevice.extinguishCard(
      cardId: card.id,
      failureReason: '平板端记录的原因',
    );
    await firstDevice.sync();
    await secondDevice.sync();

    final review = (await secondDevice.getNationalFocusReviewState())
        .reconciliationCases
        .single;
    final selectedBranch = review.options.firstWhere(
      (option) => option.operations.any(
        (operation) => operation.effects.any(
          (effect) => effect.newFailureReason == '手机端记录的原因',
        ),
      ),
    );
    expect((await secondDevice.getCard(card.id)).hasPendingReview, isTrue);

    await secondDevice.resolveNationalFocusReconciliation(
      caseId: review.id,
      selectedSourceId: selectedBranch.sourceId,
    );
    expect((await secondDevice.getCard(card.id)).failureReason, '手机端记录的原因');
    await secondDevice.sync();
    await firstDevice.sync();
    expect((await firstDevice.getCard(card.id)).failureReason, '手机端记录的原因');
    final result = (await firstDevice.getNationalFocusReviewState())
        .reconciliationHistory
        .single;
    expect(result.acceptedSourceIds, contains(selectedBranch.sourceId));
    expect(result.retainedSourceIds.length, greaterThan(1));
  });
}
