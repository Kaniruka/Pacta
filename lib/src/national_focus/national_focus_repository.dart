import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../tasks/task_database.dart';
import 'national_focus_models.dart';

abstract interface class NationalFocusRepository {
  Stream<List<NationalFocusCard>> watchTreeCards();
  Stream<List<NationalFocusCard>> watchLibraryCards();
  Future<List<NationalFocusCard>> getTreeCards();
  Future<List<NationalFocusCard>> getLibraryCards();
  Future<NationalFocusCard> getCard(String cardId);
  Future<NationalFocusCard> createCard(NationalFocusCardDraft draft);
  Future<void> placeCard({required String cardId, required String? parentId});
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
      (database.select(database.localNationalFocusCards)
            ..where((card) => card.userId.equals(userId))
            ..where((card) => card.isInTree.equals(true))
            ..orderBy([
              (card) => OrderingTerm.asc(card.createdAt),
              (card) => OrderingTerm.asc(card.id),
            ]))
          .watch()
          .map(_cardsFromRows);

  @override
  Stream<List<NationalFocusCard>> watchLibraryCards() =>
      (database.select(database.localNationalFocusCards)
            ..where((card) => card.userId.equals(userId))
            ..where((card) => card.isInTree.equals(false))
            ..orderBy([
              (card) => OrderingTerm.asc(card.createdAt),
              (card) => OrderingTerm.asc(card.id),
            ]))
          .watch()
          .map(_cardsFromRows);

  @override
  Future<List<NationalFocusCard>> getTreeCards() => _getCards(inTree: true);

  @override
  Future<List<NationalFocusCard>> getLibraryCards() => _getCards(inTree: false);

  @override
  Future<NationalFocusCard> getCard(String cardId) async =>
      _cardFromRow(await _findCardRow(cardId));

  @override
  Future<NationalFocusCard> createCard(NationalFocusCardDraft draft) async {
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
  Future<void> dispose() async {}

  Future<List<NationalFocusCard>> _getCards({required bool inTree}) async {
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
      );

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
  Future<void> dispose() async {}

  Future<T> _unavailable<T>() async {
    throw StateError('当前用户的国策卡片存储尚未配置。');
  }
}
