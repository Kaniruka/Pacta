import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';

const nationalFocusReferenceFixtureAsset =
    'assets/fixtures/national_focus_tree/reference_v13_8_18.json';
const nationalFocusReferenceDemoAction = '结构演示节点，用于还原参考图片层级；非实际行为规则';

/// Screenshot transcription plus an importer for an isolated local repository.
///
/// Ellipse labels are materialized as explicitly marked demo cards because the
/// current domain model has no group entity. Rectangle cards retain their
/// screenshot title as the independent card name, with the source rule text
/// retained as Trigger Condition and Action. This helper is
/// for fixtures and demos only; callers should use a private in-memory
/// [PactaDatabase] rather than an authenticated account.
class NationalFocusReferenceFixture {
  NationalFocusReferenceFixture._(this.data);

  final Map<String, dynamic> data;

  Map<String, dynamic> get root => data['root'] as Map<String, dynamic>;

  static Future<NationalFocusReferenceFixture> load({String? path}) async {
    final source = path == null
        ? await rootBundle.loadString(nationalFocusReferenceFixtureAsset)
        : await File(path).readAsString();
    return NationalFocusReferenceFixture._(
      jsonDecode(source) as Map<String, dynamic>,
    );
  }

  int get ruleCount {
    final generalRules = root['generalRules'] as List<dynamic>;
    var count = generalRules.length;
    void visitBranch(Map<String, dynamic> branch) {
      final cards = branch['cards'] as List<dynamic>?;
      count += cards?.length ?? 0;
      for (final group in branch['groups'] as List<dynamic>? ?? const []) {
        visitBranch(group as Map<String, dynamic>);
      }
      for (final child in branch['branches'] as List<dynamic>? ?? const []) {
        visitBranch(child as Map<String, dynamic>);
      }
    }

    visitBranch(root['central'] as Map<String, dynamic>);
    return count;
  }

  int get demoNodeCount {
    var count = 1; // The National Focus Tree title ellipse.
    void visitBranch(Map<String, dynamic> branch) {
      if (branch['title'] != null) count++;
      for (final group in branch['groups'] as List<dynamic>? ?? const []) {
        visitBranch(group as Map<String, dynamic>);
      }
      for (final child in branch['branches'] as List<dynamic>? ?? const []) {
        visitBranch(child as Map<String, dynamic>);
      }
    }

    visitBranch(root['central'] as Map<String, dynamic>);
    return count;
  }

  Future<NationalFocusReferenceSeed> seed(
    LocalNationalFocusRepository repository,
  ) async {
    final ids = <String, String>{};

    Future<String> createDemoNode({
      required String sourceId,
      required String title,
      required String? parentId,
    }) async {
      final card = await repository.createCard(
        NationalFocusCardDraft(
          name: title,
          triggerCondition: title,
          action: nationalFocusReferenceDemoAction,
          scope: '仅演示',
        ),
      );
      await repository.placeCard(cardId: card.id, parentId: parentId);
      ids[sourceId] = card.id;
      return card.id;
    }

    Future<void> addRule(
      Map<String, dynamic> source, {
      required String parentId,
      required String scope,
    }) async {
      final card = await repository.createCard(
        NationalFocusCardDraft(
          name: source['title'] as String,
          triggerCondition: source['title'] as String,
          action: source['action'] as String,
          scope: source['scope'] as String? ?? scope,
        ),
      );
      await repository.placeCard(cardId: card.id, parentId: parentId);
      ids[source['id'] as String] = card.id;
    }

    Future<void> addBranch(
      Map<String, dynamic> branch, {
      required String parentId,
      required String scopePrefix,
    }) async {
      final title = branch['title'] as String;
      final branchId = await createDemoNode(
        sourceId: branch['id'] as String,
        title: title,
        parentId: parentId,
      );
      final scope = scopePrefix.isEmpty ? title : '$scopePrefix › $title';
      for (final card in branch['cards'] as List<dynamic>? ?? const []) {
        await addRule(
          card as Map<String, dynamic>,
          parentId: branchId,
          scope: scope,
        );
      }
      for (final group in branch['groups'] as List<dynamic>? ?? const []) {
        await addBranch(
          group as Map<String, dynamic>,
          parentId: branchId,
          scopePrefix: scope,
        );
      }
      for (final child in branch['branches'] as List<dynamic>? ?? const []) {
        await addBranch(
          child as Map<String, dynamic>,
          parentId: branchId,
          scopePrefix: scope,
        );
      }
    }

    final rootTitle = root['title'] as String;
    final rootCardId = await createDemoNode(
      sourceId: root['id'] as String,
      title: rootTitle,
      parentId: null,
    );
    for (final rule in root['generalRules'] as List<dynamic>) {
      await addRule(
        rule as Map<String, dynamic>,
        parentId: rootCardId,
        scope: '通用规则',
      );
    }

    await addBranch(
      root['central'] as Map<String, dynamic>,
      parentId: rootCardId,
      scopePrefix: '',
    );
    return NationalFocusReferenceSeed(
      cardIdsBySourceId: Map.unmodifiable(ids),
      ruleCount: ruleCount,
      demoNodeCount: demoNodeCount,
    );
  }
}

class NationalFocusReferenceSeed {
  const NationalFocusReferenceSeed({
    required this.cardIdsBySourceId,
    required this.ruleCount,
    required this.demoNodeCount,
  });

  final Map<String, String> cardIdsBySourceId;
  final int ruleCount;
  final int demoNodeCount;

  int get totalNodeCount => ruleCount + demoNodeCount;

  String cardId(String sourceId) => cardIdsBySourceId[sourceId]!;
}
