import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

/// Ticket 11：失败回顾状态（未回顾/已回顾）。
///
/// 回顾状态是失败记录上独立于既有裁定字段（reviewDisposition）的持久标记；
/// 标记幂等，且绝不改写失败结果、结算统计与冻结要求。
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
        name: trigger,
        triggerCondition: trigger,
        action: action,
      );

  Future<String> createFailedBatch({int nodes = 2}) async {
    for (var index = 0; index < nodes; index++) {
      final card = await repository.createCard(draft('触发 $index', '行动 $index'));
      await repository.placeCard(cardId: card.id, parentId: null);
      await repository.lightCard(card.id);
    }
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    now = DateTime.utc(2026, 9, 26, 20);
    await repository.settleDueCheckpoints();
    final failures = await repository.getFailures();
    expect(failures, isNotEmpty);
    return failures.first.batchId;
  }

  String failureFacts(NationalFocusFailure failure) =>
      '${failure.id}|${failure.batchId}|${failure.cardId}|'
      '${failure.checkpointAt.toUtc().toIso8601String()}|${failure.cause}|'
      '${failure.failureReason}|${failure.sharedExplanation}';

  String frozenFacts(NationalFocusFailure failure) => failure.treeSnapshot
      .map(
        (card) =>
            '${card.id}|${card.name}|${card.state}|'
            '${card.effectiveAction}|${card.requirementVersionNumber}|'
            '${card.currentConsecutiveDays}|${card.bestConsecutiveDays}',
      )
      .join(',');

  test('新记录默认未回顾，标记已回顾幂等且不改写失败结果与冻结要求', () async {
    final batchId = await createFailedBatch();
    final before = await repository.getFailures();
    final treeBefore = await repository.getTreeCards();
    final cardsBefore = <NationalFocusCard>[
      for (final failure in before) await repository.getCard(failure.cardId),
    ];

    expect(before, hasLength(2));
    expect(before.every((failure) => failure.isReviewed), isFalse);
    expect(before.every((failure) => failure.needsReflection), isTrue);
    expect(before.every((failure) => failure.reviewedAt == null), isTrue);

    await repository.markFailureReviewed(batchId: batchId);

    final reviewed = await repository.getFailures();
    expect(reviewed.every((failure) => failure.isReviewed), isTrue);
    expect(reviewed.every((failure) => failure.needsReflection), isFalse);
    final reviewedAt = reviewed.map((failure) => failure.reviewedAt).toSet();
    expect(reviewedAt, hasLength(1));
    expect(reviewedAt.single, isNotNull);

    // 重复标记不产生额外副作用：时间戳保持首次标记的值。
    await repository.markFailureReviewed(batchId: batchId);
    final repeated = await repository.getFailures();
    expect(repeated.map((failure) => failure.reviewedAt).toSet(), reviewedAt);
    expect(repeated, hasLength(before.length));

    // 失败结果、结算事实与冻结要求都保持标记前的样子。
    expect(
      reviewed.map(failureFacts),
      before.map(failureFacts),
      reason: '回顾标记不得改写失败原因、检查点或补充说明。',
    );
    expect(
      reviewed.map(frozenFacts),
      before.map(frozenFacts),
      reason: '回顾标记不得改写当时树的冻结要求。',
    );
    final treeAfter = await repository.getTreeCards();
    expect(
      treeAfter.map((card) => '${card.id}|${card.name}|${card.state}'),
      treeBefore.map((card) => '${card.id}|${card.name}|${card.state}'),
    );
    for (final card in cardsBefore) {
      final after = await repository.getCard(card.id);
      expect(after.state, card.state);
      expect(after.successfulDays, card.successfulDays);
      expect(after.currentConsecutiveDays, card.currentConsecutiveDays);
      expect(after.bestConsecutiveDays, card.bestConsecutiveDays);
    }
  });

  test('回顾状态与既有裁定字段互不影响，裁定语义保持原样', () async {
    final batchId = await createFailedBatch();
    await (database.update(database.localNationalFocusFailures)
          ..where((row) => row.userId.equals('user-a'))
          ..where((row) => row.batchId.equals(batchId)))
        .write(
          const LocalNationalFocusFailuresCompanion(
            reviewDisposition: Value('pending_review'),
          ),
        );

    var failures = await repository.getFailures();
    expect(failures.every((failure) => failure.isPendingReview), isTrue);
    expect(failures.every((failure) => failure.isReviewed), isFalse);

    await repository.markFailureReviewed(batchId: batchId);
    failures = await repository.getFailures();
    expect(failures.every((failure) => failure.isReviewed), isTrue);
    expect(
      failures.every((failure) => failure.isPendingReview),
      isTrue,
      reason: '裁定待核对是另一个概念，标记回顾不得改变它。',
    );

    var rows = await database.select(database.localNationalFocusFailures).get();
    expect(
      rows.every((row) => row.reviewDisposition == 'pending_review'),
      isTrue,
    );

    await (database.update(database.localNationalFocusFailures)
          ..where((row) => row.userId.equals('user-a'))
          ..where((row) => row.batchId.equals(batchId)))
        .write(
          const LocalNationalFocusFailuresCompanion(
            reviewDisposition: Value('accepted'),
          ),
        );
    final afterArbitration = await repository.getFailures();
    expect(
      afterArbitration.every((failure) => failure.isReviewed),
      isTrue,
      reason: '裁定落定不得清掉已有的回顾标记。',
    );
    expect(
      afterArbitration.every((failure) => failure.isPendingReview),
      isFalse,
    );
    rows = await database.select(database.localNationalFocusFailures).get();
    expect(rows.every((row) => row.reviewedAt != null), isTrue);
  });

  test('回顾后可补充或清空说明，说明与回顾状态互不牵连', () async {
    final batchId = await createFailedBatch();
    await repository.markFailureReviewed(batchId: batchId);

    await repository.updateFailureExplanation(
      batchId: batchId,
      explanation: '  先把资料找齐  ',
    );
    var failures = await repository.getFailures();
    expect(failures.map((failure) => failure.sharedExplanation).toSet(), {
      '先把资料找齐',
    });
    expect(failures.every((failure) => failure.isReviewed), isTrue);

    await repository.updateFailureExplanation(
      batchId: batchId,
      explanation: null,
    );
    failures = await repository.getFailures();
    expect(
      failures.every((failure) => failure.sharedExplanation == null),
      isTrue,
    );
    expect(
      failures.every((failure) => failure.isReviewed),
      isTrue,
      reason: '清空说明不是撤回回顾。',
    );
    expect(failures, hasLength(2));
  });
}
