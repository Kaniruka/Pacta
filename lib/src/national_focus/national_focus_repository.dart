import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../tasks/task_database.dart';
import 'national_focus_checkpoints.dart';
import 'national_focus_models.dart';

abstract interface class NationalFocusRepository {
  Stream<List<NationalFocusCard>> watchTreeCards();
  Stream<List<NationalFocusCard>> watchLibraryCards();
  Future<List<NationalFocusCard>> getTreeCards();
  Future<List<NationalFocusCard>> getLibraryCards();
  Future<NationalFocusCard> getCard(String cardId);
  Future<NationalFocusCard> createCard(NationalFocusCardDraft draft);
  Future<void> placeCard({required String cardId, required String? parentId});
  Future<void> lightCard(String cardId);
  Future<void> extinguishCard({required String cardId, String? failureReason});
  Future<int> confirmToday();
  Future<void> settleDueCheckpoints();
  Future<List<NationalFocusFailure>> getFailures({String? cardId});
  Future<void> updateFailureExplanation({
    required String batchId,
    required String? explanation,
  });
  Future<void> dispose();
}

class LocalNationalFocusRepository implements NationalFocusRepository {
  LocalNationalFocusRepository({
    required this.database,
    required this.userId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', '用户标识不能为空。');
    }
  }

  final PactaDatabase database;
  final String userId;
  final DateTime Function() _now;
  final _uuid = const Uuid();

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() => _watchCards(inTree: true);

  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() =>
      _watchCards(inTree: false);

  Stream<List<NationalFocusCard>> _watchCards({required bool inTree}) async* {
    await settleDueCheckpoints();
    final query = database.select(database.localNationalFocusCards)
      ..where((card) => card.userId.equals(userId))
      ..where((card) => card.isInTree.equals(inTree))
      ..orderBy([
        (card) => OrderingTerm.asc(card.createdAt),
        (card) => OrderingTerm.asc(card.id),
      ]);
    yield* query.watch().map(_cardsFromRows);
  }

  @override
  Future<List<NationalFocusCard>> getTreeCards() => _getCards(inTree: true);

  @override
  Future<List<NationalFocusCard>> getLibraryCards() => _getCards(inTree: false);

  @override
  Future<NationalFocusCard> getCard(String cardId) async {
    await settleDueCheckpoints();
    return _cardFromRow(await _findCardRow(cardId));
  }

