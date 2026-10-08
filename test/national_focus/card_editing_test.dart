import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  for (final inTree in [false, true]) {
    testWidgets('${inTree ? "树节点" : "卡片库"}详情可编辑完整卡片并清空触发条件', (tester) async {
      final database = PactaDatabase(NativeDatabase.memory());
      final repository = LocalNationalFocusRepository(
        database: database,
        userId: 'card-edit-fixture',
        cloudSyncEnabled: false,
        now: () => DateTime.utc(2026, 10, 8, 8),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await repository.dispose();
        await database.close();
      });
      final card = await repository.createCard(
        const NationalFocusCardDraft(
          name: '阅读',
          triggerCondition: '饭后',
          action: '读十页',
        ),
      );
      if (inTree) {
        await repository.placeCard(cardId: card.id, parentId: null);
        await repository.lightCard(card.id);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: inTree
              ? Scaffold(body: NationalFocusTreePage(repository: repository))
              : NationalFocusCardLibraryPage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      if (inTree) {
        await tester.tap(
          find.byKey(ValueKey('national-focus-node-${card.id}')),
        );
      } else {
        await tester.tap(find.byTooltip('卡片操作'));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('卡片操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑卡片'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(5));
      await tester.enterText(fields.at(0), '每日阅读');
      await tester.enterText(fields.at(1), '');
      await tester.enterText(fields.at(2), '读二十页');
      await tester.ensureVisible(fields.at(3));
      await tester.enterText(fields.at(3), '工作日');
      await tester.ensureVisible(fields.at(4));
      await tester.enterText(fields.at(4), '出差除外');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final updated = await repository.getCard(card.id);
      expect(updated.name, '每日阅读');
      expect(updated.triggerCondition, isEmpty);
      expect(updated.action, '读二十页');
      expect(updated.scope, '工作日');
      expect(updated.exceptionNotes, '出差除外');
      expect(updated.isInTree, inTree);
      expect(
        updated.state,
        inTree
            ? NationalFocusCardState.lit
            : NationalFocusCardState.extinguished,
      );
      expect(updated.requirementVersions.first.effectiveAction, '读十页');
      expect(updated.requirementVersions.last.effectiveAction, '读二十页');
      expect(find.text('未设置'), findsOneWidget);
      expect(find.text('每日阅读'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
  testWidgets('新建国策卡允许不填写触发条件', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalNationalFocusRepository(
      database: database,
      userId: 'card-create-fixture',
      cloudSyncEnabled: false,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.dispose();
      await database.close();
    });
    await tester.pumpWidget(
      MaterialApp(home: NationalFocusCardLibraryPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建国策卡'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '阅读');
    await tester.enterText(find.byType(TextFormField).at(2), '读十页');
    await tester.tap(find.text('保存到卡片库'));
    await tester.pumpAndSettle();
    expect(
      (await repository.getLibraryCards()).single.triggerCondition,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
