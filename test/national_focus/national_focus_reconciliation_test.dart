import 'dart:convert';
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
      const NationalFocusCardDraft(
        name: '开始写作',
        triggerCondition: '开始写作',
        action: '写一段',
      ),
    );
    final child = await firstDevice.createCard(
      const NationalFocusCardDraft(
        name: '开始阅读',
        triggerCondition: '开始阅读',
        action: '读一页',
      ),
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
      const NationalFocusCardDraft(
        name: '晨间复盘',
        triggerCondition: '晨间复盘',
        action: '写下三点',
      ),
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
      const NationalFocusCardDraft(
        name: '完成晨间计划',
        triggerCondition: '完成晨间计划',
        action: '逐项检查',
      ),
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

  test('本机时间跳变不增加分支裁决的待核对项', () async {
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(
        name: '开始拉伸',
        triggerCondition: '开始拉伸',
        action: '伸展三分钟',
      ),
    );
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);
    await firstDevice.sync();
    await secondDevice.dispose();
    var secondWallTime = now;
    secondDevice = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'ticket-19-user',
      remote: remote,
      now: () => secondWallTime,
    );
    await secondDevice.sync();

    await firstDevice.extinguishCard(cardId: card.id, failureReason: '手机端原因');
    await secondDevice.extinguishCard(cardId: card.id, failureReason: '平板端原因');
    await firstDevice.sync();
    await secondDevice.sync();

    secondWallTime = secondWallTime.add(const Duration(hours: 2));
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
    expect(reviewState.clockReviewCases, isEmpty);

    await secondDevice.resolveNationalFocusReconciliation(
      caseId: reconciliation.id,
      selectedSourceId: selectedBranch.sourceId,
    );
    expect((await secondDevice.getCard(card.id)).hasPendingReview, isFalse);
    reviewState = await secondDevice.getNationalFocusReviewState();
    expect(reviewState.reconciliationCases, isEmpty);
    expect(reviewState.clockReviewCases, isEmpty);
  });

  test('本机时间前跳按当前时间结算且不生成国策时钟待核对', () async {
    var wallTime = DateTime.utc(2026, 9, 20, 19, 59);
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(
        name: '开始运动',
        triggerCondition: '开始运动',
        action: '活动五分钟',
      ),
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
    );
    await firstDevice.settleDueCheckpoints();
    wallTime = wallTime.add(const Duration(minutes: 2));
    await firstDevice.settleDueCheckpoints();
    expect((await firstDevice.getCard(card.id)).successfulDays, 1);

    wallTime = wallTime.add(const Duration(hours: 26));
    await firstDevice.settleDueCheckpoints();
    expect(
      (await firstDevice.getNationalFocusReviewState()).clockReviewCases,
      isEmpty,
    );
    expect((await firstDevice.getCard(card.id)).hasPendingReview, isFalse);
    expect(await firstDevice.getFailures(cardId: card.id), hasLength(1));
    await firstDevice.sync();
    await secondDevice.sync();
    expect(
      (await secondDevice.getNationalFocusReviewState()).clockReviewCases,
      isEmpty,
    );
  });

  test('升级旧时钟核对后清除仅时钟待核对并保留分支冲突与来源', () async {
    final clockOnly = await firstDevice.createCard(
      const NationalFocusCardDraft(
        name: '仅时钟',
        triggerCondition: '仅时钟',
        action: '行动',
      ),
    );
    final conflicted = await firstDevice.createCard(
      const NationalFocusCardDraft(
        name: '分支冲突',
        triggerCondition: '分支冲突',
        action: '行动',
      ),
    );
    await firstDevice.placeCard(cardId: clockOnly.id, parentId: null);
    await firstDevice.placeCard(cardId: conflicted.id, parentId: null);
    await firstDevice.lightCard(clockOnly.id);
    await firstDevice.lightCard(conflicted.id);
    await firstDevice.settleDueCheckpoints();
    final sourceRows = await firstDatabase
        .select(firstDatabase.focusSyncSources)
        .get();
    final source = sourceRows.last;
    final payload = Map<String, dynamic>.from(
      jsonDecode(source.payload) as Map,
    );
    payload['nationalFocusClockReviewCases'] = [
      {
        'id': 'legacy-clock',
        'deviceId': 'old-device',
        'direction': 'forward',
        'detectedAt': now.toIso8601String(),
        'previousWallTime': now.toIso8601String(),
        'observedWallTime': now.toIso8601String(),
        'reliableThroughTime': now.toIso8601String(),
        'estimatedElapsedSeconds': 1,
        'cardIds': [clockOnly.id, conflicted.id],
        'isDeferred': true,
      },
    ];
    payload['nationalFocusReconciliationCases'] = [
      {
        'id': 'legacy-conflict',
        'createdAt': now.toIso8601String(),
        'cardIds': [conflicted.id],
        'cardNames': {conflicted.id: '分支冲突'},
        'options': [],
        'isDeferred': false,
      },
    ];
    await firstDatabase.customStatement(
      'UPDATE focus_sync_sources SET payload = ? WHERE source_id = ?',
      [jsonEncode(payload), source.sourceId],
    );
    await firstDatabase.customStatement(
      "UPDATE local_national_focus_cards SET review_disposition = 'pending_review' WHERE id IN (?, ?)",
      [clockOnly.id, conflicted.id],
    );
    await firstDevice.dispose();
    await firstDatabase.close();
    firstDatabase = PactaDatabase(
      NativeDatabase(File('${directory.path}/first.sqlite')),
    );
    firstDevice = LocalNationalFocusRepository(
      database: firstDatabase,
      userId: 'ticket-19-user',
      remote: remote,
      now: () => now,
      cloudSyncEnabled: false,
    );
    final state = await firstDevice.getNationalFocusReviewState();
    expect(state.clockReviewCases, isEmpty);
    expect(state.clockReviewHistory, isEmpty);
    expect(state.reconciliationCases, hasLength(1));
    expect((await firstDevice.getCard(clockOnly.id)).hasPendingReview, isFalse);
    expect((await firstDevice.getCard(conflicted.id)).hasPendingReview, isTrue);
    final evidence = await firstDatabase
        .select(firstDatabase.focusSyncSources)
        .get();
    expect(evidence.any((row) => row.payload.contains('legacy-clock')), isTrue);
    expect(
      evidence.any((row) => row.payload.contains('use_local_clock')),
      isTrue,
    );

    await firstDevice.dispose();
    await firstDatabase.close();
    firstDatabase = PactaDatabase(
      NativeDatabase(File('${directory.path}/first.sqlite')),
    );
    firstDevice = LocalNationalFocusRepository(
      database: firstDatabase,
      userId: 'ticket-19-user',
      remote: remote,
      now: () => now,
      cloudSyncEnabled: false,
    );
    expect((await firstDevice.getCard(clockOnly.id)).hasPendingReview, isFalse);
    expect((await firstDevice.getCard(conflicted.id)).hasPendingReview, isTrue);
    expect(
      (await firstDevice.getNationalFocusReviewState()).clockReviewCases,
      isEmpty,
    );
  });

  test('临时数据库从旧来源恢复投影不结算、不增来源且不访问远端', () async {
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(
        name: '旧国策',
        triggerCondition: '旧国策',
        action: '行动',
      ),
    );
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);
    final oldSources = await firstDatabase
        .select(firstDatabase.focusSyncSources)
        .get();
    final originalMaintenance =
        (await firstDatabase
                .select(firstDatabase.localNationalFocusMaintenance)
                .get())
            .single
            .lastSettledCheckpointAt;
    for (final source in oldSources) {
      await secondDatabase.customStatement(
        'INSERT INTO focus_sync_sources (user_id, source_id, device_id, entity_type, entity_id, parent_source_id, parent_source_ids, occurred_at, payload) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          source.userId,
          source.sourceId,
          source.deviceId,
          source.entityType,
          source.entityId,
          source.parentSourceId,
          source.parentSourceIds,
          source.occurredAt.millisecondsSinceEpoch ~/ 1000,
          source.payload,
        ],
      );
    }
    final spy = _CountingNationalFocusRemote();
    await secondDevice.dispose();
    now = now.add(const Duration(days: 30));
    secondDevice = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'ticket-19-user',
      remote: spy,
      now: () => now,
      cloudSyncEnabled: false,
    );
    await secondDevice.restoreLegacyCloudProjection();
    final restored =
        (await secondDatabase
                .select(secondDatabase.localNationalFocusCards)
                .get())
            .single;
    expect(restored.id, card.id);
    final restoredMaintenance =
        (await secondDatabase
                .select(secondDatabase.localNationalFocusMaintenance)
                .get())
            .single
            .lastSettledCheckpointAt;
    expect(restoredMaintenance, originalMaintenance);
    final restoredSources = await secondDatabase
        .select(secondDatabase.focusSyncSources)
        .get();
    expect(
      restoredSources.map((row) => row.sourceId).toSet(),
      oldSources.map((row) => row.sourceId).toSet(),
    );
    expect(spy.pullCount, 0);
    expect(spy.upsertCount, 0);
    await expectLater(
      secondDevice.restoreLegacyCloudProjection(),
      throwsStateError,
    );
  });

  test('关闭国策旧云同步时不读取或写入远端', () async {
    final spy = _CountingNationalFocusRemote();
    await firstDevice.dispose();
    firstDevice = LocalNationalFocusRepository(
      database: firstDatabase,
      userId: 'ticket-19-user',
      remote: spy,
      now: () => now,
      cloudSyncEnabled: false,
    );
    await firstDevice.createCard(
      const NationalFocusCardDraft(
        name: '本地任务',
        triggerCondition: '本地任务',
        action: '行动',
      ),
    );
    await firstDevice.sync();
    expect(spy.pullCount, 0);
    expect(spy.upsertCount, 0);
    expect(await firstDevice.getLibraryCards(), hasLength(1));
  });

  test('裁决采用分支时恢复完整熄灭原因并将结果同步到两个端点', () async {
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(
        name: '晨间锻炼',
        triggerCondition: '晨间锻炼',
        action: '热身三分钟',
      ),
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

class _CountingNationalFocusRemote implements NationalFocusRemoteDataSource {
  int pullCount = 0;
  int upsertCount = 0;

  @override
  Future<List<NationalFocusSyncSource>> pull({required String userId}) async {
    pullCount++;
    return const [];
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<NationalFocusSyncSource> sources,
  }) async {
    upsertCount++;
  }
}