  @override
  Future<NationalFocusCard> createCard(NationalFocusCardDraft draft) async {
    await settleDueCheckpoints();
    final timestamp = _nextTimestamp();
    final card = NationalFocusCard(
      id: _uuid.v4(),
      triggerCondition: _requiredText(draft.triggerCondition, '主要触发条件'),
      action: _requiredText(draft.action, '行动'),
      scope: _optionalText(draft.scope),
      exceptionNotes: _optionalText(draft.exceptionNotes),
      isInTree: false,
      state: NationalFocusCardState.extinguished,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await database
        .into(database.localNationalFocusCards)
        .insert(
          LocalNationalFocusCardsCompanion.insert(
            userId: userId,
            id: card.id,
            triggerCondition: card.triggerCondition,
            action: card.action,
            scope: Value(card.scope),
            exceptionNotes: Value(card.exceptionNotes),
            isInTree: const Value(false),
            parentId: const Value(null),
            state: Value(card.state.storageValue),
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );
    return card;
  }

  @override
  Future<void> placeCard({
    required String cardId,
    required String? parentId,
  }) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      final rows = await (database.select(
        database.localNationalFocusCards,
      )..where((candidate) => candidate.userId.equals(userId))).get();
      final cardsById = {for (final row in rows) row.id: row};

      if (parentId != null) {
        if (parentId == cardId) {
          throw ArgumentError('国策卡不能成为自己的父节点。');
        }
        final parent = cardsById[parentId];
        if (parent == null || !parent.isInTree) {
          throw StateError('所选父节点不存在或不在当前用户的树中。');
        }

        String? ancestorId = parentId;
        final visited = <String>{};
        while (ancestorId != null) {
          if (ancestorId == cardId) {
            throw ArgumentError('不能把国策卡放到自己的后代节点下。');
          }
          if (!visited.add(ancestorId)) {
            throw StateError('现有国策树结构无效，无法继续放置。');
          }
          final ancestor = cardsById[ancestorId];
          if (ancestor == null || !ancestor.isInTree) {
            throw StateError('所选父节点的树结构无效，无法继续放置。');
          }
          ancestorId = ancestor.parentId;
        }
      }

      if (card.isInTree && card.parentId == parentId) return;
      final updatedAt = _nextTimestamp(card.updatedAt);
      await (database.update(database.localNationalFocusCards)
            ..where((candidate) => candidate.userId.equals(userId))
            ..where((candidate) => candidate.id.equals(cardId)))
          .write(
            LocalNationalFocusCardsCompanion(
              isInTree: const Value(true),
              parentId: Value(parentId),
              updatedAt: Value(updatedAt),
            ),
          );
    });
  }

  @override
  Future<void> lightCard(String cardId) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      if (!card.isInTree) {
        throw StateError('卡片需要先放入国策树才能点亮。');
      }
      if (card.state == NationalFocusCardState.lit.storageValue) return;

      await _updateCard(
        card,
        LocalNationalFocusCardsCompanion(
          state: Value(NationalFocusCardState.lit.storageValue),
          currentConsecutiveDays: Value(
            card.maintenanceCycleStarted ? card.currentConsecutiveDays : 0,
          ),
          maintenanceCycleStarted: const Value(true),
          failureReason: const Value(null),
          updatedAt: Value(_nextTimestamp(card.updatedAt)),
        ),
      );
    });
  }

  @override
  Future<void> extinguishCard({
    required String cardId,
    String? failureReason,
  }) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      if (!card.isInTree) {
        throw StateError('卡片不在国策树中。');
      }
      if (card.state == NationalFocusCardState.extinguished.storageValue) {
        return;
      }
      await _updateCard(
        card,
        LocalNationalFocusCardsCompanion(
          state: Value(NationalFocusCardState.extinguished.storageValue),
          failureReason: Value(_optionalText(failureReason)),
          updatedAt: Value(_nextTimestamp(card.updatedAt)),
        ),
      );
    });
  }

  @override
  Future<int> confirmToday() async {
    await settleDueCheckpoints();
    return database.transaction(() async {
      final pendingCards =
          await (database.select(database.localNationalFocusCards)
                ..where((card) => card.userId.equals(userId))
                ..where((card) => card.isInTree.equals(true))
                ..where(
                  (card) => card.state.equals(
                    NationalFocusCardState
                        .pendingTodayConfirmation
                        .storageValue,
                  ),
                ))
              .get();

      for (final card in pendingCards) {
        await _updateCard(
          card,
          LocalNationalFocusCardsCompanion(
            state: Value(NationalFocusCardState.lit.storageValue),
            failureReason: const Value(null),
            updatedAt: Value(_nextTimestamp(card.updatedAt)),
          ),
        );
      }
      return pendingCards.length;
    });
  }

  @override
  Future<void> settleDueCheckpoints() async {
    final now = _now().toUtc();
    await database.transaction(() async {
      final progress = await (database.select(
        database.localNationalFocusMaintenance,
      )..where((row) => row.userId.equals(userId))).getSingleOrNull();
      if (progress == null) {
        await database
            .into(database.localNationalFocusMaintenance)
            .insert(
              LocalNationalFocusMaintenanceCompanion.insert(
                userId: userId,
                lastSettledCheckpointAt: nationalFocusCheckpointAtOrBefore(now),
              ),
            );
        return;
      }

      var checkpoint = progress.lastSettledCheckpointAt.toUtc().add(
        nationalFocusCheckpointPeriod,
      );
      while (!checkpoint.isAfter(now)) {
        await _settleCheckpoint(checkpoint);
        await (database.update(
          database.localNationalFocusMaintenance,
        )..where((row) => row.userId.equals(userId))).write(
          LocalNationalFocusMaintenanceCompanion(
            lastSettledCheckpointAt: Value(checkpoint),
          ),
        );
        checkpoint = checkpoint.add(nationalFocusCheckpointPeriod);
      }
    });
  }

  Future<void> _settleCheckpoint(DateTime checkpoint) async {
    final cards =
        await (database.select(database.localNationalFocusCards)
              ..where((card) => card.userId.equals(userId))
              ..where((card) => card.isInTree.equals(true))
              ..orderBy([
                (card) => OrderingTerm.asc(card.createdAt),
                (card) => OrderingTerm.asc(card.id),
              ]))
            .get();
    if (cards.isEmpty) return;

    final snapshotJson = jsonEncode(cards.map(_snapshotJson).toList());
    final pending = cards
        .where(
          (card) =>
              card.state ==
              NationalFocusCardState.pendingTodayConfirmation.storageValue,
        )
        .toList(growable: false);
    final missedConfirmationBatchId = pending.isEmpty ? null : _uuid.v4();

    for (final card in cards) {
      final state = NationalFocusCardState.fromStorage(card.state);
      if (state == NationalFocusCardState.lit) {
        final currentConsecutive = card.currentConsecutiveDays + 1;
        await _updateCard(
          card,
          LocalNationalFocusCardsCompanion(
            state: Value(
              NationalFocusCardState.pendingTodayConfirmation.storageValue,
            ),
            successfulDays: Value(card.successfulDays + 1),
            currentConsecutiveDays: Value(currentConsecutive),
            bestConsecutiveDays: Value(
              currentConsecutive > card.bestConsecutiveDays
                  ? currentConsecutive
                  : card.bestConsecutiveDays,
            ),
            maintenanceCycleStarted: const Value(true),
            updatedAt: Value(checkpoint),
          ),
        );
      } else if (state == NationalFocusCardState.pendingTodayConfirmation) {
        await _recordFailure(
          card: card,
          checkpoint: checkpoint,
          cause: NationalFocusFailureCause.missedConfirmation,
          failureReason: NationalFocusFailureCause.missedConfirmation.label,
          batchId: missedConfirmationBatchId!,
          snapshotJson: snapshotJson,
        );
      } else if (card.maintenanceCycleStarted) {
        await _recordFailure(
          card: card,
          checkpoint: checkpoint,
          cause: NationalFocusFailureCause.activeExtinguish,
          failureReason: card.failureReason,
          batchId: _uuid.v4(),
          snapshotJson: snapshotJson,
        );
      }
    }
  }

  Future<void> _recordFailure({
    required LocalNationalFocusCard card,
    required DateTime checkpoint,
    required NationalFocusFailureCause cause,
    required String? failureReason,
    required String batchId,
    required String snapshotJson,
  }) async {
    await database
        .into(database.localNationalFocusFailures)
        .insert(
          LocalNationalFocusFailuresCompanion.insert(
            userId: userId,
            id: _uuid.v4(),
            batchId: batchId,
            cardId: card.id,
            checkpointAt: checkpoint,
            cause: cause.storageValue,
            failureReason: Value(failureReason),
            sharedExplanation: const Value(null),
            treeSnapshot: snapshotJson,
          ),
        );
    await _updateCard(
      card,
      LocalNationalFocusCardsCompanion(
        state: Value(NationalFocusCardState.extinguished.storageValue),
        currentConsecutiveDays: const Value(0),
        maintenanceCycleStarted: const Value(false),
        failureReason: const Value(null),
        updatedAt: Value(checkpoint),
      ),
    );
  }

  @override
  Future<List<NationalFocusFailure>> getFailures({String? cardId}) async {
    await settleDueCheckpoints();
    final query = database.select(database.localNationalFocusFailures)
      ..where((failure) => failure.userId.equals(userId))
      ..orderBy([
        (failure) => OrderingTerm.desc(failure.checkpointAt),
        (failure) => OrderingTerm.asc(failure.cardId),
      ]);
    if (cardId != null) {
      query.where((failure) => failure.cardId.equals(cardId));
    }
    return (await query.get()).map(_failureFromRow).toList(growable: false);
  }

  @override
  Future<void> updateFailureExplanation({
    required String batchId,
    required String? explanation,
  }) async {
    await settleDueCheckpoints();
    final normalized = _optionalText(explanation);
    if (normalized != null && normalized.length > 500) {
      throw ArgumentError('补充说明不能超过 500 个字符。');
    }
    final updated =
        await (database.update(database.localNationalFocusFailures)
              ..where((failure) => failure.userId.equals(userId))
              ..where((failure) => failure.batchId.equals(batchId)))
            .write(
              LocalNationalFocusFailuresCompanion(
                sharedExplanation: Value(normalized),
              ),
            );
    if (updated == 0) {
      throw StateError('找不到这组国策失败记录。');
    }
  }

  @override
  Future<void> dispose() async {}

  Future<List<NationalFocusCard>> _getCards({required bool inTree}) async {
    await settleDueCheckpoints();
    final query = database.select(database.localNationalFocusCards)
      ..where((card) => card.userId.equals(userId))
      ..where((card) => card.isInTree.equals(inTree))
      ..orderBy([
        (card) => OrderingTerm.asc(card.createdAt),
        (card) => OrderingTerm.asc(card.id),
      ]);
    return _cardsFromRows(await query.get());
  }

  Future<LocalNationalFocusCard> _findCardRow(String cardId) async {
    final row =
        await (database.select(database.localNationalFocusCards)
              ..where((card) => card.userId.equals(userId))
              ..where((card) => card.id.equals(cardId)))
            .getSingleOrNull();
    if (row == null) {
      throw StateError('国策卡不存在或不属于当前用户。');
    }
    return row;
  }

  Future<void> _updateCard(
    LocalNationalFocusCard card,
    LocalNationalFocusCardsCompanion update,
  ) async {
    await (database.update(database.localNationalFocusCards)
          ..where((candidate) => candidate.userId.equals(userId))
          ..where((candidate) => candidate.id.equals(card.id)))
        .write(update);
  }

  List<NationalFocusCard> _cardsFromRows(List<LocalNationalFocusCard> rows) =>
      rows.map(_cardFromRow).toList(growable: false);

  NationalFocusCard _cardFromRow(LocalNationalFocusCard row) =>
      NationalFocusCard(
        id: row.id,
        triggerCondition: row.triggerCondition,
        action: row.action,
        scope: row.scope,
        exceptionNotes: row.exceptionNotes,
        isInTree: row.isInTree,
        parentId: row.parentId,
        state: NationalFocusCardState.fromStorage(row.state),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        successfulDays: row.successfulDays,
        currentConsecutiveDays: row.currentConsecutiveDays,
        bestConsecutiveDays: row.bestConsecutiveDays,
        maintenanceCycleStarted: row.maintenanceCycleStarted,
        failureReason: row.failureReason,
      );

  Map<String, Object?> _snapshotJson(LocalNationalFocusCard row) => {
    'id': row.id,
    'triggerCondition': row.triggerCondition,
    'action': row.action,
    'scope': row.scope,
    'exceptionNotes': row.exceptionNotes,
    'isInTree': row.isInTree,
    'parentId': row.parentId,
    'state': row.state,
    'successfulDays': row.successfulDays,
    'currentConsecutiveDays': row.currentConsecutiveDays,
    'bestConsecutiveDays': row.bestConsecutiveDays,
    'maintenanceCycleStarted': row.maintenanceCycleStarted,
    'failureReason': row.failureReason,
    'createdAt': row.createdAt.toUtc().toIso8601String(),
    'updatedAt': row.updatedAt.toUtc().toIso8601String(),
  };

  NationalFocusFailure _failureFromRow(LocalNationalFocusFailure row) {
    final decoded = jsonDecode(row.treeSnapshot) as List<dynamic>;
    final snapshot = decoded
        .map((value) {
          final item = value as Map<String, dynamic>;
          return NationalFocusCardSnapshot(
            id: item['id'] as String,
            triggerCondition: item['triggerCondition'] as String,
            action: item['action'] as String,
            scope: item['scope'] as String?,
            exceptionNotes: item['exceptionNotes'] as String?,
            isInTree: item['isInTree'] as bool,
            parentId: item['parentId'] as String?,
            state: NationalFocusCardState.fromStorage(item['state'] as String),
            successfulDays: item['successfulDays'] as int,
            currentConsecutiveDays: item['currentConsecutiveDays'] as int,
            bestConsecutiveDays: item['bestConsecutiveDays'] as int,
            maintenanceCycleStarted: item['maintenanceCycleStarted'] as bool,
            failureReason: item['failureReason'] as String?,
            createdAt: DateTime.parse(item['createdAt'] as String),
            updatedAt: DateTime.parse(item['updatedAt'] as String),
          );
        })
        .toList(growable: false);
    return NationalFocusFailure(
      id: row.id,
      batchId: row.batchId,
      cardId: row.cardId,
      checkpointAt: row.checkpointAt,
      cause: NationalFocusFailureCause.fromStorage(row.cause),
      failureReason: row.failureReason,
      sharedExplanation: row.sharedExplanation,
      treeSnapshot: snapshot,
    );
  }

  String _requiredText(String value, String label) {
    final normalized = value.trim();
    if (normalized.isEmpty) throw ArgumentError('$label不能为空。');
    return normalized;
  }

  String? _optionalText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  DateTime _nextTimestamp([DateTime? previous]) {
    final candidate = _now().toUtc();
    final second = DateTime.fromMillisecondsSinceEpoch(
      candidate.millisecondsSinceEpoch - candidate.millisecond,
      isUtc: true,
    );
    if (previous == null) return second;
    final previousUtc = previous.toUtc();
    return second.isAfter(previousUtc)
        ? second
        : previousUtc.add(const Duration(seconds: 1));
  }
}

