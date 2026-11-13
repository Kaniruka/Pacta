import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/national_focus/national_focus_tree_page.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  for (final inTree in [false, true]) {
    testWidgets('${inTree ? "树节点" : "卡片库"}详情编辑三字段并以国策规则保存', (tester) async {
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
      // Current card information uses the three-field vocabulary and no
      // longer surfaces the legacy trigger condition or scope.
      expect(find.text('触发条件'), findsNothing);
      expect(find.text('适用范围'), findsNothing);
      expect(find.text('行动'), findsNothing);
      expect(find.text('国策规则'), findsOneWidget);
      expect(find.text('读十页'), findsOneWidget);
      await tester.tap(find.text('编辑卡片'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), '每日阅读');
      await tester.enterText(fields.at(1), '读二十页');
      await tester.tap(find.text('例外与判例'));
      await tester.pumpAndSettle();
      final exceptionField = find.byType(TextFormField).at(2);
      await tester.ensureVisible(exceptionField);
      await tester.enterText(exceptionField, '出差除外');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final updated = await repository.getCard(card.id);
      expect(updated.name, '每日阅读');
      expect(updated.triggerCondition, isEmpty);
      expect(updated.action, '读二十页');
      expect(updated.scope, isNull);
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
      expect(updated.requirementVersions.last.scope, isNull);
      expect(updated.requirementVersions.last.exceptionNotes, '出差除外');
      expect(find.text('每日阅读'), findsOneWidget);
      expect(find.text('例外与判例'), findsOneWidget);
      await tester.tap(find.text('例外与判例'));
      await tester.pumpAndSettle();
      expect(find.text('出差除外'), findsOneWidget);
      expect(find.text('触发条件'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
  testWidgets('新建国策卡只填写名称、国策规则与例外', (tester) async {
    final database = PactaDatabase(NativeDatabase.memory());
    final repository = LocalNationalFocusRepository(
      database: database,
      userId: 'card-create-fixture',
      cloudSyncEnabled: false,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await repository.dispose();
      await database.close();
    });
    await tester.pumpWidget(
      MaterialApp(home: NationalFocusCardLibraryPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建国策卡'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '阅读');
    await tester.enterText(fields.at(1), '读十页');
    await tester.tap(find.text('例外与判例'));
    await tester.pumpAndSettle();
    final exceptionField = find.byType(TextFormField).at(2);
    await tester.ensureVisible(exceptionField);
    await tester.enterText(exceptionField, '出差除外');
    await tester.tap(find.text('保存到卡片库'));
    await tester.pumpAndSettle();
    final created = (await repository.getLibraryCards()).single;
    expect(created.triggerCondition, isEmpty);
    expect(created.scope, isNull);
    expect(created.action, '读十页');
    expect(created.exceptionNotes, '出差除外');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
