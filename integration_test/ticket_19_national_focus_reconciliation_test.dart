import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_reconciliation_page.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('T19 真机核对并发国策分支并同步裁决结果', (tester) async {
    final fixture = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'pacta-ticket-19-device-',
      );
      final firstDatabase = PactaDatabase(
        NativeDatabase(File('${directory.path}/first.sqlite')),
      );
      final secondDatabase = PactaDatabase(
        NativeDatabase(File('${directory.path}/second.sqlite')),
      );
      final remote = InMemoryNationalFocusRemoteDataSource();
      var now = DateTime.utc(2026, 9, 20, 19, 59);
      final firstDevice = LocalNationalFocusRepository(
        database: firstDatabase,
        userId: 'ticket-19-android-user',
        remote: remote,
        now: () => now,
      );
      final secondDevice = LocalNationalFocusRepository(
        database: secondDatabase,
        userId: 'ticket-19-android-user',
        remote: remote,
        now: () => now,
      );

      final parent = await firstDevice.createCard(
        const NationalFocusCardDraft(triggerCondition: '晨间计划', action: '安排今天'),
      );
      final child = await firstDevice.createCard(
        const NationalFocusCardDraft(triggerCondition: '阅读计划', action: '读一章'),
      );
      await firstDevice.placeCard(cardId: parent.id, parentId: null);
      await firstDevice.placeCard(cardId: child.id, parentId: null);
      await firstDevice.lightCard(parent.id);
      await firstDevice.lightCard(child.id);
      now = DateTime.utc(2026, 9, 20, 20);
      await firstDevice.settleDueCheckpoints();
      await firstDevice.sync();
      await secondDevice.sync();

      now = DateTime.utc(2026, 9, 21, 19);
      await firstDevice.placeCard(cardId: child.id, parentId: parent.id);
      await secondDevice.placeCard(cardId: parent.id, parentId: child.id);
      await firstDevice.sync();
      await secondDevice.sync();
      final review = (await secondDevice.getNationalFocusReviewState())
          .reconciliationCases
          .single;
      final selectedOption = review.options.singleWhere(
        (option) => option.effects.any(
          (effect) =>
              effect.cardId == child.id && effect.newParentId == parent.id,
        ),
      );
      return (
        directory: directory,
        firstDatabase: firstDatabase,
        secondDatabase: secondDatabase,
        firstDevice: firstDevice,
        secondDevice: secondDevice,
        parentId: parent.id,
        childId: child.id,
        caseId: review.id,
        selectedSourceId: selectedOption.sourceId,
      );
    });

    expect(fixture, isNotNull);
    final data = fixture!;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: NationalFocusReconciliationPage(repository: data.secondDevice),
        ),
      );
      await _pumpDeviceUi(tester);
      expect(find.text('涉及节点：晨间计划、阅读计划'), findsOneWidget);
      expect(find.textContaining('成功日'), findsWidgets);
      expect(find.text('查看完整来源操作'), findsNWidgets(2));

      final options = find.byType(RadioListTile<String>);
      final selectedIndex =
          (await data.secondDevice.getNationalFocusReviewState())
              .reconciliationCases
              .single
              .options
              .indexWhere((option) => option.sourceId == data.selectedSourceId);
      await tester.tap(options.at(selectedIndex));
      await _pumpDeviceUi(tester);
      final adoptButton = find.text('采用此完整分支');
      await tester.ensureVisible(adoptButton);
      await tester.pump();
      await tester.tap(adoptButton);
      await _pumpDeviceUi(tester);

      expect(find.text('已裁决 2 个节点的分支'), findsOneWidget);
      final resolvedTree = await tester.runAsync(
        () => data.secondDevice.getTreeCards(),
      );
      expect(
        resolvedTree!.singleWhere((card) => card.id == data.childId).parentId,
        data.parentId,
      );
      expect(resolvedTree.every((card) => !card.hasPendingReview), isTrue);

      await tester.runAsync(() async {
        await data.firstDevice.sync();
        final firstDeviceTree = await data.firstDevice.getTreeCards();
        expect(
          firstDeviceTree
              .singleWhere((card) => card.id == data.childId)
              .parentId,
          data.parentId,
        );
        expect(
          (await data.firstDevice.getNationalFocusReviewState())
              .reconciliationHistory,
          hasLength(1),
        );
      });
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await data.firstDevice.dispose();
        await data.secondDevice.dispose();
        await data.firstDatabase.close();
        await data.secondDatabase.close();
        await data.directory.delete(recursive: true);
      });
    }
  });
}

Future<void> _pumpDeviceUi(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await tester.pump(const Duration(seconds: 1));
}
