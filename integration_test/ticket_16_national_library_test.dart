import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pacta/main.dart';
import 'package:pacta/src/national_focus/national_focus_models.dart';
import 'package:pacta/src/national_focus/national_focus_repository.dart';
import 'package:pacta/src/tasks/task_database.dart' show PactaDatabase;

import '../test/support/fake_auth_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T16 画布调整分支、拆散入库、回看快照、恢复并跨重启保留', (tester) async {
    const userId = 'ticket-16-user';
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'pacta-ticket-16-',
    );
    final databaseFile = File('${temporaryDirectory.path}/pacta.sqlite');
    var database = PactaDatabase(NativeDatabase(databaseFile));
    var now = DateTime.utc(2026, 9, 25, 19, 59);
    final repositories = <LocalNationalFocusRepository>[];
    LocalNationalFocusRepository createRepository(String requestedUserId) {
      final repository = LocalNationalFocusRepository(
        database: database,
        userId: requestedUserId,
        now: () => now,
      );
      repositories.add(repository);
      return repository;
    }

    final auth = FakeAuthRepository()..signedInUser = userId;
    final repository = createRepository(userId);
    final mainRoot = await repository.createCard(
      const NationalFocusCardDraft(triggerCondition: '主父卡', action: '维持主要行动'),
    );
    final movingRoot = await repository.createCard(
      const NationalFocusCardDraft(triggerCondition: '分支父卡', action: '整理分支'),
    );
    final child = await repository.createCard(
      const NationalFocusCardDraft(triggerCondition: '子卡', action: '执行子行动'),
    );
    final grandchild = await repository.createCard(
      const NationalFocusCardDraft(triggerCondition: '孙卡', action: '执行后代行动'),
    );
    await repository.placeCard(cardId: mainRoot.id, parentId: null);
    await repository.placeCard(cardId: movingRoot.id, parentId: null);
    await repository.placeCard(cardId: child.id, parentId: movingRoot.id);
    await repository.placeCard(cardId: grandchild.id, parentId: child.id);
    for (final card in [mainRoot, movingRoot, child, grandchild]) {
      await repository.lightCard(card.id);
    }
    now = DateTime.utc(2026, 9, 25, 20);
    await repository.settleDueCheckpoints();
    await repository.confirmToday();
    now = DateTime.utc(2026, 9, 26, 20);
    await repository.settleDueCheckpoints();
    if (Platform.isWindows) {
      await repository.placeCard(cardId: child.id, parentId: mainRoot.id);
    }

    try {
      await tester.pumpWidget(
        PactaApp(
          authRepository: auth,
          nationalFocusRepositoryFactory: createRepository,
        ),
      );
      await tester.pumpAndSettle();
      final treeDestination = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('国策树'),
      );
      await tester.tap(treeDestination);
      await tester.pumpAndSettle();
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      Finder nodeCard(String title) => find
          .ancestor(of: find.text(title).first, matching: find.byType(Card))
          .first;

      if (!Platform.isWindows) {
        final relocateChild = find.descendant(
          of: nodeCard('子卡'),
          matching: find.text('调整树中位置'),
        );
        await _reveal(tester, relocateChild);
        await tester.tap(relocateChild);
        await tester.pumpAndSettle();
        await _scrollTreeToTop(tester);
        expect(find.text('主父卡'), findsOneWidget);
        await tester.tap(nodeCard('主父卡'));
        await tester.pumpAndSettle();
      }
      expect((await repository.getCard(child.id)).parentId, mainRoot.id);
      expect((await repository.getCard(grandchild.id)).parentId, child.id);

      if (Platform.isWindows) {
        await _reveal(tester, find.text('主父卡', skipOffstage: false));
      }
      final moveBranch = find.descendant(
        of: nodeCard('主父卡'),
        matching: find.text('移入卡片库'),
      );
      await _reveal(tester, moveBranch);
      await tester.tap(moveBranch);
      await tester.pumpAndSettle();
      expect(find.textContaining('2 张后代卡片'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '移入卡片库'));
      await tester.pumpAndSettle();
      expect(
        (await repository.getLibraryCards()).map((card) => card.id).toSet(),
        {mainRoot.id, child.id, grandchild.id},
      );
      expect((await repository.getTreeCards()).map((card) => card.id), [
        movingRoot.id,
      ]);
      expect((await repository.getCard(grandchild.id)).parentId, isNull);

      await _reveal(tester, find.text('一键确认今日'));
      if (Platform.isWindows) {
        final confirmationButton = tester.widget<FilledButton>(
          find
              .ancestor(
                of: find.text('一键确认今日'),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        expect(confirmationButton.onPressed, isNotNull);
        expect(await repository.confirmToday(), 1);
      } else {
        await tester.tap(find.text('一键确认今日'));
      }
      await tester.pumpAndSettle();
      expect(
        (await repository.getCard(movingRoot.id)).state,
        NationalFocusCardState.lit,
      );
      expect(
        (await repository.getCard(mainRoot.id)).state,
        NationalFocusCardState.pendingTodayConfirmation,
      );

      await tester.tap(find.widgetWithText(FilledButton, '卡片库'));
      await tester.pumpAndSettle();
      if (Platform.isWindows) {
        await repository.placeCard(cardId: child.id, parentId: movingRoot.id);
        await repository.lightCard(child.id);
        Navigator.of(tester.element(find.text('国策卡片库'))).pop();
      } else {
        final childCard = nodeCard('子卡');
        final placeChild = find.descendant(
          of: childCard,
          matching: find.text('放入树画布'),
        );
        await tester.tap(placeChild);
        await tester.pumpAndSettle();
        await _scrollTreeToTop(tester);
        expect(find.text('分支父卡'), findsOneWidget);
        await tester.tap(nodeCard('分支父卡'));
        await tester.pumpAndSettle();
        await _reveal(tester, find.text('确认今日继续有效'));
        await tester.tap(find.text('确认今日继续有效'));
      }
      await tester.pumpAndSettle();
      final restoredChild = await repository.getCard(child.id);
      expect(restoredChild.parentId, movingRoot.id);
      expect(restoredChild.state, NationalFocusCardState.lit);
      expect(restoredChild.successfulDays, 2);
      expect(restoredChild.currentConsecutiveDays, 2);
      expect((await repository.getCard(grandchild.id)).parentId, isNull);

      now = DateTime.utc(2026, 9, 27, 20);
      await repository.settleDueCheckpoints();
      final failures = await repository.getFailures();
      expect(failures.map((failure) => failure.cardId).toSet(), {
        mainRoot.id,
        grandchild.id,
      });
      final grandchildFailure = failures.singleWhere(
        (failure) => failure.cardId == grandchild.id,
      );
      final historicalGrandchild = grandchildFailure.treeSnapshot.singleWhere(
        (card) => card.id == grandchild.id,
      );
      expect(historicalGrandchild.isInTree, isFalse);
      expect(historicalGrandchild.parentId, isNull);

      await tester.tap(find.text('查看失败记录'));
      await tester.pumpAndSettle();
      expect(find.text('国策失败记录'), findsOneWidget);
      await tester.tap(find.textContaining('· 2 个节点'));
      await tester.pumpAndSettle();
      expect(find.textContaining('卡片库内 · 孙卡'), findsOneWidget);
      Navigator.of(tester.element(find.text('国策失败记录'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, '卡片库'));
      await tester.pumpAndSettle();
      final deleteGrandchild = find.descendant(
        of: nodeCard('孙卡'),
        matching: find.text('删除'),
      );
      await _reveal(tester, deleteGrandchild);
      await tester.tap(deleteGrandchild);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect((await repository.getDeletedCards()).single.id, grandchild.id);
      expect(
        (await repository.getFailures())
            .singleWhere((failure) => failure.cardId == grandchild.id)
            .treeSnapshot
            .singleWhere((card) => card.id == grandchild.id)
            .triggerCondition,
        historicalGrandchild.triggerCondition,
      );

      await tester.tap(find.text('已删除'));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('恢复到卡片库'));
      await tester.tap(find.text('恢复到卡片库'));
      await tester.pumpAndSettle();
      final restoredGrandchild = await repository.getCard(grandchild.id);
      expect(restoredGrandchild.isDeleted, isFalse);
      expect(restoredGrandchild.isInTree, isFalse);
      expect(restoredGrandchild.parentId, isNull);
      expect(
        restoredGrandchild.successfulDays,
        historicalGrandchild.successfulDays,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      for (final openRepository in repositories) {
        await openRepository.dispose();
      }
      await database.close();
      database = PactaDatabase(NativeDatabase(databaseFile));
      final restartedRepository = createRepository(userId);
      final restartedGrandchild = await restartedRepository.getCard(
        grandchild.id,
      );
      expect(restartedGrandchild.isDeleted, isFalse);
      expect(restartedGrandchild.isInTree, isFalse);
      expect(restartedGrandchild.parentId, isNull);
      expect(await restartedRepository.getFailures(), hasLength(2));
      expect(
        (await restartedRepository.getFailures())
            .singleWhere((failure) => failure.cardId == grandchild.id)
            .treeSnapshot
            .singleWhere((card) => card.id == grandchild.id)
            .triggerCondition,
        historicalGrandchild.triggerCondition,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final openRepository in repositories) {
        await openRepository.dispose();
      }
      await database.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _scrollTreeToTop(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView).last, const Offset(0, 800));
  await tester.pumpAndSettle();
}
