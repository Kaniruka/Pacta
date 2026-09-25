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
  Stream<List<NationalFocusCard>> watchDeletedCards();
  Future<List<NationalFocusCard>> getTreeCards();
  Future<List<NationalFocusCard>> getLibraryCards();
  Future<List<NationalFocusCard>> getDeletedCards();
  Future<NationalFocusCard> getCard(String cardId);
  Future<NationalFocusCard> createCard(NationalFocusCardDraft draft);
  Future<void> placeCard({required String cardId, required String? parentId});
  Future<void> moveCardToLibrary(String cardId);
  Future<NationalFocusCardDeletion> deleteCard(String cardId);
  Future<void> restoreDeletedCard(String cardId);
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
  Stream<List<NationalFocusCard>> watchTreeCards() =>
      _watchCards(inTree: true, deleted: false);

  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() =>
      _watchCards(inTree: false, deleted: false);

  @override
  Stream<List<NationalFocusCard>> watchDeletedCards() =>
      _watchCards(inTree: false, deleted: true);

  Stream<List<NationalFocusCard>> _watchCards({
    required bool inTree,
    required bool deleted,
  }) async* {
    await settleDueCheckpoints();
    final query = database.select(database.localNationalFocusCards)
      ..where((card) => card.userId.equals(userId))
      ..where((card) => card.isInTree.equals(inTree))
      ..where(
        (card) =>
            deleted ? card.deletedAt.isNotNull() : card.deletedAt.isNull(),
      )
      ..orderBy([
        (card) => OrderingTerm.asc(card.createdAt),
        (card) => OrderingTerm.asc(card.id),
      ]);
    yield* query.watch().map(_cardsFromRows);
  }

  @override
  Future<List<NationalFocusCard>> getTreeCards() =>
      _getCards(inTree: true, deleted: false);

  @override
  Future<List<NationalFocusCard>> getLibraryCards() =>
      _getCards(inTree: false, deleted: false);

  @override
  Future<List<NationalFocusCard>> getDeletedCards() =>
      _getCards(inTree: false, deleted: true);

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
      if (card.deletedAt != null) {
        throw StateError('已删除的国策卡需要先恢复到卡片库。');
      }
      final rows = await (database.select(
        database.localNationalFocusCards,
      )..where((candidate) => candidate.userId.equals(userId))).get();
      final cardsById = {for (final row in rows) row.id: row};
      var targetBranchHasExtinguishedAncestor = false;

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
          if (ancestor.state ==
              NationalFocusCardState.extinguished.storageValue) {
            targetBranchHasExtinguishedAncestor = true;
          }
          ancestorId = ancestor.parentId;
        }
      }

      if (targetBranchHasExtinguishedAncestor) {
        final treeCards = rows.where((row) => row.isInTree).toList();
        final movedBranch = [card, ..._descendantsOf(card.id, treeCards)];
        if (movedBranch.any(
          (candidate) =>
              candidate.state == NationalFocusCardState.lit.storageValue ||
              candidate.state ==
                  NationalFocusCardState.pendingTodayConfirmation.storageValue,
        )) {
          throw StateError('不能把仍在点亮或待确认的分支放到熄灭父节点下。');
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
  Future<void> moveCardToLibrary(String cardId) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      if (card.deletedAt != null) {
        throw StateError('已删除的国策卡需要先恢复到卡片库。');
      }
      if (!card.isInTree) {
        throw StateError('只有树中的国策卡可以移入卡片库。');
      }
      final treeCards =
          await (database.select(database.localNationalFocusCards)
                ..where((candidate) => candidate.userId.equals(userId))
                ..where((candidate) => candidate.isInTree.equals(true)))
              .get();
      final branch = [card, ..._descendantsOf(card.id, treeCards)];
      for (final branchCard in branch) {
        final state = NationalFocusCardState.fromStorage(branchCard.state);
        final priorCascadeState = branchCard.cascadePriorState == null
            ? null
            : NationalFocusCardState.fromStorage(branchCard.cascadePriorState!);
        final needsRelighting =
            state == NationalFocusCardState.lit ||
            state == NationalFocusCardState.pendingTodayConfirmation ||
            priorCascadeState == NationalFocusCardState.lit ||
            priorCascadeState ==
                NationalFocusCardState.pendingTodayConfirmation;
        await _updateCard(
          branchCard,
          LocalNationalFocusCardsCompanion(
            isInTree: const Value(false),
            parentId: const Value(null),
            state: Value(
              needsRelighting
                  ? NationalFocusCardState.pendingTodayConfirmation.storageValue
                  : branchCard.state,
            ),
            cascadeSourceCardId: const Value(null),
            cascadePriorState: const Value(null),
            updatedAt: Value(_nextTimestamp(branchCard.updatedAt)),
          ),
        );
      }
    });
  }

  @override
  Future<NationalFocusCardDeletion> deleteCard(String cardId) async {
    await settleDueCheckpoints();
    return database.transaction(() async {
      final card = await _findCardRow(cardId);
      if (card.deletedAt != null) {
        throw StateError('这张国策卡已在已删除列表中。');
      }
      if (card.isInTree) {
        throw StateError('请先把国策卡移入卡片库，再删除。');
      }
      final attachedCards =
          await (database.select(database.localNationalFocusCards)
                ..where((candidate) => candidate.userId.equals(userId))
                ..where((candidate) => candidate.parentId.equals(cardId)))
              .get();
      if (attachedCards.isNotEmpty) {
        throw StateError('请先把所属分支移入卡片库，再删除。');
      }

      final failures = await (database.select(
        database.localNationalFocusFailures,
      )..where((failure) => failure.userId.equals(userId))).get();
      var referencedByHistory = false;
      for (final failure in failures) {
        if (failure.cardId == cardId) {
          referencedByHistory = true;
          break;
        }
        try {
          final snapshot = jsonDecode(failure.treeSnapshot) as List<dynamic>;
          if (snapshot.any(
            (entry) => (entry as Map<String, dynamic>)['id'] == cardId,
          )) {
            referencedByHistory = true;
            break;
          }
        } on FormatException {
          throw StateError('无法读取国策历史快照；为保护历史记录，无法删除这张卡。');
        } on TypeError {
          throw StateError('国策历史快照格式无效；为保护历史记录，无法删除这张卡。');
        }
      }

      if (!referencedByHistory) {
        await (database.delete(database.localNationalFocusCards)
              ..where((candidate) => candidate.userId.equals(userId))
              ..where((candidate) => candidate.id.equals(cardId)))
            .go();
        return NationalFocusCardDeletion.permanentlyDeleted;
      }

      final deletedAt = _nextTimestamp(card.updatedAt);
      await _updateCard(
        card,
        LocalNationalFocusCardsCompanion(
          deletedAt: Value(deletedAt),
          updatedAt: Value(deletedAt),
        ),
      );
      return NationalFocusCardDeletion.softDeleted;
    });
  }

  @override
  Future<void> restoreDeletedCard(String cardId) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      if (card.deletedAt == null || card.isInTree) {
        throw StateError('已删除列表中找不到这张国策卡。');
      }
      await _updateCard(
        card,
        LocalNationalFocusCardsCompanion(
          deletedAt: const Value(null),
          isInTree: const Value(false),
          parentId: const Value(null),
          updatedAt: Value(_nextTimestamp(card.updatedAt)),
        ),
      );
    });
  }

  @override
  Future<void> lightCard(String cardId) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      if (card.deletedAt != null) {
        throw StateError('已删除的国策卡需要先恢复到卡片库。');
      }
      if (!card.isInTree) {
        throw StateError('卡片需要先放入国策树才能点亮。');
      }
      final cards = await (database.select(
        database.localNationalFocusCards,
      )..where((candidate) => candidate.userId.equals(userId))).get();
      final cardsById = {
        for (final candidate in cards) candidate.id: candidate,
      };
      var ancestorId = card.parentId;
      final visitedAncestors = <String>{};
      while (ancestorId != null) {
        if (!visitedAncestors.add(ancestorId)) {
          throw StateError('现有国策树结构无效，无法点亮节点。');
        }
        final ancestor = cardsById[ancestorId];
        if (ancestor == null || !ancestor.isInTree) {
          throw StateError('父节点不存在或不在当前用户的树中。');
        }
        if (ancestor.state ==
            NationalFocusCardState.extinguished.storageValue) {
          throw StateError('父节点熄灭期间不能点亮子节点。');
        }
        ancestorId = ancestor.parentId;
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
          cascadeSourceCardId: const Value(null),
          cascadePriorState: const Value(null),
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
      if (card.deletedAt != null) {
        throw StateError('已删除的国策卡需要先恢复到卡片库。');
      }
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

      final treeCards =
          await (database.select(database.localNationalFocusCards)
                ..where((candidate) => candidate.userId.equals(userId))
                ..where((candidate) => candidate.isInTree.equals(true)))
              .get();
      final descendants = _descendantsOf(card.id, treeCards);
      for (final descendant in descendants) {
        final state = NationalFocusCardState.fromStorage(descendant.state);
        final hasExistingCascade = descendant.cascadeSourceCardId != null;
        if (state == NationalFocusCardState.extinguished &&
            !hasExistingCascade) {
          // Preserve a child's own already-pending failure as an independent
          // source, and leave a previously settled failure untouched.
          continue;
        }
        final stateBeforeCascade = descendant.cascadePriorState == null
            ? state
            : NationalFocusCardState.fromStorage(descendant.cascadePriorState!);
        await _updateCard(
          descendant,
          LocalNationalFocusCardsCompanion(
            state: Value(NationalFocusCardState.extinguished.storageValue),
            failureReason: const Value(null),
            cascadeSourceCardId: Value(card.id),
            cascadePriorState: Value(stateBeforeCascade.storageValue),
            updatedAt: Value(_nextTimestamp(descendant.updatedAt)),
          ),
        );
      }
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
                )
                ..where((card) => card.deletedAt.isNull()))
              .get();
      final treeCards =
          await (database.select(database.localNationalFocusCards)
                ..where((card) => card.userId.equals(userId))
                ..where((card) => card.isInTree.equals(true)))
              .get();
      final cardsById = {for (final card in treeCards) card.id: card};

      var confirmedCount = 0;
      for (final card in pendingCards) {
        if (_hasExtinguishedAncestor(card, cardsById)) continue;
        await _updateCard(
          card,
          LocalNationalFocusCardsCompanion(
            state: Value(NationalFocusCardState.lit.storageValue),
            failureReason: const Value(null),
            updatedAt: Value(_nextTimestamp(card.updatedAt)),
          ),
        );
        confirmedCount++;
      }
      return confirmedCount;
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
    final storedCards =
        await (database.select(database.localNationalFocusCards)
              ..where((card) => card.userId.equals(userId))
              ..orderBy([
                (card) => OrderingTerm.asc(card.createdAt),
                (card) => OrderingTerm.asc(card.id),
              ]))
            .get();
    final cards = storedCards
        .where((card) => card.isInTree || card.maintenanceCycleStarted)
        .toList(growable: false);
    if (cards.isEmpty) return;

    final plannedFailures = _planIndependentFailures(cards);
    final failureSourceCardIds = _failureSourceCardIds(cards, plannedFailures);
    final snapshotJson = jsonEncode(
      cards
          .map(
            (card) => _snapshotJson(
              card,
              failureSourceCardId: failureSourceCardIds[card.id],
            ),
          )
          .toList(growable: false),
    );
    final missedConfirmationBatchId =
        plannedFailures.values.any(
          (failure) =>
              failure.cause == NationalFocusFailureCause.missedConfirmation,
        )
        ? _uuid.v4()
        : null;

    for (final card in cards) {
      final plannedFailure = plannedFailures[card.id];
      if (plannedFailure == null) continue;
      await _recordFailure(
        card: card,
        checkpoint: checkpoint,
        cause: plannedFailure.cause,
        failureReason: plannedFailure.failureReason,
        batchId:
            plannedFailure.cause == NationalFocusFailureCause.missedConfirmation
            ? missedConfirmationBatchId!
            : _uuid.v4(),
        snapshotJson: snapshotJson,
      );
    }

    for (final card in cards) {
      final failureSourceId = failureSourceCardIds[card.id];
      final state = NationalFocusCardState.fromStorage(card.state);
      if (failureSourceId != null ||
          state == NationalFocusCardState.extinguished) {
        if (state == NationalFocusCardState.extinguished &&
            !card.maintenanceCycleStarted &&
            card.cascadeSourceCardId == null) {
          continue;
        }
        await _updateCard(
          card,
          LocalNationalFocusCardsCompanion(
            state: Value(NationalFocusCardState.extinguished.storageValue),
            currentConsecutiveDays: const Value(0),
            maintenanceCycleStarted: const Value(false),
            failureReason: const Value(null),
            cascadeSourceCardId: const Value(null),
            cascadePriorState: const Value(null),
            updatedAt: Value(checkpoint),
          ),
        );
      } else if (state == NationalFocusCardState.lit) {
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
            failureReason: const Value(null),
            cascadeSourceCardId: const Value(null),
            cascadePriorState: const Value(null),
            updatedAt: Value(checkpoint),
          ),
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

  Future<List<NationalFocusCard>> _getCards({
    required bool inTree,
    required bool deleted,
  }) async {
    await settleDueCheckpoints();
    final query = database.select(database.localNationalFocusCards)
      ..where((card) => card.userId.equals(userId))
      ..where((card) => card.isInTree.equals(inTree))
      ..where(
        (card) =>
            deleted ? card.deletedAt.isNotNull() : card.deletedAt.isNull(),
      )
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

  List<LocalNationalFocusCard> _descendantsOf(
    String parentId,
    List<LocalNationalFocusCard> cards,
  ) {
    final childrenByParent = <String, List<LocalNationalFocusCard>>{};
    for (final card in cards) {
      final cardParentId = card.parentId;
      if (cardParentId != null) {
        childrenByParent.putIfAbsent(cardParentId, () => []).add(card);
      }
    }

    final descendants = <LocalNationalFocusCard>[];
    final pending = <String>[parentId];
    final visited = <String>{parentId};
    while (pending.isNotEmpty) {
      final nextParentId = pending.removeLast();
      for (final child in childrenByParent[nextParentId] ?? const []) {
        if (!visited.add(child.id)) continue;
        descendants.add(child);
        pending.add(child.id);
      }
    }
    return descendants;
  }

  bool _hasExtinguishedAncestor(
    LocalNationalFocusCard card,
    Map<String, LocalNationalFocusCard> cardsById,
  ) {
    var ancestorId = card.parentId;
    final visited = <String>{card.id};
    while (ancestorId != null && visited.add(ancestorId)) {
      final ancestor = cardsById[ancestorId];
      if (ancestor == null || !ancestor.isInTree) return true;
      if (ancestor.state == NationalFocusCardState.extinguished.storageValue) {
        return true;
      }
      ancestorId = ancestor.parentId;
    }
    return false;
  }

  Map<String, _PlannedNationalFocusFailure> _planIndependentFailures(
    List<LocalNationalFocusCard> cards,
  ) {
    final planned = <String, _PlannedNationalFocusFailure>{};
    for (final card in cards) {
      final state = NationalFocusCardState.fromStorage(card.state);
      if (state == NationalFocusCardState.pendingTodayConfirmation) {
        planned[card.id] = _PlannedNationalFocusFailure(
          NationalFocusFailureCause.missedConfirmation,
          NationalFocusFailureCause.missedConfirmation.label,
        );
      } else if (state == NationalFocusCardState.extinguished &&
          card.maintenanceCycleStarted) {
        final priorState = card.cascadePriorState == null
            ? null
            : NationalFocusCardState.fromStorage(card.cascadePriorState!);
        if (card.cascadeSourceCardId == null) {
          planned[card.id] = _PlannedNationalFocusFailure(
            NationalFocusFailureCause.activeExtinguish,
            card.failureReason,
          );
        } else if (priorState ==
            NationalFocusCardState.pendingTodayConfirmation) {
          // A parent's manual failure does not erase the child's own missed
          // confirmation obligation.
          planned[card.id] = _PlannedNationalFocusFailure(
            NationalFocusFailureCause.missedConfirmation,
            NationalFocusFailureCause.missedConfirmation.label,
          );
        }
      }
    }

    final cardsById = {for (final card in cards) card.id: card};
    final orphanedCascades =
        cards
            .where(
              (card) =>
                  card.cascadeSourceCardId != null &&
                  card.maintenanceCycleStarted &&
                  !planned.containsKey(card.id),
            )
            .toList(growable: false)
          ..sort(
            (first, second) => _treeDepth(
              first,
              cardsById,
            ).compareTo(_treeDepth(second, cardsById)),
          );
    for (final card in orphanedCascades) {
      if (_nearestFailingAncestorId(card, cardsById, planned) != null) {
        continue;
      }
      // If the original parent was restored but this node stayed extinguished,
      // the remaining unlit branch now has its own pending failure source.
      planned[card.id] = _PlannedNationalFocusFailure(
        NationalFocusFailureCause.activeExtinguish,
        card.failureReason,
      );
    }
    return planned;
  }

  Map<String, String> _failureSourceCardIds(
    List<LocalNationalFocusCard> cards,
    Map<String, _PlannedNationalFocusFailure> plannedFailures,
  ) {
    final cardsById = {for (final card in cards) card.id: card};
    final sources = <String, String>{};
    for (final card in cards) {
      if (plannedFailures.containsKey(card.id)) {
        sources[card.id] = card.id;
        continue;
      }
      final ancestorId = _nearestFailingAncestorId(
        card,
        cardsById,
        plannedFailures,
      );
      if (ancestorId != null) sources[card.id] = ancestorId;
    }
    return sources;
  }

  String? _nearestFailingAncestorId(
    LocalNationalFocusCard card,
    Map<String, LocalNationalFocusCard> cardsById,
    Map<String, _PlannedNationalFocusFailure> plannedFailures,
  ) {
    var ancestorId = card.parentId;
    final visited = <String>{card.id};
    while (ancestorId != null && visited.add(ancestorId)) {
      if (plannedFailures.containsKey(ancestorId)) return ancestorId;
      ancestorId = cardsById[ancestorId]?.parentId;
    }
    return null;
  }

  int _treeDepth(
    LocalNationalFocusCard card,
    Map<String, LocalNationalFocusCard> cardsById,
  ) {
    var depth = 0;
    var ancestorId = card.parentId;
    final visited = <String>{card.id};
    while (ancestorId != null && visited.add(ancestorId)) {
      final ancestor = cardsById[ancestorId];
      if (ancestor == null) break;
      depth++;
      ancestorId = ancestor.parentId;
    }
    return depth;
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
        cascadeSourceCardId: row.cascadeSourceCardId,
        cascadePriorState: row.cascadePriorState == null
            ? null
            : NationalFocusCardState.fromStorage(row.cascadePriorState!),
        deletedAt: row.deletedAt,
      );

  Map<String, Object?> _snapshotJson(
    LocalNationalFocusCard row, {
    String? failureSourceCardId,
  }) => {
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
    'cascadeSourceCardId': row.cascadeSourceCardId,
    'cascadePriorState': row.cascadePriorState,
    'failureSourceCardId': failureSourceCardId,
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
            cascadeSourceCardId: item['cascadeSourceCardId'] as String?,
            cascadePriorState: item['cascadePriorState'] == null
                ? null
                : NationalFocusCardState.fromStorage(
                    item['cascadePriorState'] as String,
                  ),
            failureSourceCardId: item['failureSourceCardId'] as String?,
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

class _PlannedNationalFocusFailure {
  const _PlannedNationalFocusFailure(this.cause, this.failureReason);

  final NationalFocusFailureCause cause;
  final String? failureReason;
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
  Stream<List<NationalFocusCard>> watchDeletedCards() =>
      Stream.value(const <NationalFocusCard>[]);

  @override
  Future<List<NationalFocusCard>> getTreeCards() async => const [];

  @override
  Future<List<NationalFocusCard>> getLibraryCards() async => const [];

  @override
  Future<List<NationalFocusCard>> getDeletedCards() async => const [];

  @override
  Future<NationalFocusCard> getCard(String cardId) => _unavailable();

  @override
  Future<NationalFocusCard> createCard(NationalFocusCardDraft draft) =>
      _unavailable();

  @override
  Future<void> placeCard({required String cardId, required String? parentId}) =>
      _unavailable();

  @override
  Future<void> moveCardToLibrary(String cardId) => _unavailable();

  @override
  Future<NationalFocusCardDeletion> deleteCard(String cardId) => _unavailable();

  @override
  Future<void> restoreDeletedCard(String cardId) => _unavailable();

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
