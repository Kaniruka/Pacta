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
    directory = await Directory.systemTemp.createTemp('pacta-t18-sync-');
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
      userId: 'ticket-18-user',
      remote: remote,
      now: () => now,
    );
    secondDevice = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'ticket-18-user',
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

  test('两天后上传的有效离线确认会协调仅由漏收推断的失败', () async {
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '开始阅读', action: '阅读 5 页'),
    );
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);

    now = DateTime.utc(2026, 9, 20, 20);
    await firstDevice.settleDueCheckpoints();
    await firstDevice.sync();
    await secondDevice.sync();
    expect(
      (await secondDevice.getCard(card.id)).state,
      NationalFocusCardState.pendingTodayConfirmation,
    );

    now = DateTime.utc(2026, 9, 21, 19);
    expect(await firstDevice.confirmToday(), 1);

    now = DateTime.utc(2026, 9, 21, 20);
    await secondDevice.settleDueCheckpoints();
    expect(await secondDevice.getFailures(cardId: card.id), hasLength(1));
    await secondDevice.sync();

    now = DateTime.utc(2026, 9, 23, 21);
    await firstDevice.sync();
    await secondDevice.sync();

    final failures = await secondDevice.getFailures(cardId: card.id);
    expect(
      failures.map((failure) => failure.checkpointAt.toUtc()),
      everyElement(DateTime.utc(2026, 9, 22, 20)),
    );
    expect(failures, hasLength(1));
    expect((await secondDevice.getCard(card.id)).successfulDays, 2);
  });

  test('真实离线操作冲突标记待核对并合并无关卡片', () async {
    final disputedCard = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '处理邮件', action: '先回一封邮件'),
    );
    final independentCard = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '整理桌面', action: '清理一个区域'),
    );
    await firstDevice.placeCard(cardId: disputedCard.id, parentId: null);
    await firstDevice.placeCard(cardId: independentCard.id, parentId: null);
    await firstDevice.lightCard(disputedCard.id);
    await firstDevice.lightCard(independentCard.id);

    now = DateTime.utc(2026, 9, 20, 20);
    await firstDevice.settleDueCheckpoints();
    await firstDevice.sync();
    await secondDevice.sync();

    now = DateTime.utc(2026, 9, 21, 19);
    expect(await firstDevice.confirmToday(), 2);
    await secondDevice.extinguishCard(
      cardId: disputedCard.id,
      failureReason: '发现冲突操作',
    );

    await firstDevice.sync();
    await secondDevice.sync();

    final disputed = await secondDevice.getCard(disputedCard.id);
    expect(disputed.hasPendingReview, isTrue);
    expect(disputed.state, NationalFocusCardState.pendingTodayConfirmation);
    await expectLater(
      secondDevice.lightCard(disputedCard.id),
      throwsA(isA<StateError>()),
    );

    final independent = await secondDevice.getCard(independentCard.id);
    expect(independent.hasPendingReview, isFalse);
    expect(independent.state, NationalFocusCardState.lit);
  });

  test('并发分支移动不会合成循环树，受影响节点保留待核对标记', () async {
    final firstCard = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '准备写作', action: '打开文档'),
    );
    final secondCard = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '准备阅读', action: '打开书本'),
    );
    await firstDevice.placeCard(cardId: firstCard.id, parentId: null);
    await firstDevice.placeCard(cardId: secondCard.id, parentId: null);
    await firstDevice.lightCard(firstCard.id);
    await firstDevice.lightCard(secondCard.id);

    now = DateTime.utc(2026, 9, 20, 20);
    await firstDevice.settleDueCheckpoints();
    await firstDevice.sync();
    await secondDevice.sync();

    await firstDevice.placeCard(cardId: firstCard.id, parentId: secondCard.id);
    await secondDevice.placeCard(cardId: secondCard.id, parentId: firstCard.id);
    await firstDevice.sync();
    await secondDevice.sync();

    final tree = await secondDevice.getTreeCards();
    final cardsById = {for (final card in tree) card.id: card};
    expect(cardsById[firstCard.id]!.parentId, isNull);
    expect(cardsById[secondCard.id]!.parentId, isNull);
    expect(cardsById[firstCard.id]!.hasPendingReview, isTrue);
    expect(cardsById[secondCard.id]!.hasPendingReview, isTrue);
    expect(await secondDevice.getFailures(), isEmpty);
  });

  test('要求版本、软删除历史和永久删除墓碑跨端同步且重复投递不重放', () async {
    final card = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '打开书本', action: '阅读 5 页'),
    );
    await firstDevice.saveStrengtheningLevel(
      cardId: card.id,
      draft: const NationalFocusStrengtheningLevelDraft(action: '阅读 10 页'),
    );
    await firstDevice.selectStrengtheningLevel(cardId: card.id, levelNumber: 1);
    await firstDevice.placeCard(cardId: card.id, parentId: null);
    await firstDevice.lightCard(card.id);

    now = DateTime.utc(2026, 9, 20, 20);
    await firstDevice.settleDueCheckpoints();
    now = DateTime.utc(2026, 9, 21, 20);
    await firstDevice.settleDueCheckpoints();
    await firstDevice.moveCardToLibrary(card.id);
    expect(
      await firstDevice.deleteCard(card.id),
      NationalFocusCardDeletion.softDeleted,
    );
    await firstDevice.sync();
    await secondDevice.sync();

    final restoredHistory = (await secondDevice.getDeletedCards()).single;
    expect(restoredHistory.parentId, isNull);
    expect(restoredHistory.isInTree, isFalse);
    expect(restoredHistory.isDeleted, isTrue);
    expect(restoredHistory.activeStrengtheningLevel, 1);
    expect(restoredHistory.effectiveAction, '阅读 10 页');
    expect(restoredHistory.requirementVersions, hasLength(2));
    expect(restoredHistory.successfulDays, 1);
    expect(restoredHistory.currentConsecutiveDays, 0);
    final failures = await secondDevice.getFailures(cardId: card.id);
    expect(failures, hasLength(1));
    expect(failures.single.treeSnapshot, hasLength(1));
    final failureId = failures.single.id;
    await secondDevice.sync();
    await secondDevice.sync();
    expect(
      (await secondDevice.getFailures(cardId: card.id)).single.id,
      failureId,
    );

    final permanentlyDeleted = await firstDevice.createCard(
      const NationalFocusCardDraft(triggerCondition: '归档便笺', action: '移除临时便笺'),
    );
    expect(
      await firstDevice.deleteCard(permanentlyDeleted.id),
      NationalFocusCardDeletion.permanentlyDeleted,
    );
    await firstDevice.sync();
    await secondDevice.sync();
    await secondDevice.sync();
    expect(
      (await secondDevice.getLibraryCards()).map((card) => card.id),
      isNot(contains(permanentlyDeleted.id)),
    );
    await expectLater(
      secondDevice.getCard(permanentlyDeleted.id),
      throwsA(isA<StateError>()),
    );

    final databasePath = '${directory.path}/second.sqlite';
    await secondDevice.dispose();
    await secondDatabase.close();
    secondDatabase = PactaDatabase(NativeDatabase(File(databasePath)));
    secondDevice = LocalNationalFocusRepository(
      database: secondDatabase,
      userId: 'ticket-18-user',
      remote: remote,
      now: () => now,
    );
    await secondDevice.sync();
    expect((await secondDevice.getDeletedCards()).single.id, card.id);
    expect((await secondDevice.getFailures(cardId: card.id)), hasLength(1));
    expect(
      (await secondDevice.getLibraryCards()).map((card) => card.id),
      isNot(contains(permanentlyDeleted.id)),
    );
  });
}
