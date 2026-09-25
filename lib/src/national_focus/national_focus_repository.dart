import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  Future<NationalFocusStrengtheningLevel> saveStrengtheningLevel({
    required String cardId,
    int? levelNumber,
    required NationalFocusStrengtheningLevelDraft draft,
  });
  Future<void> selectStrengtheningLevel({
    required String cardId,
    required int? levelNumber,
  });
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
  Stream<NationalFocusReviewState> watchNationalFocusReviewState();
  Future<NationalFocusReviewState> getNationalFocusReviewState();
  Future<void> deferNationalFocusReconciliation(String caseId);
  Future<void> resolveNationalFocusReconciliation({
    required String caseId,
    required String selectedSourceId,
  });
  Future<void> deferNationalFocusClockReview(String caseId);
  Future<void> resolveNationalFocusClockReview(String caseId);
  Future<void> sync();
  Future<void> dispose();
}

abstract interface class NationalFocusRemoteDataSource {
  Future<List<NationalFocusSyncSource>> pull({required String userId});
  Future<void> upsertSources({
    required String userId,
    required List<NationalFocusSyncSource> sources,
  });
}

class InMemoryNationalFocusRemoteDataSource
    implements NationalFocusRemoteDataSource {
  final Map<String, Map<String, NationalFocusSyncSource>> _sourcesByUser = {};

  @override
  Future<List<NationalFocusSyncSource>> pull({required String userId}) async =>
      List.unmodifiable(_sourcesByUser[userId]?.values ?? const []);

  @override
  Future<void> upsertSources({
    required String userId,
    required List<NationalFocusSyncSource> sources,
  }) async {
    final byId = _sourcesByUser.putIfAbsent(userId, () => {});
    for (final source in sources) {
      byId.putIfAbsent(source.sourceId, () => source);
    }
  }
}

class SupabaseNationalFocusRemoteDataSource
    implements NationalFocusRemoteDataSource {
  SupabaseNationalFocusRemoteDataSource(this.client);

  final SupabaseClient client;

  @override
  Future<List<NationalFocusSyncSource>> pull({required String userId}) async {
    const pageSize = 500;
    final sources = <NationalFocusSyncSource>[];
    for (var offset = 0; ; offset += pageSize) {
      final page = await client
          .from('focus_sync_sources')
          .select()
          .eq('user_id', userId)
          .eq('entity_type', 'national_focus_tree')
          .eq('entity_id', _nationalFocusTreeEntityId)
          .order('occurred_at')
          .order('source_id')
          .range(offset, offset + pageSize - 1);
      sources.addAll(page.map(_nationalFocusSourceFromJson));
      if (page.length < pageSize) break;
    }
    return sources;
  }

  @override
  Future<void> upsertSources({
    required String userId,
    required List<NationalFocusSyncSource> sources,
  }) async {
    for (var offset = 0; offset < sources.length; offset += 200) {
      final chunk = sources.skip(offset).take(200);
      await client
          .from('focus_sync_sources')
          .upsert(
            [
              for (final source in chunk)
                _nationalFocusSourceToJson(source, userId: userId),
            ],
            onConflict: 'source_id',
            ignoreDuplicates: true,
          );
    }
  }
}

class UnavailableNationalFocusRemoteDataSource
    implements NationalFocusRemoteDataSource {
  const UnavailableNationalFocusRemoteDataSource();

  @override
  Future<List<NationalFocusSyncSource>> pull({required String userId}) async =>
      const [];

  @override
  Future<void> upsertSources({
    required String userId,
    required List<NationalFocusSyncSource> sources,
  }) async {}
}

const _nationalFocusTreeEntityId = '00000000-0000-4000-8000-000000000018';

class _NationalFocusClockSample {
  const _NationalFocusClockSample({
    required this.wallTime,
    required this.monotonicTime,
  });

  final DateTime wallTime;
  final Duration monotonicTime;
}

