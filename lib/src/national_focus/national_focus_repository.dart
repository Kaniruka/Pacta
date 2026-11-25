import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../auth/user_lifecycle.dart';
import '../profile/account_time_zone.dart';
import '../tasks/task_database.dart';
import 'national_focus_checkpoints.dart';
import 'national_focus_models.dart';

/// 读取本地账号的国策结算检查点时区；无账号或未设置时回落默认国策时区。
Future<String> readAccountCheckpointTimeZoneId(
  PactaDatabase database,
  String? userId,
) async {
  if (userId == null) {
    return AccountTimeZones.defaultNationalFocusTimeZoneId;
  }
  final row = await (database.select(
    database.localProfileAccounts,
  )..where((entry) => entry.userId.equals(userId))).getSingleOrNull();
  return AccountTimeZones.checkpointTimeZoneId(row?.timeZoneId);
}

abstract interface class NationalFocusRepository {
  Stream<List<NationalFocusCard>> watchTreeCards();
  Stream<List<NationalFocusCard>> watchLibraryCards();
  Stream<List<NationalFocusCard>> watchDeletedCards();
  Future<List<NationalFocusCard>> getTreeCards();
  Future<List<NationalFocusCard>> getLibraryCards();
  Future<List<NationalFocusCard>> getDeletedCards();
  Future<NationalFocusCard> getCard(String cardId);
  Future<NationalFocusCard> createCard(NationalFocusCardDraft draft);
  Future<void> updateCard({
    required String cardId,
    required NationalFocusCardDraft draft,
  });
  Future<void> renameCard({required String cardId, required String name});
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
  Future<void> lightCard(
    String cardId, {
    DateTime? expectedConfirmationCheckpoint,
  });
  Future<void> extinguishCard({
    required String cardId,
    String? failureReason,
    DateTime? expectedConfirmationCheckpoint,
  });
  Future<int> confirmToday({DateTime? expectedConfirmationCheckpoint});
  Future<void> settleDueCheckpoints();
  Stream<List<NationalFocusFailure>> watchFailures();
  Future<List<NationalFocusFailure>> getFailures({String? cardId});
  Future<void> updateFailureExplanation({
    required String batchId,
    required String? explanation,
  });

  /// 把一组失败记录标为已回顾；重复标记是幂等的，不产生额外副作用。
  Future<void> markFailureReviewed({required String batchId});
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

class LocalNationalFocusRepository implements NationalFocusRepository {
  LocalNationalFocusRepository({
    required this.database,
    required this.userId,
    this.remote = const UnavailableNationalFocusRemoteDataSource(),
    this.cloudSyncEnabled = true,
    UserLifecycleAccess? lifecycleAccess,
    DateTime Function()? now,
  }) : lifecycleAccess =
           lifecycleAccess ?? const AlwaysActiveUserLifecycleAccess(),
       _now = now ?? DateTime.now {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId', '用户标识不能为空。');
    }
  }