class UnavailableNationalFocusRepository implements NationalFocusRepository {
  const UnavailableNationalFocusRepository();

  @override
  Stream<List<NationalFocusCard>> watchTreeCards() =>
      Stream.value(const <NationalFocusCard>[]);

  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() =>
      Stream.value(const <NationalFocusCard>[]);

  @override
  Future<List<NationalFocusCard>> getTreeCards() async => const [];

  @override
  Future<List<NationalFocusCard>> getLibraryCards() async => const [];

  @override
  Future<NationalFocusCard> getCard(String cardId) => _unavailable();

  @override
  Future<NationalFocusCard> createCard(NationalFocusCardDraft draft) =>
      _unavailable();

  @override
  Future<void> placeCard({required String cardId, required String? parentId}) =>
      _unavailable();

  @override
  Future<void> lightCard(String cardId) => _unavailable();

  @override
  Future<void> extinguishCard({
    required String cardId,
    String? failureReason,
  }) => _unavailable();

  @override
  Future<int> confirmToday() => _unavailable();

  @override
  Future<void> settleDueCheckpoints() async {}

  @override
  Future<List<NationalFocusFailure>> getFailures({String? cardId}) async =>
      const [];

  @override
  Future<void> updateFailureExplanation({
    required String batchId,
    required String? explanation,
  }) => _unavailable();

  @override
  Future<void> dispose() async {}

  Future<T> _unavailable<T>() async {
    throw StateError('当前用户的国策卡片存储尚未配置。');
  }
}