class LocalNationalFocusRepository implements NationalFocusRepository {
  LocalNationalFocusRepository({
    required this.database,
    required this.userId,
    this.remote = const UnavailableNationalFocusRemoteDataSource(),
    DateTime Function()? now,
    Duration Function()? monotonicNow,
  }) : _now = now ?? DateTime.now,
       _injectedMonotonicNow = monotonicNow,
       _clockJumpDetectionEnabled = now == null || monotonicNow != null {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', '用户标识不能为空。');
    }
  }

  final PactaDatabase database;
  final String userId;
  final NationalFocusRemoteDataSource remote;
  final DateTime Function() _now;
  final Duration Function()? _injectedMonotonicNow;
  final bool _clockJumpDetectionEnabled;
  final Stopwatch _monotonicStopwatch = Stopwatch()..start();
  final _uuid = const Uuid();
  Future<void> _syncQueue = Future<void>.value();
  _NationalFocusClockSample? _lastClockSample;
  Duration? _trustedClockOffset;
  bool _clockOffsetRestored = false;
  String? _pendingClockReviewId;
  Duration? _pendingClockReviewMonotonicTime;

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
    yield* query.watch().asyncMap(_cardsFromRows);
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
    final id = _uuid.v4();
    final triggerCondition = _requiredText(draft.triggerCondition, '主要触发条件');
    final action = _requiredText(draft.action, '行动');
    final scope = _optionalText(draft.scope);
    final exceptionNotes = _optionalText(draft.exceptionNotes);
    final initialVersion = NationalFocusRequirementVersion(
      versionNumber: 1,
      strengtheningLevelNumber: null,
      effectiveTriggerCondition: triggerCondition,
      effectiveAction: action,
      scope: scope,
      exceptionNotes: exceptionNotes,
      effectiveFrom: timestamp,
    );
    final card = NationalFocusCard(
      id: id,
      triggerCondition: triggerCondition,
      action: action,
      scope: scope,
      exceptionNotes: exceptionNotes,
      isInTree: false,
      state: NationalFocusCardState.extinguished,
      createdAt: timestamp,
      updatedAt: timestamp,
      requirementVersions: [initialVersion],
    );
    await database.transaction(() async {
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
      await database
          .into(database.localNationalFocusRequirementVersions)
          .insert(
            LocalNationalFocusRequirementVersionsCompanion.insert(
              userId: userId,
              id: _uuid.v4(),
              cardId: card.id,
              versionNumber: 1,
              strengtheningLevelNumber: const Value(null),
              effectiveTriggerCondition: triggerCondition,
              effectiveAction: action,
              scope: Value(scope),
              exceptionNotes: Value(exceptionNotes),
              effectiveFrom: timestamp,
            ),
          );
      await _recordSyncSnapshot(operation: 'create_card');
    });
    return card;
  }

  @override
  Future<NationalFocusStrengtheningLevel> saveStrengtheningLevel({
    required String cardId,
    int? levelNumber,
    required NationalFocusStrengtheningLevelDraft draft,
  }) async {
    await settleDueCheckpoints();
    final triggerOverride = _optionalText(draft.triggerCondition);
    final actionOverride = _optionalText(draft.action);
    if (triggerOverride == null && actionOverride == null) {
      throw ArgumentError('至少填写一项强化要求；留空字段会沿用基础要求。');
    }

    final savedLevel = await database.transaction(() async {
      final card = await _findCardRow(cardId);
      _requireResolvedCard(card);
      if (card.deletedAt != null) {
        throw StateError('已删除的国策卡需要先恢复到卡片库。');
      }
      final storedLevels =
          await (database.select(database.localNationalFocusStrengtheningLevels)
                ..where(
                  (level) =>
                      level.userId.equals(userId) & level.cardId.equals(cardId),
                )
                ..orderBy([(level) => OrderingTerm.asc(level.levelNumber)]))
              .get();

      final isCreating = levelNumber == null;
      final targetLevelNumber =
          levelNumber ??
          (storedLevels.isEmpty ? 1 : storedLevels.last.levelNumber + 1);
      if (targetLevelNumber < 1 ||
          targetLevelNumber > maxNationalFocusStrengtheningLevels) {
        throw ArgumentError(
          '强化等级只能在 1 到 $maxNationalFocusStrengtheningLevels 之间。',
        );
      }
      LocalNationalFocusStrengtheningLevel? existing;
      for (final level in storedLevels) {
        if (level.levelNumber == targetLevelNumber) {
          existing = level;
          break;
        }
      }
      if (isCreating) {
        if (storedLevels.length >= maxNationalFocusStrengtheningLevels) {
          throw StateError(
            '一张国策卡最多建立 $maxNationalFocusStrengtheningLevels 个强化等级。',
          );
        }
        if (existing != null) {
          throw StateError('强化等级编号已存在。');
        }
      } else if (existing == null) {
        throw StateError('找不到要编辑的强化等级。');
      }

      if (existing != null &&
          existing.triggerConditionOverride == triggerOverride &&
          existing.actionOverride == actionOverride) {
        return NationalFocusStrengtheningLevel(
          levelNumber: targetLevelNumber,
          triggerCondition: triggerOverride,
          action: actionOverride,
        );
      }

      final timestamp = _nextTimestamp(card.updatedAt);
      if (existing == null) {
        await database
            .into(database.localNationalFocusStrengtheningLevels)
            .insert(
              LocalNationalFocusStrengtheningLevelsCompanion.insert(
                userId: userId,
                cardId: cardId,
                levelNumber: targetLevelNumber,
                triggerConditionOverride: Value(triggerOverride),
                actionOverride: Value(actionOverride),
                createdAt: timestamp,
                updatedAt: timestamp,
              ),
            );
      } else {
        await (database.update(database.localNationalFocusStrengtheningLevels)
              ..where(
                (level) =>
                    level.userId.equals(userId) &
                    level.cardId.equals(cardId) &
                    level.levelNumber.equals(targetLevelNumber),
              ))
            .write(
              LocalNationalFocusStrengtheningLevelsCompanion(
                triggerConditionOverride: Value(triggerOverride),
                actionOverride: Value(actionOverride),
                updatedAt: Value(timestamp),
              ),
            );
      }

      if (card.activeStrengtheningLevel == targetLevelNumber) {
        await _appendRequirementVersion(
          card: card,
          levelNumber: targetLevelNumber,
          triggerOverride: triggerOverride,
          actionOverride: actionOverride,
          effectiveFrom: timestamp,
        );
      }
      await _updateCard(
        card,
        LocalNationalFocusCardsCompanion(updatedAt: Value(timestamp)),
      );
      await _recordSyncSnapshot(operation: 'edit_strengthening_level');
      return NationalFocusStrengtheningLevel(
        levelNumber: targetLevelNumber,
        triggerCondition: triggerOverride,
        action: actionOverride,
      );
    });
    return savedLevel;
  }

  @override
  Future<void> selectStrengtheningLevel({
    required String cardId,
    required int? levelNumber,
  }) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      _requireResolvedCard(card);
      if (card.deletedAt != null) {
        throw StateError('已删除的国策卡需要先恢复到卡片库。');
      }
      if (levelNumber != null &&
          (levelNumber < 1 ||
              levelNumber > maxNationalFocusStrengtheningLevels)) {
        throw ArgumentError(
          '强化等级只能在 1 到 $maxNationalFocusStrengtheningLevels 之间。',
        );
      }
      if (card.activeStrengtheningLevel == levelNumber) return;

      LocalNationalFocusStrengtheningLevel? level;
      if (levelNumber != null) {
        level =
            await (database.select(
                  database.localNationalFocusStrengtheningLevels,
                )..where(
                  (candidate) =>
                      candidate.userId.equals(userId) &
                      candidate.cardId.equals(cardId) &
                      candidate.levelNumber.equals(levelNumber),
                ))
                .getSingleOrNull();
        if (level == null) throw StateError('找不到要采用的强化等级。');
      }

      final timestamp = _nextTimestamp(card.updatedAt);
      await _appendRequirementVersion(
        card: card,
        levelNumber: levelNumber,
        triggerOverride: level?.triggerConditionOverride,
        actionOverride: level?.actionOverride,
        effectiveFrom: timestamp,
      );
      await _updateCard(
        card,
        LocalNationalFocusCardsCompanion(
          activeStrengtheningLevel: Value(levelNumber),
          updatedAt: Value(timestamp),
        ),
      );
      await _recordSyncSnapshot(operation: 'select_strengthening_level');
    });
  }

  Future<void> _appendRequirementVersion({
    required LocalNationalFocusCard card,
    required int? levelNumber,
    required String? triggerOverride,
    required String? actionOverride,
    required DateTime effectiveFrom,
  }) async {
    var versions =
        await (database.select(database.localNationalFocusRequirementVersions)
              ..where(
                (version) =>
                    version.userId.equals(userId) &
                    version.cardId.equals(card.id),
              )
              ..orderBy([(version) => OrderingTerm.asc(version.versionNumber)]))
            .get();

    if (versions.isEmpty) {
      String? previousTriggerOverride;
      String? previousActionOverride;
      final selected = card.activeStrengtheningLevel;
      if (selected != null) {
        final previousLevel =
            await (database.select(
                  database.localNationalFocusStrengtheningLevels,
                )..where(
                  (level) =>
                      level.userId.equals(userId) &
                      level.cardId.equals(card.id) &
                      level.levelNumber.equals(selected),
                ))
                .getSingleOrNull();
        previousTriggerOverride = previousLevel?.triggerConditionOverride;
        previousActionOverride = previousLevel?.actionOverride;
      }
      await database
          .into(database.localNationalFocusRequirementVersions)
          .insert(
            LocalNationalFocusRequirementVersionsCompanion.insert(
              userId: userId,
              id: _uuid.v4(),
              cardId: card.id,
              versionNumber: 1,
              strengtheningLevelNumber: Value(selected),
              effectiveTriggerCondition:
                  previousTriggerOverride ?? card.triggerCondition,
              effectiveAction: previousActionOverride ?? card.action,
              scope: Value(card.scope),
              exceptionNotes: Value(card.exceptionNotes),
              effectiveFrom: card.createdAt,
            ),
          );
      versions =
          await (database.select(database.localNationalFocusRequirementVersions)
                ..where(
                  (version) =>
                      version.userId.equals(userId) &
                      version.cardId.equals(card.id),
                )
                ..orderBy([
                  (version) => OrderingTerm.asc(version.versionNumber),
                ]))
              .get();
    }

    final openVersion =
        await (database.select(database.localNationalFocusRequirementVersions)
              ..where(
                (version) =>
                    version.userId.equals(userId) &
                    version.cardId.equals(card.id) &
                    version.effectiveUntil.isNull(),
              ))
            .getSingleOrNull();
    if (openVersion != null) {
      await (database.update(database.localNationalFocusRequirementVersions)
            ..where(
              (version) =>
                  version.userId.equals(userId) &
                  version.id.equals(openVersion.id),
            ))
          .write(
            LocalNationalFocusRequirementVersionsCompanion(
              effectiveUntil: Value(effectiveFrom),
            ),
          );
    }

    await database
        .into(database.localNationalFocusRequirementVersions)
        .insert(
          LocalNationalFocusRequirementVersionsCompanion.insert(
            userId: userId,
            id: _uuid.v4(),
            cardId: card.id,
            versionNumber: versions.last.versionNumber + 1,
            strengtheningLevelNumber: Value(levelNumber),
            effectiveTriggerCondition: triggerOverride ?? card.triggerCondition,
            effectiveAction: actionOverride ?? card.action,
            scope: Value(card.scope),
            exceptionNotes: Value(card.exceptionNotes),
            effectiveFrom: effectiveFrom,
          ),
        );
  }

  @override
  Future<void> placeCard({
    required String cardId,
    required String? parentId,
  }) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      _requireResolvedCard(card);
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
      await _recordSyncSnapshot(operation: 'place_card');
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
        return;
      }
      final treeCards =
          await (database.select(database.localNationalFocusCards)
                ..where((candidate) => candidate.userId.equals(userId))
                ..where((candidate) => candidate.isInTree.equals(true)))
              .get();
      final branch = [card, ..._descendantsOf(card.id, treeCards)];
      if (branch.any(
        (branchCard) => branchCard.reviewDisposition == 'pending_review',
      )) {
        throw StateError('同步分歧待核对；请先核对这条分支。');
      }
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
      await _recordSyncSnapshot(operation: 'move_card_to_library');
    });
  }

  @override
  Future<NationalFocusCardDeletion> deleteCard(String cardId) async {
    await settleDueCheckpoints();
    final deletion = await database.transaction(() async {
      final card =
          await (database.select(database.localNationalFocusCards)
                ..where((candidate) => candidate.userId.equals(userId))
                ..where((candidate) => candidate.id.equals(cardId)))
              .getSingleOrNull();
      if (card == null) {
        return NationalFocusCardDeletion.permanentlyDeleted;
      }
      if (card.deletedAt != null) {
        return NationalFocusCardDeletion.softDeleted;
      }
      _requireResolvedCard(card);
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
        await (database.delete(database.localNationalFocusStrengtheningLevels)
              ..where(
                (level) =>
                    level.userId.equals(userId) & level.cardId.equals(cardId),
              ))
            .go();
        await (database.delete(
              database.localNationalFocusRequirementVersions,
            )..where(
              (version) =>
                  version.userId.equals(userId) & version.cardId.equals(cardId),
            ))
            .go();
        await (database.delete(database.localNationalFocusCards)
              ..where((candidate) => candidate.userId.equals(userId))
              ..where((candidate) => candidate.id.equals(cardId)))
            .go();
        await _recordSyncSnapshot(
          operation: 'permanently_delete_card',
          deletedCardIds: {cardId},
        );
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
      await _recordSyncSnapshot(operation: 'soft_delete_card');
      return NationalFocusCardDeletion.softDeleted;
    });
    return deletion;
  }

  @override
  Future<void> restoreDeletedCard(String cardId) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      _requireResolvedCard(card);
      if (card.deletedAt == null && !card.isInTree) return;
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
      await _recordSyncSnapshot(operation: 'restore_deleted_card');
    });
  }

  @override
  Future<void> lightCard(String cardId) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      _requireResolvedCard(card);
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
      await _recordSyncSnapshot(operation: 'light_card');
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
      _requireResolvedCard(card);
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
      if (descendants.any(
        (descendant) => descendant.reviewDisposition == 'pending_review',
      )) {
        throw StateError('同步分歧待核对；请先核对这条分支。');
      }
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
      await _recordSyncSnapshot(operation: 'extinguish_card');
    });
  }

  @override
  Future<int> confirmToday() async {
    await settleDueCheckpoints();
    final confirmedCardIds = <String>[];
    final confirmedCount = await database.transaction(() async {
      final pendingCards =
          await (database.select(database.localNationalFocusCards)
                ..where((card) => card.userId.equals(userId))
                ..where((card) => card.isInTree.equals(true))
                ..where((card) => card.reviewDisposition.equals('accepted'))
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

      var count = 0;
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
        confirmedCardIds.add(card.id);
        count++;
      }
      if (confirmedCardIds.isNotEmpty) {
        await _recordSyncSnapshot(
          operation: 'confirm_today',
          checkpointAt: nextNationalFocusCheckpoint(_trustedNow()),
          confirmedCardIds: confirmedCardIds,
        );
      }
      return count;
    });
    return confirmedCount;
  }

  @override
  Future<void> settleDueCheckpoints() async {
    await _restoreTrustedClockOffset();
    final sample = _sampleNationalFocusClock();
    final previous = _lastClockSample;
    final elapsed = previous == null
        ? Duration.zero
        : sample.monotonicTime - previous.monotonicTime;
    final wallDelta = previous == null
        ? Duration.zero
        : sample.wallTime.difference(previous.wallTime);
    final discrepancyMicros = wallDelta.inMicroseconds - elapsed.inMicroseconds;
    final hasClockJump =
        _clockJumpDetectionEnabled &&
        previous != null &&
        discrepancyMicros.abs() > const Duration(seconds: 30).inMicroseconds;
    final reliableNow = hasClockJump
        ? previous.wallTime.add(
            Duration(
              microseconds: elapsed.inMicroseconds.clamp(0, 1 << 62).toInt(),
            ),
          )
        : sample.wallTime;
    _lastClockSample = _NationalFocusClockSample(
      wallTime: reliableNow,
      monotonicTime: sample.monotonicTime,
    );
    if (hasClockJump) {
      _trustedClockOffset = _now().toUtc().difference(reliableNow);
      _pendingClockReviewMonotonicTime = sample.monotonicTime;
    }
    await database.transaction(() async {
      final sources = await _getNationalFocusSyncSources();
      final heads = _nationalFocusSourceHeads(sources);
      final metadata = _nationalFocusReviewMetadataFromSources(
        sources,
        heads.map((source) => source.sourceId),
      );
      final pendingClockCases = _mapList(
        metadata['nationalFocusClockReviewCases'],
      );
      if (pendingClockCases.isNotEmpty && !hasClockJump) return;

      await _settleCheckpointsThrough(reliableNow);
      if (hasClockJump) {
        final previousSample = previous;
        final activeCards = await (database.select(
          database.localNationalFocusCards,
        )..where((card) => card.userId.equals(userId))).get();
        final affectedCardIds = <String>[];
        for (final card in activeCards) {
          if (!card.isInTree && !card.maintenanceCycleStarted) continue;
          affectedCardIds.add(card.id);
          if (card.reviewDisposition == 'pending_review') continue;
          await _updateCard(
            card,
            const LocalNationalFocusCardsCompanion(
              reviewDisposition: Value('pending_review'),
            ),
          );
        }
        final rawWallTime = _now().toUtc();
        final clockReviewId = _uuid.v4();
        final deviceId = await _getNationalFocusDeviceId();
        _pendingClockReviewId = clockReviewId;
        final clockReview = {
          'id': clockReviewId,
          'deviceId': deviceId,
          'direction': discrepancyMicros > 0 ? 'forward' : 'backward',
          'detectedAt': rawWallTime.toIso8601String(),
          'previousWallTime': previousSample.wallTime.toIso8601String(),
          'observedWallTime': rawWallTime.toIso8601String(),
          'reliableThroughTime': reliableNow.toIso8601String(),
          'estimatedElapsedSeconds': elapsed.inSeconds.clamp(0, 1 << 31),
          'clockOffsetsByDevice': {
            deviceId: _trustedClockOffset!.inMilliseconds,
          },
          'cardIds': affectedCardIds..sort(),
          'isDeferred': false,
        };
        final clockCases = [...pendingClockCases, clockReview];
        await _recordSyncSnapshot(
          operation: 'national_focus_clock_anomaly',
          metadata: {...metadata, 'nationalFocusClockReviewCases': clockCases},
        );
      }
    });
  }

  Future<void> _settleCheckpointsThrough(DateTime now) async {
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
      await _recordSyncSnapshot(operation: 'initialize_checkpoints');
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
      final checkpointFailures = await (database.select(
        database.localNationalFocusFailures,
      )..where((failure) => failure.userId.equals(userId))).get();
      await _recordSyncSnapshot(
        operation: 'settle_checkpoint',
        checkpointAt: checkpoint,
        missedConfirmationCardIds: [
          for (final failure in checkpointFailures)
            if (failure.checkpointAt.isAtSameMomentAs(checkpoint) &&
                failure.cause ==
                    NationalFocusFailureCause.missedConfirmation.storageValue)
              failure.cardId,
        ],
      );
      checkpoint = checkpoint.add(nationalFocusCheckpointPeriod);
    }
  }

  _NationalFocusClockSample _sampleNationalFocusClock() =>
      _NationalFocusClockSample(
        wallTime: _trustedNow(),
        monotonicTime:
            _injectedMonotonicNow?.call() ?? _monotonicStopwatch.elapsed,
      );

  DateTime _trustedNow() {
    final now = _now().toUtc();
    final offset = _trustedClockOffset;
    return offset == null ? now : now.subtract(offset);
  }

  Future<void> _restoreTrustedClockOffset() async {
    if (_clockOffsetRestored) return;
    _clockOffsetRestored = true;
    final deviceId = await _getNationalFocusDeviceId();
    final sources = await _getNationalFocusSyncSources();
    for (final source in sources.reversed) {
      final payload = _nationalFocusPayload(source);
      for (final collection in [
        'nationalFocusClockReviewHistory',
        'nationalFocusClockReviewCases',
      ]) {
        for (final item in _mapList(payload[collection]).reversed) {
          final offsets = item['clockOffsetsByDevice'];
          final offset = offsets is Map
              ? offsets[deviceId]
              : item['deviceId'] == deviceId
              ? item['clockOffsetMilliseconds']
              : null;
          if (offset is! int) continue;
          _trustedClockOffset = Duration(milliseconds: offset);
          return;
        }
      }
    }
  }

  Future<void> _settleCheckpoint(
    DateTime checkpoint, {
    Set<String>? onlyCardIds,
  }) async {
    final storedCards =
        await (database.select(database.localNationalFocusCards)
              ..where((card) => card.userId.equals(userId))
              ..orderBy([
                (card) => OrderingTerm.asc(card.createdAt),
                (card) => OrderingTerm.asc(card.id),
              ]))
            .get();
    final settlementCards = storedCards
        .where(
          (card) =>
              card.reviewDisposition != 'pending_review' &&
              (card.isInTree || card.maintenanceCycleStarted),
        )
        .toList(growable: false);
    final cards = onlyCardIds == null
        ? settlementCards
        : settlementCards
              .where((card) => onlyCardIds.contains(card.id))
              .toList(growable: false);
    if (cards.isEmpty) return;

    final plannedFailures = _planIndependentFailures(settlementCards);
    final failureSourceCardIds = _failureSourceCardIds(
      settlementCards,
      plannedFailures,
    );
    final snapshotCards = await Future.wait(
      settlementCards.map(
        (card) => _snapshotJson(
          card,
          failureSourceCardId: failureSourceCardIds[card.id],
        ),
      ),
    );
    final snapshotJson = jsonEncode(snapshotCards);
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
    await database.transaction(() async {
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
      await _recordSyncSnapshot(operation: 'edit_failure_explanation');
    });
  }

  @override
  Stream<NationalFocusReviewState> watchNationalFocusReviewState() =>
      (database.select(database.focusSyncSources)
            ..where((row) => row.userId.equals(userId))
            ..where((row) => row.entityType.equals('national_focus_tree'))
            ..where((row) => row.entityId.equals(_nationalFocusTreeEntityId)))
          .watch()
          .asyncMap((_) => getNationalFocusReviewState());

  @override
  Future<NationalFocusReviewState> getNationalFocusReviewState() async {
    final sources = await _getNationalFocusSyncSources();
    if (sources.isEmpty) return const NationalFocusReviewState();
    final heads = _nationalFocusSourceHeads(sources);
    final pendingPayloads = <Map<String, dynamic>>[];
    if (heads.length > 1) {
      final merged = _mergeNationalFocusSnapshots(sources, heads);
      pendingPayloads.add(merged);
    } else {
      pendingPayloads.addAll(heads.map(_nationalFocusPayload));
    }
    return _nationalFocusReviewStateFromSources(
      pendingPayloads: pendingPayloads,
      sources: sources,
    );
  }

  @override
  Future<void> deferNationalFocusReconciliation(String caseId) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final sources = await _getNationalFocusSyncSources();
      final heads = _nationalFocusSourceHeads(sources);
      final metadata = _nationalFocusReviewMetadataFromSources(
        sources,
        heads.map((source) => source.sourceId),
      );
      final cases = _mapList(metadata['nationalFocusReconciliationCases']);
      final index = cases.indexWhere((item) => item['id'] == caseId);
      if (index < 0) {
        throw StateError('找不到这组待核对的国策操作。');
      }
      if (cases[index]['isDeferred'] == true) return;
      cases[index] = {...cases[index], 'isDeferred': true};
      await _recordSyncSnapshot(
        operation: 'defer_national_focus_reconciliation',
        metadata: {...metadata, 'nationalFocusReconciliationCases': cases},
      );
    });
  }

  @override
  Future<void> resolveNationalFocusReconciliation({
    required String caseId,
    required String selectedSourceId,
  }) async {
    await settleDueCheckpoints();
    await database.transaction(() async {
      final sources = await _getNationalFocusSyncSources();
      final heads = _nationalFocusSourceHeads(sources);
      final metadata = _nationalFocusReviewMetadataFromSources(
        sources,
        heads.map((source) => source.sourceId),
      );
      final cases = _mapList(metadata['nationalFocusReconciliationCases']);
      final reviewIndex = cases.indexWhere((item) => item['id'] == caseId);
      if (reviewIndex < 0) {
        if (_mapList(metadata['nationalFocusReconciliationHistory'])
            .any((item) => item['caseId'] == caseId)) {
          return;
        }
        throw StateError('找不到这组待核对的国策操作。');
      }
      final review = cases[reviewIndex];
      final optionIds = _mapList(review['options'])
          .map((option) => option['sourceId'])
          .whereType<String>()
          .toSet();
      if (!optionIds.contains(selectedSourceId)) {
        throw StateError('请选择核对记录中展示的完整操作分支。');
      }
      final sourcesById = {
        for (final source in sources) source.sourceId: source,
      };
      final selectedSource = sourcesById[selectedSourceId];
      if (selectedSource == null) {
        throw StateError('选定的原始操作来源已不可用。');
      }
      final selectedSnapshot = _nationalFocusPayload(selectedSource);
      final selectedCards = _nationalFocusCardsById(selectedSnapshot);
      final affectedCardIds = (review['cardIds'] as List<dynamic>)
          .whereType<String>()
          .toSet();
      final unresolvedConflictCardIds = cases
          .where((item) => item['id'] != caseId)
          .expand(
            (item) => (item['cardIds'] as List<dynamic>).whereType<String>(),
          )
          .toSet();
      final unresolvedClockCardIds =
          _mapList(metadata['nationalFocusClockReviewCases'])
              .expand(
                (item) =>
                    (item['cardIds'] as List<dynamic>).whereType<String>(),
              )
              .toSet();
      final pendingReviewCardIds = {
        ...unresolvedConflictCardIds,
        ...unresolvedClockCardIds,
      };
      final snapshot = await _currentNationalFocusSnapshot();
      final cards = _nationalFocusCardsById(snapshot);
      for (final cardId in affectedCardIds) {
        final accepted = selectedCards[cardId];
        if (accepted == null) {
          cards.remove(cardId);
        } else {
          cards[cardId] = {
            ...accepted,
            'reviewDisposition': pendingReviewCardIds.contains(cardId)
                ? 'pending_review'
                : 'accepted',
          };
        }
      }
      final acceptedTombstones = selectedSnapshot['tombstones'];
      final tombstones = <String>{
        if (snapshot['tombstones'] is List)
          ...(snapshot['tombstones'] as List).whereType<String>(),
      };
      for (final cardId in affectedCardIds) {
        tombstones.remove(cardId);
        if (acceptedTombstones is List &&
            acceptedTombstones.whereType<String>().contains(cardId)) {
          tombstones.add(cardId);
        }
      }
      final resolvedCards = cards.values.toList()
        ..sort(
          (left, right) =>
              (left['id'] as String).compareTo(right['id'] as String),
        );
      if (!_isValidNationalFocusTree(resolvedCards)) {
        throw StateError('这个操作分支会形成无效国策树，请选择另一完整分支。');
      }
      snapshot['cards'] = resolvedCards;
      snapshot['tombstones'] = tombstones.toList()..sort();

      final selectedFailures = _mapList(selectedSnapshot['failures'])
          .where((failure) => affectedCardIds.contains(failure['cardId']))
          .toList();
      final failures = _mapList(snapshot['failures']);
      final existingExplanations = {
        for (final failure in failures)
          if (failure['id'] is String && failure['sharedExplanation'] != null)
            failure['id'] as String: failure['sharedExplanation'],
      };
      final failuresById = {
        for (final failure in failures)
          if (!affectedCardIds.contains(failure['cardId']))
            failure['id']: failure,
      };
      for (final failure in selectedFailures) {
        failuresById[failure['id']] = {
          ...failure,
          if (existingExplanations[failure['id']] != null)
            'sharedExplanation': existingExplanations[failure['id']],
          'reviewDisposition': pendingReviewCardIds.contains(failure['cardId'])
              ? 'pending_review'
              : 'accepted',
        };
      }
      snapshot['failures'] = failuresById.values.toList();

      final options = _mapList(review['options']);
      final acceptedOperationIds = <String>{selectedSourceId};
      final retainedOperationIds = <String>{};
      for (final option in options) {
        final operationIds = _mapList(option['operations'])
            .map((operation) => operation['sourceId'])
            .whereType<String>();
        retainedOperationIds.addAll(operationIds);
        if (option['sourceId'] == selectedSourceId) {
          acceptedOperationIds.addAll(operationIds);
        }
      }
      final replayCardIds = _nationalFocusCheckpointReplayCardIds(
        affectedCardIds,
        resolvedCards,
      );
      final replayFrom = _nationalFocusCheckpointFromSnapshot(selectedSnapshot);
      final replayThrough = _nationalFocusCheckpointFromSnapshot(snapshot);
      final needsCheckpointReplay =
          replayFrom != null &&
          replayThrough != null &&
          replayThrough.isAfter(replayFrom) &&
          replayCardIds.isNotEmpty;
      final result = {
        'caseId': caseId,
        'resolvedAt': _trustedNow().toIso8601String(),
        'cardIds': affectedCardIds.toList()..sort(),
        'acceptedSourceIds': acceptedOperationIds.toList()..sort(),
        'retainedSourceIds': retainedOperationIds.toList()..sort(),
        'selectedSourceId': selectedSourceId,
        'replayFromCheckpointAt': needsCheckpointReplay
            ? replayFrom.toIso8601String()
            : null,
        'replayThroughCheckpointAt': needsCheckpointReplay
            ? replayThrough.toIso8601String()
            : null,
        'replayCardIds': replayCardIds.toList()..sort(),
        'pendingCheckpointReplay': needsCheckpointReplay,
      };
      cases.removeAt(reviewIndex);
      final history = _mapList(metadata['nationalFocusReconciliationHistory']);
      if (!history.any((item) => item['caseId'] == caseId)) {
        history.add(result);
      }
      await _applyNationalFocusSnapshot(snapshot);
      await _recordSyncSnapshot(
        operation: 'resolve_national_focus_reconciliation',
        metadata: {
          ...metadata,
          'nationalFocusReconciliationCases': cases,
          'nationalFocusReconciliationHistory': history,
        },
      );
      await _replayDeferredNationalFocusCheckpointReconciliations();
    });
  }

  Future<void> _replayDeferredNationalFocusCheckpointReconciliations() async {
    final sources = await _getNationalFocusSyncSources();
    if (sources.isEmpty) return;
    final heads = _nationalFocusSourceHeads(sources);
    final metadata = _nationalFocusReviewMetadataFromSources(
      sources,
      heads.map((source) => source.sourceId),
    );
    final pendingReviewCardIds = <String>{
      for (final review in _mapList(
        metadata['nationalFocusReconciliationCases'],
      ))
        ...(review['cardIds'] as List<dynamic>).whereType<String>(),
      for (final review in _mapList(metadata['nationalFocusClockReviewCases']))
        ...(review['cardIds'] as List<dynamic>).whereType<String>(),
    };
    final history = _mapList(metadata['nationalFocusReconciliationHistory']);
    var replayedAny = false;

    for (var index = 0; index < history.length; index++) {
      final result = history[index];
      if (result['pendingCheckpointReplay'] != true) continue;
      final cardIds = (result['replayCardIds'] as List<dynamic>)
          .whereType<String>()
          .toSet();
      if (cardIds.any(pendingReviewCardIds.contains)) continue;

      final rawFrom = result['replayFromCheckpointAt'];
      final rawThrough = result['replayThroughCheckpointAt'];
      if (rawFrom is! String || rawThrough is! String) {
        throw StateError('缺少国策检查点重算所需的原始边界。');
      }
      var checkpoint = DateTime.parse(rawFrom)
          .toUtc()
          .add(nationalFocusCheckpointPeriod);
      final through = DateTime.parse(rawThrough).toUtc();
      while (!checkpoint.isAfter(through)) {
        await _settleCheckpoint(checkpoint, onlyCardIds: cardIds);
        await _recordSyncSnapshot(
          operation: 'replay_national_focus_checkpoint',
          checkpointAt: checkpoint,
        );
        checkpoint = checkpoint.add(nationalFocusCheckpointPeriod);
      }
      history[index] = {
        ...result,
        'pendingCheckpointReplay': false,
        'replayedThroughCheckpointAt': through.toIso8601String(),
      };
      replayedAny = true;
    }

    if (!replayedAny) return;
    await _recordSyncSnapshot(
      operation: 'complete_national_focus_checkpoint_replay',
      metadata: {...metadata, 'nationalFocusReconciliationHistory': history},
    );
  }

  @override
  Future<void> deferNationalFocusClockReview(String caseId) async {
    await database.transaction(() async {
      final sources = await _getNationalFocusSyncSources();
      final heads = _nationalFocusSourceHeads(sources);
      final metadata = _nationalFocusReviewMetadataFromSources(
        sources,
        heads.map((source) => source.sourceId),
      );
      final cases = _mapList(metadata['nationalFocusClockReviewCases']);
      final index = cases.indexWhere((item) => item['id'] == caseId);
      if (index < 0) {
        throw StateError('找不到待核对的国策时钟记录。');
      }
      if (cases[index]['isDeferred'] == true) return;
      cases[index] = {...cases[index], 'isDeferred': true};
      await _recordSyncSnapshot(
        operation: 'defer_national_focus_clock_review',
        metadata: {...metadata, 'nationalFocusClockReviewCases': cases},
      );
    });
  }

  @override
  Future<void> resolveNationalFocusClockReview(String caseId) async {
    await database.transaction(() async {
      final sources = await _getNationalFocusSyncSources();
      final heads = _nationalFocusSourceHeads(sources);
      final metadata = _nationalFocusReviewMetadataFromSources(
        sources,
        heads.map((source) => source.sourceId),
      );
      final cases = _mapList(metadata['nationalFocusClockReviewCases']);
      final index = cases.indexWhere((item) => item['id'] == caseId);
      if (index < 0) {
        if (_mapList(metadata['nationalFocusClockReviewHistory'])
            .any((item) => item['id'] == caseId)) {
          return;
        }
        throw StateError('找不到待核对的国策时钟记录。');
      }
      final review = cases.removeAt(index);
      var reliableThrough = DateTime.parse(
        review['reliableThroughTime'] as String,
      ).toUtc();
      final monotonicAtDetection = _pendingClockReviewId == caseId
          ? _pendingClockReviewMonotonicTime
          : null;
      if (monotonicAtDetection != null) {
        final currentMonotonic =
            _injectedMonotonicNow?.call() ?? _monotonicStopwatch.elapsed;
        final elapsed = currentMonotonic - monotonicAtDetection;
        reliableThrough = reliableThrough.add(
          Duration(
            microseconds: elapsed.inMicroseconds.clamp(0, 1 << 62).toInt(),
          ),
        );
      }
      final rawNow = _now().toUtc();
      _trustedClockOffset = rawNow.difference(reliableThrough);
      final cardIds = (review['cardIds'] as List<dynamic>)
          .whereType<String>()
          .toSet();
      final unresolvedConflictCardIds =
          _mapList(metadata['nationalFocusReconciliationCases'])
              .expand(
                (item) =>
                    (item['cardIds'] as List<dynamic>).whereType<String>(),
              )
              .toSet();
      final unresolvedClockCardIds = cases
          .expand(
            (item) => (item['cardIds'] as List<dynamic>).whereType<String>(),
          )
          .toSet();
      for (final cardId in cardIds) {
        final card = await _findCardRow(cardId);
        if (card.reviewDisposition != 'pending_review') continue;
        if (unresolvedConflictCardIds.contains(cardId) ||
            unresolvedClockCardIds.contains(cardId)) {
          continue;
        }
        await _updateCard(
          card,
          const LocalNationalFocusCardsCompanion(
            reviewDisposition: Value('accepted'),
          ),
        );
        await (database.update(database.localNationalFocusFailures)
              ..where((failure) => failure.userId.equals(userId))
              ..where((failure) => failure.cardId.equals(cardId))
              ..where(
                (failure) => failure.reviewDisposition.equals('pending_review'),
              ))
            .write(
              const LocalNationalFocusFailuresCompanion(
                reviewDisposition: Value('accepted'),
              ),
            );
      }
      final resolvedAt = _trustedNow();
      final history = _mapList(metadata['nationalFocusClockReviewHistory']);
      final deviceId = await _getNationalFocusDeviceId();
      final clockOffsets = Map<String, dynamic>.from(
        review['clockOffsetsByDevice'] is Map
            ? review['clockOffsetsByDevice'] as Map
            : const <String, dynamic>{},
      )..[deviceId] = _trustedClockOffset!.inMilliseconds;
      history.add({
        ...review,
        'clockOffsetsByDevice': clockOffsets,
        'reliableThroughTime': reliableThrough.toIso8601String(),
        'resolvedAt': resolvedAt.toIso8601String(),
        'resolution': 'accept_monotonic_estimate',
        'clockOffsetMilliseconds': _trustedClockOffset!.inMilliseconds,
      });
      _pendingClockReviewId = null;
      _pendingClockReviewMonotonicTime = null;
      _lastClockSample = _NationalFocusClockSample(
        wallTime: reliableThrough,
        monotonicTime:
            _injectedMonotonicNow?.call() ?? _monotonicStopwatch.elapsed,
      );
      await _recordSyncSnapshot(
        operation: 'resolve_national_focus_clock_review',
        metadata: {
          ...metadata,
          'nationalFocusClockReviewCases': cases,
          'nationalFocusClockReviewHistory': history,
        },
      );
      await _replayDeferredNationalFocusCheckpointReconciliations();
      await _settleCheckpointsThrough(reliableThrough);
    });
  }

  @override
  Future<void> sync() {
    final nextSync = _syncQueue
        .catchError((Object _) {})
        .then((_) => _syncOnce());
    _syncQueue = nextSync;
    return nextSync;
  }

  Future<void> _syncOnce() async {
    await settleDueCheckpoints();
    await _recordLocalStateRecoveryIfNeeded();
    final remoteSources = await remote.pull(userId: userId);
    for (final source in remoteSources) {
      await database
          .into(database.focusSyncSources)
          .insert(
            FocusSyncSourcesCompanion.insert(
              userId: userId,
              sourceId: source.sourceId,
              deviceId: source.deviceId,
              entityType: 'national_focus_tree',
              entityId: _nationalFocusTreeEntityId,
              parentSourceId: Value(
                source.parentSourceIds.isEmpty
                    ? null
                    : source.parentSourceIds.first,
              ),
              parentSourceIds: Value(jsonEncode(source.parentSourceIds)),
              occurredAt: source.occurredAt.toUtc(),
              payload: source.payload,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }

    final sources = await _getNationalFocusSyncSources();
    if (sources.isEmpty) return;
    final heads = _nationalFocusSourceHeads(sources);
    if (heads.isEmpty) return;
    final mergedSnapshot = _mergeNationalFocusSnapshots(sources, heads);
    await _applyNationalFocusSnapshot(mergedSnapshot);
    if (heads.length > 1) {
      await _recordSyncSnapshot(
        operation: 'synchronization_merge',
        parentSourceIds: [for (final head in heads) head.sourceId],
        metadata: _reviewMetadataFromSnapshot(mergedSnapshot),
      );
    }
    await remote.upsertSources(
      userId: userId,
      sources: await _getNationalFocusSyncSources(),
    );
  }

  Future<void> _recordLocalStateRecoveryIfNeeded() async {
    final sources = await _getNationalFocusSyncSources();
    final heads = _nationalFocusSourceHeads(sources);
    final localSnapshot = await _currentNationalFocusSnapshot();
    final tombstones = <String>{};
    for (final source in sources) {
      final values = _nationalFocusPayload(source)['tombstones'];
      if (values is List) tombstones.addAll(values.whereType<String>());
    }
    localSnapshot['tombstones'] = tombstones.toList()..sort();
    final localSignature = _nationalFocusStateSignature(localSnapshot);
    if (heads.any(
      (head) =>
          _nationalFocusStateSignature(_nationalFocusPayload(head)) ==
          localSignature,
    )) {
      return;
    }
    await _recordSyncSnapshot(
      operation: sources.isEmpty ? 'initial_snapshot' : 'local_state_recovery',
      parentSourceIds: [for (final head in heads) head.sourceId],
    );
  }

  Future<List<NationalFocusSyncSource>> _getNationalFocusSyncSources() async {
    final rows =
        await (database.select(database.focusSyncSources)
              ..where((row) => row.userId.equals(userId))
              ..where((row) => row.entityType.equals('national_focus_tree'))
              ..where((row) => row.entityId.equals(_nationalFocusTreeEntityId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAt),
                (row) => OrderingTerm.asc(row.sourceId),
              ]))
            .get();
    return [
      for (final row in rows)
        NationalFocusSyncSource(
          sourceId: row.sourceId,
          deviceId: row.deviceId,
          parentSourceIds: _decodeNationalFocusSourceParents(
            row.parentSourceId,
            row.parentSourceIds,
          ),
          occurredAt: row.occurredAt.toUtc(),
          payload: row.payload,
        ),
    ];
  }

  Map<String, dynamic> _nationalFocusReviewMetadataFromSources(
    List<NationalFocusSyncSource> sources,
    Iterable<String> parentSourceIds,
  ) {
    final parentIds = parentSourceIds.toSet();
    final reconciliationCases = <String, Map<String, dynamic>>{};
    final reconciliationHistory = <String, Map<String, dynamic>>{};
    final clockReviewCases = <String, Map<String, dynamic>>{};
    final clockReviewHistory = <String, Map<String, dynamic>>{};
    for (final source in sources) {
      if (!parentIds.contains(source.sourceId)) continue;
      final payload = _nationalFocusPayload(source);
      for (final item in _mapList(
        payload['nationalFocusReconciliationCases'],
      )) {
        final id = item['id'];
        if (id is String) reconciliationCases[id] = item;
      }
      for (final item in _mapList(
        payload['nationalFocusReconciliationHistory'],
      )) {
        final id = item['caseId'];
        if (id is String) reconciliationHistory[id] = item;
      }
      for (final item in _mapList(payload['nationalFocusClockReviewCases'])) {
        final id = item['id'];
        if (id is String) clockReviewCases[id] = item;
      }
      for (final item in _mapList(payload['nationalFocusClockReviewHistory'])) {
        final id = item['id'];
        if (id is String) clockReviewHistory[id] = item;
      }
    }
    return {
      'nationalFocusReconciliationCases': reconciliationCases.values.toList(),
      'nationalFocusReconciliationHistory': reconciliationHistory.values
          .toList(),
      'nationalFocusClockReviewCases': clockReviewCases.values.toList(),
      'nationalFocusClockReviewHistory': clockReviewHistory.values.toList(),
    };
  }

  Map<String, dynamic> _reviewMetadataFromSnapshot(
    Map<String, dynamic> snapshot,
  ) => {
    'nationalFocusReconciliationCases': _mapList(
      snapshot['nationalFocusReconciliationCases'],
    ),
    'nationalFocusReconciliationHistory': _mapList(
      snapshot['nationalFocusReconciliationHistory'],
    ),
    'nationalFocusClockReviewCases': _mapList(
      snapshot['nationalFocusClockReviewCases'],
    ),
    'nationalFocusClockReviewHistory': _mapList(
      snapshot['nationalFocusClockReviewHistory'],
    ),
  };

  Future<void> _recordSyncSnapshot({
    required String operation,
    DateTime? checkpointAt,
    Iterable<String> confirmedCardIds = const [],
    Iterable<String> missedConfirmationCardIds = const [],
    Set<String> deletedCardIds = const {},
    List<String>? parentSourceIds,
    Map<String, dynamic> metadata = const {},
  }) async {
    final existingSources = await _getNationalFocusSyncSources();
    final tombstones = <String>{...deletedCardIds};
    for (final source in existingSources) {
      final previous = _nationalFocusPayload(source)['tombstones'];
      if (previous is List) tombstones.addAll(previous.whereType<String>());
    }
    final resolvedParents =
        (parentSourceIds ??
                [
                  for (final head in _nationalFocusSourceHeads(existingSources))
                    head.sourceId,
                ])
            .toSet()
            .toList()
          ..sort();
    final snapshot = await _currentNationalFocusSnapshot();
    final inheritedMetadata = _nationalFocusReviewMetadataFromSources(
      existingSources,
      resolvedParents,
    );
    final payload = {
      ...snapshot,
      ...inheritedMetadata,
      ...metadata,
      'operation': operation,
      'checkpointAt': checkpointAt?.toUtc().toIso8601String(),
      'confirmedCardIds': confirmedCardIds.toSet().toList()..sort(),
      'missedConfirmationCardIds': missedConfirmationCardIds.toSet().toList()
        ..sort(),
      'tombstones': tombstones.toList()..sort(),
    };
    final deviceId = await _getNationalFocusDeviceId();
    final source = NationalFocusSyncSource(
      sourceId: _uuid.v4(),
      deviceId: deviceId,
      parentSourceIds: resolvedParents,
      occurredAt: _trustedNow(),
      payload: jsonEncode(payload),
    );
    await database
        .into(database.focusSyncSources)
        .insert(
          FocusSyncSourcesCompanion.insert(
            userId: userId,
            sourceId: source.sourceId,
            deviceId: source.deviceId,
            entityType: 'national_focus_tree',
            entityId: _nationalFocusTreeEntityId,
            parentSourceId: Value(
              resolvedParents.isEmpty ? null : resolvedParents.first,
            ),
            parentSourceIds: Value(jsonEncode(resolvedParents)),
            occurredAt: source.occurredAt,
            payload: source.payload,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<String> _getNationalFocusDeviceId() async {
    final existing = await (database.select(
      database.focusSourceDevices,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    if (existing != null) return existing.deviceId;
    final deviceId = _uuid.v4();
    await database
        .into(database.focusSourceDevices)
        .insertOnConflictUpdate(
          FocusSourceDevicesCompanion.insert(
            userId: userId,
            deviceId: deviceId,
          ),
        );
    return deviceId;
  }

  Future<Map<String, dynamic>> _currentNationalFocusSnapshot() async {
    final cardRows =
        await (database.select(database.localNationalFocusCards)
              ..where((row) => row.userId.equals(userId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.createdAt),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final cards = <Map<String, dynamic>>[];
    for (final card in cardRows) {
      final levels =
          await (database.select(
                database.localNationalFocusStrengtheningLevels,
              )..where(
                (level) =>
                    level.userId.equals(userId) & level.cardId.equals(card.id),
              ))
              .get();
      final versions =
          await (database.select(database.localNationalFocusRequirementVersions)
                ..where(
                  (version) =>
                      version.userId.equals(userId) &
                      version.cardId.equals(card.id),
                ))
              .get();
      cards.add({
        'id': card.id,
        'triggerCondition': card.triggerCondition,
        'action': card.action,
        'scope': card.scope,
        'exceptionNotes': card.exceptionNotes,
        'isInTree': card.isInTree,
        'parentId': card.parentId,
        'state': card.state,
        'successfulDays': card.successfulDays,
        'currentConsecutiveDays': card.currentConsecutiveDays,
        'bestConsecutiveDays': card.bestConsecutiveDays,
        'maintenanceCycleStarted': card.maintenanceCycleStarted,
        'failureReason': card.failureReason,
        'cascadeSourceCardId': card.cascadeSourceCardId,
        'cascadePriorState': card.cascadePriorState,
        'activeStrengtheningLevel': card.activeStrengtheningLevel,
        'reviewDisposition': card.reviewDisposition,
        'createdAt': card.createdAt.toUtc().toIso8601String(),
        'updatedAt': card.updatedAt.toUtc().toIso8601String(),
        'deletedAt': card.deletedAt?.toUtc().toIso8601String(),
        'strengtheningLevels': [
          for (final level in levels)
            {
              'levelNumber': level.levelNumber,
              'triggerConditionOverride': level.triggerConditionOverride,
              'actionOverride': level.actionOverride,
              'createdAt': level.createdAt.toUtc().toIso8601String(),
              'updatedAt': level.updatedAt.toUtc().toIso8601String(),
            },
        ],
        'requirementVersions': [
          for (final version in versions)
            {
              'id': version.id,
              'versionNumber': version.versionNumber,
              'strengtheningLevelNumber': version.strengtheningLevelNumber,
              'effectiveTriggerCondition': version.effectiveTriggerCondition,
              'effectiveAction': version.effectiveAction,
              'scope': version.scope,
              'exceptionNotes': version.exceptionNotes,
              'effectiveFrom': version.effectiveFrom.toUtc().toIso8601String(),
              'effectiveUntil': version.effectiveUntil
                  ?.toUtc()
                  .toIso8601String(),
            },
        ],
      });
    }

    final failureRows = await (database.select(
      database.localNationalFocusFailures,
    )..where((row) => row.userId.equals(userId))).get();
    final maintenance = await (database.select(
      database.localNationalFocusMaintenance,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    return {
      'schemaVersion': 1,
      'cards': cards,
      'failures': [
        for (final failure in failureRows)
          {
            'id': failure.id,
            'batchId': failure.batchId,
            'cardId': failure.cardId,
            'checkpointAt': failure.checkpointAt.toUtc().toIso8601String(),
            'cause': failure.cause,
            'failureReason': failure.failureReason,
            'sharedExplanation': failure.sharedExplanation,
            'treeSnapshot': failure.treeSnapshot,
            'reviewDisposition': failure.reviewDisposition,
          },
      ],
      'maintenance': maintenance == null
          ? null
          : {
              'lastSettledCheckpointAt': maintenance.lastSettledCheckpointAt
                  .toUtc()
                  .toIso8601String(),
            },
    };
  }

  Map<String, dynamic> _mergeNationalFocusSnapshots(
    List<NationalFocusSyncSource> sources,
    List<NationalFocusSyncSource> heads,
  ) {
    final sourcesById = {for (final source in sources) source.sourceId: source};
    final payloadsById = {
      for (final source in sources)
        source.sourceId: _nationalFocusPayload(source),
    };
    final ancestorsByHead = {
      for (final head in heads)
        head.sourceId: _nationalFocusAncestors(head.sourceId, sourcesById),
    };
    final commonAncestors = heads
        .map((head) => ancestorsByHead[head.sourceId]!)
        .reduce((left, right) => left.intersection(right));
    String? baseSourceId;
    var baseDepth = -1;
    for (final candidateId in commonAncestors) {
      final depth = _nationalFocusSourceDepth(candidateId, sourcesById);
      if (depth > baseDepth ||
          (depth == baseDepth &&
              (baseSourceId == null ||
                  candidateId.compareTo(baseSourceId) < 0))) {
        baseSourceId = candidateId;
        baseDepth = depth;
      }
    }
    final baseSnapshot = baseSourceId == null
        ? <String, dynamic>{}
        : payloadsById[baseSourceId]!;
    final baseCards = _nationalFocusCardsById(baseSnapshot);
    final headSnapshots = {
      for (final head in heads) head.sourceId: payloadsById[head.sourceId]!,
    };
    final pendingReconciliationCases = <String, Map<String, dynamic>>{};
    final reconciliationHistory = <String, Map<String, dynamic>>{};
    final pendingClockReviewCases = <String, Map<String, dynamic>>{};
    final clockReviewHistory = <String, Map<String, dynamic>>{};
    for (final snapshot in headSnapshots.values) {
      for (final review in _mapList(
        snapshot['nationalFocusReconciliationCases'],
      )) {
        final id = review['id'];
        if (id is String) pendingReconciliationCases[id] = review;
      }
      for (final review in _mapList(
        snapshot['nationalFocusClockReviewCases'],
      )) {
        final id = review['id'];
        if (id is String) pendingClockReviewCases[id] = review;
      }
    }
    for (final snapshot in payloadsById.values) {
      for (final result in _mapList(
        snapshot['nationalFocusReconciliationHistory'],
      )) {
        final id = result['caseId'];
        if (id is String) reconciliationHistory[id] = result;
      }
      for (final result in _mapList(
        snapshot['nationalFocusClockReviewHistory'],
      )) {
        final id = result['id'];
        if (id is String) clockReviewHistory[id] = result;
      }
    }

    final validConfirmations = <String>{};
    for (final source in sources) {
      final payload = payloadsById[source.sourceId]!;
      if (payload['operation'] != 'confirm_today') continue;
      final rawCheckpoint = payload['checkpointAt'];
      if (rawCheckpoint is! String) continue;
      final checkpoint = DateTime.parse(rawCheckpoint).toUtc();
      if (source.occurredAt.isAfter(checkpoint)) continue;
      final confirmed = payload['confirmedCardIds'];
      if (confirmed is! List) continue;
      for (final cardId in confirmed.whereType<String>()) {
        validConfirmations.add(_nationalFocusCheckpointKey(cardId, checkpoint));
      }
    }

    final allCardIds = <String>{...baseCards.keys};
    for (final snapshot in headSnapshots.values) {
      allCardIds.addAll(_nationalFocusCardsById(snapshot).keys);
    }
    final mergedCards = <Map<String, dynamic>>[];
    final conflictingCardIds = <String>{};
    final tombstones = <String>{};
    for (final source in sources) {
      final values = payloadsById[source.sourceId]!['tombstones'];
      if (values is List) tombstones.addAll(values.whereType<String>());
    }

    for (final cardId in allCardIds.toList()..sort()) {
      final relevantHeads = <NationalFocusSyncSource>[];
      for (final head in heads) {
        final headFailures = headSnapshots[head.sourceId]!['failures'];
        final branchHasMissedFailure =
            headFailures is List &&
            headFailures.whereType<Map>().any((failure) {
              if (failure['cardId'] != cardId ||
                  failure['cause'] !=
                      NationalFocusFailureCause
                          .missedConfirmation
                          .storageValue ||
                  failure['checkpointAt'] is! String) {
                return false;
              }
              final checkpoint = DateTime.parse(
                failure['checkpointAt'] as String,
              ).toUtc();
              return validConfirmations.contains(
                _nationalFocusCheckpointKey(cardId, checkpoint),
              );
            });
        if (!branchHasMissedFailure) relevantHeads.add(head);
      }

      final baseCard = baseCards[cardId];
      final baseSignature = _nationalFocusCardSignature(baseCard);
      final changedValues = <String, Map<String, dynamic>?>{};
      final valuesBySignature = <String, Map<String, dynamic>?>{};
      for (final head in relevantHeads) {
        final card = _nationalFocusCardsById(
          headSnapshots[head.sourceId]!,
        )[cardId];
        final signature = _nationalFocusCardSignature(card);
        valuesBySignature.putIfAbsent(signature, () => card);
        if (signature != baseSignature) {
          changedValues.putIfAbsent(signature, () => card);
        }
      }

      Map<String, dynamic>? selected;
      var isConflict = changedValues.length > 1;
      if (changedValues.isEmpty) {
        selected = baseCard;
      } else if (changedValues.length == 1) {
        selected = changedValues.values.single;
      } else {
        selected =
            baseCard ??
            valuesBySignature.values.firstWhere(
              (value) => value != null,
              orElse: () => null,
            );
      }
      if (selected == null) continue;

      final inheritedReview = relevantHeads.any((head) {
        final value = _nationalFocusCardsById(
          headSnapshots[head.sourceId]!,
        )[cardId];
        return value?['reviewDisposition'] == 'pending_review';
      });
      final cardValue = Map<String, dynamic>.from(selected);
      cardValue['reviewDisposition'] = isConflict || inheritedReview
          ? 'pending_review'
          : 'accepted';
      if (isConflict) conflictingCardIds.add(cardId);
      mergedCards.add(cardValue);
    }

    final mergedCardsById = {
      for (final card in mergedCards) card['id'] as String: card,
    };
    final invalidTreeCardIds = <String>{};
    for (final card in mergedCards) {
      final cardId = card['id'] as String;
      final parentId = card['parentId'] as String?;
      if (!(card['isInTree'] as bool) && parentId != null) {
        invalidTreeCardIds.add(cardId);
        invalidTreeCardIds.add(parentId);
        continue;
      }
      final visited = <String>{cardId};
      var ancestorId = parentId;
      while (ancestorId != null) {
        if (!visited.add(ancestorId)) {
          invalidTreeCardIds.addAll(visited);
          invalidTreeCardIds.add(ancestorId);
          break;
        }
        final ancestor = mergedCardsById[ancestorId];
        if (ancestor == null ||
            !(ancestor['isInTree'] as bool) ||
            ancestor['deletedAt'] != null) {
          invalidTreeCardIds.add(cardId);
          invalidTreeCardIds.add(ancestorId);
          break;
        }
        ancestorId = ancestor['parentId'] as String?;
      }
    }
    for (final cardId in invalidTreeCardIds) {
      final prior = baseCards[cardId] ?? mergedCardsById[cardId];
      if (prior == null) continue;
      final reviewed = Map<String, dynamic>.from(prior)
        ..['reviewDisposition'] = 'pending_review';
      mergedCardsById[cardId] = reviewed;
      conflictingCardIds.add(cardId);
    }
    mergedCards
      ..clear()
      ..addAll(
        mergedCardsById.values.toList()..sort(
          (left, right) =>
              (left['id'] as String).compareTo(right['id'] as String),
        ),
      );

    for (final cardId in conflictingCardIds) {
      tombstones.remove(cardId);
    }

    final reviewGroups = _nationalFocusConflictGroups(
      conflictingCardIds,
      headSnapshots.values,
    );
    for (final cardIds in reviewGroups) {
      final id = _nationalFocusReconciliationId(baseSourceId, cardIds);
      pendingReconciliationCases.putIfAbsent(
        id,
        () => _nationalFocusReconciliationCaseJson(
          id: id,
          cardIds: cardIds,
          baseSourceId: baseSourceId,
          baseCards: baseCards,
          heads: heads,
          headSnapshots: headSnapshots,
          sourcesById: sourcesById,
          payloadsById: payloadsById,
        ),
      );
    }

    final failuresById = <String, Map<String, dynamic>>{};
    for (final snapshot in headSnapshots.values) {
      final failures = snapshot['failures'];
      if (failures is! List) continue;
      for (final rawFailure in failures) {
        if (rawFailure is! Map) continue;
        final failure = Map<String, dynamic>.from(rawFailure);
        final failureId = failure['id'];
        if (failureId is! String) continue;
        final existing = failuresById[failureId];
        if (existing == null ||
            (existing['sharedExplanation'] == null &&
                failure['sharedExplanation'] != null)) {
          failuresById[failureId] = failure;
        }
      }
    }
    for (final failure in failuresById.values) {
      if (conflictingCardIds.contains(failure['cardId'])) {
        failure['reviewDisposition'] = 'pending_review';
      }
    }
    failuresById.removeWhere((_, failure) {
      if (failure['cause'] !=
          NationalFocusFailureCause.missedConfirmation.storageValue) {
        return false;
      }
      final cardId = failure['cardId'];
      final checkpointAt = failure['checkpointAt'];
      if (cardId is! String || checkpointAt is! String) return false;
      return validConfirmations.contains(
        _nationalFocusCheckpointKey(
          cardId,
          DateTime.parse(checkpointAt).toUtc(),
        ),
      );
    });

    DateTime? lastSettledCheckpointAt;
    for (final snapshot in headSnapshots.values) {
      final maintenance = snapshot['maintenance'];
      if (maintenance is! Map ||
          maintenance['lastSettledCheckpointAt'] is! String) {
        continue;
      }
      final checkpoint = DateTime.parse(
        maintenance['lastSettledCheckpointAt'] as String,
      ).toUtc();
      if (lastSettledCheckpointAt == null ||
          checkpoint.isAfter(lastSettledCheckpointAt)) {
        lastSettledCheckpointAt = checkpoint;
      }
    }

    return {
      'schemaVersion': 1,
      'operation': 'synchronization_merge',
      'cards': mergedCards,
      'failures': failuresById.values.toList(),
      'maintenance': lastSettledCheckpointAt == null
          ? null
          : {
              'lastSettledCheckpointAt': lastSettledCheckpointAt
                  .toIso8601String(),
            },
      'tombstones': tombstones.toList()..sort(),
      'nationalFocusReconciliationCases': pendingReconciliationCases.values
          .toList(),
      'nationalFocusReconciliationHistory': reconciliationHistory.values
          .toList(),
      'nationalFocusClockReviewCases': pendingClockReviewCases.values.toList(),
      'nationalFocusClockReviewHistory': clockReviewHistory.values.toList(),
    };
  }

  Future<void> _applyNationalFocusSnapshot(
    Map<String, dynamic> snapshot,
  ) async {
    final rawCards = snapshot['cards'];
    final rawFailures = snapshot['failures'];
    final rawTombstones = snapshot['tombstones'];
    final cardMaps = rawCards is List
        ? rawCards.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final failureMaps = rawFailures is List
        ? rawFailures.whereType<Map>().map(Map<String, dynamic>.from).toList()
        : <Map<String, dynamic>>[];
    final tombstones = rawTombstones is List
        ? rawTombstones.whereType<String>().toSet()
        : <String>{};

    await database.transaction(() async {
      for (final card in cardMaps) {
        final cardId = card['id'] as String;
        final createdAt = DateTime.parse(card['createdAt'] as String).toUtc();
        await database
            .into(database.localNationalFocusCards)
            .insertOnConflictUpdate(
              LocalNationalFocusCardsCompanion.insert(
                userId: userId,
                id: cardId,
                triggerCondition: card['triggerCondition'] as String,
                action: card['action'] as String,
                scope: Value(card['scope'] as String?),
                exceptionNotes: Value(card['exceptionNotes'] as String?),
                isInTree: Value(card['isInTree'] as bool),
                parentId: Value(card['parentId'] as String?),
                state: Value(card['state'] as String),
                successfulDays: Value(card['successfulDays'] as int),
                currentConsecutiveDays: Value(
                  card['currentConsecutiveDays'] as int,
                ),
                bestConsecutiveDays: Value(card['bestConsecutiveDays'] as int),
                maintenanceCycleStarted: Value(
                  card['maintenanceCycleStarted'] as bool,
                ),
                failureReason: Value(card['failureReason'] as String?),
                cascadeSourceCardId: Value(
                  card['cascadeSourceCardId'] as String?,
                ),
                cascadePriorState: Value(card['cascadePriorState'] as String?),
                reviewDisposition: Value(
                  (card['reviewDisposition'] as String?) ?? 'accepted',
                ),
                activeStrengtheningLevel: Value(
                  card['activeStrengtheningLevel'] as int?,
                ),
                createdAt: createdAt,
                updatedAt: DateTime.parse(card['updatedAt'] as String).toUtc(),
                deletedAt: Value(_optionalNationalFocusDate(card['deletedAt'])),
              ),
            );

        await (database.delete(database.localNationalFocusStrengtheningLevels)
              ..where(
                (level) =>
                    level.userId.equals(userId) & level.cardId.equals(cardId),
              ))
            .go();
        final rawLevels = card['strengtheningLevels'];
        if (rawLevels is List) {
          for (final rawLevel in rawLevels.whereType<Map>()) {
            final level = Map<String, dynamic>.from(rawLevel);
            await database
                .into(database.localNationalFocusStrengtheningLevels)
                .insert(
                  LocalNationalFocusStrengtheningLevelsCompanion.insert(
                    userId: userId,
                    cardId: cardId,
                    levelNumber: level['levelNumber'] as int,
                    triggerConditionOverride: Value(
                      level['triggerConditionOverride'] as String?,
                    ),
                    actionOverride: Value(level['actionOverride'] as String?),
                    createdAt: DateTime.parse(level['createdAt'] as String)
                        .toUtc(),
                    updatedAt: DateTime.parse(level['updatedAt'] as String)
                        .toUtc(),
                  ),
                );
          }
        }

        await (database.delete(
              database.localNationalFocusRequirementVersions,
            )..where(
              (version) =>
                  version.userId.equals(userId) & version.cardId.equals(cardId),
            ))
            .go();
        final rawVersions = card['requirementVersions'];
        if (rawVersions is List) {
          for (final rawVersion in rawVersions.whereType<Map>()) {
            final version = Map<String, dynamic>.from(rawVersion);
            await database
                .into(database.localNationalFocusRequirementVersions)
                .insert(
                  LocalNationalFocusRequirementVersionsCompanion.insert(
                    userId: userId,
                    id: version['id'] as String,
                    cardId: cardId,
                    versionNumber: version['versionNumber'] as int,
                    strengtheningLevelNumber: Value(
                      version['strengtheningLevelNumber'] as int?,
                    ),
                    effectiveTriggerCondition:
                        version['effectiveTriggerCondition'] as String,
                    effectiveAction: version['effectiveAction'] as String,
                    scope: Value(version['scope'] as String?),
                    exceptionNotes: Value(version['exceptionNotes'] as String?),
                    effectiveFrom: DateTime.parse(
                      version['effectiveFrom'] as String,
                    ).toUtc(),
                    effectiveUntil: Value(
                      _optionalNationalFocusDate(version['effectiveUntil']),
                    ),
                  ),
                );
          }
        }
      }

      await (database.delete(
        database.localNationalFocusFailures,
      )..where((failure) => failure.userId.equals(userId))).go();
      for (final failure in failureMaps) {
        await database
            .into(database.localNationalFocusFailures)
            .insert(
              LocalNationalFocusFailuresCompanion.insert(
                userId: userId,
                id: failure['id'] as String,
                batchId: failure['batchId'] as String,
                cardId: failure['cardId'] as String,
                checkpointAt: DateTime.parse(failure['checkpointAt'] as String)
                    .toUtc(),
                cause: failure['cause'] as String,
                failureReason: Value(failure['failureReason'] as String?),
                sharedExplanation: Value(
                  failure['sharedExplanation'] as String?,
                ),
                treeSnapshot: failure['treeSnapshot'] as String,
                reviewDisposition: Value(
                  (failure['reviewDisposition'] as String?) ?? 'accepted',
                ),
              ),
            );
      }

      final maintenance = snapshot['maintenance'];
      if (maintenance is Map &&
          maintenance['lastSettledCheckpointAt'] is String) {
        await database
            .into(database.localNationalFocusMaintenance)
            .insertOnConflictUpdate(
              LocalNationalFocusMaintenanceCompanion.insert(
                userId: userId,
                lastSettledCheckpointAt: DateTime.parse(
                  maintenance['lastSettledCheckpointAt'] as String,
                ).toUtc(),
              ),
            );
      }

      for (final cardId in tombstones) {
        final isReferenced = failureMaps.any((failure) {
          if (failure['cardId'] == cardId) return true;
          final rawSnapshot = failure['treeSnapshot'];
          if (rawSnapshot is! String) return false;
          try {
            final tree = jsonDecode(rawSnapshot) as List<dynamic>;
            return tree.any(
              (entry) => (entry as Map<String, dynamic>)['id'] == cardId,
            );
          } on FormatException {
            return true;
          } on TypeError {
            return true;
          }
        });
        final row =
            await (database.select(database.localNationalFocusCards)..where(
                  (card) => card.userId.equals(userId) & card.id.equals(cardId),
                ))
                .getSingleOrNull();
        if (isReferenced && row != null) {
          await _updateCard(
            row,
            LocalNationalFocusCardsCompanion(
              isInTree: const Value(false),
              parentId: const Value(null),
              deletedAt: Value(row.deletedAt ?? row.updatedAt),
              reviewDisposition: const Value('accepted'),
            ),
          );
          continue;
        }
        await (database.delete(database.localNationalFocusStrengtheningLevels)
              ..where(
                (level) =>
                    level.userId.equals(userId) & level.cardId.equals(cardId),
              ))
            .go();
        await (database.delete(
              database.localNationalFocusRequirementVersions,
            )..where(
              (version) =>
                  version.userId.equals(userId) & version.cardId.equals(cardId),
            ))
            .go();
        await (database.delete(database.localNationalFocusCards)
              ..where((card) => card.userId.equals(userId))
              ..where((card) => card.id.equals(cardId)))
            .go();
      }
    });
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

  void _requireResolvedCard(LocalNationalFocusCard card) {
    if (card.reviewDisposition == 'pending_review') {
      throw StateError('同步分歧待核对；请先核对这张国策卡。');
    }
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

  Future<List<NationalFocusCard>> _cardsFromRows(
    List<LocalNationalFocusCard> rows,
  ) => Future.wait(rows.map(_cardFromRow));

  Future<NationalFocusCard> _cardFromRow(LocalNationalFocusCard row) async {
    final levelRows =
        await (database.select(database.localNationalFocusStrengtheningLevels)
              ..where(
                (level) =>
                    level.userId.equals(userId) & level.cardId.equals(row.id),
              )
              ..orderBy([(level) => OrderingTerm.asc(level.levelNumber)]))
            .get();
    final versionRows =
        await (database.select(database.localNationalFocusRequirementVersions)
              ..where(
                (version) =>
                    version.userId.equals(userId) &
                    version.cardId.equals(row.id),
              )
              ..orderBy([(version) => OrderingTerm.asc(version.versionNumber)]))
            .get();
    final versions = versionRows.isEmpty
        ? [
            NationalFocusRequirementVersion(
              versionNumber: 1,
              strengtheningLevelNumber: row.activeStrengtheningLevel,
              effectiveTriggerCondition: row.triggerCondition,
              effectiveAction: row.action,
              scope: row.scope,
              exceptionNotes: row.exceptionNotes,
              effectiveFrom: row.createdAt,
            ),
          ]
        : versionRows.map(_requirementVersionFromRow).toList(growable: false);
    return NationalFocusCard(
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
      hasPendingReview: row.reviewDisposition == 'pending_review',
      strengtheningLevels: levelRows
          .map(
            (level) => NationalFocusStrengtheningLevel(
              levelNumber: level.levelNumber,
              triggerCondition: level.triggerConditionOverride,
              action: level.actionOverride,
            ),
          )
          .toList(growable: false),
      activeStrengtheningLevel: row.activeStrengtheningLevel,
      requirementVersions: versions,
    );
  }

  NationalFocusRequirementVersion _requirementVersionFromRow(
    LocalNationalFocusRequirementVersion row,
  ) => NationalFocusRequirementVersion(
    versionNumber: row.versionNumber,
    strengtheningLevelNumber: row.strengtheningLevelNumber,
    effectiveTriggerCondition: row.effectiveTriggerCondition,
    effectiveAction: row.effectiveAction,
    scope: row.scope,
    exceptionNotes: row.exceptionNotes,
    effectiveFrom: row.effectiveFrom,
    effectiveUntil: row.effectiveUntil,
  );

  Future<Map<String, Object?>> _snapshotJson(
    LocalNationalFocusCard row, {
    String? failureSourceCardId,
  }) async {
    final version =
        await (database.select(database.localNationalFocusRequirementVersions)
              ..where(
                (candidate) =>
                    candidate.userId.equals(userId) &
                    candidate.cardId.equals(row.id) &
                    candidate.effectiveUntil.isNull(),
              ))
            .getSingleOrNull();
    return {
      'id': row.id,
      'triggerCondition': row.triggerCondition,
      'action': row.action,
      'effectiveTriggerCondition':
          version?.effectiveTriggerCondition ?? row.triggerCondition,
      'effectiveAction': version?.effectiveAction ?? row.action,
      'activeStrengtheningLevel': row.activeStrengtheningLevel,
      'requirementVersionNumber': version?.versionNumber,
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
  }

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
            activeStrengtheningLevel: item['activeStrengtheningLevel'] as int?,
            requirementVersionNumber: item['requirementVersionNumber'] as int?,
            effectiveTriggerCondition:
                item['effectiveTriggerCondition'] as String?,
            effectiveAction: item['effectiveAction'] as String?,
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
      isPendingReview: row.reviewDisposition == 'pending_review',
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
    final candidate = _trustedNow();
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
  Future<NationalFocusStrengtheningLevel> saveStrengtheningLevel({
    required String cardId,
    int? levelNumber,
    required NationalFocusStrengtheningLevelDraft draft,
  }) => _unavailable();

  @override
  Future<void> selectStrengtheningLevel({
    required String cardId,
    required int? levelNumber,
  }) => _unavailable();

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
  Stream<NationalFocusReviewState> watchNationalFocusReviewState() =>
      Stream.value(const NationalFocusReviewState());

  @override
  Future<NationalFocusReviewState> getNationalFocusReviewState() async =>
      const NationalFocusReviewState();

  @override
  Future<void> deferNationalFocusReconciliation(String caseId) =>
      _unavailable();

  @override
  Future<void> resolveNationalFocusReconciliation({
    required String caseId,
    required String selectedSourceId,
  }) => _unavailable();

  @override
  Future<void> deferNationalFocusClockReview(String caseId) => _unavailable();

  @override
  Future<void> resolveNationalFocusClockReview(String caseId) => _unavailable();

  @override
  Future<void> sync() async {}

  @override
  Future<void> dispose() async {}

  Future<T> _unavailable<T>() async {
    throw StateError('当前用户的国策卡片存储尚未配置。');
  }
}

DateTime? _nationalFocusCheckpointFromSnapshot(Map<String, dynamic> snapshot) {
  final maintenance = snapshot['maintenance'];
  final rawCheckpoint = maintenance is Map
      ? maintenance['lastSettledCheckpointAt']
      : null;
  return rawCheckpoint is String ? DateTime.parse(rawCheckpoint).toUtc() : null;
}

Set<String> _nationalFocusCheckpointReplayCardIds(
  Set<String> affectedCardIds,
  List<Map<String, dynamic>> resolvedCards,
) {
  final replayCardIds = <String>{...affectedCardIds};
  final cardsById = {
    for (final card in resolvedCards) card['id'] as String: card,
  };
  for (final card in resolvedCards) {
    final cardId = card['id'] as String;
    final visited = <String>{cardId};
    var parentId = card['parentId'] as String?;
    while (parentId != null && visited.add(parentId)) {
      if (affectedCardIds.contains(parentId)) {
        replayCardIds.add(cardId);
        break;
      }
      parentId = cardsById[parentId]?['parentId'] as String?;
    }
  }
  return replayCardIds;
}

List<Map<String, dynamic>> _mapList(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : <Map<String, dynamic>>[];

NationalFocusReviewState _nationalFocusReviewStateFromSources({
  required List<Map<String, dynamic>> pendingPayloads,
  required List<NationalFocusSyncSource> sources,
}) {
  final casesById = <String, Map<String, dynamic>>{};
  final clockCasesById = <String, Map<String, dynamic>>{};
  final historyById = <String, Map<String, dynamic>>{};
  final clockHistoryById = <String, Map<String, dynamic>>{};
  for (final payload in pendingPayloads) {
    for (final item in _mapList(payload['nationalFocusReconciliationCases'])) {
      final id = item['id'];
      if (id is String) casesById[id] = item;
    }
    for (final item in _mapList(payload['nationalFocusClockReviewCases'])) {
      final id = item['id'];
      if (id is String) clockCasesById[id] = item;
    }
  }
  for (final source in sources) {
    final payload = _nationalFocusPayload(source);
    for (final item in _mapList(
      payload['nationalFocusReconciliationHistory'],
    )) {
      final id = item['caseId'];
      if (id is String) historyById[id] = item;
    }
    for (final item in _mapList(payload['nationalFocusClockReviewHistory'])) {
      final id = item['id'];
      if (id is String) clockHistoryById[id] = item;
    }
  }

  final cases = casesById.values.map((item) {
    final options = _mapList(item['options'])
        .map((option) {
          final operations = _mapList(option['operations'])
              .map((operation) {
                return NationalFocusReconciliationOperation(
                  sourceId: operation['sourceId'] as String,
                  deviceId: operation['deviceId'] as String,
                  operation: operation['operation'] as String,
                  occurredAt: DateTime.parse(operation['occurredAt'] as String)
                      .toUtc(),
                  effects: _nationalFocusEffectsFromJson(operation['effects']),
                );
              })
              .toList(growable: false);
          return NationalFocusReconciliationOption(
            sourceId: option['sourceId'] as String,
            operations: operations,
            effects: _nationalFocusEffectsFromJson(option['effects']),
          );
        })
        .toList(growable: false);
    return NationalFocusReconciliationCase(
      id: item['id'] as String,
      createdAt: DateTime.parse(item['createdAt'] as String).toUtc(),
      cardIds: (item['cardIds'] as List<dynamic>).whereType<String>().toList(),
      cardNames: {
        for (final entry in Map<String, dynamic>.from(
          item['cardNames'] as Map,
        ).entries)
          entry.key: entry.value as String,
      },
      options: options,
      isDeferred: item['isDeferred'] == true,
    );
  }).toList()..sort((left, right) => left.createdAt.compareTo(right.createdAt));

  NationalFocusClockReviewCase clockCase(
    Map<String, dynamic> item,
  ) => NationalFocusClockReviewCase(
    id: item['id'] as String,
    direction: item['direction'] == 'backward'
        ? NationalFocusClockChangeDirection.backward
        : NationalFocusClockChangeDirection.forward,
    detectedAt: DateTime.parse(item['detectedAt'] as String).toUtc(),
    previousWallTime: DateTime.parse(item['previousWallTime'] as String)
        .toUtc(),
    observedWallTime: DateTime.parse(item['observedWallTime'] as String)
        .toUtc(),
    reliableThroughTime: DateTime.parse(item['reliableThroughTime'] as String)
        .toUtc(),
    estimatedElapsedSeconds: item['estimatedElapsedSeconds'] as int,
    cardIds: (item['cardIds'] as List<dynamic>).whereType<String>().toList(),
    isDeferred: item['isDeferred'] == true,
  );

  final reconciliationHistory =
      historyById.values.map((item) {
          return NationalFocusReconciliationResult(
            caseId: item['caseId'] as String,
            resolvedAt: DateTime.parse(item['resolvedAt'] as String).toUtc(),
            cardIds: (item['cardIds'] as List<dynamic>)
                .whereType<String>()
                .toList(),
            acceptedSourceIds: (item['acceptedSourceIds'] as List<dynamic>)
                .whereType<String>()
                .toList(),
            retainedSourceIds: (item['retainedSourceIds'] as List<dynamic>)
                .whereType<String>()
                .toList(),
          );
        }).toList()
        ..sort((left, right) => left.resolvedAt.compareTo(right.resolvedAt));

  return NationalFocusReviewState(
    reconciliationCases: cases,
    clockReviewCases: clockCasesById.values.map(clockCase).toList()
      ..sort((left, right) => left.detectedAt.compareTo(right.detectedAt)),
    reconciliationHistory: reconciliationHistory,
    clockReviewHistory: clockHistoryById.values.map(clockCase).toList()
      ..sort((left, right) => left.detectedAt.compareTo(right.detectedAt)),
  );
}

List<NationalFocusReconciliationCardEffect> _nationalFocusEffectsFromJson(
  Object? value,
) => [
  for (final item in _mapList(value))
    NationalFocusReconciliationCardEffect(
      cardId: item['cardId'] as String,
      triggerCondition: item['triggerCondition'] as String?,
      previousState: item['previousState'] as String?,
      newState: item['newState'] as String?,
      previousParentId: item['previousParentId'] as String?,
      newParentId: item['newParentId'] as String?,
      previousIsInTree: item['previousIsInTree'] as bool?,
      newIsInTree: item['newIsInTree'] as bool?,
      previousFailureReason: item['previousFailureReason'] as String?,
      newFailureReason: item['newFailureReason'] as String?,
      previousCascadeSourceCardId:
          item['previousCascadeSourceCardId'] as String?,
      newCascadeSourceCardId: item['newCascadeSourceCardId'] as String?,
      previousSuccessfulDays: item['previousSuccessfulDays'] as int?,
      newSuccessfulDays: item['newSuccessfulDays'] as int?,
      previousCurrentConsecutiveDays:
          item['previousCurrentConsecutiveDays'] as int?,
      newCurrentConsecutiveDays: item['newCurrentConsecutiveDays'] as int?,
      previousBestConsecutiveDays: item['previousBestConsecutiveDays'] as int?,
      newBestConsecutiveDays: item['newBestConsecutiveDays'] as int?,
      previousMaintenanceCycleStarted:
          item['previousMaintenanceCycleStarted'] as bool?,
      newMaintenanceCycleStarted: item['newMaintenanceCycleStarted'] as bool?,
    ),
];

Map<String, dynamic> _nationalFocusSourceToJson(
  NationalFocusSyncSource source, {
  required String userId,
}) => {
  'source_id': source.sourceId,
  'user_id': userId,
  'device_id': source.deviceId,
  'entity_type': 'national_focus_tree',
  'entity_id': _nationalFocusTreeEntityId,
  'parent_source_id': source.parentSourceIds.isEmpty
      ? null
      : source.parentSourceIds.first,
  'parent_source_ids': source.parentSourceIds,
  'occurred_at': source.occurredAt.toUtc().toIso8601String(),
  'payload': jsonDecode(source.payload),
};

NationalFocusSyncSource _nationalFocusSourceFromJson(
  Map<String, dynamic> json,
) {
  final primaryParent = json['parent_source_id'] as String?;
  final rawParents = json['parent_source_ids'];
  final parentIds = <String>{};
  if (rawParents is List) parentIds.addAll(rawParents.whereType<String>());
  if (primaryParent != null) parentIds.add(primaryParent);
  return NationalFocusSyncSource(
    sourceId: json['source_id'] as String,
    deviceId: json['device_id'] as String,
    parentSourceIds: parentIds.toList()..sort(),
    occurredAt: DateTime.parse(json['occurred_at'] as String).toUtc(),
    payload: jsonEncode(json['payload']),
  );
}

Map<String, dynamic> _nationalFocusPayload(NationalFocusSyncSource source) =>
    Map<String, dynamic>.from(jsonDecode(source.payload) as Map);

List<String> _decodeNationalFocusSourceParents(
  String? primaryParentId,
  String encodedParents,
) {
  final decoded = jsonDecode(encodedParents);
  final parentIds = <String>{};
  if (decoded is List) parentIds.addAll(decoded.whereType<String>());
  if (primaryParentId != null) parentIds.add(primaryParentId);
  return parentIds.toList()..sort();
}

List<NationalFocusSyncSource> _nationalFocusSourceHeads(
  List<NationalFocusSyncSource> sources,
) {
  final sourceIds = sources.map((source) => source.sourceId).toSet();
  final parentedIds = <String>{
    for (final source in sources)
      for (final parentId in source.parentSourceIds)
        if (sourceIds.contains(parentId)) parentId,
  };
  final heads =
      sources.where((source) => !parentedIds.contains(source.sourceId)).toList()
        ..sort((left, right) => left.sourceId.compareTo(right.sourceId));
  return heads;
}

Set<String> _nationalFocusAncestors(
  String sourceId,
  Map<String, NationalFocusSyncSource> sourcesById,
) {
  final found = <String>{};
  final pending = <String>[sourceId];
  while (pending.isNotEmpty) {
    final currentId = pending.removeLast();
    if (!found.add(currentId)) continue;
    pending.addAll(sourcesById[currentId]?.parentSourceIds ?? const []);
  }
  return found;
}

int _nationalFocusSourceDepth(
  String sourceId,
  Map<String, NationalFocusSyncSource> sourcesById, [
  Set<String>? visiting,
]) {
  final path = visiting ?? <String>{};
  if (!path.add(sourceId)) return 0;
  final source = sourcesById[sourceId];
  if (source == null || source.parentSourceIds.isEmpty) return 0;
  var parentDepth = 0;
  for (final parentId in source.parentSourceIds) {
    final depth = _nationalFocusSourceDepth(parentId, sourcesById, {...path});
    if (depth > parentDepth) parentDepth = depth;
  }
  return parentDepth + 1;
}

Map<String, Map<String, dynamic>> _nationalFocusCardsById(
  Map<String, dynamic> snapshot,
) {
  final rawCards = snapshot['cards'];
  if (rawCards is! List) return {};
  return {
    for (final rawCard in rawCards.whereType<Map>())
      if (rawCard['id'] is String)
        rawCard['id'] as String: Map<String, dynamic>.from(rawCard),
  };
}

String _nationalFocusReconciliationId(
  String? baseSourceId,
  List<String> cardIds,
) => 'national-focus:${baseSourceId ?? 'root'}:${cardIds.join(',')}';

List<List<String>> _nationalFocusConflictGroups(
  Set<String> conflictingCardIds,
  Iterable<Map<String, dynamic>> snapshots,
) {
  final neighbors = {
    for (final cardId in conflictingCardIds) cardId: <String>{},
  };
  for (final snapshot in snapshots) {
    final cards = _nationalFocusCardsById(snapshot);
    for (final cardId in conflictingCardIds) {
      final parentId = cards[cardId]?['parentId'];
      if (parentId is! String || !conflictingCardIds.contains(parentId)) {
        continue;
      }
      neighbors[cardId]!.add(parentId);
      neighbors[parentId]!.add(cardId);
    }
  }
  final groups = <List<String>>[];
  final unvisited = {...conflictingCardIds};
  while (unvisited.isNotEmpty) {
    final group = <String>{};
    final pending = <String>[unvisited.first];
    while (pending.isNotEmpty) {
      final cardId = pending.removeLast();
      if (!unvisited.remove(cardId)) continue;
      group.add(cardId);
      pending.addAll(neighbors[cardId]!.where(unvisited.contains));
    }
    groups.add(group.toList()..sort());
  }
  groups.sort((left, right) => left.first.compareTo(right.first));
  return groups;
}

Map<String, dynamic> _nationalFocusReconciliationCaseJson({
  required String id,
  required List<String> cardIds,
  required String? baseSourceId,
  required Map<String, Map<String, dynamic>> baseCards,
  required List<NationalFocusSyncSource> heads,
  required Map<String, Map<String, dynamic>> headSnapshots,
  required Map<String, NationalFocusSyncSource> sourcesById,
  required Map<String, Map<String, dynamic>> payloadsById,
}) {
  final baseAncestors = baseSourceId == null
      ? <String>{}
      : _nationalFocusAncestors(baseSourceId, sourcesById);
  final options = <Map<String, dynamic>>[];
  for (final head in heads) {
    final headCards = _nationalFocusCardsById(headSnapshots[head.sourceId]!);
    final optionEffects = <Map<String, dynamic>>[];
    for (final cardId in cardIds) {
      final before = baseCards[cardId];
      final after = headCards[cardId];
      if (_nationalFocusCardSignature(before) ==
          _nationalFocusCardSignature(after)) {
        continue;
      }
      optionEffects.add(_nationalFocusEffectJson(cardId, before, after));
    }
    if (optionEffects.isEmpty) continue;

    final branchSourceIds =
        _nationalFocusAncestors(
          head.sourceId,
          sourcesById,
        ).difference(baseAncestors).toList()..sort((left, right) {
          final timeOrder = sourcesById[left]!.occurredAt.compareTo(
            sourcesById[right]!.occurredAt,
          );
          return timeOrder == 0 ? left.compareTo(right) : timeOrder;
        });
    final operations = <Map<String, dynamic>>[];
    for (final sourceId in branchSourceIds) {
      final source = sourcesById[sourceId]!;
      final payload = payloadsById[sourceId]!;
      final sourceCards = _nationalFocusCardsById(payload);
      Map<String, Map<String, dynamic>> previousCards = baseCards;
      for (final parentSourceId in source.parentSourceIds) {
        final parentPayload = payloadsById[parentSourceId];
        if (parentPayload != null) {
          previousCards = _nationalFocusCardsById(parentPayload);
          break;
        }
      }
      final operationEffects = <Map<String, dynamic>>[];
      for (final cardId in cardIds) {
        final before = previousCards[cardId] ?? baseCards[cardId];
        final after = sourceCards[cardId];
        if (_nationalFocusCardSignature(before) ==
            _nationalFocusCardSignature(after)) {
          continue;
        }
        operationEffects.add(_nationalFocusEffectJson(cardId, before, after));
      }
      if (operationEffects.isEmpty) continue;
      operations.add({
        'sourceId': source.sourceId,
        'deviceId': source.deviceId,
        'operation': payload['operation'] is String
            ? payload['operation'] as String
            : 'unknown',
        'occurredAt': source.occurredAt.toUtc().toIso8601String(),
        'effects': operationEffects,
      });
    }
    options.add({
      'sourceId': head.sourceId,
      'operations': operations,
      'effects': optionEffects,
    });
  }
  final createdAt = heads
      .map((source) => source.occurredAt.toUtc())
      .reduce((left, right) => left.isAfter(right) ? left : right);
  return {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'cardIds': cardIds,
    'cardNames': {
      for (final cardId in cardIds)
        cardId: _nationalFocusConflictCardName(
          cardId,
          baseCards,
          heads,
          headSnapshots,
        ),
    },
    'baseSourceId': baseSourceId,
    'options': options,
    'isDeferred': false,
  };
}

Map<String, dynamic> _nationalFocusEffectJson(
  String cardId,
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
) => {
  'cardId': cardId,
  'triggerCondition': after?['triggerCondition'] ?? before?['triggerCondition'],
  'previousState': before?['state'],
  'newState': after?['state'],
  'previousParentId': before?['parentId'],
  'newParentId': after?['parentId'],
  'previousIsInTree': before?['isInTree'],
  'newIsInTree': after?['isInTree'],
  'previousFailureReason': before?['failureReason'],
  'newFailureReason': after?['failureReason'],
  'previousCascadeSourceCardId': before?['cascadeSourceCardId'],
  'newCascadeSourceCardId': after?['cascadeSourceCardId'],
  'previousSuccessfulDays': before?['successfulDays'],
  'newSuccessfulDays': after?['successfulDays'],
  'previousCurrentConsecutiveDays': before?['currentConsecutiveDays'],
  'newCurrentConsecutiveDays': after?['currentConsecutiveDays'],
  'previousBestConsecutiveDays': before?['bestConsecutiveDays'],
  'newBestConsecutiveDays': after?['bestConsecutiveDays'],
  'previousMaintenanceCycleStarted': before?['maintenanceCycleStarted'],
  'newMaintenanceCycleStarted': after?['maintenanceCycleStarted'],
};

String _nationalFocusConflictCardName(
  String cardId,
  Map<String, Map<String, dynamic>> baseCards,
  List<NationalFocusSyncSource> heads,
  Map<String, Map<String, dynamic>> headSnapshots,
) {
  final baseName = baseCards[cardId]?['triggerCondition'];
  if (baseName is String) return baseName;
  for (final head in heads) {
    final name = _nationalFocusCardsById(
      headSnapshots[head.sourceId]!,
    )[cardId]?['triggerCondition'];
    if (name is String) return name;
  }
  return '已删除的国策卡';
}

bool _isValidNationalFocusTree(List<Map<String, dynamic>> cards) {
  final cardsById = {for (final card in cards) card['id'] as String: card};
  for (final card in cards) {
    final cardId = card['id'] as String;
    final parentId = card['parentId'] as String?;
    if (card['isInTree'] != true) {
      if (parentId != null) return false;
      continue;
    }
    final visited = <String>{cardId};
    var ancestorId = parentId;
    while (ancestorId != null) {
      if (!visited.add(ancestorId)) return false;
      final ancestor = cardsById[ancestorId];
      if (ancestor == null ||
          ancestor['isInTree'] != true ||
          ancestor['deletedAt'] != null) {
        return false;
      }
      ancestorId = ancestor['parentId'] as String?;
    }
  }
  return true;
}

String _nationalFocusCardSignature(Map<String, dynamic>? card) {
  if (card == null) return '<missing>';
  final comparable = Map<String, dynamic>.from(card)
    ..remove('reviewDisposition');
  return jsonEncode(_canonicalNationalFocusJson(comparable));
}

String _nationalFocusStateSignature(Map<String, dynamic> snapshot) =>
    jsonEncode(
      _canonicalNationalFocusJson({
        'cards': snapshot['cards'] ?? const [],
        'failures': snapshot['failures'] ?? const [],
        'maintenance': snapshot['maintenance'],
        'tombstones': snapshot['tombstones'] ?? const [],
      }),
    );

Object? _canonicalNationalFocusJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {
      for (final key in keys) key: _canonicalNationalFocusJson(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalNationalFocusJson).toList();
  }
  return value;
}

String _nationalFocusCheckpointKey(String cardId, DateTime checkpoint) =>
    '$cardId:${checkpoint.toUtc().millisecondsSinceEpoch}';

DateTime? _optionalNationalFocusDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toUtc();