  final PactaDatabase database;
  final String userId;
  final NationalFocusRemoteDataSource remote;
  final bool cloudSyncEnabled;
  final UserLifecycleAccess lifecycleAccess;
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
    await lifecycleAccess.requireActive();
    final timestamp = _nextTimestamp();
    final id = _uuid.v4();
    final name = _requiredText(draft.name, '名称');
    final triggerCondition = draft.triggerCondition.trim();
    final action = _requiredText(draft.action, '国策规则');
    final scope = _optionalText(draft.scope);
    final exceptionNotes = _optionalText(draft.exceptionNotes);
    final iconKey = _optionalText(draft.iconKey);
    final levels = _normalizeStrengtheningLevels(draft.strengtheningLevels);
    final activeLevel = _validateActiveStrengtheningLevel(
      draft.activeStrengtheningLevel,
      levels,
    );
    final card = NationalFocusCard(
      id: id,
      name: name,
      triggerCondition: triggerCondition,
      action: action,
      scope: scope,
      exceptionNotes: exceptionNotes,
      iconKey: iconKey,
      isInTree: false,
      state: NationalFocusCardState.extinguished,
      createdAt: timestamp,
      updatedAt: timestamp,
      strengtheningLevels: levels,
      activeStrengtheningLevel: activeLevel,
    );
    await database.transaction(() async {
      await database
          .into(database.localNationalFocusCards)
          .insert(
            LocalNationalFocusCardsCompanion.insert(
              userId: userId,
              id: card.id,
              name: card.name,
              triggerCondition: card.triggerCondition,
              action: card.action,
              scope: Value(card.scope),
              exceptionNotes: Value(card.exceptionNotes),
              iconKey: Value(card.iconKey),
              isInTree: const Value(false),
              parentId: const Value(null),
              state: Value(card.state.storageValue),
              activeStrengtheningLevel: Value(card.activeStrengtheningLevel),
              createdAt: timestamp,
              updatedAt: timestamp,
            ),
          );
      if (levels.isNotEmpty) {
        await _writeStrengtheningLevels(
          cardId: card.id,
          levels: levels,
          timestamp: timestamp,
        );
      }
      await _recordSyncSnapshot(operation: 'create_card');
    });
    return card;
  }

  @override
  Future<void> updateCard({
    required String cardId,
    required NationalFocusCardDraft draft,
  }) async {
    await settleDueCheckpoints();
    await lifecycleAccess.requireActive();
    final normalized = NationalFocusCardDraft(
      name: _requiredText(draft.name, '名称'),
      triggerCondition: draft.triggerCondition.trim(),
      action: _requiredText(draft.action, '国策规则'),
      scope: _optionalText(draft.scope),
      exceptionNotes: _optionalText(draft.exceptionNotes),
      iconKey: _optionalText(draft.iconKey),
      strengtheningLevels: draft.strengtheningLevels,
      activeStrengtheningLevel: draft.activeStrengtheningLevel,
      updateStrengthening: draft.updateStrengthening,
    );
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      if (card.deletedAt != null) {
        throw StateError('已删除的国策卡需要先恢复到卡片库。');
      }
      // 编辑页把名称、图标、规则、例外与强化档位一起提交：这里先校验整份
      // 草稿，再在同一次事务里落盘，任何一项非法都不会留下半张卡。
      final updatesStrengthening =
          normalized.updateStrengthening ||
          normalized.strengtheningLevels != null;
      final levels = updatesStrengthening
          ? _normalizeStrengtheningLevels(normalized.strengtheningLevels)
          : const <NationalFocusStrengtheningLevel>[];
      final activeLevel = updatesStrengthening
          ? _validateActiveStrengtheningLevel(
              normalized.activeStrengtheningLevel,
              levels,
            )
          : card.activeStrengtheningLevel;
      final storedLevels = updatesStrengthening
          ? await (database.select(
                    database.localNationalFocusStrengtheningLevels,
                  )
                  ..where(
                    (level) =>
                        level.userId.equals(userId) &
                        level.cardId.equals(cardId),
                  )
                  ..orderBy([(level) => OrderingTerm.asc(level.levelNumber)]))
                .get()
          : const <LocalNationalFocusStrengtheningLevel>[];
      final levelsChanged =
          updatesStrengthening &&
          !_sameStrengtheningLevels(storedLevels, levels);
      final activeChanged =
          updatesStrengthening && card.activeStrengtheningLevel != activeLevel;
      final fieldsChanged =
          card.name != normalized.name ||
          card.triggerCondition != normalized.triggerCondition ||
          card.action != normalized.action ||
          card.scope != normalized.scope ||
          card.exceptionNotes != normalized.exceptionNotes ||
          card.iconKey != normalized.iconKey;
      if (!fieldsChanged && !levelsChanged && !activeChanged) return;

      final timestamp = _nextTimestamp(card.updatedAt);
      if (levelsChanged) {
        await _writeStrengtheningLevels(
          cardId: cardId,
          levels: levels,
          timestamp: timestamp,
          retainedCreatedAt: {
            for (final level in storedLevels)
              level.levelNumber: level.createdAt,
          },
        );
      }
      await _updateCard(
        card,
        LocalNationalFocusCardsCompanion(
          name: Value(normalized.name),
          triggerCondition: Value(normalized.triggerCondition),
          action: Value(normalized.action),
          scope: Value(normalized.scope),
          exceptionNotes: Value(normalized.exceptionNotes),
          iconKey: Value(normalized.iconKey),
          activeStrengtheningLevel: updatesStrengthening
              ? Value(activeLevel)
              : const Value.absent(),
          updatedAt: Value(timestamp),
        ),
      );
      await _recordSyncSnapshot(operation: 'edit_card');
    });
  }

  @override
  Future<void> renameCard({
    required String cardId,
    required String name,
  }) async {
    await settleDueCheckpoints();
    await lifecycleAccess.requireActive();
    final normalizedName = _requiredText(name, '名称');
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      if (card.deletedAt != null) {
        throw StateError('已删除的国策卡需要先恢复到卡片库。');
      }
      if (card.name == normalizedName) return;
      await _updateCard(
        card,
        LocalNationalFocusCardsCompanion(
          name: Value(normalizedName),
          updatedAt: Value(_nextTimestamp(card.updatedAt)),
        ),
      );
      await _recordSyncSnapshot(operation: 'rename_card');
    });
  }

  @override
  Future<NationalFocusStrengtheningLevel> saveStrengtheningLevel({
    required String cardId,
    int? levelNumber,
    required NationalFocusStrengtheningLevelDraft draft,
  }) async {
    await settleDueCheckpoints();
    await lifecycleAccess.requireActive();
    final triggerOverride = _optionalText(draft.triggerCondition);
    final actionOverride = _optionalText(draft.action);
    if (triggerOverride == null && actionOverride == null) {
      throw ArgumentError('至少填写一项强化要求；留空字段会沿用基础要求。');
    }

    final savedLevel = await database.transaction(() async {
      final card = await _findCardRow(cardId);
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
    await lifecycleAccess.requireActive();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
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

  /// 用草稿整体替换一张卡的强化档位。
  ///
  /// 只保留同编号档位的创建时间，规则与更新时间取本次保存的时间：编辑器
  /// 底部唯一「保存」按钮执行的就是这一次全量替换。
  Future<void> _writeStrengtheningLevels({
    required String cardId,
    required List<NationalFocusStrengtheningLevel> levels,
    required DateTime timestamp,
    Map<int, DateTime> retainedCreatedAt = const {},
  }) async {
    await (database.delete(database.localNationalFocusStrengtheningLevels)
          ..where(
            (level) =>
                level.userId.equals(userId) & level.cardId.equals(cardId),
          ))
        .go();
    for (final level in levels) {
      await database
          .into(database.localNationalFocusStrengtheningLevels)
          .insert(
            LocalNationalFocusStrengtheningLevelsCompanion.insert(
              userId: userId,
              cardId: cardId,
              levelNumber: level.levelNumber,
              triggerConditionOverride: Value(level.triggerCondition),
              actionOverride: Value(level.action),
              createdAt: retainedCreatedAt[level.levelNumber] ?? timestamp,
              updatedAt: timestamp,
            ),
          );
    }
  }

  /// 校验并归一化强化档位草稿：最多 5 级、编号从 1 连续递增、每级至少
  /// 一条非空规则。任何一项不满足都整体拒绝，不写半份草稿。
  List<NationalFocusStrengtheningLevel> _normalizeStrengtheningLevels(
    List<NationalFocusStrengtheningLevel>? levels,
  ) {
    if (levels == null || levels.isEmpty) return const [];
    if (levels.length > maxNationalFocusStrengtheningLevels) {
      throw ArgumentError(
        '一张国策卡最多建立 $maxNationalFocusStrengtheningLevels 个强化等级。',
      );
    }
    final sorted = [...levels]
      ..sort((left, right) => left.levelNumber.compareTo(right.levelNumber));
    final normalized = <NationalFocusStrengtheningLevel>[];
    for (var index = 0; index < sorted.length; index++) {
      final level = sorted[index];
      if (level.levelNumber != index + 1) {
        throw ArgumentError('强化等级必须从 1 开始连续编号。');
      }
      final trigger = _optionalText(level.triggerCondition);
      final action = _optionalText(level.action);
      if (trigger == null && action == null) {
        throw ArgumentError(
          '强化等级 ${level.levelNumber} 至少填写一项强化要求；留空字段会沿用基础要求。',
        );
      }
      normalized.add(
        NationalFocusStrengtheningLevel(
          levelNumber: level.levelNumber,
          triggerCondition: trigger,
          action: action,
        ),
      );
    }
    return normalized;
  }

  int? _validateActiveStrengtheningLevel(
    int? activeLevel,
    List<NationalFocusStrengtheningLevel> levels,
  ) {
    if (activeLevel == null) return null;
    if (!levels.any((level) => level.levelNumber == activeLevel)) {
      throw ArgumentError('当前选中的强化等级不存在。');
    }
    return activeLevel;
  }

  bool _sameStrengtheningLevels(
    List<LocalNationalFocusStrengtheningLevel> stored,
    List<NationalFocusStrengtheningLevel> draft,
  ) {
    if (stored.length != draft.length) return false;
    for (var index = 0; index < draft.length; index++) {
      final left = stored[index];
      final right = draft[index];
      if (left.levelNumber != right.levelNumber ||
          _optionalText(left.triggerConditionOverride) !=
              _optionalText(right.triggerCondition) ||
          _optionalText(left.actionOverride) != _optionalText(right.action)) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> placeCard({
    required String cardId,
    required String? parentId,
  }) async {
    await settleDueCheckpoints();
    await lifecycleAccess.requireActive();
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
      await _recordSyncSnapshot(operation: 'place_card');
    });
  }

  @override
  Future<void> moveCardToLibrary(String cardId) async {
    await settleDueCheckpoints();
    await lifecycleAccess.requireActive();
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
    await lifecycleAccess.requireActive();
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
    await lifecycleAccess.requireActive();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
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
  Future<void> lightCard(
    String cardId, {
    DateTime? expectedConfirmationCheckpoint,
  }) async {
    await settleDueCheckpoints();
    await lifecycleAccess.requireActive();
    final zoneId = await _accountCheckpointTimeZoneId();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      if (card.deletedAt != null) {
        throw StateError('已删除的国策卡需要先恢复到卡片库。');
      }
      if (!card.isInTree) {
        throw StateError('卡片需要先放入国策树才能点亮。');
      }
      if (expectedConfirmationCheckpoint != null) {
        // A batch confirmation captured its checkpoint window. Settlement above
        // may already have failed the node or started a new day, so the stale
        // window must never relight it.
        final windowEnd = nextNationalFocusCheckpoint(
          _trustedNow(),
          timeZoneId: zoneId,
        );
        if (!windowEnd.isAtSameMomentAs(expectedConfirmationCheckpoint)) {
          throw StateError('确认窗口已跨过检查点；请刷新后重试。');
        }
        if (card.state == NationalFocusCardState.extinguished.storageValue) {
          throw StateError('这个节点已按检查点结算，不能再按旧确认点亮。');
        }
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
    DateTime? expectedConfirmationCheckpoint,
  }) async {
    await settleDueCheckpoints();
    await lifecycleAccess.requireActive();
    final zoneId = await _accountCheckpointTimeZoneId();
    await database.transaction(() async {
      final card = await _findCardRow(cardId);
      if (card.deletedAt != null) {
        throw StateError('已删除的国策卡需要先恢复到卡片库。');
      }
      if (!card.isInTree) {
        throw StateError('卡片不在国策树中。');
      }
      if (expectedConfirmationCheckpoint != null) {
        final windowEnd = nextNationalFocusCheckpoint(
          _trustedNow(),
          timeZoneId: zoneId,
        );
        if (!windowEnd.isAtSameMomentAs(expectedConfirmationCheckpoint)) {
          throw StateError('熄灭窗口已跨过检查点；请刷新后重试。');
        }
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
      await _recordSyncSnapshot(operation: 'extinguish_card');
    });
  }

  @override
  Future<int> confirmToday({DateTime? expectedConfirmationCheckpoint}) async {
    await settleDueCheckpoints();
    await lifecycleAccess.requireActive();
    final zoneId = await _accountCheckpointTimeZoneId();
    final confirmedCardIds = <String>[];
    final confirmedCount = await database.transaction(() async {
      if (expectedConfirmationCheckpoint != null) {
        final windowEnd = nextNationalFocusCheckpoint(
          _trustedNow(),
          timeZoneId: zoneId,
        );
        if (!windowEnd.isAtSameMomentAs(expectedConfirmationCheckpoint)) {
          return 0;
        }
      }
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

      var count = 0;
      for (final card in pendingCards) {
        if (_hasExtinguishedAncestor(card, cardsById)) continue;
        // Cards with exception or precedent notes are confirmed one by one so
        // the batch action cannot bypass their user-authored judgment.
        if (card.exceptionNotes?.trim().isNotEmpty ?? false) continue;
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
          checkpointAt: nextNationalFocusCheckpoint(
            _trustedNow(),
            timeZoneId: zoneId,
          ),
          confirmedCardIds: confirmedCardIds,
        );
      }
      return count;
    });
    return confirmedCount;
  }

  @override
  Future<void> settleDueCheckpoints() async {
    await database.transaction(() async {
      await _settleCheckpointsThrough(_now().toUtc());
    });
  }

  Future<void> _settleCheckpointsThrough(DateTime now) async {
    // 账号时区决定换天：当地 04:00 就是一次检查点，设备时区只影响显示。
    final zoneId = await _accountCheckpointTimeZoneId();
    final progress = await (database.select(
      database.localNationalFocusMaintenance,
    )..where((row) => row.userId.equals(userId))).getSingleOrNull();
    if (progress == null) {
      await database
          .into(database.localNationalFocusMaintenance)
          .insert(
            LocalNationalFocusMaintenanceCompanion.insert(
              userId: userId,
              lastSettledCheckpointAt: nationalFocusCheckpointAtOrBefore(
                now,
                timeZoneId: zoneId,
              ),
            ),
          );
      await _recordSyncSnapshot(operation: 'initialize_checkpoints');
      return;
    }

    var lastSettled = progress.lastSettledCheckpointAt.toUtc();
    var checkpoint = nextNationalFocusCheckpoint(
      lastSettled,
      timeZoneId: zoneId,
      lastSettledCheckpointAt: lastSettled,
    );
    while (!checkpoint.isAfter(now)) {
      await _settleCheckpoint(checkpoint);
      lastSettled = checkpoint;
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
      // 每次都用新的已结算时刻作为锚点：时区改变时不会回拨进度，也不会在
      // 12 小时内重复结算。
      checkpoint = nextNationalFocusCheckpoint(
        lastSettled,
        timeZoneId: zoneId,
        lastSettledCheckpointAt: lastSettled,
      );
    }
  }

  DateTime _trustedNow() => _now().toUtc();

  /// 结算用的账号时区：账号资料里的 IANA 值，读不到就按北京时间。
  ///
  /// 账号时区随账号同步，不跟随设备；因此同一账号在任何手机上换天时刻一致。
  Future<String> _accountCheckpointTimeZoneId() =>
      readAccountCheckpointTimeZoneId(database, userId);

  /// 供界面读取同一份结算时区，避免界面显示的窗口与仓储实际结算的窗口分叉。
  Future<String> checkpointTimeZoneId() async => _accountCheckpointTimeZoneId();

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
        .where((card) => card.isInTree || card.maintenanceCycleStarted)
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
  Stream<List<NationalFocusFailure>> watchFailures() async* {
    await settleDueCheckpoints();
    final query = database.select(database.localNationalFocusFailures)
      ..where((failure) => failure.userId.equals(userId))
      ..orderBy([
        (failure) => OrderingTerm.desc(failure.checkpointAt),
        (failure) => OrderingTerm.asc(failure.cardId),
      ]);
    yield* query.watch().map(
      (rows) => rows.map(_failureFromRow).toList(growable: false),
    );
  }

  @override
  Future<void> markFailureReviewed({required String batchId}) async {
    await settleDueCheckpoints();
    await lifecycleAccess.requireActive();
    final reviewedAt = _nextTimestamp();
    await database.transaction(() async {
      final updated =
          await (database.update(database.localNationalFocusFailures)
                ..where((failure) => failure.userId.equals(userId))
                ..where((failure) => failure.batchId.equals(batchId))
                ..where((failure) => failure.reviewedAt.isNull()))
              .write(
                LocalNationalFocusFailuresCompanion(
                  reviewedAt: Value(reviewedAt),
                ),
              );
      if (updated == 0) {
        // 幂等：整组已经回顾过就什么都不写，也不新增同步来源。
        final existing =
            await (database.select(database.localNationalFocusFailures)
                  ..where((failure) => failure.userId.equals(userId))
                  ..where((failure) => failure.batchId.equals(batchId))
                  ..limit(1))
                .getSingleOrNull();
        if (existing == null) {
          throw StateError('找不到这组国策失败记录。');
        }
        return;
      }
      await _recordSyncSnapshot(operation: 'mark_failure_reviewed');
    });
  }

  @override
  Future<void> updateFailureExplanation({
    required String batchId,
    required String? explanation,
  }) async {
    await settleDueCheckpoints();
    await lifecycleAccess.requireActive();
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

  Future<void> _recordSyncSnapshot({
    required String operation,
    DateTime? checkpointAt,
    Iterable<String> confirmedCardIds = const [],
    Iterable<String> missedConfirmationCardIds = const [],
    Set<String> deletedCardIds = const {},
    List<String>? parentSourceIds,
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
    final payload = {
      ...snapshot,
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
      cards.add({
        'id': card.id,
        'name': card.name,
        'iconKey': card.iconKey,
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
            'reviewedAt': failure.reviewedAt?.toUtc().toIso8601String(),
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
    return NationalFocusCard(
      id: row.id,
      name: row.name,
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
      iconKey: row.iconKey,
    );
  }

  Future<Map<String, Object?>> _snapshotJson(
    LocalNationalFocusCard row, {
    String? failureSourceCardId,
  }) async {
    // 快照只冻结卡片当时的结构与规则：强化档位的当时值直接取卡上的
    // active_strengthening_level，不再依赖已删除的版本记录表。
    final activeLevel = row.activeStrengtheningLevel;
    LocalNationalFocusStrengtheningLevel? strengths;
    if (activeLevel != null) {
      strengths =
          await (database.select(database.localNationalFocusStrengtheningLevels)
                ..where(
                  (level) =>
                      level.userId.equals(userId) &
                      level.cardId.equals(row.id) &
                      level.levelNumber.equals(activeLevel),
                ))
              .getSingleOrNull();
    }
    return {
      'id': row.id,
      'name': row.name,
      'iconKey': row.iconKey,
      'triggerCondition': row.triggerCondition,
      'action': row.action,
      'effectiveTriggerCondition':
          strengths?.triggerConditionOverride ?? row.triggerCondition,
      'effectiveAction': strengths?.actionOverride ?? row.action,
      'activeStrengtheningLevel': activeLevel,
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
            name: item['name'] as String,
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
            iconKey: item['iconKey'] as String?,
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
      reviewedAt: row.reviewedAt,
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
  Future<void> updateCard({
    required String cardId,
    required NationalFocusCardDraft draft,
  }) => _unavailable();

  @override
  Future<void> renameCard({required String cardId, required String name}) =>
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
  Future<void> lightCard(
    String cardId, {
    DateTime? expectedConfirmationCheckpoint,
  }) => _unavailable();

  @override
  Future<void> extinguishCard({
    required String cardId,
    String? failureReason,
    DateTime? expectedConfirmationCheckpoint,
  }) => _unavailable();

  @override
  Future<int> confirmToday({DateTime? expectedConfirmationCheckpoint}) =>
      _unavailable();

  @override
  Future<void> settleDueCheckpoints() async {}

  @override
  Stream<List<NationalFocusFailure>> watchFailures() => Stream.value(const []);

  @override
  Future<List<NationalFocusFailure>> getFailures({String? cardId}) async =>
      const [];

  @override
  Future<void> updateFailureExplanation({
    required String batchId,
    required String? explanation,
  }) => _unavailable();

  @override
  Future<void> markFailureReviewed({required String batchId}) => _unavailable();

  @override
  Future<void> dispose() async {}

  Future<T> _unavailable<T>() async {
    throw StateError('当前用户的国策卡片存储尚未配置。');
  }
}

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
